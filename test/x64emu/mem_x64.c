/* M3 probe 3: memory APIs through the emulator.
 * VirtualAlloc/VirtualFree, memcpy/memset loops with value checks,
 * file mapping round trip. Exit code 0 iff all self-checks pass. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

static void check( const char *name, int ok )
{
    if (!ok)
    {
        printf( "FAIL %s\n", name );
        failures++;
    }
}

int main( void )
{
    size_t i;
    unsigned char *p;
    volatile unsigned char sink;

    /* VirtualAlloc reserve+commit, touch every page, free */
    p = (unsigned char *)VirtualAlloc( NULL, 4 * 1024 * 1024, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE );
    check( "VirtualAlloc", p != NULL );
    if (!p) return 1;
    printf( "VirtualAlloc at %p\n", p );

    memset( p, 0xA5, 4 * 1024 * 1024 );
    check( "memset 4MB", p[0] == 0xA5 && p[4 * 1024 * 1024 - 1] == 0xA5 );

    /* memcpy loop with verification (exercises rep movsb fast path + tail) */
    for (i = 0; i < 256; i++) p[i] = (unsigned char)i;
    memcpy( p + 1024 * 1024, p, 1024 * 1024 );
    check( "memcpy 1MB", memcmp( p, p + 1024 * 1024, 1024 * 1024 ) == 0 );

    /* overlapping memmove */
    memmove( p + 512, p, 1024 * 1024 );
    check( "memmove overlap", p[512] == 0 && p[511 + 256] == 255 );

    /* byte-write loop over every page */
    for (i = 0; i < 4 * 1024 * 1024; i += 4096) p[i] = 0x11;
    sink = 0;
    for (i = 0; i < 4 * 1024 * 1024; i += 4096) sink |= p[i];
    check( "page touch", sink == 0x11 );

    /* decommit + recommit */
    check( "VirtualFree decommit", VirtualFree( p, 1024 * 1024, MEM_DECOMMIT ) );
    check( "VirtualAlloc recommit",
           VirtualAlloc( p, 1024 * 1024, MEM_COMMIT, PAGE_READWRITE ) == p );
    check( "VirtualFree full", VirtualFree( p, 0, MEM_RELEASE ) );

    /* file mapping round trip */
    {
        HANDLE hf, hm;
        char *view;
        const char *msg = "VKMT MapViewOfFile round trip payload";
        char buf[128] = { 0 };

        hf = CreateFileA( "C:\\mem_x64_probe.tmp", GENERIC_READ | GENERIC_WRITE,
                          0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL );
        check( "CreateFile", hf != INVALID_HANDLE_VALUE );
        SetFilePointer( hf, 4096, NULL, FILE_BEGIN );
        SetEndOfFile( hf );

        hm = CreateFileMappingA( hf, NULL, PAGE_READWRITE, 0, 4096, NULL );
        check( "CreateFileMapping", hm != NULL );
        view = (char *)MapViewOfFile( hm, FILE_MAP_ALL_ACCESS, 0, 0, 4096 );
        check( "MapViewOfFile", view != NULL );
        strcpy( view, msg );
        check( "view write", view[0] == 'V' );
        FlushViewOfFile( view, 0 );
        UnmapViewOfFile( view );
        CloseHandle( hm );

        SetFilePointer( hf, 0, NULL, FILE_BEGIN );
        {
            DWORD got = 0;
            ReadFile( hf, buf, sizeof(buf) - 1, &got, NULL );
            check( "mapping round trip", got > 0 && strcmp( buf, msg ) == 0 );
        }
        CloseHandle( hf );
        DeleteFileA( "C:\\mem_x64_probe.tmp" );
    }

    printf( "mem_x64: %s (%d failures)\n", failures ? "FAIL" : "OK", failures );
    return failures ? 1 : 0;
}
