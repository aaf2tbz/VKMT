/* Isolate i386 D3D12 queue timeline signaling from command-buffer submission. */
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d12.h>
#include <stdio.h>

static DWORD module_image_size(HMODULE module)
{
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)module;
    IMAGE_NT_HEADERS32 *nt = (IMAGE_NT_HEADERS32 *)((BYTE *)module + dos->e_lfanew);
    return nt->OptionalHeader.SizeOfImage;
}

static HANDLE delayed_worker_event;
static HANDLE delayed_worker_ready;
static HANDLE delayed_worker_gate;

static DWORD WINAPI delayed_event_worker(void *unused)
{
    HANDLE event;
    (void)unused;
    SetEvent(delayed_worker_ready);
    if (WaitForSingleObject(delayed_worker_gate, INFINITE) != WAIT_OBJECT_0) return GetLastError();
    event = delayed_worker_event;
    return SetEvent(event) ? 0x71 : GetLastError();
}

int main(void)
{
    HMODULE forced_d3d12;
    ID3D12Device *device = NULL;
    ID3D12CommandQueue *queue = NULL;
    ID3D12Fence *fence = NULL;
    D3D12_COMMAND_QUEUE_DESC desc = {0};
    HANDLE event = NULL;
    HANDLE delayed_ready = NULL, delayed_gate = NULL, delayed_event = NULL, delayed_thread = NULL;
    HRESULT hr;
    DWORD wait_result;
    char module_path[MAX_PATH];

    if (GetEnvironmentVariableA("VKMT_FORCE_SYSWOW64", module_path, sizeof(module_path)))
    {
        forced_d3d12 = LoadLibraryA("C:\\windows\\syswow64\\d3d12.dll");
        fprintf(stderr, "QUEUE_FENCE: ForceSyswow64=%p image=%#lx error=%lu\n",
                forced_d3d12, forced_d3d12 ? (unsigned long)module_image_size(forced_d3d12) : 0,
                GetLastError());
        if (!forced_d3d12) return 2;
    }

    hr = D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device);
    fprintf(stderr, "QUEUE_FENCE: CreateDevice=%#lx\n", (unsigned long)hr);
    if (FAILED(hr)) return 1;

    if (GetModuleFileNameA(GetModuleHandleA("d3d12.dll"), module_path, sizeof(module_path)))
        fprintf(stderr, "QUEUE_FENCE: d3d12=%s image=%#lx\n", module_path,
                (unsigned long)module_image_size(GetModuleHandleA("d3d12.dll")));
    if (GetModuleFileNameA(GetModuleHandleA("d3d12core.dll"), module_path, sizeof(module_path)))
        fprintf(stderr, "QUEUE_FENCE: d3d12core=%p %s image=%#lx\n", GetModuleHandleA("d3d12core.dll"), module_path,
                (unsigned long)module_image_size(GetModuleHandleA("d3d12core.dll")));

    desc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    hr = ID3D12Device_CreateCommandQueue(device, &desc, &IID_ID3D12CommandQueue, (void **)&queue);
    fprintf(stderr, "QUEUE_FENCE: CreateCommandQueue=%#lx\n", (unsigned long)hr);
    if (SUCCEEDED(hr)) hr = ID3D12Device_CreateFence(device, 0, D3D12_FENCE_FLAG_NONE,
            &IID_ID3D12Fence, (void **)&fence);
    fprintf(stderr, "QUEUE_FENCE: CreateFence=%#lx\n", (unsigned long)hr);
    if (SUCCEEDED(hr))
    {
        DWORD delayed_wait, delayed_code = 0;
        delayed_ready = CreateEventW(NULL, TRUE, FALSE, NULL);
        delayed_gate = CreateEventW(NULL, TRUE, FALSE, NULL);
        delayed_worker_gate = delayed_gate;
        delayed_thread = delayed_ready && delayed_gate ? CreateThread(NULL, 0, delayed_event_worker, NULL, 0, NULL) : NULL;
        delayed_wait = delayed_thread ? WaitForSingleObject(delayed_ready, 5000) : WAIT_FAILED;
        delayed_event = CreateEventW(NULL, FALSE, FALSE, NULL);
        delayed_worker_event = delayed_event;
        if (delayed_gate) SetEvent(delayed_gate);
        delayed_wait = delayed_event ? WaitForSingleObject(delayed_event, 5000) : WAIT_FAILED;
        if (delayed_thread) { WaitForSingleObject(delayed_thread, 5000); GetExitCodeThread(delayed_thread, &delayed_code); }
        fprintf(stderr, "QUEUE_FENCE: DelayedWorker event=%p wait=%#lx code=%#lx error=%lu\n",
                delayed_event, (unsigned long)delayed_wait, (unsigned long)delayed_code, GetLastError());
        if (delayed_thread) CloseHandle(delayed_thread);
        if (delayed_ready) CloseHandle(delayed_ready);
        if (delayed_gate) CloseHandle(delayed_gate);
        if (delayed_event) CloseHandle(delayed_event);
    }
    if (SUCCEEDED(hr)) hr = ID3D12CommandQueue_Signal(queue, fence, 1);
    fprintf(stderr, "QUEUE_FENCE: Signal=%#lx\n", (unsigned long)hr);
    if (SUCCEEDED(hr))
        fprintf(stderr, "QUEUE_FENCE: PostSignalCompleted=%llu\n",
                (unsigned long long)ID3D12Fence_GetCompletedValue(fence));

    if (SUCCEEDED(hr) && ID3D12Fence_GetCompletedValue(fence) < 1)
    {
        event = CreateEventW(NULL, FALSE, FALSE, NULL);
        if (event)
        {
            BOOL set = SetEvent(event);
            DWORD preflight_wait = WaitForSingleObject(event, 0);
            fprintf(stderr, "QUEUE_FENCE: EventPreflight handle=%p set=%d wait=%#lx error=%lu\n",
                    event, set, (unsigned long)preflight_wait, GetLastError());
        }
        hr = event ? ID3D12Fence_SetEventOnCompletion(fence, 1, event) : E_FAIL;
        if (event)
        {
            DWORD flags = 0;
            BOOL valid = GetHandleInformation(event, &flags);
            fprintf(stderr, "QUEUE_FENCE: PostRegisterEvent handle=%p valid=%d flags=%#lx error=%lu\n",
                    event, valid, (unsigned long)flags, GetLastError());
        }
        wait_result = SUCCEEDED(hr) ? WaitForSingleObject(event, 10000) : WAIT_FAILED;
        fprintf(stderr, "QUEUE_FENCE: SetEvent=%#lx Wait=%#lx\n",
                (unsigned long)hr, (unsigned long)wait_result);
        if (wait_result != WAIT_OBJECT_0) hr = E_FAIL;
    }
    fprintf(stderr, "QUEUE_FENCE: Completed=%llu final=%#lx\n",
            (unsigned long long)ID3D12Fence_GetCompletedValue(fence), (unsigned long)hr);

    if (event) CloseHandle(event);
    if (fence) ID3D12Fence_Release(fence);
    if (queue) ID3D12CommandQueue_Release(queue);
    ID3D12Device_Release(device);
    return FAILED(hr);
}
