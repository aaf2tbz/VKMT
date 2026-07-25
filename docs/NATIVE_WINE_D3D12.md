# Native arm64 Wine — D3D12 probe bring-up (2026-07-25)

Related docs: [EMULATION.md](EMULATION.md) (arm64ec/xtajit PE emulation log).

Status: **PASS.** `D3D12CreateDevice(FL_11_0)` returns `S_OK` on native
arm64-apple-darwin Wine 11.12 via vkd3d-proton → VKMT MoltenVK → Metal.
No Rosetta anywhere in the stack.

Probe output (`test/d3d12_probe_nodxgi.exe`, run recipe in `test/run-vkmt-wine.sh`):

```
D3D12CreateDevice(FL_11_0): 0x00000000
max feature level: 0xb000
ResourceBindingTier: 3  TiledResourcesTier: 0  ConservativeRasterizationTier: 0
RaytracingTier: 0  RenderPassesTier: 0
VariableShadingRateTier: 0
PROBE OK
```

## Bugs found and fixed this session

### 1. New threads started with TEB in x18 (wine, PE-side crash)

`dlls/ntdll/unix/signal_arm64.c::init_syscall_frame` still initialised the
new-thread context with `context.X18 = teb`. With the VKMT pivot, PE keeps
the TEB in x28, so secondary threads (vkd3d worker threads were the first to
hit it) started with a garbage x28 and died in
`RtlInitializeCriticalSection` (`ldr x8, [x28,#0x60]` → wild PEB pointer).
Fixed: set `context.X28 = teb` instead.

### 2. Stock llvm-mingw CRT clobbers x28 (root cause of the d3d12core crash)

Even with thread init fixed, a vkd3d worker thread crashed with
`x28 = sp+0x1d9` garbage. Disassembly scan showed **477 x28-writing sites in
d3d12core.dll**, all inside static mingw-w64 CRT code
(`__mingw_pformat`, gdtoa, …). The stock toolchain CRT is built for the
standard Windows ABI where x28 is free scratch; every printf-family call
destroyed the TEB register.

Fix: rebuilt mingw-w64-crt (arm64 only) and winpthreads with
`-ffixed-x18 -ffixed-x28` and installed them into the llvm-mingw toolchain
(stock archives backed up under `aarch64-w64-mingw32/lib-backup-stock`).
Script: `scripts/rebuild-mingw-crt.sh`. After relinking, d3d12core.dll has
**zero** x28-writing instructions.

Consequences / rules:

- Any PE binary linked before the CRT fix must be **relinked** (no
  recompile needed — the bad code lives in the static archives).
