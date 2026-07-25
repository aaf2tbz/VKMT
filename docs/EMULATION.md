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


---

## M2 (2026-07-25): xtajit64 emulator skeleton — derived ABI conventions

The stub xtajit64 ("x64 emulation not implemented" → NtTerminateProcess) is
replaced by our own interface-complete skeleton in
`dlls/xtajit64/vkmt/` (thin export layer stays in `dlls/xtajit64/cpu.c`).
**No x86 execution yet** beyond a minimal decode skeleton; M3 fills in the
interpreter. This section is the ABI reference M3 is built against.

### Where the emulator gets invoked (verified in source + disassembly)

There are exactly four entry points from native code into the emulator:

1. **`BeginSimulation()`** — called as an ordinary EC function
   (`pBeginSimulation()` in `dispatch_emulation`,
   `dlls/ntdll/signal_arm64ec.c:1264`). Reached whenever the unix side
   resumes a thread whose target PC is not EC code
   (`signal_set_full_context`, `dlls/ntdll/unix/signal_arm64.c:379-387`:
   the resume frame PC is redirected to `KiUserEmulationDispatcher` with a
   full native context placed on the stack). Before the call, ntdll has:
   - converted the saved native context into the cpu area:
     `context_arm_to_x64( cpu_area->ContextAmd64, arm_ctx )`
   - set `cpu_area->InSimulation = 1`
   So at `BeginSimulation` entry **all guest state lives in
   `cpu_area->ContextAmd64`** (an `ARM64EC_NT_CONTEXT`); the native
   registers belong to the dispatcher and may be clobbered. The function
   must never return (its caller does `brk #1` afterwards) — it leaves via
   `NtContinue` or process termination.

