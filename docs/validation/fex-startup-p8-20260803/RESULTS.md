# P8 FEX startup receipt

## Scope

This receipt supersedes the older BoringSSL diagnostic note that reported an
x86_64 `0xc000001d` before application output. The check was repeated against
the current P8 ARM64EC provider and the existing receipt-backed Phase A
prefix; no disposable prefix and no Wineboot run were used.

## Runtime identity

| Item | Value |
| --- | --- |
| Prefix | `/Volumes/AverySSD/VKMT/build/probe-runs/phase-a-graphics-prefix` |
| Provider | `wine/wine-11.12/runtime-providers/xtajit64-arm64ec-p8-rendering-known-good.dll` |
| Provider SHA-256 | `cccc70a4dd598371ed11c5a7979ca2ecff66a9849ba8086421a69054890c8c5f` |
| Build-tree SHA-256 | `cccc70a4dd598371ed11c5a7979ca2ecff66a9849ba8086421a69054890c8c5f` |
| Prefix-staged SHA-256 | `cccc70a4dd598371ed11c5a7979ca2ecff66a9849ba8086421a69054890c8c5f` |
| FEX scalar/vector/memcpy TSO | `0/0/0` |
| Prefix lifecycle | prepared prefix; `wineboot=not-run` |

## Results

`scripts/probe-p6-single-prefix-architectures.sh --prefix
/Volumes/AverySSD/VKMT/build/probe-runs/phase-a-graphics-prefix` returned
`P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK` and `status=0`:

| Lane | Startup marker | Process result |
| --- | --- | --- |
| ARM64 | `P6_SINGLE_PREFIX_ARM64_OK` | pass |
| ARM64EC | `P6_SINGLE_PREFIX_ARM64EC_OK` | pass |
| x86_64 through `xtajit64` | `P6_SINGLE_PREFIX_X86_64_OK` | pass |
| i386/WoW64 through `xtajit`/WoW64 | `P6_SINGLE_PREFIX_I386_OK` | pass |

The focused x86_64 BoringSSL TLS client was also launched with the same
canonical prefix, the P8 provider, `FEX_TSOENABLED=0`,
`FEX_VECTORTSOENABLED=0`, `FEX_MEMCPYSETTSOENABLED=0`, and the default tier-0
setting. It returned `rc=0` and emitted
`VKMT_BORINGSSL_TLS_OK protocol=TLSv1.3` without a `GIVEUP` or fatal
`EXCEPTION_ILLEGAL_INSTRUCTION` record.

The earlier failure is therefore stale for the current P8 runtime. No source
or provider fallback was promoted based on that old diagnostic; future
diagnostics must record the provider hash and prefix receipt before attributing
a startup failure to FEX.
