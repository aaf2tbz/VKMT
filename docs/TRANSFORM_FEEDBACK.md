# Transform Feedback Emulation on MoltenVK — Stage 2 Design

Status: **design only** (Stage 1, the passthrough advertisement of
`VK_EXT_transform_feedback`, is implemented and documented at the bottom).

## Problem

Metal has no stream-output / transform-feedback hardware stage. vkd3d-proton
requires `VK_EXT_transform_feedback` with `transformFeedbackQueries == VK_TRUE`
to create a device at all (libs/vkd3d/device.c), and uses it to implement D3D12
stream output (`D3D12_SO_DECLARATION_ENTRY`, `CreateStreamOutputPipelineState`,
`SOSetTargets`, `DrawAuto`/counters). Stage 1 makes device creation succeed and
runs non-SO workloads perfectly, but games that actually capture varyings get
nothing written to their SO buffers. Stage 2 implements real capture.

## Design: vertex stage as a compute pre-pass

The approach mirrors MoltenVK's existing tessellation emulation
(`MVKCmdDraw::encode` tess paths, `MVKCommandUse::kMVKCommandUseTessellationVertexTessCtl`,
`MVKMetalComputeCommandEncoderState::prepareRenderDispatch`), which already runs
the vertex (and tess-control) stage as a Metal compute dispatch feeding a
post-processed vertex buffer into a fixed-function render pass.

### 1. Pipeline compile time

When a `VkGraphicsPipeline` is created with a
`VkPipelineRasterizationStateStreamCreateInfoEXT` in its rasterization state
`pNext` chain (or, for vkd3d-proton's usage, whenever the SO state indicates
captured varyings — see "vkd3d-proton specifics" below), the pipeline is marked
as a *stream-output pipeline* and records:

- `rasterizationStream` (we advertise `geometryStreams = false`, so it must be 0;
  pipeline creation can reject otherwise with `VK_ERROR_FEATURE_NOT_PRESENT`-style
  validation error, or simply ignore since VUID forbids non-zero),
- the set of captured outputs. **Note:** vanilla Vulkan determines captured
  varyings from `VkPipelineRasterizationStateStreamCreateInfoEXT` plus the
  SPIR-V `XfbBuffer`/`XfbStride`/`Offset` decorations emitted by glslang when the
  shader is compiled with transform-feedback layout qualifiers. vkd3d-proton
  instead compiles DXIL→SPIR-V via dxil-spirv with SO declaration metadata; the
  captured varying set must be extracted from the SPIR-V execution-mode /
  decoration data by SPIRV-Cross reflection (`SPIRVariable` decorations
  `DecorationXfbBuffer`, `DecorationXfbStride`, `DecorationOffset`).

### 2. SPIRV-Cross changes (External/SPIRV-Cross)

Confirmed: **no MSL transform-feedback support exists**. The only
`xfb`/`transform feedback`/`stream out` hits are in `spirv_glsl.cpp` (GLSL
backend), `spirv.hpp`/`spirv_common.hpp` (decoration enums), and `main.cpp`
(reflection CLI). `spirv_msl.cpp` never reads `DecorationXfbBuffer` /
`DecorationXfbStride` / `DecorationOffset`.

Required work in `spirv_msl.cpp` / `CompilerMSL`:

- New option `CompilerMSL::Options::capture_transform_feedback` (plus a
  `ShaderTransformFeedbackInfo` in `MSLShaderInterface` describing up to
  `kMVKMaxTransformFeedbackBufferCount` (4) output buffers: per-buffer stride,
  and per-captured-output (variable id, offset, xfb buffer index)).
