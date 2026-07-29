#include <windows.h>
#include <stdio.h>

static INIT_ONCE once = INIT_ONCE_STATIC_INIT;
static LONG called;

static BOOL CALLBACK callback(PINIT_ONCE value, void *parameter, void **context)
{
    (void)value; (void)parameter; (void)context;
    InterlockedIncrement(&called);
    return TRUE;
}

int main(void)
{
    BOOL ok = InitOnceExecuteOnce(&once, callback, NULL, NULL);
    fprintf(stderr, "InitOnceExecuteOnce=%d called=%ld error=%lu\\n", ok, called, GetLastError());
    return ok && called == 1 ? 0 : 1;
}
