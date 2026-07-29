#include <windows.h>
#include <stdio.h>

int main(void)
{
    HMODULE library = LoadLibraryA("d3d12.dll");
    fprintf(stderr, "LoadLibrary(d3d12.dll)=%p error=%lu\n", library, GetLastError());
    return library ? 0 : 1;
}
