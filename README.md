# VKMT

vkd3d-proton on Metal, directly: run Direct3D 12 titles on macOS through the
pipeline **D3D12 → vkd3d-proton (Vulkan) → MoltenVK (Metal)**, with MoltenVK
extended to guarantee the Vulkan feature surface vkd3d-proton requires.

## Status

Phase 0–1 complete, Phase 2 (fatal-gap closure) complete:

- vkd3d-proton 3.1.0 cross-builds on macOS (`d3d12.dll`, `d3d12core.dll`)
- MoltenVK 1.4.2 builds (Xcode 27 beta, Apple M4)
- Runtime feature audit: **all nine vkd3d-proton hard requirements now pass**
  (`scripts/smoke_vk`): robustBufferAccess2, robustImageAccess2, nullDescriptor,
  transformFeedbackQueries, BDA, mirror-clamp, dynamicRendering,
  synchronization2, maintenance4

See [PLAN.md](PLAN.md) for the phased plan, [docs/GAPS.md](docs/GAPS.md) for
the full gap audit, and [docs/TRANSFORM_FEEDBACK.md](docs/TRANSFORM_FEEDBACK.md)
for the stream-output emulation design.

## Layout

- `third_party/` — fetched sources (not committed; run `scripts/fetch.sh`)
- `patches/` — VKMT patches against upstream MoltenVK
- `scripts/` — fetch / build / smoke-test
- `docs/` — audits and design docs

## Quick start

```sh
scripts/fetch.sh                # clone + patch MoltenVK, vkd3d-proton, DXVK(ref)
scripts/build-moltenvk.sh       # needs Xcode (DEVELOPER_DIR override supported)
scripts/build-vkd3d-proton.sh   # needs mingw-w64, meson, ninja, glslang
```

## Roadmap

- [x] Close the 3 init-fatal gaps (robustness2 ×2, nullDescriptor, transform feedback)
- [ ] Transform-feedback real emulation (vertex-stage compute pre-pass)
- [ ] WSI/present polish; Wine prefix integration test with real D3D12 titles
- [ ] DXR → Metal raytracing; mesh shaders; VRS
- [ ] Early-win extensions: conditional rendering, conservative raster,
      custom border color, drawIndirectCount
