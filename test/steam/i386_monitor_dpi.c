#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellscalingapi.h>
#include <stdio.h>

int main(void)
{
    POINT origin = {0, 0};
    UINT x = 0xaaaaaaaa, y = 0xbbbbbbbb;
    HMONITOR monitor = MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
    HMODULE shcore = LoadLibraryA("shcore.dll");
    HRESULT (WINAPI *get_dpi)(HMONITOR, MONITOR_DPI_TYPE, UINT *, UINT *);
    DPI_AWARENESS_CONTEXT (WINAPI *set_context)(DPI_AWARENESS_CONTEXT);
    HRESULT hr;

    if (!monitor || !shcore)
    {
        printf("MONITOR_DPI_FAIL setup monitor=%p shcore=%p error=%lu\n",
               monitor, shcore, GetLastError());
        return 1;
    }

    get_dpi = (void *)GetProcAddress(shcore, "GetDpiForMonitor");
    set_context = (void *)GetProcAddress(GetModuleHandleA("user32.dll"),
                                         "SetThreadDpiAwarenessContext");
    if (!get_dpi)
    {
        printf("MONITOR_DPI_FAIL export error=%lu\n", GetLastError());
        return 2;
    }

    if (set_context) set_context(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    hr = get_dpi(monitor, MDT_EFFECTIVE_DPI, &x, &y);
    printf("monitor=%p hr=%08lx x=%u y=%u x_addr=%p y_addr=%p\n",
           monitor, (unsigned long)hr, x, y, &x, &y);
    if (FAILED(hr) || x < 72 || x > 768 || y < 72 || y > 768)
    {
        puts("MONITOR_DPI_FAIL");
        return 3;
    }

    puts("MONITOR_DPI_OK");
    return 0;
}
