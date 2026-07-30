# VKMT

VKMT is a source-integrated, Apple-Silicon-native Wine distribution built to
run ARM64, ARM64EC, x86_64, and i386/WoW64 Windows software together on macOS
without Rosetta.

It is not only a graphics wrapper. The project combines a heavily customized
Wine 11.12, ARM64EC/ARM64X support, native ARM64 x86 translators, a canonical
i386 guest-memory manager, Direct3D and OpenGL translation to Metal, MSync,
multimedia and controller runtimes, browser engines, installers, Wine Mono,
and native plus Windows Java runtimes. The source, patches, build scripts,
runtime providers, probes, and release-snapshot tooling are retained in-tree.

## Current status

The golden single-prefix gate passes all four execution modes in one prefix
and one wineserver lifetime:

| Windows mode | Execution route | Accepted baseline |
| --- | --- | --- |
| ARM64 / AArch64 | Native PE code on ARM64 Wine | Prefix creation, wineboot, loader/runtime, Vulkan, DXVK/vkd3d-proton graphics |
| ARM64EC | ARM64EC/ARM64X hybrid PE surface | Loader, CHPE redirection, DXMT bridge, architecture and runtime probes |
| x86_64 | Custom ARM64EC `xtajit64.dll` provider | CPU execution, threads/TLS, DXVK D3D11, vkd3d-proton D3D12, managed and Java workloads |
| i386 / WoW64 | FEX-derived native ARM64 `xtajit.dll` provider | CPU, memory, syscall, callback, exception and thread contracts; DXVK/vkd3d-proton graphics; browser and Java workloads |

The required aggregate marker is:

```text
P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
```

All host executables, Unix libraries, graphics bridges, and CPU providers are
ARM64 Mach-O or ARM64/ARM64EC PE as appropriate. x86_64 and i386 exist only as
Windows guest architectures. VKMT does not use Rosetta or ship an x86 Mach-O
bridge.

## What VKMT contains

### Custom Wine 11.12

VKMT maintains a targeted Wine 11.12 source and build tree with:

- native macOS ARM64 Wine and wineserver;
- AArch64, ARM64EC/ARM64X, x86_64, and i386 PE module stages;
- ARM64X image classification and CHPE metadata handling;
- ARM64EC import redirection from x64 export thunks to paired native ARM64
  implementations;
- an x28-based Wine TEB contract and post-link repair/audit tooling for code
  that would otherwise use Darwin's reserved x18 register;
- Darwin 16-KiB host-page-aware W^X and managed-runtime protection handling;
- focused headless win32u/GDI/font bootstrap for direct graphics clients;
- source-built FreeType, fontconfig fallback safety, GStreamer, GnuTLS, SDL,
  and related host closures;
- exact per-prefix wineserver shutdown and disposable-prefix cleanup;
- targeted component rebuilds so normal development does not require
  rebuilding all of Wine.

The build is configured with the normal Wine server/Unix provider boundary on
native ARM64. Guest PE architecture does not imply a same-architecture macOS
library.

### x86_64 execution on ARM64

`xtajit64.dll` is VKMT's ARM64EC x86_64 CPU provider. Its implementation
includes:

- x86_64 entry/exit simulation and Windows calling-convention transitions;
- integer, branch, stack, memory, locked-operation, SSE and packed-integer
  execution needed by accepted applications;
- thread creation, TLS, waits and exception/unwind transitions;
- a native ARM64 block cache with linked fallthrough blocks;
- hot-block lowering to ARM64;
- guest code-page tracking and invalidation for self-modifying/JIT code;
- ARM64EC feature publication and LSE compatibility;
- an optional tier-0 control used by scoped Java diagnostics.

The accepted x86_64 baseline includes ordinary PE execution, D3D11
clear/copy/readback through DXVK, D3D12 queue/fence/copy/readback through
vkd3d-proton, Wine Mono, the Temurin Server VM, CEF subprocesses, WebView2
bootstrap, and the Electron x64 fixture.

### i386/WoW64 execution with FEX

The i386 provider is derived from FEX but integrated as a Wine-owned,
source-built ARM64 WoW64 CPU provider. The custom boundary includes:

- a canonical 32-bit guest-VA to ARM64 host-pointer manager;
- guest-addressed EIP, ESP, registers, segment bases, callback frames and
  return addresses;
- page-table publication for high host mappings without requiring a native
  low-4-GiB mapping;
