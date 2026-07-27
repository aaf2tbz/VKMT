/* Isolate DXMT's ARM64EC D3D11 PE load from device creation. */
#include <windows.h>
#include <stdio.h>

int main(void)
{
    HMODULE module = LoadLibraryA("d3d11.dll");

    if (!module)
    {
        printf("DXMT LoadLibrary(d3d11.dll) failed: %lu\n", GetLastError());
        return 1;
    }

    if (!GetProcAddress(module, "D3D11CreateDevice"))
    {
        printf("DXMT d3d11.dll lacks D3D11CreateDevice\n");
        return 2;
    }

    printf("DXMT_ARM64EC_D3D11_LOAD_OK\n");
    FreeLibrary(module);
    return 0;
}
