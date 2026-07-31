import lldb


def _read_uint(process, address, size):
    error = lldb.SBError()
    data = process.ReadMemory(address, size, error)
    if not error.Success() or len(data) != size:
        raise RuntimeError(f"read {size} bytes at 0x{address:x}: {error}")
    return int.from_bytes(data, "little")


def _symbol_name(target, address):
    context = target.ResolveLoadAddress(address).GetSymbolContext(lldb.eSymbolContextEverything)
    function = context.GetFunction()
    if function.IsValid() and function.GetName():
        return function.GetName()
    symbol = context.GetSymbol()
    return symbol.GetName() if symbol.IsValid() else "?"


def _object_name(process, obj):
    name = _read_uint(process, obj + 0x20, 8)
    if not name:
        return "<unnamed>"
    length = _read_uint(process, name + 0x20, 4)
    if not length:
        return "<unnamed>"
    error = lldb.SBError()
    data = process.ReadMemory(name + 0x24, length, error)
    return data.decode("utf-16-le", errors="replace") if error.Success() else "<unreadable>"


def _handles_for_object(process, thread, obj):
    owner = _read_uint(process, thread + 0x88, 8)
    table = _read_uint(process, owner + 0x88, 8)
    if not table:
        return []
    last = _read_uint(process, table + 0x54, 4)
    entries = _read_uint(process, table + 0x60, 8)
    handles = []
    for index in range(last + 1):
        if _read_uint(process, entries + index * 0x10, 8) == obj:
            handles.append((index + 1) << 2)
    return handles


