# VKMT Gap Audit — vkd3d-proton 3.1.0 vs MoltenVK 1.4.2

Evidence gathered 2026-07-24 from `third_party/vkd3d-proton` (cited `vkd3d/…`)
and `third_party/MoltenVK` (cited `mvk/…`). MoltenVK 1.4.2 advertises Vulkan 1.4
(`mvk/MoltenVK/MoltenVK/Utility/MVKEnvironment.h:65`).

## How vkd3d-proton defines requirements

- No hard-required device extension strings — all ~90 extensions in
  `optional_device_extensions[]` are opportunistic (`vkd3d/libs/vkd3d/device.c:66-167`,
  checks at `:449` and `:3103`).
- Hard requirements: minimum Vulkan API 1.3 (`vkd3d/include/vkd3d.h:53`,
  enforced at `device.c:3535`), and feature checks in
  `vkd3d_init_device_caps()` (`device.c:3240-3486`) — every `E_INVALIDARG` is init-fatal.

## FATAL gaps (device creation fails today)

| Requirement | vkd3d evidence | MoltenVK status | mvk evidence |
|---|---|---|---|
| VK_EXT_transform_feedback: `transformFeedbackQueries` | `device.c:3292-3296` | **Missing entirely** (D3D12 stream output) | absent from `MVKExtensions.def`; ext never chained |
| VK_EXT_robustness2: `robustBufferAccess2` + `robustImageAccess2` | `device.c:3429-3434` | `robustBufferAccess2 = false` unconditionally; image2 only on Apple GPUs | `MVKDevice.mm:635-638` |
| VK_EXT_robustness2: `nullDescriptor` | `device.c:3436-3440` | `false` unconditionally | `MVKDevice.mm:638` |

Satisfied hard checks (no work needed): vertex attribute divisor, single-texel
alignment, `samplerMirrorClampToEdge` (macOS OK), `shaderDrawParameters`,
VK_KHR_push_descriptor, maintenance5/6, all Vulkan 1.3 features
(dynamicRendering, synchronization2, maintenance4).

## Optional-but-important (compatibility ceiling)

| Extension / feature | vkd3d use | MoltenVK status |
|---|---|---|
| VK_KHR_acceleration_structure + ray_tracing_pipeline + ray_query + RT maintenance1 + deferred_host_ops + opacity_micromap | DXR tiers 1.0–1.2 (`device.c:9885-9959`) | **Missing** — no RT code in tree |
| VK_EXT_mesh_shader | SM 6.5+ mesh shaders (`device.c:10029`) | **Missing** (SPIRV-Cross in this fork has MSL mesh-shader support; not exposed) |
| VK_EXT_descriptor_indexing (runtime arrays, partial bind, update-after-bind, variable count) | bindless tier 3 | **Supported**; full 1e6 limits only at argument-buffer Tier 2 (`MVKDevice.mm:196-205,863-867`) |
| bufferDeviceAddress | GPUVA, SM 6.6+ | Supported, macOS 13+ (`MVKDevice.mm:214`) |
| Subgroup ops (rotate/ballot/quad/maximal reconvergence) | wave ops | Mostly supported on Apple GPUs; note 1.4.2 "disable non-working quad control flow" |
| VK_KHR_fragment_shading_rate | VRS tiers 1/2 | **Missing** |
| VK_EXT_conditional_rendering | predication | **Missing** |
| VK_EXT_conservative_rasterization | ConservativeRasterizationTier | **Missing** |
| VK_EXT_custom_border_color | static samplers | **Missing** |
| VK_EXT_depth_clip_enable | depth clip control | **Missing** (has depth_clip_control, different ext) |
| VK_KHR_draw_indirect_count (`drawIndirectCount`) | ExecuteIndirect | **Disabled** (`MVKDevice.mm:2833`) |
| VK_EXT_shader_image_atomic_int64 / shaderBufferInt64Atomics | int64 atomics | **Missing** |
| VK_EXT_graphics_pipeline_library / shader_module_identifier / mutable_descriptor_type / descriptor_buffer / memory_priority / pageable_device_local_memory / image_sliced_view_of_3d / cooperative_matrix / float8 | optional perf/correctness paths | **Missing** |
| Sparse residency (tiled resources tier 3) | options.TiledResourcesTier | Not supported; vkd3d degrades gracefully (`device.c:3261-3266`) |
| VK_EXT_extended_dynamic_state2/3 | dynamic states | Both advertised; individual bits partially emulated (vkd3d disables most at `device.c:3346-3372`) |
| VK_EXT_hdr_metadata, memory_budget, fragment_shader_interlock, present_id/wait, swapchain_maintenance1, calibrated_timestamps, texel_buffer_alignment, external_memory_host, shader_stencil_export, line_rasterization | misc | **Supported** |
| Sampler feedback (OPTIONS7) | `device.c:6013` | Plausible (`shaderResourceMinLod` on Apple/Mac1); needs runtime verification |
| Vendor exts (NV_*, AMD_*, NVX_*, MESA_*, VALVE_*) | vendor perf paths | All missing (expected on macOS) |
| `shaderInt64` | Int64ShaderOps | Supported on Apple GPUs/Mac1 |

