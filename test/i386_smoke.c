/* i386 execution-contract fixture for the native ARM64 WoW64/FEX gate.
 * It deliberately covers register/branch arithmetic, stack calls, locked
 * operations, and self-modifying executable memory. */
#include <windows.h>

typedef int (__cdecl *code_fn)(void);

static volatile LONG locked_value;

static int __cdecl stack_add(int a, int b)
{
    return a + b;
}

int main(int argc, char **argv)
{
    const char message[] = "VKMT i386 WoW64 execution contract passed\r\n";
    unsigned char code[] = { 0xb8, 1, 0, 0, 0, 0xc3 }; /* mov eax,imm32; ret */
    unsigned char *page;
    DWORD old_prot;
    DWORD written;
    char marker_path[MAX_PATH];
    char started_path[MAX_PATH];
    HANDLE marker;
    int value = 0;
    int i;

    /* Arithmetic, branches, and a conventional i386 stack call. */
    for (i = 0; i != 9; ++i)
        value = (i & 1) ? stack_add(value, i) : stack_add(value, i + 1);
    if (value != 41) return 10;

    /* RtlEnterCriticalSection ultimately uses the lock-prefixed fast path. */
    {
        CRITICAL_SECTION cs;
        InitializeCriticalSection(&cs);
        for (i = 0; i != 128; ++i)
        {
            EnterCriticalSection(&cs);
            if (InterlockedIncrement(&locked_value) != i + 1)
            {
                LeaveCriticalSection(&cs);
                DeleteCriticalSection(&cs);
                return 11;
            }
            LeaveCriticalSection(&cs);
        }
        DeleteCriticalSection(&cs);
    }

    page = VirtualAlloc(NULL, 0x1000, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!page) return 12;
    CopyMemory(page, code, sizeof(code));
    if (!VirtualProtect(page, 0x1000, PAGE_EXECUTE_READ, &old_prot)) return 13;
    if (((code_fn)page)() != 1) return 14;

    if (!VirtualProtect(page, 0x1000, PAGE_READWRITE, &old_prot)) return 15;
    page[1] = 2; /* self-modify the immediate */
    FlushInstructionCache(GetCurrentProcess(), page, sizeof(code));
    if (!VirtualProtect(page, 0x1000, PAGE_EXECUTE_READ, &old_prot)) return 16;
    if (((code_fn)page)() != 2) return 17;
    if (!VirtualFree(page, 0, MEM_RELEASE)) return 18;

    if (argc != 2 || !argv[1][0]) return 21;
    lstrcpynA(marker_path, argv[1], sizeof(marker_path));
    lstrcpynA(started_path, marker_path, sizeof(started_path));
    lstrcatA(started_path, ".started");
    marker = CreateFileA(started_path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                         FILE_ATTRIBUTE_NORMAL, NULL);
    if (marker == INVALID_HANDLE_VALUE) return 22;
    CloseHandle(marker);
    {
        marker = CreateFileA(marker_path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                             FILE_ATTRIBUTE_NORMAL, NULL);
        if (marker == INVALID_HANDLE_VALUE) return 19;
        if (!WriteFile(marker, message, sizeof(message) - 1, &written, NULL) ||
            written != sizeof(message) - 1)
        {
            CloseHandle(marker);
            return 20;
        }
        CloseHandle(marker);
    }

    if (!WriteFile( GetStdHandle( STD_OUTPUT_HANDLE ), message, sizeof(message) - 1, &written, NULL ))
        return 2;
    return written == sizeof(message) - 1 ? 0 : 3;
}