- allocation, map, protection, dirty-write, free and unmap notifications;
- guest-keyed JIT invalidation for executable and self-modifying code;
- PE32 process startup, PEB32/TEB32, stacks and process parameters;
- syscall and Unix-call pointer conversion;
- context get/set, software and hardware SEH, `NtContinueEx`, APC delivery,
  callbacks and repeated thread lifecycle;
- recursive USER-lock release/restoration around nested message, hook,
  window-call and accessibility callbacks;
- WoW64 nested-pointer repairs for USER, OpenGL, Vulkan, CoreAudio and process
  attributes;
- DOS compatibility reservation that preserves the conventional `0x400000`
  image base for relocation-stripped installers.

The non-graphics Phase 4 gate passes `LoadLibrary`, syscall return/output
pointers, TLS, context transfers, structured exception handling, ordered
APCs, a second thread, a real Wine user callback, repeated thread creation,
and exact shutdown in one clean prefix.

### Software x86 memory ordering

VKMT does not depend on Apple's optional hardware TSO mode. The FEX Java path
keeps x86's TSO semantics while lowering them conservatively to ordinary ARM64:

- aligned loads/stores use `LDAR`/`STLR`;
- unaligned loads use `LDR` plus `DMB ISHLD`;
- unaligned stores use `DMB ISH` plus `STR`;
- locked read/modify/write paths use acquire/release atomics such as `CASAL`;
- NZCV is preserved across alignment selection;
- generated code is finalized before RX publication instead of backpatching
  Darwin executable pages;
- `LDAPR`/`LDAPUR` are excluded from the conservative Java baseline.

The same subsystem tracks HotSpot-patched C1 code, converts host code
addresses back to canonical i386 guest VAs, invalidates writable code-cache
ranges, and synchronizes them at safe non-alertable wait boundaries.

## Graphics and Metal translation

### Vulkan and MoltenVK

VKMT pins MoltenVK 1.4.2 and extends its exposed Vulkan feature contract for
the Direct3D translators. The native smoke probe creates a Vulkan 1.3
instance, selects the Apple M4, and passes every vkd3d-proton hard requirement
used by this runtime:

- `robustBufferAccess2`
- `robustImageAccess2`
- `nullDescriptor`
- transform-feedback queries
- buffer device address
- mirror-clamp-to-edge
- dynamic rendering
- synchronization2
- maintenance4

VKMT explicitly enables Vulkan portability enumeration and pins the MoltenVK
ICD used by every accepted graphics probe.

### Direct3D 12 through vkd3d-proton

The D3D12 route is:

```text
D3D12 application
  -> vkd3d-proton 3.1.0
  -> Vulkan loader
  -> patched MoltenVK 1.4.2
  -> Metal
```

Custom vkd3d-proton work includes:

- ARM64, ARM64EC/x64 and i386 cross-build and staging;
- compiling NV DirectStorage meta shaders only when the corresponding
  Vulkan extension is enabled;
- avoiding optional address-binding tracker TLS when MoltenVK does not expose
  that reporting extension;
- ABI-specific PE routing while keeping all host Vulkan libraries ARM64.

Accepted D3D12 gates include device creation, direct command queues, resource
creation, state transitions, upload/default/readback copies, fence signaling,
CPU synchronization and deterministic readback for native AArch64,
ARM64EC/x86_64, and i386/WoW64 routes.

### Direct3D 11 and DXGI through DXVK

VKMT pins DXVK 3.0.2 and maintains AArch64, ARM64EC-compatible, x86_64-routed
and i386 PE builds. MoltenVK-incompatible optional features—geometry shaders,
cull distance and depth-clip enable—do not block device admission when an
application does not use them.

Accepted DXVK gates include:

- DXGI factory creation and Apple M4 adapter enumeration;
- D3D11 device creation;
- offscreen clears;
- resource copies;
- deterministic CPU readback;
- architecture-correct `dxgi.dll`/`d3d11.dll` selection;
- i386 object/handle translation through native ARM64 Wine and MoltenVK.

The pure-AArch64 DXVK pair is distinct from the ARM64EC pair. The separate
DXMT pair must never be mixed with DXVK DLLs.

### Direct3D 9

DXVK D3D9 loading is accepted for ARM64, ARM64EC, x86_64, and i386/WoW64 in a
fresh prefix. The gate covers:

