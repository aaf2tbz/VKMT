# Phase 4 candidate receipt — FEX interpreter mask helper

Date: 2026-08-03

This is a candidate-only FEX pass. It does **not** promote a source change.
The candidate changed only the pure `sz_mask()` helper in
`dlls/xtajit64/vkmt/interp.c`, replacing the variable shift for widths 0..8
with a constant mask table and preserving the old fallback for other widths.
The candidate was built with the actual ARM64EC Wine flags and passed the
required post-link `fix-x18-tls.py` check.

## Disposition

`PROFILED_NO_PROMOTION — no repeatable speed win`

The direct x86_64 guest launch was status 0 with the expected marker for all
five candidate and all five control runs. The candidate median was 1.54%
slower than the matched control. This does not meet the roadmap's 5%
promotion threshold, and the small direct sample is diagnostic rather than an
acceptance benchmark. No candidate bytes were left in the build or prefix.

| Measurement | Median ms | Min ms | Max ms | Runs |
| --- | ---: | ---: | ---: | ---: |
| Candidate | 1150.167 | 1043.918 | 1192.170 | 5/5 rc=0 + marker |
| Control | 1132.733 | 1082.499 | 1188.237 | 5/5 rc=0 + marker |

The full P0 wrapper was also attempted. Its launches returned `rc=0`, but
the current provider did not emit enough correlated lifecycle events for the
wrapper's strict correlation contract (`unambiguous_guest_executable` and
host lifecycle events were missing). That result is retained only in the
ignored candidate workspace and is not used as a green performance claim.

## Runtime and source identity

| Artifact | SHA-256 |
| --- | --- |
| Control source `dlls/xtajit64/vkmt/interp.c` | `d4d8fc69f6f9ef44d9ec7c05e4c41f0b44e6c408bb0b4d581f671d9093ca6eca` |
| Candidate repaired `xtajit64.dll` | `bfd158292e137748653cee5ad5a186002da2eac0b8445c70b5e03544dc01d2e0` |
| Matched rebuilt control DLL | `474051a9dd1312340e392683e6554aec691a5f7282ccb4d6be587006c152a9ef` |
| Restored canonical P8 build provider | `cccc70a4dd598371ed11c5a7979ca2ecff66a9849ba8086421a69054890c8c5f` |
| Restored canonical P8 prefix provider | `cccc70a4dd598371ed11c5a7979ca2ecff66a9849ba8086421a69054890c8c5f` |

The candidate/control diagnostic DLLs are not package inputs. The current
installed source, build, and prefix use the canonical P8 provider again;
`scripts/vkmt-prefix verify` passed after restoration.

## Functional gate after restoration

The existing canonical prefix was reused. No prefix was created, reset, or
run through Wineboot. With all FEX TSO controls set to zero, the restored P8
prepared-prefix gate returned:

```text
P8_SINGLE_PREFIX_ARM64_OK
P8_SINGLE_PREFIX_ARM64EC_OK
P8_SINGLE_PREFIX_X86_64_OK
P8_SINGLE_PREFIX_I386_OK
P8_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
status=0
```

This is a gate for the restored canonical runtime, not an acceptance claim
for the rejected candidate. The candidate touched the x86_64/ARM64EC provider
only; it did not change the i386/WoW64 provider or any protected FEX dispatch,
JIT, context, invalidation, or executable-memory path.

Receipt evidence is under the ignored diagnostic workspace
`build/c-ai-optimizer-candidates/phase4-fex-mask-20260803/`; the compact P8
status and environment files are under this receipt's `p8/` directory.
