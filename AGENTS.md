# VKMT preservation and build contract

## Never-delete scope

Do not delete, reset, or wholesale rebuild these paths without an explicit
review of the replacement artifact:

- `wine/wine-11.12/` and `wine/build-ec/`
- `third_party/FEX-2607/`, `third_party/dxvk/`, `third_party/vkd3d-proton/`,
  `third_party/MoltenVK/`, `third_party/DXMT-v0.80/`, and
  `third_party/dxmt-src-v0.80/`
- `patches/`, `scripts/`, `test/`, `docs/`, and this file
- `toolchains/llvm-mingw-20260616-ucrt-macos-universal/` — active in-tree
  cross-toolchain, including the rebuilt runtime dependencies.

The project must remain reproducible from in-tree sources, pinned revisions,
and patches.  Host code must remain native ARM64; x86_64 and i386 are guest
architectures only and must not require Rosetta.

## Build policy

Use targeted `make` rules for Wine components (for example,
`make dlls/ntdll/ntdll.so` or `make dlls/wow64/aarch64-windows/wow64.dll`).
Do not run a full Wine rebuild unless the configuration or generated build
files genuinely require it.  Never use destructive Git reset/checkout to
discard custom work.

## Required preservation inventory

Before deleting any historical workspace or cache, verify that current VKMT
contains:

- ARM64 Wine Unix libraries and PE DLLs plus i386/x86_64 PE DLLs.
- MoltenVK, Vulkan loader/ICD configuration, DXVK, vkd3d-proton, DXMT 0.80,
  Winemetal, FreeType dependencies, and FEX WoW64 provider artifacts.
- Every applied source patch and the scripts that rebuild/stage each component.
- Focused probes and their source for native ARM64, x86_64, i386/WoW64, VKMT,
  and DXMT/Winemetal.

## Phase order

1. Preserve current artifacts and reclaim only verified disposable data.
2. Re-prove native ARM64 prefix/wineboot and VKMT/DXMT probes.
3. Re-prove x86_64 guest execution on the native ARM64 host.
4. Plan clean i386/WoW64/FEX integration with the staged i386 graphics DLLs.
5. Validate ARM64, ARM64EC, AArch64, x86_64, and i386/WoW64 end to end.

### 2026-07-27 FEX/WoW64 boundary observation

The saved implementation plan is `docs/I386_WOW64_PLAN.md`. The first clean
FEX boundary observation is retained in
`docs/validation/fex-boundary-20260727T090801/`: native ARM64 `wineboot --init`
passed, then an i386 smoke PE mapped in the high guest arena and loaded the
ARM64 FEX `xtajit.dll`, but exited before `BTCpuSimulate` or guest output.
FEX imports `ntdll.RtlWow64SuspendThread`, which the current Wine PE export
surface resolves only to an unimplemented stub. Treat it as an import-contract
gate to close before diagnosing deeper FEX execution. The associated prefix
was stopped through its exact wineserver and removed; no Wine process remains.

### 2026-07-27 — FEX WoW64 Phase 1 complete

- Rebuilt the ARM64 FEX provider from the in-tree LLVM-MinGW toolchain and post-linked its two x18 TLS references to Wine's x28 TLS base.
- Added the missing ARM64X `RtlWow64SuspendThread` ntdll export used by FEX.
- Corrected early Unix-call ordering and high-arena guest-pointer translation in Wine's ARM64 WoW64 wrapper.
- Gate evidence: `docs/validation/fex-phase1-20260727T093140/RESULTS.md`. A fresh prefix reached `BTCpuSimulate`; its disposable run root was removed.

### 2026-07-27 — Phase 4 i386/WoW64 system contract complete

- `scripts/probe-i386-wow64-phase4.sh` is the canonical non-graphics gate. It
  compiles one i386 executable/helper DLL, stages the source-built i386 Wine
  DLL closure, explicitly runs native ARM64 `wineboot --init`, and runs every
  gate plus the Phase 3 regression in that one fresh prefix.
- Current markers pass for LoadLibrary, syscall return/output pointers, TLS,
  context get/set, software/hardware SEH, ordered APCs, a second thread, a
  headless real Wine user callback, repeated thread lifecycle, and the complete
  system contract.
