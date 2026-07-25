/* M3 probe 2: integer + SSE2 double math through the emulator.
 * Prints computed values; the harness eyeballs them against known-good.
 * Exit code 0 iff all self-checks pass. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static int failures = 0;

static void check_i( const char *name, long long got, long long want )
{
    if (got != want)
    {
        printf( "FAIL %s: got %lld want %lld\n", name, got, want );
        failures++;
    }
}

static void check_f( const char *name, double got, double want )
{
    double d = got - want;
    if (d < 0) d = -d;
    if (d > 1e-9)
    {
        printf( "FAIL %s: got %.12f want %.12f\n", name, got, want );
        failures++;
    }
}

int main( void )
{
    /* integer: mul/div/shifts/rotates via opaque values */
    volatile long long a = 0x123456789abcdef0ll, b = 1000003;
    volatile unsigned long long ua = 0xfedcba9876543210ull, ub = 7;
    volatile int shift = 13;

    check_i( "mul", a * b, 0x123456789abcdef0ll * 1000003 );
    check_i( "div", a / b, 0x123456789abcdef0ll / 1000003 );
    check_i( "mod", a % b, 0x123456789abcdef0ll % 1000003 );
    check_i( "udiv", (long long)(ua / ub), (long long)(0xfedcba9876543210ull / 7) );
    check_i( "shl", (long long)(ua << shift), (long long)(0xfedcba9876543210ull << 13) );
    check_i( "shr", (long long)(ua >> shift), (long long)(0xfedcba9876543210ull >> 13) );
    check_i( "sar", a >> shift, 0x123456789abcdef0ll >> 13 );
    check_i( "rot", (ua << shift) | (ua >> (64 - shift)),
             (long long)((0xfedcba9876543210ull << 13) | (0xfedcba9876543210ull >> 51)) );

    /* 128-bit multiply high parts (uses mul/imul) */
    {
        unsigned long long hi = (unsigned long long)(((__uint128_t)ua * ub) >> 64);
        long long shi = (long long)(((__int128)a * b) >> 64);
        check_i( "mulhi", (long long)hi, (long long)(((__uint128_t)0xfedcba9876543210ull * 7) >> 64) );
        check_i( "imulhi", shi, (long long)(((__int128)0x123456789abcdef0ll * 1000003) >> 64) );
    }

    /* SSE2 scalar double math */
    volatile double x = 3.141592653589793, y = 2.718281828459045, z = -0.5772156649015329;
    double sum = 0;
    int i;

    check_f( "add", x + y, 5.859874482048838 );
    check_f( "sub", x - y, 0.423310825130748 );
    check_f( "mul.d", x * y, 8.539734222673566 );
    check_f( "div.d", x / y, 1.1557273497909217 );
    check_f( "neg", -z, 0.5772156649015329 );

    for (i = 1; i <= 1000; i++) sum += 1.0 / (double)i / (double)i;
    check_f( "series", sum, 1.6439345666815615 );   /* pi^2/6 partial */

    /* sqrt via sqrt() — links libmsvcrt sqrt, SSE2 sqrtsd */
    {
        extern double sqrt(double);
        check_f( "sqrt2", sqrt( 2.0 ), 1.4142135623730951 );
        check_f( "sqrt.x", sqrt( x ), 1.7724538509055159 );
    }

    /* int<->double conversions */
    {
        volatile long long big = 9007199254740993ll;  /* 2^53+1 */
        volatile double d = 1e18;
        check_f( "i2d", (double)big, 9007199254740992.0 );
        check_i( "d2i", (long long)d, 1000000000000000000ll );
        check_i( "d2i.trunc", (long long)(x * 100), 314 );
    }

    /* packed SSE2: vector double[4] via float, and double[2] */
    {
        float vf[4] = { 1.5f, -2.25f, 3.75f, 4.125f };
        float vg[4] = { 0.5f, 4.0f, -1.0f, 2.0f };
        float out[4];
        double vd[2] = { 1.0 / 3.0, 2.0 / 7.0 };
        double ve[2] = { 3.0, -7.0 };
        double od[2];

        for (i = 0; i < 4; i++) out[i] = vf[i] * vg[i] + 0.25f;
        check_f( "ps.0", out[0], 1.0 );
        check_f( "ps.1", out[1], -8.75 );
        check_f( "ps.2", out[2], -3.5 );
        check_f( "ps.3", out[3], 8.5 );

        for (i = 0; i < 2; i++) od[i] = vd[i] * ve[i] - ve[i];
        check_f( "pd.0", od[0], -2.0 );
        check_f( "pd.1", od[1], 5.0 );  /* (2/7)*(-7) - (-7) = -2 + 7 */
    }

    printf( "MATH RESULTS: mul=%lld div=%lld x+y=%.6f x*y=%.6f series=%.10f sqrt2=%.12f\n",
            a * b, a / b, x + y, x * y, sum, 1.4142135623730951 );
    printf( "math_x64: %s (%d failures)\n", failures ? "FAIL" : "OK", failures );
    return failures ? 1 : 0;
}
