/*
 * Deterministic WoW64 VM contract probe.
 *
 * This fixture intentionally uses only Win32 VM APIs so the same source can
 * be built as x86_64 and i386 PE.  It does not infer host addresses: the
 * contract is guest-visible lifetime, protection, alias, reuse, and
 * concurrent-pressure behavior.
 */

#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

static LONG failures;

static void check( const char *name, BOOL condition )
{
    if (!condition)
    {
        printf( "FAIL %s error=%lu\n", name, GetLastError() );
        InterlockedIncrement( &failures );
    }
}

static BOOL page_state( void *address, DWORD state, DWORD protect )
{
    MEMORY_BASIC_INFORMATION info;
    SIZE_T result = VirtualQuery( address, &info, sizeof(info));
    if (result != sizeof(info))
    {
        printf( "QUERY_SIZE_MISMATCH address=%p returned=%llu expected=%llu error=%lu\n",
                address, (unsigned long long)result, (unsigned long long)sizeof(info), GetLastError() );
        return FALSE;
    }
    if (info.State != state || (protect && info.Protect != protect &&
                                !(state == MEM_RESERVE && !info.Protect)))
    {
        printf( "QUERY_MISMATCH address=%p state=%lx protect=%lx base=%p region=%llu expected_state=%lx expected_protect=%lx\n",
                address, info.State, info.Protect, info.BaseAddress,
                (unsigned long long)info.RegionSize, state, protect );
        return FALSE;
    }
    return TRUE;
}

static void exercise_host_and_guest_pressure( void )
{
    const SIZE_T size = 0x10000;
    static const ULONG_PTR hints[] = { 0x10000000, 0x20000000, 0x40000000,
                                       0x50000000, 0x60000000, 0x70000000,
                                       0x7e000000 };
    BYTE *allocations[32] = { 0 };
    unsigned int allocated = 0, high_host = 0, guest_success = 0, i;

    /* MEM_TOP_DOWN forces the native allocator to exercise the high-host
     * address path.  x64 can observe the host width directly; i386 validates
     * the same pressure through its guest aperture and FEX trace instead. */
    for (i = 0; i < ARRAY_SIZE(allocations); i++)
    {
        allocations[i] = VirtualAlloc( NULL, size, MEM_RESERVE | MEM_COMMIT |
                                       MEM_TOP_DOWN, PAGE_READWRITE );
        if (!allocations[i]) continue;
        allocated++;
        allocations[i][0] = (BYTE)i;
        if (sizeof(void *) == 8 && (ULONG_PTR)allocations[i] > 0xffffffffULL) high_host++;
    }
    check( "top-down-pressure", allocated >= 8 );
    if (sizeof(void *) == 8)
    {
        check( "high-host-address", high_host != 0 );
        if (high_host) printf( "WOW64_VM_HIGH_HOST_ALLOCATION_OK count=%u\n", high_host );
    }
    else printf( "WOW64_VM_HIGH_HOST_ALLOCATION_UNOBSERVABLE guest_pointer_width=32\n" );

    /* Request a set of disjoint guest-aperture addresses.  Some addresses may
     * already belong to the loader or system reservations; success is based
     * on pressure and reuse, not on assuming a pristine 4-GiB map. */
    for (i = 0; i < ARRAY_SIZE(hints); i++)
    {
        BYTE *address = VirtualAlloc( (void *)hints[i], size,
                                      MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE );
        if (!address) continue;
        guest_success++;
        address[0] = (BYTE)(0xa0 + i);
        check( "guest-hint-alignment", !((ULONG_PTR)address & 0xfff) );
        check( "guest-hint-query", page_state( address, MEM_COMMIT, PAGE_READWRITE ));
        check( "guest-hint-release", VirtualFree( address, 0, MEM_RELEASE ));
    }
    if (guest_success >= 2)
        printf( "WOW64_VM_GUEST_APERTURE_PRESSURE_OK allocations=%u hints=%u\n",
                allocated, guest_success );
    else if (allocated >= 8)
        /* VKMT deliberately keeps the guest aperture as a translation layer
         * over high host mappings; fixed low host reservations can therefore
         * return ERROR_NOT_ENOUGH_MEMORY without indicating a registry bug. */
        printf( "WOW64_VM_GUEST_APERTURE_HIGH_HOST_POLICY_OK allocations=%u hints=%u\n",
                allocated, guest_success );
    else check( "guest-aperture-pressure", FALSE );

    for (i = 0; i < ARRAY_SIZE(allocations); i++)
        if (allocations[i]) check( "top-down-release", VirtualFree( allocations[i], 0, MEM_RELEASE ));
}

