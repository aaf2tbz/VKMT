# VKMT File-by-File AI Optimization Roadmap

Status: Phases 0 and 1, the WoW64/MSync functional promotion gate, and the
first Phase 2 heap candidate audit are complete. The heap candidate was
compiler-equivalent and was rejected without promotion; the remaining
candidate files still require workload-specific passes.
This document does not authorize source changes by itself. The current
c-ai-optimizer integration is a candidate pipeline; no production Wine or FEX
source has been optimized yet.

## Scope and operating rules

The corpus currently contains 82 custom C paths relative to the Wine 11.12
release baseline: 80 committed custom paths plus two additional current
worktree paths. There are no custom C++ paths. Optimization is function-level,
not whole-file rewriting.

- Use the existing canonical prefix:
  build/probe-runs/phase-a-graphics-prefix.
- Do not create disposable prefixes or run routine wineboot.
- Use the current P8 providers and P8 acceptance gates; P6 is supporting
  smoke evidence only.
- Keep FEX_TSOENABLED, FEX_VECTORTSOENABLED, and FEX_MEMCPYSETTSOENABLED set
  to 0.
- Preserve ABI, SEH/unwind behavior, callback order, lock order, signal-frame
  layout, guest-pointer conversion, FEX invalidation, and server
  linearization points.
- Never use -march=native or ARM64-incompatible AVX flags for the native build.
  Do not use -ffast-math for Win32-semantic code or introduce OpenMP into
  Wine runtime, lock, signal, loader, or callback paths.
- AI output is a candidate until it has reproducible source hashes,
  architecture builds, functional tests, and workload measurements.
- Optimize only VKMT-owned changes or an explicitly identified hot helper; do
  not rewrite untouched upstream Wine merely because it is in a custom file.
- Record accepted changes and their evidence in Inventory.md; never package
  candidate binaries, caches, prefixes, or diagnostic logs.

## Phase 0 — Freeze and establish the baseline

Before generating candidates:

1. Record the nested Wine commit, Wine release base, FEX revision, P8 provider
   hashes, compiler/toolchain versions, build flags, and canonical prefix
   receipt.
2. Preserve and hash the current dirty functional work in WoW64 VM, MSync,
   ARM64 signal handling, WoW64 USER, FreeType, and Winsock. Do not optimize
   those changes and unrelated AI candidates in the same patch.
3. Run the existing baseline on ARM64, ARM64EC, x86_64, and i386/WoW64.
4. Retain baseline results for P8 hotset, WoW64 VM, FEX mapping/invalidation,
   MSync, DXMT, CEF x64 OSR, Electron x64, and process loading.
5. Record median and p95 timing over repeated runs; return code alone is not a
   performance baseline.

Known CEF i386 limitations remain an explicit diagnostic boundary. They must
not be converted into a false green result while optimizing x64 or WoW64.

Exit: the current source and its known failures are reproducible before any
candidate is evaluated.

## Phase 1 — Build the function-level ledger

For each of the 82 paths below, identify the custom hunks and functions,
callers, architecture reachability, hotness, and semantic risks. Each function
gets one initial status:

- candidate — an isolated pure helper may receive an out-of-tree candidate;
- manual-review — AI may suggest but not directly rewrite or promote;
- protected — ABI, synchronization, signal, JIT, or callback boundary;
- generated/no-rewrite — generated thunk or build/bootstrap code;
- not-hot/no-candidate — profiled without forcing an optimization.

The ledger must include a baseline hash, candidate hash, compiler flags,
benchmark workload, affected architectures, test receipts, and rejection
reason where applicable.

The current candidate-path disposition matrix is
`docs/AI_OPTIMIZATION_DISPOSITION.tsv`. `TRIAGE_NO_SAFE_CANDIDATE` and
`CANDIDATE_BLOCKED_*` are scope findings, not green performance results; they
remain open until a matching workload proves a pure leaf is hot and safe.

## Phase 2 — NTDLL, loader, exceptions, and host boundaries

These are the highest-priority functional files, but they are protected from
blind AI rewriting:

- dlls/ntdll/exception.c
- dlls/ntdll/loader.c
- dlls/ntdll/process.c
- dlls/ntdll/signal_arm64.c
- dlls/ntdll/signal_arm64ec.c
- dlls/ntdll/sync.c
- dlls/ntdll/thread.c
- dlls/ntdll/unix/loader.c
- dlls/ntdll/unix/msync.c
- dlls/ntdll/unix/process.c
- dlls/ntdll/unix/signal_arm64.c
- dlls/ntdll/unix/sync.c
- dlls/ntdll/unix/thread.c
- dlls/ntdll/unix/virtual.c

Profile loader startup, DLL resolution, process creation, exception return,
signal transitions, host/guest calls, synchronization, MSync, and VM calls.
Only a demonstrably pure leaf helper may become a candidate. No candidate may
change SEH state, unwind metadata, loader locks, stack layout, signal frames,
callback reentrancy, TEB/emulator state, or host transition ordering.

First eligible candidate pass:

