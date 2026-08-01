# Canonical provider all-architecture acceptance

Date: 2026-08-01

After promotion, the default hash-pinned provider path repeated the fresh,
disposable, single-prefix Phase 6 gate without source or provider overrides.
Native ARM64, ARM64EC, x86_64, and i386/WoW64 each returned status 0, and the
run ended with `P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK`.

Scalar, vector, and memcpy/set TSO modes were disabled. The runner verified it
was not translated by Rosetta, and all host Wine executables and Unix bridges
were native ARM64.

Canonical provider SHA-256 values:

- ARM64EC/x86_64: `f0cf686e340a74d46e73549abfadc58aa08d2c7859b42bea2460631ced99c51d`
- ARM64/i386-WoW64: `c387cc42aeb3dd8857bc1045ed8890b8b1f449f73cc1756cd5be46055f249db3`

`status.txt` and the architecture logs are the direct output copied by the
probe before its disposable prefix was removed.
