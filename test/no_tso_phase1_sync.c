#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>

#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ORDERING_ROUNDS 1000000L
#define REGISTRATION_ROUNDS 20000L
#define TIMEOUT_RACE_ROUNDS 2000L
#define CV_ROUNDS 200000L
#define REPEATED_THREAD_ROUNDS 2048L
#define CHILD_COUNT 128
#define ADDRESS_WAITER_COUNT 8

#define STATUS_TIMEOUT_VALUE ((NTSTATUS)0x00000102L)

typedef NTSTATUS (WINAPI *rtl_wait_on_address_fn)(const void *, const void *, SIZE_T,
                                                  const LARGE_INTEGER *);
typedef void (WINAPI *rtl_wake_address_fn)(const void *);

static rtl_wait_on_address_fn rtl_wait_on_address;
static rtl_wake_address_fn rtl_wake_single;
static rtl_wake_address_fn rtl_wake_all;

static void fail(const char *test, const char *detail, unsigned long value)
{
    fprintf(stderr, "NO_TSO_PHASE1_FAIL test=%s detail=%s value=%lu winerr=%lu\n",
            test, detail, value, GetLastError());
    fflush(stderr);
    ExitProcess(1);
}

static LARGE_INTEGER relative_timeout_ms(DWORD milliseconds)
{
    LARGE_INTEGER timeout;
    timeout.QuadPart = -(LONGLONG)milliseconds * 10000;
    return timeout;
}

static void spin_until_equal(volatile LONG *value, LONG expected, DWORD timeout_ms,
                             const char *test, const char *detail)
{
    ULONGLONG deadline = GetTickCount64() + timeout_ms;
    while (*value != expected)
    {
        if (GetTickCount64() >= deadline) fail(test, detail, (unsigned long)*value);
        SwitchToThread();
    }
}

static void load_wait_exports(void)
{
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    rtl_wait_on_address = (rtl_wait_on_address_fn)GetProcAddress(ntdll, "RtlWaitOnAddress");
    rtl_wake_single = (rtl_wake_address_fn)GetProcAddress(ntdll, "RtlWakeAddressSingle");
    rtl_wake_all = (rtl_wake_address_fn)GetProcAddress(ntdll, "RtlWakeAddressAll");
    if (!rtl_wait_on_address || !rtl_wake_single || !rtl_wake_all)
        fail("exports", "RtlWaitOnAddress", 0);
}

struct ordering_state
{
    _Atomic LONG sequence;
    LONG payload;
    _Atomic LONG stale_reads;
};

static DWORD WINAPI ordering_producer(void *opaque)
{
    struct ordering_state *state = opaque;
    LONG i;
    for (i = 1; i <= ORDERING_ROUNDS; ++i)
    {
        while (atomic_load_explicit(&state->sequence, memory_order_acquire) != 2 * (i - 1))
            SwitchToThread();
        state->payload = i;
        atomic_store_explicit(&state->sequence, 2 * i - 1, memory_order_release);
    }
    return 0;
}

static DWORD WINAPI ordering_consumer(void *opaque)
{
    struct ordering_state *state = opaque;
    LONG i;
    for (i = 1; i <= ORDERING_ROUNDS; ++i)
    {
        while (atomic_load_explicit(&state->sequence, memory_order_acquire) != 2 * i - 1)
            SwitchToThread();
        if (state->payload != i)
            atomic_fetch_add_explicit(&state->stale_reads, 1, memory_order_relaxed);
        atomic_store_explicit(&state->sequence, 2 * i, memory_order_release);
    }
    return 0;
}

static void test_ordering(void)
{
    struct ordering_state state;
    HANDLE threads[2];
    DWORD wait;
    memset(&state, 0, sizeof(state));
    threads[0] = CreateThread(NULL, 0, ordering_producer, &state, 0, NULL);
    threads[1] = CreateThread(NULL, 0, ordering_consumer, &state, 0, NULL);
    if (!threads[0] || !threads[1]) fail("ordering", "CreateThread", 0);
    wait = WaitForMultipleObjects(2, threads, TRUE, 120000);
    if (wait != WAIT_OBJECT_0) fail("ordering", "thread timeout", wait);
    if (atomic_load_explicit(&state.stale_reads, memory_order_relaxed))
        fail("ordering", "stale read", atomic_load(&state.stale_reads));
    CloseHandle(threads[0]);
    CloseHandle(threads[1]);
    printf("NO_TSO_ORDERING_OK rounds=%ld stale=0\n", ORDERING_ROUNDS);
}

