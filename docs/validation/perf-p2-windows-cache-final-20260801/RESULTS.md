# Windows FEX persistent-cache acceptance

Date: 2026-08-01

Persistent translated-code caching passed for both Windows FEX providers.
Fresh first processes published caches and exited with status 0; fresh second
processes reported `cache_discovered`, `cache_loaded`, and `cache_enabled` and
also exited with status 0. The x86_64 cache was 1,041,192 bytes and the i386
cache was 10,327,160 bytes.

For the retained identical-fixture pairs, x86_64 wall time fell from 693.687 ms
to 575.109 ms (118.578 ms, 17.1%) and i386 wall time fell from 804.489 ms to
664.563 ms (139.926 ms, 17.4%). x86_64 user CPU time fell from 15.840 ms to
9.022 ms (43.0%). Major page faults fell from 10 to 4 for x86_64 and from 7 to
3 for i386. These are one-pair smoke measurements, not a distribution or a
game-scale benchmark, so they establish a concrete gain without claiming a
general 17% speedup for every workload.

Corruption handling was tested with isolated 64-byte truncated cache files for
each architecture. Both processes safely rejected the malformed image, used
live JIT, returned status 0, and atomically published validated `.repaired`
images. The following process discovered and loaded each repaired image.

Raw evidence is retained under `build/perf-p2/`:

- `x64-cache-v36-first` and `x64-cache-v36-second`
- `i386-cache-v35-first` and `i386-cache-v35-second`
- `corrupt-x64-v38` and `repaired-x64-v38`
- `corrupt-i386-v38` and `repaired-i386-v38`
- `final-hit-x64` and `final-hit-i386`

The cache implementation is no-TSO and architecture-aware: ARM64EC cached code
uses EC executable mappings, while WoW64/i386 cached code uses ordinary ARM64
executable mappings and preserves 32-bit guest virtual addresses separately
from high ARM64 host pointers.
