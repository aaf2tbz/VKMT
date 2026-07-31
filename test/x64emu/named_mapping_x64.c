#include <windows.h>
#include <stdio.h>
#include <string.h>

static int child_main(const char *name)
{
    HANDLE mapping;
    DWORD error;

    SetLastError( 0xdeadbeef );
    mapping = CreateFileMappingA( INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, 4096, name );
    error = GetLastError();
    printf( "CHILD mapping=%p error=%lu\n", mapping, error );
    if (mapping) CloseHandle( mapping );
    return mapping && error == ERROR_ALREADY_EXISTS ? 0 : 10;
}

int main(int argc, char **argv)
{
    char name[128], command[1024], image[MAX_PATH];
    PROCESS_INFORMATION process;
    STARTUPINFOA startup = { sizeof(startup) };
    HANDLE first, second;
    DWORD error, exit_code;

    if (argc == 3 && !strcmp( argv[1], "--child" )) return child_main( argv[2] );

    snprintf( name, sizeof(name), "Local\\VKMT.NamedMapping.%lu", GetCurrentProcessId() );
    first = CreateFileMappingA( INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, 4096, name );
    if (!first)
    {
        printf( "FIRST failed error=%lu\n", GetLastError() );
        return 1;
    }

    SetLastError( 0xdeadbeef );
    second = CreateFileMappingA( INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, 4096, name );
    error = GetLastError();
    printf( "SAME_PROCESS mapping=%p error=%lu\n", second, error );
    if (!second || error != ERROR_ALREADY_EXISTS) return 2;
    CloseHandle( second );

    if (!GetModuleFileNameA( NULL, image, sizeof(image) )) return 3;
    snprintf( command, sizeof(command), "\"%s\" --child \"%s\"", image, name );
    if (!CreateProcessA( NULL, command, NULL, NULL, TRUE, 0, NULL, NULL, &startup, &process ))
    {
        printf( "CREATE_CHILD failed error=%lu\n", GetLastError() );
        return 4;
    }
    WaitForSingleObject( process.hProcess, INFINITE );
    if (!GetExitCodeProcess( process.hProcess, &exit_code )) exit_code = 5;
    CloseHandle( process.hThread );
    CloseHandle( process.hProcess );
    CloseHandle( first );
    printf( "NAMED_MAPPING_X64_%s child=%lu\n", exit_code ? "FAIL" : "OK", exit_code );
    return exit_code ? 6 : 0;
}