- dlls/ntdll/heap.c
- dlls/ntdll/unix/env.c
- dlls/ntdll/unix/file.c
- dlls/ntdll/unix/socket.c
- dlls/ntdll/unix/system.c

The initial candidate scope is limited to pure size, lookup, parsing,
normalization, address-conversion, or calculation helpers. Heap ownership,
allocation, synchronization, signal, and process lifecycle code remains
manual until separately proven.

### Phase 2 candidate pass A — heap free-list index

`get_free_list_index()` in `dlls/ntdll/heap.c` received one out-of-tree
candidate that replaces the generic bit-scan wrapper with a native compiler
`clz` intrinsic while preserving the zero case and all bin arithmetic. The
candidate was built with the actual ARM64 Wine flags. Its `ntdll.so` was
byte-identical to control (`e1959129...`), so it was recorded as
`PROFILED_NO_PROMOTION` rather than being staged or benchmarked as a claimed
speedup. The source and installed runtime were restored to their original
hashes, and the canonical-prefix P8 prepared-prefix gate passed all four
architectures with status 0.

Receipt: `docs/validation/ai-optimization-phase2-heap-index-20260803/RESULTS.md`.
This is a valid rejection, not evidence that the entire Phase 2 corpus is
complete; the remaining eligible files need separate hot-workload profiling.

## Phase 3 — WoW64 virtual memory correctness, then optimization

Protected files:

- dlls/wow64/file.c
- dlls/wow64/memory.c
- dlls/wow64/process.c
- dlls/wow64/security.c
- dlls/wow64/sync.c
- dlls/wow64/syscall.c
- dlls/wow64/system.c
- dlls/wow64/virtual.c
- dlls/wow64win/gdi.c
- dlls/wow64win/user.c

First prove the VM contract for x64 and i386/WoW64:

- reserve, commit, decommit, recommit, release, and address reuse;
- protection changes, partial unmaps, overlapping views, and file mappings;
- high host-address translation and guest-aperture pressure;
- concurrent map/protect/unmap pressure;
- Chromium/Electron reservation and decommit patterns;
- FEX generated-code mappings and invalidation.

Only after that contract is green may candidates be considered for pure page
lookup, interval arithmetic, generation comparison, protection lookup, or
non-mutating translation. Candidates may not add allocation in sensitive
callbacks or change transactional publication, rollback, stale-map handling,
guest/host ownership, or FEX invalidation.

Exit: no stale mapping, protection, address-reuse, or corruption evidence on
either guest architecture.

## Phase 4 — FEX and x86_64/i386 emulation

Files:

- dlls/xtajit64/cpu.c
- dlls/xtajit64/vkmt/context.c
- dlls/xtajit64/vkmt/dispatch.c
- dlls/xtajit64/vkmt/interp.c
- dlls/xtajit64/vkmt/jit.c

Initial treatment:

- cpu.c: candidate-only for measured pure backend helpers;
- interp.c: candidate-only for isolated instruction/flag helpers;
- context.c, dispatch.c, and jit.c: protected.

Test x86_64 and i386 guests for generated-code maps, invalidation,
protection, allocation reuse, exceptions, signal return, and nested process
loading. Do not alter dispatcher loops, executable-memory publication, JIT
code generation, context save/restore, or invalidation ordering.

### Phase 4 candidate pass A — interpreter width-mask helper

The pure `sz_mask()` helper in `dlls/xtajit64/vkmt/interp.c` was evaluated
out-of-tree with a constant mask table. Five direct x86_64 launches for the
candidate and matched control were all `rc=0` with the expected guest marker,
but the candidate median was 1.54% slower. The strict P0 wrapper also exposed
the current provider lifecycle-telemetry gap and was not treated as a green
performance result. The candidate was rejected, the canonical P8 provider was
restored, and the prepared-prefix P8 gate passed all four architectures.

Receipt: `docs/validation/ai-optimization-phase4-fex-mask-20260803/RESULTS.md`.
This pass does not authorize changes to FEX dispatch, JIT, context, mapping,
invalidation, or executable-memory paths.

## Phase 5 — Graphics, Metal, Vulkan, OpenGL, and CEF

Protected host-boundary files:

- dlls/opengl32/unix_thunks.c
- dlls/opengl32/unix_wgl.c
- dlls/opengl32/wgl.c
- dlls/user32/button.c
- dlls/win32u/class.c
- dlls/win32u/driver.c
- dlls/win32u/gdiobj.c
- dlls/win32u/hook.c
- dlls/win32u/message.c
- dlls/win32u/opengl.c
- dlls/win32u/vulkan.c
- dlls/win32u/window.c
- dlls/win32u/winstation.c
- dlls/winecoreaudio.drv/coreaudio.c
- dlls/winemac.drv/macdrv_main.c
- dlls/winemac.drv/opengl.c
- dlls/winemac.drv/window.c
- dlls/winevulkan/loader_thunks.c
- dlls/winevulkan/loader.c
- dlls/winevulkan/vulkan_thunks.c
- dlls/winevulkan/vulkan.c

Potential narrow candidates:

