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

## Active acceptance goal

The all-architecture correctness baseline is accepted and performance work is
active under `docs/PERFORMANCE_OPTIMIZATION_PLAN.md`. Every optimization must
preserve conventional status `0` for ARM64/AArch64, ARM64EC, x86_64, and
i386/WoW64 in one fresh prefix. All three FEX TSO settings remain zero and
Rosetta must not participate. Rebuild only the affected Wine/FEX components;
do not reopen or replace the accepted providers without a focused regression.

### 2026-08-01 — P3 Wine loader/session optimization accepted

- FEX commit `90afdb42bbec564c8a8c468588b4218dba27599c` persists
  translated blocks for the main image plus the graphics-qualified fixed
  runtime set `ntdll.dll`, `kernelbase.dll`, and `kernel32.dll`. UCRT/MSVCRT
  are deliberately excluded because their process-mutated dispatch state made
  cached i386 D3D12 fail; the safe set passes x64 DXVK/D3D11 and i386
  DXGI/D3D12/D3D11 readback.
- Accepted providers are now `xtajit64.dll`
  `0c5e7b85049d2d078a55e014cdecabe767c765d382ee2f0e6c7a92d2f3149a4f`
  and `xtajit.dll`
  `ed9eac240a87cebd2bff5b4384105410a00ae0215b08c1a6f43e8b7d77ae7d98`.
  The prior P2 pair remains in `runtime-providers` as the named `pre-p3`
  rollbacks.
- Wine commit `04a6027` retains the native ARM64 wrapper instead of re-execing
  an equivalent loader, adds a bounded generation-keyed builtin path cache,
  searches `.exe` modules in `programs` first, and stops treating the external
  FEX ABI identity as a missing Wine builtin. Three paired production traces
  reduced initial failed dyld probes from 10 to 5 and warm Wine builtin probe
  failures from 3 to 0.
- `scripts/vkmt-warm-session.sh` owns the prefix-scoped, 1-600 second bounded
  wineserver policy. Its receipt binds Wine, wineserver, NTDLL, both providers,
  GStreamer, and MSync mode; provider replacement or a mode/generation change
  performs exact prefix shutdown before reuse.
- `scripts/vkmt-runtime-env.sh` enables the accepted FEX cache, forces all
  three TSO settings to zero, and uses only the bundled host dependency paths.
- Two independent 20-sample sessions passed the warm <75 ms p95 gate with all
  164 correlated launches per architecture at `rc=0`: x64 p95 was
  21.661-21.986 ms and i386 p95 was 68.672-69.112 ms. Default P2 cache
  acceptance reports 100% eligible repeat-JIT reduction; the fresh P6 prefix
  passes ARM64, ARM64EC, x86_64, and i386.
- Evidence is in `docs/validation/perf-p3-loader-20260801/` and
  `docs/validation/perf-p3-latency-20260801/`. P4 cross-architecture transition
  reduction is next.

### 2026-08-01 — P4 cross-architecture transition reduction accepted

- FEX commit `f30858e15` adds opt-in ARM64EC and i386/WoW64 transition
  classification plus syscall and Unix-call histograms. Ordinary runs do not
  update the counters; correlated runs set `VKMT_PERF_RUN_ID`.
- The measured hot boundary was WineVulkan procedure discovery. Wine commit
  `f989b1f` snapshots host instance/device function availability once and lets
  generated PE thunks answer subsequent procedure queries locally, with an
  allocation-failure fallback to the prior individual host-query path.
- i386 Unix-call counts fell from 72 to 37 for DXGI (48.6%), 1,271 to 933 for
  D3D12 (26.6%), and 767 to 462 for D3D11 (39.8%). Both deterministic D3D12
  runs produced the same count and retained their readback result.
- The original P5 substrate failure was caused by that runner omitting the
  explicit no-TSO environment. `probe-p5-i386-vkmt.sh` and the full WoW64
  system-contract runner now pin all three FEX TSO settings to zero.
- Post-change status-0 gates cover canonical i386 DXGI/D3D12/D3D11, x64 DXVK
  D3D11, the complete WoW64 system contract, and ARM64, ARM64EC, x86_64, and
  i386 together in one fresh prefix. Evidence is in
  `docs/validation/perf-p4-transitions-20260801/`. P5 CPU/JIT throughput and
  cache locality is next.

### 2026-08-01 — headless cold-start MoltenVK deferral accepted

- `WINE_NO_EXPLORER=1` now skips the desktop-integration `RunServices` pass
  while retaining `services.exe`. This prevents `winemenubuilder.exe -a -r`
  from loading shell32/win32u and creating a MoltenVK Vulkan instance for a
  trivial console guest.
- Five cold-wineserver x86_64 runs returned `0`, emitted no MoltenVK records,
  and measured 0.58-0.71 seconds versus the prior 0.88-0.92 second baseline.
- The fresh single-prefix ARM64, ARM64EC, x86_64, and i386 matrix passed with
  `status=0`; evidence is in
  `docs/validation/perf-p3-defer-moltenvk-20260801/RESULTS.md`.

### 2026-08-01 — P0 correlated CPU startup baseline

- `scripts/benchmark-perf-p0.sh` runs two independent 20-sample sessions in
  four cold/warm Wine states, enforces `rc=0`, records macOS child resource
  usage, and requires correlated Wine/FEX lifecycle traces for every sample.
- The launcher, native Wine loader/NTDLL, wineserver connection, ARM64EC or
  WoW64 FEX provider, and exact teardown now share `VKMT_PERF_RUN_ID`.
- x86_64 warm persistent-session p95 is 25.819 ms; i386/WoW64 is 110.282 ms.
  Both complete baselines passed the 5% median/p95 repeatability gate. The
  i386 value is a measured optimization target and does not meet the final
  75-ms P3 gate yet.
- P0 remains active for graphics/shader/first-present and real Steam child
  lifecycle milestones. Current results are documented in
  `docs/validation/perf-p0-cpu-baseline-20260801/RESULTS.md`.

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

### 2026-07-28 — Phase 7 VKMT D3D9 loading complete

- `scripts/probe-p7-vkmt-d3d9.sh` proves DXVK 3.0.2 D3D9 loading in one
  fresh prefix for ARM64, ARM64EC, x86_64, and i386/WoW64.
- Every route passes `LoadLibrary`/`Direct3DCreate9`, adapter enumeration,
  display-independent `GetDeviceCaps`, Apple M4 selection, and MoltenVK
  routing. This is a D3D9 loading/caps result, not device/render/present.
- The first ARM64EC run found a stale `d3d9.dll`. The focused source rebuild
  now includes the MoltenVK feature-admission patch and the required x18-to-x28
  TLS post-link repair. Rebuild scripts are
  `scripts/build-dxvk-arm64ec-d3d9.sh` and
  `scripts/build-dxvk-i386-d3d9.sh`; the AArch64 DXVK builder stages D3D9 too.
- Accepted DXVK source revision:
  `58f17bb4839631aae49bdf221d01cfb17ed79aa8`.
- i386 `GetAdapterIdentifier` remains a headless monitor-name limitation, but
  its live DXVK adapter and D3D9 caps succeed. Exact evidence and DLL hashes
  are in `docs/validation/phase7-vkmt-d3d9-20260728/RESULTS.md`.
- The retained successful prefix was stopped through its exact wineserver and
  removed. Only the 88-KiB evidence bundle remains.

### 2026-07-28 — toggleable macOS MSync integrated

- Wine includes the modern CodeWeavers Mach-semaphore MSync backend, adapted
  from the CrossOver 26.3.0 FOSS Wine 11.0 source to this Wine 11.12 in-process
  synchronization contract.
- MSync is opt-in with `WINEMSYNC=1`. Unset and `WINEMSYNC=0` retain the
  existing wineserver synchronization path. Changing modes requires an exact
  wineserver shutdown for that prefix; mismatched clients are rejected.
- `scripts/probe-msync.sh` passes unset, explicit-off, and enabled modes,
  including event, semaphore, mutex, wait-all, signal-and-wait, APC,
  second-thread, abandonment, and cross-process named-event gates.
- `WINEMSYNC=1 scripts/probe-p6-single-prefix-architectures.sh` passes ARM64,
  ARM64EC, x86_64, and i386/WoW64 in one fresh prefix. Implementation,
  provenance, focused rebuild commands, and usage are in `docs/MSYNC.md`.

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

### 2026-07-31 — no-TSO Phase 5 child-process contract accepted

- `scripts/probe-no-tso-phase5.sh` passes a fresh-prefix i386 root/service to
  x86_64 client/helper chain with all three FEX TSO settings forced to zero.
- Both provider families attach before guest execution. Environment, current
  directory, standard pipes, inherited event/raw kernel handles, waits, exits,
  and final signalling pass across both architecture transitions.
- Exact i386 SteamService, i386 steamclient, and x86_64 steamclient probes pass;
  the exact x86_64 Steam WebHelper image/import closure is valid.
- Raw inherited socket handles intentionally produce `WSAENOTSOCK` until
  transferred with `WSADuplicateSocket`/`WSASocket`, matching Windows. A
  temporary incompatible `ws2_32` adoption change was fully reverted.
- Evidence is
  `docs/validation/no-tso-phase5-v8-20260731T041911Z/RESULTS.md`. The disposable
  prefix was removed, no process remained, and canonical provider bytes were
  restored. Phase 6 owns the valid real-parent WebHelper launch and clean Steam
  UI acceptance.

### 2026-07-31 — no-TSO Phase 1 accepted

- `scripts/probe-no-tso-phase1.sh` forces every FEX TSO option off and proves
  x86_64 plus i386 ordering, wait/wake races, condition variables, APCs,
  repeated threads, 128 concurrent children, and eight concurrent WinHTTP
  Steam-CDN range downloads in one fresh prefix.
- The i386 HTTPS failure was a nested native-ntdll-to-PE-wow64 pointer
  conversion during AFD send. Native ntdll now resolves its explicit mappings
  and Darwin high-aperture guest memory locally, avoiding that unsafe re-entry.
- Accepted evidence is
  `docs/validation/no-tso-phase1-20260731T024459Z/RESULTS.md`; both architectures
  matched the native 4-MiB payload hash eight out of eight. The exact prefix
  server was stopped and the disposable run root was removed.
- Do not enable `FEX_TSOENABLED`, `FEX_VECTORTSOENABLED`, or
  `FEX_MEMCPYSETTSOENABLED` for diagnostics or acceptance. Phase 2 proceeds by
  auditing and correcting explicit ARM64 ordering instructions with all three
  options fixed at zero.

## Compatibility expansion after the accepted runtime baseline

The post-baseline plan is `docs/COMPATIBILITY_EXPANSION_PLAN.md`. Its first
host task is a relocatable ARM64 GnuTLS closure: this Wine was configured with
`--with-gnutls` and compiled against `libgnutls.30.dylib`, but GnuTLS and its
nettle/GMP/p11-kit/gettext/IDN dependencies still resolve from Homebrew.
Staging, `@loader_path` rewriting, signing, native ARM64
Schannel/WinHTTP/WinINet TLS probes, and a no-Homebrew audit are required
before GnuTLS is called shippable. Guest-architecture HTTPS repetitions are
diagnostic only; Wine's server/Unix provider boundary is native ARM64.

### 2026-07-28 — all-architecture input provider accepted

- `scripts/probe-input-runtime.sh` proves all six XInput DLL families plus
  DirectInput and DirectInput8 in one fresh prefix for ARM64, ARM64EC,
  x86_64, and i386/WoW64.
