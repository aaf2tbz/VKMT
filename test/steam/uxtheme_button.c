#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <uxtheme.h>
#include <vssym32.h>
#include <stdio.h>

int main(void)
{
    HWND button;
    HTHEME opened, stored;
    COLORREF color = 0;
    HRESULT hr;
    MSG msg;
    void *probe;
    HWND desktop;
    WCHAR *heap_text;
    BITMAPINFO bmi = {{sizeof(BITMAPINFOHEADER), 240, -100, 1, 32, BI_RGB}};
    DWORD *pixels;
    HDC screen, memory;
    HBITMAP dib, old_dib;
    unsigned i, dark = 0, center_dark = 0;

    setvbuf(stdout, NULL, _IONBF, 0);
    desktop = GetDesktopWindow();
    probe = HeapAlloc(GetProcessHeap(), 0, 32);
    printf("stage=property desktop=%p probe=%p\n", desktop, probe);
    if (!SetPropW(desktop, L"VKMT_i386_pointer_roundtrip", probe))
        return 10;
    printf("property=%p equal=%d\n",
           GetPropW(desktop, L"VKMT_i386_pointer_roundtrip"),
           GetPropW(desktop, L"VKMT_i386_pointer_roundtrip") == probe);
    RemovePropW(desktop, L"VKMT_i386_pointer_roundtrip");
    HeapFree(GetProcessHeap(), 0, probe);

    printf("stage=create-window\n");
    button = CreateWindowExW(0, L"BUTTON", L"Next >", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                             100, 100, 240, 100, NULL, NULL, GetModuleHandleW(NULL), NULL);
    if (!button)
    {
        printf("CreateWindowExW failed: %lu\n", GetLastError());
        return 1;
    }

    opened = OpenThemeData(button, L"Button");
    stored = GetWindowTheme(button);
    printf("opened=%p stored=%p equal=%d error=%lu\n",
           opened, stored, opened == stored, GetLastError());
    if (!opened || opened != stored) return 2;

    printf("set_text_ret=%ld\n", (long)SendMessageW(button, WM_SETTEXT, 0, (LPARAM)L"Next >"));
    printf("text_length=%d\n", GetWindowTextLengthW(button));
    heap_text = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 128 * sizeof(WCHAR));
    printf("heap_text_ret=%d text=%ls\n", GetWindowTextW(button, heap_text, 128), heap_text);
    ZeroMemory(heap_text, 128 * sizeof(WCHAR));
    printf("internal_text_ret=%d text=%ls\n",
           InternalGetWindowText(button, heap_text, 128), heap_text);
    if (lstrcmpW(heap_text, L"Next >")) return 4;

    hr = GetThemeColor(opened, BP_PUSHBUTTON, PBS_NORMAL, TMT_TEXTCOLOR, &color);
    printf("GetThemeColor hr=%#lx color=%#lx\n", hr, color);
    if (FAILED(hr)) return 3;

    UpdateWindow(button);
    while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE))
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    screen = GetDC(button);
    memory = CreateCompatibleDC(screen);
    dib = CreateDIBSection(screen, &bmi, DIB_RGB_COLORS, (void **)&pixels, NULL, 0);
    old_dib = SelectObject(memory, dib);
    PatBlt(memory, 0, 0, 240, 100, WHITENESS);
    SendMessageW(button, WM_PRINTCLIENT, (WPARAM)memory,
                 PRF_CLIENT | PRF_ERASEBKGND | PRF_CHILDREN);
    GdiFlush();
    for (i = 0; i < 240 * 100; i++)
    {
        BYTE b = pixels[i] & 0xff;
        BYTE g = (pixels[i] >> 8) & 0xff;
        BYTE r = (pixels[i] >> 16) & 0xff;
        if (r < 80 && g < 80 && b < 80) dark++;
        if ((i % 240) > 40 && (i % 240) < 200 && (i / 240) > 25 &&
            (i / 240) < 75 && r < 80 && g < 80 && b < 80) center_dark++;
    }
    printf("button_print_dark_pixels=%u center=%u\n", dark, center_dark);
    SelectObject(memory, old_dib);
    DeleteObject(dib);
    DeleteDC(memory);
    ReleaseDC(button, screen);
    HeapFree(GetProcessHeap(), 0, heap_text);
    if (center_dark < 8) return 5;

    DestroyWindow(button);
    printf("UXTHEME_BUTTON_I386_OK\n");
    return 0;
}
