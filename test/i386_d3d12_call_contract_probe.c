/* Isolate the i386 D3D12CreateDevice call boundary.  The marker is updated
 * before and after the indirect call so a nonlocal WoW64 exit is observable
 * without enabling broad Wine relay tracing. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#define INITGUID
#include <d3d12.h>

typedef HRESULT (WINAPI *d3d12_create_device_fn)( IUnknown *, D3D_FEATURE_LEVEL, REFIID, void ** );

static void write_marker( const char *path, const char *text )
{
    HANDLE file;
    DWORD written;

    file = CreateFileA( path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL );
    if (file == INVALID_HANDLE_VALUE) return;
    WriteFile( file, text, lstrlenA( text ), &written, NULL );
    FlushFileBuffers( file );
    CloseHandle( file );
}

int main( int argc, char **argv )
{
    HMODULE module;
    d3d12_create_device_fn create_device;
    ID3D12Device *device = NULL;
    HRESULT hr;

    if (argc != 2) return 20;
    write_marker( argv[1], "P5_D3D12_CALL_START" );
    module = LoadLibraryA( "d3d12.dll" );
    if (!module) { write_marker( argv[1], "P5_D3D12_CALL_LOAD_FAILED" ); return 1; }
    create_device = (d3d12_create_device_fn)GetProcAddress( module, "D3D12CreateDevice" );
    if (!create_device) { write_marker( argv[1], "P5_D3D12_CALL_EXPORT_FAILED" ); return 2; }
    write_marker( argv[1], "P5_D3D12_CALL_ENTER" );
    hr = create_device( NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device );
    if (SUCCEEDED( hr ) && device) device->lpVtbl->Release( device );
    write_marker( argv[1], SUCCEEDED( hr ) ? "P5_D3D12_CALL_RETURN_OK" : "P5_D3D12_CALL_RETURN_FAILED" );
    return SUCCEEDED( hr ) ? 0 : 3;
}