- `LoadLibrary`;
- `Direct3DCreate9`;
- adapter enumeration;
- display-independent `GetDeviceCaps`;
- Apple M4 selection;
- routing through MoltenVK.

This is a loading, adapter and capability result. D3D9 device rendering and
presentation are not claimed by that gate.

### DXMT 0.80 and Winemetal

VKMT also carries the independent DXMT 0.80 D3D11/DXGI stack:

```text
ARM64EC DXGI/D3D11/winemetal.dll
  -> native ARM64 winemetal.so
  -> Metal
```

The DXMT integration provides:

- pinned DXMT source and submodules;
- ARM64EC PE thunks paired with a native ARM64 Unix driver;
- i386 PE staging paired with the same native ARM64 host bridge;
- relocatable ARM64 `libunwind.1.dylib` beside `winemetal.so`;
- focused Wine builtin integration with SHA-256-verified stock DLL backups
  and an exact restore mode;
- `WMTCopyAllDevices`, native bridge loading, executable DXGI imports and
  factory creation/release gates.

There is deliberately no i386 Mach-O `winemetal.so`. i386 is a Windows guest
ABI; the host bridge remains ARM64.

DXMT adapter/device/render/readback coverage is narrower than the accepted
DXVK D3D11 path and should not be inferred from simple DLL presence.

### OpenGL 1.x–4.x to Metal

Wine's multi-architecture `opengl32.dll` path is integrated with a native
ARM64 MetalSharp sidecar containing pinned glslang and SPIRV-Cross.

The compatibility gate passes on all four guest architectures:

- `opengl32.dll` and WGL loading;
- pixel-format and context creation;
- Apple M4 / Metal renderer identity;
- offscreen RGBA8 framebuffer creation;
- deterministic clear/readback;
- GLSL 1.20 compile/link/draw.

The opt-in modern path adds:

```text
GLSL 3.30 / 4.50
  -> glslang
  -> SPIR-V
  -> SPIRV-Cross
  -> Metal Shading Language
  -> Metal pipeline and draw
  -> aligned staging-buffer readback
```

GLSL 3.30 and 4.50 fullscreen-triangle draw/readback pass on ARM64, ARM64EC,
x86_64, and i386 in one prefix. Wine routes the translated
`glReadPixels` call back to the sidecar's Metal target.

This is not a claim of full OpenGL 4.x conformance. Indexed Metal drawing,
general vertex layouts, complete uniform/texture mapping, general FBO
integration, visible presentation and the wider GL3/4 state surface remain
outside the accepted gate.

## Synchronization

VKMT incorporates CodeWeavers' modern Mach-semaphore MSync design, adapted
from CrossOver 26.3.0's Wine 11 source to this Wine 11.12 synchronization
contract.

MSync is toggleable:

```sh
WINEMSYNC=1 wine program.exe
```

Unset or `WINEMSYNC=0` retains wineserver synchronization. Changing modes
requires exact shutdown of that prefix's wineserver.

The MSync suite covers events, semaphores, mutexes, wait-all,
signal-and-wait, APCs, second threads, abandonment and cross-process named
events. The complete four-architecture single-prefix baseline also passes
with MSync enabled.

## SDL, input and controllers

VKMT source-builds and stages:

- SDL2 2.32.10;
- SDL3 3.4.10;
- AArch64, ARM64EC, x86_64 and i386 PE variants;
- an ARM64 Wine `winebus.so` SDL provider;
- a pinned relocatable ARM64 `libSDL2-2.0.0.dylib`.

The SDL gate covers version reporting, dummy audio/video initialization,
hidden windows, software-surface clear/readback, events, a second thread,
dynamic DLL loading and clean shutdown for all four guest modes. The i386
build disables SIMD/vectorization that would introduce unsupported
non-temporal vector stores.

Controller support includes all six XInput DLL families, DirectInput and
DirectInput8. A physical PS5 DualSense passed:

- normalized XInput state;
- live axis activity;
- force-feedback capability reporting;
- nonzero vibration calls;
- DirectInput controller enumeration;
- keyboard and mouse enumeration;
- every guest architecture.

The accepted route disables duplicate raw HID exposure so the same controller
is not presented twice through SDL and IOHID.

## Audio, media and Windows runtime libraries

The preserved build contains architecture-appropriate modules and runtime
assets for:

