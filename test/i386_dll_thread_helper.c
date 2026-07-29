#define WIN32_LEAN_AND_MEAN
#include <windows.h>

__declspec(dllexport) DWORD WINAPI dll_thread_entry(void *arg)
{
    return SetEvent((HANDLE)arg) ? 0x71 : GetLastError();
}