- The accepted physical-controller route is the source-built ARM64
  `winebus.so` SDL backend and pinned ARM64 `libSDL2-2.0.0.dylib`. The probe
  sets `DisableHidraw=1` so the same controller is not also exposed through
  an unnormalized raw IOHID descriptor.
  `winexinput.sys`, `hidclass.sys`, XInput, and DInput remain Wine's
  architecture-appropriate PE modules; do not replace them with older
  packaged MetalSharp DLLs.
- A connected PS5 DualSense passed normalized XInput state, live-axis
  activity, `XINPUT_CAPS_FFB_SUPPORTED`, nonzero vibration calls, DirectInput
  controller enumeration, and keyboard/mouse enumeration in every guest
  mode. Multiple-pad and disconnect/reconnect testing are optional hardware
  extensions and do not block the accepted single-controller phase.
- Evidence is in `docs/validation/input-runtime-20260728/RESULTS.md`. The
  disposable prefix was stopped through its exact wineserver and removed.

### 2026-07-28 — i386 NSIS lifecycle accepted

- `scripts/build-nsis-fixture.sh` reproducibly builds the relocation-stripped
  i386 NSIS fixture with the in-tree LLVM-MinGW compiler and native ARM64
  `makensis`.
- `scripts/probe-nsis-runtime.sh` passes a fresh-prefix silent install,
  installed i386 payload execution, in-place uninstall-section cleanup, and
  registry removal. The in-place `_?=` route intentionally leaves only the
  running `uninstall.exe`; the exact disposable prefix is then stopped and
  trashed.
- Wine's ARM64 Darwin WoW64 arena reserves DOS compatibility memory at guest
  `0x110000` instead of allowing it to consume the conventional `0x400000`
  PE image base. `WINEPRELOADRESERVE` guest bounds are translated into the
  biased host arena, allowing relocation-stripped i386 images to load at
  their preferred base without breaking FEX.
- Post-change regressions passed the complete Phase 4 i386 contract, the
  single-prefix ARM64/ARM64EC/x86_64/i386 gate, every MSI lifecycle mode, and
  the preservation inventory. Evidence is in
  `docs/validation/nsis-runtime-20260728/RESULTS.md`.

### 2026-07-28 — installer completion accepted

- `scripts/probe-msi-runtime.sh` remains the all-architecture MSI lifecycle
  gate. `scripts/probe-installer-extended.sh` is explicitly the native ARM64
  `msiexec`/`msidb` extended-table gate; do not describe guest CLI modes as
  accepted merely because the MSI APIs pass there.
- The pinned Inno contract is native ARM64 `innoextract` plus real i386
  Inno 6.3.3 `ISCC.exe` execution through WoW64. The compiler builds the
  deterministic fixture and native extraction byte-validates its payload.
  Inno 6.5.4 is pinned and classified, but a GUI setup lifecycle is not
  claimed.
- `scripts/classify-installer.sh` is read-only. Burn, InstallShield, Squirrel,
  ClickOnce, MSIX, and AppX are diagnostic-only families and must fail before
  creating a prefix when `--require-runnable` is used.
- The staged extractor closure under
  `wine/build-ec/installer-runtime/innoextract/` is ARM64-only, signed, and
  free of Homebrew runtime paths. Evidence is in
  `docs/validation/installer-completion-20260728/RESULTS.md`.

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

### 2026-07-28 SDL2/SDL3 multi-architecture runtime

`scripts/build-sdl-runtime.sh` builds and stages SDL2 2.32.10 and SDL3 3.4.10
for AArch64, native ARM64EC, x86_64, and i386. The source trees are pinned at
VKMT commits `8f57bf76` and `1f46ec8b`, directly based on upstream release
commits `5d249570` and `8e37db5e`. The i386 build explicitly disables SIMD
and compiler vectorization so FEX never receives non-temporal vector stores
from these runtime DLLs.

`scripts/probe-sdl-runtime.sh` is the acceptance runner. It creates one fresh
prefix, performs native ARM64 wineboot, and proves SDL2 and SDL3 version,
dummy audio/video initialization, hidden-window creation, software-surface
clear/readback, event delivery, a second thread, dynamic DLL loading, and
clean subsystem shutdown on all four guest architectures. It also runs the
x86_64 MOVNT/PEXTRW emulator regression. The required final marker is
`VKMT_SDL2_SDL3_ALL_ARCHITECTURES_OK`.

The runner validates PE machine types, ARM64-only host Wine artifacts, and
the no-Rosetta process flag. It stops only the exact disposable prefix's
wineserver and trashes only its own run root on success or failure. Evidence
is in `docs/validation/sdl-runtime-20260728/RESULTS.md`.

### 2026-07-28 OpenGL multi-architecture checkpoint

`scripts/probe-opengl-all-arch.sh` proves `opengl32.dll`, WGL context
creation, Apple M4 / Metal renderer identity, an offscreen RGBA8 FBO,
deterministic clear/readback, and a GLSL 1.20 shader draw for ARM64, ARM64EC,
x86_64, and i386 in one fresh prefix. The required final marker is
`OPENGL_SINGLE_PREFIX_ALL_ARCHITECTURES_OK`. The complete Phase 4 WoW64
system contract also passes after the OpenGL pointer/USER callback repairs.

Wine's generated WoW64 OpenGL thunks now route i386 client pointers through
the canonical guest-memory manager, and the OpenGL 2.x extension parser marks
the parsed extension IDs correctly. `scripts/build-metalsharp-opengl.sh`
target-builds and stages the native ARM64 MetalSharp sidecar with pinned,
in-tree SPIRV-Cross and glslang dependencies.
`scripts/probe-metalsharp-opengl.sh` passes the separate GLSL 3.30 ->
SPIR-V -> MSL translation marker `METALSHARP_GLSL330_SPIRV_MSL_OK`.

The opt-in `VKMT_OPENGL_METAL_EXPERIMENTAL=1` path now owns translated shader
and program objects, creates a Metal render pipeline, submits `glDrawArrays`,
and implements synchronous RGBA8 `glReadPixels` through an aligned Metal
staging-buffer blit. Deterministic GLSL 3.30 and GLSL 4.50 draw/readback both
pass for ARM64, ARM64EC, x86_64, and i386 in the single-prefix runner. Wine must route
experimental `glReadPixels` to the sidecar because the normal macdrv wrapper
reads the legacy OpenGL drawable rather than the Metal render target.

Do not overstate this as complete OpenGL 3/4 API compatibility. Shader-version
coverage reaches GLSL 4.50; indexed drawing,
general vertex layouts, uniforms, textures, framebuffer integration, visible
presentation, and the wider GL3/4 entrypoint/state surface remain separate
gates. Exact results are in
`docs/validation/opengl-runtime-20260728/RESULTS.md`.

### 2026-07-29 Gecko/MSHTML and provider-stage invariant

`scripts/probe-gecko-mshtml.sh` is the fresh-prefix Gecko 2.47.4 acceptance
runner. It registers both registry views, proves the x86_64 SEH prerequisite,
proves i386 time, socket, DNS, GnuTLS/WinHTTP/WinINet HTTPS prerequisites, and
then runs Gecko-backed MSHTML document creation, JavaScript, DOM, event, and
HTTPS navigation for i386 and x86_64. The final required marker is
`GECKO_MSHTML_X64_I386_ALL_OK`.

Wineboot refreshes builtin modules from `wine/build-ec`; installing a provider
only into a new prefix before wineboot is not sufficient. The accepted i386
provider must first be staged at
`wine/build-ec/dlls/xtajit/aarch64-windows/xtajit.dll`. The Gecko runner pins
SHA-256
`7810c330b54c4a89c4062e6c9b34e5b54d588c39e39f37da9cb5b7c95444bbc6`
and verifies both the canonical stage and the post-wineboot prefix copy.
Never remove those post-bootstrap checks: a stale staged provider caused
deterministic i386 `CoCreateInstance` failure while all earlier prerequisites
still passed.

FEX distinguishes external i386 context transfers from contexts reconstructed
from its currently executing JIT block. External SetContext/SEH/APC transfers
discard provider call-return continuations; internal synchronous-fault
delivery imports architectural state while preserving the interrupted
simulation's call-return cursor. The complete Phase 4 WoW64 lifecycle gate and
Phase 5 repeated D3D12 readback gate pass with this split.
The accepted local source commits are FEX `b5174e00d` on branch
`vkmt/gecko-fresh-prefix` and Wine `6c11892`.

Two independent, empty, disposable prefixes passed the complete Gecko runner
without retries or copied profile data. Failed and diagnostic prefixes are
stopped through their exact wineserver and removed before another is created.

### 2026-07-29 — active completion sequence

The accepted baseline now includes native ARM64 Wine/wineboot, ARM64EC,
x86_64, and i386/WoW64 execution; VKMT/DXVK/vkd3d-proton, DXMT/Winemetal,
D3D9 loading/caps, MSync, SDL2/3, Metal-backed OpenGL, XInput/DirectInput,
MSI/WiX/NSIS/Inno, relocatable native GnuTLS HTTPS, and Gecko/MSHTML. Preserve
all of those gates while completing the following two phases.

**Phase 1 — provider and release hardening**

1. Make one shared runtime-provider staging command authoritative for
   `xtajit64.dll` and `xtajit.dll`.
2. Pin and verify provider hashes before wineboot, in the canonical build
   stage, and again in every new prefix after wineboot.
3. Route every fresh-prefix acceptance runner and release packager through
   that command so wineboot cannot silently restore a stale provider.
4. Prove a clean staged-prefix cycle plus the architecture, WoW64 lifecycle,
   Gecko, and graphics regressions.
5. Produce and verify a new local `.tar.zst` recovery snapshot containing
   Wine, providers, sources, build/stage scripts, dependencies, and probes.

**Phase 2 — browser and launcher engines**

1. Complete CEF for x86_64 and i386/WoW64 using pinned in-tree
   redistributables and the MetalSharp compatibility wrapper/child hook.
2. Gate `libcef.dll` exports, browser/renderer/GPU subprocesses,
   sandbox-disabled compatibility mode, offscreen rendering, input, audio,
   HTTPS, deterministic pixel/readback evidence, and exact child teardown.
3. Add a separately pinned WebView2 fixed-runtime lane with an
   Evergreen-style installer/launcher fixture.
4. Add Electron launcher fixtures and prove main/renderer/GPU process
   creation, HTTPS, input, deterministic rendering, and clean shutdown.

Do not call either phase complete from DLL presence or a warmed prefix. Each
final gate uses a fresh external-SSD prefix, exact provider hashes, native
ARM64 host closure, no Rosetta, bounded child processes, exact wineserver
shutdown, and automatic disposal on both success and failure.

### 2026-07-29 — Phase 1/2 implementation checkpoint

Phase 1 is implemented through the shared
`scripts/stage-runtime-providers.sh` entry point and every fresh-prefix runner
now invokes it. The accepted i386 provider is
`runtime-providers/xtajit-arm64-known-good.dll` with SHA-256
`ea523a42ca8e7965371122bd7be1eb6b973cded50ecda5da1465b2961ad36479`;
the accepted x86_64/ARM64EC provider is
`runtime-providers/xtajit64-arm64ec-known-good.dll` with SHA-256
`3025e679b3728536896d9fd3d78138f3fc26e67ee98ad6d62f2a95e07457b132`.
The pre-wineboot canonical-stage and post-wineboot prefix checks remain
mandatory. Baseline architecture, Phase 4 WoW64, Gecko, and i386 graphics
regressions passed during this hardening pass. The remaining Phase 1
deliverable is the newly verified `.tar.zst` recovery snapshot; do not replace
or delete the existing runtime while producing it.

