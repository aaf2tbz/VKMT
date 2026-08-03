#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

static volatile LONG apc_seen;

static void fail(const char *what, DWORD value)
{
    fprintf(stderr, "MSYNC_SYNC_FAIL %s value=%lu error=%lu\n",
            what, (unsigned long)value, (unsigned long)GetLastError());
    ExitProcess(1);
}

static VOID CALLBACK apc_callback(ULONG_PTR value)
{
    if (value == 0x4d53594e) InterlockedExchange(&apc_seen, 1);
}

static DWORD WINAPI set_event_thread(void *arg)
{
    Sleep(20);
    return SetEvent((HANDLE)arg) ? 0 : GetLastError();
}

static DWORD WINAPI abandon_mutex_thread(void *arg)
{
    DWORD ret = WaitForSingleObject((HANDLE)arg, 1000);
    return ret == WAIT_OBJECT_0 ? 0 : ret;
}

struct pulse_waiter
{
    HANDLE event;
    DWORD result;
};

static DWORD WINAPI pulse_waiter_thread(void *arg)
{
    struct pulse_waiter *waiter = arg;
    waiter->result = WaitForSingleObject(waiter->event, 5000);
    return 0;
}

struct waitall_waiter
{
    HANDLE objects[2];
    DWORD result;
};

static DWORD WINAPI waitall_waiter_thread(void *arg)
{
    struct waitall_waiter *waiter = arg;
    waiter->result = WaitForMultipleObjects(2, waiter->objects, TRUE, 5000);
    return 0;
}

static int child_mode(const wchar_t *name)
{
    HANDLE event = OpenEventW(EVENT_MODIFY_STATE, FALSE, name);
    if (!event) fail("child OpenEventW", 0);
    if (!SetEvent(event)) fail("child SetEvent", 0);
    CloseHandle(event);
    puts("MSYNC_CHILD_OK");
    return 0;
}

static int pulse_waiter_mode(const wchar_t *type, const wchar_t *name, DWORD timeout)
{
    HANDLE event;
    DWORD ret;
    BOOL manual = !wcscmp(type, L"manual");

    event = CreateEventW(NULL, manual, FALSE, name);
    if (!event) fail("CreateEventW pulse waiter", 0);
    ret = WaitForSingleObject(event, timeout);
    if (ret == WAIT_OBJECT_0) printf("MSYNC_PULSE_WAIT_OK mode=%ls\n", type);
    else if (ret == WAIT_TIMEOUT) printf("MSYNC_PULSE_WAIT_TIMEOUT mode=%ls\n", type);
    else fail("pulse waiter", ret);
    CloseHandle(event);
    return 0;
}

static int pulse_mode(const wchar_t *name)
{
    HANDLE event = OpenEventW(EVENT_MODIFY_STATE, FALSE, name);

    if (!event) fail("OpenEventW pulse", 0);
    if (!PulseEvent(event)) fail("PulseEvent", 0);
    CloseHandle(event);
    puts("MSYNC_PULSE_SENT");
    return 0;
}

static int wait_for_marker_file(const wchar_t *path, DWORD minimum_size)
{
    DWORD i, size;
    HANDLE file;

    for (i = 0; i < 1000; ++i)
    {
        file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (file != INVALID_HANDLE_VALUE)
        {
            size = GetFileSize(file, NULL);
            CloseHandle(file);
            if (size >= minimum_size) return 1;
        }
        Sleep(10);
    }
    return 0;
}

static int pulse_local_mode(const wchar_t *type, const wchar_t *marker)
{
    HANDLE event, threads[2];
    struct pulse_waiter waiters[2] = {{0}, {0}};
    BOOL manual = !wcscmp(type, L"manual");
    DWORD i, ok_count = 0, timeout_count = 0;

    event = CreateEventW(NULL, manual, FALSE, NULL);
    if (!event) fail("CreateEventW local pulse", 0);
    for (i = 0; i < 2; ++i)
    {
        waiters[i].event = event;
        threads[i] = CreateThread(NULL, 0, pulse_waiter_thread, &waiters[i], 0, NULL);
        if (!threads[i]) fail("CreateThread local pulse", 0);
    }
    /* Each waiter writes one 11-byte registration acknowledgement only after
     * its server queue registration has linearized. */
    if (!wait_for_marker_file(marker, 22)) fail("local pulse registration marker", 0);
    if (!PulseEvent(event)) fail("PulseEvent local", 0);
    for (i = 0; i < 2; ++i)
    {
        if (WaitForSingleObject(threads[i], 7000) != WAIT_OBJECT_0) fail("local pulse waiter join", 0);
        CloseHandle(threads[i]);
        if (waiters[i].result == WAIT_OBJECT_0) ++ok_count;
        else if (waiters[i].result == WAIT_TIMEOUT) ++timeout_count;
        else fail("local pulse waiter result", waiters[i].result);
    }
    if ((manual && (ok_count != 2 || timeout_count)) ||
        (!manual && (ok_count != 1 || timeout_count != 1)))
        fail("local pulse fanout", ok_count * 10 + timeout_count);
    if (WaitForSingleObject(event, 0) != WAIT_TIMEOUT) fail("local pulse non-latching", 0);
    if (!SetEvent(event) || !PulseEvent(event)) fail("local pulse reset signaled state", 0);
    if (WaitForSingleObject(event, 0) != WAIT_TIMEOUT) fail("local pulse reset verification", 0);
    printf("MSYNC_PULSE_LOCAL_OK mode=%ls\n", type);
    CloseHandle(event);
    return 0;
}

