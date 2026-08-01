# P0 correlated CPU startup baseline

Date: 2026-08-01

## Harness

`scripts/benchmark-perf-p0.sh` measures four states with the same accepted
prefix and native ARM64 host Wine:

1. cold process and cold wineserver;
2. explicitly pre-read runtime files with a cold wineserver;
3. persistent, initialized wineserver session; and
4. persistent session with pre-read runtime files and an unmeasured guest
   primer.

Each measured process must return `0`, produce the expected guest marker, and
emit a correlated trace. The native runner records elapsed/user/system time,
RSS, faults, block I/O, and context switches. Wine and FEX record loader,
wineserver, NTDLL, provider, thread, and teardown boundaries on the same
`mach_continuous_time` clock. The analyzer rejects incomplete correlations.

All three FEX TSO settings were zero and the host runner was not translated by
Rosetta.

## x86_64 results

Two independent sessions of 20 measured runs per state passed:

| State | Median range | p95 range | Maximum cross-session spread |
| --- | ---: | ---: | ---: |
| Cold process/cold server | 582.626-585.102 ms | 615.046-638.498 ms | 3.81% |
| Warm files/cold server | 582.472-587.418 ms | 598.751-607.664 ms | 1.49% |
| Persistent server | 24.830-25.039 ms | 25.433-25.587 ms | 0.84% |
| Persistent warm guest | 24.975-25.023 ms | 25.519-25.819 ms | 1.18% |

All 160 measured launches returned `0`; 164 runs including primers passed
correlation coverage. Warm x86_64 is already below the final 75-ms p95 target.

## i386/WoW64 results

Two independent sessions of 20 measured runs per state passed:

| State | Median range | p95 range | Maximum cross-session spread |
| --- | ---: | ---: | ---: |
| Cold process/cold server | 672.269-675.042 ms | 704.312-713.193 ms | 1.26% |
| Warm files/cold server | 670.062-673.929 ms | 702.314-713.704 ms | 1.62% |
| Persistent server | 108.001-108.113 ms | 109.133-109.501 ms | 0.34% |
| Persistent warm guest | 108.238-109.195 ms | 109.601-110.282 ms | 0.88% |

All 160 measured launches returned `0`; 164 runs including primers passed
correlation coverage. Warm i386/WoW64 remains roughly 35 ms above the final
75-ms p95 target and is therefore an explicit P3/P4 optimization target.

## Current attribution

On a representative warm x86_64 run, total launch-to-exit was 24.944 ms:

- loader-to-runtime-ready: 9.954 ms;
- wineserver connection: 0.213 ms;
- native NTDLL initialization: 1.735 ms;
- FEX context initialization: 0.171 ms;
- FEX process initialization: 1.537 ms; and
- guest lifetime after FEX thread initialization: 8.482 ms.

The cold NTDLL interval includes automatic prefix-session bootstrap and is the
dominant cold-start cost. The earlier headless fix prevents desktop integration
from also creating MoltenVK during this interval.

## Remaining P0 scope

This accepts the CPU/process measurement spine, not all of P0. First translated
or cache-loaded guest block, transition-class counters, graphics device/shader/
pipeline milestones, first submission/present, and real Steam browser/renderer/
GPU/utility child lifecycles still require correlated instrumentation before P0
is complete.