The previous CEF diagnostic boundary is resolved. Wine now releases and
restores the exact recursive USER-lock depth around nested message, hook,
window-call, and accessibility callbacks. WoW64 process-attribute conversion
always installs the converted high-host `PS_ATTRIBUTE_IMAGE_NAME` pointer, so
i386 Chromium child creation no longer passes a raw guest pointer to
`NtCreateUserProcess`. The canonical `GetWindowThreadProcessId` guest-pointer
repair, focused i386 USER fixture, and WoW64 CoreAudio nested-pointer
conversion are built and passing. Temporary backtraces, callback traces, VEH,
PID, window, and CreateProcess instrumentation have been removed.

A new disposable prefix passed the pinned official CEF 109 x86_64 and i386
export and subprocess acceptance with GPU, renderer, and utility child-command
evidence and exact cleanup. Required markers are
`CEF_X86_64_SUBPROCESS_RUNTIME_OK`, `CEF_I386_SUBPROCESS_RUNTIME_OK`, and
`CEF_X64_I386_ALL_OK`. Do not overstate this boundary as the complete Phase 2
contract: automated OSR pixel readback, synthetic input, HTTPS/audio evidence,
WebView2 fixed-runtime acceptance, and Electron main/renderer/GPU acceptance
remain to be implemented and proven.

### 2026-07-29 — provider hardening, recovery image, and browser checkpoint

Root commit `aa100f6` contains the shared provider staging integration,
browser/runtime fetchers and probes, focused architecture fixtures, and the
reproducible snapshot creator. Wine commit `fb22a97` preserves the accepted
WoW64/browser callback work,
ARM64EC/x64 LSE feature publication, CoreAudio nested-pointer conversion,
`TlsGetValue2`/`FlsGetValue2` compatibility aliases, and both canonical
runtime providers. The current provider hashes are:

- `xtajit64-arm64ec-known-good.dll`:
  `7b9f55ceabe971ffa1f514570bb54ed7b5640959e4440e7f8a013e9af13ab7e6`
- `xtajit-arm64-known-good.dll`:
  `ea523a42ca8e7965371122bd7be1eb6b973cded50ecda5da1465b2961ad36479`

Every fresh-prefix runner uses `scripts/stage-runtime-providers.sh`; it verifies
the canonical source/build copies before wineboot and the prefix copies after
wineboot. A final clean run of
`scripts/probe-p6-single-prefix-architectures.sh` passed
`P6_SINGLE_PREFIX_ARM64_OK`, `P6_SINGLE_PREFIX_ARM64EC_OK`,
`P6_SINGLE_PREFIX_X86_64_OK`, `P6_SINGLE_PREFIX_I386_OK`, and
`P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK`.

The high-compression recovery image is:

- `/Volumes/AverySSD/VKMT_snapshots/VKMT-runtime-phase2-20260729-050624.tar.zst`
- compressed size: 3.6 GiB; logical tar size: 23.5 GiB
- SHA-256:
  `777aaa94f49942301e4e1185961893bfd3f4f2e8f63366dc9ca3ecc2cbb8876c`
- manifest:
  `/Volumes/AverySSD/VKMT_snapshots/VKMT-runtime-phase2-20260729-050624.manifest.txt`

`zstd -t --long=31` passed, the full tar manifest was decoded, and the
manifest contains Wine, wineserver, both providers, the shared staging helper,
and the single-prefix acceptance runner. Recreate future images only through
`scripts/create-runtime-snapshot.sh`; it streams tar directly into zstd and
does not create an uncompressed intermediate.

Browser/launcher gates now have explicit levels:

- CEF 109 x86_64 and i386 pass export and browser/renderer/GPU/utility
  subprocess acceptance through the MetalSharp compatibility DLL and child
  hook.
- WebView2 fixed runtime 149 x64 passes environment/controller creation,
  host HTTPS, renderer/utility/GPU startup, and `ExecuteScript` dispatch. The
  callback does not yet return, so this is
  `WEBVIEW2_X64_FIXED_RUNTIME_BOOTSTRAP_OK`, not the full
  HTTPS/input/audio/pixel marker.
- Electron 42.7.1 x64 passes deterministic HTTPS, renderer input,
  `OfflineAudioContext`, RGBA pixel readback, renderer/GPU/utility creation,
  and teardown with `ELECTRON_X64_OK`.
- Electron 42.7.1 ia32 advances through image/V8 initialization but eventually
  dereferences a decommitted Chromium allocation. An experiment reserving the
  WoW64 guest-null granularity moved that boundary but regressed the golden
  i386 Phase 6 gate and was reverted. Do not reintroduce it.

Therefore Phase 1 is complete. Phase 2 is not to be called fully complete
until CEF OSR/input/audio/HTTPS pixel evidence, WebView2 callback completion,
and Electron ia32 renderer acceptance pass without weakening the four-mode
single-prefix baseline. Failed probe roots are always stopped through their
exact wineserver and disposed before another prefix is created.

### 2026-07-29 — post-Phase-D roadmap correction

Phase G has been removed from the authoritative roadmap. LDAP,
Kerberos/GSSAPI, NTLM, ODBC, printing, smart-card, serial, scanner/camera,
COM/DCOM service expansion, scheduled-task, and shell-association coverage are
not required for completion of this runtime.

Phase F is not a from-scratch redistributable build. The current
`wine/build-ec` tree already contains ARM64, x86_64, and i386 modules for
D3DCompiler, XAudio2/XACT, UCRT/Visual C++/ATL, MSXML, Quartz, Media
Foundation, MIDI, WineGStreamer, and Windows codecs; ARM64EC uses the native
ARM64 lane. XNA/FNA and FAudio assets are complete through the preserved
MetalSharp runtime lane, and legacy D3DX9/10/11 remains intentionally excluded.
The honest remaining Phase F work is focused all-architecture API acceptance,
relocatable native audio/video dependency closure, deterministic playback,
and an explicit include/exclude decision for MFC, OpenAL, PhysX, and core
fonts. Module presence alone is not acceptance evidence.

### 2026-07-29 — Phase F closed; Phase E is the sole remaining expansion

This entry supersedes the Phase F remaining-work paragraph immediately above.
Phase F requires no additional validation. Preserve the already-built
D3DCompiler, XAudio2/XACT, UCRT/Visual C++/ATL, MSXML, Quartz, Media
Foundation, MIDI, WineGStreamer, Windows codec, XNA/FNA, and FAudio surfaces,
but do not spend completion work on new Phase F probes. Legacy D3DX9/10/11,
MFC, OpenAL, PhysX, and additional core-font payload work are outside scope.

Phase E managed and language runtimes is now the only remaining compatibility
expansion phase. Complete it without reopening Phase F or the removed Phase G.

### 2026-07-29 — Phase E Wine Mono 11.2.0 checkpoint

Official Wine Mono 11.2.0 is the sole Mono payload. The pinned GitHub runtime
archive SHA-256 is
`c9fb2e2823acf30b000b8806177db0f40751786136dd3f8fb2be7897b1643d06`;
the matching source archive SHA-256 is
`aebef9b43dca80b3ebe4a0ada0f45925d833f371ba5b42f5acf9990461568ba9`.
Do not replace either with a distro or Homebrew Mono.

`scripts/build-wine-mono-arm64.sh` applies the tracked ARM64 CoreEE/W^X and
Wine managed-loader patches, builds only the required Mono ARM64 targets, and
rebuilds only Wine's ARM64X `mscoree.dll`/`ntdll.dll`, native `ntdll.so`, and
`wineserver`. It audits x18 and stages the result beside the official
x86/x86_64 engines. The 16-KiB protection is required: Wine exposes 4-KiB
guest pages, but Darwin ARM64 combines four of them into one host page;
protecting only the generated trampoline's guest page leaves the host page
write-only.

`scripts/probe-wine-mono-runtime.sh` is the clean-prefix acceptance runner.
It passes managed compilation plus pointer width, threads, reflection, XML,
kernel32 P/Invoke, exact wineserver shutdown, and cleanup for:

- direct i386 CLR startup using the official x86 engine;
- native ARM64 CLR startup using the source-built engine;
- direct PE32+ x86_64 IL-only startup using the native ARM64 CLR contract.

The required terminal marker is `VKMT_WINE_MONO_11_2_0_ALL_OK`. Wine now
classifies same-bitness PE32+ IL-only images as native 64-bit managed
processes before stack creation, image-view registration, and ARM64EC provider
startup. Their raw AMD64 PE header is preserved for file identity, but no x64
instructions exist to emulate. Native-code x86_64 images are unchanged and
continue through `xtajit64`; the post-change single-prefix regression passes
ARM64, ARM64EC, x86_64, and i386. Evidence is in
`docs/validation/wine-mono-11.2.0-20260729/RESULTS.md`. No diagnostic prefix is
retained.

### 2026-07-29 — Phase E native ARM64 Java checkpoint

The private Oracle JRE 8u501 ARM64 lane is accepted. Its DMG remains pinned at
SHA-256
`3f488bb03113460719c4c16737c37e2ee22a85487b877b146bd33e4b4a00e7d1`
and must not be redistributed outside this runtime.
`scripts/stage-native-java-runtime.sh` verifies the staged `java` and
`lib/server/libjvm.dylib` as signed ARM64 Mach-O binaries, rejects Homebrew
dependencies, and proves that `-server` selects the 64-bit HotSpot Server VM.

`scripts/stage-native-java-handoff.sh --prefix PREFIX` performs the reusable
targeted build and prefix installation of
`C:\vkmt\bin\vkmt-native-java-handoff.exe`. The ARM64 PE is compiled with
`-ffixed-x18 -ffixed-x28`, audited for `x18`, and uses Wine's
`__wine_unix_spawnvp` boundary. Its explicit environment contract is
`VKMT_NATIVE_JAVA`, `VKMT_NATIVE_JAVA_JAR`, `VKMT_NATIVE_JAVA_JNI`, and
`VKMT_NATIVE_JAVA_TLS_URL`.

`scripts/probe-native-java-runtime.sh` passes native class-path and executable
JAR execution, ARM64 JNI, deterministic TLS 1.2, and the fresh-prefix Wine
handoff. The required terminal marker is `VKMT_NATIVE_JAVA_8U501_ALL_OK`.
Evidence is in
`docs/validation/native-java-8u501-20260729/RESULTS.md`. Eclipse ECJ 4.6.1 is
pinned under `third_party/build-tools` only to compile the acceptance fixture;
it is not shipped with the private JRE. No probe prefix or log root is
retained.

Remaining Phase E scope: add Windows Java i386/x86_64, then stage/gate .NET
Framework and modern .NET/PowerShell, followed by opt-in Python and Node
fixtures.

### 2026-07-29 — Windows Java i386/WoW64 scope and plan

The implementation plan is `docs/WINDOWS_JAVA_WOW64_PLAN.md`. Current
official inputs are Temurin 8u472-b08 for Windows i386 (the newest published
x86 JRE) and Temurin 8u492-b09 for Windows x86_64. Their ZIP hashes,
architecture inspection, HotSpot VM variants, imported APIs, FEX/Wine
ownership map, phased gates, and promotion regressions are recorded there.

The i386 archive contains only the PE32 HotSpot Client VM; do not require a
nonexistent i386 Server VM. The x86_64 archive contains the PE32+ Server VM.
The accepted `ea523a42...` i386 provider remains the first-run and rollback
baseline. The current FEX worktree's uncommitted TSO/unaligned/W^X candidates
must build and stage beside it, never over it. No Windows JRE or candidate
provider was staged during this planning pass, and all transient archive
inspection roots were removed.

For Java, preserve FEX's x86 TSO classification but never rely on host
hardware TSO. Before either JVM launches, generated ARM64 code must prove
aligned `LDAR`/`STLR`, unaligned `LDR; DMB ISHLD` and `DMB ISH; STR`, and
acquire/release locked-RMW lowering. Preserve NZCV across alignment
selection, do not backpatch Darwin RX pages, and do not use the candidate
`LDAPR` shortcut as the conservative Java baseline.

