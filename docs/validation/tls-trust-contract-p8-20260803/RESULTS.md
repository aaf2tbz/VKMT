# TLS trust contract — P8

Prefix: `/Volumes/AverySSD/VKMT/build/probe-runs/phase-a-graphics-prefix`

**Result:** all requested architecture/mode processes completed with rc=0.

## Capability table

| Architecture | API | Status | Error | Detail |
|---|---|---|---|---|
| arm64 | fixture | PASS | 0 | expired |
| arm64 | WinHTTP | PASS | 12157 | invalid certificate rejected |
| arm64 | WinINet | PASS | 12037 | invalid certificate rejected |
| arm64 | fixture | PASS | 0 | untrusted |
| arm64 | WinHTTP | PASS | 12157 | invalid certificate rejected |
| arm64 | WinINet | PASS | 12045 | invalid certificate rejected |
| arm64 | fixture | PASS | 0 | valid local trust through fragmented proxy |
| arm64 | WinHTTP | PASS | 0 | trusted localhost chain via fragmented CONNECT proxy |
| arm64 | WinINet | PASS | 0 | trusted localhost chain via fragmented CONNECT proxy |
| arm64 | fixture | PASS | 0 | valid local trust |
| arm64 | WinHTTP | PASS | 0 | trusted localhost chain and hostname |
| arm64 | WinINet | PASS | 0 | trusted localhost chain and hostname |
| arm64ec | fixture | PASS | 0 | expired |
| arm64ec | WinHTTP | PASS | 12157 | invalid certificate rejected |
| arm64ec | WinINet | PASS | 12037 | invalid certificate rejected |
| arm64ec | fixture | PASS | 0 | untrusted |
| arm64ec | WinHTTP | PASS | 12157 | invalid certificate rejected |
| arm64ec | WinINet | PASS | 12045 | invalid certificate rejected |
| arm64ec | fixture | PASS | 0 | valid local trust through fragmented proxy |
| arm64ec | WinHTTP | PASS | 0 | trusted localhost chain via fragmented CONNECT proxy |
| arm64ec | WinINet | PASS | 0 | trusted localhost chain via fragmented CONNECT proxy |
| arm64ec | fixture | PASS | 0 | valid local trust |
| arm64ec | WinHTTP | PASS | 0 | trusted localhost chain and hostname |
| arm64ec | WinINet | PASS | 0 | trusted localhost chain and hostname |
| i386 | fixture | PASS | 0 | expired |
| i386 | WinHTTP | PASS | 12157 | invalid certificate rejected |
| i386 | WinINet | PASS | 12037 | invalid certificate rejected |
| i386 | fixture | PASS | 0 | untrusted |
| i386 | WinHTTP | PASS | 12157 | invalid certificate rejected |
| i386 | WinINet | PASS | 12045 | invalid certificate rejected |
| i386 | fixture | PASS | 0 | valid local trust through fragmented proxy |
| i386 | WinHTTP | PASS | 0 | trusted localhost chain via fragmented CONNECT proxy |
| i386 | WinINet | PASS | 0 | trusted localhost chain via fragmented CONNECT proxy |
| i386 | fixture | PASS | 0 | valid local trust |
| i386 | WinHTTP | PASS | 0 | trusted localhost chain and hostname |
| i386 | WinINet | PASS | 0 | trusted localhost chain and hostname |
| arm64 | certificate_chain_seed | PASS | 0 | current-user root visible to chain engine |
| arm64 | certificate_crl | PASS | 0 | installed current-user intermediate CRL |
| arm64 | certificate_root | PASS | 0 | installed current-user localhost root |
| x86_64 | fixture | PASS | 0 | expired |
| x86_64 | WinHTTP | PASS | 12157 | invalid certificate rejected |
| x86_64 | WinINet | PASS | 12037 | invalid certificate rejected |
| x86_64 | fixture | PASS | 0 | untrusted |
| x86_64 | WinHTTP | PASS | 12157 | invalid certificate rejected |
| x86_64 | WinINet | PASS | 12045 | invalid certificate rejected |
| x86_64 | fixture | PASS | 0 | valid local trust through fragmented proxy |
| x86_64 | WinHTTP | PASS | 0 | trusted localhost chain via fragmented CONNECT proxy |
| x86_64 | WinINet | PASS | 0 | trusted localhost chain via fragmented CONNECT proxy |
| x86_64 | fixture | PASS | 0 | valid local trust |
| x86_64 | WinHTTP | PASS | 0 | trusted localhost chain and hostname |
| x86_64 | WinINet | PASS | 0 | trusted localhost chain and hostname |

## Contract

- `valid`: a localhost SAN certificate signed by an intermediate whose root is installed only in the current-user ROOT store.
- `expired`: the same hostname/chain shape with an expired leaf; it must be rejected.
- `untrusted`: a valid-shape leaf signed by a different root that is not installed; it must be rejected.
- Both WinHTTP and WinINet use normal certificate validation; no ignore-errors option is set.
- `valid-fragmented` repeats the trusted case through a local HTTP CONNECT proxy that fragments both directions (2 ms / 32-byte chunks), proving partial TLS transport handling and proxy configuration.
- Servers, certificate material, and requests are local; external DNS/network is not used.
- BoringSSL ignore-verification probes remain diagnostic-only and are not counted here.

Environment: FEX_TSOENABLED=0, FEX_VECTORTSOENABLED=0, FEX_MEMCPYSETTSOENABLED=0, wineboot=not-run.
