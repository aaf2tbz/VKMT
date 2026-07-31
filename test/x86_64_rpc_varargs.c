#include <stdint.h>
#include <stdio.h>

__declspec(dllimport)
void capture_cross_arch_varargs(uintptr_t *captured, uintptr_t tag, ...);

int main(void)
{
    uintptr_t captured[4] = {0};
    uintptr_t marker = 0x44444444;

    capture_cross_arch_varargs(captured, 0xbbbbbbbb,
                               (uintptr_t)0x11111111, (uintptr_t)0x22222222,
                               (uintptr_t)0x33333333, (uintptr_t)&marker);

    printf("captured=%Ix,%Ix,%Ix,%Ix expected_last=%Ix\n",
           captured[0], captured[1], captured[2], captured[3], (uintptr_t)&marker);

    if (captured[0] != 0x11111111 || captured[1] != 0x22222222 ||
        captured[2] != 0x33333333 || captured[3] != (uintptr_t)&marker)
        return 1;
    return 0;
}
