# Phase 0 preservation inventory

Current active project root: `/Volumes/AverySSD/VKMT`.

## Preserved active inputs and outputs

- `wine/wine-11.12` — active Wine 11.12 source with custom ARM64 / ARM64EC /
  WoW64 changes.
- `wine/build-ec` — active targeted-build tree.  It contains ARM64, x86_64,
  and i386 PE outputs, native ARM64 Unix libraries, and the staged FEX
  `dlls/xtajit/aarch64-windows/xtajit.dll` provider.
- `third_party/{FEX-2607,dxvk,vkd3d-proton,MoltenVK,DXMT-v0.80,dxmt-src-v0.80}`
  — pinned component source/build trees.
- `patches/` and `scripts/` — source patches and repeatable targeted build /
  probe commands.
- `test/` — probe source and PE probes.
- `build/fex-wow64` — current FEX provider build output.
- `toolchains/llvm-mingw-20260616-ucrt-macos-universal` — the active in-tree
  LLVM-mingw cross-toolchain and its custom C++/libunwind runtime inputs.

The current active stage does not contain `winemetal.dll` or `winemetal.so`.
That is a known preservation gap: DXMT sources and build scripts are present,
but its installed runtime must be rebuilt/staged before DXMT can be claimed as
preserved.

## Historical archive classification

`/Volumes/AverySSD/VKMT-archive-recovery/.issue25` consists primarily of July
13 MetalSharp release-runtime copies, disposable prefix snapshots, and logs.
`/Volumes/AverySSD/Arm64WINE-archive-2026-07-13/root/.issue25` contains a
second byte-identical historical runtime set.  A sampled `libLLVM.dylib` from
both `release-runtime` trees had SHA-256
`5eb23789b65618aa23195596307e2086fa6ca392f9caaf82ec5422e98cadec76`.

Neither archive is the active VKMT source/build tree.  Do not remove the
current `VKMT` root.  Archive deletion may proceed only as Phase 0 cleanup,
after checking the active inventory above.

## Cleanup record

On 2026-07-26, the verified obsolete
`VKMT-archive-recovery/.issue25` workspace was removed.  It represented about
93,106,332 KiB of logical directory usage.  APFS reported no snapshots and no
open deleted files, but did not return corresponding physical free space;
therefore logical `du` figures must not be treated as guaranteed reclaimable
space.  No remaining archive or non-VKMT user data has been removed.

The remaining active temporary probe roots and small targeted-build logs were
removed after inspection.  The project now uses exact-prefix cleanup only;
there is no broad Wine-server kill or project-tree deletion in the probes.

At the latest inventory, Wine's `dxgi`, `d3d12`, and `d3d12core` PE modules
exist for ARM64, x86_64, and i386.  The FEX provider, FreeType, MoltenVK, and
the in-tree LLVM-mingw toolchain exist.  This is preservation evidence only,
not a runtime compatibility claim.  The DXMT v0.80 stage was rebuilt on
2026-07-26 from the preserved source using Xcode 27.0 beta's installed Metal
Toolchain.  `winemetal.dll` reports `IMAGE_FILE_MACHINE_ARM64EC` and
`winemetal.so` reports ARM64 Mach-O.  Its runtime probe is still a later
acceptance gate.

DXVK now has staged x86_64 and i386 PE runtimes, and vkd3d-proton has a staged
x86_64 D3D12 runtime. DXMT also has i386 PE modules including
`i386-windows/winemetal.dll`. That i386 PE module is intentionally paired with
the already-staged native ARM64 `aarch64-unix/winemetal.so`; an i386 Mach-O
bridge would violate the ARM64-host/no-Rosetta contract.

The i386 `winemetal.dll` was verified as `COFF-i386`; the paired Unix module
was verified as ARM64 Mach-O. The full `scripts/verify-preservation.sh`
inventory passed after staging these outputs.

## Historical archive salvage

Before any further historical-archive cleanup, the unique tracked Wine edits
and root build metadata from `Arm64WINE-archive-2026-07-13` were copied to
`archive-salvage/Arm64WINE-archive-2026-07-13`.  The retained copy includes a
binary Git diff, the exact modified source files, provenance, and SHA-256
checksums.  Verify it with `shasum -a 256 -c SHA256SUMS` from that directory.

After that verification, the historical archive's `.issue25` subtree was
removed on 2026-07-26.  It contained about 89 GiB of repeated release/prefix
runtime stages and contained no DXMT/Winemetal or FEX/XTajit artifact absent
from active VKMT.  The external volume free space increased from 15 GiB to
103 GiB.  The archive root itself remains for further item-by-item auditing.

The separately named `VKMT-archive-recovery` tree was then verified against
the surviving historical archive: its Wine revision, binary custom-diff hash,
and root metadata hashes were identical. It was removed as a 23 GiB duplicate.
The volume reported 110 GiB free after the removal.

`Arm64WINE_Build` was also audited as an older clean Wine 11.5/Blink workspace.
It contained no DXMT/Winemetal/FEX artifact absent from VKMT; its root build
scripts and provenance were checksummed into `archive-salvage/Arm64WINE_Build`
before the obsolete 10 GiB workspace was removed.
