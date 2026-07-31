typedef unsigned long DWORD;
typedef unsigned long ULONG_PTR;
typedef long LONG;
typedef void *HANDLE;

typedef struct _EXCEPTION_RECORD
{
    DWORD ExceptionCode;
    DWORD ExceptionFlags;
    struct _EXCEPTION_RECORD *ExceptionRecord;
    void *ExceptionAddress;
    DWORD NumberParameters;
    ULONG_PTR ExceptionInformation[15];
} EXCEPTION_RECORD;

typedef struct _EXCEPTION_POINTERS
{
    EXCEPTION_RECORD *ExceptionRecord;
    void *ContextRecord;
} EXCEPTION_POINTERS;

__declspec(dllimport) void __stdcall ExitProcess(DWORD code);
__declspec(dllimport) HANDLE __stdcall GetStdHandle(DWORD id);
__declspec(dllimport) int __stdcall WriteFile(HANDLE file, const void *buffer,
                                              DWORD size, DWORD *written,
                                              void *overlapped);
void *__cdecl _exception_info(void);

#define EXCEPTION_ACCESS_VIOLATION ((DWORD)0xc0000005)
#define EXCEPTION_CONTINUE_SEARCH 0
#define EXCEPTION_EXECUTE_HANDLER 1
#define STD_OUTPUT_HANDLE ((DWORD)-11)

static volatile LONG filter_calls;
static volatile LONG address_ok;

static LONG filter(EXCEPTION_POINTERS *ptrs)
{
    EXCEPTION_RECORD *record = ptrs->ExceptionRecord;

    ++filter_calls;
    address_ok = record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION &&
                 record->NumberParameters >= 2 &&
                 record->ExceptionInformation[1] == 0;
    return address_ok ? EXCEPTION_EXECUTE_HANDLER : EXCEPTION_CONTINUE_SEARCH;
}

void mainCRTStartup(void)
{
    static const char ok[] = "I386_MSVC_SEH_OK\r\n";
    static const char fail[] = "I386_MSVC_SEH_FAIL\r\n";
    volatile LONG handler_ran = 0;
    DWORD written;

    __try
    {
        *(volatile DWORD *)(ULONG_PTR)0 = 0x564b4d54;
    }
    __except (filter((EXCEPTION_POINTERS *)_exception_info()))
    {
        handler_ran = 1;
    }

    if (filter_calls == 1 && address_ok && handler_ran)
    {
        WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), ok, sizeof(ok) - 1,
                  &written, 0);
        ExitProcess(0);
    }

    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), fail, sizeof(fail) - 1,
              &written, 0);
    ExitProcess(3);
}
