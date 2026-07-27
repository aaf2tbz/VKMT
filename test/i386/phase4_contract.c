#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <excpt.h>
#include <stdio.h>

typedef DWORD (WINAPI *helper_add_fn)(DWORD, DWORD);
typedef DWORD (WINAPI *helper_tls_roundtrip_fn)(DWORD);
typedef DWORD (WINAPI *helper_value_fn)(void);
typedef NTSTATUS (WINAPI *nt_query_information_process_fn)(HANDLE, PROCESSINFOCLASS, void *, ULONG, ULONG *);

static HANDLE marker;
static DWORD tls_index = TLS_OUT_OF_INDEXES;
static __thread DWORD executable_tls;
static helper_tls_roundtrip_fn helper_tls_roundtrip;
static helper_value_fn helper_tls_value;
static helper_value_fn helper_thread_attaches;
static helper_value_fn helper_thread_detaches;
static volatile LONG apc_count;
static volatile LONG apc_order;
static HANDLE apc_ready;
static HANDLE apc_done;
static volatile LONG callback_count;
static volatile LONG callback_data;
static volatile LONG seh_caught_raise;
static volatile LONG seh_caught_access;
static DWORD seh_resume_eip;

struct context_worker_state
{
    HANDLE ready;
    HANDLE stop;
};

static int pass(const char *name)
{
    DWORD written;
    char line[128];
    int len = wsprintfA(line, "P4_%s_OK\r\n", name);
    if (!WriteFile(marker, line, len, &written, NULL) || written != (DWORD)len) return 0;
    FlushFileBuffers(marker);
    return 1;
}

static int fail(const char *name, int code)
{
    DWORD written;
    char line[128];
    int len = wsprintfA(line, "P4_FAIL_%s_%d\r\n", name, code);
    WriteFile(marker, line, len, &written, NULL);
    FlushFileBuffers(marker);
    return code;
}

static void trace(const char *name)
{
    DWORD written;
    char line[128];
    int len = wsprintfA(line, "P4_TRACE_%s\r\n", name);
    WriteFile(marker, line, len, &written, NULL);
    FlushFileBuffers(marker);
}

static DWORD WINAPI context_worker(void *arg)
{
    struct context_worker_state *state = arg;
    SetEvent(state->ready);
    while (WaitForSingleObject(state->stop, 10) == WAIT_TIMEOUT) YieldProcessor();
    return 0x51;
}

static VOID CALLBACK apc_proc(ULONG_PTR value)
{
    trace(value == 1 ? "APC_CALLBACK_1" : "APC_CALLBACK_2");
    apc_order = apc_order * 10 + (LONG)value;
    if (InterlockedIncrement(&apc_count) == 2) SetEvent(apc_done);
}

static DWORD WINAPI apc_worker(void *arg)
{
    DWORD dynamic_value = (DWORD)(ULONG_PTR)arg;
    trace("APC_WORKER_ENTER");
    executable_tls = 0x22000002;
    if (!TlsSetValue(tls_index, (void *)(ULONG_PTR)dynamic_value)) return 31;
    trace("APC_WORKER_DYNAMIC_TLS");
    if (helper_tls_roundtrip(0x33000002) != 0x44000002) return 32;
    trace("APC_WORKER_DLL_TLS");
    SetEvent(apc_ready);
    trace("APC_WORKER_ALERTABLE_WAIT");
    while (apc_count != 2)
    {
        DWORD wait = SleepEx(5000, TRUE);
        trace(wait == WAIT_IO_COMPLETION ? "APC_WAIT_IO_COMPLETION" : "APC_WAIT_OTHER");
        if (wait != WAIT_IO_COMPLETION && apc_count != 2) return 33;
    }
    if (WaitForSingleObject(apc_done, 0) != WAIT_OBJECT_0) return 34;
    if ((DWORD)(ULONG_PTR)TlsGetValue(tls_index) != dynamic_value) return 35;
    if (executable_tls != 0x22000002) return 36;
    if (helper_tls_value() != 0x33000002) return 37;
    trace("APC_WORKER_EXIT");
    return 0x44;
}

