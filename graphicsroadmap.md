# VKMT P8 Graphics Completion Roadmap

This roadmap finishes VKMT's custom graphics stack rather than merely proving
that its DLLs load. MoltenVK, FEX, Wine, DXVK, vkd3d-proton, DXMT,
MetalSharp, and the WoW64 boundary are all custom or locally patched, so every
feature must be accepted from behavioral evidence against the actual promoted
runtime.

## Non-negotiable operating rules

1. **P8 only.** Do not use P6 labels, providers, receipts, or fallback
   binaries.
2. **One canonical prefix:**
   `build/probe-runs/phase-a-graphics-prefix`.
3. Probes reuse that prefix, never recreate it, and do not invoke Wineboot.
   They stage only the provider under test and record exact provider hashes.
4. An older backup binary must never be used to make a failing test pass.
   Source-built, promoted runtime artifacts are authoritative.
5. Every source fix must be promoted into the actual Wine/build tree before it
   is accepted; changing only the prefix is insufficient.
6. Test every applicable architecture independently:
   - ARM64;
   - ARM64EC;
   - x86_64 through the custom FEX/xtajit64 provider;
   - i386/WoW64 through the custom FEX/xtajit provider.
7. Acceptance runs force all FEX TSO controls off:

   ```text
   FEX_TSOENABLED=0
   FEX_VECTORTSOENABLED=0
   FEX_MEMCPYSETTSOENABLED=0
   ```

8. A feature is either behaviorally proven, correctly implemented and proven,
   explicitly disabled with a documented fallback, or reported as a real
   gap. Feature bits and DLL presence are never sufficient evidence.

## Phase 0 — Lock the P8 graphics infrastructure

### Work

Create one shared graphics execution layer with:

- canonical-prefix validation;
- architecture-to-provider mapping;
- exact staging manifests;
- provider hash verification;
- no-TSO environment enforcement;
- wineserver lifecycle handling;
- retained logs on failure;
- no prefix creation and no Wineboot.

Maintain separate provider profiles. DXVK and DXMT must never be mixed.

| Profile | Runtime |
|---|---|
| DXVK | `d3d9`, `d3d10`, `d3d11`, `dxgi` |
| vkd3d-proton | `d3d12`, `d3d12core`, `dxgi` |
| DXMT | `d3d10core`, `d3d11`, `dxgi`, `winemetal.dll`, `winemetal.so` |
| OpenGL | Wine OpenGL plus MetalSharp/SPIR-V-Cross |
| MoltenVK | Promoted Wine `libMoltenVK.dylib` |
| FEX | Current custom `xtajit.dll` and `xtajit64.dll` |

### TSO cleanup

Active graphics runners must remain zero-TSO. Legacy Java diagnostic scripts
that explicitly set `FEX_TSOENABLED=1` must be converted to internal
software-ordering tests, clearly quarantined as non-acceptance diagnostics, or
removed from the acceptance path. The final graphics gate must fail if an
active graphics or Java acceptance script enables TSO.

### Gate

Produce:

```text
docs/validation/graphics-infrastructure-p8/
  RESULTS.md
  capability.tsv
  staging-manifests/
  hashes.sha256
```

## Phase 1 — Finish FEX and WoW64 memory correctness

This phase comes first because D3D11, D3D9, CEF, Electron, and Java all rely
on the same guest mapping behavior.

### Scope

Audit and, where required, repair:

- `dlls/wow64/memory.c`;
- FEX guest-code map registration;
- executable-map invalidation;
- reserve/commit/decommit/recommit;
- partial unmaps;
- protection changes;
- overlapping views;
- file mappings;
- high-address host mappings;
- concurrent allocation pressure;
- stale mapping detection;
- W^X transitions;
- FEX generated-code invalidation.

Profile the current fixed registry before replacing it. If lookup, locking, or
correctness pressure warrants it, use a sparse/indexed model with 4 KiB guest
pages, pre-reserved leaves, host/state/protection/generation metadata, no heap
allocation in sensitive callbacks, explicit synchronization, and transactional
map/unmap publication.

### Required fixture

The WoW64 VM contract must cover:

- reserve/commit/decommit/recommit/release;
- partial protect/unmap;
- overlap ordering;
- address reuse;
- file sections/views;
- high-address translation;
- concurrent map/protect/unmap;
- Chromium-style reservation/decommit;
- FEX executable-map invalidation;
- Java code-cache allocation and invalidation.

### Gate

Both x64 and i386 must produce:

```text
WOW64_VM_CONTRACT_ALL_OK
FEX_INVALIDATION_NONZERO
NO_STALE_MAPPING
NO_CORRUPTION
FEX_TSO=0
```

No graphics workaround may replace this correctness gate.

## Phase 2 — Complete custom MoltenVK behavior

The current custom MoltenVK has narrow robust/null behavior proven, while
transform feedback and indirect-count remain disabled. The full goal requires
implementing them or retaining an explicit, justified limitation.

