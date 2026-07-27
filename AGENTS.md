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
