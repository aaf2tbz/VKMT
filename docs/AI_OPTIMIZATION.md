# VKMT C AI optimizer integration

VKMT now has a pinned, out-of-tree integration point for
[`sebyx07/c-ai-optimizer`](https://github.com/sebyx07/c-ai-optimizer).

The execution plan and complete 82-file ledger are maintained separately in
`docs/AI_OPTIMIZATION_ROADMAP.md` and `docs/AI_OPTIMIZATION_LEDGER.tsv`.
The current P8 all-architecture baseline is retained in
`docs/validation/ai-optimization-p8-phase0-baseline-20260803/`.

## Pin and commands

The optimizer is pinned to:

```text
c6f96df0ec9973a4cbdb7b015b1fd106c815ad89
```

The checkout is intentionally under the ignored `third_party/` tree. Use:

```sh
scripts/vkmt-c-ai-optimizer.sh setup
scripts/vkmt-c-ai-optimizer.sh inventory
scripts/vkmt-c-ai-optimizer.sh smoke
scripts/vkmt-c-ai-optimizer.sh prepare
scripts/vkmt-c-ai-optimizer.sh inventory-all
scripts/vkmt-c-ai-optimizer.sh prepare-all
scripts/vkmt-c-ai-optimizer.sh disposition
scripts/vkmt-c-ai-optimizer.sh verify
```

`prepare` creates a timestamped, immutable candidate workspace under
`build/c-ai-optimizer-candidates/`. It copies the high-priority custom Wine
inputs and records their SHA-256 values. It never writes to
`wine/wine-11.12`.

`inventory-all` and `prepare-all` operate on the complete 82-file ledger,
including files marked manual-review or generated/no-rewrite. Preparing a
file is not permission to transform or promote it.

`disposition` validates that every ledger row marked `candidate` has exactly
one row in `docs/AI_OPTIMIZATION_DISPOSITION.tsv`. Boundary/triage rows are
required to carry an evidence reference and a next action; they are not
treated as optimization wins.

## Why this is candidate-only

The upstream project is a proof of concept built around isolated numeric C
functions. Its default CMake configuration requires OpenMP and unconditionally
adds `-march=native -mavx -ffast-math`. That is unsuitable for VKMT's native
Apple ARM64 host, ARM64EC/x86_64 guest paths, i386/WoW64, exception handlers,
loader locks, signal frames, and FEX dispatcher ABI. The VKMT smoke command
therefore omits x86 AVX flags on ARM64 and validates the optimizer's scalar
plus OpenMP fallback only.

The manifest marks ABI-sensitive files `manual-only`. They may be profiled,
but no whole-file AI rewrite or OpenMP insertion is allowed. Candidates are
limited to isolated leaf helpers after profiling proves that the function is
hot and that its memory ordering, aliasing, exception, and reentrancy behavior
are irrelevant to the contract.

## Promotion contract

No candidate may replace a Wine source file until it has:

1. a before/after benchmark from a VKMT workload, not the optimizer demo;
2. identical focused behavior on ARM64, ARM64EC, x86_64, and i386 where the
   file participates in that architecture;
3. no ABI, SEH, lock-order, callback, FEX invalidation, or MSync regression;
4. a source hash and reproducible candidate record; and
5. a measurable win that survives the P8 smoke, WoW64 VM, CEF x64, and MSync
   gates.

The optimizer's own benchmark claims are not VKMT evidence. Current setup
evidence is retained in
`docs/validation/c-ai-optimizer-vkmt-setup-20260803/RESULTS.md`.

The first file-level loader candidate was evaluated against paired control
measurements and rejected as `PROFILED_NO_PROMOTION`; its receipt is
`docs/validation/ai-optimization-candidate-loader-hash-20260803/RESULTS.md`.
The installed Wine tree was restored to the pre-candidate source after the
measurement.
