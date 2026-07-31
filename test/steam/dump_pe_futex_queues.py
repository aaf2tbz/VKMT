import lldb


def _u(process, address, size, error):
    error.Clear()
    value = process.ReadUnsignedFromMemory(address, size, error)
    return None if error.Fail() else value


def dump_pe_futex_queues(debugger, command, result, internal_dict):
    """Walk the two ARM64X ntdll futex queue arrays in the stopped process."""
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    error = lldb.SBError()
    args = command.split()
    if len(args) != 1:
        result.PutCString("usage: dump-pe-futex-queues <mapped-ntdll-base>")
        return

    image_base = int(args[0], 0)
    # llvm-nm reports two ARM64X copies.  Keep both visible until the active
    # execution half is established from the live queue contents.
    for symbol_va in (0x180163580, 0x180166E60):
        queues = image_base + symbol_va - 0x180000000
        result.PutCString("FUTEX_ARRAY address=%#x symbol_va=%#x" % (queues, symbol_va))
        total = 0
        for bucket in range(256):
            head = queues + bucket * 24
            node = _u(process, head, 8, error)
            if node in (None, 0, head):
                continue
            seen = set()
            while node not in seen and node not in (0, head):
                seen.add(node)
                next_node = _u(process, node, 8, error)
                prev_node = _u(process, node + 8, 8, error)
                address = _u(process, node + 16, 8, error)
                tid = _u(process, node + 24, 4, error)
                event = _u(process, node + 32, 8, error)
                if None in (next_node, prev_node, address, tid, event):
                    result.PutCString("  bucket=%u node=%#x unreadable" % (bucket, node))
                    break
                values = []
                for size in (1, 2, 4, 8):
                    value = _u(process, address, size, error) if address else None
                    values.append("%u:%s" % (size, "?" if value is None else hex(value)))
                result.PutCString(
                    "  bucket=%u node=%#x next=%#x prev=%#x addr=%#x "
                    "tid=%u event=%#x values=[%s]"
                    % (bucket, node, next_node, prev_node, address, tid, event, ",".join(values))
                )
                total += 1
                node = next_node
        result.PutCString("FUTEX_ARRAY entries=%u" % total)


def dump_i386_futex_queues(debugger, command, result, internal_dict):
    """Walk the i386 ntdll queue array through Wine's high guest arena."""
    process = debugger.GetSelectedTarget().GetProcess()
    error = lldb.SBError()
    args = command.split()
    if len(args) not in (1, 2):
        result.PutCString("usage: dump-i386-futex-queues <loaded-guest-base> [arena-bias]")
        return
    loaded_base = int(args[0], 0)
    bias = int(args[1], 0) if len(args) == 2 else 0x10000000000
    preferred_base = 0x7BC00000
    preferred_symbol = 0x7BC91184
    queues_guest = loaded_base + preferred_symbol - preferred_base
    queues_host = bias + queues_guest
    total = 0
    result.PutCString("I386_FUTEX_ARRAY guest=%#x host=%#x" % (queues_guest, queues_host))
    for bucket in range(256):
        head_guest = queues_guest + bucket * 12
        head_host = queues_host + bucket * 12
        node_guest = _u(process, head_host, 4, error)
        if node_guest in (None, 0, head_guest):
            continue
        seen = set()
        while node_guest not in seen and node_guest not in (0, head_guest):
            seen.add(node_guest)
            node_host = bias + node_guest
            next_guest = _u(process, node_host, 4, error)
            prev_guest = _u(process, node_host + 4, 4, error)
            address = _u(process, node_host + 8, 4, error)
            tid = _u(process, node_host + 12, 4, error)
            event = _u(process, node_host + 16, 4, error)
            if None in (next_guest, prev_guest, address, tid, event):
                result.PutCString("  bucket=%u node=%#x unreadable" % (bucket, node_guest))
                break
            values = []
            for size in (1, 2, 4, 8):
                value = _u(process, bias + address, size, error) if address else None
                values.append("%u:%s" % (size, "?" if value is None else hex(value)))
            result.PutCString(
                "  bucket=%u node=%#x next=%#x prev=%#x addr=%#x "
                "tid=%u event=%#x values=[%s]"
                % (bucket, node_guest, next_guest, prev_guest, address, tid, event,
                   ",".join(values))
            )
            total += 1
            node_guest = next_guest
    result.PutCString("I386_FUTEX_ARRAY entries=%u" % total)


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand(
        "command script add -f dump_pe_futex_queues.dump_pe_futex_queues "
        "dump-pe-futex-queues"
    )
    debugger.HandleCommand(
        "command script add -f dump_pe_futex_queues.dump_i386_futex_queues "
        "dump-i386-futex-queues"
    )
