#include <windows.h>
#include <emmintrin.h>
#include <stdio.h>

static __attribute__((noinline)) void stream_store( void *destination, __m128i value )
{
    __asm__ volatile(
        "movntdq %1, (%0)\n\t"
        "sfence"
        :
        : "r"(destination), "x"(value)
        : "memory" );
}

int main( void )
{
    static const unsigned char expected[16] = {
        0x56, 0x4b, 0x4d, 0x54, 0x2d, 0x69, 0x33, 0x38,
        0x36, 0x2d, 0x4e, 0x54, 0x2d, 0x4f, 0x4b, 0x21
    };
    unsigned char *memory;
    __m128i value;
    unsigned int i;

    memory = VirtualAlloc( NULL, 4096, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE );
    if (!memory)
    {
        fprintf( stderr, "I386_NON_TEMPORAL_FAIL stage=VirtualAlloc error=%lu\n",
                 GetLastError() );
        return 1;
    }

    value = _mm_loadu_si128( (const __m128i *)expected );
    puts( "I386_NON_TEMPORAL_STORE_BEGIN" );
    fflush( stdout );
    stream_store( memory, value );
    puts( "I386_NON_TEMPORAL_STORE_RETURNED" );
    fflush( stdout );

    for (i = 0; i < sizeof(expected); ++i)
    {
        if (memory[i] != expected[i])
        {
            fprintf( stderr,
                     "I386_NON_TEMPORAL_FAIL stage=verify offset=%u actual=%02x expected=%02x\n",
                     i, memory[i], expected[i] );
            VirtualFree( memory, 0, MEM_RELEASE );
            return 1;
        }
    }

    if (!VirtualFree( memory, 0, MEM_RELEASE ))
    {
        fprintf( stderr, "I386_NON_TEMPORAL_FAIL stage=VirtualFree error=%lu\n",
                 GetLastError() );
        return 1;
    }

    puts( "I386_NON_TEMPORAL_MEMORY_OK" );
    return 0;
}
