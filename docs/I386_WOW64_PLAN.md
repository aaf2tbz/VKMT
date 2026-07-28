# Native ARM64 i386 / WoW64 program

## Decision

The i386 implementation is FEX's native ARM64 Windows/WoW64 CPU-provider,
built as `xtajit.dll` and loaded through Wine's existing WoW64 CPU-provider
ABI.  This is not FEX's Linux user-mode executable: the Windows module does
only x86 instruction translation, while Wine continues to perform NT syscall
conversion and Unix-call dispatch.  Consequently every Unix library remains
native ARM64 and no x86 rootfs, i386 Mach-O binary, QEMU process, or Rosetta is
involved.

FEX-2607 is pinned at commit `1cc4b93e7a71c883ec021b71359f136394dc1f3c` and
is built from `third_party/FEX-2607`.  The build uses the project LLVM-mingw
toolchain and reserves `x28`, matching the native ARM64 Wine TEB ABI on
Darwin.  QEMU remains unnecessary and is not part of the shipped stack.

## What already exists

Wine already selects `xtajit.dll` for an i386 process on an ARM64 native
machine (`dlls/wow64/syscall.c`).  That module supplies the `BTCpu*` entry
points used to enter guest code, return to WoW64 for an NT syscall, manage
thread contexts, and report memory-map changes.  The x64 `xtajit64` module is
the model for its build and integration shape.

The current macOS failure is earlier and intentional: `build_wow64_parameters`
requires process data below 4 GiB, but native ARM64 Darwin does not provide a
usable sub-4-GiB mapping.  Merely removing the rejection would truncate host
pointers stored in PEB32/TEB32 structures and corrupt the process.

The restriction is verified on the target host: normal ARM64 processes reserve
the first 4 GiB in `__PAGEZERO`, and `MAP_FIXED` allocations in that range fail
with `ENOMEM`.  Linking a diagnostic binary with a smaller `__PAGEZERO` causes
macOS to terminate it at launch, so this is not a linker flag that Wine can
safely use.  FEX supplies the CPU translation layer but cannot by itself alter
this Darwin virtual-memory contract.

## M6.0 — i386 execution substrate (hard gate)

Implement a 32-bit **guest virtual-address** layer whose 32-bit values never
depend on the high native ARM64 host addresses used to back them.  Every
conversion at the WoW64 boundary must be explicit and checked.

Work items:

1. Build and stage FEX's ARM64 `xtajit.dll`, with the complete `BTCpu*`
   contract required by `dlls/wow64/syscall.c`.
2. Resolve Darwin's unavailable sub-4-GiB host mapping without casting a high
   host pointer to `ULONG`.  This must preserve the Windows guest address
   space, allocation, protection, unmap, and image-map notifications.
3. Route PEB32, TEB32, `WOW32Reserved`, syscall thunks, stack setup, context
   get/set, and exception delivery through that safe address boundary.
4. Add independent fixtures: process start/exit, arithmetic and control flow,
   read/write guest memory, `LoadLibrary`, NT syscall return, TLS, exceptions,
   and a second thread.

**Exit criterion:** a genuine i386 PE runs under the native ARM64 Wine loader,
executes those fixtures, and completes the relevant WoW64 tests without any
host-pointer truncation or low-address host mapping assumption.  No graphics
work starts before this gate passes.

## M6.1 — i386 Vulkan graphics probe

Both vendored projects already include Win32 cross files:

* `third_party/dxvk/build-win32.txt`
* `third_party/vkd3d-proton/build-win32.txt`

Wine also already builds i386 PE `d3d12core.dll` and the associated system
DLLs.  This phase builds the eligible 32-bit PE front ends and verifies their
WoW64 marshalling to the native ARM64 Unix side.  MoltenVK remains native
ARM64; it has no guest-bitness variant.  The gate is therefore the i386
Windows ABI and the Wine Unix-call boundary, not an i386 MoltenVK build.

Acceptance sequence:

1. Verify PE machine type and DLL routing for i386 `dxgi`, `d3d12`, and
   `d3d12core`.
2. Run an i386 D3D12 device/adapter probe.
3. Run a resource/command-list smoke test, then repeat with the eligible DXVK
   D3D9/D3D10/D3D11 PE DLLs.

## M6.2 — i386 DXMT probe

DXMT v0.80 already supplies i386 `d3d10core.dll`, `d3d11.dll`, `dxgi.dll`,
and `winemetal.dll`.  Build those PE DLLs from its pinned source together with
the M5.5 native ARM64 `winemetal.so`; do not build or attempt to load an i386
Unix driver on macOS.

Acceptance sequence:

1. Confirm i386 PE architecture, builtin routing, and ARM64 Unix-driver
   selection.
