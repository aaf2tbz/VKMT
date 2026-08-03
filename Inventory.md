# VKMT Package Inventory

This is the release/package composition inventory. It is deliberately a
provenance and verification document, **not** a claim that source presence or
staging alone proves runtime compatibility. A redistributable package is
invalid if it omits a required row or includes an excluded row.

## Package policy

- Host executables and host dylibs must be ARM64-only; Rosetta is excluded.
- Provider promotion remains governed by
  `scripts/stage-runtime-providers.sh` and its pinned SHA-256 values.
- Browser, Java, Mono, Gecko, and other separately licensed payloads are not
  silently bundled. They require their own provenance and user-fetch/install
  policy.
- Do not include guessed ARM64EC dispatcher code, unverified generated
  binaries, obsolete candidate providers, disposable prefixes, caches, logs,
  or historical diagnostics in a release bundle.

## Authoritative TSV inventory

The block below is consumed by `scripts/verify-preservation.sh --inventory`.
Fields are: `id, class, architectures, canonical_path,
producer_or_stage_script, verification_source, acceptance_runner,
provenance_license, package_action`.

```tsv
id	class	architectures	canonical_path	producer_or_stage_script	verification_source	acceptance_runner	provenance_license	package_action
wine-host	required-runtime	arm64	wine/build-ec/wine	wine build	scripts/verify-preservation.sh	P8 hotset acceptance; P8 provider smoke	Wine LGPL	required
wineserver	required-runtime	arm64	wine/build-ec/server/wineserver	wine build	scripts/verify-preservation.sh	P8 hotset acceptance; P8 provider smoke	Wine LGPL	required
ntdll-host	required-runtime	arm64	wine/build-ec/dlls/ntdll/ntdll.so	wine build	scripts/verify-preservation.sh	scripts/probe-msync.sh	Wine LGPL	required
xtajit64	required-runtime	arm64ec	wine/build-ec/dlls/xtajit64/aarch64-windows/xtajit64.dll	scripts/stage-runtime-providers.sh	scripts/stage-runtime-providers.sh	P8 hotset acceptance; P8 provider smoke	project-pinned	provider-required
xtajit	required-runtime	arm64	wine/build-ec/dlls/xtajit/aarch64-windows/xtajit.dll	scripts/stage-runtime-providers.sh	scripts/stage-runtime-providers.sh	P8 hotset acceptance; P8 provider smoke	project-pinned	provider-required
wow64-bridge	required-runtime	arm64	wine/build-ec/dlls/wow64/aarch64-windows/wow64.dll	wine build	scripts/vkmt-prefix	P8 hotset acceptance; P8 provider smoke	Wine LGPL	required
wow64win-bridge	required-runtime	arm64	wine/build-ec/dlls/wow64win/aarch64-windows/wow64win.dll	wine build	scripts/vkmt-prefix	P8 hotset acceptance; P8 provider smoke	Wine LGPL	required
i386-pe-closure	required-runtime	i386	wine/build-ec/dlls	scripts/vkmt-prefix	scripts/vkmt-prefix	P8 hotset acceptance; P8 provider smoke	Wine LGPL	required
host-libs	required-runtime	arm64	wine/build-ec/dlls/win32u	scripts/stage-wine-host-libs.sh	scripts/verify-preservation.sh	graphics probes	component licenses	required
fex-source	required-source	arm64,x64,i386	third_party/FEX-2607	FEX checkout	git revision and status	P8/FEX probes	FEX license	source-required
moltenvk-source	required-source	arm64	third_party/MoltenVK	MoltenVK checkout	scripts/verify-preservation.sh	graphics probes	MoltenVK license	source-required
dxvk-source	required-source	x64,i386	third_party/dxvk	DXVK checkout	scripts/verify-preservation.sh	future DXVK gate	DXVK license	source-required
vkd3d-source	required-source	x64,i386	third_party/vkd3d-proton	vkd3d-proton checkout	scripts/verify-preservation.sh	future vkd3d gate	vkd3d-proton license	source-required
dxmt-pair	required-runtime	arm64ec	wine/build-ec/dxmt-v0.80/aarch64-windows	scripts/stage-dxmt-runtime.sh	scripts/stage-dxmt-runtime.sh	scripts/probe-dxmt-arm64ec.sh	project-pinned	profile-graphics
gecko	optional-external	all	third_party/wine-gecko	scripts/stage-gecko-runtime.sh	external manifest	future browser gate	MPL/user fetch	separate-fetch
java	optional-external	arm64	third_party/private/oracle-jre-8u501-arm64	scripts/stage-native-java-runtime.sh	external provenance	managed probes	Oracle license	separate-fetch
cef-webview-electron	optional-external	x64,i386	third_party/browser-runtimes	dedicated future stage	required future manifest	future browser gate	vendor licenses	not-bundled-until-staged
diagnostics	excluded	all	docs/validation	create-on-demand	n/a	n/a	n/a	exclude
prefixes-caches	excluded	all	build/probe-runs	create-on-demand	n/a	n/a	n/a	exclude
candidate-providers	excluded	all	wine/wine-11.12/runtime-providers/*candidate*	rollback-only	pinned provider verifier	n/a	project policy	exclude
```

