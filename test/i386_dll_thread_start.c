#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

typedef DWORD (WINAPI *thread_entry_fn)(void *);

int main(void)
{
    HMODULE module = LoadLibraryA("i386_dll_thread_helper.dll");
    thread_entry_fn entry;
    HANDLE event, thread;
    DWORD wait, code = 0;

    if (!module) return 10;
    entry = (thread_entry_fn)GetProcAddress(module, "dll_thread_entry");
    event = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (!entry || !event) return 11;
    thread = CreateThread(NULL, 0, entry, event, 0, NULL);
    wait = thread ? WaitForSingleObject(event, 5000) : WAIT_FAILED;
    if (thread) WaitForSingleObject(thread, 5000);
    if (thread) GetExitCodeThread(thread, &code);
    fprintf(stderr, "DLL_THREAD: module=%p entry=%p event=%p thread=%p wait=%#lx code=%#lx error=%lu\n",
            module, entry, event, thread, (unsigned long)wait, (unsigned long)code, GetLastError());
    if (thread) CloseHandle(thread);
    CloseHandle(event);
    FreeLibrary(module);
    return wait == WAIT_OBJECT_0 && code == 0x71 ? 0 : 1;
}
