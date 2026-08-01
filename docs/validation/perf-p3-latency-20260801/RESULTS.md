# P3 warm guest latency acceptance — 2026-08-01

Status: PASS

The accepted providers were built from FEX commit `90afdb42bbec564c8a8c468588b4218dba27599c`:

- x86_64/ARM64EC `xtajit64.dll`: `0c5e7b85049d2d078a55e014cdecabe767c765d382ee2f0e6c7a92d2f3149a4f`
- i386/WoW64 `xtajit.dll`: `ed9eac240a87cebd2bff5b4384105410a00ae0215b08c1a6f43e8b7d77ae7d98`

Each architecture ran two independent sessions with 20 measured samples in
each of four process/server states (164 correlated `rc=0` launches including
primers). P3 gates the two warm states; cold states remain reported rather than
being hidden by the warm acceptance.

| Architecture | Warm state | Session p95 values | p95 spread | Gate |
|---|---|---:|---:|---|
| x86_64 | persistent server | 21.661 / 21.883 ms | 1.02% | PASS |
| x86_64 | prewarmed guest | 21.940 / 21.986 ms | 0.21% | PASS |
| i386 | persistent server | 69.077 / 68.672 ms | 0.59% | PASS |
| i386 | prewarmed guest | 68.915 / 69.112 ms | 0.29% | PASS |

Both architectures are below the required 75 ms p95. Persistent translated
code caches remained enabled and every TSO setting remained zero.
