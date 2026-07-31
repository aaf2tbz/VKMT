#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <wchar.h>

typedef NTSTATUS (WINAPI *rtl_wait_on_address_fn)(const void *, const void *, SIZE_T,
                                                  const LARGE_INTEGER *);
typedef void (WINAPI *rtl_wake_address_single_fn)(void *);

struct delayed_wake
{
    rtl_wake_address_single_fn wake;
    LONG *address;
};

static DWORD WINAPI delayed_wake_thread(void *opaque)
{
    struct delayed_wake *wake = opaque;

    Sleep(1600);
    wake->wake(wake->address);
    return 0;
}

int main(void)
{
    rtl_wait_on_address_fn wait_on_address;
    rtl_wake_address_single_fn wake_address_single;
    THREAD_NAME_INFORMATION thread_name;
    UNICODE_STRING worker;
    struct delayed_wake delayed;
    WCHAR log_path[MAX_PATH], *slash;
    HANDLE log;
    ULONGLONG start, elapsed;
    HANDLE thread;
    HMODULE ntdll;
    LONG value = 0;
    LONG compare = 0;
    NTSTATUS status;
    unsigned int i;

    ntdll = GetModuleHandleW(L"ntdll.dll");
    wait_on_address = (rtl_wait_on_address_fn)GetProcAddress(ntdll, "RtlWaitOnAddress");
    wake_address_single = (rtl_wake_address_single_fn)GetProcAddress(ntdll, "RtlWakeAddressSingle");
    if (!wait_on_address || !wake_address_single)
    {
        puts("STEAM_WAIT_POLL_FAIL exports");
        return 1;
    }

    RtlInitUnicodeString(&worker, L"CHTTPClientThreadPool:0");
    thread_name.ThreadName = worker;
    status = NtSetInformationThread(GetCurrentThread(), (THREADINFOCLASS)38,
                                    &thread_name, sizeof(thread_name));
    if (status)
    {
        printf("STEAM_WAIT_POLL_FAIL thread_name=%08lx\n", (unsigned long)status);
        return 2;
    }

    if (!GetModuleFileNameW(NULL, log_path, MAX_PATH) ||
        !(slash = wcsrchr(log_path, L'\\')))
    {
        puts("STEAM_WAIT_POLL_FAIL image_path");
        return 3;
    }
    *slash = 0;
    lstrcatW(log_path, L"\\logs");
    CreateDirectoryW(log_path, NULL);
    lstrcatW(log_path, L"\\bootstrap_log.txt");
    log = CreateFileW(log_path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                      NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (log == INVALID_HANDLE_VALUE)
    {
        printf("STEAM_WAIT_POLL_FAIL create_log=%lu\n", GetLastError());
        return 3;
    }
    CloseHandle(log);
    Sleep(1200);

    for (i = 0; i < 2; ++i)
    {
        start = GetTickCount64();
        status = wait_on_address(&value, &compare, sizeof(compare), NULL);
        elapsed = GetTickCount64() - start;

        if (status || elapsed < 800 || elapsed > 1800)
        {
            printf("STEAM_WAIT_POLL_FAIL rescue=%u status=%08lx elapsed_ms=%llu\n",
                   i + 1, (unsigned long)status, (unsigned long long)elapsed);
            return 3;
        }
    }

    delayed.wake = wake_address_single;
    delayed.address = &value;
    thread = CreateThread(NULL, 0, delayed_wake_thread, &delayed, 0, NULL);
    if (!thread)
    {
        printf("STEAM_WAIT_POLL_FAIL create_thread=%lu\n", GetLastError());
        return 4;
    }

    start = GetTickCount64();
    status = wait_on_address(&value, &compare, sizeof(compare), NULL);
    elapsed = GetTickCount64() - start;
    WaitForSingleObject(thread, INFINITE);
    CloseHandle(thread);
    if (status || elapsed < 1400 || elapsed > 2400)
    {
        printf("STEAM_WAIT_POLL_FAIL exhausted status=%08lx elapsed_ms=%llu\n",
               (unsigned long)status, (unsigned long long)elapsed);
        return 5;
    }

    printf("STEAM_WAIT_POLL_OK rescues=2 exhausted_wait_ms=%llu\n",
           (unsigned long long)elapsed);
    return 0;
}
