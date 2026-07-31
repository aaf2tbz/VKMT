#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

static int fail(const char *stage, DWORD value)
{
    fprintf(stderr, "CHROMIUM_HANDLE_HANDOFF_FAIL stage=%s value=%lu winerr=%lu\n",
            stage, value, GetLastError());
    return 1;
}

static int child_main(int argc, WCHAR **argv)
{
    HANDLE request, response, ready, mapping;
    DWORD flags, bytes;
    char request_data[16] = {0};
    char *shared;

    if (argc != 6) return fail("child-argc", argc);
    request = (HANDLE)(uintptr_t)_wcstoui64(argv[2], NULL, 0);
    response = (HANDLE)(uintptr_t)_wcstoui64(argv[3], NULL, 0);
    ready = (HANDLE)(uintptr_t)_wcstoui64(argv[4], NULL, 0);
    mapping = (HANDLE)(uintptr_t)_wcstoui64(argv[5], NULL, 0);

    if (!GetHandleInformation(request, &flags) ||
        !GetHandleInformation(response, &flags) ||
        !GetHandleInformation(ready, &flags) ||
        !GetHandleInformation(mapping, &flags))
        return fail("child-handle-list", 0);

    shared = MapViewOfFile(mapping, FILE_MAP_ALL_ACCESS, 0, 0, 4096);
    if (!shared) return fail("child-map", 0);
    if (strcmp(shared, "parent-before-resume"))
    {
        UnmapViewOfFile(shared);
        return fail("child-shared-read", 0);
    }

    if (!ReadFile(request, request_data, sizeof(request_data), &bytes, NULL) ||
        bytes != 4 || memcmp(request_data, "ping", 4))
    {
        UnmapViewOfFile(shared);
        return fail("child-pipe-read", bytes);
    }

    memcpy(shared, "child-after-resume", sizeof("child-after-resume"));
    if (!WriteFile(response, "pong", 4, &bytes, NULL) || bytes != 4 || !SetEvent(ready))
    {
        UnmapViewOfFile(shared);
        return fail("child-reply", bytes);
    }
    MemoryBarrier();
    UnmapViewOfFile(shared);
    puts("CHROMIUM_HANDLE_HANDOFF_CHILD_OK");
    return 0;
}

static int parent_main(const WCHAR *self)
{
    SECURITY_ATTRIBUTES security = {sizeof(security), NULL, TRUE};
    STARTUPINFOEXW startup;
    PROCESS_INFORMATION process;
    SIZE_T attr_size = 0;
    HANDLE request_read = NULL, request_write = NULL;
    HANDLE response_read = NULL, response_write = NULL;
    HANDLE ready = NULL, mapping = NULL;
    HANDLE inherited[4];
    WCHAR command[32768];
    char response_data[16] = {0};
    char *shared = NULL;
    DWORD bytes, exit_code = STILL_ACTIVE;
    int ret = 1;

    memset(&startup, 0, sizeof(startup));
    memset(&process, 0, sizeof(process));
    startup.StartupInfo.cb = sizeof(startup);

    if (!CreatePipe(&request_read, &request_write, &security, 0) ||
        !CreatePipe(&response_read, &response_write, &security, 0))
        goto done;
    if (!SetHandleInformation(request_write, HANDLE_FLAG_INHERIT, 0) ||
        !SetHandleInformation(response_read, HANDLE_FLAG_INHERIT, 0))
        goto done;
    ready = CreateEventW(&security, TRUE, FALSE, NULL);
    mapping = CreateFileMappingW(INVALID_HANDLE_VALUE, &security, PAGE_READWRITE, 0, 4096, NULL);
    if (!ready || !mapping) goto done;
    shared = MapViewOfFile(mapping, FILE_MAP_ALL_ACCESS, 0, 0, 4096);
    if (!shared) goto done;
    memcpy(shared, "parent-before-resume", sizeof("parent-before-resume"));
    MemoryBarrier();

    inherited[0] = request_read;
    inherited[1] = response_write;
    inherited[2] = ready;
    inherited[3] = mapping;

    InitializeProcThreadAttributeList(NULL, 1, 0, &attr_size);
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER) goto done;
    startup.lpAttributeList = HeapAlloc(GetProcessHeap(), 0, attr_size);
    if (!startup.lpAttributeList ||
        !InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &attr_size) ||
        !UpdateProcThreadAttribute(startup.lpAttributeList, 0,
                                   PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                   inherited, sizeof(inherited), NULL, NULL))
        goto done;

    if (swprintf(command, sizeof(command) / sizeof(command[0]),
                 L"\"%ls\" --child %llu %llu %llu %llu", self,
                 (unsigned long long)(uintptr_t)request_read,
                 (unsigned long long)(uintptr_t)response_write,
                 (unsigned long long)(uintptr_t)ready,
                 (unsigned long long)(uintptr_t)mapping) < 0)
        goto done;

    if (!CreateProcessW(self, command, NULL, NULL, TRUE,
                        EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED | CREATE_NO_WINDOW,
                        NULL, NULL, &startup.StartupInfo, &process))
        goto done;

    CloseHandle(request_read);
    request_read = NULL;
    CloseHandle(response_write);
    response_write = NULL;
    if (ResumeThread(process.hThread) == (DWORD)-1) goto done;
    CloseHandle(process.hThread);
    process.hThread = NULL;

    if (!WriteFile(request_write, "ping", 4, &bytes, NULL) || bytes != 4)
        goto done;
    if (WaitForSingleObject(ready, 15000) != WAIT_OBJECT_0)
        return fail("parent-ready", 0);
    if (!ReadFile(response_read, response_data, sizeof(response_data), &bytes, NULL) ||
        bytes != 4 || memcmp(response_data, "pong", 4))
        return fail("parent-pipe-read", bytes);
    if (WaitForSingleObject(process.hProcess, 15000) != WAIT_OBJECT_0 ||
        !GetExitCodeProcess(process.hProcess, &exit_code) || exit_code)
        return fail("parent-child-exit", exit_code);
    MemoryBarrier();
    if (strcmp(shared, "child-after-resume"))
        return fail("parent-shared-read", 0);

    puts("CHROMIUM_HANDLE_HANDOFF_OK");
    ret = 0;

done:
    if (ret && GetLastError()) fail("parent", 0);
    if (process.hThread) CloseHandle(process.hThread);
    if (process.hProcess) CloseHandle(process.hProcess);
    if (startup.lpAttributeList)
    {
        DeleteProcThreadAttributeList(startup.lpAttributeList);
        HeapFree(GetProcessHeap(), 0, startup.lpAttributeList);
    }
    if (shared) UnmapViewOfFile(shared);
    if (mapping) CloseHandle(mapping);
    if (ready) CloseHandle(ready);
    if (response_write) CloseHandle(response_write);
    if (response_read) CloseHandle(response_read);
    if (request_write) CloseHandle(request_write);
    if (request_read) CloseHandle(request_read);
    return ret;
}

int wmain(int argc, WCHAR **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    if (argc > 1 && !wcscmp(argv[1], L"--child")) return child_main(argc, argv);
    if (argc != 1) return fail("argc", argc);
    return parent_main(argv[0]);
}
