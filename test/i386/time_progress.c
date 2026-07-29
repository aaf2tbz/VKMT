#include <windows.h>
#include <stdio.h>

int main( void )
{
    DWORD before = GetTickCount();
    ULONGLONG before64 = GetTickCount64();
    LARGE_INTEGER counter_before, counter_after, frequency;
    DWORD after, delta;
    ULONGLONG after64;

    if (!QueryPerformanceFrequency( &frequency ) ||
        !QueryPerformanceCounter( &counter_before ))
    {
        fprintf( stderr, "I386_TIME_PROGRESS_FAIL stage=counter_start error=%lu\n",
                 GetLastError() );
        return 1;
    }
    Sleep( 100 );
    after = GetTickCount();
    after64 = GetTickCount64();
    if (!QueryPerformanceCounter( &counter_after ))
    {
        fprintf( stderr, "I386_TIME_PROGRESS_FAIL stage=counter_end error=%lu\n",
                 GetLastError() );
        return 1;
    }

    delta = after - before;
    if (delta < 50 || after64 - before64 < 50 ||
        counter_after.QuadPart <= counter_before.QuadPart)
    {
        fprintf( stderr,
                 "I386_TIME_PROGRESS_FAIL tick=%lu tick64=%llu qpc=%lld frequency=%lld\n",
                 delta, after64 - before64,
                 counter_after.QuadPart - counter_before.QuadPart,
                 frequency.QuadPart );
        return 1;
    }

    printf( "I386_TIME_PROGRESS_OK tick=%lu tick64=%llu qpc=%lld\n",
            delta, after64 - before64,
            counter_after.QuadPart - counter_before.QuadPart );
    return 0;
}
