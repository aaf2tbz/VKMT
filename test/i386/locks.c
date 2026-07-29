#include <windows.h>

static CRITICAL_SECTION section;
static volatile LONG started;
static volatile LONG value;

static DWORD WINAPI worker(void *arg)
{
    int i;
    InterlockedIncrement(&started);
    for (i = 0; i < 4096; ++i)
    {
        EnterCriticalSection(&section);
        ++value;
        LeaveCriticalSection(&section);
        InterlockedCompareExchange(&value, value, value);
    }
    return (DWORD)(ULONG_PTR)arg;
}

int main(void)
{
    HANDLE thread;
    DWORD status;

    InitializeCriticalSection(&section);
    thread = CreateThread(NULL, 0, worker, (void *)7, 0, NULL);
    if (!thread) return 20;
    worker((void *)0);
    if (WaitForSingleObject(thread, 30000) != WAIT_OBJECT_0) return 21;
    if (!GetExitCodeThread(thread, &status) || status != 7) return 22;
    CloseHandle(thread);
    DeleteCriticalSection(&section);
    if (started != 2 || value != 8192) return 23;
    return 0;
}