- XAudio2, XACT and FAudio;
- XNA/FNA compatibility assets;
- D3DCompiler;
- UCRT, Visual C++ and ATL runtimes;
- MSXML;
- Quartz;
- Media Foundation;
- MIDI;
- WineGStreamer;
- Windows codecs.

Legacy D3DX9/10/11 payloads are intentionally excluded. MFC, OpenAL, PhysX
and extra core-font payloads are outside the completed scope.

## Networking and TLS

Wine is built with GnuTLS and VKMT stages a relocatable, signed, native ARM64
closure rather than depending on Homebrew at runtime. The closure includes
GnuTLS and its required nettle, GMP, p11-kit, gettext and IDN dependencies
with `@loader_path`-relative linkage.

Accepted native-provider routes include:

- Schannel;
- WinHTTP;
- WinINet;
- HTTPS and local deterministic TLS fixtures;
- Gecko/MSHTML HTTPS prerequisites;
- Java TLS 1.2.

The TLS provider boundary is native ARM64 even when the calling PE is x86_64
or i386.

## Browser and embedded web runtimes

### Gecko and MSHTML

Wine Gecko 2.47.4 is staged for both registry views. Fresh x86_64 and i386
prefixes pass:

- Gecko-backed MSHTML document creation;
- JavaScript execution;
- DOM access;
- event delivery;
- HTTPS navigation;
- required i386 time, socket, DNS and TLS prerequisites.

Provider hashes are checked before wineboot, in the canonical build stage and
again in the new prefix so wineboot cannot silently restore a stale
`xtajit.dll`.

### Chromium Embedded Framework

Pinned CEF 109 x86_64 and i386 runtimes pass:

- `libcef.dll` export loading;
- browser subprocess creation;
- renderer subprocess creation;
- GPU subprocess creation;
- utility subprocess creation;
- MetalSharp compatibility wrapper and child hook;
- exact process and wineserver cleanup.

This accepted boundary is subprocess/runtime compatibility. Automated CEF
offscreen pixel, input, audio and HTTPS evidence is not represented by the
committed final gate.

### WebView2

The pinned WebView2 fixed runtime 149 x64 lane reaches:

- environment creation;
- controller creation;
- host HTTPS;
- renderer, utility and GPU startup;
- `ExecuteScript` dispatch.

The callback does not yet return in the committed gate, so this is a fixed
runtime bootstrap result rather than a complete WebView2 input/audio/pixel
acceptance.

### Electron

Electron 42.7.1 x64 passes:

- main, renderer, GPU and utility process creation;
- deterministic HTTPS;
- renderer input;
- `OfflineAudioContext`;
- RGBA pixel readback;
- clean teardown.

Electron ia32 reaches image and V8 initialization but is not accepted for a
complete renderer lifecycle. A guest-null reservation experiment that moved
that boundary was reverted because it weakened the golden i386 baseline.

## Installers and deployment formats

### MSI and WiX

The all-architecture MSI lifecycle gate covers installation, installed
payload execution, repair/reinstall, uninstall and registry/file cleanup.
Native ARM64 `msiexec`/`msidb` fixtures exercise extended MSI tables and WiX
generated packages.

### NSIS

The real i386 NSIS gate builds a relocation-stripped installer and proves:

- silent install;
- installed i386 payload execution;
- uninstall-section execution;
- registry cleanup;
- exact disposal of the remaining in-place uninstaller and prefix.

The WoW64 DOS-memory reservation preserves the fixture's conventional
`0x400000` preferred image base.

### Inno Setup

VKMT includes:

- native ARM64 `innoextract` with a signed, relocatable dependency closure;
- real i386 Inno Setup 6.3.3 `ISCC.exe` execution under WoW64;
- deterministic fixture compilation;
- native extraction with byte-for-byte payload validation;
- a pinned Inno 6.5.4 classification input.

A full Inno GUI setup lifecycle is not claimed.

### Installer classification

The read-only classifier recognizes MSI/WiX, NSIS, Inno, Burn,
InstallShield, Squirrel, ClickOnce, MSIX and AppX families. Unsupported
diagnostic-only families fail before creating a prefix when runnable support
is required.

## Managed runtimes

### Wine Mono 11.2.0

Official Wine Mono 11.2.0 is the only Mono payload. VKMT combines the official
x86/x86_64 engines with a targeted source-built ARM64 CoreEE and W^X path.

Accepted managed modes are:

