/* Verify that Wine pairs DXMT's ARM64EC PE thunk with its arm64 Unix driver. */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>

typedef void *(__cdecl *wmt_copy_all_devices_fn)(void);
typedef void (__cdecl *nsobject_release_fn)(void *);
typedef HRESULT (WINAPI *d3d11_create_device_fn)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT,
                                                  const D3D_FEATURE_LEVEL *, UINT, UINT,
                                                  ID3D11Device **, D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);

int main(void)
{
    HMODULE module = LoadLibraryA("winemetal.dll");
    wmt_copy_all_devices_fn copy_all_devices;
    nsobject_release_fn release;
    d3d11_create_device_fn create_device;
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    void *devices;
    HRESULT hr;

    if (!module)
    {
        printf("LoadLibrary(winemetal.dll) failed: %lu\n", GetLastError());
        return 1;
    }

    copy_all_devices = (wmt_copy_all_devices_fn)GetProcAddress(module, "WMTCopyAllDevices");
    release = (nsobject_release_fn)GetProcAddress(module, "NSObject_release");
    if (!copy_all_devices || !release)
    {
        printf("DXMT exports are missing\n");
        return 2;
    }

    devices = copy_all_devices();
    if (!devices)
    {
        printf("WMTCopyAllDevices returned no Metal devices\n");
        return 3;
    }

    release(devices);

    /* Keep the Unix bridge proof independently runnable.  The D3D11 portion
     * exercises a substantially wider DXMT surface and is intentionally a
     * separate gate while that work is being stabilized. */
    if (GetEnvironmentVariableA("VKMT_DXMT_WMT_ONLY", NULL, 0))
    {
        printf("DXMT ARM64EC winemetal.dll / native arm64 bridge passed\n");
        return 0;
    }

    module = LoadLibraryA("d3d11.dll");
    create_device = module ? (d3d11_create_device_fn)GetProcAddress(module, "D3D11CreateDevice") : NULL;
    if (!create_device)
    {
        printf("DXMT d3d11.dll is unavailable\n");
        return 4;
    }
    hr = create_device(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION,
                       &device, NULL, &context);
    if (FAILED(hr))
    {
        printf("DXMT D3D11CreateDevice failed: 0x%08lx\n", (unsigned long)hr);
        return 5;
    }
    ID3D11DeviceContext_Release(context);
    ID3D11Device_Release(device);
    printf("DXMT ARM64EC DLLs and arm64 winemetal.so loaded successfully\n");
    return 0;
}