- The callback gate is a thread-local `WH_MSGFILTER` hook driven through
  `CallMsgFilter`; do not replace it with a window/display-dependent probe.
- Wine commit `d43a990` fixes the `NtContinueEx` scalar/pointer distinction and
  makes generic `wow64win` data pointers use the canonical guest-memory
  manager. Evidence and exact commands are in
  `docs/validation/phase4-wow64-system-contract-20260727/RESULTS.md`.
- The same regression session passed
  `P1_UNIFIED_ARM64_AARCH64_ARM64EC_OK`, `P2_X64_ENTRY_OK`, and
  `P2_X64_DXVK_D3D11_READBACK_OK`. No retained Phase 4 prefix remains.
- This is not an i386 graphics claim. Raw data-pointer conversions in
  GDI/D3DKMT marshalling remain explicit work for the i386 VKMT/DXMT phase.

### 2026-07-27 — x86_64 execution re-proved

- The fresh x64 harness now uses an in-tree Wineboot test mode that defers only unfinished i386 WoW64 installation and device services.
- After bounded bootstrap and exact wineserver restart, `entry_x64.exe` executed through `xtajit64.dll`, printed its guest message, and returned 7 on the native ARM64 host.
- Evidence: `docs/validation/p2-x64-execution-20260727T094000/RESULTS.md`.

### 2026-07-27 — i386 guest-memory manager checkpoint (NOT Phase 2 complete)

- Current code is a scaffold, not the canonical manager required for Phase 2.
  It has explicit guest/host map records and a synthetic high-host allocation /
  map / protect / unmap self-test, but it still installs a 4-GiB biased
  compatibility aperture at initialization.
- Several real VM map paths call `wow64_host_to_guest_ptr()` before registering
  the newly returned host mapping. That cannot support an arbitrary host
  address, so it does not meet the no-low-4-GiB Phase 2 contract.
- The i386 exception, callback, and startup paths inspected use named
  conversion helpers. The `PtrToUlong()` occurrences currently found in
  `syscall.c` are ARMNT branches, not i386 branches. Phase 2 nevertheless
  remains incomplete until every specified i386 lifecycle mapping is
  manager-owned and covered by a real (not manually registered) fixture.
- Do not claim Phase 2 complete based on the previous self-test evidence.

### 2026-07-27 — FEX Phase 3 execution checkpoint (NOT complete)

- FEX's i386 generated memory paths use the Wine-published guest-page table,
  and the first i386 guest path now reaches a generated block.  Guest EIP,
  ESP, and the FEX page-table register are still guest-addressed at that
  boundary.
- The current runtime failure is a host execute fault on FEX's generated
  code-cache page.  Wine then enters `KiUserExceptionDispatcher`, producing
  a secondary recursive exception loop; that dispatcher loop is not the
  primary fault.
- Focused native ARM64 Wine probes prove ordinary and direct-ntdll RW-to-RX
  execution, including at FEX's exact high virtual address
  `0x7fffb37f0000`.  The remaining repair is therefore FEX code-cache /
  control-transfer specific, not a generic Darwin executable-memory or
  Wine `NtProtectVirtualMemory` failure.
- Failed i386 diagnostics are disposable external-SSD run roots only. Stop
  their exact prefix server and move the exact run root to Trash immediately.

## Current verification command

Run `scripts/verify-preservation.sh` before cleanup or release staging.  It is
read-only and fails honestly while any requested runtime stage is absent.

### 2026-07-26 inventory result

The active build has the ARM64, x86_64, and i386 Wine `dxgi`, `d3d12`, and
`d3d12core` PE outputs; ARM64EC `xtajit64.dll`; the FEX provider; FreeType; and
MoltenVK.  DXMT v0.80 is staged at `wine/build-ec/dxmt-v0.80`: its
`winemetal.dll` is COFF-ARM64EC and its `winemetal.so` is ARM64 Mach-O.
ARM64 and i386 DXMT stages are present. The i386 `winemetal.dll` is paired
with the native ARM64 `winemetal.so`; no i386 Mach-O bridge is valid or needed.
Separate DXVK and vkd3d-proton stages are also present. This records file/ABI
staging only; the runtime probes remain separate Phase 1 acceptance gates.

### 2026-07-26 Phase 1 native runtime status