static LRESULT CALLBACK phase4_message_filter_hook(int code, WPARAM wparam, LPARAM lparam)
{
    MSG *message = (MSG *)lparam;
    trace("USER_CALLBACK_ENTER");
    callback_data = code;
    if (!wparam && message && message->message == WM_APP + 4 &&
        message->wParam == 0x404 && message->lParam == 0x505)
        InterlockedIncrement(&callback_count);
    return 0;
}

static EXCEPTION_DISPOSITION seh_handler(EXCEPTION_RECORD *record, void *frame, CONTEXT *context, void *dispatch)
{
    (void)frame;
    (void)dispatch;
    if (record->ExceptionCode == 0xe0420404)
    {
        fprintf(stderr, "phase4: SEH received RaiseException at %08lx\n", context->Eip);
        seh_caught_raise = 1;
        return ExceptionContinueExecution;
    }
    if (record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION && seh_resume_eip)
    {
        fprintf(stderr, "phase4: SEH received access violation at %08lx, resume %08lx\n", context->Eip, seh_resume_eip);
        seh_caught_access = 1;
        context->Eip = seh_resume_eip;
        return ExceptionContinueExecution;
    }
    return ExceptionContinueSearch;
}

static int gate_loader(HMODULE *helper_out)
{
    HMODULE helper = LoadLibraryA("phase4_helper.dll");
    helper_add_fn add;
    helper_value_fn process_attaches;
    if (!helper)
    {
        fprintf(stderr, "phase4: LoadLibrary phase4_helper.dll failed: %lu\n", GetLastError());
        return 0;
    }
    add = (helper_add_fn)GetProcAddress(helper, "phase4_helper_add");
    helper_tls_roundtrip = (helper_tls_roundtrip_fn)GetProcAddress(helper, "phase4_helper_tls_roundtrip");
    helper_tls_value = (helper_value_fn)GetProcAddress(helper, "phase4_helper_tls_value");
    helper_thread_attaches = (helper_value_fn)GetProcAddress(helper, "phase4_helper_thread_attaches");
    helper_thread_detaches = (helper_value_fn)GetProcAddress(helper, "phase4_helper_thread_detaches");
    process_attaches = (helper_value_fn)GetProcAddress(helper, "phase4_helper_process_attaches");
    if (!add || !helper_tls_roundtrip || !helper_tls_value || !helper_thread_attaches ||
        !helper_thread_detaches || !process_attaches)
    {
        fprintf(stderr, "phase4: helper export lookup failed: %lu\n", GetLastError());
        return 0;
    }
    if (add(19, 23) != 42 || process_attaches() != 1)
    {
        fprintf(stderr, "phase4: helper call or process TLS attach failed: add=%lu attaches=%lu\n",
                add(19, 23), process_attaches());
        return 0;
    }
    *helper_out = helper;
    return pass("LOADLIBRARY");
}

static int gate_syscall(void)
{
    HMODULE ntdll = GetModuleHandleA("ntdll.dll");
    nt_query_information_process_fn query;
    PROCESS_BASIC_INFORMATION info;
    ULONG returned = 0;
    NTSTATUS status;
    if (!ntdll) return 0;
    query = (nt_query_information_process_fn)GetProcAddress(ntdll, "NtQueryInformationProcess");
    if (!query) return 0;
    ZeroMemory(&info, sizeof(info));
    status = query(GetCurrentProcess(), ProcessBasicInformation, &info, sizeof(info), &returned);
    if (status || returned != sizeof(info) || (DWORD)info.UniqueProcessId != GetCurrentProcessId()) return 0;
    return pass("SYSCALL_RETURN");
}

