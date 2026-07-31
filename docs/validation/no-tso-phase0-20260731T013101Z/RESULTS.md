# Phase 0 no-TSO freeze and instrumentation results

## Result

Phase 0 passes with the v12 candidate providers. The accepted runs use:

```text
FEX_TSOENABLED=0
FEX_VECTORTSOENABLED=0
FEX_MEMCPYSETTSOENABLED=0
```

The canonical known-good provider files were preserved and were not
overwritten during candidate development.

## Frozen lineage

- Wine source HEAD: `fb22a9782ad812d0cf9df9021047eccee84b5135`
- FEX source HEAD: `6b17b7c1ed15825e218358bc04580a6b08c3c890`
- Initial source state, full binary diffs, runtime hashes, architectures, and
  the separated Steam/generic synchronization surfaces are stored at the root
  of this evidence directory.
- Post-v12 source and runtime state is stored in `post-v12/`.

Accepted provider candidates:

```text
b2a24e4585b44119b1d8ff9a8907987036ab8ed7992d6dcb148600fbaba4422e  candidates/xtajit-authoritative-v12.dll
455730fec28029be1c646147214f164164726f1ee5b542f2f69b409b11a07c86  candidates/xtajit64-authoritative-v12.dll
```

Targeted Wine artifacts used by the accepted run:

```text
ecb929747c3054bf392d1a7785c180e2a6cc24213164b0e65f6ec562b46775b0  wine/build-ec/dlls/ntdll/aarch64-windows/ntdll.dll
e8e9491dee4ec8d2b919c60750fdb9adf629e7ce65415f67b9e6a6d43d1c8c8c  wine/build-ec/dlls/wow64/aarch64-windows/wow64.dll
```

The Wine launcher, wineserver, and native `ntdll.so` hashes are unchanged
between the initial and post-v12 captures. No full Wine rebuild was performed.

## Instrumented acceptance

Evidence: `baseline-authoritative-v12/`

- `status=0`.
- Native ARM64 passed.
- ARM64EC passed and recorded an `arm64ec-x86_64` provider attachment.
- x86_64 passed and recorded an `arm64ec-x86_64` provider attachment.
- i386 passed and recorded:

  ```text
  tso=false vector_tso=false memcpyset_tso=false
  ```

- The Wine handoff records `no_tso_contract=accepted` only after the provider
  initialization function returns.
- Bounded per-process sync summaries record registrations,
  wake-before-wait, delivered/retained wakes, timeouts, and synthetic wakes.
- No fatal, unhandled, segmentation, or contract-violation marker is present.
- The disposable prefix was shut down with the matching wineserver and removed.

## Silent acceptance

Evidence: `baseline-silent-v12/`

- `status=0` with ARM64, ARM64EC, x86_64, and i386 all passing.
- With the metric toggles and FEX logging toggle unset, no `VKMT_NO_TSO`,
  `VKMT_PROVIDER_ATTACH`, or `VKMT_WOW64_SYNC` record is emitted.
- The disposable prefix was removed.

## Hard startup controls

Each negative control uses the same v12 providers, enables exactly one
forbidden effective option, fails the i386 gate before its first guest
instruction, and removes its disposable prefix:

| Evidence | Effective forbidden setting | Status |
| --- | --- | --- |
| `negative-tso-rejection-v12/` | `tso=true` | `1` |
| `negative-vector-tso-rejection-v12/` | `vector_tso=true` | `1` |
| `negative-memcpyset-tso-rejection-v12/` | `memcpyset_tso=true` | `1` |

These controls also proved that FEX's debug-only `LOGMAN_THROW_A_FMT` was not
a valid release invariant. The final provider uses an unconditional fail-fast
trap when any of the three effective settings is enabled.

## Phase 0 implementation notes

- The accepted i386 provider is rebuilt from the authoritative FEX tree; the
  earlier passing Java-lineage provider remains evidence only.
- ARM64EC-only executable allocation is now guarded from the WoW64 provider.
- i386 code validation resolves architectural guest addresses through the
  managed guest-page mapping.
- The Windows i386 JIT state register is x23; ARM64EC uses x24 and does not
  consume Wine's reserved x28 TEB register.
- Wine sync metrics are opt-in through `VKMT_WOW64_SYNC_METRICS=1` and
  `warn+sync`; provider attachment records are bounded to provider startup.
- Steam-specific wake recovery remains separately identified from the generic
  synchronization surface and is not accepted as a substitute for later
  generic wait-bridge work.
