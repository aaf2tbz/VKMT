/* M4: CPUID must not advertise opcode maps the interpreter does not implement. */
#include <intrin.h>
#include <stdio.h>

int main(void)
{
    int regs[4];

    __cpuidex(regs, 1, 0);
    if (regs[2] & ((1 << 19) | (1 << 20)))
    {
        printf("FAIL: CPUID still advertises SSE4.x: ECX=%08x\n", regs[2]);
        return 1;
    }
    printf("cpuid_x64: OK (SSE4.x not advertised)\n");
    return 0;
}
