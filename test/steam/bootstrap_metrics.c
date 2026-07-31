#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0a00
#include <windows.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    HWND window;
    RECT window_rect;
    HBITMAP bitmap;
    BITMAP bitmap_info = {0};
    if (argc > 1)
        printf("set_per_monitor_v2=%d gle=%lu\n",
               SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2),
               GetLastError());
    HDC dc = GetDC(NULL);
    SIZE extent_a = {0}, extent_w = {0};
    TEXTMETRICA tm_a = {0};
    TEXTMETRICW tm_w = {0};
    GetTextExtentPoint32A(dc, "Downloading update (5,592 of 336,229 KB)...", 44, &extent_a);
    GetTextExtentPoint32W(dc, L"Downloading update (5,592 of 336,229 KB)...", 44, &extent_w);
    GetTextMetricsA(dc, &tm_a);
    GetTextMetricsW(dc, &tm_w);
    printf("dpi_window_desktop=%u dpi_system=%u "
           "LOGPIXELS=%d,%d HORZVERTRES=%d,%d DESKTOP=%d,%d "
           "screen=%d,%d work=%ld,%ld,%ld,%ld\n",
           GetDpiForWindow(GetDesktopWindow()), GetDpiForSystem(),
           GetDeviceCaps(dc, LOGPIXELSX), GetDeviceCaps(dc, LOGPIXELSY),
           GetDeviceCaps(dc, HORZRES), GetDeviceCaps(dc, VERTRES),
           GetDeviceCaps(dc, DESKTOPHORZRES), GetDeviceCaps(dc, DESKTOPVERTRES),
           GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN),
           (long)GetSystemMetrics(SM_XVIRTUALSCREEN), (long)GetSystemMetrics(SM_YVIRTUALSCREEN),
           (long)GetSystemMetrics(SM_CXVIRTUALSCREEN), (long)GetSystemMetrics(SM_CYVIRTUALSCREEN));
    printf("extentA=%ldx%ld extentW=%ldx%ld metricsA=%ld metricsW=%ld\n",
           extent_a.cx, extent_a.cy, extent_w.cx, extent_w.cy, tm_a.tmHeight, tm_w.tmHeight);
    printf("physical_mm=%d,%d aspect=%d,%d,%d scaling=%d,%d rastercaps=%#x\n",
           GetDeviceCaps(dc, HORZSIZE), GetDeviceCaps(dc, VERTSIZE),
           GetDeviceCaps(dc, ASPECTX), GetDeviceCaps(dc, ASPECTY), GetDeviceCaps(dc, ASPECTXY),
           GetDeviceCaps(dc, SCALINGFACTORX), GetDeviceCaps(dc, SCALINGFACTORY),
           GetDeviceCaps(dc, RASTERCAPS));
    printf("dialog_base_units=%u,%u\n", LOWORD(GetDialogBaseUnits()), HIWORD(GetDialogBaseUnits()));
    bitmap = CreateBitmap(480, 136, 1, 32, NULL);
    printf("bitmap_getobject_ret=%d size=%ldx%ld stride=%ld planes=%u bpp=%u bits=%p\n",
           GetObjectW(bitmap, sizeof(bitmap_info), &bitmap_info),
           bitmap_info.bmWidth, bitmap_info.bmHeight, bitmap_info.bmWidthBytes,
           bitmap_info.bmPlanes, bitmap_info.bmBitsPixel, bitmap_info.bmBits);
    DeleteObject(bitmap);
    window = CreateWindowExW(0, L"STATIC", L"DPI fixture",
                             WS_OVERLAPPEDWINDOW, 100, 100, 480, 136,
                             NULL, NULL, GetModuleHandleW(NULL), NULL);
    GetWindowRect(window, &window_rect);
    printf("requested=480x136 actual=%ldx%ld window_dpi=%u\n",
           window_rect.right - window_rect.left, window_rect.bottom - window_rect.top,
           GetDpiForWindow(window));
    DestroyWindow(window);
    ReleaseDC(NULL, dc);
    return 0;
}