**Current P8 status (2026-08-03):** the direct ARM64 behavior gate passes and
the custom runtime is rebuilt/promoted, but the capability policy is still
truthful fallback rather than full feature completion. Nested source commit
`665b11e7` disables the old passthrough transform-feedback advertisement;
`docs/validation/moltenvk-behavior-p8-20260803/RESULTS.md` is the receipt.

### 2.1 Robust access and null descriptors

Expand the direct native tests to cover:

- storage buffers;
- storage images;
- null descriptors;
- out-of-bounds reads and writes;
- synchronization after OOB access;
- descriptor reuse;
- applicable buffer formats.

### 2.2 Transform feedback

Implement actual output capture in the custom MoltenVK path, not just state
tracking. Prove:

- captured vertex data;
- buffer contents;
- pause/resume;
- multiple streams;
- query counts;
- offsets;
- overflow behavior;
- synchronization;
- repeated capture cycles.

If Metal has no direct primitive, implement an explicit emulation path using
shader/output instrumentation and custom buffer management. Do not restore
the extension until captured bytes and counters are correct.

### 2.3 Indirect draw count

Implement and test:

- aligned count buffers;
- unaligned count rejection or fixup;
- zero counts;
- nonzero counts;
- count changes between submissions;
- command synchronization;
- graphics and compute variants.

### 2.4 Typed-buffer alignment

Implement offset fixups or precise rejection. Test aligned and misaligned
offsets, views crossing boundaries, and read/write correctness.

### Gate

Native ARM64 must produce actual output and counter evidence. Then exercise
the behavior through D3D11 and D3D12 consumers where applicable.

## Phase 3 — Stabilize and complete vkd3d-proton/D3D12

The current D3D12 path is the strongest: all four architectures pass
deterministic render/compute/readback. The ARM64/ARM64EC provider now avoids
both DXIL-SPIRV C++ TLS and vkd3d C PE-TLS x18 accesses.

**Current P8 status (2026-08-03):** the canonical fixture is rc=0 on ARM64,
ARM64EC, x86_64, and i386/WoW64 for VS/PS/CS, descriptor-table UAV, render
and compute output, barriers, texture/buffer copies, fence timeout/completion,
and removal-reason queries. A second device initialization passes on the three
64-bit lanes; i386's second `D3D12CreateDevice` entry faults after the first
lane completes and is recorded as `DEVICE_RECREATE_NOT_CLAIMED_I386_WOW64`.

### Remaining work

Add and prove:

- swapchain creation;
- present;
- resize;
- fullscreen/windowed transitions where possible;
- queue synchronization;
- fence timeout behavior;
- descriptor-table coverage;
- UAV/SRV/RTV transitions;
- device removal/recreation;
- texture-array and format coverage;
- additional DXIL shader variants;
- vkd3d-facing workloads.

Keep the ARM64-safe DXIL-SPIRV TLS implementation. Do not reintroduce
x18-relative C++ TLS into ARM64 or ARM64EC binaries.

### Gate

All four lanes must pass VS/PS, compute, render target, texture copy,
barriers, descriptors, queue/fence, and device recreation. Present/resize is
accepted when a display-backed lane is available.

## Phase 4 — Finish DXVK D3D11

### 4.1 Fix the current boundary

Minimize the ARM64EC/x86_64 structured-UAV failure across:

- structured-buffer creation;
- UAV stride;
- dispatch;
- UAV unbind;
- staging copy;
- map/readback;
- provider boundary;
- FEX/WoW64 pointer conversion.

Diagnose the latest ARM64 startup timeout separately from D3D11 device
creation. Keep the failing logs and do not convert `E_FAIL` into a pass using
known-boundary markers.

### 4.2 Complete D3D11

All four architectures must prove:

- device creation;
- VS/PS/CS compilation;
- structured and raw buffers;
- UAV/SRV;
- compute readback;
- texture upload/copy/readback;
- render target;
- blend/depth state;
- multiple render targets;
- map/unmap;
- synchronization;
- swapchain/present/resize;
- device-loss/recreation.

### 4.3 D3D10

Add a DXVK D3D10 contract for `d3d10core.dll`, device creation,
buffer/texture creation, shader load, draw, readback, and DXGI interaction.

### Gate

No architecture is accepted for D3D11 until the same fixture passes with its
matched DXVK provider.

## Phase 5 — Finish DXMT

DXMT remains a separate custom stack and must not be inferred from DXVK or from
bridge/factory loading alone.

### Scope

Prove and repair:

- ARM64EC `d3d11.dll`;
- ARM64EC `dxgi.dll`;
- `d3d10core.dll`;
- `winemetal.dll`;
- ARM64 `winemetal.so`;
- native device discovery;
- imported DXGI factory lifecycle;
- CHPE/loader routing;
- i386 PE loading through the ARM64 host bridge.