- `scripts/fix-x18-tls.py` must be re-run on **every freshly linked PE
  binary** (LLVM's Windows TLS lowering still hardcodes `[x18,#0x58]`).
  TODO: wire it into the vkd3d/dxvk meson builds as a post-link step.
- compiler-rt builtins (`libclang_rt.builtins-aarch64.a`) are clean; the
  sanitizer/profile runtimes are not (we don't link them).
- DXVK still needs the same treatment for its C++ runtime (libc++/libc++abi
  from llvm-mingw use x28 as scratch) before its dxgi can load.

### 3. (Earlier in bring-up, kept in the patch)

- `winevulkan/vulkan_private.h::conversion_context_alloc` returned
  uninitialised memory; MoltenVK walked garbage `pNext` chains. Fixed with
  memset (permanent).
- vkd3d meta compute shaders `cs_emit_nv_memory_decompression_regions{,_workgroups}.comp`
  did `atomicAdd` on a `uvec3` SSBO member → Metal "address of vector
  element" compile error. Replaced with three scalar uints in
  `third_party/vkd3d-proton` (layout-identical).
- Robustness2 requires the VKMT MoltenVK dylib
  (`DYLD_LIBRARY_PATH=third_party/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS`)
  plus `MVK_CONFIG_ADVERTISE_ROBUST_BUFFER_ACCESS_2=1`; homebrew's stock
  MoltenVK reports robustBufferAccess2=0 and vkd3d refuses to init.

## Debug technique that paid off twice

Get the faulting PC from the crash line, the module load base from
`WINEDEBUG=+loaddll`, then:

```
llvm-addr2line -e <dll> -f -C <ImageBase + (faultPC - loadBase)>
```

(vkd3d/wine PE dlls carry DWARF.) For "which register got clobbered"
questions, `WINEDEBUG=+seh` prints the full dispatch context.

## DXVK dxgi (2026-07-25, second pass)

DXVK's dxgi.dll now works for the D3D12 path:

```
CreateDXGIFactory1: 0x00000000
adapter 0: Apple M4 (VID:106b PID:1b000209)
D3D12CreateDevice(FL_11_0): 0x00000000
PROBE OK
```

Required work:

- **libc++/libc++abi/libunwind rebuilt** from llvm-project at the exact
  clang commit (`ca7933e4`) with `-ffixed-x18 -ffixed-x28` and installed
  into the toolchain — the stock ones clobber x28 like the CRT did.
  `scripts/rebuild-mingw-crt.sh cxx` reproduces it. The remaining 2
  "x28 writes" per archive are balanced unwinder context save/restore.
- **DXVK patches** (`patches/dxvk-vkmt-moltenvk.patch`):
  - `geometryShader`, `shaderCullDistance` no longer required (MoltenVK
    lacks both; only two missing required features on Apple M4).
  - `VK_EXT_depth_clip_enable` no longer required. When absent, D3D
    depth-clip semantics are mapped through Metal's clip mode
    (`depthClampEnable = !depthClipEnable`), which is exact for Metal.
  - meson post-link `fix-x18-tls` custom_target (also added to
    vkd3d-proton's meson.build) so freshly linked PE dlls are patched
    automatically on every ninja run.
- Probe exe must be linked against the fixed CRT too (rebuild with
  `-nostartfiles ... -ld3d12 -ldxgi -ldxguid -lole32`).

## Known remaining issues

- First-boot rpcss ordering + a stray `0x7ffe0324` read (intermittent).
- winedbg itself crashes after attaching on aarch64 PE crashes
  ("Internal crash"); use `+seh` register dumps instead.
- DXVK dxgi unusable until libc++/libc++abi are rebuilt with the fixed
  registers (same recipe as the CRT).
- i386/x86_64 guest support via an emulation boundary (GEM/FEX-style) —
  planned, no Rosetta.

## First-boot & debugger hygiene (2026-07-25, third pass)

- **32-bit launches fail cleanly now.** The syswow64 rundll32 that wineboot
  spawns for wine.inf's Wow64Install used to die on `assert(!status)` in
  `build_wow64_parameters` (the sub-2GB wow64 block can't exist on macOS
  arm64). It now logs a clear ERR and exits. This assert was also the
  "winedbg: Internal crash"/hanging seen on crash handling.
- **`0x7ffe0324` stray read:** already fixed by the earlier KUSD relocation;
  kernel32/kernelbase read `0x1:7ffe0000`. Remaining `0x7ffe` hits in the
  tree are AND-masks or the wow64 debug hack at `ntdll/process.c:739`.
- **RpcSs "failed to open" on first boot** is the upstream services race;
  the service registers during boot and starts on demand afterwards
  (verified `sc start rpcss` → RUNNING). Cosmetic.
- **winedbg --auto hang fixed:** the crash dialog (DialogBoxW via winemac)
  blocked forever in unattended sessions. `ShowCrashDialog=0` is now the
  default in new prefixes (wine.inf.in); --auto prints exception, register
  dump, and a symbolized backtrace to stderr and exits. Interactive winedbg
  (bt, info reg) works; `be_arm64_single_step` is still a stub, and
  `info share` on huge DWARF dlls is slow — use `bt`/`info locals` instead.
- **Caveat learned:** `pkill -9 wineserver` loses unflushed registry
  writes; run `wineserver -w` to flush before killing.
