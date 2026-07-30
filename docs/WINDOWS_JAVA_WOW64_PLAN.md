# Windows Java 8 i386/WoW64 and x86_64 plan

## Decision and fixed baseline

Windows Java is feasible on this stack, but it is a guest runtime and is
separate from the accepted native Oracle JRE 8u501 ARM64 lane. The Windows
i386 JVM executes through Wine WoW64 and the native ARM64 FEX `xtajit.dll`;
the Windows x86_64 JVM executes through `xtajit64.dll`. Windows JNI libraries
must match the guest JVM architecture. Neither guest JVM may load an ARM64
Mach-O JNI library.

The canonical accepted providers after J6 are:

- i386 `xtajit-arm64-known-good.dll`, SHA-256
  `fe1345724f6a2950541966515f766099b7bce38701c9960d4be513c27ec81073`;
- x86_64 `xtajit64-arm64ec-known-good.dll`, SHA-256
  `7b9f55ceabe971ffa1f514570bb54ed7b5640959e4440e7f8a013e9af13ab7e6`.

The current FEX worktree contains later uncommitted TSO, unaligned-memory,
W^X, exception, and ARM64EC candidates. They are evidence and candidate
source, not permission to overwrite the golden providers. A Java candidate
must be built to a side directory and selected through
`VKMT_XTAJIT_SOURCE`/`VKMT_XTAJIT_SHA256`.

### Mandatory memory-model invariant

Do not remove or bypass FEX's x86 TSO semantic model. Also do not depend on
Apple hardware TSO being present. Guest operations remain classified as TSO
through the IR, and the final AArch64 emitter supplies their ordering:

- naturally aligned scalar load: size-appropriate `LDAR`;
- naturally aligned scalar store: size-appropriate `STLR`;
- unaligned scalar load: ordinary `LDR` followed by `DMB ISHLD`;
- unaligned scalar store: `DMB ISH` followed by ordinary `STR`;
- locked read/modify/write: acquire/release atomic operation or
  `LDAXR`/`STLXR` loop, with a serialized fallback for split or unaligned
  atomics.

The alignment-selection sequence must preserve NZCV. Darwin W^X means the
unaligned form is emitted before publication; it may not depend on patching an
RX JIT page after an alignment fault. The existing candidate's optional
`LDAPR` path is not the conservative Java baseline: use `LDAR` unless a
separate cumulative-ordering proof and fixture justify otherwise.

## Pinned inputs discovered during scoping

As of 2026-07-29, Eclipse Temurin publishes different latest Java 8 levels for
the two Windows architectures:

- i386: Temurin 8u472-b08,
  `OpenJDK8U-jre_x86-32_windows_hotspot_8u472b08.zip`, SHA-256
  `21a2c5af684a658f1484daa85eabf4961ab9de28c0efbf31da2381d77fce3b5f`,
  from
  `https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u472-b08/OpenJDK8U-jre_x86-32_windows_hotspot_8u472b08.zip`;
- x86_64: Temurin 8u492-b09,
  `OpenJDK8U-jre_x64_windows_hotspot_8u492b09.zip`, SHA-256
  `bb25b002556afc7ef158cd95ec6270dddb3eecba69acdd7abb9d28b2e9ff0f5e`,
  from
  `https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u492-b09/OpenJDK8U-jre_x64_windows_hotspot_8u492b09.zip`.

The archives were inspected transiently on the external SSD and the inspection
roots were removed. The i386 archive contains PE32 `java.exe` and
`bin/client/jvm.dll`; it does not contain a Server VM. The x86_64 archive
contains PE32+ `java.exe` and `bin/server/jvm.dll`. Therefore i386 acceptance
means HotSpot Client VM interpreter plus C1 JIT; x86_64 acceptance means
HotSpot Server VM plus its JIT.