2. Probe `WMTCopyAllDevices`.
3. Probe `D3D11CreateDevice`, then issue a minimal resource/draw workload.

## M6.3 — source-integrated product build

Move each successful component behind a reproducible source-controlled build
step and staged installation layout: Wine/xtajit, MoltenVK, vkd3d-proton,
DXVK when eligible, and DXMT.  The final distribution may not depend on a
hand-copied DLL directory, `WINEDLLPATH`, or prebuilt runtime archive.

The release gate is a clean checkout, fetch, and rebuild followed by native
ARM64, x64-on-ARM64, and i386 probe runs using only the produced installation.

## Guest-managed boundary implementation plan (2026-07-27)

This plan supersedes any assumption that a 32-bit guest pointer can be used as
an ARM64 Darwin host pointer. FEX remains a native ARM64 Windows CPU provider
(`xtajit.dll`), Wine retains syscall and Unix-call ownership, and all Unix,
Vulkan, MoltenVK, and Metal modules remain native ARM64. QEMU, i386 Mach-O,
and Rosetta are not part of this design.

### 1. Freeze and characterize the existing boundary

Preserve the current FEX and Wine worktree state without reset, cleanup, or
rebuild. Capture one fresh i386 launch with loader resolution, selected host
arena, guest-to-host conversions, `BTCpu*` entry/return, and first failure.
Record exact revisions, staged PE/Mach-O architectures, prefix lifecycle, and
the first failing boundary. This phase does not change runtime behavior.

### 2. Canonical guest-address manager

Introduce one Wine-owned conversion layer for i386 guest virtual addresses.
Guest addresses are always `uint32_t`; host mappings may be arbitrary native
ARM64 addresses. Only named checked helpers may convert between them. The
manager owns reserve/commit, images, protection, unmap, PEB32/TEB32, stacks,
and KUSER mappings. A high contiguous arena may be used as a fast path but
cannot be a correctness requirement.

#### 2026-07-27 implementation checkpoint

`dlls/wow64/memory.c` is the sole i386 guest-address conversion layer. It
uses checked, registered guest-range to host-range mappings and gives explicit
non-contiguous mappings precedence over the existing Darwin high-arena
compatibility aperture. The syscall, VM, process, security, synchronization,
and system wrappers now use named conversions rather than truncating host
pointers.

The manager registers the bootstrap TEB32, PEB32, process parameters, guest
stack, and KUSER data, and the VM wrappers register allocation and section-map
results, retain mappings across protect/commit, and remove them only after
successful release/unmap. With `WINEDEBUG=+wow`, its in-process fixture uses
independent guest ranges for native host mappings above 4 GiB and validates
allocate, guest-to-host and host-to-guest conversion, protect, free, map, and
unmap. The trace on 2026-07-27 reached:

```
i386 guest memory selftest passed: allocate/map/protect/unmap above 4GiB
```

This proves the Wine-side VM contract. The subsequent FEX page-map/TLB work
remains Phase 3: it must consume these registered mappings rather than assume
a linear aperture for generated guest memory accesses.

### 1.5. Close the CPU-provider import contract

Before invoking guest execution, enumerate `xtajit.dll` imports against Wine's
native ARM64 PE exports and implement or deliberately remove every unresolved
provider import. The first recorded gap is `ntdll.RtlWow64SuspendThread`, used
by FEX for non-self thread suspension. This is an ABI gate, not a reason to
weaken address conversion or bypass thread safety. Re-run the Phase 1 launch
with an explicit `BTCpuSimulate` entry/return record after the import surface
is closed.

### 3. FEX provider contract

Make FEX retain EIP, ESP, GPRs, contexts, callbacks, and return addresses as
guest values. Instruction fetch and generated memory accesses resolve through
the manager's page map/TLB. Wire every Wine memory notification to FEX cache
invalidation and mapping state. Complete context, syscall/Unix-call, TLS,
exception, APC, and thread-lifecycle behavior; first focused regression is
`RtlEnterCriticalSection` plus subsequent locked operations.

### 4. Non-graphics i386 substrate gate

In a fresh disposable prefix, prove wineboot and clean server exit, then
process start/exit, arithmetic/control flow, memory lifecycle, imports,
syscall return, TLS, exceptions, APCs, and a second thread. Every fixture must
assert that guest pointers remain 32-bit and no raw host-pointer truncation is
used.

#### 2026-07-27 completion result

Phase 4.1 through 4.8 are complete. The unified fixture and runner are
`test/i386/phase4_contract.c`, `test/i386/phase4_helper.c`, and
`scripts/probe-i386-wow64-phase4.sh`. One fresh prefix passed native ARM64
`wineboot --init`, DLL loading,
syscall return/output pointers, executable/DLL/dynamic TLS, suspended i386
context get/set, software and hardware SEH with resume, two ordered APCs,
second-thread state isolation, a real headless Wine user callback, eight
thread-lifecycle cycles, and the Phase 3 guest-memory regression.

