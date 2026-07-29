#include <stdint.h>

static volatile uint32_t callee_esp;

__attribute__((noinline)) static int direct_callee(int value)
{
    uint32_t esp;
    __asm__ volatile("movl %%esp, %0" : "=r"(esp));
    callee_esp = esp;
    return value + 1;
}

int main(void)
{
    if (direct_callee(41) != 42) return 10;
    if ((callee_esp & 0xffff0000u) == 0xc0000000u) return 77;
    if (!callee_esp) return 11;
    return 0;
}
