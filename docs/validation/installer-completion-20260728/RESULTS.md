# Installer completion — 2026-07-28

## Accepted gates

- `scripts/probe-msi-runtime.sh`
  - `MSI_ARM64_INSTALL_REPAIR_UNINSTALL_OK`
  - `MSI_ARM64EC_INSTALL_REPAIR_UNINSTALL_OK`
  - `MSI_X86_64_INSTALL_REPAIR_UNINSTALL_OK`
  - `MSI_I386_INSTALL_REPAIR_UNINSTALL_OK`
  - `MSI_SINGLE_PREFIX_ALL_ARCHITECTURES_OK`
- `scripts/probe-installer-extended.sh`
  - `INSTALLER_ARM64_MSI_EXTENDED_OK`
  - `INSTALLER_NATIVE_ARM64_MSI_WIX_EXTENDED_OK`
- `scripts/probe-inno-runtime.sh`
  - `INNO_NATIVE_ARM64_FALLBACK_OK`
  - `INNO_I386_WOW64_COMPILER_OK`
  - `INNO_COMPILED_PAYLOAD_FALLBACK_OK`
  - `INNO_EXECUTION_AND_EXTRACTION_ALL_OK`
- `scripts/probe-installer-classifier.sh`
  - `INSTALLER_CLASSIFIER_DIAGNOSTIC_FAILURE_OK`
- Regression gates:
  - `NSIS_I386_WOW64_INSTALL_PAYLOAD_INPLACE_UNINSTALL_OK`
  - `P6_SINGLE_PREFIX_ARM64_OK`
  - `P6_SINGLE_PREFIX_ARM64EC_OK`
  - `P6_SINGLE_PREFIX_X86_64_OK`
  - `P6_SINGLE_PREFIX_I386_OK`
  - `P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK`
  - `Inventory complete.`

The native extractor is built from innoextract commit
`6e9e34ed0876014fdb46e684103ef8c3605e382e`, staged with its complete ARM64
dylib closure, ad-hoc signed, and audited to contain no `/opt/homebrew` or
`/usr/local` load paths.

Pinned installer hashes:

- Inno Setup 6.5.4:
  `fa73bf47a4da250d185d07561c2bfda387e5e20db77e4570004cf6a133cc10b1`
- Inno Setup 6.3.3:
  `0bcb2a409dea17e305a27a6b09555cabe600e984f88570ab72575cd7e93c95e6`

## Scope boundary

The Inno acceptance gate executes the genuine i386 6.3.3 command-line
compiler through WoW64, compiles a real installer, classifies it, and then
recovers and byte-compares its payload with native ARM64 innoextract. It does
not claim that the Inno 6.5.4 GUI installer transaction completes under Wine.
The native extraction path is the accepted fallback for that case.

The extended MSI/WiX CLI fixture is a native ARM64 gate. All four architecture
modes are accepted through the separate MSI API lifecycle fixture. An x86_64
`msidb` diagnostic printed its usage text instead of receiving the requested
table arguments, so no guest CLI claim is made.

Every accepted probe uses a disposable external-SSD prefix, stops that
prefix's exact wineserver, and removes the run root on success or failure.