static int waitall_rollback_mode(const wchar_t *mutex_name, const wchar_t *event_name, DWORD timeout)
{
    HANDLE mutex, event, thread, objects[2];
    DWORD ret, code;

    mutex = CreateMutexW(NULL, FALSE, mutex_name);
    event = CreateEventW(NULL, FALSE, TRUE, event_name);
    if (!mutex || !event) fail("Create rollback objects", 0);
    thread = CreateThread(NULL, 0, abandon_mutex_thread, mutex, 0, NULL);
    if (!thread) fail("Create rollback abandoner", 0);
    if (WaitForSingleObject(thread, 2000) != WAIT_OBJECT_0) fail("rollback abandoner wait", 0);
    if (!GetExitCodeThread(thread, &code) || code) fail("rollback abandoner exit", code);
    CloseHandle(thread);

    objects[0] = mutex;
    objects[1] = event;
    ret = WaitForMultipleObjects(2, objects, TRUE, timeout);
    if (ret != WAIT_TIMEOUT) fail("forced WaitAll rollback result", ret);
    puts("MSYNC_WAITALL_ROLLBACK_TIMEOUT");
    CloseHandle(event);
    CloseHandle(mutex);
    return 0;
}

static int consume_event_mode(const wchar_t *name)
{
    HANDLE event = OpenEventW(SYNCHRONIZE, FALSE, name);
    DWORD ret;

    if (!event) fail("OpenEventW rollback consumer", 0);
    ret = WaitForSingleObject(event, 2000);
    if (ret != WAIT_OBJECT_0) fail("rollback event consumer", ret);
    CloseHandle(event);
    puts("MSYNC_WAITALL_EVENT_CONSUMED");
    return 0;
}

static int probe_abandoned_mode(const wchar_t *name)
{
    HANDLE mutex = OpenMutexW(SYNCHRONIZE | MUTEX_MODIFY_STATE, FALSE, name);
    DWORD ret;

    if (!mutex) fail("OpenMutexW rollback probe", 0);
    ret = WaitForSingleObject(mutex, 2000);
    if (ret != WAIT_ABANDONED) fail("rollback abandoned mutex preserved", ret);
    if (!ReleaseMutex(mutex)) fail("rollback abandoned mutex release", 0);
    CloseHandle(mutex);
    puts("MSYNC_WAITALL_ABANDONED_PRESERVED");
    return 0;
}