### 2026-07-29 — Windows Java phase J0 complete

The authoritative i386 source/build pair was recovered from
`VKMT-runtime-phase2-20260729-050624.tar.zst`: its
`build/fex-wow64-baseline-build/Bin/libwow64fex.dll` is byte-identical to the
accepted `ea523a42...` provider. The archive's later
`third_party/FEX-2607` tree was not the source of that binary. The exact
baseline plus the Java delta is retained in-tree as
`third_party/FEX-2607-java-baseline`.

`scripts/build-fex-wow64.sh` now accepts `VKMT_FEX_SOURCE`, emits only a side
candidate by default, and refuses to overwrite the Wine build. The final J0
candidate is
`build/fex-wow64-java-final/provider/xtajit.dll`, SHA-256
`f7ace1980b33e270c9ee8b9d240705a82bcface99e868ff65895a3dbcfd4d247`.
It has not been promoted.

The fresh disposable-prefix gate passed
`VKMT_WINDOWS_JAVA_J0_TSO_OK`. Its i386 publication/alignment/atomic fixture
returned the deterministic checksum `00000000a5a50ff0`; offline disassembly of
629 generated blocks proved `LDAR`/`STLR`, unaligned
`LDR; DMB ISHLD`, `DMB ISH; STR`, and `CASAL`, with no `LDAPR`/`LDAPUR`.
The complete wrapping i386 effective address is translated only after its
offset is applied, NZCV is preserved, both alignment paths are emitted before
RX publication, and Windows FEX never enables hardware TSO.

The pinned Temurin stages also pass architecture and dependency audits:
i386 8u472-b08 contains 107 PE32 files with the Client VM; x86_64 8u492-b09
contains 104 PE32+ files with the Server VM. Both canonical providers remain
byte-identical, the exact wineserver was stopped, and no J0 prefix remains.
Evidence is in `docs/validation/windows-java-j0-20260729/RESULTS.md`.

### 2026-07-29 — Windows Java phase J1 complete

`scripts/probe-windows-java-j1-interpreters.sh` passed
`VKMT_WINDOWS_JAVA_J1_INTERPRETERS_OK` in one fresh prefix, running the
x86_64 control lane before i386/WoW64. The J0 i386 TSO/CAS preflight passed
first with checksum `00000000a5a50ff0`.

Temurin x86_64 8u492-b09 reported the OpenJDK 64-Bit Server VM,
`sun.arch.data.model=64`, `os.arch=amd64`, and `interpreted mode` under
`-server -Xint`. Temurin i386 8u472-b08 reported the OpenJDK Client VM,
`sun.arch.data.model=32`, `os.arch=x86`, and `interpreted mode` under
`-client -Xint`.

Both JVMs passed the same class-path and executable-JAR fixture. Each run
loaded an isolated class through `URLClassLoader`, invoked it by reflection,
opened the executable JAR as a ZIP, and validated its payload. The exact
wineserver was stopped and waited; no Java/Wine process or J1 prefix remains.
Both accepted provider copies remain byte-identical and the J0 i386 candidate
was not promoted. Evidence is in
`docs/validation/windows-java-j1-20260729/RESULTS.md`.

### 2026-07-29 — Windows Java phase J2 complete

`scripts/probe-windows-java-j2-services.sh` passed
`VKMT_WINDOWS_JAVA_J2_SERVICES_OK` in one fresh prefix, running the x86_64
control lane before i386/WoW64 under `-Xint`.

The probe builds architecture-matched Windows JNI fixtures from the same C
source with the in-tree LLVM-MinGW toolchain and pinned OpenJDK 8u472 headers.
Both PE32+ and PE32 DLLs export `JNI_OnLoad` and the required native methods.
The x86_64 and i386 JVMs passed JNI callbacks, callback exceptions, native
thread attach/callback/detach, allocation/GC pressure, direct and mapped
buffers, repeated isolated class loading, monitors, Java TLS, exceptions,
stack overflow, `ProcessBuilder`, loopback sockets, deterministic local TLS,
QPC timing, sleeps, and shutdown hooks.

The i386 lane reported `pointerBits=32` and a Java-visible native address of
`0x78925034`; no host-width pointer crossed that boundary. Both child JVMs
exited, mapped files were removed by shutdown, and the exact wineserver was
stopped and waited. No J2 prefix or process remains. The accepted providers
remain byte-identical and the J0 candidate remains unpromoted. Evidence is in
`docs/validation/windows-java-j2-20260729/RESULTS.md`.

### 2026-07-29 — Windows Java phase J3 complete

`scripts/probe-windows-java-j3-jit.sh` passed
`VKMT_WINDOWS_JAVA_J3_JIT_OK` in one fresh prefix. The order was x86_64
Server tiered, x86_64 scoped `-Xcomp`, i386 Client/C1, then i386 scoped
`-Xcomp`. Fixture compilation counts were respectively 26, 124, 27, and 23;
all four lanes also reported nonzero HotSpot compilation time.

The architecture-matched JNI fixtures repeatedly changed a private code page
RW→RX, called `FlushInstructionCache`, executed it, changed it back to RW,
patched it, and executed the replacement. Each lane passed 257 protection
transitions/flushes and 128 code patches. The Java fixture passed hot compiled
loops, tiered polymorphic deoptimization, four isolated class-loader
compile/unload/recompile waves, explicit divide/null exception guards,
recursive stack overflow and resume, and code-cache telemetry. Scoped
`-Xcomp` excludes only orchestration/reflection and exception-catching
coordinators; the kernels and isolated payloads remain forced-compiled.

J3 exposed that x86 HotSpot may recycle executable code without an x86
`FlushInstructionCache` contract and that broad outer tier-0 translation is
not yet a safe control lane for forced HotSpot code. The side x86_64 provider
therefore validates cached guest bytes, invalidates on free/unmap, and
supports `VKMT_X64_TIER0=0`. J3 uses that toggle while leaving HotSpot JIT
enabled. The side candidate is
`build/xtajit64-java-j3-final/provider/xtajit64.dll`, SHA-256
`3c5878816c78dc670190e3587e76ace53e472c14a50972cd97808fda25636c3b`.
Neither it nor the J0 i386 candidate was promoted.

The exact wineserver stopped and waited; no Java/Wine process or J3 prefix
remains. Both canonical providers and build copies remain byte-identical.
Evidence is in `docs/validation/windows-java-j3-20260729/RESULTS.md`.

### 2026-07-29 — Windows Java phase J4 complete

`scripts/probe-windows-java-j4-memory-model.sh` passed
`VKMT_WINDOWS_JAVA_J4_MEMORY_MODEL_OK`. It ran the accepted i386 provider
first and selected it unchanged; the J0 side candidate was not needed and
remains unpromoted.

Three independent repetitions each used a fresh disposable prefix. In every
prefix, a mixed/JIT lane passed volatile publication, contended monitors,
wait/notify, 32-bit and 64-bit CAS, concurrent queue/once initialization,
deliberately unaligned scalar publication, REP stores, and
`movntq`/`sfence`. A separate `-Xint` allocation lane then kept four mutators
active through an observed young collection and verified 20,000 rooted
objects plus deterministic field and pressure-buffer checksums.

The candidate's pre-JVM generated-code gate still proved conservative
software TSO lowering (`LDAR`/`STLR`, `LDR; DMB ISHLD`,
`DMB ISH; STR`, acquire/release locked RMW), no `LDAPR` shortcut, and no
hardware-TSO enablement. Every exact wineserver stopped and waited, all J4
prefixes were deleted, and canonical provider hashes remain unchanged.

A deeper combined compiled-mutator/repeated-safepoint experiment reproduced
class-dispatch corruption or a later publication stall in both provider
lanes. This is preserved as J5 diagnostic evidence, not hidden: phase J5
explicitly owns compiled execution across GC safepoints and repeated VM
lifecycle. J4 evidence is in
`docs/validation/windows-java-j4-20260729/RESULTS.md`.

### 2026-07-29 — Windows Java phase J5 complete

`scripts/probe-windows-java-j5-lifecycle.sh` passed
`VKMT_WINDOWS_JAVA_J5_LIFECYCLE_OK` in one fresh prefix. It completed 10
i386 Client-VM launches with 10 lifecycle cycles each: 100/100 total and
`exact_shutdown=1`. Every cycle ran four C1-compiled/allocation workers
through two full collections, a JNI native-thread attach/Java callback/detach
held across GC, PE TLS, APC delivery, compiled null/divide exceptions, and
exact worker/JVM exit. Launch 0 also passed a controlled normal-HotSpot
SuspendThread/GetThreadContext/SetThreadContext/ResumeThread roundtrip.

The accepted J5 side provider is
`build/fex-wow64-java-j5-divide/provider/xtajit.dll`, SHA-256
`fe1345724f6a2950541966515f766099b7bce38701c9960d4be513c27ec81073`.
The final targeted `wine/build-ec/dlls/wow64/aarch64-windows/wow64.dll`
is SHA-256
`3f252921f12806907c78a4bf07c1aa5a761ba7882d3b72bb876c1dc316f93e7b`.
The canonical known-good provider was not overwritten.

The root J5 failure was stale FEX translation of HotSpot C1 code containing
GC-patched embedded object references. FEX now converts tracked host code
addresses back to canonical i386 guest VAs, invalidates only code-cache ranges
that are actually writable, and reprotects them at quiescent non-alertable
wait boundaries. Synchronization is deferred while another guest thread is
in translated execution. The local suspend path releases the global
thread-map mutex before interrupting the target, cross-thread context locking
never imports the caller's CPU area, no-op context transfers preserve the
call-return cursor, and compiled divide faults carry exact guest RIP and the
Windows integer-divide status.

The final regression `scripts/probe-i386-wow64-phase4.sh` passed context, SEH,
APC, second-thread, user-callback, repeated-thread, and Phase 3 execution
gates. Alertable waits are deliberately excluded from dynamic-code
synchronization so APC return nesting remains intact. Both probe scripts now
delete their exact disposable roots after exact wineserver `-k`/`-w`; no J5
or Phase 4 process/prefix remains.

Evidence is
`docs/validation/windows-java-j5-20260729/RESULTS.md`. Reproducible ignored
source-tree snapshots are `patches/fex-2607-java-j5.patch` and
`patches/wine-11.12-java-j5.patch`; both pass `git apply --check` against FEX
commit `a745bebae8c65025869288be1b50275928702338` and Wine commit
`fb22a9782ad812d0cf9df9021047eccee84b5135`, respectively. Phase J6 is now
active; do not promote either provider until its unified-prefix and affected
graphics/browser regressions pass.

### 2026-07-29 — Windows Java phase J6 complete

`scripts/probe-windows-java-j6-unified.sh` passed
`VKMT_WINDOWS_JAVA_J6_UNIFIED_OK` in one clean prefix. The exact sequence was
the native Oracle 8u501 ARM64 Server VM handoff, Windows Temurin x86_64 Server
VM, Windows Temurin i386 Client VM, then ARM64, ARM64EC, x86_64, and i386
Wine fixtures. Exact wineserver shutdown passed and no disposable prefix or
process remained.

The accepted J5 i386 provider is now canonical in both
`wine/wine-11.12/runtime-providers` and `wine/build-ec`, SHA-256
`fe1345724f6a2950541966515f766099b7bce38701c9960d4be513c27ec81073`.
The established x86_64 provider remains canonical at
`7b9f55ceabe971ffa1f514570bb54ed7b5640959e4440e7f8a013e9af13ab7e6`.
Build-tree loading showed that prefix-only tests had not selected the
experimental J3 x86_64 candidate. Putting it in the actual build-tree load
path reproducibly crashed its tier-0 interpreter, so it was rejected and the
established binary was restored byte-for-byte.

