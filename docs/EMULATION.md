# VKMT emulation milestones — running log

PE-side emulation work (arm64ec / xtajit / wow64) on native arm64 Wine 11.12.
Related: [NATIVE_WINE_D3D12.md](NATIVE_WINE_D3D12.md) (native D3D12 bring-up).

## 2026-07-25 — M0: arm64ec PE architecture enabled, xtajit64.dll links

Goal: `--enable-archs=aarch64,arm64ec,x86_64,i386` builds cleanly and
`xtajit64.dll` (upstream stub) links as ARM64EC. Result: **PASS**, no wine
source breakage beyond one configure.ac fix.

### Toolchain: arm64ec CRT + C++ runtime rebuilt with fixed registers

- `scripts/rebuild-mingw-crt.sh` generalized: now takes a target argument
  (`aarch64` default, `arm64ec` new) plus the existing `cxx` mode, in any
  order (`rebuild-mingw-crt.sh arm64ec [cxx]`). Per-target build dirs
  (`third_party/build-mingw-crt-arm64ec`, `build-winpthread-arm64ec`,
  `build-cxxrt-arm64ec`); backups in
  `<toolchain>/arm64ec-w64-mingw32/lib-backup-stock`.
- mingw-w64 master was refreshed in `third_party/mingw-w64` (the old
  depth-1 checkout predated arm64ec CRT support; arm64ec CRT is the
  libarm64 build selected by `--host=arm64ec-w64-mingw32`, which sets
  `ARM64EC_TRUE` and adds `-target arm64ec-windows-gnu` automatically).
- Built + installed for arm64ec with `-O2 -ffixed-x18 -ffixed-x28`:
  mingw-w64 CRT, winpthreads, then libunwind/libc++abi/libc++ from
  llvm-project @ ca7933e4 (same sparse checkout as aarch64, no extra dirs
  needed).
- Verified: `arm64ec-w64-mingw32-clang` accepts both fixed flags
  (arm64ec is an ARM64-compatible ABI); hello-world C and C++ (with
  exceptions, static libstdc++) link and contain no x18 references after
  fixup.

### x28 / x18 facts learned (arm64ec)

- The VKMT-patched `winnt.h` (already installed in both triples) declares
  `NtCurrentTeb()` as a global register variable on **x28** for both
  `__aarch64__` and `__arm64ec__`. Clang only accepts a global register
  variable on x28 when x28 is reserved, so **both** `-ffixed-x18` and
  `-ffixed-x28` are required to compile any EC code including winnt.h —
  same recipe as aarch64. Without the flags the header errors out.
- Plain arm64ec clang does not allocate x18/x28 as scratch (verified by
  disassembly of register-pressure test), so the stock EC CRT was less
  dangerous than stock aarch64 CRT — but EC CRT startup (`crt2.o`,
  `__tmainCRTStartup`) reads `[x28,#8]` (StackBase via NtCurrentTeb), so a
  consistent rebuilt CRT is still required, and static libs must be
  rebuilt with the fixed flags just like aarch64.
- **LLVM's arm64ec-windows TLS lowering emits the same `[x18,#0x58]`
  pattern as aarch64** (seen in libc++ exception-state TLS).
  `scripts/fix-x18-tls.py` rewrites it to `[x28,#0x58]` unchanged — no
  script changes needed. Confirmed: 2/2 sites patched in a test EC exe.

### wine configure fix

- `wine/wine-11.12/configure.ac`: the VKMT block appended
  `-ffixed-x18 -ffixed-x28` only for `aarch64`; changed to
  `AS_CASE([$wine_arch],[aarch64|arm64ec],...)`. Regenerated `configure`
  with `autoconf` (2.73, matches the shipped one).
- `scripts/build-ec.sh` (new): mirrors `build-wine.sh` into
  `wine/build-ec` with `--enable-archs=aarch64,arm64ec,x86_64,i386`.
  `wine/build-full` untouched.
- configure result: `arm64ec_CC=arm64ec-w64-mingw32-clang` (found via
  PATH), `arm64ec_CFLAGS='-g -O2 -ffixed-x18 -ffixed-x28'`,
  `enable_xtajit64=arm64ec`.

### Build result

`make -j8` completed with **zero source changes beyond configure.ac** —
winebuild EC thunk generation and `libs/winecrt0/arm64ec.c` worked
out of the box.

Layout surprise (not a bug): with arm64ec in `--enable-archs`, wine links
**ARM64X (0xA64E) hybrid dlls** for dual-arch modules, placed in the
`aarch64-windows/` dirs (e.g. `ntdll.dll`, `kernel32.dll` are ARM64X).
Pure-EC modules land there too as single-arch ARM64EC (0xA641):
`xtajit64.dll` is at `dlls/xtajit64/aarch64-windows/xtajit64.dll`
(the `arm64ec-windows/` dirs hold only intermediate `.o` files).
The handoff's expected path `arm64ec-windows/xtajit64.dll` does not exist;
the ARM64EC dll at the aarch64-windows path is the real artifact.

### Verification

- `xtajit64.dll`: `Machine: IMAGE_FILE_MACHINE_ARM64EC (0xA641)` ✓
- `ntdll.dll`, `kernel32.dll` (aarch64-windows): ARM64X ✓; x86_64 and
  i386 ntdll.dll present ✓
- **x18 scan:** every ARM64/ARM64EC/ARM64X dll+exe in build-ec — zero
  `[x18]` memory operands (full-tree llvm-objdump scan). Wine's own dlls
  never needed fix-x18-tls.py (no `__thread` TLS in PE code; TEB access
  goes through the patched header).
- Boot test: fresh `test/prefix-ec`,
  `./wine/build-ec/wine 'C:\windows\system32\cmd.exe' /c echo EC-BOOT-OK`
  → EC-BOOT-OK printed. (First-boot RpcSs error is the known cosmetic
  upstream race.)
