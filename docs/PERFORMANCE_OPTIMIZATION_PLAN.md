# VKMT Wine/FEX performance optimization plan

Date: 2026-07-31

## Objective

Optimize the actual runtime rather than the MetalSharp backend: Wine startup
and process lifecycle, FEX x86_64/i386 translation throughput, cross-architecture
transitions, CPU overhead, GPU translation, pipeline compilation, and reusable
caches.

Backend changes are permitted only where they provide low-overhead measurement
or remove work that obscures runtime measurements. They are not the primary
optimization target.

All accepted configurations must keep these settings disabled:

- `FEX_TSOENABLED=0`
- `FEX_VECTORTSOENABLED=0`
- `FEX_MEMCPYSETTSOENABLED=0`

Correctness gates for ARM64, AArch64, ARM64EC, x86_64, and i386/WoW64 remain
mandatory. Do not trade away the accepted exception, memory, Java JIT,
graphics, Steam child-process, or exact-shutdown contracts for benchmark
numbers.

## Current measured and inspected baseline

- The accepted Steam WebHelper path renders in approximately 28 seconds.
- Steam's CEF GPU child currently forces `FEX_MAXINST=1` to preserve precise
  architectural state during synchronous exception delivery. Normal FEX uses
  multiblock translation and a substantially larger instruction ceiling. This
  is the highest-confidence translation bottleneck.
- A same-prefix x86_64 entry fixture measured approximately 0.88-0.92 seconds
  with a cold wineserver and approximately 0.03 seconds with the Wine session
  warm. The first observed cold run was 2.07 seconds while MoltenVK initialized
  and logged its complete capability surface.
- FEX contains code-map generation and reusable code-cache infrastructure, but
  the Windows/ARM64EC cache loader is explicitly disabled and the Windows image
  tracker still has unfinished cache load/register steps. Repeat Windows
  processes therefore do not yet receive the intended persistent translated
  ARM64 code reuse.
- The installed runtime contains 35,260 files totaling about 15.7 GB; 14,874
  files are smaller than 64 KiB. The Steam prefix contains 12,053 files.
  Startup can therefore be dominated by metadata and path lookup latency even
  when sequential storage bandwidth is high.
- Normal Steam launch currently performs wrapper readiness checks, a
  synchronous Wine `reg import`, MoltenVK readiness checks, and production
  graphics tracing. Two recent Steam traces contained 32,440 lines. These are
  supporting launch costs, not the central runtime optimization project.
- Some game routes copy and hash injected DLLs again at launch, and preset
  shader SQLite databases can be reopened and merged again on an unchanged
  launch.

## P0 - Runtime measurement spine

Add one correlation identifier spanning the launch request, Wine, wineserver,
NTDLL, both FEX providers, graphics translation, and child processes. Record:

1. launch request received;
2. runtime readiness completed;
3. Wine process spawned;
4. wineserver connection established;
5. NTDLL process initialization entered/completed;
6. FEX context initialized;
7. first guest block translated or loaded from cache;
8. PE entry point reached;
9. first native/guest boundary transitions by class;
10. graphics device initialization;
11. shader conversion and pipeline-cache hit/miss;
12. first submission and first visible present;
13. Steam browser, renderer, GPU, and utility child lifecycle; and
14. process and exact-prefix teardown.

Benchmark four states independently:

- cold process and cold wineserver;
- warm macOS file cache with cold wineserver;
- persistent wineserver/session;
- persistent session plus warm FEX and graphics caches.

Use 20-30 runs and report median, p90, and p95. Capture CPU time, logical and
physical I/O, page faults, loaded image count, failed path probes, translated
blocks, cache hits, dispatcher exits, architecture transitions, shader compile
time, pipeline creation time, and first-frame latency. Use `os_signpost`,
Instruments File Activity, Time Profiler, System Trace, and M4 Processor Trace
where appropriate.

Gate: repeated benchmark sessions agree within 5% or explain the variance.

## P1 - FEX precise-exception fast path

Replace the Steam GPU child's single-instruction block workaround without
weakening its correctness:

- Record a compact mapping from host JIT PC to exact guest RIP.
- Record where live guest registers reside at exception-capable instructions:
  host registers, spills, or constants.
- On a synchronous fault, reconstruct and publish the exact guest architectural
  state before Wine dispatches the exception.
- If full state maps are initially too expensive, split blocks or commit state
  only around instructions that can produce the relevant synchronous fault.
- Restore normal multiblock translation and a normal `MaxInst` after the
  original CEF regression passes.

Gate:

- the original CEF synchronous-access-violation regression passes;
- no stale guest register reaches Wine SEH;
- the GPU child uses normal multiblock translation;
- all no-TSO settings remain zero; and
- Steam first visible paint is below 10 seconds initially, with below 5
  seconds as the warm-path target.