The final canonical configuration passed the complete Phase 4 WoW64
contract, i386 VKMT DXGI/D3D12/D3D11, Gecko/MSHTML, OpenGL through GLSL 4.5
Metal readback, SDL2/SDL3, and the ordinary four-architecture single-prefix
gate without provider overrides. Affected probes now re-stage selected
providers after `wineboot` and delete only their exact run roots. Evidence is
`docs/validation/windows-java-j6-20260729/RESULTS.md`.

The verified J6 recovery image is
`/Volumes/AverySSD/VKMT_snapshots/VKMT-runtime-j6-20260729-1738.tar.zst`
(4.38 GiB), SHA-256
`be5f656e857f3fb1d3b8a9ec528655e22947372dfa1651244b1d2bc9d49a2298`.
Its 322,137-entry manifest is beside it as
`VKMT-runtime-j6-20260729-1738.manifest.txt`. The archive passed `zstd -t`
and required-manifest checks for Wine, both canonical providers, the J5
Wine/FEX patches, the J6 runner, and the Java/WoW64 plan.

### 2026-07-30 — Steam WebHelper ARM64EC syscall boundary complete

The installed x86_64 `steamwebhelper.exe` CEF runtime now passes sustained
40-second probes in the existing all-architecture Steam prefix with both
`FEX_TSOENABLED=0` and `FEX_TSOENABLED=1`. Both lanes reached the extended
CEF dependency set, including Shell, SDL3, SetupAPI, and HID, without the
previous `chrome_elf` PartitionAlloc trap, another exception, or an error
signature. Each run ended with exact wineserver `-k`/`-w`; no helper or Wine
process remains.

The failure was not TSO scheduling. The x64 `NtQueryValueKey` path supplied a
24-byte output buffer, but the internal ARM64EC syscall hp target received
guest `R10/R11` as native arguments 5/6 because the hp-target shortcut
bypassed the normal ARM64EC entry-thunk argument lift. Wine consequently
treated a large pointer as the buffer length and wrote registry data into
Chrome's adjacent PartitionAlloc freelist word.

`ExitFunctionEC` now performs the complete x64-to-native syscall call
contract: x64 stack arguments 5-8 are loaded into `x4-x7`, arguments 9-16 are
copied into an aligned native stack frame, and the exact guest return address
and post-pop stack pointer survive the native syscall in memory. Sixteen
arguments covers the largest syscall in the pinned Wine table. Temporary
Steam/allocator watchpoints, transition histories, and exception tracing
were removed after proof.

The complete accumulated FEX ARM64EC/WoW64 boundary is committed in the FEX
source tree as `6b17b7c1e` (`Complete ARM64EC and WoW64 guest boundary`).
The clean provider SHA-256 is
`4d52a4f2a6d6c8587d1d4274346826738026abf2e93a29d591f9574364367db0`;
the candidate, Wine build-tree provider, and prefix provider are
byte-identical. Probe logs are
`/tmp/vkmt-steamwebhelper-clean-tso0.log` and
`/tmp/vkmt-steamwebhelper-clean-tso1.log`.

### 2026-07-30 — Steam bootstrap recovery made installer-safe

The former Steam `RtlWaitOnAddress` workaround incorrectly applied to every
`steam.exe`, including the client launched by `SteamSetup.exe`, and classified
one second without a bootstrap-log write as a hang.  That could synthesize a
wake during a legitimate package/network transition and produce Steam's
spurious “must be online to install” failure.

`dlls/ntdll/sync.c` now enables the recovery only when
`VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY=1` is explicitly supplied.  The ordinary
SteamSetup launcher never supplies that environment value.  The installed
client launcher is `scripts/launch-steam-client-recovery.sh`; it is a one-shot
launcher and uses the recovery only after `Steam.exe` exists.  It polls the
specific `CHTTPClientThreadPool:0` infinite wait every ten seconds, requires
twenty seconds without a `logs\\bootstrap_log.txt` write, and permits at most
two spurious wakes per client process.

The active installer launch is the user LaunchAgent
`com.vkmt.steamsetup-one-shot`, explicitly `RunAtLoad=false` and
`KeepAlive=false`; it has no relaunch-on-exit behavior.  The old inferred-
KeepAlive `launchctl submit` job was removed.  `ntdll.so` was rebuilt only
from the changed `sync.c` object and relinked at `wine/build-ec/dlls/ntdll/`.

### 2026-07-30 — Direct Rosetta boundary comparison

Direct probes of Apple's installed Rosetta runtime (without Wine or GPTK)
passed eight concurrent Steam-CDN range downloads with 33,554,432 verified
bytes, 128/128 translated child-process handoffs, one million acquire/release
publications, and 200,000 pthread condition-variable ping-pong rounds per
thread. The x86 acquire/release path contained only ordinary `movl`
instructions, so Rosetta itself preserved the required x86 ordering.

`vmmap` confirmed a complete translated-process environment: Rosetta runtime,
per-thread context and return stack, a 128 MiB JIT arena, x86_64 dyld, and
x86_64 libsystem kernel/pthread libraries. This differs structurally from
VKMT's mixed FEX guest/native ARM64 Wine Unix boundary, where pointers,
wait/wake state, exceptions, and child bootstrap must be explicitly bridged.
Evidence and the reusable source probe are in
`docs/validation/rosetta-boundary-20260730/RESULTS.md` and
`test/rosetta_sync_probe.c`.

### 2026-07-30 — No-TSO Rosetta-parity Phase 0 instrumentation complete

Phase 0 of `docs/NO_TSO_ROSETTA_PARITY_PLAN.md` completed the instrumentation
and no-TSO assertion work. The original runner staged provider candidates
only inside the prefix, while x86_64 bootstrap actually loaded `xtajit64.dll`
from `WINEBUILDDIR`. Consequently its x86_64 v12-candidate acceptance claim
was invalid and is superseded by the correctly staged Phase 2 evidence below.
The instrumentation-disabled silence gate and the i386 candidate checks remain
valid.

The Phase 0 candidates were
`docs/validation/no-tso-phase0-20260731T013101Z/candidates/xtajit-authoritative-v12.dll`
(SHA-256 `b2a24e4585b44119b1d8ff9a8907987036ab8ed7992d6dcb148600fbaba4422e`)
and `xtajit64-authoritative-v12.dll` (SHA-256
`455730fec28029be1c646147214f164164726f1ee5b542f2f69b409b11a07c86`).
The established canonical provider files were deliberately preserved. The
x86_64 v12 candidate hangs in `wineboot` when placed in the real bootstrap
path and must not be promoted.

Provider startup now checks the effective scalar, vector, and memcpy/set TSO
settings and uses an unconditional release-build fail-fast trap if any is
enabled. Three isolated negative controls enabled one setting at a time solely
to prove rejection; all three failed before i386 guest execution and were
cleaned. They are tests, not supported runtime modes, and must never be used by
normal launchers.

Wine has opt-in bounded counters for WaitOnAddress registration, early wakes,
delivery/retention, timeout, and synthetic recovery, plus one provider-handoff
record per emulated process. Steam-specific wake recovery remains separately
identified from generic synchronization work. Only affected FEX providers,
ARM64X `ntdll.dll`, and native ARM64 `wow64.dll` were rebuilt; there was no full
Wine rebuild. Complete evidence is
`docs/validation/no-tso-phase0-20260731T013101Z/RESULTS.md`. Phase 1 deterministic
ordering/synchronization fixtures are next.

### 2026-07-30 — No-TSO Rosetta-parity Phase 2 complete

The software x86 memory-ordering contract now passes on both x86_64 and i386
with `FEX_TSOENABLED=0`, `FEX_VECTORTSOENABLED=0`, and
`FEX_MEMCPYSETTSOENABLED=0`. Ordinary guest loads end with `DMB ISHLD`;
ordinary stores end with `DMB SY`; locked operations retain LSE acquire/release
or `LDAXR`/`STLXR`; explicit fences use `DMB LD/ST/SY`. Syscall, Unix-thunk,
callback, and ARM64EC guest/native boundaries now emit `DMB SY` before transfer
and/or after native return as applicable. No hardware TSO or Rosetta process
participates.

The final candidate providers are
`build/no-tso-phase2/providers/xtajit64-no-tso-final-v15.dll` (SHA-256
`a0a586eb6687dd45bdb4818e44c64294f4cfed89dc5b5bafd806c3d402100513`)
and `xtajit-no-tso-final-v15.dll` (SHA-256
`67192836cb4eb15cb51ef5487a4ec30a3fa210bfac370e3193ede3760a4e4273`).
The x86_64 candidate uses the preserved working FEX source/configuration
lineage with no release optimization flags and LTO disabled. Both providers
received the required two-site x18-to-x28 PE TLS fix.

The corrected runners temporarily stage candidates in the real Wine build-tree
bootstrap path, verify hashes, and restore the exact prior bytes after exact
wineserver shutdown. The final one-prefix Store Buffering gate passed
1,000,000 rounds per architecture with zero forbidden outcomes. The complete
Phase 1 regression also passed: all ordering/wait/condition/APC/thread gates,
128/128 children per architecture, and 8/8 verified 4 MiB CDN transfers per
architecture. Steam-specific wake injection remained disabled. Evidence is
`docs/validation/no-tso-phase2-final-v15-20260731T034214Z/RESULTS.md` and
`docs/validation/no-tso-phase2-phase1-regression-v15-20260731T034241Z/RESULTS.md`.
The canonical build-tree providers were restored byte-for-byte; Phase 3 is the
active wait/wake bridge work.

### 2026-07-30 — No-TSO Rosetta-parity Phase 3 complete

Wine's WoW64 WaitOnAddress bridge now uses runtime `WowTebOffset` detection,
queue-locked compare/registration, and per-waiter synchronization events. The
waker removes and signals the entry while holding the queue lock; the waiter
always reacquires that lock before examining its stack-backed entry and runs
an explicit ARM64 acquire barrier after observing either wait transport.

The former fixed 16-slot raw-pointer pending-wake cache was removed. A wake
with no registered waiter is discarded according to WakeByAddress semantics,
so overflow, eviction, and virtual-address reuse cannot deliver an old wake.
The fixture now verifies both an unregistered stale wake and free/reallocate at
the exact same virtual address.

Only ntdll sync objects and the ARM64X, i386, and x86_64 PE ntdll outputs were
rebuilt. Three consecutive fresh-prefix runs passed on x64 and i386: 20,000
registration races, stale-address rejection, WakeSingle/WakeAll, 2,000 timeout
races, conditions, APCs, repeated threads, 128/128 children, and 8/8 verified
Steam-CDN transfers. Every TSO setting and Steam wake recovery remained off.
Evidence is
`docs/validation/no-tso-phase3-wait-final-20260731T034855Z/RESULTS.md`.
Phase 4 asynchronous networking is active.

### 2026-07-30 — No-TSO Rosetta-parity Phase 4 complete

The new `scripts/probe-no-tso-phase4.sh` and
`test/no_tso_phase4_network.c` pass asynchronous networking on x86_64 and
i386 in one clean prefix. Each architecture completes eight simultaneous
callback-driven WinHTTP HTTPS downloads over a shared connection. Slot zero
performs a two-request 2 MiB + 2 MiB range restart; all other slots fetch the
full 4 MiB range. Every output matches the native reference hash.

The fixture traces request submission, callback queue/consumption, socket
readability, byte receipt, and exact package commit. A loopback overlapped
Winsock/IOCP subtest receives data, posts another receive, observes peer close
as a zero-byte completion, and joins its worker. No HTTP 200 or zero-byte
success is accepted. No Wine source change was needed after the Phase 2/3
ordering and wait fixes.

