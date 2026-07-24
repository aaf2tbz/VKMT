# VKMT — vkd3d-proton on Metal, directly

## Goal

Run Direct3D 12 titles on macOS by combining:

```
D3D12 API calls ──► vkd3d-proton (D3D12 → Vulkan)
                  ──► MoltenVK (Vulkan → Metal)
                  ──► Metal driver
```

This is the same proven pipeline as Apple Game Porting Toolkit's D3DMetal and
CodeWeavers CrossOver. VKMT's differentiator: upstream, open, and focused on
closing the MoltenVK gaps that vkd3d-proton requires — "guaranteeing" the
translation instead of hoping the Vulkan subset lines up.

## What we have

- `third_party/vkd3d-proton` — D3D12-on-Vulkan translation layer (D3D12 API,
  DXGI bits it owns, DXIL→SPIR-V via bundled `dxil-spirv`, and
  D3D12 shaders compiled to SPIR-V). Submodules: Vulkan-Headers, SPIRV-Headers,
  dxil-spirv, etc.
- `third_party/MoltenVK` — Vulkan-on-Metal implementation. `fetchDependencies`
  pulls SPIRV-Cross, SPIRV-Tools, glslang, Vulkan-Headers/Tools, cereal.
- `third_party/dxvk` — reference only (D3D9–11). Not in the critical path, but
  useful for shared Wine/DXGI idioms if VKMT later covers pre-12 APIs.
- Prior art worth studying on this drive: `DXMT-Finisher-Research-20260712`
  (DXMT takes the D3D11→Metal direct route; many of its Metal-side solutions
  transfer to our MoltenVK work).

## Known gaps (vkd3d-proton requirements vs. stock MoltenVK)

vkd3d-proton has a documented minimum Vulkan feature set; several of its
heavy-use paths are weak or missing in MoltenVK:

1. **Bindless / descriptor indexing** — vkd3d-proton is fundamentally bindless
   (raw VA descriptor heaps). MoltenVK supports `VK_EXT_descriptor_indexing`
   via Metal argument buffers, but tier limits, update-after-bind, and
   mutable descriptor types need auditing against vkd3d-proton's demands.
2. **Stream output** — D3D12 SO maps to `VK_EXT_transform_feedback`.
   MoltenVK has historically not supported it (Metal has no direct equivalent;
   needs emulation via compute pass + argument-buffer feedback).
3. **DXR raytracing** — `VK_KHR_ray_tracing_pipeline` is unimplemented in
   MoltenVK. Metal 3+ has native RT (acceleration structures, intersection
   queries). Big work item; map RT pipeline → MPS/MTL raytracing APIs.
4. **Geometry shaders** — unsupported by MoltenVK. vkd3d-proton needs them for
   some titles. Emulation path: Metal mesh/object shaders (Apple7+/Metal 3)
   or compute expansion.
5. **Tessellation** — MoltenVK supports it via compute pre-pass, but
   correctness/perf against vkd3d-proton workloads must be validated.
6. **Shader semantics** — SPIRV-Cross MSL gaps that matter here: precise math,
   BCD integer patterns from dxil-spirv output, wave/subgroup ops,
   demote-to-helper-invocation, sampler feedback.
7. **Memory model / sync** — vkd3d-proton uses UAV barriers and
   `VK_KHR_buffer_device_address`; check Metal memory-barrier granularity and
   BDA emulation correctness.
8. **WSI / present** — no DXGI swapchain on macOS; need a VKMT WSI shim
   (`VK_KHR_surface`/`swapchain` → `CAMetalLayer` + present pacing, HDR,
   fullscreen).

## Phases

### Phase 0 — Build & environment (now)
- [x] Repo skeleton on external SSD (`/Volumes/AverySSD/VKMT`)
- [ ] Clone vkd3d-proton (+ submodules), MoltenVK (+ fetchDependencies), DXVK (ref)
- [ ] Toolchain: Xcode + Command Line Tools, mingw-w64 cross compiler
      (vkd3d-proton builds Windows PE DLLs: `d3d12.dll`, `d3d12core.dll`),
      Meson/Ninja, Homebrew deps (`brew install mingw-w64 meson ninja glslang`)
- [ ] Build MoltenVK (`make macos`) → `MoltenVK.xcframework`
- [ ] Cross-build vkd3d-proton (`./package-release.sh` path or meson cross file)
- [ ] Hello-triangle smoke test under Wine/macOS with VK_LOADER debug on

### Phase 1 — Gap audit
- [ ] Script MoltenVK's `VkPhysicalDevice` report vs vkd3d-proton's required
      feature/extension list (`libs/vkd3d/device.c` minimum requirements)
- [ ] Run vkd3d-proton's test suite where buildable; catalog failures by gap
- [ ] Produce `docs/GAPS.md` with per-gap severity and owner

### Phase 2 — Core correctness ("guarantee" work)
- [ ] Descriptor indexing / argument-buffer tier parity; fix mutable/update-after-bind
- [ ] BDA + memory-barrier correctness fixes in MoltenVK
- [ ] SPIRV-Cross MSL fixes for dxil-spirv output patterns (upstream PRs where possible)
- [ ] WSI shim: `CAMetalLayer` surface, present queue, vsync/pacing

### Phase 3 — Feature extension (the D3D12-for-MoltenVK avenue)
- [ ] Transform feedback / stream output emulation (compute feedback pass)
- [ ] DXR: `VK_KHR_ray_tracing_pipeline` → Metal RT mapping (largest item)
- [ ] Geometry shader emulation (mesh shaders on Apple silicon)
- [ ] Sampler feedback, subgroup completeness, misc `VK_EXT_*` vkd3d wants

### Phase 4 — Integration & testing (plug in to test at the end)
- [ ] VKMT installer: MoltenVK ICD + vkd3d-proton DLLs into a Wine prefix
- [ ] Test matrix: vkd3d-proton tests → VKCTS/Vulkan samples → real D3D12 titles
- [ ] Perf pass: GPU frame capture in Xcode, argument-buffer residency, pipelines

## Non-goals (for now)

- D3D9–11 (DXVK/DXMT territory)
- Windows-on-Arm translation (out of scope; x86 titles still need Wine's WoW64)
- Upstreaming everything immediately (we PR upstream when stable, but VKMT
  carries patches as needed)

## Repo layout

```
VKMT/
├── PLAN.md
├── third_party/
│   ├── vkd3d-proton/
│   ├── MoltenVK/
│   └── dxvk/            # reference
├── patches/             # our patches against upstream (applied via script)
├── scripts/             # fetch, apply-patches, build, package
└── docs/                # GAPS.md, design notes
```
