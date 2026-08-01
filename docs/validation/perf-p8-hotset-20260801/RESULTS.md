# P8 runtime hot-set acceptance — 2026-08-01

## Observed hot set

- Sampling window: first five seconds, every 50 ms.
- Guests: x86_64 and i386/WoW64, hosted by native ARM64 Wine/FEX.
- TSO modes: scalar, vector, and memcpy/set all disabled.
- Manifest: 222 identity-checked ranges, 211,225,570 bytes (201.44 MiB).
- Quota: 268,435,456 bytes (256 MiB).

## Five-run median

| Metric | Result |
| --- | ---: |
| Cold physical demand-read stall | 266,715,000 ns |
| Cold physical throughput | **0.791952 GB/s** |
| Prefetch advisory setup | 2,588,000 ns |
| Blocking stall after 100-ms overlap | 110,655,000 ns |
| Effective post-prefetch throughput | **1.908866 GB/s** |
| Total delivery throughput including setup and overlap | **0.990010 GB/s** |
| Blocking-stall reduction | **58.41%** |
| Warm baseline stall | 10,159,000 ns |
| Warm advised stall | 10,109,000 ns |
| Warm regression | **-0.49%** |

Decimal throughput uses `GB/s = bytes / nanoseconds`, since one byte per
nanosecond is one billion bytes per second. The physical value is measured
with `F_NOCACHE`; the 1.908866-GB/s value is explicitly an effective blocking
service rate after asynchronous read-ahead, not a claim that the SSD itself
transferred at that rate.

An incompatible file-size identity was rejected without preventing the other
221 valid entries from being advised. The default path uses a per-prefix lock,
30-second cooldown, 256-MiB manifest cap, and macOS's clean-page LRU. It can be
disabled with `VKMT_HOTSET_PREFETCH=0`.

After integration, the runtime launch fixture returned status 0 and a new
single prefix passed ARM64, ARM64EC, x86_64, and i386/WoW64 with status 0.