- direct i386 CLR startup;
- native ARM64 CLR startup;
- x86_64 PE32+ IL-only startup through the native ARM64 CLR contract.

The gate covers managed compilation, pointer width, threads, reflection, XML,
kernel32 P/Invoke, exact shutdown and cleanup. Same-bitness PE32+ IL-only
images are identified before stack creation and provider startup, while
native-code x86_64 images continue through `xtajit64.dll`.

## Java runtimes

### Native ARM64 Java

VKMT stages the private Oracle JRE 8u501 ARM64 runtime and verifies:

- signed ARM64 `java` and `lib/server/libjvm.dylib`;
- 64-bit HotSpot Server VM selection;
- no Homebrew runtime dependency;
- class-path and executable-JAR execution;
- ARM64 JNI;
- deterministic TLS 1.2;
- launch from a Windows ARM64 PE through Wine's Unix spawn boundary.

The Oracle DMG is pinned but must not be redistributed outside this runtime.

### Windows x86_64 Java

Temurin 8u492-b09 for Windows x86_64 runs its 64-bit Server VM through the
established x86_64 provider. Accepted coverage includes:

- interpreted and tiered/JIT execution;
- scoped `-Xcomp`;
- class-path and executable JARs;
- reflection and isolated class loading;
- JNI, native thread attach/callback/detach;
- process creation, sockets and TLS;
- code-page RW/RX transitions and instruction-cache invalidation;
- HotSpot code-cache telemetry.

An experimental outer tier-0 provider was rejected after it failed when
actually staged into Wine's build-tree load path. The established canonical
provider was restored byte-for-byte.

### Windows i386/WoW64 Java

Temurin 8u472-b08 for Windows i386 runs its 32-bit Client VM through the
FEX-derived provider. The completed J0–J6 sequence covers:

- software-TSO lowering and generated-code disassembly;
- interpreted class-path and executable-JAR execution;
- JNI callbacks, exceptions and attached native threads;
- direct and mapped buffers;
- allocation and GC pressure;
- monitors, wait/notify, volatile publication and atomic operations;
- loopback sockets, local TLS, timers, sleeps and shutdown hooks;
- C1/JIT and scoped `-Xcomp`;
- deoptimization, stack overflow and exception resume;
- repeated RW→RX code generation, patching and execution;
- young and full garbage collections;
- compiled mutators across safepoints;
- SuspendThread/Get/SetContext/ResumeThread;
- PE TLS and APC delivery;
- 100/100 repeated JVM lifecycle cycles with exact shutdown.

The unified J6 gate runs native ARM64 Java, Windows x86_64 Java, Windows i386
Java, and all four Wine architecture fixtures in one clean prefix. It then
reruns the Phase 4 WoW64 contract, i386 D3D11/D3D12, Gecko/MSHTML, OpenGL
through GLSL 4.5 Metal readback, SDL2/SDL3 and the ordinary four-mode
single-prefix baseline.

## Runtime-provider integrity

Every fresh-prefix runner uses:

```sh
scripts/stage-runtime-providers.sh
```

The command verifies canonical `xtajit64.dll` and `xtajit.dll` hashes before
wineboot, stages them into the build, and verifies the prefix copies after
wineboot. This prevents a fresh prefix from silently receiving an older
provider.

The accepted canonical providers are retained separately from experimental
side candidates. Candidate builds never overwrite the known-good runtime
until the complete promotion regression passes.

## Reproducibility and recovery

VKMT retains:

- pinned third-party source revisions;
- custom Wine, FEX, MoltenVK, DXVK, vkd3d-proton and DXMT patches;
- an in-tree universal LLVM-MinGW cross-toolchain;
- source-built runtime dependencies;
- focused build scripts for each component;
- source for every acceptance fixture;
- SHA-256 provider and artifact checks;
- automatic fresh-prefix cleanup;
- reproducible `.tar.zst` snapshot creation without an uncompressed
  intermediate.

The latest verified recovery image is:

```text
/Volumes/AverySSD/VKMT_snapshots/VKMT-runtime-j6-20260729-1738.tar.zst
SHA-256: be5f656e857f3fb1d3b8a9ec528655e22947372dfa1651244b1d2bc9d49a2298
```

Its 322,137-entry manifest is stored beside the archive. The archive passed
`zstd -t` and required-manifest checks for Wine, both canonical providers,
the Java/FEX/Wine patches, the unified runner and the Java/WoW64 plan.

