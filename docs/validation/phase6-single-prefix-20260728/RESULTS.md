# Phase 6 single-prefix architecture baseline

Status: **pass** on 2026-07-28.

One fresh Wine prefix and one wineserver lifetime successfully executed four
separately compiled Windows fixtures:

```text
P6_SINGLE_PREFIX_ARM64_OK
P6_SINGLE_PREFIX_ARM64EC_OK
P6_SINGLE_PREFIX_X86_64_OK
P6_SINGLE_PREFIX_I386_OK
P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
```

The authoritative command is:

```sh
VKMT_P6_TIMEOUT=120 scripts/probe-p6-single-prefix-architectures.sh
```

## Covered routes

- `IMAGE_FILE_MACHINE_ARM64`: native AArch64 Wine PE execution.
- `IMAGE_FILE_MACHINE_ARM64EC`: native ARM64EC PE execution.
- `IMAGE_FILE_MACHINE_AMD64`: x86_64 execution through ARM64EC
  `xtajit64.dll`.
- `IMAGE_FILE_MACHINE_I386`: i386/WoW64 execution through ARM64 FEX
  `xtajit.dll`, `wow64.dll`, and `wow64win.dll`.

The runner stages both CPU providers and the complete source-built i386 Wine
DLL closure before one native ARM64 `wineboot --init`. It then executes all
four fixtures sequentially without changing the prefix or restarting its
wineserver.

`architecture.log` records ARM64-only `wine`, `wineserver`, and `ntdll.so`;
the exact four fixture PE machine types; the provider PE machine types; and
`sysctl.proc_translated = 0`.

The first retained pass is represented by `wineboot.log`, `arm64.log`,
`arm64ec.log`, `x86_64.log`, `i386.log`, and `i386.marker`. Its exact prefix
was stopped and removed after those files were archived. `final-runner.log`
is a second fresh non-retained pass and proves the runner's automatic exact
wineserver shutdown and disposable-prefix cleanup.

This is a CPU architecture and loader baseline. It does not replace the
separate VKMT or DXMT graphics gates.
