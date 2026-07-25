// VKMT D3D12 probe: create a D3D12 device under Wine+vkd3d-proton+MoltenVK.
// Prints adapter info and feature levels; exit 0 on success.
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <stdio.h>

int main(void) {
    HRESULT hr;
    IDXGIAdapter1 *adapter = NULL;  /* NULL: vkd3d-proton picks the default Vulkan adapter */

    ID3D12Device *device = NULL;
    hr = D3D12CreateDevice((IUnknown *)adapter, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device);
    printf("D3D12CreateDevice(FL_11_0): 0x%08lx\n", (unsigned long)hr);
    if (FAILED(hr)) return 1;

    D3D12_FEATURE_DATA_FEATURE_LEVELS fl = {0};
    D3D_FEATURE_LEVEL levels[] = { D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_11_1,
                                   D3D_FEATURE_LEVEL_12_0, D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_2 };
    fl.NumFeatureLevels = 5; fl.pFeatureLevelsRequested = levels;
    device->lpVtbl->CheckFeatureSupport(device, D3D12_FEATURE_FEATURE_LEVELS, &fl, sizeof(fl));
    printf("max feature level: 0x%04x\n", fl.MaxSupportedFeatureLevel);

    D3D12_FEATURE_DATA_D3D12_OPTIONS opts = {0};
    device->lpVtbl->CheckFeatureSupport(device, D3D12_FEATURE_D3D12_OPTIONS, &opts, sizeof(opts));
    printf("ResourceBindingTier: %d  TiledResourcesTier: %d  ConservativeRasterizationTier: %d\n",
           opts.ResourceBindingTier, opts.TiledResourcesTier, opts.ConservativeRasterizationTier);

    D3D12_FEATURE_DATA_D3D12_OPTIONS5 o5 = {0};
    if (SUCCEEDED(device->lpVtbl->CheckFeatureSupport(device, D3D12_FEATURE_D3D12_OPTIONS5, &o5, sizeof(o5))))
        printf("RaytracingTier: %d  RenderPassesTier: %d\n", o5.RaytracingTier, o5.RenderPassesTier);

    D3D12_FEATURE_DATA_D3D12_OPTIONS6 o6 = {0};
    if (SUCCEEDED(device->lpVtbl->CheckFeatureSupport(device, D3D12_FEATURE_D3D12_OPTIONS6, &o6, sizeof(o6))))
        printf("VariableShadingRateTier: %d\n", o6.VariableShadingRateTier);

    device->lpVtbl->Release(device);
    printf("PROBE OK\n");
    return 0;
}
