# No-TSO Rosetta-parity Phase 3 results

Status: **PASS**

Wine's WoW64 `RtlWaitOnAddress` bridge now preserves registration-race wakes
without retaining stale wakes for future calls.

## Contract

- WoW64 is detected at runtime through `NtCurrentTeb()->WowTebOffset`; the
  native ARM64 build architecture is not used as a proxy.
- The compare and waiter registration occur under the address queue lock.
- Each registered WoW64 waiter owns a synchronization event. A waker removes
  the entry and signals that event while holding the queue lock, so a wake
  racing registration cannot be lost and the event cannot be closed early.
- The waiter always reacquires the queue lock before inspecting/removing its
  stack-backed entry. This removes the prior unlocked ARM64 stale-read window.
- Explicit ARM64 memory barriers publish the guest value before wake and form
  an acquire point after either wait transport returns.
- The fixed 16-entry raw-address pending-wake cache was removed. Windows
  `WakeByAddress*` does not create a token when no waiter is registered. This
  eliminates overflow, eviction, and recycled-address consumption rather than
  trying to infer an allocation generation after the fact.
- WakeSingle, WakeAll, timeout races, APC interaction, process/thread exit,
  and event lifetime remain covered by the regression suite.
- Steam-specific synthetic wake recovery was disabled throughout.

The rebuilt ntdll artifacts are:

- ARM64X: `06ae1a34e06de6f385ccea090fd7810b422d1a1dc7c8f2fbdc42d1738699dd91`
- i386: `ede7f7f2f4575e36dc82150d2132f72f9acd3e4bc4910c78e628c5c6f233e3c4`
- x86_64: `81aed28f59b093d9751f02f88c9711b91c8251d6430b2086f2b84ed95cd98b9c`

Only the affected ntdll sync objects and three PE ntdll outputs were rebuilt.

## New regressions

`test/no_tso_phase1_sync.c` now proves both stale-wake cases:

1. A wake issued with no waiter does not satisfy a later unchanged-value wait.
2. A wake from a freed allocation does not satisfy a wait after the exact
   virtual address is allocated again.

Both x64 and i386 emit `NO_TSO_STALE_WAKE_REJECTED_OK`.

## Repeated gates

Three consecutive clean-prefix runs passed with the Phase 2 final providers
and all FEX TSO settings disabled:

- `no-tso-phase3-wait-final-20260731T034855Z`
- `no-tso-phase3-wait-repeat2-20260731T034938Z`
- `no-tso-phase3-wait-repeat3-20260731T035010Z`

Each run passed, on both x64 and i386:

- changed-predicate wake-before-wait;
- 20,000 registration races;
- stale and recycled-address rejection;
- WakeSingle/WakeAll across eight waiters;
- 2,000 timeout-versus-wake races;
- condition variables, APCs, repeated threads, and 128/128 child processes;
- 8/8 simultaneous verified 4 MiB Steam-CDN transfers.

Every `status.txt` is `0`. Exact wineserver shutdown completed, all disposable
prefixes were deleted, and the canonical bootstrap provider bytes were
restored after each run.