The accepted run used all FEX TSO options off and Steam wake recovery off.
Exact shutdown and cleanup passed. Evidence is
`docs/validation/no-tso-phase4-final-v5-20260731T040055Z/RESULTS.md`. Phase 5
child-process lifecycle and architecture handoff is active.

### 2026-07-30 — Phase 6 Steam two-cycle handoff notification staged

The native ARM64 ntdll Unix `NtWriteFile` path now has an opt-in, exact-byte
Steam bootstrap marker detector. With `VKMT_STEAM_HANDOFF_NOTIFY=1`, a
successful write containing `Update complete, launching Steam...` sends one
HTTP `POST /steam/handoff` to loopback port 9274 per process. The notification
uses host sockets, never Winsock, and an acquire/release one-shot atomic; it
does not require or enable TSO. `VKMT_STEAM_HANDOFF_PORT` exists only to route
isolated tests away from the production backend.

`tools/steam-handoff-backend` is a dependency-free native ARM64 Rust receiver
bound to `127.0.0.1:9274`. It serializes handoffs, rejects concurrent requests,
accepts exactly two cycles per backend lifetime, shuts down only the Phase 6
prefix wineserver, and relaunches that prefix's installed Steam executable
with all three FEX TSO settings zero. The production binary is
`build/steam-handoff-backend`.

An isolated Windows `NtWriteFile` probe sent the expected HTTP request to a
mock listener on port 19274. The production backend remained at zero accepted
handoffs, proving the test did not consume or execute a real cycle. Both the
repository launcher and its staged LaunchAgent copy export the opt-in flag.
Only `dlls/ntdll/ntdll.so` and the small Rust backend were rebuilt.

### 2026-07-31 — Native media closure and Valve Wine comparison

Every accepted prefix now depends on a verified, relocatable native ARM64
GLib/GObject/GStreamer closure staged at
`wine/build-ec/runtime/gstreamer-arm64`. `scripts/stage-gstreamer-runtime.sh`
recursively closes non-system dylib dependencies, rewrites Homebrew and rpath
references, ad-hoc signs the resulting Mach-O files, stages the required GI
typelibs and plugin scanner, and rejects publication unless a clean full
plugin scan loads `coreelements` with zero stderr. The final stage is 415 MiB,
contains 733 manifest entries, and passes its integrated scan and manifest
verification. GTK3/GTK4 display-only plugins are excluded because loading both
registers duplicate Objective-C classes; Wine supplies its own display path.

`scripts/stage-runtime-providers.sh` makes this closure mandatory and writes
the exact manifest hash to `<prefix>/.vkmt/gstreamer-runtime.sha256`.
`scripts/vkmt-runtime-env.sh`, the Phase 6 launcher, prefix preparation, and
the Steam handoff backend now propagate the staged library, typelib, plugin,
scanner, and per-prefix registry paths. The existing Phase 6 prefix receipt
matches manifest SHA-256
`d87273c176ebddaacb60091daec01737e6a8ae93048273955fb28fb44eccf8e3`.
The currently running backend predates its rebuilt binary and must be
restarted at the next controlled Steam restart before its new media-runtime
environment takes effect.

Valve's Wine fork is pinned for source comparison only at
`third_party/valve-wine`, branch `proton_11.0`, commit
`81d78e4f3ea8ce868d775021fdc9f90122dc1a6b`; provenance is in
`third_party/VALVE_WINE_PIN.md`. Useful patches are to be adapted semantically
to Wine 11.12 and compiled for VKMT's ARM64/ARM64EC and guest PE outputs as
applicable. Version or host-architecture differences are adaptation work, not
rejection criteria. Valve/Proton binaries and Linux-only helpers are not
runtime dependencies.

Valve commit `fadcf28ba2` exposed a generic WinHTTP TLS correctness issue that
was still present locally. Its handshake finalization was adapted in
`dlls/winhttp/net.c` and rebuilt only for the AArch64/ARM64X, x86_64, and i386
PE outputs. Accepted hashes are
`556fe14c13eada20cc04ec3b81590c890c64c86fce0dfd8a2ea126cc7617c955`
(ARM64X),
`06b5bbe50c51c61af60c8ac247e70f43671f152dc66abdc246097646c5b47c48`
(x86_64), and
`a8991ad83e1df27929594cb64446c69c826f36eb5fd2afa348ac0c84c1f0bf15`
(i386). The live prefix still has the older mapped DLLs; stage these new bytes
only after an exact controlled wineserver shutdown.

Steam CEF dump analysis is now reproducible with
`scripts/inspect-minidump.py` and the local native
`build/minidump-tools/bin/minidump-stackwalk`. The repeated browser fatal is an
intentional `int3` at `libcef.dll` RVA `0x691ad97` after nine GPU child exits,
not a null-string assertion. Its call chain and referenced strings resolve to
`gpu_process_host.cc` and `GPU process isn't usable. Goodbye.` CEF also
restarts network-service children with the same outer `0xc0000409` failure, so
SwiftShader/in-process-GPU and the Valve DirectComposition delay remain
diagnostic containment options rather than a root fix. One distinct renderer
dump is a read at address `0xba` in `libcef.dll` RVA `0x392160d`, with a full
unwind through `cef_execute_process`. Evidence and the candidate classification
are in `build/no-tso-phase6/minidump-analysis/RESULTS.md`.

### 2026-07-31 — Steam rendered through the MetalSharp WebHelper contract

Steam now renders its complete sign-in UI in the preserved all-architecture
prefix with every FEX TSO setting disabled. The accepted layout uses
MetalSharp's forwarding `steamwebhelper.exe` beside Steam's original helper as
`steamwebhelper_real.exe`. The wrapper adds `--in-process-gpu --disable-gpu`;
Steam is launched with `-no-cef-sandbox -cef-single-process -noverifyfiles
-no-dwrite`. The decisive flag is `--in-process-gpu`: GPU disable alone still
produced a black window, while the wrapper route rendered in about 28 seconds.

`scripts/launch-steam-metalsharp-compatible.sh` preserves a freshly updated
real helper before redeploying the hash-pinned wrapper, exports the complete
VKMT runtime environment, enforces scalar/vector/memcpy no-TSO, and waits on
the exact prefix wineserver. Evidence is
`docs/validation/steam-render-metalsharp-wrapper-20260731/RESULTS.md`.

The next phase is direct MetalSharp integration: make VKMT's packaged Wine
layout match MetalSharp's runtime discovery contract, then drive its install
wizard, Steam installation, and x86/x64 redistributable installers through
that single authoritative layout. Preserve the working prefix and do not
replace the accepted wrapper contract while implementing that phase.

### 2026-07-31 — strict all-architecture rc=0 acceptance

The Phase 6 architecture fixtures now use conventional success status `0`
for ARM64EC and x86_64, and the runner explicitly disables scalar, vector, and
memcpy/set FEX TSO modes for every Wine invocation. A source-built x86_64
provider regression was isolated to the new ARM64EC callback-frame shortcut:
the CRT `exit()` callback could resume the impossible guest return address
`exit()+5`, overwrite `ContextImpl::SyscallHandler` with that RIP, and enter a
recursive exception storm. ARM64EC callbacks now retain the established
shared-stack contract: guest RET reaches the native continuation through the
EC bitmap and `ExitFunctionEC`. Generated callback and EnterEC boundaries also
reload the authoritative `CpuStateFrame` from Wine's CHPE CPU area.

The current source-built providers are:

- x86_64/ARM64EC: `build/fex-arm64ec-steam-probe/Bin/libarm64ecfex.dll`,
  SHA-256 `317160d7343328a119cfc72a86c0895fe880ee804f9f8ca1a552b89ea736debc`
- i386/WoW64: `build/fex-wow64-java/Bin/libwow64fex.dll`, SHA-256
  `87053cad6be68ff5b8e2cdbeb47da7b8f91702cffa921d6ad8242a64a3c5801d`

Each translated provider passed its focused fixture five consecutive times
with its guest marker present and process status `0`. Those exact bytes are
now the canonical runtime providers and the staging script pins their hashes.
A final fresh, default-configured single prefix at
`build/probe-runs/p6-single-prefix.KGua3y` then passed native ARM64, ARM64EC,
x86_64, and i386/WoW64 with all four exact `rc=0` gates and the final
`P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK` marker, without candidate overrides.
This is the correctness baseline required before performance optimization
resumes.

### 2026-08-01 — persistent Windows FEX cache and strict rc=0 repair

The Windows FEX providers now persist translated code across processes for
both ARM64EC/x86_64 and WoW64/i386 without TSO or Rosetta. The repair moves
relocation ownership out of teardown-dead thread state, saves at normal
`ProcessTerm`, uses checked sequential Win32 I/O and atomic publication, and
loads executable storage with the correct ARM64EC versus ARM64 mapping. Cache
identity is deterministic and includes the complete PE content hash. WoW64
image tracking now keeps host pointers separate from 32-bit guest addresses,
so cache discovery never depends on low-4-GiB host mappings. Runtime cache
loading is independent of the offline compiler, and incomplete `.new` cache
publications are never executable.

Fresh two-pass probes proved save then load for both translated architectures:
x86_64 loaded a 1,041,192-byte cache and i386 loaded a 10,327,160-byte cache.
Truncated 64-byte cache fixtures fell back to live JIT with status 0, published
validated `.repaired` images, and loaded those repaired images on the next
process. Evidence is recorded under `build/perf-p2/` in the `x64-cache-v36-*`,
`i386-cache-v35-*`, `corrupt-*-v38`, and `repaired-*-v38` runs.

The final providers, including rejection of incomplete `.new` files, are:

- ARM64EC/x86_64: SHA-256
  `f0cf686e340a74d46e73549abfadc58aa08d2c7859b42bea2460631ced99c51d`
- ARM64/i386-WoW64: SHA-256
  `c387cc42aeb3dd8857bc1045ed8890b8b1f449f73cc1756cd5be46055f249db3`

The previous cache-capable providers are retained as
`xtajit64-arm64ec-pre-published-only-88b735f3.dll` and
`xtajit-arm64-pre-published-only-895fb779.dll`; the earlier pre-cache providers
remain retained separately. A fresh single prefix using the final exact bytes
passed ARM64, ARM64EC, x86_64, and i386/WoW64 with four conventional status-0
results and `P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK`. Evidence is in
`docs/validation/perf-p2-published-only-all-arch-rc0-20260801/`.
The promoted, default hash-pinned path then repeated the same four status-0
gates without overrides; that final canonical evidence is in
`docs/validation/perf-p2-canonical-all-arch-rc0-20260801/`.

### 2026-08-01 — P1 precise ARM64EC synchronous-exception state

FEX commit `19a09617e` removes the need for single-instruction translation at
synchronous-fault boundaries. The frontend materializes guest EFLAGS only at
instructions capable of side effects, while the ARM64EC JIT publishes exact
guest RIP and RSP. Exception re-entry preserves those values across native
context reconstruction before Wine receives its packed x64 context. This is a
compact boundary commit, not `MaxInst=1`, TSO, or a full per-instruction state
spill.

The post-commit ARM64EC/x86_64 provider is canonical at SHA-256
`4e43c95c64a0c12f8f64c9c5c18d3839ce1345f55c58411a77c657bcbdf6a35b`.
The prior cache-capable provider is preserved as
`xtajit64-arm64ec-pre-precise-f0cf686e.dll`. Five consecutive x64 processes in
one clean prefix validated exact RIP, all 15 GPRs, RSP, EFLAGS, AV metadata,
and continuation through a faulting multiblock with `FEX_MAXINST=5000`.
Evidence is in `docs/validation/perf-p1-postcommit-5x-20260801/`. The same
post-commit bytes passed ARM64, ARM64EC, x86_64, and i386/WoW64 with status 0
in `docs/validation/perf-p1-postcommit-all-arch-rc0-20260801/`.