static void test_wake_before_wait(void)
{
    volatile LONG value = 0;
    LONG compare = 0;
    LARGE_INTEGER timeout = relative_timeout_ms(1000);
    NTSTATUS status;

    InterlockedExchange(&value, 1);
    rtl_wake_single((const void *)&value);
    status = rtl_wait_on_address((const void *)&value, &compare, sizeof(compare), &timeout);
    if (status) fail("wake_before_wait", "predicate was already changed", status);
    printf("NO_TSO_WAKE_BEFORE_WAIT_OK\n");
}

static void test_stale_wake_is_not_retained(void)
{
    volatile LONG value = 0;
    LONG compare = 0;
    LARGE_INTEGER timeout = relative_timeout_ms(20);
    NTSTATUS status;
    volatile LONG *reused, *original;

    /* A wake with no registered waiter is not a token for a future wait. */
    rtl_wake_single((const void *)&value);
    status = rtl_wait_on_address((const void *)&value, &compare, sizeof(compare), &timeout);
    if (status != STATUS_TIMEOUT_VALUE)
        fail("stale_wake", "wake without waiter was retained", status);

    /* Reusing the same virtual address must not consume state from its prior
     * allocation lifetime. */
    original = VirtualAlloc(NULL, 0x1000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    if (!original) fail("stale_wake", "VirtualAlloc original", 0);
    *original = 0;
    rtl_wake_single((const void *)original);
    if (!VirtualFree((void *)original, 0, MEM_RELEASE))
        fail("stale_wake", "VirtualFree original", 0);
    reused = VirtualAlloc((void *)original, 0x1000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    if (reused != original) fail("stale_wake", "virtual address reuse", (ULONG_PTR)reused);
    *reused = 0;
    timeout = relative_timeout_ms(20);
    status = rtl_wait_on_address((const void *)reused, &compare, sizeof(compare), &timeout);
    if (status != STATUS_TIMEOUT_VALUE)
        fail("stale_wake", "prior allocation wake was retained", status);
    VirtualFree((void *)reused, 0, MEM_RELEASE);
    printf("NO_TSO_STALE_WAKE_REJECTED_OK\n");
}

struct registration_state
{
    volatile LONG value;
    volatile LONG ready;
    volatile LONG done;
    volatile LONG acknowledged;
    volatile LONG failed;
};

static DWORD WINAPI registration_waiter(void *opaque)
{
    struct registration_state *state = opaque;
    LARGE_INTEGER timeout = relative_timeout_ms(2000);
    LONG i;

    for (i = 1; i <= REGISTRATION_ROUNDS && !state->failed; ++i)
    {
        LONG compare = 0;
        InterlockedExchange(&state->ready, i);
        while (state->value == 0)
        {
            NTSTATUS status = rtl_wait_on_address((const void *)&state->value, &compare,
                                                  sizeof(compare), &timeout);
            if (status == STATUS_TIMEOUT_VALUE)
            {
                InterlockedExchange(&state->failed, i);
                return 1;
            }
            if (status)
            {
                InterlockedExchange(&state->failed, i);
                return 2;
            }
        }
        InterlockedExchange(&state->done, i);
        spin_until_equal(&state->acknowledged, i, 5000,
                         "registration_race", "acknowledged");
    }
    return 0;
}

static void test_registration_race(void)
{
    struct registration_state state;
    HANDLE thread;
    LONG i;
    memset(&state, 0, sizeof(state));
    thread = CreateThread(NULL, 0, registration_waiter, &state, 0, NULL);
    if (!thread) fail("registration_race", "CreateThread", 0);

    for (i = 1; i <= REGISTRATION_ROUNDS; ++i)
    {
        spin_until_equal(&state.ready, i, 5000, "registration_race", "ready");
        InterlockedExchange(&state.value, 1);
        rtl_wake_single((const void *)&state.value);
        spin_until_equal(&state.done, i, 5000, "registration_race", "done");
        InterlockedExchange(&state.value, 0);
        InterlockedExchange(&state.acknowledged, i);
    }
    if (WaitForSingleObject(thread, 5000) != WAIT_OBJECT_0)
        fail("registration_race", "thread exit", 0);
    if (state.failed) fail("registration_race", "wait status", state.failed);
    CloseHandle(thread);
    printf("NO_TSO_REGISTRATION_RACE_OK rounds=%ld\n", REGISTRATION_ROUNDS);
}

struct multi_wait_state
{
    volatile LONG value;
    volatile LONG ready;
    volatile LONG woke;
    volatile LONG failed;
};

static DWORD WINAPI multi_waiter(void *opaque)
{
    struct multi_wait_state *state = opaque;
    LONG compare = 0;
    LARGE_INTEGER timeout = relative_timeout_ms(5000);
    NTSTATUS status;
    InterlockedIncrement(&state->ready);
    status = rtl_wait_on_address((const void *)&state->value, &compare, sizeof(compare), &timeout);
    if (status)
    {
        InterlockedIncrement(&state->failed);
        return (DWORD)status;
    }
    InterlockedIncrement(&state->woke);
    return 0;
}

static void test_wake_single_all(void)
{
    struct multi_wait_state state;
    HANDLE threads[ADDRESS_WAITER_COUNT];
    DWORD wait;
    int i;
    memset(&state, 0, sizeof(state));
    for (i = 0; i < ADDRESS_WAITER_COUNT; ++i)
    {
        threads[i] = CreateThread(NULL, 0, multi_waiter, &state, 0, NULL);
        if (!threads[i]) fail("wake_single_all", "CreateThread", i);
    }
    spin_until_equal(&state.ready, ADDRESS_WAITER_COUNT, 5000, "wake_single_all", "ready");
    Sleep(50);
    rtl_wake_single((const void *)&state.value);
    spin_until_equal(&state.woke, 1, 2000, "wake_single_all", "single");
    InterlockedExchange(&state.value, 1);
    rtl_wake_all((const void *)&state.value);
    wait = WaitForMultipleObjects(ADDRESS_WAITER_COUNT, threads, TRUE, 10000);
    if (wait != WAIT_OBJECT_0 || state.failed || state.woke != ADDRESS_WAITER_COUNT)
        fail("wake_single_all", "wake all", state.woke);
    for (i = 0; i < ADDRESS_WAITER_COUNT; ++i) CloseHandle(threads[i]);
    printf("NO_TSO_WAKE_SINGLE_ALL_OK waiters=%d\n", ADDRESS_WAITER_COUNT);
}

struct timeout_race_state
{
    volatile LONG value;
    NTSTATUS status;
};

static DWORD WINAPI timeout_race_waiter(void *opaque)
{
    struct timeout_race_state *state = opaque;
    LONG compare = 0;
    LARGE_INTEGER timeout = relative_timeout_ms(1);
    state->status = rtl_wait_on_address((const void *)&state->value, &compare,
                                        sizeof(compare), &timeout);
    return 0;
}

static void test_timeout_races(void)
{
    LONG successes = 0, timeouts = 0;
    LONG i;
    for (i = 0; i < TIMEOUT_RACE_ROUNDS; ++i)
    {
        struct timeout_race_state state;
        HANDLE thread;
        memset(&state, 0, sizeof(state));
        thread = CreateThread(NULL, 0, timeout_race_waiter, &state, 0, NULL);
        if (!thread) fail("timeout_race", "CreateThread", i);
        if (i & 1) Sleep(1); else SwitchToThread();
        InterlockedExchange(&state.value, 1);
        rtl_wake_single((const void *)&state.value);
        if (WaitForSingleObject(thread, 5000) != WAIT_OBJECT_0)
            fail("timeout_race", "stranded thread", i);
        if (!state.status) ++successes;
        else if (state.status == STATUS_TIMEOUT_VALUE) ++timeouts;
        else fail("timeout_race", "unexpected status", state.status);
        CloseHandle(thread);
    }
    printf("NO_TSO_TIMEOUT_RACE_OK rounds=%ld successes=%ld timeouts=%ld\n",
           TIMEOUT_RACE_ROUNDS, successes, timeouts);
}

struct cv_state
{
    CRITICAL_SECTION lock;
    CONDITION_VARIABLE cv;
    LONG turn;
    LONG failed;
};

static DWORD WINAPI cv_ping(void *opaque)
{
    struct cv_state *state = ((struct cv_state **)opaque)[0];
    LONG id = (LONG)(INT_PTR)((struct cv_state **)opaque)[1];
    LONG i;
    for (i = 0; i < CV_ROUNDS && !state->failed; ++i)
    {
        EnterCriticalSection(&state->lock);
        while (state->turn != id && !state->failed)
        {
            if (!SleepConditionVariableCS(&state->cv, &state->lock, 5000) &&
                GetLastError() == ERROR_TIMEOUT)
                InterlockedExchange(&state->failed, i + 1);
        }
        if (!state->failed)
        {
            state->turn ^= 1;
            WakeConditionVariable(&state->cv);
        }
        LeaveCriticalSection(&state->lock);
    }
    return state->failed ? 1 : 0;
}

static void test_condition_pingpong(void)
{
    struct cv_state state;
    void *args[2][2];
    HANDLE threads[2];
    DWORD wait;
    memset(&state, 0, sizeof(state));
    InitializeCriticalSection(&state.lock);
    InitializeConditionVariable(&state.cv);
    args[0][0] = &state; args[0][1] = (void *)(INT_PTR)0;
    args[1][0] = &state; args[1][1] = (void *)(INT_PTR)1;
    threads[0] = CreateThread(NULL, 0, cv_ping, args[0], 0, NULL);
    threads[1] = CreateThread(NULL, 0, cv_ping, args[1], 0, NULL);
    if (!threads[0] || !threads[1]) fail("condition", "CreateThread", 0);
    wait = WaitForMultipleObjects(2, threads, TRUE, 120000);
    if (wait != WAIT_OBJECT_0 || state.failed) fail("condition", "ping-pong", state.failed);
    CloseHandle(threads[0]);
    CloseHandle(threads[1]);
    DeleteCriticalSection(&state.lock);
    printf("NO_TSO_CONDITION_OK rounds_per_thread=%ld\n", CV_ROUNDS);
}

struct apc_state
{
    HANDLE event;
    volatile LONG callback_seen;
    volatile LONG waiting;
    DWORD wait_result;
};

static VOID CALLBACK apc_callback(ULONG_PTR opaque)
{
    struct apc_state *state = (struct apc_state *)opaque;
    InterlockedIncrement(&state->callback_seen);
}

static DWORD WINAPI apc_waiter(void *opaque)
{
    struct apc_state *state = opaque;
    InterlockedExchange(&state->waiting, 1);
    do
    {
        state->wait_result = WaitForSingleObjectEx(state->event, 5000, TRUE);
    } while (state->wait_result == WAIT_IO_COMPLETION);
    return 0;
}

static void test_apc_wait(void)
{
    struct apc_state state;
    HANDLE thread;
    memset(&state, 0, sizeof(state));
    state.event = CreateEventW(NULL, TRUE, FALSE, NULL);
    thread = CreateThread(NULL, 0, apc_waiter, &state, 0, NULL);
    if (!state.event || !thread) fail("apc", "setup", 0);
    spin_until_equal(&state.waiting, 1, 5000, "apc", "waiter ready");
    if (!QueueUserAPC(apc_callback, thread, (ULONG_PTR)&state)) fail("apc", "QueueUserAPC", 0);
    spin_until_equal(&state.callback_seen, 1, 5000, "apc", "callback");
    if (!SetEvent(state.event)) fail("apc", "SetEvent", 0);
    if (WaitForSingleObject(thread, 5000) != WAIT_OBJECT_0 ||
        state.wait_result != WAIT_OBJECT_0)
        fail("apc", "wait completion", state.wait_result);
    CloseHandle(thread);
    CloseHandle(state.event);
    printf("NO_TSO_APC_WAIT_OK callbacks=%ld\n", state.callback_seen);
}

static DWORD WINAPI lifecycle_thread(void *opaque)
{
    volatile LONG *counter = opaque;
    InterlockedIncrement(counter);
    return 0;
}

static void test_thread_lifecycle(void)
{
    volatile LONG counter = 0;
    HANDLE pair[2];
    LONG i;
    pair[0] = CreateThread(NULL, 0, lifecycle_thread, (void *)&counter, 0, NULL);
    pair[1] = CreateThread(NULL, 0, lifecycle_thread, (void *)&counter, 0, NULL);
    if (!pair[0] || !pair[1] || WaitForMultipleObjects(2, pair, TRUE, 5000) != WAIT_OBJECT_0)
        fail("thread_lifecycle", "second thread", 0);
    CloseHandle(pair[0]);
    CloseHandle(pair[1]);
    for (i = 0; i < REPEATED_THREAD_ROUNDS; ++i)
    {
        HANDLE thread = CreateThread(NULL, 0, lifecycle_thread, (void *)&counter, 0, NULL);
        if (!thread || WaitForSingleObject(thread, 5000) != WAIT_OBJECT_0)
            fail("thread_lifecycle", "repeated thread", i);
        CloseHandle(thread);
    }
    if (counter != REPEATED_THREAD_ROUNDS + 2)
        fail("thread_lifecycle", "counter", counter);
    printf("NO_TSO_THREAD_LIFECYCLE_OK repeated=%ld\n", REPEATED_THREAD_ROUNDS);
}

static int child_mode(void)
{
    volatile LONG value = 0;
    if (InterlockedIncrement(&value) != 1) return 2;
    Sleep(1);
    return 0;
}

static void test_children(void)
{
    char image[MAX_PATH];
    char command[2 * MAX_PATH];
    PROCESS_INFORMATION children[CHILD_COUNT];
    STARTUPINFOA startup;
    int i;
    memset(children, 0, sizeof(children));
    memset(&startup, 0, sizeof(startup));
    startup.cb = sizeof(startup);
    if (!GetModuleFileNameA(NULL, image, sizeof(image))) fail("children", "image path", 0);

    for (i = 0; i < CHILD_COUNT; ++i)
    {
        snprintf(command, sizeof(command), "\"%s\" --child", image);
        if (!CreateProcessA(NULL, command, NULL, NULL, FALSE, 0, NULL, NULL,
                            &startup, &children[i]))
            fail("children", "CreateProcess", i);
    }
    for (i = 0; i < CHILD_COUNT; ++i)
    {
        DWORD code = STILL_ACTIVE;
        if (WaitForSingleObject(children[i].hProcess, 60000) != WAIT_OBJECT_0)
            fail("children", "wait", i);
        if (!GetExitCodeProcess(children[i].hProcess, &code) || code)
            fail("children", "exit", code);
        CloseHandle(children[i].hThread);
        CloseHandle(children[i].hProcess);
    }
    printf("NO_TSO_CHILDREN_OK completed=%d/%d\n", CHILD_COUNT, CHILD_COUNT);
}

static int run_named_test(const char *name)
{
    if (!strcmp(name, "ordering")) test_ordering();
    else if (!strcmp(name, "wait"))
    {
        test_wake_before_wait();
        test_stale_wake_is_not_retained();
        test_registration_race();
        test_wake_single_all();
        test_timeout_races();
    }
    else if (!strcmp(name, "condition")) test_condition_pingpong();
    else if (!strcmp(name, "apc")) test_apc_wait();
    else if (!strcmp(name, "threads")) test_thread_lifecycle();
    else if (!strcmp(name, "children")) test_children();
    else return 2;
    return 0;
}

int main(int argc, char **argv)
{
    load_wait_exports();
    if (argc == 2 && !strcmp(argv[1], "--child")) return child_mode();
    if (argc == 3 && !strcmp(argv[1], "--test")) return run_named_test(argv[2]);
    test_ordering();
    test_wake_before_wait();
    test_stale_wake_is_not_retained();
    test_registration_race();
    test_wake_single_all();
    test_timeout_races();
    test_condition_pingpong();
    test_apc_wait();
    test_thread_lifecycle();
    test_children();
    puts("NO_TSO_PHASE1_SYNC_OK");
    return 0;
}
