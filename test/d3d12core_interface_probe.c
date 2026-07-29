#define INITGUID
#include <windows.h>
#include <initguid.h>
#include <stdio.h>

DEFINE_GUID(CLSID_VKD3DCore, 0xed53efad, 0xda21, 0x4d96, 0xa1, 0xbc, 0xe7, 0x34, 0xe0, 0x78, 0x87, 0x9c);
DEFINE_GUID(IID_IVKD3DCoreInterface, 0x18da885c, 0xa7b5, 0x464e, 0xa1, 0x21, 0xcc, 0xb7, 0x5d, 0x4d, 0xfc, 0x31);

typedef HRESULT (WINAPI *get_interface_fn)(REFCLSID, REFIID, void **);

int main(void)
{
    HMODULE core = LoadLibraryA("d3d12core.dll");
    get_interface_fn get_interface = core ? (void *)GetProcAddress(core, "D3D12GetInterface") : NULL;
    void *core_interface = NULL;
    fprintf(stderr, "core=%p D3D12GetInterface=%p\\n", core, get_interface);
    fflush(stderr);
    HRESULT hr = get_interface ? get_interface(&CLSID_VKD3DCore, &IID_IVKD3DCoreInterface, &core_interface) : E_FAIL;
    fprintf(stderr, "D3D12GetInterface=%#lx core_interface=%p\\n", (unsigned long)hr, core_interface);
    return SUCCEEDED(hr) && core_interface ? 0 : 1;
}