## Prepared-prefix profiles

| Profile | Verified Phase-A content | Explicitly not claimed installed |
| --- | --- | --- |
| core | Wine host closure, providers, GStreamer/GPU-cache/hotset contracts, WoW64 bridges, i386 DLL closure | Browser and managed payloads |
| graphics | core plus the preserved release-qualified DXMT pair | DXVK and vkd3d runtime DLLs |
| browser | graphics plus browser identity metadata | CEF, WebView2, Electron payloads |
| managed | core plus managed identity metadata | Wine Mono and Java payload installation |
| full | union of the above truthful contracts | Any component lacking a prefix staging helper |

## Release/package gate

1. Run `scripts/verify-preservation.sh --inventory`.
2. Verify every `required-runtime` row is present with its architecture and
   pinned/hash verification path.
3. Verify every external asset has a provenance/hash receipt and is either
   separately fetched or explicitly authorized for distribution.
4. Run `scripts/vkmt-prefix verify --prefix PATH`, then run
   `scripts/probe-perf-p8-hotset.sh` with the release prefix and manifest.
   P8 is final acceptance; legacy phase receipts are supporting historical diagnostics only.
5. Reject a package containing an `excluded` path, stale prefix/caches,
   Rosetta/x86 host Mach-O content, unpinned provider bytes, or diagnostic
   logs masquerading as acceptance evidence.

## Known Phase-A gaps

Dedicated reusable prefix stage helpers are still needed for DXVK, vkd3d,
CEF, WebView2, Electron, Wine Mono, and managed/browser fixtures. Their
presence in this inventory preserves provenance; it does not make them
package-ready or accepted.

DXMT prefix staging uses the separately preserved release-qualified pair at `build/provider-preservation/pre-dxmt-cross-process-allow-20260731`; locally regenerated build output is intentionally not staged until promoted.

## WoW64 VM phase inventory (current working state)

The single canonical working prefix for this phase is:

```text
build/probe-runs/phase-a-graphics-prefix
```

Do **not** create or reset another prefix for the WoW64 work. The phase uses
the existing receipt-backed graphics prefix and fast-syncs only the rebuilt
WoW64 closure (`wow64.dll`, `wow64win.dll`, and i386 `ntdll.dll`) with:

```sh
scripts/vkmt-prefix sync-wow64 --prefix "$PWD/build/probe-runs/phase-a-graphics-prefix"
scripts/vkmt-prefix verify --prefix "$PWD/build/probe-runs/phase-a-graphics-prefix"
```

The current staged WoW64 bridge SHA-256 is
`cd534da4ec125c292bede66e5b7bf6a91eb5ce4c025db7bb0a0df77d3b129a39`.
The matching staged USER bridge is
`8703ca51aaa5ec5f1e0859f46835add0d4e247cfda0b055f82504ef1978c9113`,
and the rebuilt i386 `syswow64/ntdll.dll` is
`50ad58ec524fbf6ebde1d89d52b346b6c66a98eb5c2fe94b5f0dd7a87d70a861`.
The canonical ARM64EC renderer provider is now
`wine/wine-11.12/runtime-providers/xtajit64-arm64ec-p8-rendering-known-good.dll`
with SHA-256
`cccc70a4dd598371ed11c5a7979ca2ecff66a9849ba8086421a69054890c8c5f`.
The former `xtajit64-arm64ec-known-good.dll` (`0dde3c54...`) remains a
rollback artifact and is not the default staged provider.
The preserved DXMT pair remains authoritative; if `wineboot --update` is
needed on this existing prefix, run it first and then restage DXMT with
`scripts/vkmt-prefix sync-dxmt`. Do not run full prefix creation as part of
this phase.