The callback gate uses `WH_MSGFILTER` plus `CallMsgFilter`: ARM64 `win32u`
enters `KeUserModeCallback`, ARM64 `wow64win` marshals the hook frame, i386
`user32` calls the application hook, and `NtCallbackReturn` restores the
native frame. It does not create a window or initialize a display driver.

The same acceptance session re-proved the unified ARM64/AArch64/ARM64EC gate
and the separate x86_64 DXVK deterministic readback gate. Evidence is in
`docs/validation/phase4-wow64-system-contract-20260727/RESULTS.md`; the focused
Wine change is commit `d43a990`.

This closes the non-graphics system contract only. Remaining i386 GDI/D3DKMT
data-pointer marshalling is owned by the following graphics phase and must not
be inferred from these results.

### 5. Graphics gates after substrate success

Validate VKMT and DXMT separately. VKMT is i386 PE DXVK/vkd3d-proton through
native ARM64 Wine Unix libraries and MoltenVK; DXMT is i386 PE frontends and
`winemetal.dll` through the paired ARM64 `winemetal.so`. For each route use
load/export, factory/adapter, device, queue/resource, and deterministic
readback gates. Never mix the DXVK and DXMT D3D11/DXGI pairs.

#### Phase 5 execution plan — i386 VKMT (complete 2026-07-28)

Phase 5 is accepted. The final fresh-prefix runner produced all five required
markers after rebuilding the selected i386 DXVK and vkd3d-proton DLLs with
the in-tree LLVM-MinGW 22.1.8 toolchain. Wine `97ff7730`, FEX `baaca8565`,
DXVK `ab0f99ac`, and vkd3d-proton `3300fe64` are the accepted revisions.
Detailed evidence and architecture hashes are in
`docs/validation/phase5-i386-vkmt-20260727/RESULTS.md`.

The retained `p5-i386-vkmt.NDwg2k` diagnostic root was disposed after final
acceptance. `scripts/probe-p5-i386-vkmt.sh` now always creates one fresh
external-SSD prefix, stops its exact wineserver, and removes that run root
unless explicit diagnostic retention is requested.

**Accepted scope and fixed inputs.** The Windows front ends are i386 PEs;
every Unix library and every host executable is ARM64 Mach-O. On any future
failure, stop that prefix with its exact `wineserver -k` then `-w`, dispose
that exact run root, and only then start a fresh run.

```
i386 dxgi.dll / d3d11.dll (DXVK)       i386 d3d12.dll / d3d12core.dll (vkd3d-proton)
                  |                                      |
                  +----------- i386 winevulkan.dll -------+
                                      |
                        ARM64 winevulkan.so / ntdll.so
                                      |
                       pinned ARM64 MoltenVK → Apple Metal
```

The authoritative inputs are `third_party/dxvk/runtime/dxvk-vkmt-1a5919b/x32`,
`third_party/vkd3d-proton/install-win32/bin`, `wine/build-ec`, and the pinned
MoltenVK dynamic library.  Before any runtime gate, record `llvm-readobj`
machine type `IMAGE_FILE_MACHINE_I386` for every PE and `lipo -archs` value
`arm64` for `wine`, `wineserver`, `ntdll.so`, `winevulkan.so`, and MoltenVK.

**5.1 — close the i386 Winevulkan ABI boundary.** The current first failure
was a raw i386 guest pointer passed to the ARM64 `winevulkan.so` in
`wow64_init_vulkan`.  The generated `vulkan_thunks.c` must use the named
guest-to-host and host-to-guest conversion helpers for data pointers; the only
remaining direct 32-bit casts may be documented `PFN_*` guest callback
pointers.  Build only `ntdll.so`, `wow64.dll`, `winevulkan.so`, and the i386
`winevulkan.dll`; stage only those two PEs into the retained prefix.  The
focused `i386_vkmt_dxgi_probe.exe` must create a Vulkan instance and enumerate
the Apple M4 in the DXVK log without a guest-address fault.  This gate does
not require a DXGI factory yet.  On a pointer fault, stop here and repair the
Winevulkan/NTDLL conversion owner; do not change DXVK features or FEX.

