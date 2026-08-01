#include <windows.h>
#include <inttypes.h>
#include <stdio.h>

extern int p1_fault_sequence(void);
extern const unsigned char p1_fault_site;
extern const unsigned char p1_resume_site;
extern DWORD64 p1_saved_return;

static volatile LONG handled;
static volatile LONG failures;

static void check64(const char *name, DWORD64 actual, DWORD64 expected)
{
    if (actual != expected)
    {
        fprintf(stderr, "P1 stale %s: actual=%016" PRIx64 " expected=%016" PRIx64 "\n",
                name, (uint64_t)actual, (uint64_t)expected);
        InterlockedIncrement(&failures);
    }
}

static LONG CALLBACK precise_fault_handler(EXCEPTION_POINTERS *exception)
{
    EXCEPTION_RECORD *record = exception->ExceptionRecord;
    CONTEXT *context = exception->ContextRecord;

    if (record->ExceptionCode != EXCEPTION_ACCESS_VIOLATION ||
        context->Rip != (DWORD64)(uintptr_t)&p1_fault_site)
        return EXCEPTION_CONTINUE_SEARCH;

    check64("RAX", context->Rax, UINT64_C(0x1111111122222222));
    check64("RBX", context->Rbx, UINT64_C(0x3333333344444444));
    check64("RCX", context->Rcx, UINT64_C(0x5555555566666666));
    check64("RDX", context->Rdx, UINT64_C(0x7777777788888888));
    check64("RSI", context->Rsi, UINT64_C(0x99999999aaaaaaaa));
    check64("RDI", context->Rdi, UINT64_C(0xbbbbbbbbcccccccc));
    check64("RBP", context->Rbp, UINT64_C(0xddddddddeeeeeeee));
    check64("R8", context->R8, UINT64_C(0x0123456789abcdef));
    check64("R9", context->R9, UINT64_C(0xfedcba9876543210));
    check64("R10", context->R10, UINT64_C(0x13579bdf2468ace0));
    check64("R11", context->R11, UINT64_C(0x0f1e2d3c4b5a6978));
    check64("R12", context->R12, UINT64_C(0x1020304050607080));
    check64("R13", context->R13, UINT64_C(0x8877665544332211));
    check64("R14", context->R14, UINT64_C(0xa5a5a5a55a5a5a5a));
    check64("R15", context->R15, 0);
    {
        LONG return_offset = -1;
        for (LONG offset = 0; offset <= 96; offset += 8)
            if (*(const DWORD64 *)(uintptr_t)(context->Rsp + offset) == p1_saved_return)
            {
                return_offset = offset;
                break;
            }
        if (return_offset != 64)
        {
            fprintf(stderr, "P1 stale RSP: reconstructed=%016" PRIx64 " return_offset=%ld expected=64\n",
                    (uint64_t)context->Rsp, return_offset);
            InterlockedIncrement(&failures);
        }
    }

    /* The assembly compares RAX with itself immediately before the fault. */
    if (!(context->EFlags & (1u << 6)) ||
        (context->EFlags & ((1u << 0) | (1u << 7) | (1u << 11))))
    {
        fprintf(stderr, "P1 stale EFLAGS: %08lx\n", context->EFlags);
        InterlockedIncrement(&failures);
    }
    if (record->NumberParameters < 2 || record->ExceptionInformation[0] != 1 ||
        record->ExceptionInformation[1] != 0)
    {
        fprintf(stderr, "P1 incorrect AV metadata\n");
        InterlockedIncrement(&failures);
    }

    context->Rip = (DWORD64)(uintptr_t)&p1_resume_site;
    InterlockedIncrement(&handled);
    return EXCEPTION_CONTINUE_EXECUTION;
}

int main(void)
{
    PVOID handler = AddVectoredExceptionHandler(1, precise_fault_handler);
    if (!handler)
        return 2;

    int resumed = p1_fault_sequence();
    RemoveVectoredExceptionHandler(handler);

    if (resumed != 1 || handled != 1 || failures)
    {
        fprintf(stderr, "P1_PRECISE_MULTIBLOCK_FAILED resumed=%d handled=%ld failures=%ld\n",
                resumed, handled, failures);
        return 1;
    }

    puts("P1_PRECISE_MULTIBLOCK_OK");
    return 0;
}
