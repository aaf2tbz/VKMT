# FEX Phase 4 receipt — P8 runtime

Date: 2026-08-03

The FEX/WoW64 contract ran from the canonical prefix with TSO disabled. It
covered x86_64 and i386 guest mapping, executable reuse, concurrent mapping
pressure, address reuse, generated-code memory, and invalidation.

Result: `WOW64_VM_CONTRACT_ALL_OK`, status 0.

The i386 provider emitted a correlated nonzero maintenance-summary invalidation
count. The ARM64EC x64 provider did not emit a component FEX row for this
fixture; that telemetry gap is recorded as unavailable rather than treated as
proof. Full details and receipts are in
`docs/validation/ai-optimization-wow64-msync-phase3-20260803/RESULTS.md`.

No AI candidate was promoted in FEX `cpu.c`, `context.c`, `dispatch.c`,
`interp.c`, or `jit.c`. The interpreter/dispatcher boundary remains protected
until a workload-specific profile identifies a pure leaf function.