## P2 - Persistent FEX translated-code cache on Windows

Complete the existing FEX Windows code-cache contract:

1. bounds-check the complete cache file before reading headers, block lists,
   relocation records, code, or guest-page metadata;
2. allocate ARM64EC-compatible executable storage;
3. copy and relocate cached ARM64 code;
4. perform the required instruction-cache maintenance;
5. finalize executable protection;
6. register cached blocks and executable guest ranges with the lookup cache;
7. retain mapped-cache ownership for the complete process lifetime; and
8. integrate Wine's existing flush, protection, free/unmap, section-unmap,
   dirty-write, and self-modifying-code invalidation notifications.

The cache identity must include:

- complete PE content identity;
- FEX commit and cache-format version;
- Wine/FEX ABI generation;
- x86_64 versus i386 mode;
- effective host CPU features;
- `MaxInst`, multiblock, precise-exception, and dynamic-code modes; and
- all three no-TSO values.

Do not reuse a normal-image cache for Java/HotSpot or another dynamic-code
mode unless that mode's invalidation fixture explicitly passes. Generate or
refresh caches after successful runs, preferably outside the first-paint
critical path. Prioritize Steam, SteamUI, CEF/libcef, shared runtime DLLs, and
frequently launched game images.

Gate:

- more than 80% of eligible early guest blocks hit cache on repeat launch;
- repeat JIT generation time falls by at least 70%;
- cache corruption or mismatch safely falls back to live translation; and
- self-modifying code, Java JIT, exceptions, i386, graphics, and child-process
  gates pass.

## P3 - Wine process, loader, and session overhead

- Profile NTDLL initialization, PE mapping, imports, ARM64X redirection,
  wineserver requests, Unix calls, DLL search misses, initial services, and
  teardown.
- Add a prefix-scoped, bounded warm-session policy using Wine's persistent
  server support. Never share one session between prefixes. Shut it down for
  migration, repair, provider replacement, or MSync mode changes.
- Determine why a trivial cold x86_64 fixture initializes MoltenVK and defer
  Vulkan/Metal initialization until a process actually imports the graphics
  route.
- Build a generation-aware resolved-DLL cache and negative lookup cache.
- Keep verified GStreamer and font registries; do not rescan the complete
  native dependency closure during ordinary launches.
- Prefer stable `@loader_path`/`@rpath` dependencies and narrow search paths
  over broad `DYLD_LIBRARY_PATH` plus `DYLD_FALLBACK_LIBRARY_PATH` lists.

Gate:

- warm trivial x86_64 and i386 execution below 75 ms p95;
- failed filesystem/path probes reduced by at least 50%;
- native ARM64 Wine and exact prefix shutdown remain correct; and
- no Homebrew, Rosetta, or undeclared host dependency appears.

## P4 - Cross-architecture transition reduction

Instrument and classify transitions across:

- x86_64/i386 guest to FEX JIT;
- JIT to ARM64EC/ARM64X Wine code;
- ARM64EC to native ARM64 Unix libraries;
- syscalls and Unix calls;
- callbacks, APCs, exceptions, context get/set, and thread lifecycle; and
- graphics and media host bridges.

Then:

- eliminate duplicate guest/host pointer and context conversion;
- cache safe thunk and export resolution;
- batch boundary operations where Windows ordering permits;
- promote measured hot Wine builtin paths to ARM64X/ARM64EC rather than
  repeatedly emulating pure x86 implementations; and
- preserve explicit acquire/release or barrier behavior required by the
  no-TSO memory contract.

Gate: expensive boundary transitions per startup interval or representative
frame fall by 25-50% without changing observable Windows behavior.

## P5 - CPU/JIT throughput and cache locality

Profile the FEX decoder, frontend, IR passes, emitter, dispatcher, lookup
cache, code invalidation, thread state, Wine syscall bridge, and ARM64EC
handoffs on real Steam and game workloads.

- Compare the accepted provider with clean `-O2`, `-O3`, ThinLTO, and PGO
  builds independently.
- Do not combine compiler changes until each result has a correctness and
  performance measurement.
- Improve lookup-cache and thread-state locality based on measured cache
  misses and false sharing.
- Reduce allocator churn and batch code-buffer growth/finalization.
- Avoid M4-only instructions in the general release unless explicit CPU slices
  and selection logic are introduced.

Gate: at least 15% lower guest CPU time after persistent-code-cache benefits
are excluded, with all architecture and Java gates passing.

## P6 - GPU translation and pipeline cache

Measure DXVK, vkd3d-proton, DXMT, OpenGL-Metal, Winemetal, and MoltenVK
independently. Record:

