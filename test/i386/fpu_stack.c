#include <windows.h>
#include <stdint.h>
#include <math.h>
#include <stdio.h>

#ifndef FPU_STACK_ITERATIONS
#define FPU_STACK_ITERATIONS 4096
#endif

static void write_hex(uintptr_t value)
{
    static const char hex[] = "0123456789abcdef";
    char buffer[] = "P5_I386_FPU_PRECALL_ESP=00000000\r\n";
    DWORD written;
    for (unsigned int i = 0; i != 8; ++i) buffer[24 + i] = hex[(value >> ((7 - i) * 4)) & 0xf];
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), buffer, sizeof(buffer) - 1, &written, NULL);
}

int main(void)
{
    volatile float input = 1.25f;
    volatile float output;
    uintptr_t esp;
    __asm__ volatile("movl %%esp, %0" : "=r"(esp));
    write_hex(esp);
    __asm__ volatile("movl %%esp, %0" : "=r"(esp));
    if ((esp & 0xffff0000u) == 0xc0000000u) return 77;
    for (unsigned int i = 0; i != FPU_STACK_ITERATIONS; ++i) output = ceilf(input + (float)(i & 1) * 0.25f);
    if (output != 2.0f) {
        printf("P5_I386_FPU_STACK_VALUE %.9g\n", (double)output);
        return 10;
    }
    puts("P5_I386_FPU_STACK_OK");
    return 0;
}
