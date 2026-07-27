# FEX/WoW64 boundary observation — 2026-07-27

This is a Phase 1 observation, not a passing i386 execution result.

## Recorded environment

- FEX source: `1cc4b93e7a71c883ec021b71359f136394dc1f3c`, with the preserved
  local experiment represented by the Phase 1 manifest/diff state.
- Wine source: `07e6a94e02ace0fb2f0da76c2c60a170e1a64164` plus its preserved
  local worktree.
- `i386_smoke.exe`: `IMAGE_FILE_MACHINE_I386`.
- FEX `xtajit.dll`: `IMAGE_FILE_MACHINE_ARM64`.
- `wine`, `wineserver`, and `ntdll.so`: native ARM64 Mach-O.

## Result

Native `wineboot --init` completed with status 0 in a fresh disposable prefix.
The following i386 launch exited with status 1 before the smoke message or a
`BTCpuSimulate` record. Wine mapped the i386 image at `0x1000052...`, proving
the current high-address mapping experiment is selected, and loaded the ARM64
FEX provider.

The loader reported one concrete provider ABI gap:

```text
No implementation for ntdll.dll.RtlWow64SuspendThread imported from xtajit.dll
```

FEX imports that API for non-self thread suspension in
`Source/Windows/WOW64/Module.cpp`. The trace does not prove that this import
was invoked before exit, so it is recorded as an import-contract failure to
close before attributing the terminal launch status to it.

The disposable prefix was stopped through its exact wineserver and removed.
No Wine process remained. `launch.log`, `wineboot.log`, and the manifest are
preserved in this directory; the earlier first-prefix observation remains in
the sibling timestamped directory for comparison.
