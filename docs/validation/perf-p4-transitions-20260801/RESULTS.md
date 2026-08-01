# P4 cross-architecture transition acceptance

Date: 2026-08-01

## Accepted change

WineVulkan now resolves the generated PE thunk locally and snapshots the host
instance/device procedure-availability surface in one Unix call when each
Vulkan object is created.  Subsequent `vkGetInstanceProcAddr` and
`vkGetDeviceProcAddr` queries use an immutable per-object bitmap instead of one
i386-to-ARM64 Unix call per function name.  Allocation failure safely falls
back to the original individual-query path.

The generated WineVulkan source and `make_vulkan` generator carry the same
contract.  The i386, x86_64, and ARM64X/ARM64EC PE modules plus the native
ARM64 `winevulkan.so` were rebuilt with targeted make rules.

## Measured transition reduction

The baseline was captured with the instrumented FEX provider before batching
in `build/perf-p4/unix-histogram-no-tso-20260801T053832/`.  The accepted result
is in `build/perf-p4/proc-batch-final-20260801T054757/`.

| Fixture | Baseline Unix calls | Accepted Unix calls | Reduction |
| --- | ---: | ---: | ---: |
| i386 DXGI | 72 | 37 | 48.6% |
| i386 D3D12 | 1,271 | 933 | 26.6% |
| i386 D3D11 | 767 | 462 | 39.8% |

The two D3D12 samples were identical at 933 calls.  The dominant eliminated
calls were individual instance/device procedure queries.  Host support remains
authoritative because the bitmap is produced with the same host Vulkan
`vkGetInstanceProcAddr` and `vkGetDeviceProcAddr` calls that the old path used.

FEX commit `f30858e15` adds opt-in correlated counters for ARM64EC transitions
and WoW64 syscalls, Unix calls, simulations, context operations, callbacks,
exceptions, and syscall/Unix-call IDs.  Counters are inactive unless
`VKMT_PERF_RUN_ID` is present.  Wine commit `f989b1f` implements the accepted
batching optimization.

## Correctness gates

All runs explicitly set these values to zero:

- `FEX_TSOENABLED=0`
- `FEX_VECTORTSOENABLED=0`
- `FEX_MEMCPYSETTSOENABLED=0`

The following passed with status 0 after the change:

- canonical i386 substrate, DLL/export load, DXGI factory/adapter, two D3D12
  device/queue/fence/copy/readback runs, and D3D11 clear/copy/readback;
- x86_64 entry plus DXVK D3D11 readback;
- one fresh prefix containing ARM64, ARM64EC, x86_64, and i386;
- the complete i386 WoW64 LoadLibrary, syscall return, TLS, context, SEH, APC,
  second-thread, callback, and thread-lifecycle contract.

The earlier apparent i386 stack regression was isolated to the P5 runner
omitting the explicit no-TSO environment.  The canonical provider and original
debug-sized fixture pass after the runner was corrected; no stack workaround
or smaller fixture was accepted.

## Gate result

P4 passes: representative graphics boundary transitions fell by 26.6-48.6%
without changing observable Windows behavior, enabling TSO, or involving
Rosetta.