Create future snapshots only with:

```sh
scripts/create-runtime-snapshot.sh
```

## Build and verification

Xcode, CMake/Meson/Ninja, the in-tree LLVM-MinGW toolchain and the pinned
source trees are required for a full rebuild. Prefer focused component builds
over rebuilding all of Wine.

Common build commands:

```sh
scripts/build-moltenvk.sh
scripts/build-vkd3d-proton.sh
scripts/build-vkd3d-proton-i386.sh
scripts/build-dxvk-aarch64.sh
scripts/build-dxvk-vkmt.sh 32
scripts/build-dxmt-arm64ec.sh
scripts/build-dxmt-i386.sh
scripts/build-fex-wow64.sh
scripts/build-sdl-runtime.sh
scripts/build-metalsharp-opengl.sh
scripts/build-wine-mono-arm64.sh
```

Core acceptance runners:

```sh
scripts/probe-p1-unified-arm64.sh
scripts/probe-p2-x64-dxvk.sh
scripts/probe-i386-wow64-phase4.sh
scripts/probe-p5-i386-vkmt.sh
scripts/probe-p6-single-prefix-architectures.sh
scripts/probe-p7-vkmt-d3d9.sh
scripts/probe-msync.sh
scripts/probe-sdl-runtime.sh
scripts/probe-opengl-all-arch.sh
scripts/probe-input-runtime.sh
scripts/probe-gecko-mshtml.sh
scripts/probe-msi-runtime.sh
scripts/probe-nsis-runtime.sh
scripts/probe-wine-mono-runtime.sh
scripts/probe-native-java-runtime.sh
scripts/probe-windows-java-j6-unified.sh
scripts/verify-preservation.sh
```

Each acceptance runner owns one disposable run root, stops only that prefix's
exact wineserver and removes its run root on success or failure. Prefixes,
logs and generated probes belong on the external SSD rather than consuming
internal storage.

## Repository layout

- `wine/wine-11.12/` — custom Wine source.
- `wine/build-ec/` — active multi-architecture Wine build and staged runtime.
- `third_party/` — pinned component source and runtime inputs.
- `runtime/` — architecture-specific graphics and runtime stages.
- `runtime-providers/` — canonical and candidate CPU providers.
- `patches/` — reproducible Wine, FEX and third-party patches.
- `scripts/` — fetch, focused build, stage, probe and snapshot commands.
- `test/` — source and binaries for deterministic fixtures.
- `docs/` — architecture plans, audits, contracts and validation evidence.
- `AGENTS.md` — preservation rules and authoritative implementation journal.

## Accepted boundaries and deliberate exclusions

VKMT is broad, but its claims remain gate-specific:

- D3D9 is accepted for loading, adapter enumeration and caps, not rendering.
- DXMT bridge/factory coverage is narrower than DXVK D3D11 rendering.
- OpenGL GLSL 3.30/4.50 rendering is accepted, not the entire GL 4.x API.
- CEF is accepted at export/subprocess level; its committed automated
  OSR/input/audio/HTTPS pixel gate is not complete.
- WebView2 x64 is a fixed-runtime bootstrap result.
- Electron x64 is accepted; Electron ia32 rendering is not.
- Inno compilation/extraction is accepted; a complete GUI installer lifecycle
  is not.
- Legacy D3DX9/10/11, MFC, OpenAL, PhysX and additional core fonts are outside
  scope.
- LDAP, Kerberos/GSSAPI, NTLM expansion, ODBC, printing, smart cards, serial,
  scanner/camera, COM/DCOM service expansion, scheduled tasks and shell
  association expansion were removed from the completion roadmap.

## Documentation

- [Preservation and build contract](AGENTS.md)
- [i386/WoW64 execution contract](docs/I386_WOW64_EXECUTION_CONTRACT.md)
- [i386/WoW64 architecture plan](docs/I386_WOW64_PLAN.md)
- [MSync](docs/MSYNC.md)
- [SDL runtime](docs/SDL_RUNTIME.md)
- [emulation design](docs/EMULATION.md)
- [native Wine D3D12](docs/NATIVE_WINE_D3D12.md)
- [MoltenVK/vkd3d gap audit](docs/GAPS.md)
- [transform-feedback design](docs/TRANSFORM_FEEDBACK.md)
- [Windows Java/WoW64 plan](docs/WINDOWS_JAVA_WOW64_PLAN.md)
