#include <windows.h>

typedef int (__cdecl *code_fn)(void);

int main(void)
{
    static const BYTE first[] = { 0xb8, 1, 0, 0, 0, 0xc3 };
    BYTE *code;
    DWORD old;

    code = VirtualAlloc(NULL, 4096, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    if (!code) return 30;
    CopyMemory(code, first, sizeof(first));
    if (!VirtualProtect(code, 4096, PAGE_EXECUTE_READ, &old)) return 31;
    FlushInstructionCache(GetCurrentProcess(), code, sizeof(first));
    if (((code_fn)code)() != 1) return 32;
    if (!VirtualProtect(code, 4096, PAGE_READWRITE, &old)) return 33;
    code[1] = 2;
    if (!VirtualProtect(code, 4096, PAGE_EXECUTE_READ, &old)) return 34;
    FlushInstructionCache(GetCurrentProcess(), code, sizeof(first));
    if (((code_fn)code)() != 2) return 35;
    if (!VirtualFree(code, 0, MEM_RELEASE)) return 36;
    return 0;
}
