# Phase 2 — NTDLL opt-in Steam marker scan

Date: 2026-08-03

## Candidate

`dlls/ntdll/unix/file.c::buffer_contains()` now uses `memchr()` to locate
the first marker byte and retains `memcmp()` for the exact match. It keeps
the original short-buffer and empty-needle semantics. No socket, atomic,
notification-state, read-completion, or TSO behavior changed.

The path is opt-in (`VKMT_STEAM_HANDOFF_NOTIFY=1`) and is not on ordinary
NTDLL read behavior unless the caller enables the Steam handoff notification.

## Validation

```text
VKMT_NTDLL_FILE_SCAN_EQUIVALENCE_OK runs=250000
VKMT_NTDLL_FILE_SCAN_BENCH size=4096 mode=0 control_ns=319000 candidate_ns=14000
VKMT_NTDLL_FILE_SCAN_BENCH size=4096 mode=1 control_ns=325000 candidate_ns=14000
VKMT_NTDLL_FILE_SCAN_BENCH size=65536 mode=0 control_ns=5357000 candidate_ns=177000
VKMT_NTDLL_FILE_SCAN_BENCH size=65536 mode=1 control_ns=5339000 candidate_ns=177000
VKMT_NTDLL_FILE_SCAN_BENCH size=1048576 mode=0 control_ns=91403000 candidate_ns=2799000
VKMT_NTDLL_FILE_SCAN_BENCH size=1048576 mode=1 control_ns=97953000 candidate_ns=2799000
VKMT_NTDLL_FILE_SCAN_OK
```

`mode=0` is an absent marker and `mode=1` places the marker at the end of
the buffer. `mode=2` is an immediate hit below the host clock's useful
resolution and is intentionally not used for a speed claim.

The test command was:

```text
scripts/probe-ai-ntdll-file-scan.sh
```

The actual ARM64 target was rebuilt with:

```text
make -C wine/build-ec -j4 dlls/ntdll/ntdll.so
```

The prepared canonical-prefix P8 gate then passed:

```text
P8_SINGLE_PREFIX_ARM64_OK
P8_SINGLE_PREFIX_ARM64EC_OK
P8_SINGLE_PREFIX_X86_64_OK
P8_SINGLE_PREFIX_I386_OK
P8_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
status=0
```

No prefix was created, reset, staged, or Wineboot-run for the prepared gate.

## Provenance

```text
source_sha256=732c5ef59e4fd2e19442e57cb4c0e6332f62c075cc2462c56e1ced775a92e3d1
ntdll_so_sha256=e3cd6e3c55a96ea5f47c7c9a24f3c268fecb15b0bdf43d6577aa4450b71aae89
nested_wine_commit=07df604e8f4e2f475bdd9983905cf98802905ee7
p8_evidence=docs/validation/ai-optimization-phase2-file-scan-20260803/p8/
```

This is one function-level accepted promotion. It is not evidence that the
remaining candidate rows are optimized; those still require their own
workload and semantic gates.