Phase 1.0 passed. The ARM64 host closure is verified (`wine`, `wineserver`,
and `ntdll.so` are ARM64 Mach-O); the fresh probe is COFF-ARM64; and
`scripts/probe-p1-aarch64-prefix.sh` proves fresh-prefix creation, native
AArch64 `wineboot --init`, native AArch64 PE execution, and an explicit
per-prefix `wineserver -k`/`-w` clean exit. The concise current evidence is
`docs/validation/p1-aarch64-prefix.latest`; its disposable run root is removed
after success.

The loader fix is in `dlls/ntdll/loader.c`: ARM64X images report ARM64EC plus
CHPE metadata and must be accepted for native ARM64 as well as AMD64. The
ARM64X TLS post-link tool now locates the preserved in-tree LLVM-Mingw tools
relative to its Wine source path. Build-tree probes must retain
`WINEBUILDDIR` and `WINEBOOTSTRAPMODE=1` while testing an unstaged disposable
prefix; that is not a packaged-runtime dependency and does not involve Rosetta
or i386.

Phase 1.1 native Vulkan passed. An ARM64 host executable built from
`scripts/smoke_vk.c`, with `VK_ICD_FILENAMES=test/vkmt_icd.json`, created a
Vulkan 1.3 instance through the pinned MoltenVK ICD and enumerated the Apple
M4. The checked vkd3d-proton requirements all reported available:
robustness2, transform-feedback queries, buffer-device-address,
mirror-clamp-to-edge, dynamic rendering, synchronization2, and maintenance4.
The probe explicitly enables portability enumeration, which MoltenVK requires.

The `dxmt-v0.80/aarch64-windows` directory name is staging terminology, not a
pure-AArch64 Windows ABI claim: its `winemetal.dll`, `d3d11.dll`, and
`dxgi.dll` are COFF-ARM64EC. Their Windows-side runtime proof therefore belongs
to the ARM64EC/x86_64 phase. The paired `aarch64-unix/winemetal.so` is native
ARM64 Mach-O and is the correct native host bridge. Do not try to treat the
ARM64EC DLLs as pure AArch64 PE binaries.

The DXMT bridge's ARM64 `libunwind.1.dylib` is staged beside `winemetal.so` and
the latter now references `@loader_path/libunwind.1.dylib`; it no longer needs
the Homebrew LLVM prefix at runtime. `scripts/verify-preservation.sh` checks
both the staged file and this relative load command.

Phase 1.2 DXMT's focused ARM64EC/native-ARM64 bridge gate now passes via
`scripts/probe-dxmt-arm64ec.sh`. It creates a fresh prefix, runs the in-tree
ARM64 wineboot, compiles a COFF-ARM64EC probe, loads `winemetal.dll`, calls
`WMTCopyAllDevices`, and verifies through dyld output that the paired
`aarch64-unix/winemetal.so` and `winemac.so` were loaded. The script also
checks the co-staged ARM64 `libunwind.1.dylib` and its `@loader_path` linkage,
then stops exactly that prefix's server and removes only that disposable run
root. The wider DXMT D3D11 device gate remains separate and is not implied by
this focused bridge acceptance.

Native Wine D3D12 also has a current real-device result: a disposable
COFF-ARM64 no-DXGI probe successfully called `D3D12CreateDevice` through the
pinned MoltenVK ICD on Apple M4. MoltenVK created and destroyed the VkDevice
and reported the Metal argument-buffer and MTLEvent paths. This proves the
native ARM64 Wine/Vulkan/MoltenVK boundary; it is not a claim that the
x86_64 DXVK/vkd3d-proton device/readback gate has passed.

### 2026-07-26 x86_64 recovery note — not yet an acceptance result

`dlls/ntdll/loader.c` now detects an AMD64 main image with
`ProcessImageInformation` before loading `xtajit64.dll`. The provider alone is
temporarily accepted as ARM64EC while bootstrapping. Ordinary x64-guest Wine
core DLLs resolve from `aarch64-windows` as ARM64X images, not from the pure
`x86_64-windows` directory: their mapped EC ranges are what make x64 imports
transition safely into native ARM64 code. This repaired the native-ARM64
regression caused by an earlier unconditional selector: a fresh AArch64
prefix, in-tree `wineboot.exe --init`, ARM64 smoke PE, and per-prefix
`wineserver -k`/`-w` again pass.

