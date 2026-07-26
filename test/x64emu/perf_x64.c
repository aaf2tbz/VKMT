/* M3 perf probe: tight integer loop, reports wall time. */
#include <windows.h>
#include <stdio.h>

int main( void )
{
    volatile unsigned long long x = 0x9e3779b97f4a7c15ull;
    unsigned long long i, t0, t1;
    const unsigned long long iters = 30000000ull;

    t0 = GetTickCount64();
    for (i = 0; i < iters; i++)
        x = (x >> 3) ^ (x << 5) ^ i;   /* ~7-9 x86 insns/iter incl. loop overhead */
    t1 = GetTickCount64();

    printf( "perf_x64: %llu iters in %llu ms (%.2f ns/iter) x=%llx\n",
            iters, t1 - t0, iters ? (double)(t1 - t0) * 1e6 / iters : 0.0, x );
    return 0;
}
