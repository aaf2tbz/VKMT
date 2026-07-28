# MSI/WiX core lifecycle — 2026-07-28

`scripts/probe-msi-runtime.sh` built x86 and x64 MSI databases from the pinned
WiX source using native ARM64 `wixl` 0.106, then passed this lifecycle in one
fresh prefix for ARM64, ARM64EC, x86_64, and i386/WoW64:

1. Install the embedded-cabinet payload and HKCU registry value.
2. Deliberately replace the installed payload with invalid content.
3. Repair with `REINSTALL=ALL REINSTALLMODE=amus` and verify restoration.
4. Uninstall and verify the Windows Installer product state is absent.

Final marker:

```text
MSI_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
```

The disposable prefix was stopped through its exact wineserver and removed.
This is the MSI core lifecycle gate. Major upgrade, rollback, services,
shortcuts, environment changes, custom actions, and the direct `msiexec` /
`msidb` command-line surfaces remain explicit Phase C work.
