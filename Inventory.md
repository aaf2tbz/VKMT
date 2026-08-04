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
ntdll-host	required-runtime	arm64	wine/build-ec/dlls/ntdll/ntdll.so	wine build	scripts/verify-preservation.sh	scripts/probe-msync.sh; scripts/probe-ai-ntdll-file-scan.sh	Wine LGPL	required
xtajit64	required-runtime	arm64ec	wine/build-ec/dlls/xtajit64/aarch64-windows/xtajit64.dll	scripts/stage-runtime-providers.sh	scripts/stage-runtime-providers.sh	P8 hotset acceptance; P8 provider smoke	project-pinned	provider-required
xtajit	required-runtime	arm64	wine/build-ec/dlls/xtajit/aarch64-windows/xtajit.dll	scripts/stage-runtime-providers.sh	scripts/stage-runtime-providers.sh	P8 hotset acceptance; P8 provider smoke	project-pinned	provider-required
wow64-bridge	required-runtime	arm64	wine/build-ec/dlls/wow64/aarch64-windows/wow64.dll	wine build	scripts/vkmt-prefix	P8 hotset acceptance; P8 provider smoke	Wine LGPL	required
wow64win-bridge	required-runtime	arm64	wine/build-ec/dlls/wow64win/aarch64-windows/wow64win.dll	wine build	scripts/vkmt-prefix	P8 hotset acceptance; P8 provider smoke	Wine LGPL	required
i386-pe-closure	required-runtime	i386	wine/build-ec/dlls	scripts/vkmt-prefix	scripts/vkmt-prefix	P8 hotset acceptance; P8 provider smoke	Wine LGPL	required
host-libs	required-runtime	arm64	wine/build-ec/dlls/win32u	scripts/stage-wine-host-libs.sh	scripts/verify-preservation.sh	graphics probes	component licenses	required
fex-source	required-source	arm64,x64,i386	third_party/FEX-2607	FEX checkout	git revision and status	P8/FEX probes	FEX license	source-required
moltenvk-source	required-source	arm64	third_party/MoltenVK	MoltenVK checkout	scripts/verify-preservation.sh	graphics probes	MoltenVK license	source-required
dxvk-source	required-source	x64,i386	third_party/dxvk	DXVK checkout	scripts/verify-preservation.sh	future DXVK gate	DXVK license	source-required
d3dcompiler-contract	test-only	arm64,arm64ec,x64,i386	test/d3dcompiler_contract.c	scripts/probe-d3dcompiler-contract.sh	docs/validation/d3dcompiler-contract-p8-20260803/capability.tsv	P8 one-prefix contract	Wine LGPL	exclude
moltenvk-behavior	behavior-contract	native arm64	test/moltenvk_behavior_contract.c;test/moltenvk_storage_read.comp;test/moltenvk_image_read.comp	scripts/probe-moltenvk-behavior.sh	docs/validation/moltenvk-behavior-p8-20260803/RESULTS.md;capability.tsv	P8 direct Vulkan/Metal behavior	MoltenVK/Vulkan licenses	required-source
eac-contract	test-only	arm64,arm64ec,x64,i386	test/eac_contract.c;test/eac_mock_backend	scripts/probe-eac-contract.sh	docs/validation/eac-contract-p8-20260803/capability.tsv	P8 mock lifecycle/negative matrix	project test code	exclude
eac-host-bridge	test-only	arm64	dlls/vkmt_eac/unix/vkmt_eac.c	scripts/probe-eac-contract.sh	docs/validation/eac-contract-p8-20260803/host-exports.txt	P8 dynamically loaded mock bridge	project test code	exclude
eac-runtime	optional-external	x64	build/probe-runs/phase-a-graphics-prefix/drive_c/vkmt-eac-test	scripts/stage-eac-runtime.sh	VKMT_EAC_STAGE.tsv;docs/validation/eac-contract-p8-20260803/RESULTS.md	Epic EOS/EAC license	separate-fetch;never-package
graphics32-consumer-closure	optional-runtime	i386	third_party/dxvk/runtime/dxvk-vkmt-1a5919b/x32;third_party/vkd3d-proton/install-win32/bin	scripts/vkmt-prefix sync-graphics32	prefix .vkmt manifest + graphics32-sync.receipt	D3D11/D3D12 consumer lanes	DXVK/vkd3d-proton licenses	separate-provider-policy
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
| graphics | core plus the preserved release-qualified DXMT pair; optional receipt-backed 32-bit DXVK/vkd3d consumer closure via `sync-graphics32` | CEF/WebView2/Electron payloads; 32-bit graphics providers are not staged until that explicit sync |
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

