#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0a00
#include <windows.h>
#include <stdio.h>

int main(void)
{
    RECT rect = {0, 0, 491, 350};
    BOOL ret = AdjustWindowRectExForDpi(&rect, WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
                                        FALSE, WS_EX_WINDOWEDGE, 96);
    printf("ret=%d error=%lu rect=%ld,%ld,%ld,%ld size=%ldx%ld\n",
           ret, GetLastError(), rect.left, rect.top, rect.right, rect.bottom,
           rect.right - rect.left, rect.bottom - rect.top);
    return ret ? 0 : 1;
}
