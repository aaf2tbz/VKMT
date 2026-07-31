#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>

static uintptr_t captured[4];

__declspec(noinline)
static void capture(void *desc, void *format, ...)
{
    va_list args;
    unsigned int i;

    va_start(args, format);
    for (i = 0; i < 4; ++i) captured[i] = va_arg(args, uintptr_t);
    va_end(args);
}

int main(void)
{
    uintptr_t marker = 0x44444444;

    capture((void *)0xaaaaaaaa, (void *)0xbbbbbbbb,
            (uintptr_t)0x11111111, (uintptr_t)0x22222222,
            (uintptr_t)0x33333333, (uintptr_t)&marker);

    printf("captured=%Ix,%Ix,%Ix,%Ix expected_last=%Ix\n",
           captured[0], captured[1], captured[2], captured[3], (uintptr_t)&marker);

    if (captured[0] != 0x11111111 || captured[1] != 0x22222222 ||
        captured[2] != 0x33333333 || captured[3] != (uintptr_t)&marker)
        return 1;
    return 0;
}