### D3DCompiler contract (P8, 2026-08-03)

The complete D3DCompiler fixture is `test/d3dcompiler_contract.c`. Its
single-prefix runner is `scripts/probe-d3dcompiler-contract.sh`; it validates
the existing receipt-backed prefix before execution, never creates a prefix,
and records `wineboot=not-run`. The runner compiles and executes ARM64,
ARM64EC, x86_64, and i386 PE fixtures with all FEX TSO controls set to zero.

The canonical prefix is
`build/probe-runs/phase-a-graphics-prefix`. The i386 D3D11/D3D12 consumer
lanes use the explicit, hash-backed
`scripts/vkmt-prefix sync-graphics32` operation. It stages only the x32 DXVK
`d3d11.dll`/`dxgi.dll` pair and win32 vkd3d-proton `d3d12.dll`/
`d3d12core.dll`; their source paths and hashes are included in the prefix
manifest and `graphics32-sync.receipt`. No Wineboot or full prefix rebuild is
needed to add this closure.

The retained receipt is
`docs/validation/d3dcompiler-contract-p8-20260803/RESULTS.md`, with the
machine-readable architecture/API table in `capability.tsv`. The final run
returned status 0 and recorded:

| Area | Evidence |
| --- | --- |
| VS/PS/CS, macros, flags, include handler, failures/diagnostics | all four compiler lanes `PASS` |
| Unicode `D3DCompileFromFile`/`D3DReadFileToBlob`, preprocess, disassembly | 43/46/47 rows recorded for every architecture; 46/47 file APIs pass |
| Reflection/signatures and version behavior | 47 metadata pass; 43 `D3DReflect` `E_NOINTERFACE` is explicitly `KNOWN_LIMITATION` |
| Unsupported API behavior | `D3DLoadModule` `E_NOTIMPL`; spec stubs such as compression, trace, `D3DReflectLibrary`, and `D3DSetBlobPart` are explicit `KNOWN_STUB_NOT_CALLED` rows and are never invoked |
| Generated DXBC consumers | i386 DXVK D3D11 readback and vkd3d-proton D3D12 compute pipeline both pass in isolated processes |

The consumer processes are intentionally isolated: combining DXVK D3D11 and
vkd3d-proton D3D12 in one i386 process currently faults after the D3D11 pass.
That boundary is retained as a diagnostic rather than hidden. The table also
keeps all expected missing exports and the d3dcompiler_43 reflection
limitation visible; a green runner status is not a claim that Wine stubs are
implemented. These D3DCompiler DLLs and probe executables are test/runtime
inputs, not package payloads unless separately licensed and promoted.

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
The 12 remaining candidate dispositions and their concrete next actions are
audited in `docs/validation/ai-optimization-candidate-audit-20260803/RESULTS.md`.
After a final existing-prefix Wineboot update, use
`scripts/vkmt-prefix refresh --prefix PATH` once before prepared gates; this
restores any built-in files that Wineboot may replace and does not recreate or
reset the prefix.

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

### Networking, TLS trust, COM/STA, DirectWrite, and CEF text gate (P8, 2026-08-03)

This phase reuses the single receipt-backed prefix
`build/probe-runs/phase-a-graphics-prefix`; no new prefix or wineboot was used.
All lanes set `FEX_TSOENABLED=0`, `FEX_VECTORTSOENABLED=0`, and
`FEX_MEMCPYSETTSOENABLED=0`.

