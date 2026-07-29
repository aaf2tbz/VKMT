/* Prints the actual i386 DLL route used by the Phase 5 graphics gates. */
#include <windows.h>
#include <stdio.h>

static int report_module(const char *name)
{
    HMODULE module = LoadLibraryA(name);
    char path[MAX_PATH];

    if (!module)
    {
        fprintf(stderr, "P5_ROUTE_FAIL %s error=%lu\n", name, GetLastError());
        return 1;
    }
    if (!GetModuleFileNameA(module, path, sizeof(path)))
    {
        fprintf(stderr, "P5_ROUTE_FAIL %s path_error=%lu\n", name, GetLastError());
        return 1;
    }
    printf("P5_ROUTE %s %s\n", name, path);
    return 0;
}

int main(void)
{
    int failed = 0;

    failed |= report_module("dxgi.dll");
    failed |= report_module("d3d11.dll");
    failed |= report_module("d3d12.dll");
    failed |= report_module("d3d12core.dll");
    if (failed) return 1;
    puts("P5_I386_ROUTE_OK");
    return 0;
}
