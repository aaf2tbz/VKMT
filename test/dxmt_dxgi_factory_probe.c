/* Pin the first executable DXMT ARM64EC boundary: DXGI factory creation. */
#define COBJMACROS
#include <windows.h>
#include <dxgi.h>
#include <stdio.h>

typedef HRESULT (WINAPI *create_dxgi_factory1_fn)(REFIID riid, void **factory);

int main(void)
{
    HMODULE module = LoadLibraryA("dxgi.dll");
    create_dxgi_factory1_fn create_factory;
    IDXGIFactory1 *factory = NULL;
    IDXGIAdapter1 *adapter = NULL;
    HRESULT hr;

    if (!module)
    {
        printf("DXMT LoadLibrary(dxgi.dll) failed: %lu\n", GetLastError());
        return 1;
    }
    create_factory = (create_dxgi_factory1_fn)GetProcAddress(module, "CreateDXGIFactory1");
    if (!create_factory)
    {
        printf("DXMT dxgi.dll lacks CreateDXGIFactory1\n");
        return 2;
    }

    hr = create_factory(&IID_IDXGIFactory1, (void **)&factory);
    if (FAILED(hr))
    {
        printf("DXMT CreateDXGIFactory1 failed: 0x%08lx\n", (unsigned long)hr);
        return 3;
    }
    hr = IDXGIFactory1_EnumAdapters1(factory, 0, &adapter);
    if (FAILED(hr))
    {
        printf("DXMT EnumAdapters1 failed: 0x%08lx\n", (unsigned long)hr);
        IDXGIFactory1_Release(factory);
        return 4;
    }
    IDXGIAdapter1_Release(adapter);
    IDXGIFactory1_Release(factory);
    printf("DXMT_ARM64EC_DXGI_FACTORY_OK\n");
    return 0;
}
