import lldb


def _u(process, address, size):
    error = lldb.SBError()
    value = process.ReadUnsignedFromMemory(address, size, error)
    if error.Fail():
        raise RuntimeError("read %u bytes at %#x: %s" % (size, address, error))
    return value


def _s32(value):
    return value - 0x100000000 if value & 0x80000000 else value


EVENTS = {
    1: "crit-enter",
    2: "crit-acquired",
    3: "crit-recursive",
    4: "crit-leave",
    5: "crit-left",
    10: "loader-init",
    11: "loader-init-locked",
    12: "loader-init-done",
    20: "shutdown",
    21: "shutdown-locked",
    22: "shutdown-done",
    30: "exit-user-thread",
}


def dump_i386_loader_lock_trace(debugger, command, result, internal_dict):
    args = command.split()
    if len(args) not in (1, 2):
        result.PutCString("usage: dump-i386-loader-lock-trace <loaded-ntdll-base> [arena-bias]")
        return
    process = debugger.GetSelectedTarget().GetProcess()
    loaded_base = int(args[0], 0)
    bias = int(args[1], 0) if len(args) == 2 else 0x10000000000
    preferred_base = 0x7BC00000
    index_guest = loaded_base + 0x7BC91180 - preferred_base
    records_guest = loaded_base + 0x7BC91184 - preferred_base
    index = _u(process, bias + index_guest, 4)
    records = []
    for slot in range(256):
        address = bias + records_guest + slot * 28
        sequence = _u(process, address, 4)
        if not sequence:
            continue
        records.append((sequence, slot, address))
    result.PutCString("I386_LOADER_LOCK_TRACE index=%u records=%u" % (index, len(records)))
    for sequence, slot, address in sorted(records):
        tid = _u(process, address + 4, 4)
        event = _u(process, address + 8, 4)
        lock_count = _s32(_u(process, address + 12, 4))
        recursion = _s32(_u(process, address + 16, 4))
        owner = _u(process, address + 20, 4)
        argument = _u(process, address + 24, 4)
        result.PutCString(
            "seq=%u slot=%u tid=%u event=%s(%u) lock=%d recursion=%d owner=%u arg=%#x"
            % (sequence, slot, tid, EVENTS.get(event, "?"), event,
               lock_count, recursion, owner, argument)
        )


def dump_wow64_thread_term_trace(debugger, command, result, internal_dict):
    args = command.split()
    if len(args) != 1:
        result.PutCString("usage: dump-wow64-thread-term-trace <loaded-wow64-base>")
        return
    process = debugger.GetSelectedTarget().GetProcess()
    loaded_base = int(args[0], 0)
    preferred_base = 0x180000000
    index_address = loaded_base + 0x180058310 - preferred_base
    records_address = loaded_base + 0x180058320 - preferred_base
    index = _u(process, index_address, 4)
    records = []
    for slot in range(64):
        address = records_address + slot * 24
        sequence = _u(process, address, 4)
        if sequence:
            records.append((sequence, slot, address))
    result.PutCString("WOW64_THREAD_TERM_TRACE index=%u records=%u" % (index, len(records)))
    for sequence, slot, address in sorted(records):
        result.PutCString(
            "seq=%u slot=%u caller=%u target=%u handle=%#x exit=%#x query=%#x"
            % (sequence, slot,
               _u(process, address + 4, 4), _u(process, address + 8, 4),
               _u(process, address + 12, 4), _u(process, address + 16, 4),
               _u(process, address + 20, 4))
        )


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand(
        "command script add -f dump_loader_lock_trace.dump_i386_loader_lock_trace "
        "dump-i386-loader-lock-trace"
    )
    debugger.HandleCommand(
        "command script add -f dump_loader_lock_trace.dump_wow64_thread_term_trace "
        "dump-wow64-thread-term-trace"
    )
