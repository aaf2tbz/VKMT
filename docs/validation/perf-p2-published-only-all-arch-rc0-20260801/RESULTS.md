# Persistent-cache provider all-architecture acceptance

Date: 2026-08-01

The exact final provider candidates passed a fresh, disposable, single-prefix
Phase 6 run. Every fixture returned conventional process status 0:

- native ARM64: pass
- ARM64EC: pass
- x86_64 through the ARM64EC FEX provider: pass
- i386/WoW64 through the ARM64 FEX provider: pass

The run ended with `P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK`. Scalar, vector,
and memcpy/set TSO modes were disabled, and the host Wine executables and Unix
bridges were native ARM64. Rosetta was not used.

Accepted provider SHA-256 values:

- ARM64EC/x86_64: `f0cf686e340a74d46e73549abfadc58aa08d2c7859b42bea2460631ced99c51d`
- ARM64/i386-WoW64: `c387cc42aeb3dd8857bc1045ed8890b8b1f449f73cc1756cd5be46055f249db3`

The sibling log files and `status.txt` are the direct probe output. The
disposable prefix was removed automatically after success.
