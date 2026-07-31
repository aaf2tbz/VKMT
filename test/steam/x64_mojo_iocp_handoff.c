#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define PAYLOAD "vkmt-mojo-parent"
#define REPLY   "vkmt-mojo-child"
#define IO_KEY  ((ULONG_PTR)0x564b4d54)

static int fail(const char *stage, DWORD value)
{
    fprintf(stderr, "MOJO_IOCP_FAIL stage=%s value=%lu winerr=%lu\n",
            stage, value, GetLastError());
    return 1;
}

static BOOL wait_overlapped(HANDLE handle, OVERLAPPED *overlapped, DWORD *bytes)
{
    DWORD wait = WaitForSingleObject(overlapped->hEvent, 10000);
    if (wait != WAIT_OBJECT_0)
    {
        SetLastError(wait == WAIT_TIMEOUT ? WAIT_TIMEOUT : GetLastError());
        return FALSE;
    }
    return GetOverlappedResult(handle, overlapped, bytes, FALSE);
}

static int run_child(HANDLE pipe, HANDLE ready)
{
    HANDLE port;
    OVERLAPPED read_overlapped = {0}, write_overlapped = {0};
    OVERLAPPED *completed = NULL;
    ULONG_PTR key = 0;
    DWORD bytes = 0;
    char buffer[64] = {0};
    BOOL result;

    if (!GetHandleInformation(pipe, &bytes)) return fail("child-pipe-handle", 0);
    if (!GetHandleInformation(ready, &bytes)) return fail("child-ready-handle", 0);

    port = CreateIoCompletionPort(pipe, NULL, IO_KEY, 1);
    if (!port) return fail("child-create-iocp", 0);

    result = ReadFile(pipe, buffer, sizeof(buffer), &bytes, &read_overlapped);
    if (!result && GetLastError() != ERROR_IO_PENDING)
        return fail("child-read-submit", 0);
    if (!SetEvent(ready)) return fail("child-ready", 0);
    if (!GetQueuedCompletionStatus(port, &bytes, &key, &completed, 10000))
        return fail("child-read-completion", bytes);
    if (key != IO_KEY || completed != &read_overlapped ||
        bytes != sizeof(PAYLOAD) || memcmp(buffer, PAYLOAD, sizeof(PAYLOAD)))
        return fail("child-read-payload", bytes);

    result = WriteFile(pipe, REPLY, sizeof(REPLY), &bytes, &write_overlapped);
    if (!result && GetLastError() != ERROR_IO_PENDING)
        return fail("child-write-submit", 0);
    completed = NULL;
    key = 0;
    if (!GetQueuedCompletionStatus(port, &bytes, &key, &completed, 10000))
        return fail("child-write-completion", bytes);
    if (key != IO_KEY || completed != &write_overlapped || bytes != sizeof(REPLY))
        return fail("child-write-result", bytes);

    CloseHandle(port);
    puts("MOJO_IOCP_CHILD_OK");
    return 0;
}