### WoW64 source and test artifacts

| Artifact | Role | Package action | Evidence |
| --- | --- | --- | --- |
| `wine/wine-11.12/dlls/wow64/memory.c` | static-pool interval registry, overlay retirement, split/reuse tracking, committed-page publication state | source-only; rebuild bridge | ARM64 WoW64 DLL build; focused VM contract |
| `wine/wine-11.12/dlls/wow64/virtual.c` | transactional VM/map/unmap publication and rollback; explicit MEM_DECOMMIT versus MEM_RELEASE handling | source-only; rebuild bridge | focused VM contract; Electron ia32 diagnostic |
| `wine/wine-11.12/dlls/wow64win/user.c` | preserves MAKEINTATOM class values instead of translating them as guest pointers | source-only; rebuild USER bridge | Electron ia32 progressed past the prior `0xc021` fault |
| `wine/wine-11.12/dlls/wow64/wow64_private.h` | registry lifecycle declarations | source-only | bridge build |
| `test/wow64_vm_contract.c` | x64/i386 reserve, commit, decommit, protection, aliases, executable reuse, concurrency | test-only; exclude package | `docs/validation/wow64-vm-contract-cef-fix-final2` |
| `scripts/probe-wow64-vm-contract.sh` | one-prefix x64 then i386 runner with FEX trace correlation | test-only; exclude package | focused receipt |
| `docs/validation/wow64-vm-contract-current-20260802` | focused evidence after decommit publication fix | diagnostics; exclude package | `WOW64_VM_CONTRACT_ALL_OK`, i386 invalidation summary |
| `docs/validation/wow64-p6-final` | four-architecture regression evidence | diagnostics; exclude package | `P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK`, `status=0` |
| `docs/validation/wow64-p8-final` | final hotset/performance regression evidence using the same prefix | diagnostics; exclude package | `P8_HOTSET_OK`, 61.84% median stall reduction |

The focused proof records all three FEX TSO modes as zero, requires both x64
and i386 markers, requires concurrent and executable-reuse markers, and
requires a nonzero correlated i386 FEX `maintenance_summary` invalidation
counter. The current P8 ARM64EC provider emits no x64 FEX component row for
this fixture; the runner records that telemetry gap explicitly as
`x64_fex_trace=unavailable-provider-telemetry` rather than treating loader
TSV files as provider proof. It does not by itself claim that CEF, Electron
ia32, or Chromium renderer allocation traces are complete browser acceptance;
those remain separate integration gates.

The P8 hotset gate also passed against this same prefix:
`physical_gbps=0.867708`, `effective_gbps=2.145993`,
`total_gbps=1.003657`, `stall_reduction_pct=59.79`, and
`warm_regression_pct=-3.92`.

### Existing-prefix CEF/Electron diagnostic pass

The CEF and Electron probes now accept the same receipt-backed prefix with
`--prefix`; they do not create a prefix or run `wineboot` unless their
explicit `*_WINEBOOT_UPDATE=1` escape hatch is selected. Existing-prefix mode
fast-syncs only the rebuilt WoW64 bridge, matching `wow64win.dll`, and i386
`ntdll.dll`; it does not rehash/copy the whole i386 closure on every
Electron/CEF invocation. The compatibility launcher and CEF child hook are
staged into a temporary per-run client directory, not into the canonical
prefix.

The current diagnostic runs are preserved here:

| Probe | Prefix | Evidence | Result |
| --- | --- | --- | --- |
| CEF 109 x86_64 + i386/WoW64 legacy probe | `build/probe-runs/phase-a-graphics-prefix` | `docs/validation/cef-existing-prefix-v4` | historical only; not current provider acceptance |
| Electron 42 x64 + ia32/WoW64 legacy probe | `build/probe-runs/phase-a-graphics-prefix` | `docs/validation/electron-existing-prefix-v3` | both ABIs executed; legacy diagnostic traces only |

