# WoW64/MSync Phase 3 promotion receipt — P8 runtime

Date: 2026-08-03

The existing WoW64 VM and MSync source changes were promoted into the nested
Wine source tree and rebuilt through targeted Wine rules. The canonical prefix
was updated in place with `scripts/vkmt-prefix sync-wow64`; no prefix was
created and no Wineboot was run for this promotion.

## Source promotion

- Nested Wine commit: `656bd43` — `runtime: promote P8 WoW64 and MSync fixes`.
- Source base: Wine 11.12 release commit `996020f`.
- Promoted source areas:
  - WoW64 guest memory/virtual lifecycle and guest pointer conversion;
  - ARM64/ARM64EC signal and FEX memory invalidation paths;
  - MSync server/client pulse and WaitAll rollback behavior;
  - WoW64 USER conversion;
  - native Winsock address-list ordering and guest buffer conversion;
  - relocatable FreeType loading.
- Targeted build completed for NTDLL, WoW64/WoW64Win, WinSock, DWrite,
  Win32U, and wineserver. The actual build tree is
  `wine/build-ec`; this was not a prefix-only replacement.
- Nested push was attempted but its configured `origin` is the unavailable
  local archive path `/Volumes/AverySSD/VKMT-archive-recovery/wine-11.12`.
  The commit is retained locally; VKMT root documentation was pushed to
  `origin/main`.

## WoW64 VM contract

Command:

```sh
FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
  scripts/probe-wow64-vm-contract.sh \
  --prefix "$PWD/build/probe-runs/phase-a-graphics-prefix" \
  --evidence-dir "$PWD/docs/validation/ai-optimization-wow64-phase3-20260803"
```

Result:

```text
WOW64_VM_X64_CONTRACT_OK
WOW64_VM_I386_CONTRACT_OK
WOW64_VM_CONCURRENT_OK
WOW64_VM_MAPPING_PRESSURE_OK
WOW64_VM_ADDRESS_REUSE_OK
WOW64_VM_EXECUTABLE_REUSE_OK
WOW64_VM_FEX_INVALIDATION_OK
WOW64_VM_CONTRACT_ALL_OK
status=0
```

The i386 FEX maintenance summary contained a nonzero invalidation count. The
ARM64EC x64 provider emitted no component FEX TSV row for this fixture, so the
receipt records `unavailable-provider-telemetry` rather than claiming x64 FEX
telemetry.

## MSync contract

The existing canonical prefix passed:

- default synchronization mode;
- explicit `WINEMSYNC=0`;
- enabled `WINEMSYNC=1`;
- stale Mach-port recovery;
- invalid-destination fallback;
- manual-reset pulse;
- auto-reset pulse;
- forced WaitAll rollback;
- child-process synchronization and clean shutdown.

The retained summary reports:

```text
result=PASS
pulse_manual=PASS
pulse_auto=PASS
forced_waitall_rollback=PASS
stale_port_recoveries=11
invalid_destination_diagnostics=11
status=0
```

Evidence is in `ai-optimization-msync-phase3-20260803/` and
`ai-optimization-wow64-phase3-20260803/`. These are functional promotions,
not AI performance claims; the next candidate must still beat the Phase 0
control without regressing these gates.