static int gate_tls_main(void)
{
    executable_tls = 0x22000001;
    tls_index = TlsAlloc();
    if (tls_index == TLS_OUT_OF_INDEXES) return 0;
    if (!TlsSetValue(tls_index, (void *)(ULONG_PTR)0x11000001)) return 0;
    if (helper_tls_roundtrip(0x33000001) != 0x44000001) return 0;
    if ((DWORD)(ULONG_PTR)TlsGetValue(tls_index) != 0x11000001) return 0;
    if (executable_tls != 0x22000001 || helper_tls_value() != 0x33000001) return 0;
    return pass("TLS_MAIN");
}

static int gate_context(void)
{
    HANDLE thread;
    DWORD tid;
    CONTEXT before, changed, after;
    DWORD exit_code;
    struct context_worker_state state;
    trace("CONTEXT_BEGIN");
    state.ready = CreateEventA(NULL, TRUE, FALSE, NULL);
    state.stop = CreateEventA(NULL, TRUE, FALSE, NULL);
    if (!state.ready || !state.stop) return 0;
    thread = CreateThread(NULL, 0, context_worker, &state, 0, &tid);
    if (!thread) return 0;
    trace("CONTEXT_THREAD_CREATED");
    if (WaitForSingleObject(state.ready, 10000) != WAIT_OBJECT_0) return 0;
    if (SuspendThread(thread) == (DWORD)-1) return 0;
    trace("CONTEXT_THREAD_SUSPENDED");
    ZeroMemory(&before, sizeof(before));
    before.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
    if (!GetThreadContext(thread, &before)) return 0;
    trace("CONTEXT_GET_BEFORE");
    changed = before;
    changed.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
    changed.Eax ^= 0x13579bdf;
    if (!SetThreadContext(thread, &changed)) return 0;
    trace("CONTEXT_SET");
    ZeroMemory(&after, sizeof(after));
    after.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
    if (!GetThreadContext(thread, &after) || after.Eax != changed.Eax) return 0;
    trace("CONTEXT_GET_AFTER");
    if (ResumeThread(thread) == (DWORD)-1) return 0;
    trace("CONTEXT_THREAD_RESUMED");
    SetEvent(state.stop);
    if (WaitForSingleObject(thread, 10000) != WAIT_OBJECT_0) return 0;
    if (!GetExitCodeThread(thread, &exit_code) || exit_code != 0x51) return 0;
    trace("CONTEXT_THREAD_EXITED");
    CloseHandle(thread);
    CloseHandle(state.ready);
    CloseHandle(state.stop);
    return pass("CONTEXT");
}

static int gate_seh(void)
{
    trace("SEH_BEGIN");
    seh_caught_raise = 0;
    seh_caught_access = 0;
    __try1(seh_handler)
    fprintf(stderr, "phase4: raising guest exception\n");
    RaiseException(0xe0420404, 0, 0, NULL);
    __except1

    trace("SEH_RAISE_RETURNED");
    fprintf(stderr, "phase4: RaiseException returned, caught=%ld\n", seh_caught_raise);

    seh_resume_eip = (DWORD)(ULONG_PTR)&&resume_after_access;
    __try1(seh_handler)
    fprintf(stderr, "phase4: raising guest access violation\n");
    *(volatile DWORD *)0 = 1;
resume_after_access:
    __except1
    trace("SEH_ACCESS_RETURNED");
    seh_resume_eip = 0;
    fprintf(stderr, "phase4: access resumed, caught=%ld\n", seh_caught_access);
    if (!seh_caught_raise || !seh_caught_access) return 0;
    return pass("SEH");
}

