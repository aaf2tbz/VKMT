# No-TSO Rosetta-parity Phase 2 results

Status: **PASS**

Phase 2 implements the x86 ordering contract in software. All accepted runs
used:

```text
FEX_TSOENABLED=0
FEX_VECTORTSOENABLED=0
FEX_MEMCPYSETTSOENABLED=0
```

No Rosetta process, Apple TSO mode, FEX TSO mode, or Steam-specific wake
injection participated.

## Accepted providers

- x86_64/ARM64EC `xtajit64-no-tso-final-v15.dll`:
  `a0a586eb6687dd45bdb4818e44c64294f4cfed89dc5b5bafd806c3d402100513`
- i386/WoW64 `xtajit-no-tso-final-v15.dll`:
  `67192836cb4eb15cb51ef5487a4ec30a3fa210bfac370e3193ede3760a4e4273`

The x86_64 provider was rebuilt from the preserved working FEX generation in
`build/recovery-source/VKMT/third_party/FEX-2607`, with release optimization
flags empty and LTO disabled to match the established provider lineage. The
i386 provider was rebuilt from `third_party/FEX-2607`. Both received the
required two-site x18-to-x28 PE TLS fix. The canonical build-tree providers
were restored byte-for-byte after every disposable run.

## Software ordering implementation

- Ordinary and paired guest loads emit `DMB ISHLD` after the load.
- Ordinary and paired guest stores emit `DMB SY` after the store, providing
  the x86 Store-to-Load edge without relying on hardware TSO.
- Forced-TSO IR store forms also end in `DMB SY`; this is an IR correctness
  fallback and does not enable a TSO runtime mode.
- Locked compare/exchange and read/modify/write paths use `CASAL`, `LDSWPAL`,
  `LDADDAL`, or `LDAXR`/`STLXR` loops.
- FEX fences map load to `DMB LD`, store to `DMB ST`, and load/store/MFENCE to
  `DMB SY`.
- Syscall and Unix-thunk transitions emit `DMB SY` immediately before native
  entry and immediately after native return.
- Callback return, native-to-guest callback entry, and ARM64EC native exits
  emit `DMB SY` at the transfer boundary.

The compiled ARM64 emitter objects were disassembled with the pinned LLVM
toolchain. Representative sequences are:

```text
Op_LoadMem:
  mov w1, #0x9                 // BarrierScope::ISHLD
  bl  ARMEmitter::Emitter::dmb

Op_StoreMem:
  mov w1, #0xf                 // BarrierScope::SY
  bl  ARMEmitter::Emitter::dmb

Op_Syscall and Op_Thunk, on both sides of native call:
  mov w1, #0xf                 // BarrierScope::SY
  bl  ARMEmitter::Emitter::dmb

Op_CallbackReturn and ARM64EC native exit:
  mov w1, #0xf                 // BarrierScope::SY
  bl  ARMEmitter::Emitter::dmb
```

`BarrierScope::ISHLD` emits ARM64 opcode `0xd50339bf`; `BarrierScope::SY`
emits `0xd5033fbf`.

## Gates

`scripts/probe-no-tso-phase2.sh` passed in one fresh prefix:

```text
NO_TSO_PHASE2_X64_STORE_BUFFERING_OK
NO_TSO_PHASE2_I386_STORE_BUFFERING_OK
NO_TSO_PHASE2_LITMUS_OK
rounds=1000000
arches=x64 i386
```

Both architectures completed 1,000,000 Store Buffering rounds with zero
forbidden outcomes. `status.txt` is `0`; the disposable prefix was removed
after exact wineserver `-k`/`-w` shutdown.

The complete Phase 1 regression passed against these exact providers. Its
evidence is
`docs/validation/no-tso-phase2-phase1-regression-v15-20260731T034241Z/RESULTS.md`.
