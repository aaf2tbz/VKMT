/* Deterministic control/candidate benchmark for the opt-in Steam marker scan. */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const char marker[] = "Update complete, launching Steam...";

static int control_contains( const void *buffer, size_t length,
                             const char *needle, size_t needle_length )
{
    const unsigned char *bytes = buffer;
    size_t i;

    if (length < needle_length) return 0;
    for (i = 0; i <= length - needle_length; ++i)
        if (!memcmp( bytes + i, needle, needle_length )) return 1;
    return 0;
}

static int candidate_contains( const void *buffer, size_t length,
                               const char *needle, size_t needle_length )
{
    const unsigned char *bytes = buffer, *found;

    if (length < needle_length) return 0;
    if (!needle_length) return 1;
    while (length >= needle_length &&
           (found = memchr( bytes, (unsigned char)needle[0],
                            length - needle_length + 1 )))
    {
        size_t offset = found - bytes;
        if (!memcmp( found, needle, needle_length )) return 1;
        bytes = found + 1;
        length -= offset + 1;
    }
    return 0;
}

static uint64_t clock_ns(void)
{
    struct timespec ts;
    clock_gettime( CLOCK_MONOTONIC, &ts );
    return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

static uint64_t measure( int (*fn)(const void *, size_t, const char *, size_t),
                         const unsigned char *buffer, size_t length, int reps,
                         volatile int *sink )
{
    uint64_t start = clock_ns();
    int result = 0;
    int i;

    for (i = 0; i < reps; ++i)
        result += fn( buffer, length, marker, sizeof(marker) - 1 );
    *sink += result;
    return clock_ns() - start;
}

static uint64_t median( uint64_t *values, size_t count )
{
    size_t i, j;
    for (i = 1; i < count; ++i)
    {
        uint64_t value = values[i];
        for (j = i; j && values[j - 1] > value; --j) values[j] = values[j - 1];
        values[j] = value;
    }
    return values[count / 2];
}

int main(void)
{
    const size_t sizes[] = { 4096, 65536, 1048576 };
    unsigned char *buffer = malloc( sizes[2] );
    volatile int sink = 0;
    size_t size_index;
    unsigned long random_state = 0x8a37;
    unsigned long run;

    if (!buffer) return 2;

    /* The replacement must be exact for arbitrary byte strings, including
     * empty needles and lengths smaller than the marker. */
    for (run = 0; run < 250000; ++run)
    {
        size_t length = (random_state = random_state * 1103515245 + 12345) % 256;
        size_t needle_length =
            (random_state = random_state * 1103515245 + 12345) % 64;
        size_t i;
        for (i = 0; i < length; ++i)
            buffer[i] = (unsigned char)(random_state = random_state * 1103515245 + 12345);
        for (i = 0; i < needle_length; ++i)
            buffer[256 - 64 + i] =
                (unsigned char)(random_state = random_state * 1103515245 + 12345);
        if (control_contains( buffer, length, (const char *)(buffer + 192), needle_length ) !=
            candidate_contains( buffer, length, (const char *)(buffer + 192), needle_length ))
        {
            fprintf( stderr, "buffer_contains equivalence failure run=%lu length=%zu needle=%zu\n",
                     run, length, needle_length );
            return 1;
        }
    }
    puts( "VKMT_NTDLL_FILE_SCAN_EQUIVALENCE_OK runs=250000" );

    for (size_index = 0; size_index < sizeof(sizes) / sizeof(sizes[0]); ++size_index)
    {
        const size_t length = sizes[size_index];
        const int reps = 100;
        int mode;

        memset( buffer, 0x5b, length );
        for (mode = 0; mode < 3; ++mode)
        {
            uint64_t control[5], candidate[5];
            int sample;

            if (mode == 1) memcpy( buffer + length - sizeof(marker) + 1,
                                   marker, sizeof(marker) - 1 );
            if (mode == 2) memcpy( buffer, marker, sizeof(marker) - 1 );
            for (sample = 0; sample < 5; ++sample)
            {
                control[sample] = measure( control_contains, buffer, length, reps, &sink );
                candidate[sample] = measure( candidate_contains, buffer, length, reps, &sink );
            }
            printf( "VKMT_NTDLL_FILE_SCAN_BENCH size=%zu mode=%d control_ns=%llu "
                    "candidate_ns=%llu\n", length, mode,
                    (unsigned long long)median( control, 5 ),
                    (unsigned long long)median( candidate, 5 ) );
        }
    }
    fprintf( stderr, "sink=%d\n", sink );
    free( buffer );
    return 0;
}
