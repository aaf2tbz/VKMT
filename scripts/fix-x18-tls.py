#!/usr/bin/env python3
# VKMT: rewrite [x18] base-register memory operands to [x28] in aarch64 PE
# binaries. LLVM's Windows-aarch64 TLS lowering hardcodes x18 (TEB.TlsSlots);
# VKMT keeps the TEB in x28. Safe because all our PE code is built with
# -ffixed-x18, so no legitimate x18 allocation remains in .text.
import re, struct, subprocess, sys

BIN = "/Volumes/AverySSD/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"

def patch(path):
    out = subprocess.run([f"{BIN}/llvm-objdump", "-d", "--no-show-raw-insn", path],
                         capture_output=True, text=True).stdout
    sites = [int(m.group(1), 16) for line in out.splitlines()
             if (m := re.match(r"\s*([0-9a-f]+):.*\[x18[,\]]", line))]
    if not sites:
        print(f"{path}: no [x18] operands found")
        return

    hdr = subprocess.run([f"{BIN}/llvm-readobj", "--sections", "--file-headers", path],
                         capture_output=True, text=True).stdout
    image_base = int(re.search(r"ImageBase: (0x[0-9a-fA-F]+)", hdr).group(1), 16)
    secs = []  # (vma, fileoff, size)
    for m in re.finditer(r"VirtualAddress: (0x[0-9a-f]+)\n(?:.*\n)*?\s+RawDataSize: (\d+)\n\s+PointerToRawData: (0x[0-9a-f]+)", hdr):
        rva, size, off = int(m.group(1), 16), int(m.group(2)), int(m.group(3), 16)
        secs.append((image_base + rva, off, size))

    data = bytearray(open(path, "rb").read())
    patched = 0
    for va in sites:
        for vma, off, size in secs:
            if vma <= va < vma + size:
                fo = off + (va - vma)
                (w,) = struct.unpack_from("<I", data, fo)
                rn = (w >> 5) & 0x1F
                if rn != 18:
                    print(f"{path}: WARNING word at {va:#x} has Rn={rn}, expected 18 ({w:#010x})")
                    break
                struct.pack_into("<I", data, fo, (w & ~(0x1F << 5)) | (28 << 5))
                patched += 1
                break
        else:
            print(f"{path}: WARNING no section for vaddr {va:#x}")
    open(path, "wb").write(data)
    print(f"{path}: patched {patched}/{len(sites)} [x18]->[x28] sites")

for p in sys.argv[1:]:
    patch(p)