| Area | Implementation / runner | Evidence | Status |
|---|---|---|---|
| WinSock | `test/network_contract.c`, `scripts/probe-network-contract.sh` | `docs/validation/network-contract-p8-20260803/` | ARM64, ARM64EC, x86_64, i386 processes rc=0; IPv4/IPv6, localhost ordering, nonblocking connect, select, WSAPoll, event rearm, IOCP, and parallel close pass; i386 `SIO_ADDRESS_LIST_SORT` is explicit `UNSUPPORTED` / WSAEOPNOTSUPP |
| TLS/trust | `test/tls_trust_contract.c`, `scripts/probe-tls-trust-contract.sh`, `test/browser/tls_connect_delay_proxy.mjs` | `docs/validation/tls-trust-contract-p8-20260803/` | All four architectures rc=0; WinHTTP/WinINet valid root+intermediate+hostname, expired rejection, untrusted-root rejection, and local fragmented CONNECT proxy pass without bypass flags |
| COM/UI/fonts | `test/ui_com_dwrite_contract.c`, `scripts/probe-ui-com-dwrite-contract.sh` | `docs/validation/ui-com-dwrite-contract-p8-20260803/` | All four processes rc=0; STA pump/callback/nested loop/window lifetime, font enumeration/glyphs/layout/fallback pass where supported; standard IStream cross-apartment marshal is explicit `UNSUPPORTED` on all lanes and i386 mixed-script layout metrics are explicit `UNSUPPORTED` |
| CEF text/pixels/trust | `third_party/metalsharp-cef/vkmt_browser_capi.c`, `scripts/probe-cef-osr-render.sh`, `test/tls_trust_contract.c` | `docs/validation/cef-osr-render-p8/RESULTS.md`, `capability.tsv`, and `browser-20260803T145321.log` | CEF data-URL and local-root HTTPS loads pass DOM text, deterministic BGRA, and foreground text pixels; root install/remove is explicit; `--ignore-certificate-errors` is diagnostic-only |

The DirectWrite source audit is
`docs/validation/ui-com-dwrite-contract-p8-20260803/font-source-audit.txt`.
`dlls/dwrite/freetype.c` and `dlls/win32u/freetype.c` were not modified or
promoted in this phase; no optimization is claimed without a benchmark-backed
source change and a passing contract gate.
The old BoringSSL diagnostic note about a custom-FEX `0xc000001d` before
application output is superseded. The current P8 provider and canonical
prepared prefix pass the x86_64 BoringSSL startup/TLS launch with `rc=0`, and
the four-lane FEX startup receipt is
`docs/validation/fex-startup-p8-20260803/RESULTS.md`. The probe remains
diagnostic-only for trust acceptance; WinHTTP/WinINet fragmented lanes remain
authoritative. The updated diagnostic details are in
`docs/validation/tls-trust-contract-p8-20260803/boringssl-diagnostic.txt`.

### Easy Anti-Cheat compatibility phase (P8, 2026-08-03)

The EAC-only contract is implemented by:

- test/eac_contract.c
- test/eac_mock_backend/main.c
- test/eac_mock_backend/vkmt_eac_test_protocol.[ch]
- dlls/vkmt_eac/unix/vkmt_eac.[ch]
- scripts/stage-eac-runtime.sh
- scripts/probe-eac-contract.sh

The host bridge is a test-only dynamically loaded native .so; it is not an
Epic implementation and must never be reported as a real EAC attestation
provider. The loopback backend uses a VKMT-owned protocol and test key. It
covers valid challenge/response, module-digest mismatch, expiration, missing
capabilities, wrong architecture, bad signatures, malformed messages, replay
rejection, backend disconnect, separate client/server restart, four-client
concurrent sessions, and callback/lifetime cleanup.

The official artifacts are kept outside Git at:

/Volumes/AverySSD/anticheat-evaluation/

The canonical prefix was updated in place by scripts/stage-eac-runtime.sh
without Wineboot. Only the required Win64 loading surface was staged under:

drive_c/vkmt-eac-test/

The stage manifest is VKMT_EAC_STAGE.tsv. It records the staged EOS SDK DLL,
protected launcher, EAC setup executable, test settings, dummy target, and
source archive hashes. The official setup executable is never invoked with an
install command; the probe only creates it for a bounded loader test.

Authoritative evidence:

docs/validation/eac-contract-p8-20260803/RESULTS.md
docs/validation/eac-contract-p8-20260803/capability.tsv
docs/validation/eac-contract-p8-20260803/sdk-api-inventory.tsv

The final run returned EAC_CONTRACT_ALL_ARCHITECTURES_OK and status=0.
ARM64, ARM64EC, x86_64/FEX, and i386/WoW64 all passed the VKMT mock contract,
malformed-message and negative matrix, client/server restart, and concurrent
session checks. The x86_64/FEX lane also:

- loaded all selected EOS Anti-Cheat client/server exports;
- created the official start_protected_game.exe;
- created the official EasyAntiCheat_EOS_Setup.exe without installing it;
- recorded launcher/setup exit or bounded-termination results.

