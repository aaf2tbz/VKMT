/* Isolate DXMT's ARM64EC D3D11 PE load from device creation. */
#include <windows.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    const char *name = argc > 1 ? argv[1] : "d3d11.dll";
    HMODULE module = LoadLibraryA(name);

    if (!module)
    {
        printf("DXMT LoadLibrary(%s) failed: %lu\n", name, GetLastError());
        return 1;
    }

    if (!lstrcmpiA(name, "d3d11.dll") && !GetProcAddress(module, "D3D11CreateDevice"))
    {
        printf("DXMT d3d11.dll lacks D3D11CreateDevice\n");
        return 2;
    }

    printf("DXMT_ARM64EC_%s_LOAD_OK\n", name);
    FreeLibrary(module);
    return 0;
}
