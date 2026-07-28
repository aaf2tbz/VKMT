#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <initguid.h>
#include <dxgi1_4.h>
#include <stdio.h>

typedef HRESULT (WINAPI *create_dxgi_factory1_fn)(REFIID, void **);

static LONG exception_recorded;

static LONG CALLBACK record_first_exception(EXCEPTION_POINTERS *pointers)
{
    EXCEPTION_RECORD *record = pointers->ExceptionRecord;

    if (InterlockedCompareExchange(&exception_recorded, 1, 0))
        return EXCEPTION_CONTINUE_SEARCH;
    fprintf(stderr, "P5 DXGI exception code=%08lX eip=%08lX esp=%08lX count=%lu",
            record->ExceptionCode, pointers->ContextRecord->Eip,
            pointers->ContextRecord->Esp, record->NumberParameters);
    for (DWORD i = 0; i < record->NumberParameters && i < 15; ++i)
        fprintf(stderr, " info%lu=%08lX", i,
                (DWORD)record->ExceptionInformation[i]);
    fputc('\n', stderr);
    fflush(stderr);
    return EXCEPTION_CONTINUE_SEARCH;
}

int main(void)
{
    HMODULE module;
    create_dxgi_factory1_fn create_factory;
    IDXGIFactory1 *factory = NULL;
    IDXGIAdapter1 *adapter = NULL;
    DXGI_ADAPTER_DESC1 desc;
    HRESULT hr;

    AddVectoredExceptionHandler(1, record_first_exception);
    fputs("P5 DXGI probe entered main\n", stderr);
    fflush(stderr);
    module = LoadLibraryA("dxgi.dll");
    fprintf(stderr, "P5 DXGI LoadLibrary module=%p error=%lu\n", module, GetLastError());
    fflush(stderr);
    if (!module) return 1;
    create_factory = (create_dxgi_factory1_fn)GetProcAddress(module, "CreateDXGIFactory1");
    fprintf(stderr, "P5 DXGI GetProcAddress CreateDXGIFactory1=%p error=%lu\n",
            create_factory, GetLastError());
    fflush(stderr);
    if (!create_factory) return 2;
    hr = create_factory(&IID_IDXGIFactory1, (void **)&factory);
    fprintf(stderr, "P5 DXGI CreateDXGIFactory1 hr=%#lx\n", (unsigned long)hr);
    if (FAILED(hr)) return 3;
    puts("P5_I386_DXGI_FACTORY_OK");

    hr = IDXGIFactory1_EnumAdapters1(factory, 0, &adapter);
    fprintf(stderr, "P5 DXGI EnumAdapters1 hr=%#lx\n", (unsigned long)hr);
    if (FAILED(hr))
    {
        IDXGIFactory1_Release(factory);
        return 4;
    }
    ZeroMemory(&desc, sizeof(desc));
    hr = IDXGIAdapter1_GetDesc1(adapter, &desc);
    fprintf(stderr, "P5 DXGI GetDesc1 hr=%#lx vendor=%#x device=%#x\n",
            (unsigned long)hr, desc.VendorId, desc.DeviceId);
    IDXGIAdapter1_Release(adapter);
    IDXGIFactory1_Release(factory);
    if (FAILED(hr) || !desc.Description[0]) return 5;
    puts("P5_I386_DXGI_ADAPTER_OK");
    return 0;
}
