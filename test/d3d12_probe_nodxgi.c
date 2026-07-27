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

    /* Run one deterministic GPU copy through a direct queue and read it back.
     * This is deliberately no-DXGI: it isolates the vkd3d-proton/Vulkan/Metal
     * contract from DXGI routing while proving command submission, resource
     * transitions, fence completion, and mapped readback. */
    ID3D12CommandQueue *queue = NULL;
    ID3D12CommandAllocator *allocator = NULL;
    ID3D12GraphicsCommandList *list = NULL;
    ID3D12Resource *upload = NULL, *gpu = NULL, *readback = NULL;
    ID3D12Fence *fence = NULL;
    HANDLE event = NULL;
    D3D12_COMMAND_QUEUE_DESC queue_desc = {0};
    D3D12_HEAP_PROPERTIES heap = {0};
    D3D12_RESOURCE_DESC buffer = {0};
    D3D12_RESOURCE_BARRIER barrier = {0};
    const UINT32 expected = 0x4b4d5456u; /* "VKMT" little-endian */
    void *mapped = NULL;

    queue_desc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    buffer.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    buffer.Width = 256;
    buffer.Height = 1;
    buffer.DepthOrArraySize = 1;
    buffer.MipLevels = 1;
    buffer.SampleDesc.Count = 1;
    buffer.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;

    hr = device->lpVtbl->CreateCommandQueue(device, &queue_desc, &IID_ID3D12CommandQueue, (void **)&queue);
    fprintf(stderr, "VKMT_COPY: CreateCommandQueue hr=%#lx\n", (unsigned long)hr);
    if (SUCCEEDED(hr)) hr = device->lpVtbl->CreateCommandAllocator(device, D3D12_COMMAND_LIST_TYPE_DIRECT,
            &IID_ID3D12CommandAllocator, (void **)&allocator);
    fprintf(stderr, "VKMT_COPY: CreateCommandAllocator hr=%#lx\n", (unsigned long)hr);
    heap.Type = D3D12_HEAP_TYPE_UPLOAD;
    if (SUCCEEDED(hr)) hr = device->lpVtbl->CreateCommittedResource(device, &heap, D3D12_HEAP_FLAG_NONE,
            &buffer, D3D12_RESOURCE_STATE_GENERIC_READ, NULL, &IID_ID3D12Resource, (void **)&upload);
    fprintf(stderr, "VKMT_COPY: CreateUpload hr=%#lx\n", (unsigned long)hr);
    heap.Type = D3D12_HEAP_TYPE_DEFAULT;
    if (SUCCEEDED(hr)) hr = device->lpVtbl->CreateCommittedResource(device, &heap, D3D12_HEAP_FLAG_NONE,
            &buffer, D3D12_RESOURCE_STATE_COPY_DEST, NULL, &IID_ID3D12Resource, (void **)&gpu);
    fprintf(stderr, "VKMT_COPY: CreateDefault hr=%#lx\n", (unsigned long)hr);
    heap.Type = D3D12_HEAP_TYPE_READBACK;
    if (SUCCEEDED(hr)) hr = device->lpVtbl->CreateCommittedResource(device, &heap, D3D12_HEAP_FLAG_NONE,
            &buffer, D3D12_RESOURCE_STATE_COPY_DEST, NULL, &IID_ID3D12Resource, (void **)&readback);
    fprintf(stderr, "VKMT_COPY: CreateReadback hr=%#lx\n", (unsigned long)hr);
    if (SUCCEEDED(hr)) hr = upload->lpVtbl->Map(upload, 0, NULL, &mapped);
    fprintf(stderr, "VKMT_COPY: MapUpload hr=%#lx\n", (unsigned long)hr);
    if (SUCCEEDED(hr)) {
        *(UINT32 *)mapped = expected;
        upload->lpVtbl->Unmap(upload, 0, NULL);
        hr = device->lpVtbl->CreateCommandList(device, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator,
                NULL, &IID_ID3D12GraphicsCommandList, (void **)&list);
        fprintf(stderr, "VKMT_COPY: CreateCommandList hr=%#lx\n", (unsigned long)hr);
    }
    if (SUCCEEDED(hr)) {
        list->lpVtbl->CopyBufferRegion(list, gpu, 0, upload, 0, sizeof(expected));
        barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        barrier.Transition.pResource = gpu;
        barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_DEST;
        barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
        barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        list->lpVtbl->ResourceBarrier(list, 1, &barrier);
        list->lpVtbl->CopyBufferRegion(list, readback, 0, gpu, 0, sizeof(expected));
        hr = list->lpVtbl->Close(list);
        fprintf(stderr, "VKMT_COPY: Close hr=%#lx\n", (unsigned long)hr);
    }
    if (SUCCEEDED(hr)) {
        ID3D12CommandList *lists[] = {(ID3D12CommandList *)list};
        queue->lpVtbl->ExecuteCommandLists(queue, 1, lists);
        fprintf(stderr, "VKMT_COPY: ExecuteCommandLists returned\n");
        hr = device->lpVtbl->CreateFence(device, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void **)&fence);
        fprintf(stderr, "VKMT_COPY: CreateFence hr=%#lx\n", (unsigned long)hr);
    }
    if (SUCCEEDED(hr)) hr = queue->lpVtbl->Signal(queue, fence, 1);
    fprintf(stderr, "VKMT_COPY: Signal hr=%#lx\n", (unsigned long)hr);
    if (SUCCEEDED(hr) && fence->lpVtbl->GetCompletedValue(fence) < 1) {
        event = CreateEventW(NULL, FALSE, FALSE, NULL);
        if (!event || FAILED(hr = fence->lpVtbl->SetEventOnCompletion(fence, 1, event)) ||
                WaitForSingleObject(event, 10000) != WAIT_OBJECT_0)
            hr = E_FAIL;
    }
    if (SUCCEEDED(hr)) hr = readback->lpVtbl->Map(readback, 0, NULL, &mapped);
    fprintf(stderr, "VKMT_COPY: MapReadback hr=%#lx\n", (unsigned long)hr);
    if (SUCCEEDED(hr)) {
        if (*(UINT32 *)mapped != expected) hr = E_FAIL;
        readback->lpVtbl->Unmap(readback, 0, NULL);
    }
    printf("queue/copy/fence/readback: 0x%08lx\n", (unsigned long)hr);
    if (event) CloseHandle(event);
    if (fence) fence->lpVtbl->Release(fence);
    if (list) list->lpVtbl->Release(list);
    if (readback) readback->lpVtbl->Release(readback);
    if (gpu) gpu->lpVtbl->Release(gpu);
    if (upload) upload->lpVtbl->Release(upload);
    if (allocator) allocator->lpVtbl->Release(allocator);
    if (queue) queue->lpVtbl->Release(queue);
    if (FAILED(hr)) { device->lpVtbl->Release(device); return 1; }

    device->lpVtbl->Release(device);
    printf("PROBE OK\n");
    return 0;
}
