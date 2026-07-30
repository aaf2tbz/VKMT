# Steam WebHelper ARM64EC syscall-boundary validation

Date: 2026-07-30

## Result

PASS. The installed x86_64 Steam CEF helper ran for the complete 40-second
gate in the existing all-architecture prefix with software TSO both disabled
and enabled. No `chrome_elf` PartitionAlloc trap, provider exception,
unhandled error, segmentation fault, or assertion appeared.

## Root cause and repair

The x64 `NtQueryValueKey` call crossed directly into Wine's internal ARM64EC
syscall hp target. This shortcut bypassed the standard ARM64EC entry thunk,
so native arguments 5+ were not lifted from the x64 stack. The syscall saw
guest `R10/R11` in `x4/x5`, interpreted a pointer as the output-buffer length,
and wrote beyond Chrome's 24-byte registry-query buffer.

`Source/Windows/ARM64EC/Module.S` now:

- loads x64 arguments 5-8 into native `x4-x7`;
- copies x64 arguments 9-16 to an aligned native call frame;
- preserves the guest return address and exact post-pop guest stack pointer
  in that frame across the native syscall;
- restores the native return value to guest `RAX` and resumes the exact x64
  continuation.

The maximum pinned Wine syscall signature is 16 arguments, so the frame
covers the complete syscall table rather than only `NtQueryValueKey`.

## Accepted source and binary

- FEX commit: `6b17b7c1e` (`Complete ARM64EC and WoW64 guest boundary`)
- Provider SHA-256:
  `4d52a4f2a6d6c8587d1d4274346826738026abf2e93a29d591f9574364367db0`
- Candidate, Wine build tree, and prefix provider hashes matched.
- Temporary Steam/allocator diagnostics were removed before the accepted
  rebuild.

## Gates

- `FEX_TSOENABLED=0`: 40 seconds, timeout exit `124` as expected for a
  sustained helper, no failure signature.
- `FEX_TSOENABLED=1`: 40 seconds, timeout exit `124` as expected for a
  sustained helper, no failure signature.
- Exact wineserver shutdown: passed after both runs.
- Remaining Wine/helper processes: none.

Logs:

- `/tmp/vkmt-steamwebhelper-clean-tso0.log`
- `/tmp/vkmt-steamwebhelper-clean-tso1.log`
