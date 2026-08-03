# VKMT c-ai-optimizer setup

- Upstream: `https://github.com/sebyx07/c-ai-optimizer`
- Pinned commit: `c6f96df0ec9973a4cbdb7b015b1fd106c815ad89`
- Integration: `scripts/vkmt-c-ai-optimizer.sh`
- Target manifest: `docs/c-ai-optimizer-vkmt-targets.tsv`
- Wine source root: `wine/wine-11.12`

The upstream CMake optimized build was not used because it unconditionally
passes `-mavx`, which is invalid for the native ARM64 host. The VKMT wrapper
compiled both the normal and optimized upstream fixture sources with Apple
OpenMP and architecture-safe scalar fallback flags. The shared comprehensive
test suite passed for both builds, including large, non-square, transpose, and
aliasing cases:

```text
ARM64_SCALAR_CAI_OPTIMIZER_TESTS_OK
ALL TESTS PASSED (normal)
ALL TESTS PASSED (optimized scalar fallback)
```

No VKMT Wine source was modified or replaced by this setup. No performance
claim about NTDLL, WoW64, or FEX is made until a workload-specific candidate
passes the promotion contract.
