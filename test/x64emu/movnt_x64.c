#include <emmintrin.h>
#include <xmmintrin.h>
#include <stdio.h>

static unsigned int integer_output[4] __attribute__((aligned(16)));
static float float_output[4] __attribute__((aligned(16)));

__attribute__((noinline))
static int pixel_format_switch(unsigned int format)
{
    unsigned int masks[4] = { 0, 0, 0, 0 };
    unsigned int output[4] = { 0, 0, 0, 0 };
    unsigned int layout = (format >> 16) & 15;
    unsigned int order = (format >> 20) & 15;

    switch (layout)
    {
    case 6:
        masks[0] = 0xff000000;
        masks[1] = 0x00ff0000;
        masks[2] = 0x0000ff00;
        masks[3] = 0x000000ff;
        break;
    default:
        return 3;
    }
    switch (order)
    {
    case 7:
        output[3] = masks[0];
        output[2] = masks[1];
        output[1] = masks[2];
        output[0] = masks[3];
        break;
    default:
        return 4;
    }
    return output[0] == 0xff && output[1] == 0xff00 &&
           output[2] == 0xff0000 && output[3] == 0xff000000 ? 0 : 5;
}

int main(void)
{
    const __m128i integers = _mm_set_epi32(0x44556677, 0x10203040,
                                           0x7fffffff, 0x01234567);
    const __m128 floats = _mm_set_ps(4.5f, -3.25f, 2.0f, 1.5f);
    unsigned int extracted;

    __asm__ __volatile__("movntdq %1, %0"
                         : "=m"(*(volatile __m128i *)integer_output)
                         : "x"(integers)
                         : "memory");
    _mm_stream_ps(float_output, floats);
    _mm_sfence();

    if (integer_output[0] != 0x01234567 ||
        integer_output[1] != 0x7fffffff ||
        integer_output[2] != 0x10203040 ||
        integer_output[3] != 0x44556677)
        return 1;
    if (float_output[0] != 1.5f || float_output[1] != 2.0f ||
        float_output[2] != -3.25f || float_output[3] != 4.5f)
        return 2;
    __asm__ __volatile__("pextrw $5, %1, %0"
                         : "=r"(extracted)
                         : "x"(integers));
    if (extracted != 0x1020)
        return 8;
    {
        volatile unsigned int format = 0x16762004;
        int result = pixel_format_switch(format);
        if (result) return result;
        __asm__ __volatile__("shrl $16, %0" : "+r"(format) : : "cc");
        if (format != 0x1676) return 6;
        __asm__ __volatile__("shrl $4, %0" : "+r"(format) : : "cc");
        if (format != 0x167) return 7;
    }

    puts("VKMT_X64_MOVNT_OK");
    return 0;
}
