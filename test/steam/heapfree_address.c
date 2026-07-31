#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

int main(void)
{
    HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    void *heap_free = GetProcAddress(kernel32, "HeapFree");
    void *rtl_free = GetProcAddress(ntdll, "RtlFreeHeap");
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("kernel32=%p HeapFree=%p ntdll=%p RtlFreeHeap=%p\n",
           kernel32, heap_free, ntdll, rtl_free);
    return 0;
}