The fresh AMD64 base acceptance now passes: ARM64EC `xtajit64.dll` loads,
hybrid `kernel32`, `kernelbase`, and `ucrtbase` load, `entry_x64.exe` prints
its guest message and exits 7, and the exact wineserver shuts down cleanly.
`PACKUSWB` (`66 0f 67`) was added to the ARM64EC x64 interpreter and rebuilt
through the targeted `dlls/xtajit64/aarch64-windows/xtajit64.dll` rule.

The x64 DXVK/vkd3d-proton D3D12 probe now reaches DXVK 3.0.2 and advances well
beyond that former instruction fault, but has not yet completed device
creation/readback: without trace it remained CPU-bound for over a minute with
no D3D12 result. This is not a graphics-pass claim. All diagnostic prefixes
were stopped with their exact wineserver and removed. Do not begin i386/WoW64
work until the fresh-prefix x64 graphics acceptance succeeds.

The exact fresh-prefix x86_64 base gate was rerun after the ARM64EC stage
resolver update: `entry_x64.exe` again printed its guest message and returned
its expected status 7, followed by exact `wineserver -k`/`-w` cleanup. The
resolver now maps `IMAGE_FILE_MACHINE_ARM64EC` builtins to the shared
`aarch64-windows` PE stage; this is required for the DXMT ARM64EC PE/ARM64
Unix pair and is rebuilt with the targeted `dlls/ntdll/ntdll.so` rule.

### 2026-07-26 x86_64 native-ARM64 D3D12 device gate

The focused x86_64 no-DXGI D3D12 probe is now a passing fresh-prefix gate.
It loads ARM64EC `xtajit64.dll`, ARM64EC vkd3d-proton `d3d12.dll` and
`d3d12core.dll`, and successfully executes `D3D12CreateDevice` through the
pinned MoltenVK ICD on Apple M4. Its log records native `VkInstance` and
`VkDevice` creation plus Metal argument-buffer and MTLEvent use, then reports
`PROBE OK`; its disposable prefix was stopped with its exact wineserver and
removed. The vkd3d-proton source repair is commit `6b69581e`: NV-only
DirectStorage meta shaders are now compiled only when
`VK_NV_memory_decompression` is actually enabled. This prevents MoltenVK from
rejecting an irrelevant NV shader during device initialization.

This is a device-creation acceptance, not the full x64 graphics acceptance.
The next gate is command queue/resource clear/fence/readback; DXGI/DXVK
routing remains separately unproven. A full DXGI probe was stopped and
removed after it failed to complete, so it is not evidence of success.

### 2026-07-27 x86_64/ARM64EC D3D12 deterministic resource gate

`test/d3d12_probe_nodxgi.c` now performs a deterministic upload → default
buffer → readback copy. It checks resource creation, an explicit COPY_DEST to
COPY_SOURCE transition, command-list closure, direct-queue submission, a
fence, and the exact `0x4b4d5456` result read back on the CPU. The fixture
passes as both an ARM64EC guest and an x86_64 guest running through
`xtajit64.dll`, using ARM64EC vkd3d-proton PEs and the pinned MoltenVK ICD.
Each successful run created a new prefix with in-tree ARM64 wineboot and then
stopped its exact wineserver before its run root was removed.

The required vkd3d-proton source repair is commit `3300fe64`: address-binding
tracker TLS is accessed only when its optional Vulkan reporting extension is
actually active. MoltenVK does not expose that extension. Previously the
unconditional TLS access faulted before `vkCreateBuffer`; after the repair,
the resource, queue, fence, and readback path succeeds. This does not yet
prove DXGI/DXVK routing, D3D11, rendering/shader output, or presentation.

### 2026-07-27 x86_64 DXVK/D3D11 deterministic Metal gate

The historical x86_64 DXVK route reached a fresh-prefix D3D11 readback on
Apple M4. It must not currently be treated as an acceptance: the 2026-07-27
recheck with the active build reaches DXVK 3.0.2/OpenXR initialization and
then exits with `STATUS_ILLEGAL_INSTRUCTION` before device creation. The base
x86_64 gate still passes independently (`entry_x64.exe` prints its message
and exits 7 after fresh in-tree wineboot and exact cleanup). Diagnose this
remaining x64 graphics transition before reasserting the D3D11 readback claim.