CEF-specific observations above are historical diagnostics. The current
x86_64 OSR gate below is accepted. Electron x64 now passes the
renderer/result gate with the P8 provider. Electron ia32 reaches the guest
runtime, but still fails in V8 at `electron.exe+0x4697c6` while reading an
object in a recently decommitted Chromium allocation; it produces no
renderer/result markers. This remains an open ia32/FEX compatibility issue,
not probe success.

The FEX TSVs are loader/JIT and maintenance allocation evidence, not a claim
that every Chromium renderer VM operation has been traced. The focused OSR
pixel gate below is the accepted x86_64 rendering proof; direct ia32 renderer
allocation/protection proof remains open. The canonical prefix was verified
after the legacy runs with `VKMT_PREFIX_VERIFY_OK`; no new disposable prefix
was used.

### CEF/Electron rendering work in progress

The CEF host path now has a real windowless C API host in
`third_party/metalsharp-cef/vkmt_browser_capi.c`. It requests CEF OSR,
provides a 1280x800 `cef_render_handler_t`, samples BGRA paint output, and
emits `VKMT_BROWSER_PIXEL_OK` when the deterministic RGB(17,34,51) page is
painted. `scripts/launch-vkmt-cef-browser.sh` now supports the canonical
receipt-backed prefix without wineboot, converts host log paths to `Z:` paths,
accepts `VKMT_BROWSER_EXTRA_ARGS`, and accepts duration values with or without
an `s` suffix. The existing CEF wrapper no longer unconditionally appends
`--disable-gpu`; the launcher/probe owns the rendering policy.

The reusable OSR gate is `scripts/probe-cef-osr-render.sh`; it only accepts
the existing receipt-backed prefix, waits for the pixel marker, and records
`CEF_X86_64_OSR_RENDER_OK` without creating or resetting a prefix.

The canonical prefix was updated in place with `vkmt-prefix refresh`; this did
not run `wineboot` or recreate the prefix. The launcher has an opt-in
`VKMT_BROWSER_WAIT_FOR_RENDER=1` mode that waits for the OSR pixel marker and
returns a deterministic status instead of treating CEF child shutdown timing
as a rendering failure.

The x86_64 rendering gate remains accepted on its recorded canonical P8
evidence. The current i386 CEF run is intentionally not marked accepted:
`docs/validation/cef-i386-config-hardened-20260802/` proves export loading and
FEX allocation tracing with the current provider, but the browser never
publishes a DevTools endpoint and no renderer/pixel markers are present. This
is a live CEF/WoW64 integration gap, not a prefix or provider-receipt failure.

The x86_64 rendering gate is accepted on the recorded canonical P8 provider:

| Diagnostic | Evidence | Result |
| --- | --- | --- |
| P8 final non-WoW64 architecture gate | `docs/validation/p8-final-nonwow64-rc0-20260803` | ARM64, ARM64EC, and x86_64 smoke `rc=0`; i386/WoW64 intentionally excluded |
| Current CEF x86_64 OSR final gate | `docs/validation/cef-x64-final-p8-20260803` | current host rebuilt, `VKMT_BROWSER_PIXEL_OK`, deterministic BGRA marker, launcher `rc=0`; canonical-prefix reuse |
| Windowless CEF host, canonical P8 provider | `docs/validation/cef-osr-render-p8` | `VKMT_BROWSER_PIXEL_OK`, BGRA `51,34,17,255`, launcher `rc=0`; one-prefix reuse |
| Electron x64 software-render fixture, canonical P8 provider | `docs/validation/electron-render-p8-canonical-x64-vmfix` | `ELECTRON_X64_OK`, HTTPS/input/audio/pixel result, renderer and FEX allocation markers; `rc=0` |
| WoW64 VM contract, x64+i386 | `docs/validation/wow64-vm-contract-cef-fix-final2` | both architecture contracts, concurrent pressure, executable reuse, i386 FEX invalidation; `rc=0` |
| CEF 109 i386/WoW64 diagnostic | `docs/validation/cef-i386-config-hardened-20260802` | current provider exports and FEX allocation trace; CDP/pixel/renderer gate timed out; not accepted |
| Electron ia32/WoW64 | `docs/validation/electron-render-p8-canonical-i386-vmfix-final` | prior atom fault removed; still fails at V8 `0x004697c6` after `MEM_DECOMMIT`; no renderer/result; not accepted |
| Official CEF x64, bundled SwiftShader/windowed | `docs/validation/cef-existing-prefix-v9-explorer` | separate legacy diagnostic; not the OSR acceptance gate |

