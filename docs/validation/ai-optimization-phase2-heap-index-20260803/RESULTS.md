# Phase 2 candidate receipt — NTDLL heap free-list index

Date: 2026-08-03

This is a candidate-only Phase 2 pass. It does **not** promote a source
change. The candidate replaces the generic `BitScanReverse` call in
`get_free_list_index()` with the compiler's native `clz` intrinsic on GCC or
Clang and keeps an explicit zero case. The function's bin arithmetic and
limits are unchanged.

## Disposition

`PROFILED_NO_PROMOTION — compiler-equivalent output`

The candidate and control `ntdll.so` files are byte-identical under the actual
ARM64 Wine build flags, so there can be no runtime speed difference to claim.
The installed source and binary were restored and verified after the probe.
No candidate binary was copied into the prefix.

| Artifact | SHA-256 |
| --- | --- |
| Control `wine/build-ec/dlls/ntdll/ntdll.so` | `e1959129169227d89e0a884eff9d51d39aefd6f77f41d69bb5ad6cf9a4348e` |
| Candidate `ntdll.so` | `e1959129169227d89e0a884eff9d51d39aefd6f77f41d69bb5ad6cf9a4348e` |
| Restored installed `ntdll.so` | `e1959129169227d89e0a884eff9d51d39aefd6f77f41d69bb5ad6cf9a4348e` |
| Restored `dlls/ntdll/heap.c` | `90381483700e7171c768857e7bee7c7e35d637b69efac0eed710a07d0838a8b9` |

## Evidence

- Candidate build and restoration: `build-status.txt`, `build.log`, and
  `restore-build.log` in the ignored candidate workspace
  `build/c-ai-optimizer-candidates/phase2-heap-index-20260803/`.
- The candidate workspace contains both binary hashes and the control source;
  it is not a package input.
- Prefix verification: `prefix-verify.log`.
- Prepared-prefix P8 gate: `p8/status.txt`, `p8-output.log`, and the
  architecture logs under `p8/`.

The current canonical prefix was reused. No Wineboot, prefix creation,
provider staging, or prefix replacement was performed by this candidate pass.
The P8 gate returned:

```text
P8_SINGLE_PREFIX_ARM64_OK
P8_SINGLE_PREFIX_ARM64EC_OK
P8_SINGLE_PREFIX_X86_64_OK
P8_SINGLE_PREFIX_I386_OK
P8_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
status=0
```

The all-architecture result validates the restored runtime, not a promoted
heap candidate. The candidate is rejected because it produced no distinct
machine code; a future heap optimization must first show a different binary
and then beat the P8 workload gate without changing allocator semantics.

## Commands

```sh
make -C wine/build-ec dlls/ntdll/ntdll.so -j4
scripts/vkmt-prefix verify --prefix build/probe-runs/phase-a-graphics-prefix
FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
  scripts/probe-p8-single-prefix-architectures.sh \
  --prefix build/probe-runs/phase-a-graphics-prefix \
  --evidence-dir docs/validation/ai-optimization-phase2-heap-index-20260803/p8
```
