#include <windows.h>
#include <stdio.h>

typedef int (WINAPI *wine_dbg_output_fn)(const char *);

int main(void)
{
    HMODULE ntdll = GetModuleHandleA("ntdll.dll");
    wine_dbg_output_fn output = ntdll ? (void *)GetProcAddress(ntdll, "__wine_dbg_output") : NULL;
    fprintf(stderr, "__wine_dbg_output=%p\\n", output);
    if (!output) return 1;
    output("native AArch64 debug output probe\\n");
    return 0;
}