The current ARM64EC P8 rendering provider is
`xtajit64-arm64ec-p8-rendering-known-good.dll` (`cccc70a4...`). The current
ARM64/i386 WoW64 provider is
`xtajit-arm64-p8-wineconfig-known-good.dll`
(`ac512105b5feb85227f2814deb77de603d73ff4713ee60045b23e51c2276f386`), built
from FEX commit `a4128f01913d25d49f0d1cd1f62668327de1815e` with the config-file
startup hardening in `third_party/FEX-2607/Source/Common/Config.cpp`. The old
`e030b4d3...` provider remains rollback-only and is not staged. Provider
staging now updates the existing prefix manifest/receipt through
`scripts/vkmt-prefix sync-providers`; no prefix recreation or wineboot is
needed. Do not package diagnostic logs, disposable browser runtimes, or
rollback providers.

### Current final-gate boundary (2026-08-03)

The acceptance boundary for this phase is the non-WoW64 architecture gate
plus the user-facing x86_64 CEF OSR host. Both were run against
`build/probe-runs/phase-a-graphics-prefix` with the current P8 providers and
all three FEX TSO controls set to zero. No prefix was recreated and Wineboot
was not run. The authoritative retained summaries are:

- `docs/validation/p8-final-nonwow64-rc0-20260803/RESULTS.md`
- `docs/validation/cef-x64-final-p8-20260803/RESULTS.md`

i386/WoW64 CEF is intentionally outside this final gate. The official CEF
Windows32 runtime is present and exports load, but the current i386 browser
does not return from `cef_initialize` or publish a DevTools/renderer/pixel
marker. That remains an open compatibility gap and must not be represented
as package-ready or green. The standalone legacy `cefclient` diagnostic is
also not the product acceptance gate; the user-facing CEF host and its OSR
pixel marker are the authoritative x86_64 result here.

### AI optimization Phase 0/1 baseline (2026-08-03)

The file-by-file optimization plan is `docs/AI_OPTIMIZATION_ROADMAP.md` and
the source-hashed ledger for all 82 custom C paths is
`docs/AI_OPTIMIZATION_LEDGER.tsv`. The current candidate pipeline is pinned
to c-ai-optimizer commit
`c6f96df0ec9973a4cbdb7b015b1fd106c815ad89`.
The candidate-path disposition matrix is
`docs/AI_OPTIMIZATION_DISPOSITION.tsv`; boundary and triage rows are not
performance acceptance claims.
Run `scripts/vkmt-c-ai-optimizer.sh disposition` to verify that all 15 ledger
candidate rows are represented exactly once before packaging or promotion.

The prepared-prefix Winsock address-order contract is recorded at
`docs/validation/address-list-sort-p8-canonical-20260803/`. Its runner is
`scripts/probe-x64-address-list-sort.sh --prefix PATH`; fresh bootstrap mode
remains available separately.

The active provider-backed architecture runner is
`scripts/probe-p8-single-prefix-architectures.sh`. It reuses the canonical
graphics prefix and does not recreate it or run Wineboot in prepared-prefix
mode. The compatibility `probe-p6-single-prefix-architectures.sh` name and
historical P6 evidence remain provenance-only; current acceptance markers and
new receipts use P8 naming to identify the P8 provider generation.

Phase 0/1 evidence is
`docs/validation/ai-optimization-p8-phase0-baseline-20260803/`. It passed
ARM64, ARM64EC, x86_64, and i386/WoW64 with status 0 and all three FEX TSO
settings fixed at zero. One narrow pure NTDLL marker-scan candidate has since
been promoted; the ledger and disposition matrix record its source hash and
receipt separately from the remaining candidate/manual-review boundary.

### AI optimization WoW64/MSync promotion (2026-08-03)

The current nested Wine functional changes are committed at
`wine/wine-11.12` commit `656bd43`. Targeted builds were promoted into the
actual `wine/build-ec` runtime and the existing canonical prefix was updated
only through `scripts/vkmt-prefix sync-wow64`.

The combined receipt is
`docs/validation/ai-optimization-wow64-msync-phase3-20260803/RESULTS.md`.
The WoW64 contract passed x64 and i386 mapping pressure, reuse, concurrency,
executable reuse, and i386 FEX invalidation. MSync passed manual/auto pulse,
WaitAll rollback, stale-port recovery, and invalid-destination fallback.
These are functional source promotions; no AI-generated performance candidate
has been promoted in this phase. The separate NTDLL scan promotion is recorded
below.

