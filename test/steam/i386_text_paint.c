#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

static unsigned count_changed(const DWORD *pixels, unsigned count, DWORD background)
{
    unsigned changed = 0;
    while (count--) if ((*pixels++ & 0x00ffffff) != background) changed++;
    return changed;
}

int main(void)
{
    static const WCHAR draw_text[] = L"Steam Setup static text";
    static const WCHAR ext_text[] = L"Next >  Cancel";
    BITMAPINFO bmi = {{sizeof(BITMAPINFOHEADER), 320, -120, 1, 32, BI_RGB}};
    RECT rect = {8, 8, 312, 55};
    SIZE extent = {0};
    TEXTMETRICW metrics = {0};
    HDC screen = GetDC(NULL), dc;
    HBITMAP bitmap, old_bitmap;
    HFONT old_font;
    DWORD *pixels = NULL;
    unsigned changed;
    BOOL draw_ret, ext_ret, extent_ret, metrics_ret;

    if (!screen) return 10;
    dc = CreateCompatibleDC(screen);
    bitmap = CreateDIBSection(screen, &bmi, DIB_RGB_COLORS, (void **)&pixels, NULL, 0);
    ReleaseDC(NULL, screen);
    if (!dc || !bitmap || !pixels) return 11;

    old_bitmap = SelectObject(dc, bitmap);
    old_font = SelectObject(dc, GetStockObject(DEFAULT_GUI_FONT));
    PatBlt(dc, 0, 0, 320, 120, WHITENESS);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(0, 0, 0));

    extent_ret = GetTextExtentPoint32W(dc, draw_text, ARRAYSIZE(draw_text) - 1, &extent);
    metrics_ret = GetTextMetricsW(dc, &metrics);
    draw_ret = DrawTextW(dc, draw_text, -1, &rect, DT_LEFT | DT_TOP | DT_SINGLELINE);
    ext_ret = ExtTextOutW(dc, 8, 70, 0, NULL, ext_text, ARRAYSIZE(ext_text) - 1, NULL);
    GdiFlush();
    changed = count_changed(pixels, 320 * 120, 0x00ffffff);

    printf("extent_ret=%d extent=%ldx%ld metrics_ret=%d height=%ld "
           "draw_ret=%d ext_ret=%d changed=%u gle=%lu\n",
           extent_ret, extent.cx, extent.cy, metrics_ret, metrics.tmHeight,
           draw_ret, ext_ret, changed, GetLastError());

    SelectObject(dc, old_font);
    SelectObject(dc, old_bitmap);
    DeleteObject(bitmap);
    DeleteDC(dc);

    if (!extent_ret || extent.cx <= 0 || extent.cy <= 0) return 20;
    if (!metrics_ret || metrics.tmHeight <= 0) return 21;
    if (!draw_ret || !ext_ret) return 22;
    if (changed < 32) return 23;
    puts("STEAM_I386_GDI_TEXT_PIXELS_OK");
    return 0;
}
