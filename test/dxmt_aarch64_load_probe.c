/* First DXMT native-AArch64 boundary: PE thunk load without invoking Metal. */
#include <windows.h>
#include <stdio.h>

int main(void)
{
    HMODULE module = LoadLibraryA("winemetal.dll");

    if (!module)
    {
        printf("LoadLibrary(winemetal.dll) failed: %lu\n", GetLastError());
        return 1;
    }
    if (!GetProcAddress(module, "WMTCopyAllDevices") ||
        !GetProcAddress(module, "NSObject_release"))
    {
        printf("DXMT required exports are missing\n");
        return 2;
    }
    printf("DXMT AArch64 PE winemetal.dll load/export gate passed\n");
    return 0;
}