The broader CEF CDP harness currently times out before its DevTools endpoint
with both the previous canonical provider and the P1 candidate, even with the
persistent translated-code cache disabled. It is therefore not a differential
P1 regression. Both providers reach three Vulkan-backed CEF processes under
normal multiblock execution; the harness must be repaired independently before
it can be used as a browser-rendering performance gate.

### 2026-08-01 — P2 quantitative persistent-code-cache acceptance

FEX commit `db4a8262d` adds opt-in, process-local JIT accounting to both
Windows providers. When a correlated VKMT performance trace is active it
records total and main-image-eligible compile blocks and nanoseconds; the
normal untraced path retains only one predictable disabled branch at a compile
miss. The main-image range is published atomically for multithreaded guests.
Cache-enable trace records now include the exact cache identity and mapped
block count.

`scripts/probe-perf-p2-cache-acceptance.sh` creates one fresh disposable
prefix, forces normal multiblock execution (`FEX_MAXINST=5000`) with scalar,
vector, and memcpy/set TSO all disabled, and runs cold plus three warm
processes for x86_64 and i386. It then corrupts each exact cache header and
requires a successful live-JIT fallback without enabling the corrupt cache.
The accepted post-commit measurements were:

- x86_64: 39 eligible cold blocks to 0 warm blocks, 10,306,800 ns to 0 ns,
  100% coverage and measured eligible-JIT reduction, 90 cached blocks.
- i386: 39 eligible cold blocks to 0 warm blocks, 486,400 ns to 0 ns,
  100% coverage and measured eligible-JIT reduction, 134 cached blocks.

Both exceed the P2 gates of 80% eligible-block coverage and 70% eligible JIT
reduction. Evidence is in
`docs/validation/perf-p2-cache-acceptance-db4a8262-20260801/`.

The exact promoted canonical providers are:

- ARM64EC/x86_64: SHA-256
  `73a00af3ce734a48af43c1be31536bfa40cffc11fe7913353ea8d5d3d0dcfca7`
- ARM64/i386-WoW64: SHA-256
  `a74775b45db0952e2d70657888b445ebc4bdee7fb331b927429c027aed0d76e2`

The prior P1 x86_64 provider and prior i386 provider are retained as
`xtajit64-arm64ec-pre-p2-4e43c95c.dll` and
`xtajit-arm64-pre-p2-c387cc42.dll`. The default staging contract pins the new
hashes. Those default-promoted bytes repeated the precise multiblock exception
gate and the single-prefix ARM64, ARM64EC, x86_64, and i386 status-0 gate. The
same post-commit bytes also passed x64 DXVK D3D11 readback and i386 DXGI,
D3D12, and D3D11 readback with all TSO modes zero. The x64 graphics runner was
repaired to use the current Wine launcher, bounded execution, post-wineboot
provider restaging, and the fixture's actual status-0 contract.

The Windows Java J3 harness currently exits before HotSpot emits output with
the P2 candidate, the P1 canonical provider, and the historical Java-specific
provider alike. This is not a P2 differential regression. Failed-run logs are
now preserved before exact disposable-prefix deletion, and the harness exposes
its software-ordering mode explicitly so the separate final no-TSO Java work
can be completed under P5.

### 2026-08-01 — P5 i386/WoW64 safepoint and teardown acceptance

P5 is accepted for the i386/WoW64 provider. The Windows control-word protocol
now uses ARM acquire/release ordering for JIT ownership, suspension, context
publication, and dirty-state transfer while every FEX TSO mode remains zero.
HotSpot writable-executable subregions are swept individually so embedded-oop
patches cannot escape translation invalidation. Externally supplied WoW64
contexts invalidate superseded call-return continuations, and imported Wine CPU
state is published before JIT re-entry.

The decisive exception-teardown repair pins the JIT code-buffer generation for
every active simulation, including the outermost simulation. Native return
addresses used by Wine's exception/unwind path therefore remain executable
until that simulation exits; the previous freed-code execute fault and
non-progressing `RtlUnwindEx` loop are eliminated. Temporary exception,
same-PC-context, and SMC tracing was removed from the promoted build.

The accepted clean i386 provider is SHA-256
`e8d4c6694b456d9ecaa5d79e7461d6e0981a7080d14f3fe1b74732554a4b12a0`.
Its source boundary is FEX commit `22b3110d0` on the preserved
`phase5-fex-stable` branch.
The last accepted P4 i386 provider remains at
`runtime-providers/xtajit-arm64-pre-p5-ed9eac24.dll` with SHA-256
`ed9eac240a87cebd2bff5b4384105410a00ae0215b08c1a6f43e8b7d77ae7d98`.
The P4 x86_64/ARM64EC provider remains unchanged at SHA-256
`0c5e7b85049d2d078a55e014cdecabe767c765d382ee2f0e6c7a92d2f3149a4f`.

In one fresh disposable prefix, the clean P5 provider passed both OpenJDK 8
i386 modes: C1 compiled 28 fixture methods and Xcomp compiled 23, both emitted
their complete GC, code-cache, executable-memory, deoptimization, and exception
markers, returned status 0, and completed exact wineserver shutdown. Evidence
is in `docs/validation/perf-p5-i386-java-final-20260801/`. Five preceding
instrumented C1 runs also passed; their 2.4-GiB retained diagnostic prefix was
deleted after the compact evidence was extracted.

### 2026-08-01 — x86_64 Java provider repair after P5

The P4 ARM64EC/x86_64 provider remained valid for the single-prefix smoke gate
but could stall before HotSpot emitted its first line. The source-built provider
from FEX commit `22b3110d0` resolves that startup and teardown path without TSO.
Its SHA-256 is
`0dde3c54ff286553b0592d58057e99f9ef4aca0d86436d1c1fa2e38d3fc14330`.
The prior all-architecture baseline remains available as
`runtime-providers/xtajit64-arm64ec-pre-java-fix-0c5e7b85.dll`, SHA-256
`0c5e7b85049d2d078a55e014cdecabe767c765d382ee2f0e6c7a92d2f3149a4f`.

The repaired x86_64 provider first passed tiered and Xcomp alone, then passed a
fresh four-lane Java matrix alongside the accepted P5 i386 provider. The lanes
compiled 34 x86_64 tiered, 125 x86_64 Xcomp, 28 i386 C1, and 23 i386 Xcomp
fixture methods; all emitted their complete execution, GC, code-cache,
deoptimization, and exception markers and completed exact wineserver shutdown.
Evidence is in `docs/validation/perf-p5-java-all-lanes-x64-fix-20260801/`.
That directory contains the final no-override rerun, where candidate and golden
hashes are identical to the promoted canonical providers. After promotion, a
new single-prefix ARM64, ARM64EC, x86_64, and i386/WoW64 matrix also passed all
four conventional status-0 gates and emitted
`P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK`; its logs and status are in
`docs/validation/perf-p5-all-architecture-after-x64-java-fix-20260801/`.

### 2026-08-01 — P6 versioned GPU translation-cache acceptance

P6 is accepted without changing either P5 FEX provider. Prefix initialization
now stages a private, versioned graphics-cache generation and every normal
runtime launch exports the same DXVK, vkd3d-proton, DXMT, MetalSharp/OpenGL,
Metal, and XDG cache roots. Generation schema 2 hashes the complete shipped
graphics binaries and includes the macOS version/build, hardware model, GPU
chipset, and Metal generation. Only two generations are retained; manifest
publication is atomic and incompatible identities are rejected before use.

DXVK commit `398baae` fixes two short-process persistence defects: completed
writer bursts are flushed without waiting for 32 shaders, and the zero-user
cache singleton is actually destroyed so its writer is joined and drained.
The rebuilt i386 D3D11 DLL is the exact artifact exercised by
`scripts/probe-perf-p6-gpu-cache.sh`.

In a fresh disposable no-TSO prefix, deterministic compute DXBC produced one
cold translation and a persisted cache record. The warm run loaded that record
with one cache hit, zero repeat translations, a 100% hit rate, and 100% shader
translation reduction. Warm compute pipeline creation/submission/readback was
43,209,300 ns, below the 100-ms gate, and returned the expected `0x504b3656`
value. A deliberately incompatible manifest was rejected and repaired. The
i386 VKMT DXGI/D3D12/D3D11 ladder then passed, including explicit
vkd3d-proton cache remapping, and the canonical ARM64, ARM64EC, x86_64, and
i386 single-prefix gate passed with four status-0 results. Evidence is in
`docs/validation/perf-p6-gpu-cache-20260801/`.

### 2026-08-01 — P7 executable-memory maintenance acceptance

P7 is accepted without TSO or Rosetta. The WoW64 implementations of
`BTCpuFlushInstructionCache2` and `BTCpuFlushInstructionCacheHeavy` previously
invalidated the identical guest range twice: first through
`InvalidationTracker::InvalidateAlignedInterval`, then again through the
provider's host-to-guest invalidation helper. The common tracker already owns
the canonical host-to-guest conversion, code-buffer invalidation, and every
thread lookup eviction, so the second pass was redundant.

FEX now exposes correlated, opt-in executable-memory metrics for flush
requests/passes/bytes, tracker invalidations/bytes, thread lookup evictions,
RWX write faults, and protection calls. Atomic counter updates occur only when
`VKMT_PERF_RUN_ID` activates tracing. `scripts/probe-perf-p7-executable-memory.sh`
builds and executes the i386 SMC fixture in separate disposable baseline and
candidate prefixes, shuts each wineserver down exactly, retains compact trace
evidence, and removes each prefix even on failure. Two guest flush requests
produced four baseline passes and two candidate passes: an exact 50.00%
reduction, while both executions returned status 0 and observed the rewritten
code.

The promoted i386/WoW64 provider is SHA-256
`e030b4d33909d6158bf1a8521f948a4ddde85da8368e2d605ced301ff14ffee1`.
The accepted P6 provider is retained separately as
`runtime-providers/xtajit-arm64-p6-known-good-e8d4c669.dll`, SHA-256
`e8d4c6694b456d9ecaa5d79e7461d6e0981a7080d14f3fe1b74732554a4b12a0`.
The ARM64EC/x86_64 provider was not changed because its flush boundary already
uses a single tracker pass.

The candidate and then the promoted canonical path passed: i386 SMC; i386 C1
and Xcomp Java JIT/executable-memory fixtures; the complete WoW64 LoadLibrary,
syscall, TLS, context, SEH, APC, callback, and thread-lifecycle contract; 128
x86_64 and 128 i386 child-process launches plus their no-TSO synchronization
and CDN gates; i386 DXGI, D3D11, and D3D12 deterministic readback; and the
single-prefix ARM64, ARM64EC, x86_64, and i386 matrix with four conventional
status-0 results. Compact current evidence is under
`build/evidence/perf-p7/`; the reproducible result summary is in
`docs/validation/perf-p7-executable-memory-20260801/RESULTS.md`.

### 2026-08-01 — P8 measured runtime hot-set acceptance

P8 is accepted. `tools/vkmt-hotset-snapshot.c` is a native ARM64 supervisor
which follows Wine's child-process tree and samples file-backed VM regions and
open vnode descriptors every 50 ms for the first five seconds. This avoids the
root-only `fs_usage` dependency and records resident bytes, mapping offsets,
and real paths without Wine or FEX tracing overhead. The representative
x86_64 and i386 workloads each loaded the same fifteen UI, network, crypto,
audio, DirectX, and OpenGL surfaces; the resulting manifest naturally includes
Winemetal, Wine graphics builtins, FreeType, libpng, GnuTLS, fonts, NLS data,
and the actually mapped core runtime rather than every file in the tree.

