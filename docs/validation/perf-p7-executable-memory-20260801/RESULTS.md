# P7 executable-memory acceptance — 2026-08-01

All runs used native ARM64 host executables with
`FEX_TSOENABLED=0`, `FEX_VECTORTSOENABLED=0`, and
`FEX_MEMCPYSETTSOENABLED=0`.

## Quantitative gate

| provider | flush requests | flush invalidation passes | tracker invalidation passes |
| --- | ---: | ---: | ---: |
| instrumented two-pass baseline | 2 | 4 | 13 |
| single-pass candidate | 2 | 2 | 13 |

Flush-maintenance reduction: **50.00%**. Both SMC processes returned status 0
and executed the updated instruction stream. The tracker-pass total remains
13 because the removed legacy pass bypassed the common tracker; the dedicated
flush-pass counter captures that duplicated work explicitly.

## Correctness gates

- i386 Java JIT: C1 and Xcomp passed executable-memory transitions, 257
  instruction-cache flushes, 128 live patches, GC, deoptimization, and
  exception-resume checks.
- i386 system contract: LoadLibrary, syscall return, TLS, context get/set,
  SEH, APC, callback return, second thread, and repeated lifecycle passed.
- Cross-process/no-TSO: x86_64 and i386 ordering, waits, conditions, APCs,
  threads, and 128/128 child processes passed; eight CDN transfers per guest
  architecture matched the native reference hash.
- Graphics: i386 DXGI enumeration, D3D11 clear/copy/readback, and D3D12
  device/queue/fence/copy/readback passed through MoltenVK/Metal.
- Canonical single prefix: ARM64, ARM64EC, x86_64, and i386 all returned
  status 0 after provider promotion.

Promoted i386/WoW64 provider SHA-256:
`e030b4d33909d6158bf1a8521f948a4ddde85da8368e2d605ced301ff14ffee1`.
