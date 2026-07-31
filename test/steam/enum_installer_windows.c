#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0a00
#include <windows.h>
#include <stdio.h>

static BOOL CALLBACK print_child(HWND hwnd, LPARAM parent)
{
    WCHAR class_name[128] = {0};
    WCHAR text[256] = {0};
    RECT rect = {0};

    GetClassNameW(hwnd, class_name, ARRAYSIZE(class_name));
    GetWindowTextW(hwnd, text, ARRAYSIZE(text));
    GetWindowRect(hwnd, &rect);
    wprintf(L"CHILD parent=%p hwnd=%p id=%d visible=%d enabled=%d "
            L"style=%Ix exstyle=%Ix rect=%ld,%ld,%ld,%ld class=%ls text=%ls\n",
            (void *)parent, hwnd, GetDlgCtrlID(hwnd), IsWindowVisible(hwnd), IsWindowEnabled(hwnd),
            GetWindowLongPtrW(hwnd, GWL_STYLE), GetWindowLongPtrW(hwnd, GWL_EXSTYLE),
            rect.left, rect.top, rect.right, rect.bottom, class_name, text);
    return TRUE;
}

static BOOL click_next;
static BOOL force_redraw;

static BOOL CALLBACK print_window(HWND hwnd, LPARAM unused)
{
    WCHAR class_name[128] = {0};
    WCHAR text[256] = {0};
    DWORD pid = 0;
    RECT rect = {0};
    RECT client = {0};
    POINT origin = {0};
    LONG_PTR style;
    LONG_PTR exstyle;
    UINT dpi;
    RECT adjusted = {0, 0, 491, 350};

    GetWindowThreadProcessId(hwnd, &pid);
    GetClassNameW(hwnd, class_name, ARRAYSIZE(class_name));
    GetWindowTextW(hwnd, text, ARRAYSIZE(text));
    GetWindowRect(hwnd, &rect);
    GetClientRect(hwnd, &client);
    ClientToScreen(hwnd, &origin);
    style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    exstyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    dpi = GetDpiForWindow(hwnd);
    AdjustWindowRectExForDpi(&adjusted, style, FALSE, exstyle, dpi);
    wprintf(L"TOP pid=%lu hwnd=%p visible=%d enabled=%d rect=%ld,%ld,%ld,%ld "
            L"client=%ld,%ld,%ld,%ld origin=%ld,%ld style=%Ix exstyle=%Ix dpi=%u "
            L"adjusted491x350=%ld,%ld,%ld,%ld class=%ls text=%ls\n",
            pid, hwnd, IsWindowVisible(hwnd), IsWindowEnabled(hwnd),
            rect.left, rect.top, rect.right, rect.bottom,
            client.left, client.top, client.right, client.bottom,
            origin.x, origin.y, style, exstyle, dpi,
            adjusted.left, adjusted.top, adjusted.right, adjusted.bottom,
            class_name, text);
    EnumChildWindows(hwnd, print_child, (LPARAM)hwnd);
    if (force_redraw && !lstrcmpW(class_name, L"#32770") && IsWindowVisible(hwnd))
    {
        wprintf(L"ACTION redraw hwnd=%p\n", hwnd);
        RedrawWindow(hwnd, NULL, NULL, RDW_INVALIDATE | RDW_INTERNALPAINT |
                                      RDW_ERASE | RDW_FRAME | RDW_ALLCHILDREN |
                                      RDW_UPDATENOW);
        force_redraw = FALSE;
    }
    if (click_next && !lstrcmpW(class_name, L"#32770") && IsWindowVisible(hwnd))
    {
        HWND next = GetDlgItem(hwnd, IDOK);
        if (next && IsWindowVisible(next) && IsWindowEnabled(next))
        {
            wprintf(L"ACTION click IDOK hwnd=%p\n", next);
            SendMessageW(next, BM_CLICK, 0, 0);
            click_next = FALSE;
        }
    }
    return TRUE;
}

int wmain(int argc, WCHAR **argv)
{
    click_next = argc > 1 && !lstrcmpiW(argv[1], L"next");
    force_redraw = argc > 1 && !lstrcmpiW(argv[1], L"redraw");
    EnumWindows(print_window, 0);
    return 0;
}
