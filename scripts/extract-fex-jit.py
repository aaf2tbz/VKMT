#!/usr/bin/env python3
"""Extract FEXJIT01 debug records to raw AArch64 bytes and a RIP map."""

import pathlib
import re
import struct
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: extract-fex-jit.py TRACE RAW MAP", file=sys.stderr)
        return 2

    trace_path, raw_path, map_path = map(pathlib.Path, sys.argv[1:])
    trace = trace_path.read_text(encoding="utf-8", errors="replace")
    raw = bytearray()
    mapping = []
    current_rip = None
    current_size = None
    current_words = bytearray()

    for line in trace.splitlines():
        begin = re.search(r"FEXJIT01 BEGIN rip=([0-9a-fA-F]+) size=([0-9a-fA-F]+)", line)
        word = re.search(r"FEXJIT01 WORD ([0-9a-fA-F]{8})", line)
        if begin:
            if current_rip is not None:
                raise SystemExit("nested JIT block in trace")
            current_rip = int(begin.group(1), 16)
            current_size = int(begin.group(2), 16)
            current_words.clear()
        elif word and current_rip is not None:
            current_words.extend(struct.pack("<I", int(word.group(1), 16)))
        elif "FEXJIT01 END" in line and current_rip is not None:
            if len(current_words) != current_size:
                raise SystemExit(
                    f"JIT block at RIP 0x{current_rip:x} has "
                    f"{len(current_words)} bytes, expected {current_size}"
                )
            mapping.append((len(raw), current_rip, current_size))
            raw.extend(current_words)
            current_rip = None
            current_size = None
            current_words.clear()

    if current_rip is not None:
        raise SystemExit(f"unterminated JIT block at RIP 0x{current_rip:x}")
    if not mapping:
        raise SystemExit("JIT trace contained no blocks")
    raw_path.write_bytes(raw)
    map_path.write_text(
        "".join(
            f"raw_offset=0x{offset:x} guest_rip=0x{rip:x} size=0x{size:x}\n"
            for offset, rip, size in mapping
        ),
        encoding="utf-8",
    )
    print(f"FEX_JIT_EXTRACT_OK blocks={len(mapping)} bytes={len(raw)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