DXVK's ARM64EC source/cross-file is preserved in nested commit `f0e22fc`.
That change makes MoltenVK's absent geometry-shader, cull-distance, and
depth-clip-enable feature bits optional for device admission while keeping
those features disabled. It does not claim applications using those features
are supported. Runtime staging must copy the finished DLLs from
`runtime/dxvk-vkmt-1a5919b/build.arm64ec/src/{dxgi,d3d11}/` into its
`arm64ec/` stage: `meson install --no-rebuild` may retain older existing
copies. This is now proof of DXGI/DXVK D3D11 device and resource translation
to Metal, but not presentation/swapchain coverage or the separate DXMT D3D11
rendering gate.

### 2026-07-27 DXMT widened D3D11 gate status

DXMT is integrated into the active Wine build without a full Wine rebuild:
`scripts/integrate-dxmt-arm64ec-builtins.sh` replaces only the generated
`dxgi.dll`/`d3d11.dll` build-path artifacts with symlinks to the paired DXMT
ARM64EC stage and pairs the native ARM64 `winemetal.so` plus
`libunwind.1.dylib`. It first retains SHA-256-verified stock Wine DLL backups;
`--restore` restores those exact files.

The focused bridge and an executable DXGI import gate now pass in one fresh,
cleaned prefix: `scripts/probe-dxmt-arm64ec.sh` runs ARM64 wineboot,
`WMTCopyAllDevices`, then an ARM64EC client import of
`CreateDXGIFactory1` and `IDXGIFactory1::Release`. The latter fixed a real
Wine loader defect: ARM64EC import tables were bound to `.hexpthk` x64 export
thunks, which caused native ARM64 to execute x64 bytes. The ARM64EC NTDLL
loader now redirects imports made by an ARM64EC caller through the imported
module's CHPE redirection metadata to its paired ARM64 implementation. True
x64 callers are deliberately unchanged and still use xtajit64. The focused
Wine source repairs are nested commits `3abfdc0` and `e342ff5`.

`IDXGIFactory1::EnumAdapters1` and DXMT `D3D11CreateDevice` are the next
separate gates. They are not yet acceptance results. The factory vtable is
native ARM64EC, and the remaining fault occurs after the successful factory
call while enumerating Metal devices; do not regress the completed import
binding repair or claim DXMT D3D11 rendering until adapter enumeration,
device creation, and readback each pass.

### 2026-07-27 restored x86_64 DXVK/D3D11 acceptance

The current clean acceptance is `scripts/probe-p2-x64-dxvk.sh`. It creates a
fresh disposable prefix with in-tree ARM64 `wineboot.exe`, proves the x86_64
guest entry fixture through ARM64EC `xtajit64.dll`, then routes compatible
ARM64EC DXVK `dxgi.dll` and `d3d11.dll` through the pinned MoltenVK ICD. The
D3D11 fixture creates the Apple M4 device and verifies deterministic
clear/copy/readback (`P2_X64_DXVK_D3D11_READBACK_OK`). Its trap stops only the
prefix's wineserver and removes only that disposable run root.

The Wine-side fix is deliberately narrow and rebuilt only as
`dlls/win32u/win32u.so`. Direct win32u clients such as DXVK can bypass the
normal user32 callback bootstrap; at first desktop use, win32u now attaches
the window station/desktop and registers the two server prerequisite classes.
Full builtin class registration waits for a valid user32 callback table, and
same-thread re-entry is guarded on macOS. In `WINE_NO_EXPLORER=1` probe mode,
the Wine null driver is selected so headless tests do not instantiate a macOS
desktop driver. The normal interactive driver path is otherwise unchanged.

### 2026-07-27 native ARM64 font and D3D12 loader recovery

`scripts/probe-p1-aarch64-prefix.sh` again passes from a fresh disposable
prefix after targeted `win32u` rebuilds. The native ARM64 D3D12 loader probe
also passes for both Wine's builtin `d3d12.dll` and the pure-AArch64
vkd3d-proton `install-arm64/bin/{d3d12,d3d12core}.dll` pair.

