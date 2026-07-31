#include <stdarg.h>
#include <stdint.h>

__declspec(dllexport)
void capture_cross_arch_varargs(uintptr_t *captured, uintptr_t tag, ...)
{
    va_list args;
    unsigned int i;

    va_start(args, tag);
    for (i = 0; i < 4; ++i) captured[i] = va_arg(args, uintptr_t);
    va_end(args);
}
