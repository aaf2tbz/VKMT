#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <uxtheme.h>
#include <stdio.h>

enum { ID_NEXT = 1001, ID_FINISH = 1002 };

static HWND page1, page2, next_button, finish_button;
static unsigned next_callbacks, finish_callbacks, destroy_callbacks;

static LRESULT CALLBACK installer_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam)
{
    (void)lparam;

    switch (message)
    {
    case WM_CREATE:
        page1 = CreateWindowExW(0, L"STATIC", L"Welcome to Steam Setup",
                                WS_CHILD | WS_VISIBLE, 20, 20, 300, 40,
                                hwnd, NULL, GetModuleHandleW(NULL), NULL);
        next_button = CreateWindowExW(0, L"BUTTON", L"Next >",
                                     WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON,
                                     230, 130, 90, 28, hwnd, (HMENU)ID_NEXT,
                                     GetModuleHandleW(NULL), NULL);
        page2 = CreateWindowExW(0, L"STATIC", L"Setup probe complete",
                                WS_CHILD, 20, 20, 300, 40,
                                hwnd, NULL, GetModuleHandleW(NULL), NULL);
        finish_button = CreateWindowExW(0, L"BUTTON", L"Finish",
                                       WS_CHILD | WS_TABSTOP | BS_DEFPUSHBUTTON,
                                       230, 130, 90, 28, hwnd, (HMENU)ID_FINISH,
                                       GetModuleHandleW(NULL), NULL);
        if (!page1 || !page2 || !next_button || !finish_button)
            return -1;
        return 0;

    case WM_COMMAND:
        if (HIWORD(wparam) != BN_CLICKED) break;
        if (LOWORD(wparam) == ID_NEXT)
        {
            ++next_callbacks;
            ShowWindow(page1, SW_HIDE);
            ShowWindow(next_button, SW_HIDE);
            ShowWindow(page2, SW_SHOW);
            ShowWindow(finish_button, SW_SHOW);
            SetFocus(finish_button);
            return 0;
        }
        if (LOWORD(wparam) == ID_FINISH)
        {
            ++finish_callbacks;
            DestroyWindow(hwnd);
            return 0;
        }
        break;

    case WM_DESTROY:
        ++destroy_callbacks;
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

int main(void)
{
    static const WCHAR class_name[] = L"VKMT_NSIS_NAVIGATION";
    WNDCLASSW wc = {0};
    HWND window;
    HTHEME next_theme, finish_theme;
    MSG message;

    setvbuf(stdout, NULL, _IONBF, 0);
    wc.lpfnWndProc = installer_proc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.hCursor = LoadCursorW(NULL, MAKEINTRESOURCEW(32512));
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = class_name;
    if (!RegisterClassW(&wc))
    {
        printf("RegisterClassW failed: %lu\n", GetLastError());
        return 1;
    }

    window = CreateWindowExW(WS_EX_CONTROLPARENT, class_name, L"Steam Setup",
                             WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_VISIBLE,
                             CW_USEDEFAULT, CW_USEDEFAULT, 360, 220, NULL, NULL,
                             wc.hInstance, NULL);
    if (!window)
    {
        printf("CreateWindowExW failed: %lu\n", GetLastError());
        return 2;
    }

    next_theme = OpenThemeData(next_button, L"Button");
    finish_theme = OpenThemeData(finish_button, L"Button");
    if (!next_theme || !finish_theme ||
        GetWindowTheme(next_button) != next_theme ||
        GetWindowTheme(finish_button) != finish_theme)
    {
        printf("theme gate failed next=%p finish=%p\n", next_theme, finish_theme);
        return 3;
    }

    SendMessageW(next_button, BM_CLICK, 0, 0);
    if (next_callbacks != 1 || IsWindowVisible(page1) || IsWindowVisible(next_button) ||
        !IsWindowVisible(page2) || !IsWindowVisible(finish_button) || GetCapture())
    {
        printf("page transition state invalid callbacks=%u visible=%d,%d,%d,%d\n",
               next_callbacks, IsWindowVisible(page1), IsWindowVisible(next_button),
               IsWindowVisible(page2), IsWindowVisible(finish_button));
        return 4;
    }
    SendMessageW(finish_button, BM_CLICK, 0, 0);
    while (GetMessageW(&message, NULL, 0, 0) > 0)
    {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }

    printf("next=%u finish=%u destroy=%u\n",
           next_callbacks, finish_callbacks, destroy_callbacks);
    if (next_callbacks != 1 || finish_callbacks != 1 || destroy_callbacks != 1)
        return 5;
    puts("STEAM_NSIS_I386_CONTROL_THEME_NAVIGATION_EXIT_OK");
    return 0;
}
