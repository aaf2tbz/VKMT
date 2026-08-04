# VKMT graphics capability truth — P8

Updated 2026-08-03 from direct contract receipts. This is a capability
boundary document, not a claim that every row is green.

The Phase 0 infrastructure gate is
`docs/validation/graphics-infrastructure-p8/RESULTS.md`. It verifies the
receipt-backed canonical graphics prefix without Wineboot, checks the
architecture headers and hashes of the promoted custom FEX, DXVK,
vkd3d-proton, DXMT, and MoltenVK artifacts, and rejects nonzero TSO settings
in active graphics acceptance runners. It is staging evidence only; it does
not replace the behavioral rows below.

The FEX/WoW64 prerequisite gate is
`docs/validation/graphics-phase1-wow64-p8/RESULTS.md`. The nested Wine memory
source fix is commit `f108c09`; it repairs derived low-alias fallback and
complete reservation retirement after interval splitting. The x64 and i386
VM contracts now pass high-host/top-down allocation, guest-aperture pressure,
reserve/commit/decommit/recommit, protection, reuse, overlapping views,
concurrent mapping pressure, executable reuse, and correlated i386 FEX
invalidation with all TSO settings zero.

## Requirement matrix

| Area | Behavioral evidence | Result |
|---|---|---|
| MoltenVK null descriptors | Native ARM64 null storage-buffer read returns zero | **PASS — narrow** |
| MoltenVK robust buffer/image access | Native ARM64 direct OOB storage-buffer and storage-image reads return zero | **PASS — narrow** |
| MoltenVK transform feedback | Direct capture/counters/queries are not available | **NOT ADVERTISED**; extension and feature bits disabled |
| MoltenVK indirect count | Count-buffer alignment/zero/nonzero/synchronization not proven | **NOT ADVERTISED** |
| MoltenVK typed-buffer alignment | Device reports 16-byte storage/uniform alignment | **QUERY_ONLY**; unaligned offsets are not claimed |
| D3D11 device/VS/PS/CS/compute/texture/render | `d3d11-graphics-contract` | Latest receipt: i386 completes the full lane; ARM64EC/x86_64 create the device/shaders but retain a bounded structured-UAV compute readback gap; ARM64 latest rerun timed out during provider startup and is not counted green |
| D3D11 swapchain/present/resize | Same fixture | **NOT APPLICABLE** on current no-display host |
| D3D11 device-loss/recreation | No safe injected loss fixture | **NOT CLAIMED** |
| D3D12 queue/fence/copy/readback | Existing no-DXGI probe and P8 fixture | **PASS — all four lanes** |
| D3D12 render/barrier/RTV/readback | `d3d12_graphics_contract.c` | **PASS — all four lanes**, after the ARM64-safe DXIL-SPIRV TLS fix and rebuilt ARM64/ARM64EC providers |
| D3D12 swapchain/present/resize | No-display host and no window lane in fixture | **NOT CLAIMED** |
| D3D9 device/texture/surface | `d3d9_contract.c` | Device and texture upload/readback pass; fixed-function and shader textured draw/readback remain unavailable in the current headless DXVK route |
| D3D9 present/resize/reset | `d3d9_contract.c` | Visible present is no-display; reset is downstream of draw gap |
| OpenGL indexed/texture/FBO/uniform/sync/share/UBO/present | `opengl_extended_contract.c` | Four processes execute; current host records `NO_DISPLAY`, so display-dependent rows are not passes |
| ARM64EC DXMT D3D11CreateDevice | `probe-dxmt-arm64ec.sh` now includes full lane | **PENDING EXECUTION**; WMT-only bridge is not sufficient |

## Receipts

- MoltenVK: `docs/validation/moltenvk-behavior-p8-20260803/RESULTS.md`
- D3D11: `docs/validation/d3d11-graphics-contract-p8-20260803/RESULTS.md`
- D3D12: `docs/validation/d3d12-graphics-contract-p8-20260803/RESULTS.md`
- D3D9: `docs/validation/d3d9-contract-p8-20260803/RESULTS.md`
- OpenGL: `docs/validation/opengl-extended-contract-p8-20260803/RESULTS.md`

All new contract runners use the existing receipt-backed prefix, do not call
Wineboot, set `FEX_TSOENABLED=0`, `FEX_VECTORTSOENABLED=0`, and
`FEX_MEMCPYSETTSOENABLED=0`, and retain nonzero lanes and unsupported APIs in
their capability tables.

## Immediate gaps

1. Diagnose the x64/ARM64EC D3D11 structured-UAV compute-readback boundary
   while preserving the passing ARM64/i386 lanes. The current fixture uses a
   bounded event/nonblocking-map path and does not turn the failure into a
   pass. The most recent ARM64 rerun also needs an isolated startup diagnosis;
   its earlier receipt had passed before repeated canonical-prefix sessions.
2. Provide a display-backed D3D9/OpenGL/DXGI swapchain fixture, or retain the
   explicit headless fallback policy.
3. Implement a real MoltenVK transform-feedback capture path before restoring
   `VK_EXT_transform_feedback`.
4. Execute the updated DXMT standard D3D11 gate and add compute/render
   readback to it before claiming DXMT WoW64 coverage.

## ARM64 pipeline fix

The ARM64/ARM64EC D3D12 pipeline crash was not a D3D12 feature limitation. It
was DXIL-SPIRV C++ `thread_local` lowering emitting an x18-relative access
inside `dxil_spv_set_thread_log_callback`; x18 is reserved at VKMT's Wine/FEX
boundary. `subprojects/dxil-spirv/util/vkmt_thread_local.hpp` now uses the
Win32 TLS API on Windows while retaining native C++ TLS elsewhere. The rebuilt
providers are installed in `third_party/vkd3d-proton/install-arm64` and
`install-arm64ec`, and the four-lane D3D12 receipt records pixel readback
`64,128,191,255` with rc=0.
