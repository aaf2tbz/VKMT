/* M3 probe 4: threads through the emulator.
 * CreateThread x4 doing real work, WaitForMultipleObjects, per-thread
 * TLS slot check. Exit code = number of failures (0 = pass). */
#include <windows.h>
#include <stdio.h>
#include <string.h>

#define NTHREADS 4
#define ITERS    200000

static DWORD tls_index;
static LONG  failures;

typedef struct { int id; unsigned long long sum; int tls_ok; } work_t;
static work_t work[NTHREADS];

static DWORD WINAPI worker( void *arg )
{
    work_t *w = (work_t *)arg;
    unsigned long long s = 0;
    int i;
    char *slot;

    /* per-thread TLS: store a per-thread string, read it back */
    slot = (char *)LocalAlloc( LMEM_FIXED, 32 );
    if (!slot) { InterlockedIncrement( &failures ); return 1; }
    _snprintf( slot, 32, "thread-%d", w->id );
    if (!TlsSetValue( tls_index, slot )) { InterlockedIncrement( &failures ); return 1; }

    for (i = 1; i <= ITERS; i++) s += (unsigned)i ^ (unsigned)(s >> 3);
    w->sum = s;

    if (TlsGetValue( tls_index ) != slot || strcmp( TlsGetValue( tls_index ), slot ))
        w->tls_ok = 0;
    else
        w->tls_ok = 1;

    /* brief contention on the failures counter even when passing */
    InterlockedAdd( &failures, 0 );
    return 0;
}

int main( void )
{
    HANDLE th[NTHREADS];
    DWORD wait;
    int i;
    static const unsigned long long want[NTHREADS] = { 0, 0, 0, 0 };

    tls_index = TlsAlloc();
    if (tls_index == TLS_OUT_OF_INDEXES)
    {
        printf( "FAIL TlsAlloc\n" );
        return 1;
    }

    for (i = 0; i < NTHREADS; i++)
    {
        work[i].id = i;
        work[i].sum = 0;
        work[i].tls_ok = 0;
        th[i] = CreateThread( NULL, 0, worker, &work[i], 0, NULL );
        if (!th[i])
        {
            printf( "FAIL CreateThread %d\n", i );
            return 1;
        }
    }

    wait = WaitForMultipleObjects( NTHREADS, th, TRUE, 20000 );
    if (wait != WAIT_OBJECT_0)
    {
        printf( "FAIL WaitForMultipleObjects -> %lu\n", wait );
        return 1;
    }

    for (i = 0; i < NTHREADS; i++)
    {
        DWORD code = 0xdead;
        GetExitCodeThread( th[i], &code );
        if (code != 0)
        {
            printf( "FAIL thread %d exit code %lu\n", i, code );
            failures++;
        }
        if (!work[i].tls_ok)
        {
            printf( "FAIL thread %d TLS\n", i );
            failures++;
        }
        if (!work[i].sum)
        {
            printf( "FAIL thread %d did no work\n", i );
            failures++;
        }
        else printf( "thread %d sum %llu tls_ok %d\n", i, work[i].sum, work[i].tls_ok );
        CloseHandle( th[i] );
        (void)want;
    }
    TlsFree( tls_index );

    printf( "thread_x64: %s (%ld failures)\n", failures ? "FAIL" : "OK", failures );
    return (int)failures;
}