2. **`ExitToX64()`** (`__os_arm64x_dispatch_call_no_redirect`) — `blr`'d
   from inside llvm-mingw `$iexit_thunk$` thunks when EC code calls an x64
   function. Verified from ntdll.dll disassembly:
   ```
   $iexit_thunk$cdecl$i8$i8:
     sub sp, sp, #0x30
     stp x29, x30, [sp, #0x20]
     add x29, sp, #0x20
     ldr x16, [__os_arm64x_dispatch_call_no_redirect]
     blr x16                    ; -> ExitToX64
     mov x0, x8                 ; guest RAX comes back in x8
     ldp x29, x30, [sp, #0x20]
     add sp, sp, #0x30
     ret
   ```
   At `ExitToX64` entry: **x9 = x64 target address** (placed by
   `arm64x_check_call`'s `.Lexit`: `mov x9, x11`), x0–x7 = EC args,
   sp = guest stack (the thunk's 0x30 frame: saved fp/lr at `[sp,#0x20]`,
   16 bytes free at `[sp,#0x00]` — believed to be the slot where the
   emulator writes the `RetToEntryThunk` marker as the guest return
   address; **unverified, confirm in M3**), lr = return address into the
   thunk epilogue. Return protocol: emulator resumes native execution with
   guest RAX in x8 and PC = the lr it saw at entry (the thunk then does
   `mov x0, x8; ret` back into EC code).

3. **`DispatchJump()`** (`__os_arm64x_dispatch_fptr`) — same convention as
   `ExitToX64` (x9 = x64 target) but tail-called for indirect *jumps* into
   x64 code; no new frame is created, so a guest `ret` lands directly on
   the EC caller's return address (which is EC code → plain exit-to-native).

4. **`RetToEntryThunk()`** (`__os_arm64x_dispatch_ret`) — `br`'d to from
   the epilogue of `$ientry_thunk$` thunks when a native (EC) function that
   was called *from the emulator* returns:
   ```
   $ientry_thunk$cdecl$...:
     sub sp, sp, #0xd0 ; save q6-q15, fp/lr
     ldp x8, x5, [x4, #0x20] ; reload args from a descriptor buffer in x4:
     ldr q0,     [x4, #0x40] ;   +0x20 x4, +0x28 x5, +0x30 x6/x7,
     ldp x6, x7, [x4, #0x30] ;   +0x40 q0, +0x50 extra (stack-arg/retaddr?)
     ldr x10,    [x4, #0x50] ;   (exact x4 descriptor semantics: M3)
     blr x9                  ; x9 = native EC function
     ldr x1, [__os_arm64x_dispatch_ret]
     mov x8, x0              ; result -> guest RAX in x8
     ...restore..., add sp, sp, #0xd0
     br x1                   ; -> RetToEntryThunk
   ```
   At `RetToEntryThunk` entry: x8 = guest RAX, sp = guest RSP as at
   entry-thunk entry, and `[sp]` = the x64 return address the guest pushed
   with its `call`. So the re-entry convention is: capture regs,
   guest RIP = pop([sp]), re-enter simulation.

### Guest state representation

`CHPE_V2_CPU_AREA_INFO` (include/winternl.h:352), per thread, allocated by
M1 in `dlls/ntdll/unix/thread.c:1217-1241` (above 4GB on Darwin):
- `InSimulation` (0x00), `InSyscallCallback` (0x01) — cooperative flags
  read by `signal_arm64.c` suspend machinery; emulator must set
  `InSimulation=1` while interpreting and clear it before any `NtContinue`
  back to native code.
- `EmulatorStackBase` (0x08) / `EmulatorStackLimit` (0x10) — private
  emulator stack (256KB); entry points switch SP here before running C.
- `ContextAmd64` (0x18) → `ARM64EC_NT_CONTEXT` (0x4d0 bytes, lives inline
  in the reserved area at `EmulatorDataInline`). THE guest register file.
- `EmulatorData[4]` (0x30) — emulator-private slots; VKMT uses
  `[0]` = per-thread `vkmt_x64_context*`, `[1]` = raw NZCV scratch during
  ExitToX64/DispatchJump entry.

x64 ↔ ARM64EC register aliasing inside `ARM64EC_NT_CONTEXT`
(include/winnt.h:1908-2012; this is what the interpreter reads/writes):

| x64 | ARM64EC field | offset | x64 | ARM64EC field | offset |
|-----|---------------|--------|-----|---------------|--------|
| rax | X8   | 0x078 | r8  | X2  | 0x0b8 |
| rcx | X0   | 0x080 | r9  | X3  | 0x0c0 |
| rdx | X1   | 0x088 | r10 | X4  | 0x0c8 |
| rbx | X27  | 0x090 | r11 | X5  | 0x0d0 |
| rsp | Sp   | 0x098 | r12 | X19 | 0x0d8 |
| rbp | Fp   | 0x0a0 | r13 | X20 | 0x0e0 |
| rsi | X25  | 0x0a8 | r14 | X21 | 0x0e8 |
| rdi | X26  | 0x0b0 | r15 | X22 | 0x0f0 |
| rip | Pc   | 0x0f8 | lr (native ret) | Lr | 0x120 |
| rflags | AMD64_EFlags | 0x044 | xmm0-15 | V[0..15] | 0x1a0 |

EFlags ↔ CPSR (from ntdll `cpsr_to_eflags`): N→SF(0x80), Z→ZF(0x40),
C→CF(0x01), V→OF(0x800), plus always-set 0x002 and IF 0x200. Raw NZCV has
no place in the EC context, so the asm entry stashes it in
`EmulatorData[1]` and C code converts.

### Leaving simulation

Uniform exit for all paths: write final guest state into `ContextAmd64`,
set `Pc` = native (EC) target, `InSimulation = 0`, then
`NtContinue( (CONTEXT *)ContextAmd64, FALSE )` (EC ntdll converts
x64→native and resumes; if the target were still x64 the unix side would
bounce us straight back into `KiUserEmulationDispatcher` →
`BeginSimulation`, which is the correct re-entry loop).

The interpreter decides to exit when the next guest RIP is:
- EC code (`RtlIsEcCode(rip)`) → exit to native at that PC
  (covers guest `call`/`jmp`/`ret` into EC thunks and EC return addresses);
- equal to `&RetToEntryThunk` (the marker) → guest `ret` from an
  ExitToX64-entered call: exit to native at the saved native lr
  (`ContextAmd64->Lr`), guest RAX already in X8;
- 0 → giveup diagnostic (guest returned from a top-level entry).

### Skeleton behavior for M2 (no real x86 execution)

`vkmt/interp_stub.c` decodes a deliberately tiny subset — enough to run a
hand-written `mov eax,imm; ret` snippet and typical prologue prefixes:
`nop`, `mov r32,imm32` / `mov r64,imm64` (B8+rd), register-direct
`mov r64,r64` (89/8B mod=3), `push/pop r64`, `add/sub rsp,imm8`,
`call/jmp rel`, `call/jmp r/m64` (FF /2,/4 mod=3), `ret`/`ret imm16`,
`int3`. Anything else → loud `ERR` diagnostic ("VKMT M2 skeleton:
unsupported guest opcode …") and clean `NtTerminateProcess(
STATUS_ILLEGAL_INSTRUCTION )` — replacing the stub's blanket terminate.
All Notify*/BTCpu64* hooks log on the `vkmtx64` debug channel.

### Implementation notes (what actually landed)

- `dlls/xtajit64/cpu.c` is now a thin export layer; implementation in
  `dlls/xtajit64/vkmt/`: `vkmt.h`, `context.c` (process/thread lifecycle,
  per-thread `vkmt_x64_context` in `EmulatorData[0]`, feature bits,
  `UpdateProcessorInformation` → AMD64/level 21/revision 1), `dispatch.c`
  (naked `BeginSimulation`/`ExitToX64`/`DispatchJump`/`RetToEntryThunk`,
  `vkmt_simulate` loop, `ResetToConsistentState`), `interp_stub.c`.
  Debug channel `vkmtx64`.
- **Observed entry path:** the x64 exe entry point is reached via
  **ExitToX64** (loader → exit thunk → `blr ExitToX64`, x9 = exe entry),
  not via `BeginSimulation`. `BeginSimulation` fires on the
  `NtContinue`-to-x64 path (thread starts, syscall re-entry,
  `STATUS_EMULATION_SYSCALL`); both funnel into the same `vkmt_simulate`.
- **Return-marker protocol (now implemented + verified):** on
  ExitToX64/DispatchJump entry the emulator writes `&RetToEntryThunk` to
  the guest stack top and stashes the thunk-entry SP/FP in
  `EmulatorData[2..3]`. A guest `ret` pops the marker → EXIT_RETURN →
  `NtContinue` with `Pc = entry-time lr` (thunk epilogue), **SP/FP
  restored to entry values** (the guest frame is discarded; the thunk's
  own epilogue must see its exact entry SP — first version of this
  crashed with c0000005 at caller+4 until the restore was added).
  Guest RAX lands in x8, thunk does `mov x0, x8` → the EC caller sees a
  normal return value.
- **x64-half discovery:** a guest call to a hybrid-dll API (e.g.
  `ExitProcess` via IAT) lands in the dll's **x64 half** (real x64 code,
  not EC per `RtlIsEcCode`), which then transitions to the EC half
  internally. So M3 cannot avoid interpreting those prologues — API calls
  are not a cheap "jump straight to native" escape.
- Interpreter subset: as listed above plus rip-relative `call/jmp
  [rip+disp32]` (FF /2,/4 mod=0 rm=101).

### TLS fixup wiring (M1 follow-up, done)

`tools/makedep.c` now emits a post-link command for every module whose
link arch is arm64ec (covers arm64x too): runs
`tools/vkmt-fix-x18-tls.py $@` (a copy of `scripts/fix-x18-tls.py`,
shipped in the wine patch; guarded by `if [ -f ]`, silent skip when
absent). Make-level hook in `output_module()` — the single rule every PE
dll/exe link goes through — no winegcc changes needed. Gotcha found:
`$(top_srcdir)` is not defined in the generated top-level Makefile; the
hook uses `$(srcdir)`. Verified: `touch libs/icucommon/chariter.cpp &&
make dlls/icu/aarch64-windows/icu.dll` relinks and prints
`dlls/icu/aarch64-windows/icu.dll: patched 22/22 [x18]->[x28] sites`;
post-link scan `llvm-objdump -d | grep -c '\[x18, #0x'` → **0**.
Full rescan of every `aarch64-windows`/`arm64ec-windows` PE in build-ec
with the corrected `\[x18, #0x` pattern → **0 offenders**.

### Test results (verbatim highlights)

- Regression, fresh prefix: `wine cmd /c echo OK` → `OK`.
- Regression, `test/prefix-ec2`, `C:\hello_ec.exe` → `hello from arm64ec`,
  `exit=42`.
- `test/x64emu/entry_x64.exe` (normal-CRT hello+`return 7`), fresh
  `test/prefix-x64`, `WINEDEBUG=+vkmtx64`:
  ```
  0024:trace:vkmtx64:vkmt_process_init VKMT x86-64 emulator skeleton (M2): process init
  0024:trace:vkmtx64:vkmt_thread_init thread 0024 init, cpu area 0000000105CB0000
  0024:trace:vkmtx64:vkmt_simulate_from_ec simulation from EC: thread 0024 guest rip 0000000140001480 rsp 0000000105AEF500 native lr 00006FFFFFA56364
  0024:trace:vkmtx64:vkmt_simulate enter simulation: thread 0024 guest rip 0000000140001480 rsp 0000000105AEF500
  0024:err:vkmtx64:vkmt_simulate VKMT M2 skeleton: cannot continue guest execution at rip 0000000140001487 (opcode 8b) — terminating process cleanly; full x86-64 interpretation lands in M3
  ```
  → process exit code 0x1d (STATUS_ILLEGAL_INSTRUCTION), no crash/hang,
  `wineserver -w` returns 0. (All Notify* traffic visible on the channel.)
- `test/x64emu/ret_snippet_x64.exe` (hand-written `mov eax,7; ret`,
  `-nostdlib -e entry`):
  ```
  0024:trace:vkmtx64:vkmt_simulate_from_ec simulation from EC: thread 0024 guest rip 0000000140001000 rsp 000000010755FFB0 native lr 00006FFFFF68F9FC
  0024:trace:vkmtx64:vkmt_simulate enter simulation: thread 0024 guest rip 0000000140001000 rsp 000000010755FFB0
  0024:trace:vkmtx64:vkmt_simulate guest returned to EC caller at 00006FFFFF68F9FC (rax 0000000000000007)
  0024:trace:vkmtx64:vkmt_process_term process term handle 0000000000000000 is_post 0 status 0
  ```
  → **process exit code 7**: full enter→interpret→return→native round
  trip with the exit-code value propagated through x8 → x0.
- `test/x64emu/exit_native_x64.exe` (`mov ecx,7; jmp [rip+__imp_ExitProcess]`):
  interpreter followed the IAT into kernel32's **x64 half** and gave up
  cleanly at its prologue (`48 89` memory-form mov) — expected for M2,
  see the x64-half note above.

### Open questions / M3 scope (honest assessment)

- **M3 is a real interpreter, no shortcuts.** The two biggest hopes for
  avoiding full decode turned out false: (1) the CRT entry runs dozens of
  x64 instructions before any native call; (2) hybrid-dll API calls route
  through the dll's x64 half first, so even "just call ExitProcess"
  needs memory-operand decode. Expect entry_x64's `hello` to need:
  full ModRM/SIB memory addressing, flag-tracking ALU, jcc, movs/stos,
  SSE movs, and the `syscall`/fast-forward sequences.
- **Confirm the ExitToX64 marker slot** ([thunk sp+0]) against a call
  with >4 args and against floating-point args (entry thunks save
  q6–q15; xmm0–3 argument passing is untested).
- **`$ientry_thunk` x4-descriptor layout** (+0x20/+0x30/+0x40/+0x50) needs
  confirmation the first time the emulator exits to native through an
  entry thunk rather than a plain EC return address.
- KiUserExceptionDispatcher's `dispatch_ret`-based unwind and
  `ResetToConsistentState` are stubs; exception flow across the
  x64/EC boundary is unexplored.
- Guest FPU/SSE state: v0–v15 captured on thunk entry, mxcsr defaults to
  0x1f80; no per-instruction FP decode yet.
- Debuggers: winedbg auto-attach after a guest giveup couldn't get the
  first exception (debugger process itself trips emulation paths) —
  worth fixing early in M3, debugging the interpreter needs it.

---

## M3 (2026-07-25): real x86-64 interpreter — entry_x64.exe passes

`dlls/xtajit64/vkmt/interp.c` replaces the M2 stub with a full
decode→execute interpreter (decoder fills a `vkmt_insn` metadata struct —
prefixes/opcode/ModRM/SIB/disp/imm/resolved EA — reusable by a future JIT;
execute stage is separate). RFLAGS: **always-compute** (every ALU op
materialises CF/OF/AF/SF/ZF/PF immediately; no lazy state).

Coverage: full ModRM/SIB/REX + rip-relative addressing, 8/16/32/64
operands (incl. no-REX high-byte regs), ALU groups + group1 imm, flag-
accurate add/sub/and/or/xor/test/cmp, shifts/rotates (rcl/rcr via carry
loop), mul/imul/div/idiv (incl. 128-bit), inc/dec/neg/not, jcc8/jcc32/
loop/jrcxz/cmov/setcc, movzx/movsx/movsxd, lea, xchg, bswap, bsf/bsr,
bt/bts/btr/btc (+bit-string mem addressing), shld/shrd, popcnt,
cmpxchg/cmpxchg8b/16b and xadd with host `__atomic` RMW for LOCK forms,
string ops (movs/stos/scas/cmps/lods + rep; rep movsb/stosb have
memcpy/memset fast paths), push/pop/pushf/popf/enter/leave, cbw/cwde/cdqe
+cwd/cdq/cqo, sahf/lahf, xlat, clc/stc/cmc/cld/std, CPUID (GenuineIntel
baseline matching UpdateProcessorInformation: SSE..SSE4.2, POPCNT, NX,
RDTSCP, long mode), RDTSC/RDTSCP (NtQueryPerformanceCounter-based),
mfence/lfence/sfence as nops, ldmxcsr/stmxcsr, x87: fldcw/fnstcw/fninit/
fnstsw only — anything else x87 is a loud giveup.
SSE/SSE2: movups/movaps/movdqa/movdqu/movss/movsd/movd/movq/movlps/
movhps/movhlps/movlhps/movddup, add/sub/mul/div/min/max/sqrt ps/pd/ss/sd
(local Newton sqrt — no libm in PE link), cvt family (cvtsi2ss/sd,
cvt(t)s(s|d)2si, cvtss2sd/sd2ss/ps2pd/pd2ps, cvtdq2ps/ps2dq/tps2dq),
ucomiss/ucomisd, cmpps/pd/ss/sd (8 predicates), and/andn/or/xor ps/pd,
pxor/pand/pandn/por, pcmpeq/pcmpgt b/w/d, padd/psub b/w/d/q, pshufd/
pshuflw/pshufhw, shufps/shufpd, unpcklps/pd, punpcklbw/lwd/lqdq/hqdq,
psll/psrl/psra w/d/q + pslldq/psrldq, movmskps/pd, movnti.

### Boundary discoveries (M2 open questions resolved)

- **IAT slots in a pure-x64 exe point at the *EC halves* of ARM64X dlls**
  (verified: `__imp___acrt_iob_func` = ucrtbase EC `__acrt_iob_func`, arm64
  code at dll RVA 0xBD5FC). So guest calls into dll code exit to native
  immediately via `RtlIsEcCode` — hybrid transitions need no x64-half
  interpretation for wine's own dlls. (llvm-objdump prints the *EC* half
  at plain RVAs with base 0x180000000.)
- **x64→EC call protocol:** when the interpreter exits to native at an EC
  target it must plant `Lr = &RetToEntryThunk` in the context — the EC
  callee returns with a plain `ret` (x30); without the marker it rets to
  0 (M2 never exercised EXIT_NATIVE; first attempt crashed execute-at-0).
  RetToEntryThunk therefore now also runs when a *native* EC callee
  returns (not only via `$ientry_thunk$`): it does `mov x8, x0` first
  (EC result → guest RAX; idempotent with the real ientry thunks which
  already do it), then pops the guest return address. >4-arg/xmm-arg
  EC calls need nothing special: stack args are read off the guest stack
  and xmm args flow through ec->V (captured/restored on every switch) —
  confirmed working by puts/__acrt_iob_func/setvbuf/fflush.
- **ec->Lr cannot back the EXIT_RETURN path:** the RetToEntryThunk capture
  overwrites `ContextAmd64->Lr` with the planted marker on every EC-callee
  return, so the ExitToX64-entry lr is now saved separately
  (`vkmt_x64_context.native_ret`). Using ec->Lr caused an infinite
  marker→marker ping-pong (observed).

### Interpreter bugs found via the exec-ring dump (new debug tool)

The giveup dump now prints guest regs, 32 bytes at rip, last 16 branch
targets, and the last up-to-8192 executed instructions
(rip/eflags/rax/rcx ring in the per-thread context; tight loops elided).
`vkmt_reset_to_consistent_state` dumps the *live* guest context when a
host fault happens mid-simulation — this is how these were found:

1. Missing immz table entries for ALU accumulator forms
   (05/0d/15/1d/25/2d/35/3d) — `cmp rax,imm32` decoded 4 bytes short.
2. `cmp` (ALU index 7) fell into the XOR branch of the shared ALU helper —
   flags always wrong for `cmp` (CF never set); `___chkstk_ms` probed the
   stack into the guard page (c00000fd).

Null-page guest operands (< 0x10000) are caught at decode time and turned
into a clean giveup with the full dump (exempt: lea, hint nops, prefetch).

### Result

`entry_x64.exe` (full mingw CRT startup, puts("VKMT entry_x64: hello
from x86-64 guest"), `return 7`): prints correctly, **process exit code
7**, clean `wineserver -w`. This is the complete path: loader → exit
thunk → ExitToX64 → CRT startup (~100k+ interpreted insns across dozens
of simulation entries) → puts → EC ucrtbase → return marker → exit code.
