import lldb


def _u(process, address, size):
    error = lldb.SBError()
    value = process.ReadUnsignedFromMemory(address, size, error)
    return None if error.Fail() else value


def _utf16(process, address, length):
    error = lldb.SBError()
    data = process.ReadMemory(address, length, error)
    return data.decode("utf-16-le", errors="replace") if error.Success() else "<unreadable>"


def dump_wow64_modules(debugger, command, result, internal_dict):
    args = command.split()
    if not args:
        result.SetError("usage: dump-wow64-modules <host-teb32> [arena-bias]")
        return
    process = debugger.GetSelectedTarget().GetProcess()
    native_teb = int(args[0], 0)
    bias = int(args[1], 0) if len(args) > 1 else 0x10000000000
    wow_offset = _u(process, native_teb + 0x180C, 4)
    if wow_offset is None:
        result.SetError("native TEB has no readable WowTebOffset")
        return
    if wow_offset & 0x80000000:
        wow_offset -= 0x100000000
    teb = native_teb + wow_offset
    peb_guest = _u(process, teb + 0x30, 4)
    if not peb_guest:
        result.SetError("TEB32 has no PEB32")
        return
    peb = bias + peb_guest
    ldr_guest = _u(process, peb + 0x0C, 4)
    if not ldr_guest:
        result.SetError("PEB32 has no loader data")
        return
    head = bias + ldr_guest + 0x0C
    node_guest = _u(process, head, 4)
    seen = set()
    result.PutCString("WOW64_MODULES native_teb=%#x teb32=%#x peb=%#x ldr=%#x" %
                      (native_teb, teb, peb_guest, ldr_guest))
    while node_guest and node_guest not in seen and bias + node_guest != head:
        seen.add(node_guest)
        entry = bias + node_guest
        base = _u(process, entry + 0x18, 4)
        size = _u(process, entry + 0x20, 4)
        name_len = _u(process, entry + 0x2C, 2)
        name_ptr = _u(process, entry + 0x30, 4)
        name = _utf16(process, bias + name_ptr, name_len) if name_ptr and name_len else "<unnamed>"
        result.PutCString("  base=%#x size=%#x end=%#x name=%s" % (base, size, base + size, name))
        node_guest = _u(process, entry, 4)


def dump_native_modules(debugger, command, result, internal_dict):
    args = command.split()
    if len(args) != 1:
        result.SetError("usage: dump-native-modules <native-teb>")
        return
    process = debugger.GetSelectedTarget().GetProcess()
    teb = int(args[0], 0)
    peb = _u(process, teb + 0x60, 8)
    ldr = _u(process, peb + 0x18, 8) if peb else None
    if not ldr:
        result.SetError("native PEB has no loader data")
        return
    head = ldr + 0x10
    node = _u(process, head, 8)
    seen = set()
    result.PutCString("NATIVE_MODULES teb=%#x peb=%#x ldr=%#x" % (teb, peb, ldr))
    while node and node not in seen and node != head:
        seen.add(node)
        base = _u(process, node + 0x30, 8)
        size = _u(process, node + 0x40, 4)
        name_len = _u(process, node + 0x58, 2)
        name_ptr = _u(process, node + 0x60, 8)
        name = _utf16(process, name_ptr, name_len) if name_ptr and name_len else "<unnamed>"
        result.PutCString("  base=%#x size=%#x end=%#x name=%s" % (base, size, base + size, name))
        node = _u(process, node, 8)


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand(
        "command script add -f dump_wow64_modules.dump_wow64_modules dump-wow64-modules"
    )
    debugger.HandleCommand(
        "command script add -f dump_wow64_modules.dump_native_modules dump-native-modules"
    )
