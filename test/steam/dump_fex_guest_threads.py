import lldb


def _u(process, address, size):
    error = lldb.SBError()
    value = process.ReadUnsignedFromMemory(address, size, error)
    return None if error.Fail() else value


def dump_fex_guest_threads(debugger, command, result, internal_dict):
    """Print the WoW64 FEX TLS and last stored i386 CPU state per Mach thread."""
    process = debugger.GetSelectedTarget().GetProcess()
    for thread in process:
        frame = thread.GetFrameAtIndex(0)
        x22_value = frame.FindRegister("x22")
        x28_value = frame.FindRegister("x28")
        syscall_frame = x22_value.GetValueAsUnsigned() if x22_value.IsValid() else 0
        live_x28 = x28_value.GetValueAsUnsigned() if x28_value.IsValid() else 0
        saved_x28 = _u(process, syscall_frame + 0xE0, 8) if syscall_frame else None
        teb = saved_x28 or live_x28
        pc = frame.GetPC()
        result.PutCString(
            "MACH_THREAD index=%u tid=%#x pc=%#x x22_frame=%#x "
            "live_x28=%#x saved_x28=%s teb=%#x"
            % (thread.GetIndexID(), thread.GetThreadID(), pc, syscall_frame,
               live_x28, "?" if saved_x28 is None else hex(saved_x28), teb)
        )
        if not teb:
            continue

        # AMD64 TEB.TlsSlots starts at 0x1480. FEX reserves slots 15..18.
        frontend = _u(process, teb + 0x14D8, 8)  # WineFEXRecoveryTLSSlot 11
        callret = _u(process, teb + 0x14F8, 8)
        thread_state = _u(process, teb + 0x1500, 8)  # WOW64_TLS_MAX_NUMBER - 3
        control = _u(process, teb + 0x1508, 4)
        entry_context = _u(process, teb + 0x1510, 8)
        result.PutCString(
            "  FEX_TLS frontend=%s callret=%s state=%s control=%s entry_context=%s"
            % tuple("?" if value is None else hex(value) for value in
                    (frontend, callret, thread_state, control, entry_context))
        )
        if not thread_state:
            continue
        current_frame = _u(process, thread_state, 8)
        if not current_frame:
            continue
        rip = _u(process, current_frame + 24, 8)
        gregs = [_u(process, current_frame + 32 + index * 8, 8) for index in range(8)]
        result.PutCString(
            "  GUEST frame=%#x eip=%s eax=%s ecx=%s edx=%s ebx=%s "
            "esp=%s ebp=%s esi=%s edi=%s"
            % ((current_frame, ) + tuple("?" if value is None else hex(value & 0xffffffff)
                                        for value in (rip, *gregs)))
        )


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand(
        "command script add -f dump_fex_guest_threads.dump_fex_guest_threads "
        "dump-fex-guest-threads"
    )