### AI optimization Phase 2 file-scan promotion (2026-08-03)

`dlls/ntdll/unix/file.c::buffer_contains()` was promoted in nested Wine commit
`07df604e8f4e2f475bdd9983905cf98802905ee7` after 250,000 equivalence cases,
repeated benchmark cells, an actual ARM64 `ntdll.so` build, and the prepared
P8 four-architecture gate passed. The candidate accelerates the opt-in Steam
handoff marker scan while leaving notification state, socket transport,
completion ordering, and default-disabled behavior unchanged.

Receipt: `docs/validation/ai-optimization-phase2-file-scan-20260803/RESULTS.md`.
The promoted ARM64 `ntdll.so` hash is
`e3cd6e3c55a96ea5f47c7c9a24f3c268fecb15b0bdf43d6577aa4450b71aae89`.

### AI optimization FEX/graphics gates (2026-08-03)

The FEX phase receipt is
`docs/validation/ai-optimization-fex-phase4-20260803/RESULTS.md`. The graphics
phase receipt is
`docs/validation/ai-optimization-graphics-phase5-20260803/RESULTS.md`.
The current P8 hot-set run measured `61.45%` cold blocking-stall reduction,
`2.249713 GB/s` effective delivery, and `0.15%` warm regression. CEF x86_64
OSR emitted the deterministic pixel marker with status 0. No FEX or graphics
source candidate was promoted because no candidate passed a repeatable
workload-specific speed gate.

The first loader candidate evaluation is retained at
`docs/validation/ai-optimization-candidate-loader-hash-20260803/RESULTS.md`.
It passed the functional gates but was rejected for promotion because its
paired startup measurements did not establish a repeatable improvement and
the i386 tail became noisy. The candidate source is not in the installed Wine
tree or canonical prefix.

The complete 82-file candidate workspace preparation is recorded in
`docs/validation/ai-optimization-corpus-20260803/RESULTS.md`. The workspace is
ignored and contains no promoted binaries.

### AI optimization final P8 gate receipt (2026-08-03)

The final one-prefix receipt is
`docs/validation/ai-optimization-final-p8-20260803/RESULTS.md`. It records the
native ARM64 Wineboot update (`rc=0`), the P8 all-architecture fixture gate,
WoW64 VM, MSync, CEF x86_64 OSR, and the final P8 hot-set measurement. The
prefix was refreshed in place after Wineboot repopulated a stale i386 DLL;
`scripts/vkmt-prefix` now prunes only stale prefix-owned i386 closure files
that have no source-built counterpart before rebuilding the receipt.

### AI optimization Phase 2 candidate pass A (2026-08-03)

The first Phase 2 heap candidate receipt is
`docs/validation/ai-optimization-phase2-heap-index-20260803/RESULTS.md`.
It evaluated the pure `get_free_list_index()` helper in the actual installed
NTDLL build, but the native `clz` candidate compiled to a byte-identical
`ntdll.so` under the current ARM64 flags. It was therefore rejected as
`PROFILED_NO_PROMOTION`; no candidate binary or source was staged into the
Wine tree or canonical prefix. The source and installed NTDLL hashes were
restored exactly, and the prepared-prefix P8 gate returned status 0 for
ARM64, ARM64EC, x86_64, and i386/WoW64. This receipt closes only this heap
candidate pass; it does not claim that the remaining eligible C paths have
been materially optimized.

### AI optimization Phase 4 candidate pass A (2026-08-03)

The FEX interpreter mask candidate receipt is
`docs/validation/ai-optimization-phase4-fex-mask-20260803/RESULTS.md`.
It evaluated only the pure `sz_mask()` helper. Candidate and control direct
x86_64 launches were all `rc=0` with the expected marker, but the candidate
was 1.54% slower at the median and did not meet the promotion threshold. It
was rejected without staging; the canonical P8 ARM64EC provider was restored,
prefix verification passed, and the prepared-prefix P8 gate again passed
ARM64, ARM64EC, x86_64, and i386/WoW64. The FEX dispatcher/JIT/context,
invalidation, and executable-memory code remains protected and unchanged.
