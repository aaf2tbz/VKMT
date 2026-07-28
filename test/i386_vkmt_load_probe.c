#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

struct module_export
{
    const char *module;
    const char *symbol;
    const char *marker;
};

static HANDLE marker = INVALID_HANDLE_VALUE;
static LONG exception_recorded;

static void write_marker(const char *text)
{
    DWORD written;
    WriteFile(marker, text, lstrlenA(text), &written, NULL);
    WriteFile(marker, "\r\n", 2, &written, NULL);
    FlushFileBuffers(marker);
}

static LONG CALLBACK record_first_d3d12core_exception(EXCEPTION_POINTERS *pointers)
{
    HMODULE core = GetModuleHandleA("d3d12core.dll");
    MEMORY_BASIC_INFORMATION memory;
    char fault_module[MAX_PATH] = "<unknown>";
    DWORD instruction[4];
    char line[1024];
    int length;

    if (!core || InterlockedCompareExchange(&exception_recorded, 1, 0))
        return EXCEPTION_CONTINUE_SEARCH;

    ZeroMemory(&memory, sizeof(memory));
    VirtualQuery((const void *)(ULONG_PTR)pointers->ContextRecord->Eip,
                 &memory, sizeof(memory));
    if (memory.AllocationBase)
        GetModuleFileNameA((HMODULE)memory.AllocationBase, fault_module,
                           sizeof(fault_module));
    CopyMemory(instruction,
               (const void *)(ULONG_PTR)(pointers->ContextRecord->Eip - 8),
               sizeof(instruction));

    length = _snprintf(line, sizeof(line),
            "P5_I386_EXCEPTION code=%08lX core=%08lX owner=%08lX module=%s "
            "eip=%08lX bytes=%08lX,%08lX,%08lX,%08lX esp=%08lX "
            "eax=%08lX ecx=%08lX edx=%08lX ebx=%08lX esi=%08lX edi=%08lX "
            "count=%lu info0=%08lX info1=%08lX info2=%08lX info3=%08lX "
            "info4=%08lX info5=%08lX info6=%08lX info7=%08lX info8=%08lX "
            "info9=%08lX info10=%08lX info11=%08lX info12=%08lX "
            "info13=%08lX info14=%08lX\r\n",
            pointers->ExceptionRecord->ExceptionCode, (DWORD)(ULONG_PTR)core,
            (DWORD)(ULONG_PTR)memory.AllocationBase, fault_module,
            pointers->ContextRecord->Eip,
            instruction[0], instruction[1], instruction[2], instruction[3],
            pointers->ContextRecord->Esp,
            pointers->ContextRecord->Eax, pointers->ContextRecord->Ecx,
            pointers->ContextRecord->Edx, pointers->ContextRecord->Ebx,
            pointers->ContextRecord->Esi, pointers->ContextRecord->Edi,
            pointers->ExceptionRecord->NumberParameters,
            pointers->ExceptionRecord->NumberParameters > 0 ?
                    (DWORD)pointers->ExceptionRecord->ExceptionInformation[0] : 0,
            pointers->ExceptionRecord->NumberParameters > 1 ?
                    (DWORD)pointers->ExceptionRecord->ExceptionInformation[1] : 0,
            (DWORD)pointers->ExceptionRecord->ExceptionInformation[2],
            (DWORD)pointers->ExceptionRecord->ExceptionInformation[3],
            (DWORD)pointers->ExceptionRecord->ExceptionInformation[4],
            (DWORD)pointers->ExceptionRecord->ExceptionInformation[5],
            (DWORD)pointers->ExceptionRecord->ExceptionInformation[6],
            (DWORD)pointers->ExceptionRecord->ExceptionInformation[7],
            (DWORD)pointers->ExceptionRecord->ExceptionInformation[8],
            (DWORD)pointers->ExceptionRecord->ExceptionInformation[9],
            (DWORD)pointers->ExceptionRecord->ExceptionInformation[10],
            (DWORD)pointers->ExceptionRecord->ExceptionInformation[11],
            (DWORD)pointers->ExceptionRecord->ExceptionInformation[12],
            (DWORD)pointers->ExceptionRecord->ExceptionInformation[13],
            (DWORD)pointers->ExceptionRecord->ExceptionInformation[14]);
    if (length > 0)
    {
        DWORD written;
        WriteFile(marker, line, length < sizeof(line) ? length : sizeof(line), &written, NULL);
        FlushFileBuffers(marker);
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

int main(int argc, char **argv)
{
    static const struct module_export gates[] =
    {
        {"d3d12.dll", "D3D12CreateDevice", "P5_I386_D3D12_DLL_LOAD_OK"},
        {"d3d12core.dll", "D3D12GetInterface", "P5_I386_D3D12CORE_DLL_LOAD_OK"},
        {"dxgi.dll", "CreateDXGIFactory1", "P5_I386_DXGI_DLL_LOAD_OK"},
        {"d3d11.dll", "D3D11CreateDevice", "P5_I386_D3D11_DLL_LOAD_OK"},
    };
    unsigned int i;

    if (argc != 2) return 20;
    marker = CreateFileA(argv[1], GENERIC_WRITE, FILE_SHARE_READ, NULL,
                         CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (marker == INVALID_HANDLE_VALUE) return 21;
    AddVectoredExceptionHandler(1, record_first_d3d12core_exception);

    for (i = 0; i < sizeof(gates) / sizeof(gates[0]); ++i)
    {
        fprintf(stderr, "P5 loading %s!%s\n", gates[i].module, gates[i].symbol);
        fflush(stderr);
        HMODULE module = LoadLibraryA(gates[i].module);
        FARPROC symbol = module ? GetProcAddress(module, gates[i].symbol) : NULL;
        if (!module || !symbol)
        {
            fprintf(stderr, "P5 load failed: %s!%s module=%p symbol=%p error=%lu\n",
                    gates[i].module, gates[i].symbol, module, symbol, GetLastError());
            write_marker("P5_I386_DLL_LOAD_FAILED");
            CloseHandle(marker);
            return i + 1;
        }
        write_marker(gates[i].marker);
    }
    write_marker("P5_I386_DLL_LOAD_DONE");
    CloseHandle(marker);
    return 0;
}
