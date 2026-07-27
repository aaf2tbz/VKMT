# Phase 4 i386/WoW64 system-contract acceptance

Date: 2026-07-27

## Authoritative commands and results

All commands ran from `/Volumes/AverySSD/VKMT` against the current in-tree
build. Each probe stopped its exact wineserver and removed its disposable run
root.

```
scripts/probe-i386-wow64-phase4.sh
P4_LOADLIBRARY_OK
P4_SYSCALL_RETURN_OK
P4_TLS_MAIN_OK
P4_CONTEXT_OK
P4_SEH_OK
P4_APC_OK
P4_SECOND_THREAD_OK
P4_USER_CALLBACK_OK
P4_THREAD_LIFECYCLE_OK
P4_ALL_SYSTEM_CONTRACT_OK
VKMT i386 WoW64 execution contract passed

scripts/probe-p1-unified-arm64.sh
P1_UNIFIED_ARM64_AARCH64_ARM64EC_OK

scripts/probe-p2-x64-dxvk.sh
P2_X64_ENTRY_OK
P2_X64_DXVK_D3D11_READBACK_OK
```

The Phase 4 runner compiled an i386 executable and helper DLL, staged 642
source-built i386 Wine DLLs, initialized a new prefix, and ran every Phase 4
gate plus the Phase 3 guest-memory regression in that one prefix. It also
verified that `wine`, `wineserver`, and `ntdll.so` are ARM64-only Mach-O and
that `xtajit.dll`, `wow64.dll`, and `wow64win.dll` are ARM64 PE images. No
x86 Mach-O or Rosetta component is part of this route.

## Fixed contracts

- `NtContinue`'s scalar alertable argument is no longer mistaken for a guest
  pointer by the shared `NtContinueEx` WoW64 wrapper. This restores ordered APC
  delivery and return from the alertable wait.
- `wow64win` imports Wine's canonical guest/host address conversion helpers.
  Generic syscall pointers, output addresses, strings, object attributes, and
  absolute security-descriptor pointers no longer assume a low host address.
- The user-callback fixture uses a thread-local `WH_MSGFILTER` hook. Native
  ARM64 `win32u` calls `KeUserModeCallback`, ARM64 `wow64win` marshals the hook,
  i386 `user32` calls the application hook, and the result returns through
  `NtCallbackReturn`. This is headless and does not create a Wine window.

The focused Wine source commit is `d43a990`.

## Scope boundary for the next graphics phase

Raw 32-bit code-pointer and handle encodings in callback structures remain
intentional. Separate raw data-pointer conversions still present in i386
GDI/D3DKMT marshalling are not covered by this non-graphics system-contract
gate. They must be converted to the canonical guest-memory manager and proven
by the later i386 VKMT/DXMT graphics fixtures; this result does not claim those
graphics gates.
