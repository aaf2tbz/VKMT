# D3D12 graphics contract — P8

Prefix: `/Volumes/AverySSD/VKMT/build/probe-runs/phase-a-graphics-prefix`

| Architecture | rc | status |
|---|---:|---|
| arm64 | 0 | PASS |
| arm64ec | 0 | PASS |
| x86_64 | 0 | PASS |
| i386 | 0 | PASS |

## Coverage and boundaries

- The fixture covers generated VS/PS/CS DXBC, queue/allocator/list, descriptor-table UAV, RTV descriptor heap, graphics/compute pipelines, clear/draw/dispatch, explicit UAV/RTV state barriers, texture/buffer readback, fence timeout/completion, and clean device-removal-reason queries.
- A second device initialization is proven on ARM64, ARM64EC, and x86_64. The i386/WoW64 thunk currently faults on a second D3D12CreateDevice entry after the first lane completes; it is recorded as `DEVICE_RECREATE_NOT_CLAIMED_I386_WOW64`, not converted into a pass.
- Swap-chain/present/resize and injected device-loss remain separate window/lifecycle lanes.
- Nonzero lanes remain visible in `capability.tsv`; this is not a green gate unless every lane is zero.
- All lanes use matched rebuilt providers, FEX TSO settings of zero, and the existing prefix without wineboot.
