# VKMT Product Completion Roadmap

## Operating principles

- No CI requirement. Validation remains reproducible through local, staged,
  targeted runners and retained evidence receipts.
- A feature is complete only with implementation, deterministic test,
  applicable architecture coverage, retained evidence, and a reusable runner.
- Preserve known-good behavior while expanding coverage. Do not make broad
  FEX, Wine, or MoltenVK updates without a contract test identifying the gap.
- Test-only orchestration hooks must be opt-in, ABI-safe, and never provide
  production timing-workaround semantics.

## 1. Shared validation and prepared-prefix infrastructure

This is the highest-leverage foundation: it removes repeated prefix setup,
makes results comparable, and prevents false positives from missing runtime
pieces.

### 1.1 Generic prefix lifecycle runner

Implement a reusable runner:

```sh
scripts/vkmt-prefix create  --profile core|graphics|browser|managed|full --prefix PATH
scripts/vkmt-prefix verify  --prefix PATH
scripts/vkmt-prefix warm    --prefix PATH
scripts/vkmt-prefix run     --prefix PATH -- command.exe
scripts/vkmt-prefix reset   --prefix PATH
scripts/vkmt-prefix destroy --prefix PATH
```

Profiles:

| Profile | Required staged components |
| --- | --- |
| core | Wine prefix, FEX providers, host libraries, WoW64 support, GStreamer closure, environment contract, GPU cache and hotset |
| graphics | core plus MoltenVK, DXVK, vkd3d-proton, DXMT where supported, MetalSharp runtime |
| browser | graphics plus CEF, Chromium fixture assets, WebView2, Electron assets, Gecko, and TLS roots |
| managed | core plus Wine Mono, Java/JRE/JDK runtime, and managed fixtures |
| full | All supported components and diagnostic fixtures |

Each prefix should contain:

```text
prefix/.vkmt/receipt.json
prefix/.vkmt/staged-files.manifest
prefix/.vkmt/environment.sh
prefix/.vkmt/wineboot.status
prefix/.vkmt/cache-state.json
```

The receipt must record VKMT/Wine/FEX/graphics component identities, host
architecture, staged provider hashes, runtime closure hashes, Wine prefix
version, cache and hotset identity, installed roots, and Wineboot status.

Required behavior:

- `create` stages dependencies, creates the prefix, runs Wineboot once,
  restages anything Wineboot changes, and writes a receipt.
- `verify` detects missing, stale, or incompatible staged state.
- `warm` performs narrow warm-up workloads without treating them as proof.
- `run` rejects incomplete/stale prefixes unless explicitly overridden for
  diagnosis.
- Tests accept `--prefix PATH`; fresh-prefix mode remains for bootstrap
  testing.

Migrate first:

- `scripts/probe-p6-single-prefix-architectures.sh`
- `scripts/probe-msync.sh`
- `scripts/probe-dxmt-arm64ec.sh`
- `scripts/probe-cef-runtime.sh`
- `scripts/probe-perf-p6-gpu-cache.sh`
- managed Java/Wine Mono probes
- networking/browser fixture probes

## 2. Architecture matrix and evidence

Every component should state intended support:

| Architecture | Required baseline |
| --- | --- |
| ARM64 | Native Wine/loader/process/runtime behavior |
| ARM64EC | Native/translated interoperability, CHPE redirection, callback and unwind correctness |
| x64 | WoW64/FEX execution, PE loading, graphics/browser/managed behavior |
| i386 | WoW64/FEX execution, address-space pressure, legacy graphics/browser compatibility |

P6 remains a focused all-architecture loader/lifecycle regression probe. P8 is
the accepted final runtime baseline: it adds the measured hot-set contract,
identity-checked staging, integrated launch, and a fresh four-architecture
status-0 matrix. P6 is never release acceptance by itself.

Standard evidence layout:

```text
docs/validation/<component>-<date>/
  RESULTS.md
  environment.txt
  prefix-receipt.json
  commands.txt
  ARM64/
  ARM64EC/
  x86_64/
  i386/
```

Each result must identify command, prefix receipt, architecture, exit status,
required markers/artifacts, exclusions, and whether it is acceptance,
diagnostic, or exploratory. Timeouts, signals, wrapper success, and partial
markers are not acceptance passes.

