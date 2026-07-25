/*
 * VKMT M2 probe: exercise the skeleton's exit-to-native path.
 *
 * Linked without CRT so the entry point is exactly:
 *     mov  ecx, 7
 *     jmp  [rip + __imp_ExitProcess]
 * The interpreter decodes both instructions, sees the IAT target is EC
 * code (kernel32's arm64x ExitProcess entry thunk) and does the M2
 * exit-to-native: NtContinue back into native EC code, which runs
 * ExitProcess(7).  Expected: process exits with status 7 and the
 * "exit simulation to native" trace on the vkmtx64 channel.
 */

__declspec(dllimport) void __stdcall ExitProcess( unsigned int code );

void entry( void )
{
    ExitProcess( 7 );
}
