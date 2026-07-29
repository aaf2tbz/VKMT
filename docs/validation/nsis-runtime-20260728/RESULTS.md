# NSIS i386/WoW64 runtime acceptance — 2026-07-28

## Result

PASS. A native ARM64 host build created a fresh Wine prefix and ran a real
relocation-stripped i386 NSIS installer through the FEX-backed WoW64 path.
The installer extracted its payload, the installed payload executed, and the
in-place uninstaller removed the payload, install marker, and registry key.

Accepted marker:

```text
NSIS_I386_WOW64_INSTALL_PAYLOAD_INPLACE_UNINSTALL_OK
```

The `_?=` in-place mode avoids NSIS's separate self-copy launcher. It
necessarily leaves the currently running `uninstall.exe`; that file exists
only in the disposable prefix, which the probe stops through its exact
`wineserver -k/-w` and moves to Trash.

## Reproducible fixture

```text
scripts/build-nsis-fixture.sh
INSTALLER_FIXTURE_NSIS_I386_OK
```

The builder uses the in-tree i386 LLVM-MinGW compiler and verifies that
`makensis` is a native ARM64 Mach-O executable. The accepted installer was
COFF-i386, relocation-stripped, preferred image base `0x400000`.

## Runtime fix

On ARM64 Darwin, Wine cannot map the traditional low DOS range. Its previous
dynamic fallback consumed guest `0x400000`, forcing relocation-stripped NSIS
images away from their required base. Mapping DOS memory at guest zero made
FEX terminate before i386 `main`.

The accepted implementation:

- reserves a dedicated nonzero DOS compatibility slot at guest
  `0x110000–0x21ffff`;
- maps the DOS fallback into that biased host slot;
- translates Wine's guest-coordinate `WINEPRELOADRESERVE` range into host
  coordinates, keeping anonymous startup allocations out of the main image
  range.

Focused controls passed together:

```text
basic exit=0
locks exit=0
smc exit=0
i386-fixed-base exit=0 NSIS_INSTALLED_PAYLOAD_OK
```

## Regression gates

`scripts/probe-i386-wow64-phase4.sh`:

```text
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
```

`scripts/probe-p6-single-prefix-architectures.sh`:

```text
P6_SINGLE_PREFIX_ARM64_OK
P6_SINGLE_PREFIX_ARM64EC_OK
P6_SINGLE_PREFIX_X86_64_OK
P6_SINGLE_PREFIX_I386_OK
P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
```

`scripts/probe-msi-runtime.sh`:

```text
MSI_ARM64_INSTALL_REPAIR_UNINSTALL_OK
MSI_ARM64EC_INSTALL_REPAIR_UNINSTALL_OK
MSI_X86_64_INSTALL_REPAIR_UNINSTALL_OK
MSI_I386_INSTALL_REPAIR_UNINSTALL_OK
MSI_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
```

`scripts/verify-preservation.sh` ended with:

```text
Inventory complete.
```

All disposable prefixes used for the accepted gates were stopped with their
exact wineserver and removed.
