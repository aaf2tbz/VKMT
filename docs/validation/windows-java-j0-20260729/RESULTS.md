# Windows Java J0 acceptance

Phase J0 passed on 2026-07-29.

## Inputs and staging

- Windows i386 Temurin 8u472-b08:
  `21a2c5af684a658f1484daa85eabf4961ab9de28c0efbf31da2381d77fce3b5f`
- Windows x86_64 Temurin 8u492-b09:
  `bb25b002556afc7ef158cd95ec6270dddb3eecba69acdd7abb9d28b2e9ff0f5e`
- The i386 stage contains 107 PE32 files and
  `bin/client/jvm.dll`.
- The x86_64 stage contains 104 PE32+ files and
  `bin/server/jvm.dll`.
- Every staged EXE/DLL has the expected machine type. Both stages have the
  matching in-tree Wine UCRT and VCRUNTIME140 closure.

The accepted four-architecture Wine baseline remains the
`P6_SINGLE_PREFIX_{ARM64,ARM64EC,X86_64,I386}_OK` run recorded in
`AGENTS.md` and preserved by
`VKMT-runtime-phase2-20260729-050624.tar.zst`.

## Reproducible FEX source boundary

The recovery archive proved that its
`build/fex-wow64-baseline-build/Bin/libwow64fex.dll` is byte-for-byte the
accepted i386 provider. Its actual source was the archive's
`build/fex-wow64-baseline-src`, not the archive's later
`third_party/FEX-2607` worktree.

That exact source plus the Java software-ordering delta is retained at:

`third_party/FEX-2607-java-baseline`

The final side-built candidate is:

- `build/fex-wow64-java-final/provider/xtajit.dll`
- SHA-256:
  `f7ace1980b33e270c9ee8b9d240705a82bcface99e868ff65895a3dbcfd4d247`

The builder accepts `VKMT_FEX_SOURCE`, refuses output anywhere in the
canonical Wine build, and requires explicit promotion. No candidate was
promoted.

## Software TSO proof

The final disposable-prefix gate was:

```sh
VKMT_FEX_SOURCE="$PWD/third_party/FEX-2607-java-baseline" \
VKMT_XTAJIT_SOURCE="$PWD/build/fex-wow64-java-final/provider/xtajit.dll" \
VKMT_XTAJIT_SHA256=f7ace1980b33e270c9ee8b9d240705a82bcface99e868ff65895a3dbcfd4d247 \
scripts/probe-windows-java-j0-tso.sh
```

Terminal marker:

`VKMT_WINDOWS_JAVA_J0_TSO_OK f7ace1980b33e270c9ee8b9d240705a82bcface99e868ff65895a3dbcfd4d247`

The i386 fixture returned:

`JAVA_TSO_PREFLIGHT_OK checksum=00000000a5a50ff0 aligned32=12345678 aligned64=1122334455667788`

Offline disassembly of 629 generated blocks proved:

- `LDAR`/`LDARB`/`LDARH` aligned loads;
- `STLR`/`STLRB`/`STLRH` aligned stores;
- ordinary unaligned load followed by `DMB ISHLD`;
- `DMB ISH` followed by an ordinary unaligned store;
- `CASAL` acquire/release locked operations;
- no `LDAPR` or `LDAPUR` family instructions.

The emitter computes and truncates the complete i386 effective address before
Wine's guest-page-table lookup, preserves NZCV across alignment selection,
and emits both paths before JIT-page publication. Windows FEX does not call
`TryEnableHardwareTSO()` or `SetHardwareTSOSupport(true)`.

## Preservation and cleanup

The accepted provider hashes remained unchanged:

- i386:
  `ea523a42ca8e7965371122bd7be1eb6b973cded50ecda5da1465b2961ad36479`
- x86_64:
  `7b9f55ceabe971ffa1f514570bb54ed7b5640959e4440e7f8a013e9af13ab7e6`

The canonical build copies match those hashes. The disposable prefix and JIT
trace were removed after exact wineserver shutdown. No
`windows-java.j0-tso.*` probe root or Wine/Java process remains.