- When enabled for a vertex shader compiled **as a compute kernel** (the same
  "vertex-as-compute" mode the tessellation pre-pass already uses
  (`is_tessellation_shader()`-adjacent paths, `MSL_VERTEX_ATTR` / stage-in
  struct handling), each captured output is additionally written to
  `device` address space: `xfb_buffers[i][atomic_counter[i] * stride + offset] = value`.
- The write index comes from a per-buffer atomic counter bound as
  `device atomic_uint*` — see §3.
- The pre-pass kernel must also write the ordinary vertex outputs (position and
  all varyings) into the indirect vertex buffer it produces, exactly as the
  tessellation vertex pre-pass does today, so the subsequent fixed-function
  render pass re-runs a trivial "passthrough" vertex shader. Whether the real
  render pass keeps the original vertex shader (and SO capture only happens in
  the pre-pass) or uses a passthrough shader is an open choice; the tessellation
  infrastructure already demonstrates the passthrough route
  (`MVKGraphicsPipeline` tess-related `getMTLComputePipelineState` paths).

### 3. Counter buffers

`vkCmdBeginTransformFeedbackEXT` binds per-buffer counter buffers holding the
current write offset (in *bytes* for the Vulkan extension, unlike D3D12's
filled-size counters — vkd3d-proton adapts).

- Each Vulkan counter buffer (a `VkBuffer` range) maps to a 4-byte
  `atomic_uint` in an MTLBuffer. MoltenVK keeps the *Vulkan-visible* counter
  buffers as the single source of truth: the pre-pass kernel does
  `atomic_fetch_add_explicit(&counter, 1)` per emitted vertex and uses the
  returned value as the output slot.
- On `vkCmdBeginTransformFeedbackEXT` with `pCounterBuffers == NULL`, counters
  conceptually start at 0; with non-NULL counter buffers, the captured offset
  resumes. Because the counter values live in device memory already, both cases
  work without host reads: NULL counters bind a MoltenVK-internal zeroed
  scratch counter buffer (per command encoder, from
  `MVKCommandResourceFactory`/command encoding pool), non-NULL binds the
  app's buffer directly.
- Multi-buffer XFB: each of the up-to-4 SO buffers has its own counter; the
  SPIR-V `XfbBuffer` decoration selects which counter a captured output uses.

### 4. Draw execution with an active SO pipeline

Inside `MVKCmdDraw*::encode` (and indexed/indirect variants), when
`_vkGraphics._transformFeedbackActive` and the bound pipeline is an SO pipeline
(Stage 1 already tracks `_xfbBuffers`, `_xfbCounterBuffers`,
`_transformFeedbackActive` in `MVKVulkanGraphicsCommandEncoderState`):

1. Switch to the compute encoder (`getMTLComputeEncoder` with a new
   `MVKCommandUse`, e.g. `kMVKCommandUseTransformFeedbackVertex`), exactly like
   the tessellation pre-pass switches encoders mid-render-pass.
2. Dispatch the vertex-as-compute kernel over the draw's vertex range
   (instances handled like the tess pre-pass's instance expansion). The kernel
   writes captured varyings into the bound `_xfbBuffers` at offsets advanced by
   the per-buffer atomic counters, and writes the full vertex output record
   into a scratch indirect vertex buffer.
3. Return to the render encoder and issue the real draw sourcing the scratch
   vertex buffer (tessellation's `needsVertexAdjustment` /
   `vtxAdjmts` paths in `MVKCmdDraw.mm` are the template for this fixup).

Rasterization-discard interaction: D3D12 SO-only passes use
`D3D12_RASTERIZER_DESC` with no render targets; in Vulkan this maps to
`rasterizerDiscardEnable`. When discard is on, step 3 is skipped entirely and
only the compute capture runs — this is the cheap and common SO case.

### 5. `vkCmdDrawIndirectByteCountEXT` (D3D12 `DrawAuto` / SO-as-input)

The draw's vertex count is `counterValue / vertexStride`. Since the counter
lives in device memory, do what DXVK does for `drawIndirectCount`:

- A tiny compute "args patching" kernel (new pipeline in
  `MVKCommandResourceFactory`, alongside
  `newCmdDrawIndirectTessConvertBuffersMTLComputePipelineState`) reads the
  counter buffer, computes `vertexCount = counter / vertexStride`, and writes a
  `MTLDrawPrimitivesIndirectArguments` struct into a scratch buffer.
- The draw then issues `drawPrimitives:indirectBuffer:` from the patched args.
- This replaces the Stage-1 stub, which currently logs a warning and skips the
  draw.

### 6. Queries (`VK_QUERY_TYPE_TRANSFORM_FEEDBACK_STREAM_EXT`)

`transformFeedbackQueries = true` is already advertised.

- `primitivesWrittenQuery`: read back the counter delta (end counter − begin
  counter) × vertices-per-primitive for the stream's topology. Implement as a
  compute reduction writing into the query pool's visibility/result buffer,
  or — simpler first cut — patch the counter value into the query result
  buffer with the same args-patching kernel used in §5.
- `primitivesGeneratedQuery` (pre-SO): can be approximated by the input vertex
  count when no clipping-dependent accuracy is required; a correct
  implementation needs a counting pass and can be deferred.

### 7. State tracking already in place (Stage 1)

`MVKVulkanGraphicsCommandEncoderState` holds:

- `_xfbBuffers[kMVKMaxTransformFeedbackBufferCount]` — bound SO buffers,
- `_xfbCounterBuffers[kMVKMaxTransformFeedbackBufferCount]` — bound counters,
- `_transformFeedbackActive`.

Stage 2 consumes this state in the draw commands; no new Vulkan-visible state
is needed. `MVKCmdBindTransformFeedbackBuffers`, `MVKCmdBeginTransformFeedback`,
`MVKCmdEndTransformFeedback` already record all bindings at encode time.

## Task breakdown

1. **SPIRV-Cross**: parse `DecorationXfbBuffer/Stride/Offset` in reflection;
   `CompilerMSL` option + codegen writing captured outputs to device buffers
   via an atomic counter in vertex-as-compute mode. (Largest piece.)
2. **MoltenVK pipeline**: plumb stream state from
   `VkPipelineRasterizationStateStreamCreateInfoEXT` + SPIRV-Cross reflection
   into `MVKGraphicsPipeline`; compile SO pre-pass MSL via the new option.
3. **Command encoding**: new `MVKCommandUse`, draw-command branch for SO
   pre-pass + scratch vertex buffer handoff (model on tessellation paths in
   `MVKCmdDraw.mm`).
4. **Counters**: internal zeroed scratch counters for the NULL-counter case;
   buffer binding plumbing into the pre-pass kernel's argument buffer.
5. **Args patching**: `vkCmdDrawIndirectByteCountEXT` compute patch pass +
   indirect draw (replace Stage-1 skip-stub).
6. **Queries**: transform-feedback-stream query pools via counter deltas.
7. **Testing**: vkd3d-proton stream-output tests (libs/vkd3d tests,
   `test_stream_output`), then a real D3D12 SO workload.

## Stage 1 reference (implemented)

- `VK_EXT_transform_feedback` advertised for all platforms (10.11+ macOS,
  8.0+ iOS) — chosen over Apple-GPU-only gating because the passthrough
  emulation needs no Metal capability; capture quality does not depend on GPU
  family. Files: `MVKExtensions.def`, `MVKDevice.mm` (features: transformFeedback
  = true, geometryStreams = false; properties: spec-minimum limits,
  transformFeedbackQueries = true, transformFeedbackDraw = true), entry points
  in `vulkan.mm`/`MVKInstance.mm`, command classes in `MVKCmdDraw.h/.mm`,
  state in `MVKCommandEncoderState.h/.mm`.
- Behavior: buffers/counters tracked; draws run normally without capture;
  one-time `MVKLogWarn` on first `vkCmdBeginTransformFeedbackEXT`;
  `vkCmdDrawIndirectByteCountEXT` logs once and skips.
- vkd3d-proton impact: `d3d12_device_caps_init` marks stream output supported;
  only games that actually bind SO targets and render with SO pipelines are
  affected (their captured buffers stay unwritten). Everything else is exact.