`runtime/hotsets/all-arch-default.tsv` contains 222 validated ranges totaling
211,225,570 bytes (201.44 MiB), below the hard 256-MiB quota. Paths are stored
relative to the VKMT runtime or prefix, and every row carries its file size and
mtime identity. `tools/vkmt-hotset-prefetch.c` rejects changed rows and uses
native `F_RDAHEAD` plus asynchronous `F_RDADVISE`; it never concatenates the
runtime in production or retains a second RAM copy. macOS owns clean-page LRU
eviction. The prefix launcher adds a 30-second cooldown and atomic one-request
lock, and `VKMT_HOTSET_PREFETCH=0` disables the feature.

Five independent cold pairs were built with no-cache source reads and
no-cache writes so baseline and candidate used distinct, unwarmed vnodes. The
median 211,225,570-byte results were:

- physical demand-read stall: 266,715,000 ns, **0.791952 GB/s**;
- prefetch request setup: 2,588,000 ns;
- post-prefetch blocking stall: 110,655,000 ns, **1.908866 GB/s** effective;
- total delivery including setup and the explicit 100-ms overlap window:
  **0.990010 GB/s**; and
- blocking physical-read stall reduction: **58.41%**, exceeding the 25% gate.

The GB/s formula is decimal bytes divided by nanoseconds: because one byte per
nanosecond equals one GB/s, `211225570 / 266715000 = 0.791952 GB/s` and
`211225570 / 110655000 = 1.908866 GB/s`. Cached reads had a 10,159,000-ns
median before advice and 10,109,000 ns after it, a `-0.49%` regression
(slightly faster). An intentionally mismatched identity was rejected while
the remaining valid rows continued normally.

Prefix staging now builds and verifies the native ARM64 helper, copies the
manifest atomically, and records its exact hashes and quota in the prefix.
The integrated runtime launch returned status 0. A fresh canonical prefix then
passed ARM64, ARM64EC, x86_64, and i386 with four conventional status-0
results after hot-set staging and receipt verification. Reproducible evidence
is in `docs/validation/perf-p8-hotset-20260801/RESULTS.md`; compact run logs are
under `build/evidence/perf-p8/`.

### 2026-08-01 — 0.60.0 self-contained runtime release published

The authoritative P8-integrated runtime is published as
`v0.60.0-dependency-bundles` in both VKMT and MetalSharp. VKMT is the default
download origin; MetalSharp carries an exact asset mirror for its 0.60.0
dependency contract. Both releases contain the same eleven assets and GitHub
reports identical SHA-256 digests for every asset.

The reconstructed runtime is 3,058,560,880 bytes, contains 45,892 archive
entries, and has SHA-256
`9210991e4249d8dd647fba1bb7e8dcfe808f760c638eeebbf55752f560ad8f0c`.
Its four 764,640,220-byte parts have these ordered hashes:

- `b855ca1a5f6a84e3cbc256dad89c8af12fa8ceb974c2cbf92bef5bc6ceb742dd`;
- `5130129b2747bcceed9384ab2b374dff6a11b00b2db32fc7fd299f313fbab8e8`;
- `2464d5ec890a56407d62c44aa6c4ac788b0c434cc67bcd0865214ab19a2d4ea6`;
- `64a373161f9165da64f0395460df4584943f9ead4a86d37be1bcf22e77bbf81e`.

The runtime includes the complete Wine build and four PE architectures,
canonical x86_64/i386 providers, graphics and Metal stacks, SDL2/SDL3, Java,
Mono, Gecko, GStreamer, GnuTLS, FreeType/fonts, GOG support, all runtime
scripts, public source/licenses, and the compiled/source P8 helper plus its
222-entry manifest. The package audit found 812 Mach-O host files, zero
non-ARM64 host binaries, zero absolute symlinks, and zero non-relocatable load
commands. A release-compatible zstd window is used; no special decoder flag
is required.

Before publication, the release installer performed a full transactional
extraction and verified all 38,920 payload hashes. The extracted Wine launcher,
canonical provider staging, relocated GStreamer closure, P6 versioned graphics
cache, P8 hot-set staging, no-TSO environment, and native ARM64 GOG tool all
passed. The canonical local release set is retained at
`/Volumes/AverySSD/MetalSharp-Wine-Runtime-COMPLETE-release-parts/`.

## 2026-08-03 — AI optimization Phase 0/1 status

The active optimization plan is `docs/AI_OPTIMIZATION_ROADMAP.md` and its
source ledger is `docs/AI_OPTIMIZATION_LEDGER.tsv`. The ledger covers all 82
custom C paths relative to Wine 11.12. The current P8 provider-backed
architecture runner is `scripts/probe-p8-single-prefix-architectures.sh`; use
it for new acceptance receipts. P6 names remain only in historical evidence
and compatibility references, and must not be used to label current P8
provider results.

The Phase 0/1 baseline receipt is
`docs/validation/ai-optimization-p8-phase0-baseline-20260803/`. It passed
ARM64, ARM64EC, x86_64, and i386/WoW64 with all FEX TSO settings zero using
the existing canonical prefix. One narrow pure NTDLL candidate has now been
promoted into `wine/wine-11.12`; any candidate must be built and tested against the
actual installed Wine tree, then staged into the existing prefix only after
the source-level build and P8 gates pass.

The current WoW64/MSync functional promotion is nested Wine commit `656bd43`.
Its targeted build and canonical-prefix receipts are retained in
`docs/validation/ai-optimization-wow64-msync-phase3-20260803/RESULTS.md`.
The nested Wine remote is currently configured to an unavailable local archive
path, so the commit is retained locally while the VKMT root receipt is pushed
to `origin/main`.

The first AI file candidate, a hashed NTDLL builtin-path cache, is explicitly
rejected and is not installed. Its paired control/candidate evidence is
`docs/validation/ai-optimization-candidate-loader-hash-20260803/RESULTS.md`.
Do not promote it without a larger repeatable control and workload-specific
loader measurement.

The complete 82-file candidate preparation is recorded in
`docs/validation/ai-optimization-corpus-20260803/RESULTS.md`. Use
`inventory-all` and `prepare-all` for corpus-wide work; they never mutate
`wine/wine-11.12`.
The current candidate-path disposition matrix is
`docs/AI_OPTIMIZATION_DISPOSITION.tsv`. Treat `CANDIDATE_BLOCKED_*` and
`PROFILED_NO_SAFE_CANDIDATE` as explicit audit outcomes, never as optimization
wins or permission for unsafe rewrites.
`scripts/vkmt-c-ai-optimizer.sh verify` now enforces that every ledger
candidate path has exactly one disposition row with evidence and a next
action.

The FEX and graphics phase receipts are
`docs/validation/ai-optimization-fex-phase4-20260803/RESULTS.md` and
`docs/validation/ai-optimization-graphics-phase5-20260803/RESULTS.md`.
The current P8 hot-set measurement is 61.45% cold stall reduction with 0.15%
warm regression; CEF x86_64 OSR remains status 0. These are acceptance results,
not permission to rewrite FEX or host callback boundaries without a new paired
candidate measurement.

The final P8 one-prefix receipt is
`docs/validation/ai-optimization-final-p8-20260803/RESULTS.md`. Wineboot
update returned rc=0, all four architecture fixtures returned rc=0, and the
WoW64, MSync, CEF x86_64 OSR, and P8 hot-set gates were retained. The final
receipt must continue to distinguish accepted x86_64 CEF from the unresolved
i386 CEF boundary and must identify the single accepted pure NTDLL helper
without claiming that the remaining corpus was optimized.

### 2026-08-03 — AI optimization Phase 2 heap candidate audit

The first Phase 2 candidate receipt is
`docs/validation/ai-optimization-phase2-heap-index-20260803/RESULTS.md`.
It tested an out-of-tree `dlls/ntdll/heap.c` free-list-index candidate using
the actual ARM64 build. Candidate and control `ntdll.so` were byte-identical,
so the candidate was rejected without staging or promotion. The installed
source and runtime hashes matched the pre-file-scan candidate values at that
time, and its canonical prepared-prefix P8 gate passed ARM64, ARM64EC,
x86_64, and i386/WoW64 with status 0. A later file-scan promotion changed
only the accepted NTDLL helper; this does not close the rest of Phase 2,
which continues to require a
distinct, repeatable workload improvement before promoting any other helper.

The x64 Winsock address-list probe also supports verified prepared-prefix
execution via `scripts/probe-x64-address-list-sort.sh --prefix PATH`; it must
not run Wineboot or stage providers in that mode.

### 2026-08-03 — AI optimization Phase 2 file-scan promotion

`dlls/ntdll/unix/file.c::buffer_contains()` was promoted in nested Wine commit
`07df604e8f4e2f475bdd9983905cf98802905ee7`. Its exact-equivalence, benchmark,
ARM64 build, and prepared P8 evidence is
`docs/validation/ai-optimization-phase2-file-scan-20260803/RESULTS.md`.
This is the only accepted narrow source candidate so far; all other
dispositions remain subject to their own workload and semantic gates.
The remaining 12-row audit is
`docs/validation/ai-optimization-candidate-audit-20260803/RESULTS.md`.
If a final Wineboot update is required, run the non-creating prefix refresh
once afterward before prepared gates; do not recreate the canonical prefix.

### 2026-08-03 — AI optimization Phase 4 FEX candidate audit

The FEX interpreter candidate receipt is
`docs/validation/ai-optimization-phase4-fex-mask-20260803/RESULTS.md`.
The `sz_mask()` table candidate passed five direct x86_64 launch/marker checks
but measured 1.54% slower than the matched control and was rejected. The
canonical P8 ARM64EC provider was restored and the all-architecture prepared
prefix gate returned status 0. Do not infer FEX dispatcher or JIT optimization
from this result; those paths remain protected.

### 2026-08-03 — P8 D3DCompiler contract

`test/d3dcompiler_contract.c` and
`scripts/probe-d3dcompiler-contract.sh` are the authoritative D3DCompiler
coverage. The runner reuses the receipt-backed
`build/probe-runs/phase-a-graphics-prefix`; it does not create a prefix or run
Wineboot. It compiles and executes ARM64, ARM64EC, x86_64, and i386 fixtures
with `FEX_TSOENABLED=0`, `FEX_VECTORTSOENABLED=0`, and
`FEX_MEMCPYSETTSOENABLED=0`. The retained P8 receipt and full capability table
are `docs/validation/d3dcompiler-contract-p8-20260803/RESULTS.md` and
`capability.tsv`.

The fixture covers VS/PS/CS compilation, flags/macros, custom include
callbacks, diagnostics, Unicode `D3DCompileFromFile`/`D3DReadFileToBlob`,
preprocess, disassembly, reflection/signatures, and dynamic 43/46/47 exports.
It records `D3DLoadModule` `E_NOTIMPL`, all discovered Wine spec stubs as
`KNOWN_STUB_NOT_CALLED` with `E_NOTIMPL`, and the d3dcompiler_43 reflection
`E_NOINTERFACE` limitation without calling aborting stubs. All four compiler
lanes returned rc=0. i386 DXVK D3D11 compute readback and vkd3d-proton D3D12
compute pipeline also returned rc=0 in separate processes.

The i386 consumer closure is explicitly staged in-place, not through a new
prefix, by `scripts/vkmt-prefix sync-graphics32`. It records the x32 DXVK pair
and win32 vkd3d-proton pair in the prefix manifest and
`.vkmt/graphics32-sync.receipt`; a subsequent `vkmt-prefix verify` must pass.
Do not combine the D3D11 and D3D12 consumer calls in one i386 process: the
current boundary faults after a successful D3D11 pass and is intentionally
kept visible in the receipt.