def dump_steam_waits(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    wanted = {int(value, 0) for value in command.split()} if command.strip() else set()
    head_value = target.FindFirstGlobalVariable("thread_list")
    if not head_value.IsValid():
        result.SetError("thread_list is unavailable")
        return
    head = head_value.GetLoadAddress()
    node = _read_uint(process, head, 8)
    seen = set()
    while node != head and node not in seen:
        seen.add(node)
        thread = node - 0x58  # offsetof(struct thread, entry)
        thread_id = _read_uint(process, thread + 0x90, 4)
        wait = _read_uint(process, thread + 0xc8, 8)
        if not wanted or thread_id in wanted:
            request_fd = _read_uint(process, thread + 0x1d8, 8)
            reply_fd = _read_uint(process, thread + 0x1e0, 8)
            wait_fd = _read_uint(process, thread + 0x1e8, 8)
            state = _read_uint(process, thread + 0x1f0, 4)
            unix_pid = _read_uint(process, thread + 0x1f8, 4)
            unix_tid = _read_uint(process, thread + 0x1fc, 4)
            teb = _read_uint(process, thread + 0x210, 8)
            entry_point = _read_uint(process, thread + 0x218, 8)
            req_toread = _read_uint(process, thread + 0x1c0, 4)
            reply_towrite = _read_uint(process, thread + 0x1d4, 4)

            def unix_fd(fd):
                return _read_uint(process, fd + 0xc4, 4) if fd else 0xffffffff

            result.AppendMessage(
                f"thread={thread_id} host={unix_pid}/{unix_tid} state={state} "
                f"teb=0x{teb:x} entry=0x{entry_point:x} "
                f"wait=0x{wait:x} req_toread={req_toread} reply_towrite={reply_towrite} "
                f"request_fd=0x{request_fd:x}/{unix_fd(request_fd)} "
                f"reply_fd=0x{reply_fd:x}/{unix_fd(reply_fd)} "
                f"wait_fd=0x{wait_fd:x}/{unix_fd(wait_fd)}"
            )
        if wait and (not wanted or thread_id in wanted):
            count = _read_uint(process, wait + 0x10, 4)
            flags = _read_uint(process, wait + 0x14, 4)
            select = _read_uint(process, wait + 0x1c, 4)
            key = _read_uint(process, wait + 0x20, 8)
            cookie = _read_uint(process, wait + 0x28, 8)
            status = _read_uint(process, wait + 0x40, 4)
            result.AppendMessage(
                f"  wait_detail count={count} flags=0x{flags:x} select={select} "
                f"key=0x{key:x} cookie=0x{cookie:x} status=0x{status:x}"
            )
            for index in range(count):
                queue = wait + 0x48 + index * 0x20
                obj = _read_uint(process, queue + 0x10, 8)
                ops = _read_uint(process, obj + 0x08, 8)
                dump = _read_uint(process, ops + 0x10, 8)
                dump_name = _symbol_name(target, dump)
                result.AppendMessage(
                    f"  object[{index}]=0x{obj:x} ops=0x{ops:x} dump={dump_name} "
                    f"name={_object_name(process, obj)} "
                    f"handles={[hex(handle) for handle in _handles_for_object(process, thread, obj)]}"
                )
                if dump_name == "event_dump":
                    sync = _read_uint(process, obj + 0x48, 8)
                    sync_ops = _read_uint(process, sync + 0x08, 8)
                    sync_dump = _read_uint(process, sync_ops + 0x10, 8)
                    bits = _read_uint(process, sync + 0x48, 4)
                    result.AppendMessage(
                        f"    sync=0x{sync:x} dump={_symbol_name(target, sync_dump)} "
                        f"manual={bits & 1} signaled={(bits >> 1) & 1}"
                    )
                elif dump_name == "dump_thread":
                    target_id = _read_uint(process, obj + 0x90, 4)
                    target_state = _read_uint(process, obj + 0x1f0, 4)
                    target_exit = _read_uint(process, obj + 0x1f4, 4)
                    target_pid = _read_uint(process, obj + 0x1f8, 4)
                    target_tid = _read_uint(process, obj + 0x1fc, 4)
                    result.AppendMessage(
                        f"    target_thread={target_id} host={target_pid}/{target_tid} "
                        f"state={target_state} exit=0x{target_exit:x}"
                    )
        node = _read_uint(process, node, 8)


def dump_process_thread_handles(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    wanted = int(command.strip(), 0)
    head_value = target.FindFirstGlobalVariable("thread_list")
    head = head_value.GetLoadAddress()
    node = _read_uint(process, head, 8)
    owner_thread = 0
    seen = set()
    while node != head and node not in seen:
        seen.add(node)
        thread = node - 0x58
        if _read_uint(process, thread + 0x90, 4) == wanted:
            owner_thread = thread
            break
        node = _read_uint(process, node, 8)
    if not owner_thread:
        result.SetError(f"active thread {wanted} not found")
        return
    owner = _read_uint(process, owner_thread + 0x88, 8)
    table = _read_uint(process, owner + 0x88, 8)
    last = _read_uint(process, table + 0x54, 4)
    entries = _read_uint(process, table + 0x60, 8)
    for index in range(last + 1):
        obj = _read_uint(process, entries + index * 0x10, 8)
        if not obj:
            continue
        ops = _read_uint(process, obj + 0x08, 8)
        dump = _read_uint(process, ops + 0x10, 8)
        if _symbol_name(target, dump) != "dump_thread":
            continue
        result.AppendMessage(
            f"handle=0x{((index + 1) << 2):x} object=0x{obj:x} "
            f"thread={_read_uint(process, obj + 0x90, 4)} "
            f"state={_read_uint(process, obj + 0x1f0, 4)} "
            f"exit=0x{_read_uint(process, obj + 0x1f4, 4):x} "
            f"host={_read_uint(process, obj + 0x1f8, 4)}/"
            f"{_read_uint(process, obj + 0x1fc, 4)} "
            f"teb=0x{_read_uint(process, obj + 0x210, 8):x}"
        )


def dump_host_process_handles(debugger, command, result, internal_dict):
    """Print every wineserver handle owned by the process with a host PID."""
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    wanted = int(command.strip(), 0)
    head_value = target.FindFirstGlobalVariable("thread_list")
    head = head_value.GetLoadAddress()
    node = _read_uint(process, head, 8)
    owner = 0
    seen = set()
    while node != head and node not in seen:
        seen.add(node)
        thread = node - 0x58
        if _read_uint(process, thread + 0x1f8, 4) == wanted:
            owner = _read_uint(process, thread + 0x88, 8)
            break
        node = _read_uint(process, node, 8)
    if not owner:
        result.SetError(f"host process {wanted} not found")
        return
    table = _read_uint(process, owner + 0x88, 8)
    last = _read_uint(process, table + 0x54, 4)
    entries = _read_uint(process, table + 0x60, 8)
    for index in range(last + 1):
        entry = entries + index * 0x10
        obj = _read_uint(process, entry, 8)
        if not obj:
            continue
        access = _read_uint(process, entry + 8, 4)
        ops = _read_uint(process, obj + 0x08, 8)
        dump = _read_uint(process, ops + 0x10, 8)
        result.AppendMessage(
            f"handle=0x{((index + 1) << 2):x} object=0x{obj:x} "
            f"type={_symbol_name(target, dump)} access=0x{access:x}"
        )


def dump_object_owners(debugger, command, result, internal_dict):
    """Find every process handle table entry referencing a server object."""
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    wanted = int(command.strip(), 0)
    head = target.FindFirstGlobalVariable("thread_list").GetLoadAddress()
    node = _read_uint(process, head, 8)
    seen_nodes = set()
    seen_owners = set()
    while node != head and node not in seen_nodes:
        seen_nodes.add(node)
        thread = node - 0x58
        owner = _read_uint(process, thread + 0x88, 8)
        host_pid = _read_uint(process, thread + 0x1f8, 4)
        node = _read_uint(process, node, 8)
        if owner in seen_owners:
            continue
        seen_owners.add(owner)
        table = _read_uint(process, owner + 0x88, 8)
        if not table:
            continue
        last = _read_uint(process, table + 0x54, 4)
        entries = _read_uint(process, table + 0x60, 8)
        for index in range(last + 1):
            if _read_uint(process, entries + index * 0x10, 8) == wanted:
                result.AppendMessage(
                    f"host={host_pid} process=0x{owner:x} "
                    f"handle=0x{((index + 1) << 2):x}"
                )


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand(
        "command script add -f dump_wineserver_waits.dump_steam_waits dump_steam_waits"
    )
    debugger.HandleCommand(
        "command script add -f dump_wineserver_waits.dump_process_thread_handles "
        "dump-process-thread-handles"
    )
    debugger.HandleCommand(
        "command script add -f dump_wineserver_waits.dump_host_process_handles "
        "dump-host-process-handles"
    )
    debugger.HandleCommand(
        "command script add -f dump_wineserver_waits.dump_object_owners "
        "dump-object-owners"
    )