## 3. MSync

MSync has focused work and all-architecture validation for:

- server-managed event waiter registration;
- pulse-specific wake tokens;
- exact non-latching PulseEvent behavior;
- WaitAll rollback bookkeeping;
- abandoned-mutex rollback restoration;
- deterministic opt-in test hooks.

Maintain it by adding stress coverage for repeated manual/auto pulse,
pulse-before-wait non-latching, wake/set/reset races, abandoned mutex retries,
and recursively pre-owned mutexes. Run this gate after changes to ntdll,
wineserver synchronization, WoW64 wait machinery, or FEX signal/exception
behavior. Preserve shared ABI assertions.

## 4. WoW64 virtual memory: `dlls/wow64/memory.c`

This is a major compatibility area for i386, Chromium/Electron allocation,
graphics applications, and FEX-generated code.

### 4.1 Contract to prove

Validate:

- high host-address allocations and guest aperture pressure;
- reserve/commit/decommit/recommit;
- protection changes;
- overlapping views and partial unmaps;
- address reuse;
- file mappings;
- concurrent allocation/mapping pressure;
- FEX generated-code maps and invalidation;
- Chromium/Electron reservation/decommit patterns.

### 4.2 Candidate implementation direction

Profile before replacing the existing registry. If lookup/locking or
correctness pressure warrants it, introduce a sparse page-granular indexed
mapping model:

- 4 KiB guest-page lookup;
- two-level sparse guest address map;
- static/pre-reserved leaf allocation;
- host base, state, protection, and generation metadata;
- no heap allocation in sensitive callbacks;
- explicit synchronization/reentrancy rules;
- transactional map/unmap update ordering.

Potential benefits are bounded mapping lookup, explicit partial-unmap state,
stale association detection, and stable FEX mapping/protection data.

### 4.3 Tests

Add/extend a WoW64 VM contract fixture for x64/i386 guest modes:

- reserve, commit, decommit, recommit, release, reuse;
- partial protect and unmap;
- section/view mappings;
- overlap ordering;
- high-address translation;
- concurrent map/protect/unmap;
- Chromium-like allocator stress;
- FEX guest-code mapping and invalidation.

Acceptance: correct faults/protection, no stale mappings or corruption, and
no regressions in P6 i386, DXMT i386, Electron ia32, or browser fixtures.

## 5. FEX, process loading, and transitions

### 5.1 Compatibility contract

Document the local FEX base revision, local commits, patch ownership,
behavior contracts, cache assumptions, and performance-sensitive paths.
Treat upstream update work as a controlled compatibility project.

### 5.2 Process/loader contract suite

Implement all-applicable-architecture tests for:

- `CreateProcess` and `NtCreateUserProcess`;
- command line, environment, CWD, executable lookup;
- inherited handles, redirected pipes, consoles;
- suspended startup/resume and exit cleanup;
- LoadLibrary/GetProcAddress/forwarders/delay loads;
- loader lock/reentrancy;
- TLS/FLS and thread lifecycle;
- APC/callback paths;
- ARM64EC CHPE routing;
- exception/unwind/callback transitions across FEX and ARM64EC.

### 5.3 Runtime-image cache safety

Create cold/warm/corrupt/stale cache tests covering repeated process lifecycle,
JIT invalidation, DLL load/unload, graphics startup, Java JIT/GC, and browser
subprocesses. Reintroduce deliberately excluded CRT images only one at a
time with graphics/browser/managed regressions.

### 5.4 Transition optimization

Profile real workloads: CEF, WebView2, Electron x64/ia32, Steam/launchers,
Java, DXMT, and i386 graphics. Use transition histograms to optimize only
proven hot boundaries.

## 6. Core Wine functional substrate

### 6.1 Networking and WinSock

Promote existing socket experiments into a contract suite:

- IPv4/IPv6 loopback and DNS/address ordering;
- `SIO_ADDRESS_LIST_SORT`;
- nonblocking connect;
- event select/rearm, select/poll/WSAPoll;
- overlapped I/O and async lifetime;
- parallel connections and close races;
- TLS fragmentation/partial reads/writes;
- proxy environment handling where supported.

Prioritize x64/i386, then all applicable architectures.

### 6.2 TLS and trust

