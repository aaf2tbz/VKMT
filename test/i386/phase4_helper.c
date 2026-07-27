#include <windows.h>

static __thread DWORD helper_tls;
static volatile LONG process_attach_count;
static volatile LONG thread_attach_count;
static volatile LONG thread_detach_count;

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, void *reserved)
{
    (void)instance;
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH)
    {
        helper_tls = 0x44000001;
        InterlockedIncrement(&process_attach_count);
    }
    else if (reason == DLL_THREAD_ATTACH)
    {
        helper_tls = 0x44000002;
        InterlockedIncrement(&thread_attach_count);
    }
    else if (reason == DLL_THREAD_DETACH)
        InterlockedIncrement(&thread_detach_count);
    return TRUE;
}

__declspec(dllexport) DWORD WINAPI phase4_helper_add(DWORD left, DWORD right)
{
    return left + right;
}

__declspec(dllexport) DWORD WINAPI phase4_helper_tls_roundtrip(DWORD value)
{
    DWORD previous = helper_tls;
    helper_tls = value;
    return previous;
}

__declspec(dllexport) DWORD WINAPI phase4_helper_tls_value(void)
{
    return helper_tls;
}

__declspec(dllexport) DWORD WINAPI phase4_helper_process_attaches(void)
{
    return process_attach_count;
}

__declspec(dllexport) DWORD WINAPI phase4_helper_thread_attaches(void)
{
    return thread_attach_count;
}

__declspec(dllexport) DWORD WINAPI phase4_helper_thread_detaches(void)
{
    return thread_detach_count;
}
