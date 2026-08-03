# VKMT AI optimization roadmap — final P8 receipt

Date: 2026-08-03

This is the final receipt for the work completed in this pass. It inventories
the source/runtime promotions, candidate evaluations, prepared-prefix result,
and current P8 gates. It does not claim that an unsafe or unmeasured AI source
rewrite was promoted.

## Runtime identity

| Item | Value |
| --- | --- |
| Canonical prefix | build/probe-runs/phase-a-graphics-prefix |
| Nested Wine HEAD | 07df604e8f4e2f475bdd9983905cf98802905ee7 |
| Functional Wine promotion | 656bd43 |
| P8 provider publication | 03ba1ec |
| Host | native Apple ARM64; Rosetta false |
| FEX TSO controls | all zero |
| Full source ledger | 82 custom C files; no custom C++ files |
| Optimizer pin | c6f96df0ec9973a4cbdb7b015b1fd106c815ad89 |

| Runtime artifact | SHA-256 |
| --- | --- |
| wine/build-ec/wine | 334122ba9c93fdc9624fe2ef7138ef6c4000b7bb9ab25e7af3e388ba1d9dbd5d |
| wine/build-ec/server/wineserver | 82b35e96bd449382ca1df262bd493781b638cd74fc1070bc67fcbd17a90ddee7 |
| wine/build-ec/dlls/ntdll/ntdll.so | e3cd6e3c55a96ea5f47c7c9a24f3c268fecb15b0bdf43d6577aa4450b71aae89 |
| wine/build-ec/programs/wineboot/aarch64-windows/wineboot.exe | 939478679896dc14b754c564dadfb1392cd7fb63aa5d89f889b50eb7c8bfaa1e |
| wine/build-ec/dlls/wow64/aarch64-windows/wow64.dll | cd534da4ec125c292bede66e5b7bf6a91eb5ce4c025db7bb0a0df77d3b129a39 |
| wine/build-ec/dlls/wow64win/aarch64-windows/wow64win.dll | 8703ca51aaa5ec5f1e0859f46835add0d4e247cfda0b055f82504ef1978c9113 |
| P8 ARM64EC provider | cccc70a4dd598371ed11c5a7979ca2ecff66a9849ba8086421a69054890c8c5f |
| P8 ARM64/i386 provider | ac512105b5feb85227f2814deb77de603d73ff4713ee60045b23e51c2276f386 |
| Prefix receipt | 947147fd7a8a8d1d0079a029bb1367c1c99782d122135957da65ab92b2ff335f |
| Prefix staged manifest | 98f89f3da6661a3d54ae22a467f1c38291dd85736dc3a5e46e73f0c790a969b9 |

## Final gates

| Gate | Result |
| --- | --- |
| Existing-prefix ARM64 Wineboot --update | rc=0 |
| ARM64 fixture | rc=0 |
| ARM64EC fixture | rc=0 |
| x86_64 fixture | rc=0 |
| i386/WoW64 fixture | rc=0 |
| WoW64 VM contract | WOW64_VM_CONTRACT_ALL_OK |
| i386 FEX invalidation | correlated nonzero maintenance summary |
| MSync manual pulse | PASS |
| MSync auto pulse | PASS |
| MSync WaitAll rollback | PASS |
| MSync stale-port/fallback | PASS; 11 recoveries and 11 diagnostics |
| CEF x86_64 OSR | pixel marker and rc=0 |
| P8 hot-set | PASS; 62.00% cold stall reduction |

The active runner is scripts/probe-p8-single-prefix-architectures.sh. P6
names are retained only for historical provenance; new provider acceptance
uses P8 names.

## Performance result

The final P8 hot-set retry measured:

- cold_physical_gbps=0.865709
- effective_gbps=2.273383
- total_gbps=1.034158
- blocking_stall_reduction_pct=62.00
- warm_regression_pct=2.52

The earlier accepted P8 hot-set receipt measured 61.45% reduction; both are
well above the 25% gate. The promoted NTDLL scan candidate adds a focused
opt-in helper result: absent/end-marker scans improved from 0.319/0.325 ms to
0.014 ms at 4 KiB, 5.357/5.339 ms to 0.177 ms at 64 KiB, and
91.403/97.953 ms to 2.799 ms at 1 MiB over 100 calls. These are helper-level
measurements, not a claim about total Steam startup time.

Previously promoted runtime optimizations already present in this Wine tree
also have retained measurements:

