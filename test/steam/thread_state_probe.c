#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>

#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

#ifndef STATUS_INFO_LENGTH_MISMATCH
#define STATUS_INFO_LENGTH_MISMATCH ((NTSTATUS)0xc0000004)
#endif

typedef HRESULT (WINAPI *get_thread_description_t)(HANDLE, PWSTR *);

static const char *state_name(ULONG state)
{
    static const char *const names[] = {
        "Initialized", "Ready", "Running", "Standby", "Terminated",
        "Wait", "Transition", "Unknown"
    };
    return state < sizeof(names) / sizeof(names[0]) ? names[state] : "?";
}

int wmain(void)
{
    get_thread_description_t get_description;
    SYSTEM_PROCESS_INFORMATION *process;
    NTSTATUS status;
    ULONG size = 0x10000, needed;
    BYTE *buffer = NULL;

    get_description = (get_thread_description_t)GetProcAddress(
        GetModuleHandleW(L"kernel32.dll"), "GetThreadDescription");
    for (;;)
    {
        BYTE *next = realloc(buffer, size);
        if (!next) return 2;
        buffer = next;
        status = NtQuerySystemInformation(SystemProcessInformation, buffer, size, &needed);
        if (status != STATUS_INFO_LENGTH_MISMATCH) break;
        size = needed > size * 2 ? needed : size * 2;
    }
    if (status)
    {
        fprintf(stderr, "NtQuerySystemInformation failed %#lx\n", status);
        free(buffer);
        return 3;
    }

    process = (SYSTEM_PROCESS_INFORMATION *)buffer;
    for (;;)
    {
        const WCHAR *name = process->ImageName.Buffer;
        if (name && process->ImageName.Length == 18 &&
            !_wcsnicmp(name, L"steam.exe", 9))
        {
            SYSTEM_THREAD_INFORMATION *thread = (SYSTEM_THREAD_INFORMATION *)(process + 1);
            ULONG i;
            wprintf(L"STEAM_PROCESS pid=%lu threads=%lu handles=%lu image=%.*ls\n",
                    HandleToULong(process->UniqueProcessId), process->NumberOfThreads,
                    process->HandleCount, process->ImageName.Length / 2, name);
            for (i = 0; i < process->NumberOfThreads; ++i)
            {
                HANDLE handle = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, FALSE,
                                           HandleToULong(thread[i].ClientId.UniqueThread));
                PWSTR description = NULL;
                HRESULT hr = E_NOTIMPL;
                if (handle && get_description) hr = get_description(handle, &description);
                printf("STEAM_THREAD tid=%lu state=%s(%lu) wait_reason=%lu start=%p priority=%ld",
                       HandleToULong(thread[i].ClientId.UniqueThread),
                       state_name(thread[i].ThreadState), thread[i].ThreadState,
                       thread[i].WaitReason, thread[i].StartAddress, thread[i].Priority);
                if (SUCCEEDED(hr) && description && *description)
                    wprintf(L" name=%ls", description);
                putchar('\n');
                if (description) LocalFree(description);
                if (handle) CloseHandle(handle);
            }
        }
        if (!process->NextEntryOffset) break;
        process = (SYSTEM_PROCESS_INFORMATION *)((BYTE *)process + process->NextEntryOffset);
    }
    free(buffer);
    return 0;
}
