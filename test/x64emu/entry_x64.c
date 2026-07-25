/*
 * VKMT M2 probe: pure x86_64 console executable.
 * Prints a line and returns 7.  Under VKMT arm64ec wine this must reach
 * xtajit64's BeginSimulation; the M2 skeleton then either exits to native
 * code or terminates cleanly with its own diagnostic.
 */

#include <stdio.h>

int main( void )
{
    printf( "VKMT entry_x64: hello from x86-64 guest\n" );
    fflush( stdout );
    return 7;
}