Both VM DLLs import the UCRT API-set surface, `VCRUNTIME140.dll`, Kernel32,
PSAPI, User32, Version, WinMM, and Winsock. Both use PE TLS, virtual-memory
allocation/protection/query, mapped files, thread suspend/resume/context,
events/condition variables, process creation, exception filters, dynamic DLL
loading, and performance counters. The i386 VM also contains `cmpxchg8b`,
`movntq`, and REP move/store instruction families.

## Boundary ownership map

| HotSpot surface | Existing owner | First files to inspect if its gate fails |
| --- | --- | --- |
| 32-bit heap, code-cache and mapped-JAR addresses | Wine canonical guest-memory manager | `dlls/wow64/memory.c`, `dlls/wow64/virtual.c`, `dlls/ntdll/unix/virtual.c` |
| Guest effective-address translation | FEX i386 page-table path | `JIT/MemoryOps.cpp`, `JIT/AtomicOps.cpp`, `JIT/JITClass.h` |
| JIT RW→RX, instruction-cache flush and SMC eviction | Wine VM notifications plus FEX code cache | `dlls/wow64/virtual.c`, `Source/Windows/WOW64/Module.cpp`, `CPUBackend.cpp`, `JIT/JIT.cpp`, `Core.cpp`, `CodeCache.cpp` |
| x86 TSO, volatile accesses, CAS and unaligned access | FEX TSO IR plus final ARM64 memory/atomic emitter; never host TSO | `JIT/MemoryOps.cpp`, `JIT/AtomicOps.cpp`, `Common/TSOHandlerConfig.h`, `ArchHelpers/Arm64Emitter.*` |
| TLS and segment bases | Wine loader/WoW64 plus FEX CPU state | `dlls/ntdll/loader.c`, `dlls/wow64/syscall.c`, `Source/Windows/WOW64/Module.cpp`, `CoreState.h` |
| Implicit null checks, stack guards, SEH and continuation | Wine exception dispatch plus FEX reconstruction | `dlls/wow64/syscall.c`, `dlls/ntdll/unix/signal_arm64.c`, `Source/Windows/WOW64/Module.cpp` |
| Safepoint suspension and thread context | Wine thread syscalls plus `BTCpu*Context` | `dlls/wow64/process.c`, `dlls/wow64/syscall.c`, `Source/Windows/WOW64/Module.cpp` |
| JNI DLL routing and dependencies | Wine PE loader and architecture-specific stage | `dlls/ntdll/loader.c`, `dlls/kernelbase/loader.c`, UCRT/VCRUNTIME stages |
| `ProcessBuilder` child creation | Wine WoW64 process conversion | `dlls/wow64/process.c`, `dlls/ntdll/unix/process.c` |
| Networking/TLS | i386 Winsock/AFD and Java JSSE | `dlls/ws2_32`, `dlls/wow64/file.c`, staged GnuTLS only where Wine APIs participate |

This map is diagnostic ownership, not a list of files to edit preemptively.
The first failing gate selects the owner.

## Phase J0 — preserve and stage — complete 2026-07-29

1. Record root, Wine, and FEX revisions, all dirty nested-source paths, golden
   provider hashes, and the current four-architecture baseline.
2. Add checksum-pinned fetch and stage scripts for the two ZIP archives. Stage
   them separately under `wine/build-ec/java-runtime/i386` and
   `wine/build-ec/java-runtime/x86_64`; never merge their `bin` directories.
3. Verify PE machine type for `java.exe`, `javaw.exe`, `jvm.dll`, and every
   native JRE DLL. Verify the matching UCRT/VCRUNTIME dependency closure before
   launch.
4. Build candidates only under `build/fex-wow64-java/`. Adjust the existing
   FEX builder before using it so it cannot replace the canonical
   `xtajit.dll`.
5. Add a provider-mode audit proving Darwin uses software TSO lowering, then
   disassemble focused aligned, unaligned, and locked fixtures. Require the
   exact `LDAR`/`STLR` or `LDR`/`DMB`/`STR` families above before launching
   either JVM.

Gate: inputs, hashes, architecture manifests, and provider selection are
deterministic; the golden provider files remain byte-identical; software TSO
lowering is visible in generated ARM64 code.

