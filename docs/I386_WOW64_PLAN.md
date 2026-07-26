# Native ARM64 i386 / WoW64 program

## Decision

The i386 implementation is a native ARM64 Wine CPU backend named
`xtajit.dll`, using Wine's existing WoW64 CPU-provider ABI.  It is *not* an
embedded FEX or QEMU user-mode process.

FEX targets ARM64 Linux and expects the Linux process, signal, loader, and
syscall environment.  QEMU user mode similarly implements a guest ABI by
forwarding guest syscalls to the host OS and only documents Linux/BSD host
support.  Neither can be placed inside a macOS Wine process and made to
service Windows NT syscalls without replacing the very Wine boundary we need
to preserve.  QEMU is GPL-2.0-or-later, so embedding its TCG implementation
would also impose an unsuitable distribution constraint on the Wine tree.

They remain useful as external instruction-semantics test oracles.  The
shipping implementation must be built from source in this tree and call the
existing Wine WoW64 dispatch interfaces.

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

## M6.0 — i386 execution substrate (hard gate)

Implement a 32-bit **guest virtual-address** layer whose 32-bit values never
depend on the high native ARM64 host addresses used to back them.  Every
conversion at the WoW64 boundary must be explicit and checked.

Work items:

1. Introduce `dlls/xtajit` as an ARM64 CPU-provider DLL, with the full
   `BTCpu*` contract required by `dlls/wow64/syscall.c`.
2. Define guest-address allocation, lookup, protection, unmap, and image-map
   notifications.  Preserve the Windows 32-bit address-space rules without
   casting host pointers to `ULONG`.
3. Route PEB32, TEB32, `WOW32Reserved`, syscall thunks, stack setup, context
   get/set, and exception delivery through that mapping layer.
4. Start with an interpreter that is correct for the Windows/i386 ABI;
   translation/JIT is an optimisation phase after compatibility is proven.
   FEX/QEMU instruction traces may be used only to cross-check semantics.
5. Add independent fixtures: process start/exit, arithmetic and control flow,
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