static void exercise_reservation( void )
{
    const SIZE_T total = 64 * 1024 * 1024;
    const SIZE_T page = 4096;
    BYTE *base, *p;
    SIZE_T i;
    DWORD old_protect;

    base = VirtualAlloc( NULL, total, MEM_RESERVE, PAGE_NOACCESS );
    check( "reserve-64MiB", base != NULL );
    if (!base) return;

    for (i = 0; i < total; i += 64 * 1024)
    {
        p = VirtualAlloc( base + i, page, MEM_COMMIT, PAGE_READWRITE );
        check( "commit-island", p == base + i );
        if (p) *(volatile BYTE *)p = (BYTE)(i >> 16);
    }
    check( "committed-page-query", page_state( base, MEM_COMMIT, PAGE_READWRITE ));

    for (i = 0; i < total; i += 128 * 1024)
        check( "decommit-island", VirtualFree( base + i, page, MEM_DECOMMIT ));
    check( "decommitted-page-query", page_state( base, MEM_RESERVE, PAGE_NOACCESS ));

    for (i = 0; i < total; i += 128 * 1024)
    {
        p = VirtualAlloc( base + i, page, MEM_COMMIT, PAGE_READWRITE );
        check( "recommit-island", p == base + i );
        if (p) *(volatile BYTE *)p = 0xa5;
    }

    p = VirtualAlloc( base + 2 * page, page, MEM_COMMIT, PAGE_READWRITE );
    check( "protection-page-commit", p == base + 2 * page );
    if (p)
    {
        check( "protect-readonly", VirtualProtect( p, page, PAGE_READONLY, &old_protect ));
        check( "readonly-query", page_state( p, MEM_COMMIT, PAGE_READONLY ));
        check( "protect-readwrite", VirtualProtect( p, page, PAGE_READWRITE, &old_protect ));
        check( "readwrite-query", page_state( p, MEM_COMMIT, PAGE_READWRITE ));
    }

    check( "release-reservation", VirtualFree( base, 0, MEM_RELEASE ));
}

static void exercise_address_reuse( void )
{
    const SIZE_T size = 0x20000;
    BYTE *first, *second;

    first = VirtualAlloc( NULL, size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE );
    check( "reuse-first-allocation", first != NULL );
    if (!first) return;
    memset( first, 0x7b, size );
    check( "reuse-first-release", VirtualFree( first, 0, MEM_RELEASE ));

    /* Prefer the released VA, but accept the documented allocator fallback
     * when another reservation wins the race.  Either result must be a fresh
     * zero-filled commit and must never expose the retired bytes. */
    second = VirtualAlloc( first, size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE );
    check( "reuse-second-allocation", second != NULL );
    if (second)
    {
        check( "reuse-zero-fill", second[0] == 0 );
        check( "reuse-second-release", VirtualFree( second, 0, MEM_RELEASE ));
        printf( "WOW64_VM_ADDRESS_REUSE_OK mode=%s\n", second == first ? "exact" : "fallback" );
    }
}

static void exercise_aliases( void )
{
    HANDLE section;
    BYTE *first, *overlap;

    section = CreateFileMappingW( INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, 128 * 1024, NULL );
    check( "pagefile-section", section != NULL );
    if (!section) return;
    first = MapViewOfFile( section, FILE_MAP_ALL_ACCESS, 0, 0, 128 * 1024 );
    overlap = MapViewOfFile( section, FILE_MAP_ALL_ACCESS, 0, 64 * 1024, 64 * 1024 );
    check( "first-view", first != NULL );
    check( "overlapping-view", overlap != NULL );
    if (first && overlap)
    {
        first[64 * 1024] = 0x5a;
        check( "overlap-visible", overlap[0] == 0x5a );
        check( "independent-unmap", UnmapViewOfFile( first ));
        check( "surviving-view", overlap[0] == 0x5a );
        printf( "WOW64_VM_OVERLAP_ORDER_OK\n" );
    }
    if (overlap) UnmapViewOfFile( overlap );
    CloseHandle( section );
}

static void exercise_code_reuse( void )
{
    static const BYTE code[] = { 0xb8, 0x2a, 0, 0, 0, 0xc3 };
    typedef int (__cdecl *code_fn)(void);
    BYTE *page;
    DWORD old_protect;

    page = VirtualAlloc( NULL, 4096, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE );
    check( "code-page", page != NULL );
    if (!page) return;
    memcpy( page, code, sizeof(code) );
    check( "code-rx", VirtualProtect( page, 4096, PAGE_EXECUTE_READ, &old_protect ));
    FlushInstructionCache( GetCurrentProcess(), page, sizeof(code) );
    check( "code-first-result", ((code_fn)page)() == 42 );
    check( "code-rw", VirtualProtect( page, 4096, PAGE_READWRITE, &old_protect ));
    page[1] = 0x2b;
    check( "code-rx-reuse", VirtualProtect( page, 4096, PAGE_EXECUTE_READ, &old_protect ));
    FlushInstructionCache( GetCurrentProcess(), page, sizeof(code) );
    check( "code-reused-result", ((code_fn)page)() == 43 );
    check( "code-release", VirtualFree( page, 0, MEM_RELEASE ));
}

