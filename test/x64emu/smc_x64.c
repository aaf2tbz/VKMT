/* M5 probe: a cached x64 block must be retired after code is modified. */
#include <windows.h>
#include <stdio.h>

int main(void)
{
    BYTE *code = VirtualAlloc( NULL, 0x1000, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE );
    int (WINAPI *fn)(void);
    int first, second;

    if (!code) return 1;
    /* mov eax, 1; ret */
    code[0] = 0xb8; code[1] = 1; code[2] = code[3] = code[4] = 0; code[5] = 0xc3;
    fn = (void *)code;
    first = fn();
    /* Patch the immediate, notify the emulator, and execute the same RIP. */
    code[1] = 2;
    if (!FlushInstructionCache( GetCurrentProcess(), code, 6 )) return 2;
    second = fn();
    VirtualFree( code, 0, MEM_RELEASE );
    printf( "smc_x64: %s (%d -> %d)\n", first == 1 && second == 2 ? "OK" : "FAIL", first, second );
    return first == 1 && second == 2 ? 0 : 3;
}
