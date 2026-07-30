# Windows Java i386/WoW64 J5 acceptance

Date: 2026-07-29

Result: `VKMT_WINDOWS_JAVA_J5_LIFECYCLE_OK`

## Accepted artifacts

- FEX WoW64 provider:
  `build/fex-wow64-java-j5-divide/provider/xtajit.dll`
- Provider SHA-256:
  `fe1345724f6a2950541966515f766099b7bce38701c9960d4be513c27ec81073`
- Targeted Wine `wow64.dll` SHA-256:
  `3f252921f12806907c78a4bf07c1aa5a761ba7882d3b72bb876c1dc316f93e7b`
- i386 JNI fixture SHA-256:
  `c059e1d00af4ff25c19f1f506f3f09a3b127d46cbfceb88e4b3da912879bdeb7`
- Windows i386 runtime: Temurin OpenJDK 8u472-b08 Client VM
- Host execution: native ARM64 Wine and native ARM64 FEX PE provider

The accepted provider remains a side candidate. J5 did not overwrite the
canonical known-good provider.

## Canonical gate

Command:

```sh
scripts/probe-windows-java-j5-lifecycle.sh
```

One clean prefix completed 10 JVM launches with 10 lifecycle iterations per
launch: 100/100 total. Wall time was 50.95 seconds.

Each iteration proved:

- four Java worker threads executing a C1-compiled kernel;
- allocation and rooted-object traversal while full GC safepoints ran;
- JNI native-thread attach, Java callback during GC, and detach;
- i386 PE TLS isolation;
- APC delivery through an alertable wait;
- compiled null and integer-divide exception delivery;
- worker and JVM process exit without retained fixture processes.

Launch 0 also proved a controlled normal-HotSpot
`SuspendThread` → `GetThreadContext` → `SetThreadContext` → `ResumeThread`
roundtrip. The gate recorded 10 successful JNI callbacks per launch and
`exact_shutdown=1`.

## Owning fixes

- FEX translates host code-cache addresses back to canonical i386 guest VAs
  before invalidating translated lookup state.
- Native x86 HotSpot code-cache patches are detected through tracked
  writable-executable ranges. Only ranges currently writable are invalidated
  and reprotected.
- Synchronization is deferred while another guest thread is executing
  translated code, keeping ordinary waits from perturbing active mutators.
- The WoW64 suspend path no longer holds the global thread-map mutex while it
  forces a target out of translated execution.
- Cross-thread context locking never imports the caller's WOW64 CPU area into
  the suspended target.
- A no-op context roundtrip preserves the provider call-return continuation.
- Wine invokes dynamic-code synchronization only after non-alertable single
  waits. Alertable APC waits retain their nested callback-return contract.
- Compiled i386 divide-by-zero faults carry exact guest RIP and map to
  `EXCEPTION_INT_DIVIDE_BY_ZERO`.

## Regression

After the final J5 build, `scripts/probe-i386-wow64-phase4.sh` passed:

- `P4_CONTEXT_OK`
- `P4_SEH_OK`
- `P4_APC_OK`
- `P4_SECOND_THREAD_OK`
- `P4_USER_CALLBACK_OK`
- `P4_THREAD_LIFECYCLE_OK`
- `P4_ALL_SYSTEM_CONTRACT_OK`
- `VKMT i386 WoW64 execution contract passed`

The probe scripts stop and wait for the exact wineserver and delete their
exact disposable run roots. No J5 or Phase 4 prefix, Java fixture process, or
Wine fixture process remained after acceptance.

## Reproducibility

- `patches/fex-2607-java-j5.patch`
- `patches/wine-11.12-java-j5.patch`

Both patches passed `git apply --check` against their recorded source commits.
Raw launch summaries are in `RESULTS.txt`; compilation, phase, context, and
cycle markers are in `compilation-and-cycles.txt`; JNI exports are in
`jni-i386-exports.txt`.