The official Win64 launcher is NOT_APPLICABLE to ARM64, ARM64EC, and i386
guest binaries; those lanes retain mock/API coverage. Real EAC backend
attestation remains MISSING_PRODUCT_CONFIGURATION because the downloaded
sample settings contain placeholder product, sandbox, and deployment IDs.
No VKMT_EAC_REAL_ATTESTATION_OK marker exists. Kernel-driver requirements
remain unsupported unless a legitimate platform/vendor implementation is
provided.

EAC binaries are external licensed assets and are never package payloads by
default. They must remain separate-fetch;never-package unless distribution
authorization is separately documented.

### MoltenVK capability-truthfulness phase (P8, 2026-08-03)

`scripts/probe-moltenvk-behavior.sh` is the authoritative native ARM64
Vulkan/Metal fixture. It directly verifies null storage-buffer descriptors and
out-of-bounds storage-buffer/storage-image robustness readback on Apple M4.
It records typed-buffer alignment properties (16-byte storage/uniform
alignment) without claiming unaligned offsets are safe. Transform feedback
and indirect-count behavior are explicitly not advertised: the previous
transform-feedback path only tracked state and skipped capture, so its
extension entry and feature bits were removed instead of being reported as
working.

The source truthfulness change is nested MoltenVK commit `665b11e7`, with the
raw bundling delta in `patches/moltenvk-phase2-665b11e7.patch`; the rebuild
script promotes the resulting universal dylib into
`wine/build-ec/dlls/win32u/libMoltenVK.dylib`. This is a deliberate capability
boundary, not evidence that transform feedback or indirect-count is complete.

Evidence:

docs/validation/moltenvk-behavior-p8-20260803/RESULTS.md
docs/validation/moltenvk-behavior-p8-20260803/capability.tsv

### Graphics behavioral coverage expansion (P8, 2026-08-03)

The following fixtures and runners reuse the receipt-backed canonical prefix
`build/probe-runs/phase-a-graphics-prefix`; none creates a prefix or invokes
Wineboot:

| Area | Source / runner | Evidence | Current truth |
|---|---|---|---|
| D3D11 | `test/d3d11_graphics_contract.c`, `scripts/probe-d3d11-graphics-contract.sh` | `docs/validation/d3d11-graphics-contract-p8-20260803/` | Latest receipt: i386 completes device, VS/PS/CS, compute UAV readback, texture copy/readback, and render-target shader readback. ARM64EC/x86_64 create the device and shaders but retain a bounded structured-UAV compute readback gap (`0x80004005`); the latest ARM64 rerun timed out during provider startup and is not counted green. Swapchain is headless-not-applicable; device-loss injection is not claimed. The runner supports targeted `VKMT_D3D11_GRAPHICS_LANES`. |
| D3D12 | `test/d3d12_graphics_contract.c`, `scripts/probe-d3d12-graphics-contract.sh` | `docs/validation/d3d12-graphics-contract-p8-20260803/` | **All four lanes pass** generated VS/PS, queue/allocator/list, RTV descriptor, graphics pipeline, barrier, render/readback, and fence. ARM64/ARM64EC required the ARM64-safe DXIL-SPIRV TLS fix and rebuilt providers. Existing no-DXGI queue/copy/fence probe remains separate. |
| D3D9 | `test/d3d9_contract.c`, `scripts/probe-d3d9-contract.sh` | `docs/validation/d3d9-contract-p8-20260803/` | Device and texture upload are proven in attempted lanes; both fixed-function and shader textured draw/readback remain unavailable in the current headless DXVK route and are not advertised as passing. Present is no-display only. The runner supports targeted `VKMT_D3D9_LANES`. |
| OpenGL | `test/opengl_extended_contract.c`, `scripts/probe-opengl-extended-contract.sh` | `docs/validation/opengl-extended-contract-p8-20260803/` | Four architecture processes execute and record a no-display boundary on this host. The display-capable fixture contains indexed VBO/EBO, texture sampling, FBO, uniform, sync, sharing, UBO API, present, and resize markers; no headless run is counted as visible-presentation proof. |
| MoltenVK runtime promotion | `scripts/build-moltenvk.sh`, `wine/build-ec/dlls/win32u/libMoltenVK.dylib` | `docs/validation/moltenvk-behavior-p8-20260803/` plus runtime hash | Rebuilt universal MoltenVK is promoted into the actual Wine tree, not only the prefix/package. Runtime extension truthfulness remains authoritative from the direct native behavior receipt. |
| ARM64EC DXMT | `scripts/probe-dxmt-arm64ec.sh` | runner source | WMT bridge proof remains plus a standard `D3D11CreateDevice` lane; this does not convert to a pass until that runner is executed successfully with the paired DXMT provider. |