Replace certificate-bypass acceptance with a deterministic local trust
fixture:

- locally trusted valid root and hostname;
- expired/untrusted certificate rejection;
- intermediate chains;
- WinHTTP and WinINet;
- CEF/Chromium and WebView2.

Ignore-certificate-errors remains diagnostic-only.

### 6.3 UI, COM, callbacks, and fonts

Build a contract suite for COM apartments, STA message pumping, cross-thread
callbacks, controller/environment completion, nested loops, window lifetime,
and DirectWrite enumeration/layout/shaping/fallback. Use CEF/WebView pixel
checks to validate actual text output. Investigate and validate changes in
`dlls/dwrite/freetype.c` and `dlls/win32u/freetype.c`.

## 7. Browser and application hosts

### 7.1 CEF/Chromium

Current evidence includes CEF exports and selective diagnostic/candidate CDP
markers, but canonical release-style C0 evidence did not publish DevTools in
the required window. This is not yet promoted standard-exit acceptance.

Sequence:

1. Browser prepared-prefix closure.
2. Standard startup contract: child processes, DevTools endpoint, clean exit.
3. CDP semantic contract: navigation, trusted HTTPS, script/DOM, input,
   audio where practical, screenshot checksum, deterministic teardown.
4. Explicit architecture policy: validate x64 graphics path; keep i386
   software-only limitations visible until equivalent support exists.
5. OSR: render buffers, input, resize, dirty rectangles, deterministic pixels.
6. Subprocess robustness: crash/restart, multiple instances, cache/profile
   isolation.

### 7.2 WebView2

Move bootstrap proof to full application proof:

- environment/controller callbacks return;
- WebView creation/navigation;
- script callback;
- trusted HTTPS;
- host/web messaging;
- resize/input;
- clean shutdown;
- deterministic DOM or screenshot output.

Trace COM apartment state, callback marshaling, message-loop behavior,
window handles, and cross-thread waits. Do not mask callback failure with
timeouts.

### 7.3 Electron

Keep Electron x64 as a strong deterministic regression workload. Expand it
with multi-window, renderer/GPU lifecycle, packaged startup, and profile
behavior.

For ia32: first minimize/reproduce its decommitted-allocation failure, prove
the WoW64 memory contract, then add startup/rendering acceptance and expand
behavior only after that.

## 8. Graphics roadmap

### 8.1 Capability truthfulness

Every nontrivial advertised feature needs behavioral proof. For partial
features, implement correctly, disable/limit exposure, or document a precise
fallback policy. Feature bits alone are not proof.

### 8.2 MoltenVK

Add direct behavioral fixtures for robust access, null descriptors, transform
feedback, indirect draw count, and typed-buffer alignment.

Transform feedback must capture actual output. Test buffer contents,
pause/resume, streams, query counts, and offsets. Implement an emulation path
or stop advertising it if correctness cannot be delivered.

For indirect count, test count-buffer alignment, zero/nonzero counts, and
synchronization.

### 8.3 D3D9, OpenGL, D3D11, and D3D12

D3D9 needs device creation, texture/surface, clear, textured draw, readback,
present, resize, and reset tests.

OpenGL needs vertex/index paths, texture upload/readback, FBOs,
uniforms/UBOs, context sharing, visible present/resize, and synchronization.

Expand D3D11/D3D12 with deterministic shader/device/resource tests, compute
and render readback, texture copies, swapchain/present, command queue/fence,
descriptor/barrier behavior, and DXVK/vkd3d-facing workloads.

## 9. DXMT

ARM64EC DXMT already has proof beyond a staging bridge: Metal device discovery,
imported DXGI factory lifecycle, and loader/CHPE routing. A D3D11 device
fixture exists, but canonical acceptance currently uses the narrower WMT path.

Therefore next steps are:

1. Promote ARM64EC `D3D11CreateDevice` to a standard gate.
2. Add D3D11 compute/readback.
3. Add render target/readback.
4. Add DXGI swapchain/present/resize.
5. Add device-loss/recreation if feasible.
6. Establish i386 runtime acceptance: staging, process/load, device,
   compute/readback, then render/present.

Do not claim WoW64 DXMT support until the i386 runtime path has evidence.

## 10. D3DCompiler

