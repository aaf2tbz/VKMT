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