static int waitall_rollback_local_mode(const wchar_t *ready, const wchar_t *release)
{
    HANDLE mutex, event, abandoner, waiter_thread;
    struct waitall_waiter waiter;
    DWORD code, ret;
    HANDLE release_file;

    mutex = CreateMutexW(NULL, FALSE, NULL);
    event = CreateEventW(NULL, FALSE, TRUE, NULL);
    if (!mutex || !event) fail("Create local rollback objects", 0);
    abandoner = CreateThread(NULL, 0, abandon_mutex_thread, mutex, 0, NULL);
    if (!abandoner) fail("Create local rollback abandoner", 0);
    if (WaitForSingleObject(abandoner, 2000) != WAIT_OBJECT_0) fail("local rollback abandoner", 0);
    if (!GetExitCodeThread(abandoner, &code) || code) fail("local rollback abandoner exit", code);
    CloseHandle(abandoner);

    waiter.objects[0] = mutex;
    waiter.objects[1] = event;
    waiter.result = ~0u;
    waiter_thread = CreateThread(NULL, 0, waitall_waiter_thread, &waiter, 0, NULL);
    if (!waiter_thread) fail("Create local rollback waiter", 0);
    if (!wait_for_marker_file(ready, 9)) fail("local rollback acquisition marker", 0);
    ret = WaitForSingleObject(event, 0);
    if (ret != WAIT_OBJECT_0) fail("local rollback event consumer", ret);
    release_file = CreateFileW(release, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (release_file == INVALID_HANDLE_VALUE) fail("local rollback release marker", 0);
    CloseHandle(release_file);
    if (WaitForSingleObject(waiter_thread, 7000) != WAIT_OBJECT_0) fail("local rollback waiter join", 0);
    CloseHandle(waiter_thread);
    if (waiter.result != WAIT_TIMEOUT) fail("local forced WaitAll rollback result", waiter.result);
    ret = WaitForSingleObject(mutex, 2000);
    if (ret != WAIT_ABANDONED) fail("local rollback abandoned mutex preserved", ret);
    if (!ReleaseMutex(mutex)) fail("local rollback abandoned mutex release", 0);
    CloseHandle(event);
    CloseHandle(mutex);
    puts("MSYNC_WAITALL_ROLLBACK_LOCAL_OK");
    return 0;
}

static void test_named_cross_process(void)
{
    wchar_t name[96], image[MAX_PATH], command[2 * MAX_PATH];
    STARTUPINFOW startup = {sizeof(startup)};
    PROCESS_INFORMATION process;
    HANDLE event;
    DWORD wait;

    swprintf(name, sizeof(name) / sizeof(name[0]), L"Local\\VKMT-msync-%lu",
             (unsigned long)GetCurrentProcessId());
    event = CreateEventW(NULL, TRUE, FALSE, name);
    if (!event) fail("CreateEventW named", 0);
    if (!GetModuleFileNameW(NULL, image, MAX_PATH)) fail("GetModuleFileNameW", 0);
    swprintf(command, sizeof(command) / sizeof(command[0]), L"\"%ls\" --child \"%ls\"", image, name);
    if (!CreateProcessW(NULL, command, NULL, NULL, FALSE, 0, NULL, NULL, &startup, &process))
        fail("CreateProcessW", 0);

    wait = WaitForSingleObject(event, 5000);
    if (wait != WAIT_OBJECT_0) fail("named event wait", wait);
    wait = WaitForSingleObject(process.hProcess, 5000);
    if (wait != WAIT_OBJECT_0) fail("child process wait", wait);
    if (GetExitCodeProcess(process.hProcess, &wait) && wait) fail("child exit", wait);

    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    CloseHandle(event);
}

static void test_contended_wait_any(void)
{
    HANDLE pair[2], thread;
    DWORD ret, code;

    pair[0] = CreateEventW(NULL, TRUE, FALSE, NULL);
    pair[1] = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!pair[0] || !pair[1]) fail("CreateEventW contended wait any", 0);

    thread = CreateThread(NULL, 0, set_event_thread, pair[1], 0, NULL);
    if (!thread) fail("CreateThread contended wait any", 0);

    ret = WaitForMultipleObjects(2, pair, FALSE, 2000);
    if (ret != WAIT_OBJECT_0 + 1) fail("contended wait any", ret);
    if (WaitForSingleObject(thread, 2000) != WAIT_OBJECT_0)
        fail("contended wait any thread", 0);
    if (!GetExitCodeThread(thread, &code) || code)
        fail("contended wait any thread exit", code);

    CloseHandle(thread);
    CloseHandle(pair[0]);
    CloseHandle(pair[1]);
}

