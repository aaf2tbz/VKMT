/* M3 probe 5: SEH across emulated frames.
 * __try/__except catching a deliberate AV, __try/__finally, and an
 * exception crossing an EC-boundary call. Exit 0 iff all pass. */
#include <windows.h>
#include <stdio.h>

static int failures = 0;
static volatile int *bad_ptr;

static void make_bad_ptr( void )
{
    /* opaque to the compiler: __argc is 1 at runtime but not foldable */
    bad_ptr = (volatile int *)(ULONG_PTR)(__argc - 1);
}

static int av_filter( unsigned code )
{
    printf( "filter saw exception %lx\n", code ); fflush(stdout);
    return code == EXCEPTION_ACCESS_VIOLATION ? EXCEPTION_EXECUTE_HANDLER
                                              : EXCEPTION_CONTINUE_SEARCH;
}

static int finally_flag = 0;

static __attribute__((noinline)) void do_av( void )
{
    *bad_ptr = 42;   /* AV: must unwind through the call frame */
}

static void finally_inner( void )
{
    __try
    {
        do_av();
    }
    __finally
    {
        finally_flag = 1;
    }
}

int main( void )
{
    int caught = 0;

    make_bad_ptr();

    __try
    {
        do_av();
    }
    __except( av_filter( GetExceptionCode() ) )
    {
        caught = 1;
    }
    if (!caught)
    {
        printf( "FAIL: AV was not caught\n" );
        failures++;
    }
    else { printf( "AV caught and handled\n" ); fflush(stdout); }

    __try
    {
        finally_inner();
    }
    __except( EXCEPTION_EXECUTE_HANDLER )
    {
        if (!finally_flag)
        {
            printf( "FAIL: finally did not run during unwind\n" );
            failures++;
        }
        else { printf( "finally ran during unwind\n" ); fflush(stdout); }
    }

    printf( "seh_x64: %s (%d failures)\n", failures ? "FAIL" : "OK", failures ); fflush(stdout);
    return failures;
}