- P3 loader/session caching reduced initial-process dyld resolutions from
  1,140 to 590 and failed path probes from 10 to 5; warm p95 was 21.940/21.986
  ms for x86_64 and 68.915/69.112 ms for i386.
- P4 WineVulkan procedure-availability batching reduced representative i386
  Unix calls by 48.6% for DXGI, 26.6% for D3D12, and 39.8% for D3D11.
- P8 hot-set staging reduced cold blocking stall by 58.41% in its original
  acceptance and 62.00% in the final retry.

## Source and documentation changes

Root commits pushed to origin/main during this pass:

- ba80434 — establish P8 AI optimization baseline and 82-file ledger;
- eb9007a — record P8 WoW64/MSync promotion;
- b828a3f, 4647196 — evaluate and reject the loader hash candidate;
- 7e52568 — record P8 FEX and graphics gates;
- ffdc891 — add full-corpus candidate preparation and P8 snapshot naming;
- be7f0ff — finalize the one-prefix P8 receipt and staging closure fix;
- d7c3c47, 7e87c47, 8afcc88 — complete the final inventory, speed, and P8
  marker receipts.
- 183c6bd — enforce complete candidate disposition coverage;
- b4abed9, 7462a19, d41412c — add prepared-prefix address-sort evidence and
  refresh its inventory/disposition receipts;
- 4c71904 — promote the accepted NTDLL marker-scan candidate and validation
  harness.

Nested Wine commits:

- 656bd43 — promote WoW64/MSync functional source changes;
- 03ba1ec — publish the two canonical P8 provider artifacts.
- 07df604e — promote the NTDLL opt-in marker-scan helper after paired
  equivalence, benchmark, build, and P8 validation.

The complete changed-file inventory is
docs/validation/ai-optimization-final-p8-20260803/changed-files.tsv.
It records 97 root paths and 16 nested-Wine paths relative to the start of
this pass. The 82-file source ledger is docs/AI_OPTIMIZATION_LEDGER.tsv.
The supplemental candidate disposition matrix is
`docs/AI_OPTIMIZATION_DISPOSITION.tsv`; it records which remaining candidate
paths are blocked by ABI, pointer, lock, TLS, ordering, or side-effect
boundaries and which still need workload-specific profiling.
The disposition validator passed with `candidates=15`; it is part of the
optimizer verification command and does not turn unresolved rows green.
The remaining 12 candidate rows are audited at
`docs/validation/ai-optimization-candidate-audit-20260803/RESULTS.md`.
The prepared-prefix Winsock address-list contract also passed with
`VKMT_X64_ADDRESS_LIST_SORT_OK`; its receipt is
`docs/validation/address-list-sort-p8-canonical-20260803/RESULTS.md`.

## Candidate disposition and remaining boundary

The hashed NTDLL loader cache candidate was compiled and tested against paired
control runs, but was rejected: the extended candidate median/P95 became
slower and noisier. Its source was restored and the actual Wine build was
rebuilt from the committed source. It was not installed. The separate
`dlls/ntdll/unix/file.c::buffer_contains()` candidate was accepted and is
installed in the actual nested Wine source/build; its receipt is
`docs/validation/ai-optimization-phase2-file-scan-20260803/RESULTS.md`.
No claim is made that the remaining custom C corpus is optimized.

The protected loader, exception, signal, WoW64, FEX dispatcher/JIT, MSync,
Vulkan, and graphics callback files remain manual-review unless a measured
pure leaf candidate is found. CEF x64 is accepted; i386 CEF remains an
explicit unresolved compatibility boundary. The nested Wine remote is still
configured to an unavailable local archive path, so nested commits are
retained locally while VKMT documentation is pushed to GitHub.

The first follow-on Phase 2 heap candidate is recorded separately at
`docs/validation/ai-optimization-phase2-heap-index-20260803/RESULTS.md`.
It compiled to the exact same `ntdll.so` as control and was rejected without
promotion; the current final runtime hashes and P8 gate therefore remain
unchanged.

The first FEX Phase 4 candidate is recorded at
`docs/validation/ai-optimization-phase4-fex-mask-20260803/RESULTS.md`. It
passed direct x86_64 functional checks but was 1.54% slower and was rejected;
the canonical P8 provider and all-architecture gate remain unchanged.

Therefore the functional/runtime P8 gate is green, but the stronger claim
that every custom C file has been materially AI-optimized is not made.