- dlls/dwrite/freetype.c
- dlls/win32u/freetype.c
- dlls/win32u/sysparams.c

Only pure text/geometry conversion, cache-key, immutable lookup, pixel, or
format-conversion helpers are eligible. Driver loading, host callbacks,
window/message dispatch, Vulkan/OpenGL procedure translation, presentation,
audio callbacks, and Metal transitions remain manual.

Required gates are DXMT, Vulkan/OpenGL/Metal paths, CEF x64 OSR startup and
deterministic pixel output, and clean shutdown. CEF i386 remains separately
reported rather than used to falsify the accepted x64 gate.

## Phase 6 — Networking, system, and runtime helpers

Potential candidate files, limited to pure helpers:

- dlls/msvcrt/locale.c
- dlls/winhttp/net.c
- dlls/ws2_32/protocol.c
- dlls/ws2_32/socket.c
- dlls/ws2_32/unixlib.c

The following remain manual-review until profiling identifies a safe leaf:

- dlls/crypt32/unixlib.c
- dlls/kernel32/process.c
- dlls/kernel32/sync.c
- dlls/kernelbase/process.c
- dlls/kernelbase/sync.c
- dlls/mscoree/mscoree_main.c
- dlls/msvcrt/main.c
- dlls/msvcrt/thread.c
- dlls/ntoskrnl.exe/instr.c
- dlls/secur32/schannel_gnutls.c

Crypto, TLS, synchronization, process startup, and instruction emulation must
not receive unsafe math, OpenMP, or opaque whole-file rewrites.

The existing x64 address-list sort contract now has a prepared-prefix path:
`scripts/probe-x64-address-list-sort.sh --prefix PATH`. Its canonical P8
receipt is `docs/validation/address-list-sort-p8-canonical-20260803/`; the
probe reuses the prefix, verifies it first, and does not run Wineboot or stage
providers in prepared mode.

## Phase 7 — Server-side synchronization and mapping

Files:

- server/inproc_sync.c
- server/main.c
- server/mapping.c
- server/msync.c
- server/thread.c

Prove MSync waiter registration, pulse tokens, manual/auto-reset pulse
behavior, WaitAll rollback, abandoned mutex ownership, cancellation, and
cross-process ordering first. Server linearization points and lock-held code
remain human-reviewed. Only pure non-mutating helpers may later become
candidates.

## Phase 8 — Bootstrap and tooling

Files:

- libs/winecrt0/arm64ec.c
- programs/wineboot/wineboot.c
- tools/makedep.c
- tools/wine/wine.c

These are lower priority. Profile them only for a specific startup or build
time objective. Do not optimize wineboot merely to make test setup faster;
the product runtime and prepared-prefix work are separate concerns.

## Phase 9 — Candidate generation and promotion loop

For each candidate function:

1. Copy the exact source hash into the ignored candidate workspace.
2. Generate one function-level candidate.
3. Compile with actual Wine target flags for every affected architecture.
4. Run focused tests, property tests, ASan/UBSan where supported, and TSan
   where the function is not signal/lock-sensitive.
5. Run the relevant integration gates and compare repeated medians and p95.
6. Reject candidates with any functional, ABI, sanitizer, architecture, or
   known performance regression.
7. Require a repeatable targeted improvement. The proposed default is at least
   5% on the targeted workload with no more than 1% regression elsewhere,
   unless a latency-critical path has an explicitly recorded alternative
   threshold.
8. Promote one small change in one nested Wine commit.
9. Record source hash, optimizer commit, flags, evidence, and result in the
   ledger and Inventory.md.

If profiling finds no safe or meaningful candidate, record
PROFILED_NO_SAFE_CANDIDATE. Every file must be audited, but every file does
not need to change.

## Phase 10 — Final acceptance and packaging

The optimized corpus must pass the applicable P8 gates on ARM64, ARM64EC,
x86_64, and i386/WoW64, including:

- process loading, loader, exceptions, and teardown;
- WoW64 VM contract;
- FEX generated-code and invalidation tests;
- MSync;
- DXMT and graphics rendering;
- CEF x64 OSR;
- browser and process-loading fixtures;
- P8 hotset/performance evidence.

Final records must include:

- function-level candidate ledger;
- accepted and rejected candidate history;
- source and optimizer hashes;
- reproducible build commands;
- before/after benchmark receipts;
- architecture gate receipts;
- updated Inventory.md;
- nested Wine commits for accepted source changes.

No candidate binary, cache, disposable prefix, or diagnostic log is a package
asset.

## Proposed execution order

1. Phase 0 baseline and source freeze.
2. Phase 1 function ledger for all 82 files.
3. dlls/ntdll/heap.c and pure dlls/ntdll/unix/* helpers.
4. WoW64 VM proof, without AI changes until the contract is green.
5. dlls/xtajit64/cpu.c and isolated interp.c helpers.
6. CEF/graphics boundary profiling and narrow conversion candidates.
7. Networking, locale, and other supporting helpers.
8. Final P8 cross-architecture promotion and inventory update.