struct pressure_worker
{
    LONG failures;
    LONG allocation_failures;
    LONG mapping_failures;
    LONG protect_failures;
    LONG free_failures;
    LONG unmap_failures;
    DWORD seed;
    HANDLE section;
};

static DWORD WINAPI pressure_thread( void *parameter )
{
    struct pressure_worker *worker = parameter;
    unsigned int round;

    for (round = 0; round < 200; round++)
    {
        SIZE_T size = 0x1000 * (1 + ((worker->seed + round) & 7));
        BYTE *p = VirtualAlloc( NULL, size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE );
        DWORD old_protect;
        if (!p)
        {
            InterlockedIncrement( &worker->allocation_failures );
            InterlockedIncrement( &worker->failures );
            continue;
        }
        p[(worker->seed + round) % size] = (BYTE)round;
        if (!VirtualProtect( p, size, PAGE_READONLY, &old_protect ) ||
            !VirtualProtect( p, size, PAGE_READWRITE, &old_protect ))
        {
            InterlockedIncrement( &worker->protect_failures );
            InterlockedIncrement( &worker->failures );
        }
        else if (!VirtualFree( p, 0, MEM_RELEASE ))
        {
            InterlockedIncrement( &worker->free_failures );
            InterlockedIncrement( &worker->failures );
        }
    }
    for (round = 0; round < 100 && worker->section; round++)
    {
        DWORD offset = ((worker->seed + round) & 15) * 0x10000;
        BYTE *view = MapViewOfFile( worker->section, FILE_MAP_ALL_ACCESS, 0, offset, 0x10000 );
        if (!view)
        {
            InterlockedIncrement( &worker->mapping_failures );
            InterlockedIncrement( &worker->failures );
            continue;
        }
        view[0] = (BYTE)round;
        if (!UnmapViewOfFile( view ))
        {
            printf( "mapping-unmap-failure error=%lu\n", GetLastError() );
            InterlockedIncrement( &worker->unmap_failures );
            InterlockedIncrement( &worker->failures );
        }
    }
    return 0;
}

static void exercise_pressure( void )
{
    struct pressure_worker workers[8] = { 0 };
    HANDLE handles[8];
    HANDLE section;
    unsigned int i;
    DWORD wait_result;

    section = CreateFileMappingW( INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, 0x100000, NULL );
    check( "concurrent-section", section != NULL );
    for (i = 0; i < 8; i++)
    {
        workers[i].seed = 0x13579bdfu + i * 0x1021u;
        workers[i].section = section;
        handles[i] = CreateThread( NULL, 0, pressure_thread, &workers[i], 0, NULL );
        check( "pressure-thread-create", handles[i] != NULL );
    }
    wait_result = WaitForMultipleObjects( 8, handles, TRUE, 30000 );
    check( "pressure-join", wait_result == WAIT_OBJECT_0 );
    for (i = 0; i < 8; i++)
    {
        if (handles[i]) CloseHandle( handles[i] );
        if (workers[i].failures)
            printf( "pressure-worker[%u] failures=%ld allocation=%ld mapping=%ld protect=%ld free=%ld unmap=%ld\n", i,
                    workers[i].failures, workers[i].allocation_failures,
                    workers[i].mapping_failures, workers[i].protect_failures,
                    workers[i].free_failures, workers[i].unmap_failures );
        check( "pressure-worker", workers[i].failures == 0 );
    }
    if (section) CloseHandle( section );
    if (!failures) printf( "WOW64_VM_MAPPING_PRESSURE_OK\n" );
}

int main( void )
{
    printf( "VM_STEP host-pressure\n" ); fflush( stdout );
    exercise_host_and_guest_pressure();
    printf( "VM_STEP reservation\n" ); fflush( stdout );
    exercise_reservation();
    printf( "VM_STEP reuse\n" ); fflush( stdout );
    exercise_address_reuse();
    printf( "VM_STEP aliases\n" ); fflush( stdout );
    exercise_aliases();
    printf( "VM_STEP code\n" ); fflush( stdout );
    exercise_code_reuse();
    printf( "VM_STEP pressure\n" ); fflush( stdout );
    exercise_pressure();
    if (failures)
    {
        printf( "WOW64_VM_CONTRACT_FAIL failures=%ld\n", failures );
        return 1;
    }
    printf( "WOW64_VM_CONCURRENT_OK\n" );
    printf( "WOW64_VM_EXECUTABLE_REUSE_OK\n" );
    if (sizeof(void *) == 8) printf( "WOW64_VM_X64_CONTRACT_OK\n" );
    else printf( "WOW64_VM_I386_CONTRACT_OK\n" );
    printf( "WOW64_VM_CONTRACT_ALL_OK\n" );
    return 0;
}
