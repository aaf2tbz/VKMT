#include <windows.h>
#include <stdio.h>

#define WM_VKMT_PING (WM_APP + 0x386)
#define VKMT_PING_RESULT ((LRESULT)0x3865a11)

static LONG create_count;
static LONG destroy_count;
static LONG userdata_cookie = 0x38655a11;
static LONG_PTR wndproc_userdata;
static LRESULT nested_defwindow_result;

static LRESULT CALLBACK probe_wndproc( HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam )
{
    switch (msg)
    {
    case WM_NCCREATE:
    {
        const CREATESTRUCTW *create = (const CREATESTRUCTW *)lparam;
        LONG previous;

        SetLastError( 0 );
        previous = SetWindowLongW( hwnd, GWL_USERDATA, (LONG)(LONG_PTR)create->lpCreateParams );
        if (previous || GetLastError())
        {
            fprintf( stderr,
                     "I386_USER_CLASS_WINDOW_FAIL stage=SetWindowLongW previous=%lx error=%lu\n",
                     previous, GetLastError() );
            return FALSE;
        }
        wndproc_userdata = GetWindowLongW( hwnd, GWL_USERDATA );
        return wndproc_userdata == (LONG_PTR)create->lpCreateParams;
    }
    case WM_CREATE:
    {
        MSG message;
        if (GetWindowLongW( hwnd, GWL_USERDATA ) != wndproc_userdata) return -1;
        PeekMessageW( &message, NULL, 0, 0, PM_NOREMOVE );
        PostMessageW( hwnd, WM_VKMT_PING, 0, 0 );
        GetMessageW( &message, hwnd, WM_VKMT_PING, WM_VKMT_PING );
        InterlockedIncrement( &create_count );
        return 0;
    }
    case WM_DESTROY:
        InterlockedIncrement( &destroy_count );
        return 0;
    case WM_VKMT_PING:
        return VKMT_PING_RESULT;
    default:
        return DefWindowProcW( hwnd, msg, wparam, lparam );
    }
}

static LRESULT CALLBACK default_wndproc( HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam )
{
    if (msg == WM_CREATE)
    {
        const CREATESTRUCTW *create = (const CREATESTRUCTW *)lparam;
        SetLastError( 0 );
        if (SetWindowLongW( hwnd, GWL_USERDATA, (LONG)(LONG_PTR)create->lpCreateParams ) ||
            GetLastError())
            return -1;
    }
    LRESULT result = DefWindowProcW( hwnd, msg, wparam, lparam );
    if (msg == WM_NCCREATE) nested_defwindow_result = result;
    return result;
}

static int fail( const char *stage )
{
    fprintf( stderr, "I386_USER_CLASS_WINDOW_FAIL stage=%s error=%lu\n", stage, GetLastError() );
    return 1;
}

int main( void )
{
    static const WCHAR class_name[] = L"VKMT_i386_UserClassWindow";
    HINSTANCE instance = GetModuleHandleW( NULL );
    WNDCLASSEXW query = { sizeof(query) };
    WNDCLASSEXW wc = { sizeof(wc) };
    HWND window;
    HWND default_window;
    LRESULT result;
    DWORD process_id = 0;
    DWORD thread_id;
    ATOM atom;

    wc.lpfnWndProc = probe_wndproc;
    wc.hInstance = instance;
    wc.lpszClassName = class_name;

    if (!(atom = RegisterClassExW( &wc ))) return fail( "RegisterClassExW" );
    if (!GetClassInfoExW( instance, class_name, &query )) return fail( "GetClassInfoExW" );
    if (query.hInstance != instance || query.lpfnWndProc != probe_wndproc)
    {
        fprintf( stderr,
                 "I386_USER_CLASS_WINDOW_FAIL stage=class_roundtrip instance=%p/%p wndproc=%p/%p\n",
                 query.hInstance, instance, query.lpfnWndProc, probe_wndproc );
        return 1;
    }

    window = CreateWindowExW( 0, class_name, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                              NULL, instance, &userdata_cookie );
    if (!window) return fail( "CreateWindowExW" );
    thread_id = GetWindowThreadProcessId( window, &process_id );
    if (thread_id != GetCurrentThreadId() || process_id != GetCurrentProcessId())
    {
        fprintf( stderr,
                 "I386_USER_CLASS_WINDOW_FAIL stage=GetWindowThreadProcessId "
                 "thread=%lu/%lu process=%lu/%lu\n",
                 thread_id, GetCurrentThreadId(), process_id, GetCurrentProcessId() );
        return 1;
    }
    if (GetWindowLongW( window, GWL_USERDATA ) != (LONG)(LONG_PTR)&userdata_cookie)
    {
        fprintf( stderr,
                 "I386_USER_CLASS_WINDOW_FAIL stage=GWL_USERDATA value=%lx expected=%lx\n",
                 GetWindowLongW( window, GWL_USERDATA ), (LONG)(LONG_PTR)&userdata_cookie );
        return 1;
    }
    if (create_count != 1)
    {
        fprintf( stderr, "I386_USER_CLASS_WINDOW_FAIL stage=WM_CREATE count=%ld\n", create_count );
        return 1;
    }

    result = SendMessageW( window, WM_VKMT_PING, 0, 0 );
    if (result != VKMT_PING_RESULT)
    {
        fprintf( stderr, "I386_USER_CLASS_WINDOW_FAIL stage=WNDPROC result=%Ix\n",
                 (UINT_PTR)result );
        return 1;
    }

    if (!DestroyWindow( window )) return fail( "DestroyWindow" );
    if (destroy_count != 1)
    {
        fprintf( stderr, "I386_USER_CLASS_WINDOW_FAIL stage=WM_DESTROY count=%ld\n", destroy_count );
        return 1;
    }
    if (!UnregisterClassW( class_name, instance )) return fail( "UnregisterClassW" );

    wc.lpfnWndProc = default_wndproc;
    wc.lpszClassName = L"VKMT_i386_DefaultWindow";
    if (!RegisterClassExW( &wc )) return fail( "RegisterClassExW(default)" );
    default_window = CreateWindowExW( WS_EX_NOACTIVATE, wc.lpszClassName, L"",
                                      WS_POPUP, 0, 0, 0, 0, NULL, NULL,
                                      instance, &userdata_cookie );
    if (!default_window)
    {
        fprintf( stderr,
                 "I386_USER_CLASS_WINDOW_FAIL stage=CreateWindowExW(default) "
                 "error=%lu nested_defwindow_result=%Ix\n",
                 GetLastError(), (UINT_PTR)nested_defwindow_result );
        return 1;
    }
    if (GetWindowLongW( default_window, GWL_USERDATA ) != (LONG)(LONG_PTR)&userdata_cookie)
        return fail( "GetWindowLongW(default)" );
    if (!DestroyWindow( default_window )) return fail( "DestroyWindow(default)" );
    if (!UnregisterClassW( wc.lpszClassName, instance ))
        return fail( "UnregisterClassW(default)" );

    printf( "I386_USER_CLASS_WINDOW_OK atom=%u\n", atom );
    return 0;
}