Current proof includes x64 compilation to DXBC and i386 D3D11 consumption with
deterministic compute readback. It is not complete D3DCompiler coverage.

Add `test/d3dcompiler_contract.c` and all-architecture execution for:

- VS/PS/CS compilation;
- flags/macros/include handlers;
- compile failures and diagnostics;
- `D3DCompileFromFile`, including Unicode/path behavior;
- preprocess and disassembly;
- reflection metadata;
- 43/46/47 DLL behavior;
- explicit unsupported API HRESULTs;
- D3D11/D3D12 consumption of generated DXBC where applicable.

Publish an architecture/API capability table and do not conceal known stubs.

## 11. Apple Silicon optimization program

Measure before optimizing. For each workload retain cold/warm prefix/cache,
startup latency, process count, FEX transitions, CPU time, memory high-water,
shader/cache timings, cache hit/miss data, and output checksums.

Priority workloads:

1. CEF startup/CDP;
2. WebView2 lifecycle;
3. Electron x64 and later ia32;
4. Java startup/JIT/GC;
5. DXMT D3D11;
6. DXVK/vkd3d;
7. Steam/launcher startup.

Candidates:

- reduce measured FEX boundary crossings;
- improve runtime-image cache reuse/safety;
- optimize WoW64 mapping lookup/invalidation;
- avoid redundant staging and loader work;
- preserve native ARM64 execution;
- optimize Metal lifetime/synchronization only with correctness coverage;
- version shader-cache warming/eviction through prefix receipts;
- assess thread QoS/affinity only after measured evidence.

## 12. Execution order

### Phase A: foundation

1. Implement `scripts/vkmt-prefix`.
2. Add receipts, verification, profiles, and standard evidence structure.
3. Migrate P6 and MSync.

### Phase B: core contracts

4. Process/loader/cross-architecture suite.
5. WinSock/TLS suite.
6. WebView2 callback-return investigation.
7. WoW64 VM stress and Chromium-style allocator reproducer.

### Phase C: memory and FEX

8. Profile `dlls/wow64/memory.c`.
9. Implement indexing/transaction improvements only if justified.
10. Validate FEX cache/process/transition behavior.

### Phase D: browser/application host

11. CEF standard DevTools/startup gate.
12. CEF trusted HTTPS/CDP/pixel/subprocess gate.
13. WebView2 full lifecycle contract.
14. Electron x64 regression expansion.
15. Electron ia32 recovery after VM proof.

### Phase E: graphics

16. D3DCompiler contract.
17. DXMT ARM64EC device/compute/render proof.
18. DXMT i386 proof.
19. D3D9/OpenGL render and present coverage.
20. MoltenVK feature-truthfulness, transform feedback, and indirect-count work.
21. DXVK/vkd3d application-facing regressions.

### Phase F: performance

22. Benchmark the prepared workload matrix.
23. Optimize measured FEX/WoW64/Apple Silicon bottlenecks.
24. Retain before/after performance and functional evidence.

## 13. Product-ready definition

Do not claim broad compatibility from smoke tests alone. A release-quality
claim requires:

| Area | Minimum proof |
| --- | --- |
| Architectures | P6 plus architecture-specific functional workloads |
| MSync | Deterministic pulse/rollback stress |
| Process loading | Child creation, loader, pipes, callbacks, teardown |
| FEX | Cache safety, exceptions, transitions, nested processes |
| WoW64 memory | Mapping/protection/reuse/concurrency/Chromium-style stress |
| Networking/TLS | IPv4/IPv6/events/order/trusted success and rejection |
| CEF | Standard startup, trusted HTTPS, CDP, pixels, subprocesses, teardown |
| WebView2 | Returning callbacks, navigation/script/input/teardown |
| Electron | Robust x64; ia32 after VM contract is green |
| D3DCompiler | Compile/preprocess/reflection plus runtime shader output |
| DXMT | ARM64EC render proof and i386 proof before WoW64 claims |
| Graphics | Deterministic render/readback/present and truthful feature exposure |
| Apple Silicon performance | Measured improvement with functional output proof |

The priority order is intentional: reusable staged prefixes, process/loader
correctness, WoW64 memory, FEX transitions, networking/TLS, and browser
callback behavior unlock more applications than isolated rendering features.
