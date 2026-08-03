# AI optimization Phase 0/1 baseline — P8 providers

Date: 2026-08-03

This receipt establishes the baseline before any AI-generated candidate is
promoted. It reuses the existing canonical prefix and the installed Wine
build; it does not create a prefix or run Wineboot in prepared-prefix mode.

## Source and runtime identity

| Item | Value |
| --- | --- |
| Wine source HEAD | `14c236a84fdbe133ab234b486648276d40783680` |
| Wine release base | `996020f410e7a1aa2dd6b44cf740854ea524d31a` |
| Existing Wine worktree diff SHA-256 | `95f51d58050040dc2aa1699479ab61b936945f9d7128b8d7b7adebd71c01ed0b` |
| c-ai-optimizer | `c6f96df0ec9973a4cbdb7b015b1fd106c815ad89` |
| Full 82-file ledger SHA-256 | `9f526af93bd840c1fa3474ab1f65259a679045cc7679f1657597dfb2cbe8855b` |
| Host | native Apple ARM64; Rosetta false |
| Prefix | `build/probe-runs/phase-a-graphics-prefix` |
| Provider runner | `scripts/probe-p8-single-prefix-architectures.sh` |
| FEX TSO controls | all zero |

Important runtime hashes:

| Artifact | SHA-256 |
| --- | --- |
| `wine/build-ec/wine` | `334122ba9c93fdc9624fe2ef7138ef6c4000b7bb9ab25e7af3e388ba1d9dbd5d` |
| `wine/build-ec/server/wineserver` | `82b35e96bd449382ca1df262bd493781b638cd74fc1070bc67fcbd17a90ddee7` |
| `wine/build-ec/dlls/ntdll/ntdll.so` | `b59ce0775439fa19a438973df0be94dcb2a6ae749ed94d08e54e05ab300aab97` |
| `wine/build-ec/programs/wineboot/aarch64-windows/wineboot.exe` | `939478679896dc14b754c564dadfb1392cd7fb63aa5d89f889b50eb7c8bfaa1e` |
| `wine/build-ec/dlls/wow64/aarch64-windows/wow64.dll` | `cd534da4ec125c292bede66e5b7bf6a91eb5ce4c025db7bb0a0df77d3b129a39` |
| `wine/build-ec/dlls/wow64win/aarch64-windows/wow64win.dll` | `8703ca51aaa5ec5f1e0859f46835add0d4e247cfda0b055f82504ef1978c9113` |
| P8 ARM64EC provider | `cccc70a4dd598371ed11c5a7979ca2ecff66a9849ba8086421a69054890c8c5f` |
| P8 ARM64/i386 provider | `ac512105b5feb85227f2814deb77de603d73ff4713ee60045b23e51c2276f386` |

## Architecture gate

Command:

```sh
FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
  scripts/probe-p8-single-prefix-architectures.sh \
  --prefix "$PWD/build/probe-runs/phase-a-graphics-prefix" \
  --evidence-dir "$PWD/docs/validation/ai-optimization-p8-phase0-baseline-20260803"
```

Result:

```text
P8_SINGLE_PREFIX_ARM64_OK
P8_SINGLE_PREFIX_ARM64EC_OK
P8_SINGLE_PREFIX_X86_64_OK
P8_SINGLE_PREFIX_I386_OK
P8_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
status=0
```

## Startup baseline

The P0 runner used five status-0 samples in the persistent warm-guest state
for each guest architecture, with the existing prefix and all TSO controls
disabled:

| Guest | Median | P95 | Samples |
| --- | ---: | ---: | ---: |
| x86_64 | 45.773 ms | 50.479 ms | 5/5 rc=0 |
| i386/WoW64 | 375.669 ms | 378.925 ms | 5/5 rc=0 |

Raw receipts are `x86_64-summary.tsv`, `i386-summary.tsv`, the corresponding
`runs.tsv`, `phases.tsv`, and `repeatability.tsv` files. The analyzer was run
with `VKMT_PERF_ALLOW_PROVIDER_TELEMETRY_GAP=1`: the current P8 provider emits
the Wine loader/NTDLL lifecycle rows but no FEX component lifecycle rows. That
gap is marked as `OBSERVE:provider_telemetry_unavailable` in the phase TSV; it
is not treated as FEX performance proof.

## Phase status

- Phase 0 baseline: complete for current source/runtime identity and the
  four-architecture rc=0 gate.
- Phase 1 ledger: complete for all 82 custom C paths; source hashes and the
  candidate/manual/generated boundary are in `docs/AI_OPTIMIZATION_LEDGER.tsv`.
- Production optimization: none promoted yet.
- Performance improvement: none claimed yet; these numbers are the control
  baseline for later candidate comparisons.