## Config gates to remember

- Argument-buffer Tier 2 (Apple7+/Mac2) → full bindless limits; config
  `useMetalArgumentBuffers` (`MVKConfigMembers.def:81`).
- BDA requires macOS 13+ (`MVKFoundation.cpp:139`); MoltenVK refuses Vulkan
  ≥1.3 instances without it (`MVKInstance.mm:330`).
- `wideLines` needs `useMetalPrivateAPI` (`MVKDevice.mm:2769`).
- MoltenVK 1.4.2 minimum deployment: macOS 12.0.

## Runtime notes (2026-07-24, Wine integration findings)

- **winevulkan extension filtering**: Wine's Unix-side vulkan driver only
  forwards extensions in its built-in list. MetalSharp's wine-11.5 build lacks
  VK_EXT_transform_feedback, VK_EXT_robustness2, and
  VK_EXT_texel_buffer_alignment entirely (`strings winevulkan.so` → 0 hits),
  so vkd3d-proton under Wine sees none of the features we enabled natively.
  Probe failures cascade: coopmat proc load → TF check → texel alignment →
  robustness2. Short-term: `patches/vkd3d-proton-vkmt-wine-compat.patch`
  demotes the TF/texel-alignment checks to WARN and makes the coopmat proc
  optional. Proper fix: native arm64 Wine 11.12 build (`scripts/build-wine.sh`)
  where we control the winevulkan extension list.
- **Texel buffer alignment is a real MoltenVK gap too**: natively, MoltenVK
  reports 16-byte `storageTexelBufferOffsetAlignment` (Metal
  `minimumTextureBufferAlignment`), failing vkd3d's single-texel check even
  without Wine filtering. Typed buffer views with byte offsets not divisible
  by 16 will misbehave until MoltenVK gains offset emulation.

## Priority order (severity × effort)

1. **robustness2: `robustBufferAccess2` + `nullDescriptor`** — fatal, medium
   effort. Options: SPIRV-Cross robustness instrumentation for buffers, or
   a justified "lie" where Metal argument-buffer runtime already bounds-checks
   + null-descriptor emulation in argument-buffer encoding. vkd3d refuses to
   drop robustness (`device.c:3409-3421`).
2. **VK_EXT_transform_feedback** — fatal, high effort. No Metal equivalent;
   emulate stream output with a compute feedback pass + `transformFeedbackQueries`
   via pipeline statistics emulation. Alternative short-term: patch vkd3d to
   disable stream output (breaks SO-using games).
3. **DXR stack** — biggest workstream. Metal 3 RT (MTLAccelerationStructure,
   intersection functions) maps reasonably; MTL4 in macOS 26 improves fit.
4. **VK_EXT_mesh_shader** — high value; SPIRV-Cross MSL mesh support already
   exists in this fork, work is exposing the Vulkan ext + pipeline stages.
5. **VK_KHR_fragment_shading_rate** — tier 1 emulation likely feasible.
6. **Early wins (bounded, independent):** conditional_rendering,
   conservative_rasterization, custom_border_color, depth_clip_enable,
   drawIndirectCount (compute pass to patch counts).
7. Sparse/tiled tier 3 and pipeline-library niceties — opportunistic.

Bottom line: three checkboxes (robustness2 × 2, transform feedback) stand
between MoltenVK and vkd3d-proton device creation; after that, DXR, mesh
shaders, and VRS define the game-compatibility ceiling.