Acceptance evidence is
`docs/validation/windows-java-j0-20260729/RESULTS.md`. The retained,
source-integrated side baseline is `third_party/FEX-2607-java-baseline`; its
accepted candidate is deliberately not promoted before the later Java and
WoW64 regression phases.

## Phase J1 — loader and interpreter gate — complete 2026-07-29

At each step, run x86_64 first as the fixture/control lane and then i386 in the
same fresh prefix:

1. run the focused TSO publication/CAS preflight with the selected provider;
2. `java.exe -version`;
3. i386 `-client -Xint -version`, x86_64 `-server -Xint -version`;
4. class-path execution;
5. executable-JAR execution;
6. reflection, class loading, ZIP/JAR reads, and clean VM shutdown.

Require logs to identify the expected VM and data model: i386 Client VM/32-bit
and x86_64 Server VM/64-bit. No JIT fix is considered during this phase.

Failure ownership:

- missing import or wrong DLL machine → stage/loader;
- guest address outside the registered map → Wine guest-memory owner;
- missing/incorrect x86 instruction → FEX decoder/emitter;
- exception before `_JNI_CreateJavaVM` → loader/TLS/CRT boundary.

Gate: both interpreters run the same class and JAR fixtures and exit exactly.

Acceptance evidence is
`docs/validation/windows-java-j1-20260729/RESULTS.md`. One fresh prefix ran
x86_64 first and i386 second; both reported interpreted mode, the correct
Server/Client VM and data model, and identical class-path, executable-JAR,
reflection/class-loader, and ZIP/JAR markers before exact shutdown.

## Phase J2 — services and guest JNI gate under `-Xint` — complete 2026-07-29

Use architecture-matched Windows JNI DLLs built with the in-tree LLVM-MinGW
toolchain. Cover:

1. JNI load, symbol lookup, 32/64-bit pointer width, callbacks, and
   attach/detach from a second native thread;
2. allocation pressure, explicit GC, direct byte buffers, mapped files, and
   repeated class-loader creation;
3. Java threads, monitors, TLS, exceptions, stack overflow, and shutdown
   hooks;
4. `ProcessBuilder` child launch and inherited environment;
5. sockets plus deterministic local HTTPS/TLS;
6. timing and sleeps driven by `QueryPerformanceCounter`.

Gate: identical semantic markers from i386 and x86_64, no host pointer in an
i386 exception or Java-visible address, and no leaked child process.

Acceptance evidence is
`docs/validation/windows-java-j2-20260729/RESULTS.md`. One fresh prefix ran
x86_64 first and i386 second. Architecture-matched JNI DLLs passed load,
callback, exception, pointer-width, and native-thread attach/detach gates.
Both interpreted JVMs then passed matching allocation/GC, direct and mapped
buffer, class-loader, monitor/TLS, exception/stack-overflow, child-process,
socket, local HTTPS, timer, sleep, and shutdown-hook fixtures. The i386
Java-visible native address was `0x78925034`, the mapped files were removed
at VM shutdown, and exact wineserver shutdown left no child or prefix.

## Phase J3 — HotSpot JIT and executable-memory gate — complete 2026-07-29

Enable one compiler at a time:

- i386: Client VM/C1 with a low compile threshold, then `-Xcomp`;
- x86_64: Server VM with normal tiering, then `-Xcomp`.

Fixtures must prove compilation occurred, then exercise:

1. code-cache reserve/commit and RW→RX transitions;
2. `FlushInstructionCache` and FEX guest-block invalidation;
3. deoptimization, uncommon traps, class unloading, and recompilation;
4. implicit null checks, divide-by-zero, stack guards, and exception resume
   from compiled code;
5. repeated code-cache growth without a stale guest-to-host block.

Do not patch Java binaries. On the first fault record guest EIP, host PC,
guest fault address, translated host address, mapping/protection, current
provider hash, and last completed Java marker.

Gate: both JIT lanes complete twice in one prefix and report nonzero compiled
method counts.

