#!/usr/bin/env python3
"""Print the exception and containing module from a Windows minidump."""

import pathlib
import struct
import sys


def unpack(fmt, data, offset):
    return struct.unpack_from(fmt, data, offset)


def utf16_string(data, rva):
    (size,) = unpack("<I", data, rva)
    return data[rva + 4 : rva + 4 + size].decode("utf-16-le", errors="replace")


def inspect(path):
    data = path.read_bytes()
    signature, version, stream_count, directory_rva = unpack("<IIII", data, 0)
    if signature != 0x504D444D:
        raise ValueError("not a minidump")

    streams = {}
    for index in range(stream_count):
        stream_type, size, rva = unpack("<III", data, directory_rva + index * 12)
        streams[stream_type] = (size, rva)

    exception = None
    if 6 in streams:
        _, rva = streams[6]
        thread_id = unpack("<I", data, rva)[0]
        code, flags = unpack("<II", data, rva + 8)
        address = unpack("<Q", data, rva + 24)[0]
        parameter_count = unpack("<I", data, rva + 32)[0]
        parameters = unpack("<" + "Q" * min(parameter_count, 15), data, rva + 40)
        exception = (thread_id, code, flags, address, parameters)

    modules = []
    if 4 in streams:
        _, rva = streams[4]
        (count,) = unpack("<I", data, rva)
        cursor = rva + 4
        for _ in range(count):
            base, size, checksum, timestamp, name_rva = unpack("<QIIII", data, cursor)
            modules.append((base, base + size, utf16_string(data, name_rva), timestamp, checksum))
            cursor += 108

    print(f"file={path}")
    print(f"version=0x{version:08x} streams={stream_count} modules={len(modules)}")
    if not exception:
        print("exception=none")
        return
    thread_id, code, flags, address, parameters = exception
    print(f"thread={thread_id} exception=0x{code:08x} flags=0x{flags:08x} address=0x{address:016x}")
    if parameters:
        print("parameters=" + ",".join(f"0x{value:x}" for value in parameters))
    for base, end, name, timestamp, checksum in modules:
        if base <= address < end:
            print(f"module={name} base=0x{base:016x} offset=0x{address - base:x} size=0x{end - base:x}")
            break
    else:
        print("module=<unmapped>")


def main():
    if len(sys.argv) < 2:
        raise SystemExit(f"usage: {sys.argv[0]} MINIDUMP...")
    for argument in sys.argv[1:]:
        inspect(pathlib.Path(argument))


if __name__ == "__main__":
    main()
