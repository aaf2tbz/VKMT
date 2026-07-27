/* Exercise DXMT DXGI through an ARM64EC import, as a normal client does. */
#define COBJMACROS
#include <windows.h>
#include <dxgi.h>
#include <stdio.h>

int main(void)
{
    IDXGIFactory1 *factory = NULL;
    IDXGIAdapter1 *adapter = NULL;
    HRESULT hr;

    hr = CreateDXGIFactory1(&IID_IDXGIFactory1, (void **)&factory);
    if (FAILED(hr))
    {
        printf("DXMT imported CreateDXGIFactory1 failed: 0x%08lx\n", (unsigned long)hr);
        return 1;
    }
    printf("DXMT factory vtable: EnumAdapters1=%p Release=%p\n",
           factory->lpVtbl->EnumAdapters1, factory->lpVtbl->Release);
    if (GetEnvironmentVariableA("DXMT_DXGI_FACTORY_ONLY", NULL, 0))
    {
        /* The process owns the reference until clean process teardown. This
         * makes the export/import boundary independently observable before
         * exercising COM vtable calls in the next gate. */
        printf("DXMT_ARM64EC_DXGI_IMPORT_FACTORY_ONLY_OK\n");
        return 0;
    }
    if (GetEnvironmentVariableA("DXMT_DXGI_FACTORY_RELEASE_ONLY", NULL, 0))
    {
        IDXGIFactory1_Release(factory);
        printf("DXMT_ARM64EC_DXGI_IMPORT_FACTORY_RELEASE_OK\n");
        return 0;
    }
    hr = IDXGIFactory1_EnumAdapters1(factory, 0, &adapter);
    if (FAILED(hr))
    {
        printf("DXMT imported EnumAdapters1 failed: 0x%08lx\n", (unsigned long)hr);
        IDXGIFactory1_Release(factory);
        return 2;
    }
    IDXGIAdapter1_Release(adapter);
    IDXGIFactory1_Release(factory);
    printf("DXMT_ARM64EC_DXGI_IMPORT_FACTORY_OK\n");
    return 0;
}
