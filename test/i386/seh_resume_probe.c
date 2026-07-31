#include <windows.h>
#include <stdint.h>
#include <stdio.h>

static volatile uintptr_t resume_eip;
static volatile LONG handler_calls;
static volatile LONG address_ok;

static LONG CALLBACK handler(EXCEPTION_POINTERS *ptrs)
{
    EXCEPTION_RECORD *record = ptrs->ExceptionRecord;

    if (record->ExceptionCode != EXCEPTION_ACCESS_VIOLATION ||
        record->NumberParameters < 2)
        return EXCEPTION_CONTINUE_SEARCH;

    ++handler_calls;
    address_ok = record->ExceptionInformation[1] == 0;
    ptrs->ContextRecord->Eip = (DWORD)resume_eip;
    return EXCEPTION_CONTINUE_EXECUTION;
}

int main(void)
{
    PVOID registration = AddVectoredExceptionHandler(1, handler);

    if (!registration)
    {
        puts("I386_SEH_RESUME_FAIL registration");
        return 2;
    }

    resume_eip = (uintptr_t)&&resume;
    *(volatile DWORD *)(uintptr_t)0 = 0x564b4d54;

resume:
    RemoveVectoredExceptionHandler(registration);
    if (handler_calls != 1 || !address_ok)
    {
        printf("I386_SEH_RESUME_FAIL calls=%ld address_ok=%ld\n",
               handler_calls, address_ok);
        return 3;
    }

    puts("I386_SEH_RESUME_OK");
    return 0;
}
