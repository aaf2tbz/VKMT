#!/usr/bin/env python3
"""Patch Steam's pinned chrome_elf UCRT invalid-read fail-fast.

Steam's 2026-07-24 win64 chrome_elf statically links the UCRT.  Under the
ARM64EC/FEX process boundary a crash-reporting configuration FILE may lose its
descriptor between the outer and inner read checks.  The inner check calls the
noreturn invalid-parameter handler and kills the renderer with fast-fail code
5.  The instruction immediately following the call is the UCRT's normal
``return -1`` path, so replacing only that call with NOPs preserves the error
return and lets the caller handle EOF/EBADF.

The patch is deliberately pinned to the complete input hash and the exact
instruction bytes.  It refuses unknown Steam updates instead of guessing.
"""

from __future__ import annotations

import hashlib
import pathlib
import sys


INPUT_SHA256 = "18ec3b5310467b8dd875d43bbfaa482d3e72c7fcab86d91efd57bfe05d87e85f"
FILE_OFFSET = 0x9292D  # .text RVA 0x9352d: call invalid_parameter_noinfo_noreturn
EXPECTED = bytes.fromhex("e8 32 ec 00 00")
REPLACEMENT = b"\x90" * len(EXPECTED)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} INPUT-chrome_elf.dll OUTPUT-chrome_elf.dll", file=sys.stderr)
        return 2

    source = pathlib.Path(sys.argv[1])
    output = pathlib.Path(sys.argv[2])
    data = bytearray(source.read_bytes())
    digest = sha256(data)
    if digest != INPUT_SHA256:
        print(f"refusing chrome_elf input hash {digest}; expected {INPUT_SHA256}", file=sys.stderr)
        return 1
    if data[FILE_OFFSET : FILE_OFFSET + len(EXPECTED)] != EXPECTED:
        actual = data[FILE_OFFSET : FILE_OFFSET + len(EXPECTED)].hex(" ")
        print(f"refusing unexpected bytes at {FILE_OFFSET:#x}: {actual}", file=sys.stderr)
        return 1

    data[FILE_OFFSET : FILE_OFFSET + len(EXPECTED)] = REPLACEMENT
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(data)
    print(f"VKMT_STEAM_CHROME_ELF_INVALID_READ_PATCH_OK sha256={sha256(data)} output={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