static int run_iteration(const WCHAR *self, unsigned int iteration)
{
    SECURITY_ATTRIBUTES security = {sizeof(security), NULL, TRUE};
    STARTUPINFOEXW startup = {0};
    PROCESS_INFORMATION process = {0};
    SIZE_T attribute_size = 0;
    HANDLE inherited[2], server = INVALID_HANDLE_VALUE, client = INVALID_HANDLE_VALUE;
    HANDLE ready = NULL;
    OVERLAPPED connect_overlapped = {0}, write_overlapped = {0}, read_overlapped = {0};
    WCHAR pipe_name[128], command[32768];
    char buffer[64] = {0};
    DWORD bytes = 0, exit_code = 0;
    BOOL result, connect_pending = FALSE;
    int ret = 1;

    swprintf(pipe_name, sizeof(pipe_name) / sizeof(pipe_name[0]),
             L"\\\\.\\pipe\\vkmt-mojo-%lu-%u", GetCurrentProcessId(), iteration);
    server = CreateNamedPipeW(pipe_name, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
                              PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
                              1, 4096, 4096, 0, &security);
    if (server == INVALID_HANDLE_VALUE) return fail("parent-create-pipe", iteration);

    connect_overlapped.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    write_overlapped.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    read_overlapped.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    ready = CreateEventW(&security, TRUE, FALSE, NULL);
    if (!connect_overlapped.hEvent || !write_overlapped.hEvent ||
        !read_overlapped.hEvent || !ready)
        goto done;

    result = ConnectNamedPipe(server, &connect_overlapped);
    if (!result)
    {
        DWORD error = GetLastError();
        if (error == ERROR_IO_PENDING) connect_pending = TRUE;
        else if (error != ERROR_PIPE_CONNECTED) goto done;
    }
    client = CreateFileW(pipe_name, GENERIC_READ | GENERIC_WRITE, 0, NULL,
                         OPEN_EXISTING, FILE_FLAG_OVERLAPPED, NULL);
    if (client == INVALID_HANDLE_VALUE) goto done;
    if (connect_pending && !wait_overlapped(server, &connect_overlapped, &bytes))
        goto done;

    inherited[0] = server;
    inherited[1] = ready;
    InitializeProcThreadAttributeList(NULL, 1, 0, &attribute_size);
    startup.lpAttributeList = HeapAlloc(GetProcessHeap(), 0, attribute_size);
    if (!startup.lpAttributeList ||
        !InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &attribute_size) ||
        !UpdateProcThreadAttribute(startup.lpAttributeList, 0,
                                   PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                   inherited, sizeof(inherited), NULL, NULL))
        goto done;
    startup.StartupInfo.cb = sizeof(startup);
    swprintf(command, sizeof(command) / sizeof(command[0]),
             L"\"%ls\" --child %llu %llu", self,
             (unsigned long long)(uintptr_t)server,
             (unsigned long long)(uintptr_t)ready);
    if (!CreateProcessW(self, command, NULL, NULL, TRUE,
                        EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED | CREATE_NO_WINDOW,
                        NULL, NULL, &startup.StartupInfo, &process))
        goto done;
    if (ResumeThread(process.hThread) == (DWORD)-1) goto done;
    if (WaitForSingleObject(ready, 10000) != WAIT_OBJECT_0)
        return fail("parent-child-ready", iteration);

    result = WriteFile(client, PAYLOAD, sizeof(PAYLOAD), &bytes, &write_overlapped);
    if (!result && GetLastError() != ERROR_IO_PENDING) goto done;
    if (!result && !wait_overlapped(client, &write_overlapped, &bytes)) goto done;
    if (bytes != sizeof(PAYLOAD)) goto done;

    result = ReadFile(client, buffer, sizeof(buffer), &bytes, &read_overlapped);
    if (!result && GetLastError() != ERROR_IO_PENDING) goto done;
    if (!result && !wait_overlapped(client, &read_overlapped, &bytes)) goto done;
    if (bytes != sizeof(REPLY) || memcmp(buffer, REPLY, sizeof(REPLY))) goto done;
    if (WaitForSingleObject(process.hProcess, 10000) != WAIT_OBJECT_0 ||
        !GetExitCodeProcess(process.hProcess, &exit_code) || exit_code)
        return fail("parent-child-exit", exit_code);
    ret = 0;

done:
    if (ret) fail("parent-iteration", iteration);
    if (process.hThread) CloseHandle(process.hThread);
    if (process.hProcess) CloseHandle(process.hProcess);
    if (startup.lpAttributeList)
    {
        DeleteProcThreadAttributeList(startup.lpAttributeList);
        HeapFree(GetProcessHeap(), 0, startup.lpAttributeList);
    }
    if (ready) CloseHandle(ready);
    if (read_overlapped.hEvent) CloseHandle(read_overlapped.hEvent);
    if (write_overlapped.hEvent) CloseHandle(write_overlapped.hEvent);
    if (connect_overlapped.hEvent) CloseHandle(connect_overlapped.hEvent);
    if (client != INVALID_HANDLE_VALUE) CloseHandle(client);
    if (server != INVALID_HANDLE_VALUE) CloseHandle(server);
    return ret;
}

int wmain(int argc, WCHAR **argv)
{
    WCHAR self[MAX_PATH];
    unsigned int i, iterations = 100;

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    if (argc == 4 && !wcscmp(argv[1], L"--child"))
        return run_child((HANDLE)(uintptr_t)_wcstoui64(argv[2], NULL, 0),
                         (HANDLE)(uintptr_t)_wcstoui64(argv[3], NULL, 0));
    if (argc == 2) iterations = wcstoul(argv[1], NULL, 0);
    if (!GetModuleFileNameW(NULL, self, sizeof(self) / sizeof(self[0])))
        return fail("self-path", 0);
    for (i = 0; i < iterations; ++i)
        if (run_iteration(self, i)) return 1;
    printf("MOJO_IOCP_HANDOFF_OK iterations=%u\n", iterations);
    return 0;
}