Acceptance evidence is
`docs/validation/windows-java-j3-20260729/RESULTS.md`. One fresh prefix ran
x86_64 Server tiered and scoped `-Xcomp`, then i386 Client/C1 and scoped
`-Xcomp`. All four lanes passed with nonzero fixture compilation counts,
nonzero HotSpot compilation time, four code-cache unload/reload waves, and
architecture-matched RW→RX/patch/flush executable-memory fixtures. Tiered
lanes own uncommon-trap and exception-resume acceptance; forced lanes own
compile-on-first-use and repeated execution, with orchestration/reflection
and exception-catching coordinators deliberately excluded from `-Xcomp`.

The x86_64 side provider is
`build/xtajit64-java-j3-final/provider/xtajit64.dll`, SHA-256
`3c5878816c78dc670190e3587e76ace53e472c14a50972cd97808fda25636c3b`.
It adds guest-byte validation, free/unmap invalidation, and
`VKMT_X64_TIER0=0` for a precise dynamic-code lane. It is not promoted.

## Phase J4 — x86 memory-model acceptance — complete 2026-07-29

Run the golden i386 provider first. FEX's x86 TSO model remains enabled, but
Darwin must always use software lowering at the final ARM64 emitter. It must
not call `SetHardwareTSOSupport(true)` or otherwise suppress TSO IR based on a
host capability. Vector and REP memcpy/set TSO are intentionally separate
modes; do not globally enable them without a fixture proving the need.

The acceptance suite covers:

1. volatile producer/consumer publication with sequence and payload checks;
2. monitor enter/exit and contended wait/notify;
3. `AtomicInteger` and i386 `AtomicLong` CAS (`cmpxchg8b`);
4. concurrent queue handoff and once-only initialization;
5. aligned and deliberately unaligned scalar loads/stores;
6. REP move/store and the i386 VM's non-temporal `movntq` path;
7. GC write barriers while mutator threads are active.

If the golden provider fails an unaligned TSO access, evaluate the existing
side candidate after making its final lowering match the mandatory invariant:
aligned accesses use `LDAR`/`STLR`; unaligned loads use `LDR` then
`DMB ISHLD`; unaligned stores use `DMB ISH` then `STR`. This avoids runtime
backpatching of Darwin RX pages. Flags must be preserved across the alignment
test. Strict split-lock mode is enabled only for a reproduced cross-boundary
atomic. Vector or memcpy TSO is enabled only for a failing vector/REP ordering
fixture.

Gate: deterministic checksums and sequence counts across repeated high-load
runs with no torn 64-bit atomic, missed publication, deadlock, or exception
loop.

Acceptance evidence is
`docs/validation/windows-java-j4-20260729/RESULTS.md`. Three independent
fresh-prefix repetitions selected the accepted golden provider without
promotion. Each repetition passed a mixed/JIT volatile, monitor, CAS,
queue/once, unaligned, REP, and `movntq` lane plus an interpreted
allocation-driven GC/write-barrier lane. The split is intentional: J5 owns
the separately reproduced interaction between repeated safepoints and
compiled mutators.

## Phase J5 — safepoint and lifecycle stress — complete 2026-07-29

Combine the JIT and memory-model fixtures with:

1. repeated thread creation/exit;
2. GC safepoints while other threads allocate and execute compiled code;
3. suspend/get-context/set-context/resume through HotSpot's normal machinery;
4. JNI attach/detach and callbacks during GC pressure;
5. repeated VM process startup/shutdown and exact wineserver survival.

This phase specifically regresses FEX call-return cursor preservation,
internal synchronous-fault reconstruction versus external context transfer,
Wine `NtContinueEx`, PE TLS, APC delivery, and second-thread isolation.

Gate: 100 lifecycle iterations with exact process exit and no retained Java,
Wine, or TLS-server process.