- DXBC/DXIL/SPIR-V/MSL conversion;
- Vulkan pipeline-cache lookup and creation;
- Metal library and pipeline compilation;
- command queue and first submission; and
- first present plus subsequent frame-time stutter.

Create one versioned cache identity containing the translation-stack revisions,
source shader hash, root signature and pipeline descriptor, macOS build, Metal
compiler/language generation, and GPU family/device.

- Persist the Vulkan caches actually consumed by DXVK/vkd3d-proton/MoltenVK.
- Harvest and serialize Metal binary archives for DXMT, OpenGL-Metal, and
  MoltenVK-compatible paths.
- Load compatible archives before pipeline creation.
- Compile missing pipelines asynchronously when correctness and title behavior
  allow it.
- Keep per-game caches isolated while permitting separately versioned shared
  presentation/UI archives.

Gate:

- warm pipeline-cache hit rate above 90%;
- warm pipeline creation below 100 ms p95 for deterministic fixtures;
- first-frame latency reduced by at least 50%; and
- incompatible cache identities always fall back safely.

## P7 - Executable memory and cache maintenance

Status: completed 2026-08-01. The WoW64 instruction-cache flush boundary no
longer repeats the same guest-range invalidation through both the common
tracker and a second host-to-guest path. Correlated baseline/candidate traces
prove a 50.00% reduction in flush invalidation passes. The trace-only metrics
cover flush ranges, general invalidation passes/bytes, thread lookup eviction,
RWX write faults, and protection calls; their atomic accounting is disabled
outside an active VKMT performance trace.

Measure JIT code-buffer allocation, RW/RX transitions, instruction-cache
maintenance, invalidation ranges, lookup eviction, page faults, and
self-modifying-code behavior.

- Batch executable-page finalization and instruction-cache maintenance where
  visibility and exception semantics allow.
- Prefer page-granular invalidation over complete-cache eviction.
- Keep W^X and current macOS executable-memory correctness.
- Never use TSO as a shortcut.

Gate: protection/cache-maintenance operations during startup fall by at least
50%, while the i386 SMC, Java JIT, exception, and cross-process fixtures pass.

## P8 - Runtime hot-set and storage support

Storage is supporting work, not the primary optimization target. Trace the
actual PE, Mach-O, registry, font, media, shader, and cache pages consumed in
the first five seconds.

- Build a per-title hot-set manifest.
- Test `F_RDADVISE`, `F_RDAHEAD`, or controlled mmap prefetch only for files
  demonstrated to be on the critical path.
- Keep the immutable runtime layout valid; do not concatenate executable
  images into an unusable archive or copy the full runtime into RAM.
- Apply explicit cache quotas and LRU eviction.
- Measure metadata latency, physical read stalls, and page faults instead of
  advertised sequential bandwidth.

Gate: genuinely cold physical read stall time falls by at least 25%, with no
warm-cache regression.

## Supporting launch cleanup

These are useful but subordinate to Wine/FEX/GPU work:

- production Steam uses `WINEDEBUG=-all`; diagnostic graphics tracing is
  opt-in;
- seed the Steam D3D12 registry guard during prefix preparation/migration and
  store a versioned receipt;
- verify wrapper and deployed DLL hashes only when metadata or runtime
  generation changes;
- merge preset shader databases only when the preset/runtime identity changes;
- create verbose runtime logs only for explicit diagnostics; and
- fix MoltenVK readiness detection to use the canonical bundled paths.

## Required execution order

1. P0 measurement spine.
2. P1 precise exception reconstruction and removal of `MAXINST=1`.
3. P2 persistent FEX translated-code cache.
4. P3 Wine loader/session work.
5. P4 cross-architecture transition reduction.
6. P5 CPU/JIT profiling and optimization.
7. P6 GPU translation and pipeline archives.
8. P7 executable-memory/cache-maintenance improvements.
9. P8 measured hot-set support.

Supporting launch cleanup may accompany P0, but it must not displace or be
reported as the core optimization project.

## Final performance acceptance

- All existing ARM64, AArch64, ARM64EC, x86_64, and i386/WoW64 correctness
  gates pass in the accepted single-prefix configuration.
- Every FEX TSO setting remains zero.
- Warm Steam first visible paint targets below 5-10 seconds from the current
  approximately 28-second accepted baseline.
- Warm trivial guest process entry is below 75 ms p95.
- Repeat eligible JIT work falls by at least 70%.
- Warm graphics pipeline-cache hit rate exceeds 90%, with at least 50% lower
  first-frame latency in deterministic graphics fixtures.
- No Rosetta process or x86 Mach-O host dependency participates.
