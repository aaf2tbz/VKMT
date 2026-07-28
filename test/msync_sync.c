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

static int child_mode(const wchar_t *name)
{
    HANDLE event = OpenEventW(EVENT_MODIFY_STATE, FALSE, name);
    if (!event) fail("child OpenEventW", 0);
    if (!SetEvent(event)) fail("child SetEvent", 0);
    CloseHandle(event);
    puts("MSYNC_CHILD_OK");
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

int wmain(int argc, wchar_t **argv)
{
    HANDLE event, thread, semaphore, mutex, pair[2];
    DWORD ret, code;
    LONG previous;

    if (argc == 3 && !wcscmp(argv[1], L"--child")) return child_mode(argv[2]);

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