int wmain(int argc, wchar_t **argv)
{
    HANDLE event, thread, semaphore, mutex, pair[2];
    DWORD ret, code;
    LONG previous;

    if (argc == 3 && !wcscmp(argv[1], L"--child")) return child_mode(argv[2]);
    if (argc == 5 && !wcscmp(argv[1], L"--pulse-waiter"))
        return pulse_waiter_mode(argv[2], argv[3], wcstoul(argv[4], NULL, 10));
    if (argc == 3 && !wcscmp(argv[1], L"--pulse")) return pulse_mode(argv[2]);
    if (argc == 4 && !wcscmp(argv[1], L"--pulse-local")) return pulse_local_mode(argv[2], argv[3]);
    if (argc == 5 && !wcscmp(argv[1], L"--waitall-rollback"))
        return waitall_rollback_mode(argv[2], argv[3], wcstoul(argv[4], NULL, 10));
    if (argc == 3 && !wcscmp(argv[1], L"--consume-event")) return consume_event_mode(argv[2]);
    if (argc == 3 && !wcscmp(argv[1], L"--probe-abandoned")) return probe_abandoned_mode(argv[2]);
    if (argc == 4 && !wcscmp(argv[1], L"--waitall-rollback-local"))
        return waitall_rollback_local_mode(argv[2], argv[3]);

    event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!event) fail("CreateEventW manual", 0);
    thread = CreateThread(NULL, 0, set_event_thread, event, 0, NULL);
    if (!thread) fail("CreateThread event", 0);
    ret = WaitForSingleObject(event, 2000);
    if (ret != WAIT_OBJECT_0) fail("manual event wait", ret);
    ret = WaitForSingleObject(thread, 2000);
    if (ret != WAIT_OBJECT_0) fail("event thread wait", ret);
    if (!GetExitCodeThread(thread, &code) || code) fail("event thread exit", code);
    CloseHandle(thread);
    CloseHandle(event);

    event = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (!event || !SetEvent(event)) fail("auto event set", 0);
    if (WaitForSingleObject(event, 0) != WAIT_OBJECT_0) fail("auto event first wait", 0);
    if (WaitForSingleObject(event, 0) != WAIT_TIMEOUT) fail("auto event consumed", 0);
    CloseHandle(event);

    semaphore = CreateSemaphoreW(NULL, 0, 2, NULL);
    if (!semaphore) fail("CreateSemaphoreW", 0);
    previous = -1;
    if (!ReleaseSemaphore(semaphore, 2, &previous) || previous != 0)
        fail("ReleaseSemaphore", previous);
    if (WaitForSingleObject(semaphore, 0) != WAIT_OBJECT_0 ||
        WaitForSingleObject(semaphore, 0) != WAIT_OBJECT_0 ||
        WaitForSingleObject(semaphore, 0) != WAIT_TIMEOUT)
        fail("semaphore count", 0);
    if (!ReleaseSemaphore(semaphore, 2, NULL)) fail("semaphore refill", 0);
    SetLastError(ERROR_SUCCESS);
    if (ReleaseSemaphore(semaphore, 1, NULL) || GetLastError() != ERROR_TOO_MANY_POSTS)
        fail("semaphore maximum", GetLastError());
    CloseHandle(semaphore);

    mutex = CreateMutexW(NULL, TRUE, NULL);
    if (!mutex) fail("CreateMutexW recursive", 0);
    if (WaitForSingleObject(mutex, 0) != WAIT_OBJECT_0) fail("recursive mutex wait", 0);
    if (!ReleaseMutex(mutex) || !ReleaseMutex(mutex)) fail("recursive mutex release", 0);
    CloseHandle(mutex);

    mutex = CreateMutexW(NULL, FALSE, NULL);
    if (!mutex) fail("CreateMutexW abandoned", 0);
    thread = CreateThread(NULL, 0, abandon_mutex_thread, mutex, 0, NULL);
    if (!thread) fail("CreateThread abandoned", 0);
    if (WaitForSingleObject(thread, 2000) != WAIT_OBJECT_0) fail("abandon thread wait", 0);
    if (!GetExitCodeThread(thread, &code) || code) fail("abandon thread exit", code);
    CloseHandle(thread);
    ret = WaitForSingleObject(mutex, 2000);
    if (ret != WAIT_ABANDONED) fail("abandoned mutex result", ret);
    if (!ReleaseMutex(mutex)) fail("abandoned mutex release", 0);
    CloseHandle(mutex);

    pair[0] = CreateEventW(NULL, TRUE, TRUE, NULL);
    pair[1] = CreateEventW(NULL, FALSE, TRUE, NULL);
    if (!pair[0] || !pair[1]) fail("CreateEventW wait all", 0);
    ret = WaitForMultipleObjects(2, pair, TRUE, 1000);
    if (ret != WAIT_OBJECT_0) fail("wait all", ret);
    if (WaitForSingleObject(pair[1], 0) != WAIT_TIMEOUT) fail("wait all auto consume", 0);
    CloseHandle(pair[0]);
    CloseHandle(pair[1]);

    test_contended_wait_any();

    pair[0] = CreateEventW(NULL, TRUE, FALSE, NULL);
    pair[1] = CreateEventW(NULL, FALSE, TRUE, NULL);
    if (!pair[0] || !pair[1]) fail("CreateEventW signal wait", 0);
    ret = SignalObjectAndWait(pair[0], pair[1], 1000, FALSE);
    if (ret != WAIT_OBJECT_0 || WaitForSingleObject(pair[0], 0) != WAIT_OBJECT_0)
        fail("SignalObjectAndWait", ret);
    CloseHandle(pair[0]);
    CloseHandle(pair[1]);

    if (!QueueUserAPC(apc_callback, GetCurrentThread(), 0x4d53594e)) fail("QueueUserAPC", 0);
    ret = SleepEx(1000, TRUE);
    if (ret != WAIT_IO_COMPLETION || !apc_seen) fail("alertable APC", ret);

    test_named_cross_process();
    puts("MSYNC_SYNC_OK");
    return 0;
}
