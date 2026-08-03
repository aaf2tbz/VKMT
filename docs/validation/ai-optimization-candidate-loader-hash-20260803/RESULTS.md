# Rejected candidate: hashed NTDLL builtin-path cache

Date: 2026-08-03

This was the first actual file-level performance candidate from the roadmap.
It changed `dlls/ntdll/unix/loader.c` from a full 128-entry cache scan to an
open-addressed hash lookup with explicit generation clearing. The candidate
was compiled into the actual Wine build tree and tested against the existing
canonical prefix.

## Safety results

- Candidate compiled successfully as `wine/build-ec/dlls/ntdll/ntdll.so`.
- P8 ARM64, ARM64EC, x86_64, and i386/WoW64 rc=0 gate passed.
- WoW64 VM contract passed, including i386 FEX invalidation.
- MSync pulse, WaitAll rollback, stale-port, and fallback gates passed.
- CEF x64 OSR pixel gate passed.
- The candidate was not promoted because performance evidence was not strong
  enough and the control itself showed normal run-to-run variance.

## Measurement

Persistent warm-guest state, five samples per session, two sessions where
available:

| Run | Median range | P95 range | Result |
| --- | ---: | ---: | --- |
| Control x86_64 | 44.319–44.813 ms | 45.314–47.815 ms | repeatability observe |
| Candidate x86_64 | 42.804–43.397 ms | 46.981–48.916 ms | no decisive win |
| Candidate i386/WoW64 | 364.807–371.540 ms | 377.574–407.538 ms | repeatability fail |

The candidate looked faster in median x86_64 startup, but the P95 did not
improve consistently and the i386/WoW64 run had a large tail. The control's
own P95 repeatability also exceeded the five-percent diagnostic threshold, so
the result cannot support a production speed claim.

## Disposition

The candidate patch is retained in `candidate.patch` for provenance only. The
source was restored to the pre-candidate nested Wine commit and the actual
build tree was rebuilt from that source. No candidate code remains installed
or staged in the canonical prefix.

This is an evidence-backed `PROFILED_NO_PROMOTION` result, not a failure of
the loader runtime. A later candidate needs a larger paired control/candidate
sample and a workload-specific loader trace before promotion.

An extended x86_64 run (10 samples in each of two sessions) confirmed the
disposition: control medians were 43.802 and 45.001 ms, while candidate
medians were 44.553 and 48.964 ms. Candidate P95 values reached 47.913 and
56.334 ms versus control values of 52.952 and 50.719 ms. The candidate is
therefore rejected rather than promoted; the apparent small win in the first
five-sample comparison was measurement noise.
