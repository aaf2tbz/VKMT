/*
 * VKMT M2 probe: minimal guest snippet exercising the full enter/return
 * round trip.  The entry point is exactly:
 *     mov  eax, 7
 *     ret
 * The emulator skeleton (ExitToX64 path) plants the RetToEntryThunk
 * marker on the guest stack; the interpreter runs both instructions, the
 * `ret` pops the marker, and control is handed back to the native EC
 * caller at the return address captured on entry, with guest RAX (=7) in
 * x8 where the exit thunk expects it.  Expected: "guest returned to EC
 * caller" trace on the vkmtx64 channel and graceful process exit.
 */

__attribute__((naked)) void entry( void )
{
    __asm__( "movl $7, %eax\n\t"
             "ret" );
}