### Required lanes

1. Native WMT/Metal device discovery.
2. ARM64EC `D3D11CreateDevice`.
3. ARM64EC compute/readback.
4. ARM64EC render/readback.
5. DXGI swapchain/present/resize.
6. D3D10 core/device path.
7. i386/WoW64 device creation.
8. i386 compute/readback.
9. i386 render/readback.
10. Close/release/device recreation.

The i386 path uses the ARM64 host `winemetal.so`; no i386 Mach-O sidecar is
required or expected.

### Gate

Do not claim DXMT WoW64 support until the complete i386 device, compute, and
render sequence passes.

## Phase 6 — Finish DXVK D3D9

### Diagnose first

Reduce the current textured-render failure into independent fixtures:

1. fixed-function vertex/declaration path;
2. vertex-shader/pixel-shader path;
3. texture sampling;
4. render-target readback;
5. i386 pointer/handle conversion.

### Required coverage

- device creation;
- caps;
- texture/surface creation;
- lock/unlock;
- clear;
- fixed-function textured draw;
- shader textured draw;
- readback;
- present;
- resize;
- reset;
- lost-device behavior;
- i386/WoW64 object and pointer lifetime.

A clear or texture upload is not sufficient. The acceptance marker must
contain known expected pixels from a textured draw on every applicable
architecture.

## Phase 7 — Complete OpenGL 1.x–4.x through SPIR-V-Cross

### Offscreen contract

Produce real offscreen evidence for all four architectures covering:

- indexed VBO/EBO;
- texture upload/sampling/readback;
- FBO attachment and blit;
- uniforms;
- UBOs;
- synchronization;
- context sharing;
- shader compile/link diagnostics;
- GLSL 1.20 through 4.50;
- integer, float, texture, and framebuffer formats.

### Display contract

On a display-backed host, add:

- WGL context creation;
- visible window;
- swap/present;
- resize;
- framebuffer resize;
- context recreation;
- window-thread synchronization.

`NO_DISPLAY` is a valid environmental result but is not a visible-rendering
pass.

### Gate

Publish separate offscreen all-architecture and display-backed results, plus
an explicit unsupported API table.

## Phase 8 — FEX/Java graphics integration

Run the real graphics fixtures through the custom FEX providers with:

- all TSO settings zero;
- no hardware TSO request;
- no Rosetta fallback;
- no stale provider;
- no stale guest mappings;
- generated-code invalidation enabled;
- W^X transitions validated.

Exercise Java startup, Java code-cache pressure, CEF renderer allocations,
D3D11/D3D12 shader compilation, OpenGL shader translation, repeated process
creation/shutdown, and concurrent graphics helper processes.

The same provider hash and no-TSO proof must appear in every graphics receipt.

## Phase 9 — Cross-stack integration

After individual API gates are green, run integrated workloads for:

- DXVK D3D9;
- DXVK D3D11;
- vkd3d-proton D3D12;
- DXMT D3D11;
- OpenGL;
- CEF x64 rendering;
- CEF i386 diagnostics where supported;
- simultaneous graphics processes;
- shader-cache and GPU-cache reuse;
- process termination during compilation;
- device recreation after renderer restart.

This phase specifically checks interaction between FEX memory mappings, the
Wine loader, MoltenVK, DXVK, vkd3d-proton, DXMT, MetalSharp, wineserver/MSync,
and CEF/renderer processes.

## Phase 10 — Final P8 acceptance and packaging

Produce:

```text
docs/validation/graphics-final-p8/
  RESULTS.md
  capability.tsv
  architecture-matrix.tsv
  provider-hashes.sha256
  staging-manifest.tsv
  failure-boundaries.md
```

Update `Inventory.md`, `AGENTS.md`, `README.md`, `docs/GAPS.md`, and every
staging/build script. Replace stale P6 references with P8.

Every architecture must have an explicit row for MoltenVK, D3D9, D3D10,
D3D11, D3D12, DXMT, OpenGL, and FEX/Java integration. Each row must be
`PASS`, `NOT_APPLICABLE` with a reason, `EXPLICIT_UNSUPPORTED` with a precise
fallback, or `FAIL` with retained diagnostics.

The final runtime gate must use the actual promoted Wine tree and the canonical
prepared prefix. No old provider or backup binary may be used to manufacture a
green result.

## Phase completion discipline

At the end of each phase:

1. build the custom source;
2. promote the resulting runtime into the actual Wine/build tree;
3. verify hashes and architecture headers;
4. stage only the required files into the canonical prefix;
5. run targeted and all-architecture contracts;
6. retain logs and capability tables;
7. update `Inventory.md`, `AGENTS.md`, and relevant gap documentation;
8. commit only that phase's changes.

No phase is complete merely because a DLL loads or because a prefix can be
created. The completion criterion is reproducible behavior from the promoted
P8 runtime with FEX TSO disabled.
