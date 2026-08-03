#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

#define VKMT_WM_SENTINEL (WM_APP + 0x245)
#define VKMT_SENTINEL ((LRESULT)0x12345678abcdef01ULL)

static LRESULT CALLBACK vkmt_wndproc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam)
{
    switch (message)
    {
    case WM_NCCREATE:
        return TRUE;
    case VKMT_WM_SENTINEL:
        return VKMT_SENTINEL;
    default:
        return DefWindowProcW(hwnd, message, wparam, lparam);
    }
}

int main(void)
{
    const WCHAR class_name[] = L"VKMT_x64_WndProc_Callback";
    WNDCLASSEXW wc = {0};
    HWND hwnd;
    LRESULT result;

    wc.cbSize = sizeof(wc);
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpfnWndProc = vkmt_wndproc;
    wc.lpszClassName = class_name;

    if (!RegisterClassExW(&wc))
    {
        printf("VKMT_WNDPROC_FAIL register error=%lu\n", GetLastError());
        return 10;
    }

    hwnd = CreateWindowExW(0, class_name, L"VKMT callback probe", WS_OVERLAPPED,
                           CW_USEDEFAULT, CW_USEDEFAULT, 320, 200, NULL, NULL,
                           wc.hInstance, (void *)0x1122334455667788ULL);
    if (!hwnd)
    {
        printf("VKMT_WNDPROC_FAIL create error=%lu\n", GetLastError());
        return 11;
    }

    result = SendMessageW(hwnd, VKMT_WM_SENTINEL, 0, 0);
    if (result != VKMT_SENTINEL)
    {
        printf("VKMT_WNDPROC_FAIL result=%llx expected=%llx\n",
               (unsigned long long)result, (unsigned long long)VKMT_SENTINEL);
        DestroyWindow(hwnd);
        return 12;
    }

    DestroyWindow(hwnd);
    UnregisterClassW(class_name, wc.hInstance);
    puts("VKMT_WNDPROC_CALLBACK_OK");
    return 0;
}