static int gate_apc_and_worker(void)
{
    HANDLE thread;
    DWORD exit_code;
    trace("APC_BEGIN");
    executable_tls = 0x22000001;
    apc_count = 0;
    apc_order = 0;
    apc_ready = CreateEventA(NULL, TRUE, FALSE, NULL);
    apc_done = CreateEventA(NULL, TRUE, FALSE, NULL);
    if (!apc_ready || !apc_done) return 0;
    thread = CreateThread(NULL, 0, apc_worker, (void *)0x11000002, 0, NULL);
    if (!thread || WaitForSingleObject(apc_ready, 10000) != WAIT_OBJECT_0) return 0;
    trace("APC_WORKER_READY");
    if (!QueueUserAPC(apc_proc, thread, 1) || !QueueUserAPC(apc_proc, thread, 2)) return 0;
    trace("APC_QUEUED");
    if (WaitForSingleObject(thread, 15000) != WAIT_OBJECT_0) return 0;
    trace("APC_WORKER_JOINED");
    if (!GetExitCodeThread(thread, &exit_code) || exit_code != 0x44) return 0;
    if (apc_count != 2 || apc_order != 12) return 0;
    if ((DWORD)(ULONG_PTR)TlsGetValue(tls_index) != 0x11000001 || executable_tls != 0x22000001 ||
        helper_tls_value() != 0x33000001) return 0;
    CloseHandle(thread);
    CloseHandle(apc_ready);
    CloseHandle(apc_done);
    return pass("APC") && pass("SECOND_THREAD");
}

static int gate_user_callback(void)
{
    HHOOK hook;
    MSG message = {0};
    trace("USER_CALLBACK_BEGIN");
    callback_count = 0;
    callback_data = 0;
    hook = SetWindowsHookExA(WH_MSGFILTER, phase4_message_filter_hook, NULL,
                             GetCurrentThreadId());
    if (!hook) return 0;
    message.message = WM_APP + 4;
    message.wParam = 0x404;
    message.lParam = 0x505;
    trace("USER_CALLBACK_QUEUED");
    CallMsgFilterA(&message, MSGF_DIALOGBOX);
    trace("USER_CALLBACK_RETURNED");
    if (!UnhookWindowsHookEx(hook)) return 0;
    if (callback_count != 1 || callback_data != MSGF_DIALOGBOX) return 0;
    return pass("USER_CALLBACK");
}

static int gate_thread_repetition(void)
{
    unsigned int i;
    DWORD attaches = helper_thread_attaches();
    DWORD detaches = helper_thread_detaches();
    for (i = 0; i != 8; ++i)
    {
        struct context_worker_state state;
        HANDLE thread;
        DWORD code;
        state.ready = CreateEventA(NULL, TRUE, FALSE, NULL);
        state.stop = CreateEventA(NULL, TRUE, FALSE, NULL);
        if (!state.ready || !state.stop) return 0;
        thread = CreateThread(NULL, 0, context_worker, &state, 0, NULL);
        if (!thread || WaitForSingleObject(state.ready, 10000) != WAIT_OBJECT_0) return 0;
        SetEvent(state.stop);
        if (!thread || WaitForSingleObject(thread, 10000) != WAIT_OBJECT_0) return 0;
        if (!GetExitCodeThread(thread, &code) || code != 0x51) return 0;
        CloseHandle(thread);
        CloseHandle(state.ready);
        CloseHandle(state.stop);
    }
    if (helper_thread_attaches() != attaches + 8 ||
        helper_thread_detaches() != detaches + 8) return 0;
    return pass("THREAD_LIFECYCLE");
}

int main(int argc, char **argv)
{
    HMODULE helper = NULL;
    if (argc != 2) return 100;
    marker = CreateFileA(argv[1], GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (marker == INVALID_HANDLE_VALUE) return 101;
    if (!gate_loader(&helper)) return fail("LOADLIBRARY", 1);
    if (!gate_syscall()) return fail("SYSCALL_RETURN", 2);
    if (!gate_tls_main()) return fail("TLS_MAIN", 3);
    if (!gate_context()) return fail("CONTEXT", 4);
    if (!gate_seh()) return fail("SEH", 5);
    if (!gate_apc_and_worker()) return fail("APC_OR_SECOND_THREAD", 6);
    if (!gate_user_callback()) return fail("USER_CALLBACK", 7);
    if (!gate_thread_repetition()) return fail("THREAD_LIFECYCLE", 8);
    if (!TlsFree(tls_index)) return fail("TLS_FREE", 9);
    FreeLibrary(helper);
    if (!pass("ALL_SYSTEM_CONTRACT")) return fail("FINAL_MARKER", 10);
    CloseHandle(marker);
    return 0;
}
