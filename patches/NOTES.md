# VKMT wine patch series

- `wine-11.12-vkmt.patch` — apply to pristine wine-11.12.tar.xz (`patch -p1 < patches/wine-11.12-vkmt.patch`).
- `wine-11.12-java-j5.patch` — reproducible snapshot of the current Wine
  source delta at J5 acceptance, including the WoW64 guest-memory,
  exception/callback, local-suspend, and non-alertable dynamic-code
  synchronization contracts. Apply with `git apply` to Wine commit
  `fb22a9782ad812d0cf9df9021047eccee84b5135`.
- `fex-2607-java-j5.patch` — reproducible FEX Java/WoW64 delta at J5
  acceptance, including conservative non-TSO lowering, managed guest-address
  translation, synchronous divide faults, context/call-return handling, and
  safepoint code-cache invalidation. Apply with `git apply` to FEX commit
  `a745bebae8c65025869288be1b50275928702338`.
- `fex-2607-no-tso-steam-runtime.patch` — the final software-ordering,
  invalidation, callback, and Steam child-handoff delta committed as
  `18a20dc8d` in the local FEX tree.
- `wine-11.12-no-tso-steam-runtime.patch` — the final Wine WoW64, networking,
  browser, loader, and Winemac cross-process presentation delta committed as
  `03cd2bd` in the local Wine tree.
- `wine-wow64-phase1-f108c09.patch` — the P8 graphics prerequisite delta from
  nested Wine commit `f108c09`. It preserves an explicit guest address while
  falling back from an occupied derived low alias, and retires complete mapped
  reservations after WoW64 interval splitting. Apply after the canonical
  `wine-11.12-vkmt.patch` delta.
- `moltenvk-phase2-665b11e7.patch` — the custom MoltenVK truthfulness delta
  from nested commit `665b11e7`. It removes `VK_EXT_transform_feedback` from
  device advertisement and reports zero transform-feedback limits/features
  until a real capture/counter implementation is available. The direct P8
  behavior receipt records this as an explicit non-advertised capability.
- `vkd3d-proton-phase3-tls.patch` — the P8 vkd3d C TLS delta applied after
  `vkd3d-proton-vkmt-wine-compat.patch`. It replaces the ARM64/ARM64EC
  `__declspec(thread)` paths used by UAV handoff, debug buffers, and address
  binding with process-allocated Win32 TLS while preserving per-thread
  semantics. This is required for the D3D12 CS/UAV gate; do not omit it from
  future provider assembly.
- `wine-11.12-arm64-mono-fusion.patch` — native ARM64 `mscoree` fallback
  plus the same-bitness PE32+ IL-only process/loader/server contract.
  `scripts/build-wine-mono-arm64.sh` applies it and rebuilds only ARM64X
  `mscoree.dll`/`ntdll.dll`, native `ntdll.so`, and `wineserver`.
- `wine-mono-11.2.0-arm64-coree.patch` — ARM64 CoreEE export fixups plus
  Darwin 16-KiB W^X transition for the interpreter P/Invoke trampoline.
  `scripts/build-wine-mono-arm64.sh` applies it to the pinned official
  Wine Mono 11.2.0 source archive.

Also required (not in the patch): the bundled llvm-mingw toolchain header
`aarch64-w64-mingw32/include/winnt.h` has `__mingw_current_teb` moved from x18 to x28
(VKMT keeps the Windows TEB in x28 because the Darwin kernel scrubs x18 on every
kernel->user boundary). All aarch64 PE code is built with `-ffixed-x18 -ffixed-x28`.

The accepted unified build enables
`--enable-archs=aarch64,arm64ec,x86_64,i386`.