The repaired `win32u` behavior is intentionally small: direct GDI callers
lazily initialize the shared GDI table after the Wine process exists; and the
fontconfig fallback checks `fontconfig_enabled` before calling any dynamically
resolved fontconfig entry points. This matters on macOS when FreeType loads
successfully but `libfontconfig.1.dylib` is outside dyld's default search
path. FreeType 2.14.3 itself initializes and Wine's builtin font fallback is
used safely. The verified focused source commit records these two changes.

Native vkd3d-proton subsequently reaches the pinned MoltenVK ICD on Apple M4,
but `CreateDXGIFactory1` from Wine's builtin pure-AArch64 DXGI still returns
`DXGI_ERROR_UNSUPPORTED`. Do not claim native AArch64 D3D12 device/readback
until the pure-AArch64 DXGI route is completed. The existing ARM64EC DXMT
Winemetal factory/bridge gate still passes; its probe now uses idempotent
symlink replacement in its disposable prefix.

### 2026-07-27 unified ARM64/AArch64/ARM64EC acceptance

The preceding builtin-DXGI limitation is superseded by the pure-AArch64 DXVK
route. `third_party/dxvk/build-vkmt-aarch64.txt` is the committed MinGW ARM64
cross file; it reserves `x18` and `x28` for Wine and includes the pinned Vulkan
and SPIR-V headers. `scripts/build-dxvk-aarch64.sh` rebuilds only DXVK,
applies the in-tree `fix-x18-tls.py` post-link check, and stages
`runtime/dxvk-vkmt-1a5919b/aarch64/{dxgi,d3d11}.dll`. Do not replace this with
the ARM64EC pair: a pure AArch64 guest must load the pure AArch64 PE modules.

`scripts/probe-p1-unified-arm64.sh` is the release-quality Phase 1 gate. It
uses one fresh disposable prefix and one Wine server lifetime, boots with the
in-tree ARM64 wineboot, proves the ARM64 host closure, then sequentially
proves both provider pairs without mixing them in a process:

- pure-AArch64 VKMT smoke, DXVK D3D11 clear/copy/readback, and
  DXVK + vkd3d-proton D3D12 queue/copy/fence/readback through the pinned
  MoltenVK ICD on Apple M4;
- ARM64EC DXMT's `winemetal.dll` to native ARM64 `winemetal.so` bridge and its
  DXGI import/factory-release path.

Its successful marker is `P1_UNIFIED_ARM64_AARCH64_ARM64EC_OK`. It validates
the guest PE machines and ARM64 Mach-O Wine host closure, cleans only its own
`build/probe-runs/p1-unified-arm64.*` root after stopping that prefix's server,
and leaves source, staged dependencies, and unrelated prefixes untouched.

`scripts/probe-p2-x64-dxvk.sh` remains the separate x86_64 regression gate;
its current successful markers are `P2_X64_ENTRY_OK` and
`P2_X64_DXVK_D3D11_READBACK_OK`. Its `xtajit64.dll` link is deliberately
idempotent so a partially initialized disposable prefix cannot turn a valid
runtime regression into setup failure.

## Historical archive salvage

`archive-salvage/Arm64WINE-archive-2026-07-13/` preserves the five modified
Wine source files, a binary Git diff, and root-level custom build plans/scripts
from the historical archive.  `SHA256SUMS` and `PROVENANCE.txt` bind them to
the archived Wine revision.  Treat the archive as a cleanup candidate only
after this checksum manifest verifies and any needed release artifacts have
their own active VKMT inventory entry.

The archive's audited `.issue25` duplicate runtime subtree was removed after
that condition was met.  Do not infer that its sibling worktrees are safe to
remove; audit each one independently.

### 2026-07-27 Phase 3 i386/WoW64 execution contract

`scripts/probe-i386-wow64.sh` now passes from a fresh disposable prefix using
the source-built i386 fixture and 642 source-built PE32 Wine DLLs staged before
the first launch.  The verified marker is
`VKMT i386 WoW64 execution contract passed`; it covers arithmetic, branches,
stack operations, `RtlEnterCriticalSection`, locked atomics, executable-memory
allocation, and self-modifying-code invalidation.

