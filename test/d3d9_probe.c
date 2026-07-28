/* VKMT D3D9 acceptance: native DXVK DLL -> interface -> adapter enumeration. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>

typedef IDirect3D9 *(WINAPI *direct3d_create9_fn)(UINT sdk_version);

int main(void)
{
    D3DADAPTER_IDENTIFIER9 identifier;
    direct3d_create9_fn create9;
    IDirect3D9 *d3d9;
    HMODULE module;
    char module_path[MAX_PATH];
    D3DCAPS9 caps;
    UINT adapters;
    HRESULT hr;

    module = LoadLibraryA("d3d9.dll");
    if (!module)
    {
        fprintf(stderr, "VKMT_D3D9: LoadLibrary failed error=%lu\n",
                GetLastError());
        return 1;
    }

    if (!GetModuleFileNameA(module, module_path, sizeof(module_path)))
        lstrcpyA(module_path, "<unknown>");
    create9 = (direct3d_create9_fn)GetProcAddress(module, "Direct3DCreate9");
    fprintf(stderr, "VKMT_D3D9: module=%s export=%p\n",
            module_path, (void *)create9);
    if (!create9)
    {
        FreeLibrary(module);
        return 2;
    }

    d3d9 = create9(D3D_SDK_VERSION);
    fprintf(stderr, "VKMT_D3D9: Direct3DCreate9 result=%p\n", (void *)d3d9);
    if (!d3d9)
    {
        FreeLibrary(module);
        return 3;
    }

    adapters = d3d9->lpVtbl->GetAdapterCount(d3d9);
    fprintf(stderr, "VKMT_D3D9: adapter_count=%u\n", adapters);
    if (!adapters)
    {
        d3d9->lpVtbl->Release(d3d9);
        FreeLibrary(module);
        return 4;
    }

    ZeroMemory(&identifier, sizeof(identifier));
    hr = d3d9->lpVtbl->GetAdapterIdentifier(d3d9, 0, 0, &identifier);
    fprintf(stderr,
            "VKMT_D3D9: GetAdapterIdentifier hr=%#lx description=%s "
            "vendor=%#lx device=%#lx\n",
            (unsigned long)hr, SUCCEEDED(hr) ? identifier.Description : "<failed>",
            SUCCEEDED(hr) ? identifier.VendorId : 0,
            SUCCEEDED(hr) ? identifier.DeviceId : 0);

    /*
     * Identifier lookup asks Wine's display driver for a monitor name and is
     * therefore not a headless D3D9 loading contract. Keep it observable, but
     * use device caps as the display-independent adapter API gate.
     */
    ZeroMemory(&caps, sizeof(caps));
    hr = d3d9->lpVtbl->GetDeviceCaps(d3d9, 0, D3DDEVTYPE_HAL, &caps);
    fprintf(stderr,
            "VKMT_D3D9: GetDeviceCaps hr=%#lx device_type=%u "
            "vertex_shader=%#lx pixel_shader=%#lx\n",
            (unsigned long)hr, caps.DeviceType,
            (unsigned long)caps.VertexShaderVersion,
            (unsigned long)caps.PixelShaderVersion);

    d3d9->lpVtbl->Release(d3d9);
    FreeLibrary(module);
    if (FAILED(hr))
        return 5;

    puts("VKMT_D3D9_LOAD_ADAPTER_OK");
    return 0;
}
