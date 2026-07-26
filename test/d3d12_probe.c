// VKMT D3D12 probe: create a D3D12 device under Wine+vkd3d-proton+MoltenVK.
// Prints adapter info and feature levels; exit 0 on success.
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <stdio.h>

int main(void) {
    HRESULT hr;
    IDXGIFactory4 *factory = NULL;
    hr = CreateDXGIFactory1(&IID_IDXGIFactory4, (void **)&factory);
    printf("CreateDXGIFactory1: 0x%08lx\n", (unsigned long)hr);
    if (FAILED(hr)) return 1;

    IDXGIAdapter1 *adapter = NULL;
    for (UINT i = 0; factory->lpVtbl->EnumAdapters1(factory, i, &adapter) != DXGI_ERROR_NOT_FOUND; i++) {
        DXGI_ADAPTER_DESC1 d;
        adapter->lpVtbl->GetDesc1(adapter, &d);
        printf("adapter %u: %ls (VID:%04x PID:%04x)\n", i, d.Description, d.VendorId, d.DeviceId);
    }

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

    /* M4: submit real GPU work without needing a window.  Clearing a small
     * offscreen render target exercises command creation, descriptor setup,
     * queue submission and fence completion through vkd3d-proton/VKMT. */
    D3D12_COMMAND_QUEUE_DESC qdesc = {0};
    qdesc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    ID3D12CommandQueue *queue = NULL;
    ID3D12CommandAllocator *allocator = NULL;
    ID3D12GraphicsCommandList *list = NULL;
    ID3D12DescriptorHeap *rtv_heap = NULL;
    ID3D12Resource *target = NULL;
    ID3D12Fence *fence = NULL;
    HANDLE fence_event = NULL;
    D3D12_HEAP_PROPERTIES heap = {0};
    D3D12_RESOURCE_DESC target_desc = {0};
    D3D12_CLEAR_VALUE clear = {0};
    D3D12_CPU_DESCRIPTOR_HANDLE rtv;
    const float color[4] = { 0.08f, 0.25f, 0.60f, 1.0f };

    heap.Type = D3D12_HEAP_TYPE_DEFAULT;
    target_desc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    target_desc.Width = 64;
    target_desc.Height = 64;
    target_desc.DepthOrArraySize = 1;
    target_desc.MipLevels = 1;
    target_desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    target_desc.SampleDesc.Count = 1;
    target_desc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
    target_desc.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    clear.Format = target_desc.Format;
    clear.Color[0] = color[0]; clear.Color[1] = color[1];
    clear.Color[2] = color[2]; clear.Color[3] = color[3];

    hr = device->lpVtbl->CreateCommandQueue(device, &qdesc, &IID_ID3D12CommandQueue, (void **)&queue);
    if (SUCCEEDED(hr)) hr = device->lpVtbl->CreateCommandAllocator(device, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                                                     &IID_ID3D12CommandAllocator, (void **)&allocator);
    if (SUCCEEDED(hr)) hr = device->lpVtbl->CreateCommittedResource(device, &heap, D3D12_HEAP_FLAG_NONE,
        &target_desc, D3D12_RESOURCE_STATE_RENDER_TARGET, &clear, &IID_ID3D12Resource, (void **)&target);
    if (SUCCEEDED(hr)) {
        D3D12_DESCRIPTOR_HEAP_DESC desc = { D3D12_DESCRIPTOR_HEAP_TYPE_RTV, 1, D3D12_DESCRIPTOR_HEAP_FLAG_NONE, 0 };
        hr = device->lpVtbl->CreateDescriptorHeap(device, &desc, &IID_ID3D12DescriptorHeap, (void **)&rtv_heap);
    }
    if (SUCCEEDED(hr)) hr = device->lpVtbl->CreateCommandList(device, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator,
                                                                NULL, &IID_ID3D12GraphicsCommandList, (void **)&list);
    if (SUCCEEDED(hr)) {
        rtv_heap->lpVtbl->GetCPUDescriptorHandleForHeapStart(rtv_heap, &rtv);
        device->lpVtbl->CreateRenderTargetView(device, target, NULL, rtv);
        list->lpVtbl->ClearRenderTargetView(list, rtv, color, 0, NULL);
        hr = list->lpVtbl->Close(list);
    }
    if (SUCCEEDED(hr)) {
        ID3D12CommandList *lists[] = { (ID3D12CommandList *)list };
        queue->lpVtbl->ExecuteCommandLists(queue, 1, lists);
        hr = device->lpVtbl->CreateFence(device, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void **)&fence);
    }
    if (SUCCEEDED(hr)) hr = queue->lpVtbl->Signal(queue, fence, 1);
    if (SUCCEEDED(hr) && fence->lpVtbl->GetCompletedValue(fence) < 1) {
        fence_event = CreateEventW(NULL, FALSE, FALSE, NULL);
        if (!fence_event || FAILED(hr = fence->lpVtbl->SetEventOnCompletion(fence, 1, fence_event)) ||
            WaitForSingleObject(fence_event, 10000) != WAIT_OBJECT_0) hr = E_FAIL;
    }
    printf("offscreen clear/submit: 0x%08lx\n", (unsigned long)hr);
    if (fence_event) CloseHandle(fence_event);
    if (fence) fence->lpVtbl->Release(fence);
    if (list) list->lpVtbl->Release(list);
    if (rtv_heap) rtv_heap->lpVtbl->Release(rtv_heap);
    if (target) target->lpVtbl->Release(target);
    if (allocator) allocator->lpVtbl->Release(allocator);
    if (queue) queue->lpVtbl->Release(queue);
    if (FAILED(hr)) { device->lpVtbl->Release(device); return 1; }

    device->lpVtbl->Release(device);
    printf("PROBE OK\n");
    return 0;
}
