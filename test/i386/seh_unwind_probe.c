#include <windows.h>
#include <stdio.h>

static volatile LONG filter_calls;
static volatile LONG address_ok;
static volatile LONG unwind_calls;
static volatile ULONG_PTR resume_eip;

struct registration
{
    struct registration *previous;
    EXCEPTION_DISPOSITION (__cdecl *handler)(EXCEPTION_RECORD *,
                                             struct registration *,
                                             CONTEXT *, void *);
};

static EXCEPTION_DISPOSITION __cdecl frame_handler(EXCEPTION_RECORD *record,
                                                    struct registration *frame,
                                                    CONTEXT *context,
                                                    void *dispatcher)
{
    (void)context;
    (void)dispatcher;
    if (record->ExceptionFlags & (EXCEPTION_UNWINDING | EXCEPTION_EXIT_UNWIND))
    {
        ++unwind_calls;
        return ExceptionContinueSearch;
    }

    ++filter_calls;
    address_ok = record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION &&
                 record->NumberParameters >= 2 &&
                 record->ExceptionInformation[1] == 0;
    if (!address_ok) return ExceptionContinueSearch;

    RtlUnwind(frame, (void *)resume_eip, record, 0);
    return ExceptionContinueSearch;
}

int main(void)
{
    struct registration frame;
    volatile LONG handler_ran = 0;

    frame.handler = frame_handler;
    __asm__ volatile("movl %%fs:0,%0"
                     : "=r"(frame.previous)
                     :
                     : "memory");
    __asm__ volatile("movl %0,%%fs:0"
                     :
                     : "r"(&frame)
                     : "memory");
    resume_eip = (ULONG_PTR)&&resume;
    *(volatile DWORD *)(ULONG_PTR)0 = 0x564b4d54;

resume:
    handler_ran = 1;
    __asm__ volatile("movl %0,%%fs:0"
                     :
                     : "r"(frame.previous)
                     : "memory");

    if (filter_calls != 1 || !address_ok || unwind_calls != 1 || !handler_ran)
    {
        printf("I386_SEH_UNWIND_FAIL filter=%ld address=%ld unwind=%ld handler=%ld\n",
               filter_calls, address_ok, unwind_calls, handler_ran);
        return 3;
    }

    puts("I386_SEH_UNWIND_OK");
    return 0;
}
