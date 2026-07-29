#include <windows.h>
#include <stdio.h>

#define WM_VKMT_PING (WM_APP + 0x386)
#define VKMT_PING_RESULT ((LRESULT)0x3865a11)

static LONG create_count;
static LONG destroy_count;

static LRESULT CALLBACK probe_wndproc( HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam )
{
    switch (msg)
    {
    case WM_CREATE:
        InterlockedIncrement( &create_count );
        return 0;
    case WM_DESTROY:
        InterlockedIncrement( &destroy_count );
        return 0;
    case WM_VKMT_PING:
        return VKMT_PING_RESULT;
    default:
        return DefWindowProcW( hwnd, msg, wparam, lparam );
    }
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
    LRESULT result;
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
                              NULL, instance, NULL );
    if (!window) return fail( "CreateWindowExW" );
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

    printf( "I386_USER_CLASS_WINDOW_OK atom=%u\n", atom );
    return 0;
}