Acceptance evidence is
`docs/validation/windows-java-j5-20260729/RESULTS.md`. One fresh prefix
completed 10 i386 Client-VM launches with 10 lifecycle iterations per launch:
100/100 total. Every iteration ran four compiled/allocation workers through
two full collections, JNI native-thread attach/callback/detach, PE TLS,
compiled null/divide exceptions, APC delivery, and exact worker/JVM exit.
Launch 0 additionally passed a controlled HotSpot
SuspendThread/GetThreadContext/SetThreadContext/ResumeThread roundtrip.

The accepted side provider is
`build/fex-wow64-java-j5-divide/provider/xtajit.dll`, SHA-256
`fe1345724f6a2950541966515f766099b7bce38701c9960d4be513c27ec81073`.
The final targeted `wow64.dll` is SHA-256
`3f252921f12806907c78a4bf07c1aa5a761ba7882d3b72bb876c1dc316f93e7b`.
The provider invalidates only dirty writable-executable HotSpot code-cache
ranges at non-alertable, quiescent wait boundaries; alertable APC waits are
excluded. The complete Phase 4 i386/WoW64 contract passed afterward,
including context, SEH, APC, second-thread, user-callback, and repeated-thread
gates. No J5 or Phase 4 prefix/process remains.

## Phase J6 — unified-prefix and regression promotion — complete 2026-07-29

One fresh prefix must run, sequentially:

1. native ARM64 Oracle JRE server handoff;
2. Windows x86_64 Temurin Server VM;
3. Windows i386 Temurin Client VM through WoW64;
4. the ordinary ARM64/ARM64EC/x86_64/i386 single-prefix gate.

If FEX or Wine changes were needed, also rerun:

- the complete Phase 4 i386 lifecycle contract;
- i386 VKMT/D3D12/D3D11;
- i386 Gecko/MSHTML;
- OpenGL and SDL multi-architecture gates.

A candidate provider is promoted only after every affected regression passes.
Then update the canonical provider hash, preservation inventory, recovery
snapshot manifest, validation evidence, and `AGENTS.md`.

Acceptance evidence is
`docs/validation/windows-java-j6-20260729/RESULTS.md`. One clean prefix ran
the native Oracle ARM64 Server VM handoff, Windows x86_64 Temurin Server VM,
Windows i386 Temurin Client VM, then ARM64, ARM64EC, x86_64, and i386 Wine
fixtures in that order. Exact shutdown passed with no retained process or
prefix.

The J5 i386 provider was promoted to the canonical source and Wine build
copies at SHA-256
`fe1345724f6a2950541966515f766099b7bce38701c9960d4be513c27ec81073`.
The established x86_64 provider remains canonical at
`7b9f55ceabe971ffa1f514570bb54ed7b5640959e4440e7f8a013e9af13ab7e6`.
J6 proved that build-tree Wine resolves `xtajit64` from its build output
rather than a prefix override. Promoting the experimental J3 x86_64 binary
there exposed a reproducible tier-0 interpreter crash, so it was rejected and
the byte-identical established provider was restored before final acceptance.

After promotion, the complete Phase 4 WoW64 contract, i386 VKMT
DXGI/D3D12/D3D11, Gecko/MSHTML, OpenGL through GLSL 4.5 Metal readback,
SDL2/SDL3, and the ordinary four-architecture single-prefix gate all passed
without provider override variables. All affected probes re-stage the
selected providers after `wineboot` and delete only their exact disposable
run root.

## Build and cleanup discipline

- Never perform a full Wine rebuild for this work. Rebuild only the owning
  targets, normally `wow64.dll`, `ntdll.dll`/`ntdll.so`, `wineserver`, or the
  FEX `wow64fex` target.
- Every probe root lives under
  `/Volumes/AverySSD/VKMT/build/probe-runs/windows-java.*`.
- Every exit path stops that root's exact `wine/build-ec/server/wineserver`
  with `-k` and `-w`, stops local TLS/child processes, then deletes only that
  exact disposable run root.
- A retained diagnostic root must be removed before the next prefix is
  created.
- Never overwrite or delete the golden Wine tree or providers. Candidate
  staging is explicit and reversible.