The capability tables intentionally distinguish `PASS`, `NOT_APPLICABLE`,
`UNAVAILABLE`, and `CRASH_OR_FAIL`; feature enumeration or DLL presence is not
substituted for behavioral proof. The rebuilt i386 vkd3d-proton runtime is in
`third_party/vkd3d-proton/install-win32/bin` and was used by the D3D12 i386
contract. All test environments set FEX TSO modes to zero.

The i386 vkd3d-proton rebuild was performed with
`scripts/build-vkd3d-proton-i386.sh` after the transform-feedback policy
change. The resulting i386 D3D12 device plus graphics render/readback receipt
returned rc=0; older pre-rebuild binaries returned `DXGI_ERROR_UNSUPPORTED`
or `E_INVALIDARG` and must not be used as current evidence.

The ARM64 graphics-pipeline failure was fixed rather than waived. DXIL-SPIRV
had C++ `thread_local` variables that emitted `[x18,#0x58]` accesses in the
ARM64 PE; `subprojects/dxil-spirv/util/vkmt_thread_local.hpp` routes Windows
builds through Win32 TLS and preserves normal native TLS elsewhere. The
reproducible builders are `scripts/build-vkd3d-proton-arm64.sh` and
`scripts/build-vkd3d-proton-arm64ec.sh`. Current installed provider hashes:

```
arm64    d3d12.dll     4abfc19fce06daff755f9a48d3a0a0acefea8fb0c2b85d4d34645d9f5079e40a
arm64    d3d12core.dll 7d3900ebeaac424dbe57fa74a8cdde2e12a93ff21e7d94a2e876063896571775
arm64ec  d3d12.dll     b534c163f6a4409e92669f725d0be2dfee7ce4ad840eaf77a135b2d60eefaf66
arm64ec  d3d12core.dll 152c97a524f7696d37a76d40039bb0791e4681f027c5364f829f71f346be17fd
MoltenVK wine/build-ec/dlls/win32u/libMoltenVK.dylib
         f05d95bb072630c301228752ecdbe5eecc5afce2d3de5365b2a29934fd32e0f2
```

### Graphics infrastructure Phase 0 (P8, 2026-08-03)

`scripts/verify-graphics-infrastructure.sh` is the non-mutating Phase 0 gate.
It verifies the existing receipt-backed
`build/probe-runs/phase-a-graphics-prefix` without creating a prefix or
running Wineboot. It checks the promoted custom FEX providers, universal
MoltenVK, architecture-matched DXVK/vkd3d-proton artifacts, ARM64EC DXMT
artifacts, and native ARM64 `winemetal.so` closure. It also rejects any active
graphics acceptance runner that enables a FEX TSO mode.

The receipt is
`docs/validation/graphics-infrastructure-p8/RESULTS.md` and the artifact
hash/architecture table is `capability.tsv`. The gate returned
`GRAPHICS_INFRASTRUCTURE_P8_OK`; this verifies staging integrity only and does
not claim that the remaining D3D11, D3D9, DXMT full-device,
MoltenVK transform-feedback/indirect-count, or display-backed feature gaps are
complete.

### FEX/WoW64 graphics prerequisite Phase 1 (P8, 2026-08-03)

The nested Wine source promotion is commit `f108c09` in
`wine/wine-11.12`. It makes native guest-range selection retry a concrete gap
when a derived low alias is occupied, while preserving an explicitly
requested guest address. It also makes `NtUnmapViewOfSection` and
`NtUnmapViewOfSectionEx` retire the complete mapping reservation after
commit/decommit interval splitting instead of retiring only the queried
interval. The rebuilt ARM64 WoW64 module is staged in the canonical prefix by
`scripts/vkmt-prefix sync-wow64`.

`test/wow64_vm_contract.c` and `scripts/probe-wow64-vm-contract.sh` now prove
top-down/high-host allocation, guest-aperture pressure, reserve/commit/
decommit/recommit/release, protection, reuse, overlapping file views,
concurrent allocation/mapping pressure, executable reuse, and correlated
i386 FEX invalidation. The all-lane receipt is
`docs/validation/graphics-phase1-wow64-p8/RESULTS.md` with matching
`capability.tsv`; both x64 and i386 returned rc=0 with all FEX TSO settings
zero. On x64, fixed low-host hints are explicitly recorded as the
high-host-aperture policy rather than treated as a false allocation pass.
