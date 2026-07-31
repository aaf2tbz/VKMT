#include <windows.h>
#include <stdio.h>

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

int main(void)
{
    volatile LONG handler_ran = 0;

    __try
    {
        *(volatile DWORD *)(ULONG_PTR)0 = 0x564b4d54;
    }
    __except (filter(GetExceptionInformation()))
    {
        handler_ran = 1;
    }

    if (filter_calls != 1 || !address_ok || !handler_ran)
    {
        printf("I386_MSVC_SEH_FAIL filter=%ld address=%ld handler=%ld\n",
               filter_calls, address_ok, handler_ran);
        return 3;
    }

    puts("I386_MSVC_SEH_OK");
    return 0;
}