**5.2 — accept DXGI factory and adapter enumeration.** Rebuild the x32 DXVK
PEs from the pinned source, stage only `dxgi.dll` and `d3d11.dll`, and run
`test/i386_vkmt_dxgi_probe.c` in the retained prefix.  Its required output is
`P5_I386_DXGI_FACTORY_OK`, followed by `P5_I386_DXGI_ADAPTER_OK`; the log must
identify the Apple M4 adapter.  The present failure after Vulkan enumeration
is DXVK's x32 `geometryShader` eligibility check, so the immediate work item
is to validate the freshly built x32 DLLs containing the MoltenVK portability
feature policy.  If factory creation fails before the DXVK device list, own it
in Winevulkan/ABI; if DXVK sees the device but rejects a required feature, own
it in DXVK; if it lists no Vulkan device, own it in ICD/MoltenVK setup.  Do
not advance to D3D12 until both markers are produced by one run.

**5.3 — accept the i386 D3D12 device boundary.** With 5.2 still staged,
stage only vkd3d-proton's pinned i386 `d3d12.dll` and `d3d12core.dll` and run
the i386 build of `test/d3d12_probe_nodxgi.c`.  Require a successful
`D3D12CreateDevice`, a vkd3d-proton log naming the native Vulkan device, and
MoltenVK evidence of `VkDevice` creation.  Keep DXVK out of this probe: it is
not a DXGI acceptance test.  A failure before the PE exports is routing; from
PE entry through Unix call is a WoW64 ABI failure; after Vulkan feature query
is a vkd3d-proton/MoltenVK capability failure.

**5.4 — accept deterministic i386 D3D12 execution.** Reuse exactly the
5.3 route and fixture, which performs upload → default buffer → explicit
COPY_DEST-to-COPY_SOURCE barrier → direct-queue execute → fence wait →
readback.  Require the fixture's `PROBE OK` and the exact CPU value
`0x4b4d5456`; record command submission and `VkDevice` evidence.  The result
must be deterministic on two consecutive invocations in the same prefix.
If it fails, classify the first missing step as command marshalling, resource
state/barrier, queue/fence synchronization, or readback mapping before making
another source change.

**5.5 — accept i386 D3D11/DXVK execution.** Use only the matching x32 DXVK
`dxgi.dll` and `d3d11.dll` from 5.2, never a DXMT DLL.  Run the i386 build of
`test/d3d11_probe.c`; require `VKMT_D3D11_PROBE_OK`, DXVK's adapter/device
record, and MoltenVK `VkDevice` evidence.  The fixture must cover device
creation plus clear/copy/readback.  If it fails after D3D12 passed, treat it
as a DXVK D3D11 path issue, not evidence to reopen vkd3d-proton or FEX.

**5.6 — reproduce, package, and preserve.** Dispose the retained diagnostic
prefix only after its focused boundary has either passed or been fully
captured.  Then run `scripts/probe-p5-i386-vkmt.sh` once from a new disposable
root with the exact same staged inputs; it must print all five final markers:
`P5_I386_DLL_LOAD_OK`, `P5_I386_DXGI_FACTORY_ADAPTER_OK`,
`P5_I386_D3D12_DEVICE_QUEUE_FENCE_COPY_READBACK_OK`,
`P5_I386_D3D11_DEVICE_CLEAR_COPY_READBACK_OK`, and `P5_I386_VKMT_OK`.
Archive concise logs and architecture evidence under `docs/validation/`,
make source-controlled targeted build/stage rules reproduce the selected
artifacts, update `AGENTS.md`, and commit only after that clean run.  A
passing retained diagnostic run alone is not a Phase 5 acceptance result.

#### Phase 6 — i386 DXMT (begins only after Phase 5.6)

Stage the pinned DXMT 0.80 i386 `dxgi.dll`, `d3d11.dll`, and
`winemetal.dll` with the already-native ARM64 `winemetal.so` and its relative
`libunwind.1.dylib`.  First prove DLL routing and `WMTCopyAllDevices`, then
`D3D11CreateDevice`, then a separate minimal clear/copy/readback probe.  The
DXMT D3D11/DXGI pair never shares a prefix-stage test with DXVK's pair.  The
host must load the ARM64 `winemetal.so`; an i386 Mach-O bridge is invalid and
is a hard failure.

#### Phase 7 — final multi-architecture acceptance and release integration

Run the maintained fresh-prefix probes in this order: pure ARM64/AArch64,
ARM64EC, x86_64 through `xtajit64`, i386/WoW64 non-graphics contract, i386
VKMT, then i386 DXMT.  Each run must use only source-built/staged artifacts,
native ARM64 host binaries, the pinned MoltenVK ICD, an exact wineserver
shutdown, and disposable external-SSD storage.  The final audit records
`lipo`/`llvm-readobj` output, loaded Unix bridge paths, no Rosetta process,
and no hand-copied dependency outside the staged tree.

### 6. Product integration

Put every proven source change behind targeted build/stage rules, preserve
architecture/routing checks and exact-prefix cleanup in probes, update this
document and `AGENTS.md`, and commit only validated focused changes. Do not
perform a full Wine rebuild unless generated configuration genuinely requires
it.
