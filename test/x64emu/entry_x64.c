/*
 * VKMT M2 probe: pure x86_64 console executable.
 * Prints a line and returns the conventional success status. Under VKMT
 * ARM64EC Wine this must reach xtajit64's BeginSimulation and tear down with
 * an exact process status of zero.
 */

#include <stdio.h>

int main( void )
{
    printf( "VKMT entry_x64: hello from x86-64 guest\n" );
    fflush( stdout );
    return 0;
}
