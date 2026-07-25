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

## 2026-07-25 — M1: ARM64EC processes boot on Darwin, hello_ec runs native

Goal: EC/CHPE per-thread init (emulator stack + CHPE_V2_CPU_AREA_INFO) works
despite the no-sub-4GB host constraint, and a mingw arm64ec console exe runs.
Result: **PASS (ideal)** — `hello from arm64ec` printed, exit code 42, fully
native execution (xtajit64 stub never entered).

### Wine source fixes (all `#if defined(__APPLE__) && defined(__aarch64__)` or VKMT-marked)

- `dlls/ntdll/unix/thread.c` (`init_thread_stack`, arm64ec block): the
  emulator stack was allocated with `limit_low = limit_4g` ("anywhere above
  4GB") — harmless upstream, but the same call is the one that must not aim
  below 4GB here; made the limits explicit `0, 0` on Darwin with a VKMT
  comment, plus a one-per-thread `FIXME` log line proving the allocation
  (`VKMT: arm64ec emulator stack at 0x...-0x..., cpu area 0x...`).
- `dlls/ntdll/unix/virtual.c` (`virtual_set_large_address_space`): upstream
  resets `address_space_start` to `0x10000` for 64-bit guests — that would
  re-open the sub-4GB range on this host (EC guests included, since
  `is_wow64()` is false for them). Guarded out on Darwin.
- `include/winnt.h` — **the big one**: the VKMT x28-TEB patch only covered
  the `__GNUC__` branch of `NtCurrentTeb()` for aarch64. Wine builds PE with
  `-target arm64ec-windows` (MSVC mode, no `__GNUC__`), so the `_MSC_VER`
  branch was taken, and it returned `__getReg(18)` for `__arm64ec__`
  ("arm64ec keeps x18 for now"). Both branches now use x28 for
  aarch64 **and** arm64ec. Without this, EC ntdll faulted immediately:
  `ldrh w8, [x18, #0x17ee]` (TEB.SkipLoaderInit) with x18 kernel-zeroed →
  read at address `0x17ee` → exception-dispatch recursion → native-stack
  exhaustion (`virtual_setup_exception stack overflow`).
- `dlls/ntdll/signal_arm64ec.c`: four inline-asm TEB reads switched
  `x18` → `x28`: `KiUserCallbackDispatcher` (peb), `arm64x_check_call`
  (peb→EcCodeBitMap — this is `__os_arm64x_check_call`, hit on *every*
  indirect call in EC code), `raise_status` (peb->BeingDebugged),
  `DbgUiRemoteBreakin` (peb).

### Audit of other low-VA / EC paths (checked, no change needed)

- `virtual.c` `alloc_arm64ec_map` (EcCodeBitMap): `map_view(..., MEM_TOP_DOWN, 0, 0)`
  — top-down anywhere, host-safe. Note it reserves one bit per page over the
  whole 128TB guest space = a **4GB reservation** (reserve-only, committed
  per EC range via `commit_arm64ec_map`); works fine on Darwin.
- `set_arm64ec_range`/`clear_arm64ec_range`: pure bitmap math on guest page
  numbers, no host assumptions. `MEM_EXTENDED_PARAMETER_EC_CODE` path only
  gates on `arm64ec_view` existing.
- `virtual_alloc_thread_data` (`map_view limit_low=limit_4g`): "above 4GB",
  correct on this host. `ldt_update_entry` and the `user_space_wow_limit`
  paths are 32-bit-wow64-only (arm64ec is_win64 && !is_wow64; wow64 stays
  rejected in `env.c`). `map_image` chooses the `base >= limit_4g` branch
  for 64-bit images — fine.
- `loader.c` (PE, `load_arm64ec_module`/`arm64ec_thread_init`) and
  `unix/loader.c` (`redirect_ntdll_functions`, unix-call dispatcher swap):
  no VA assumptions.
- `unix/signal_arm64.c` EC hook (`is_ec_code` check before
  KiUserEmulationDispatcher): address-space-neutral.

### Diagnostics left in / removed

Kept: the `init_thread_stack` FIXME (one line per EC thread, proves CHPE
init). Removed after debugging: temporary `init_syscall_frame` and
`segv_handler` FIXME traces.

### Test: test/x64emu/hello_ec.c

`arm64ec-w64-mingw32-clang -O1 hello_ec.c -o hello_ec.exe` (pure ARM64EC,
`file format coff-arm64ec`; puts + `return 42`). Run in fresh
`test/prefix-ec2`:

```
0024:fixme:thread:init_thread_stack VKMT: arm64ec emulator stack at 0x107cf0000-0x107df0000, cpu area 0x107cf0000
hello from arm64ec
EXIT=42
```

**Observed EC entry behavior:** the exe entry (`0x140001424`) is EC code and
runs *natively* — ARM64EC is an ABI, not a different ISA, so the host CPU
executes it directly; the emulator is only needed for actual x86_64 code,
which this binary contains none of. CRT startup, `puts` into wine's hybrid
ARM64X ucrtbase, and exit all ran native. xtajit64.dll loads
(`load_arm64ec_module` + `arm64ec_process_init` succeeded silently) but its
stub was never entered.

**Regression check:** fresh `test/prefix-ec`,
`wine cmd /c echo OK` → `OK`, exit 0.

### Surprises / notes for M2 (the actual emulator)

- **The M0 "zero x18 operands" scan was a false negative.** Its pattern
  (`[x18]`) missed offset forms like `[x18, #0x17ee]`. EC ntdll had two
  such TEB reads until the winnt.h `_MSC_VER` branch was fixed. A
  full-tree rescan with `\[x18, #0x` found one more offender:
- **`dlls/icu/aarch64-windows/icu.dll` (ARM64X) had 22 `[x18,#0x58]` TLS
  sites** in its EC half (ICU's own `__thread` TLS — the pattern
  `fix-x18-tls.py` exists for). Patched post-link with the script
  (22/22 rewritten to x28). **This regresses on any icu.dll relink** — M2
  should wire `scripts/fix-x18-tls.py` into the PE link step (or strip
  `__thread` from the ICU build) before anything loads icu (usp10 /
  directwrite path).
- EC code in wine's own dlls reads PEB.EcCodeBitMap via
  `arm64x_check_call` on every indirect call; with the x28 fix this works
  and is on the hot path for any future emulation dispatch.
- `llvm-objdump`/`llvm-nm` on ARM64X binaries print the EC image at
  ImageBase `0x180000000`; native-half symbols appear at plain RVAs —
  handy for offline symbolication of EC crashes (fault RVA = pc − module
  base; both halves land in one map).