The host remains ARM64-only: `wine`, `wineserver`, the FEX `xtajit.dll`
provider, and ARM64 `wow64.dll` are native AArch64/ARM64 artifacts, while only
the guest fixture and `syswow64` modules are i386 PE files.  No Rosetta or x86
Mach-O component participates.  Wine owns explicit 32-bit guest-address to
ARM64 host-pointer mappings; FEX keeps EIP, ESP, registers, segment bases,
callbacks, and return addresses guest-addressed and resolves instruction/data
access through the published page table.  Wine memory flush, dirty,
allocation/protection, free/unmap, section-unmap, and tracked-write
notifications explicitly evict FEX's guest-keyed JIT cache.

Keep mapping publication separate from notification locking: Wine can call
`BTCpuMapGuestMemory` while an allocation notification already holds FEX's
thread-creation mutex.  Reacquiring that mutex in the map/unmap callbacks
deadlocks prefix bootstrap.  Code eviction belongs in the serialized memory
notification paths; map/unmap callbacks publish or clear page-table entries.
The gate stops only its exact prefix wineserver and trashes only its generated
`build/probe-runs/i386-wow64.*` run root on both success and failure.

### 2026-07-28 Phase 5 i386 VKMT complete

`scripts/probe-p5-i386-vkmt.sh` is the authoritative i386 VKMT gate. It uses
one fresh external-SSD prefix and proves i386 DLL/export loading, DXGI factory
and Apple M4 adapter enumeration, D3D12 device/direct queue/fence/copy/readback,
and D3D11 offscreen clear/copy/readback through native ARM64 Wine Unix
libraries and the pinned ARM64 MoltenVK ICD. The required final markers are:

- `P5_I386_DLL_LOAD_OK`
- `P5_I386_DXGI_FACTORY_ADAPTER_OK`
- `P5_I386_D3D12_DEVICE_QUEUE_FENCE_COPY_READBACK_OK`
- `P5_I386_D3D11_DEVICE_CLEAR_COPY_READBACK_OK`
- `P5_I386_VKMT_OK`

Accepted nested revisions are Wine `97ff7730`, FEX `baaca8565`, DXVK
`ab0f99ac`, and vkd3d-proton `3300fe64`. Rebuild the i386 graphics PEs with
`scripts/build-dxvk-vkmt.sh 32` and
`scripts/build-vkd3d-proton-i386.sh`; both use the preserved in-tree
LLVM-MinGW and in-tree Vulkan/SPIR-V headers. Never mix DXVK's
`dxgi.dll`/`d3d11.dll` with the separate DXMT pair.

The native dependency closure is ARM64-only. Run
`scripts/stage-wine-host-libs.sh wine/build-ec` to stage signed FreeType and
libpng dylibs beside `win32u.so`; FreeType must reference
`@loader_path/libpng16.16.dylib`, and neither staged dylib may retain an
absolute Homebrew runtime path. The Phase 5 runner enforces ARM64 host Mach-O,
ARM64 provider PEs, i386 graphics PEs, the no-Rosetta flag, exact wineserver
shutdown, and disposable-prefix cleanup.

Final evidence is
`docs/validation/phase5-i386-vkmt-20260727/RESULTS.md`. The former 2.6-GiB
retained diagnostic prefix has been disposed; no Phase 5 prefix is retained.

### 2026-07-28 Phase 6 single-prefix architecture baseline

`scripts/probe-p6-single-prefix-architectures.sh` proves ARM64, ARM64EC,
x86_64, and i386 execution sequentially in one fresh prefix and one wineserver
lifetime. It stages `xtajit64.dll`, FEX `xtajit.dll`, `wow64.dll`,
`wow64win.dll`, and the complete source-built i386 Wine DLL closure before
running native ARM64 `wineboot --init`.

The required final marker is `P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK`, preceded
by the four per-architecture markers. The runner validates PE machine types,
ARM64-only host Mach-O artifacts, and the no-Rosetta process flag. It stops
only that prefix's exact wineserver and trashes only its own external-SSD run
root. Evidence is in
`docs/validation/phase6-single-prefix-20260728/RESULTS.md`.

This is a baseline CPU-loader gate, not a graphics claim. Keep the separate
VKMT and DXMT acceptance runners authoritative for their translation routes.
