# No-TSO Phase 5 child-process contract

Date: 2026-07-31

## Result

PASS for the child-process/provider handoff contract. The accepted run forced:

```text
FEX_TSOENABLED=0
FEX_VECTORTSOENABLED=0
FEX_MEMCPYSETTSOENABLED=0
```

The fresh-prefix chain was:

```text
i386 root -> i386 service -> x86_64 client -> x86_64 webhelper fixture
```

Both i386 processes attached the WoW64 provider and both x86_64 processes
attached the ARM64EC provider before guest execution. Every stage preserved the
environment sentinel, current directory, standard-output/error pipe, inherited
event, and inherited raw AFD handle. Process waits, exit codes, and final event
signalling completed normally.

## Windows socket semantics

An earlier fixture incorrectly required a raw socket handle inherited through
`CreateProcess`/`DuplicateHandle` to be accepted by Winsock in the child. Wine's
own Windows-conformance test documents that this must return `WSAENOTSOCK`;
cross-process Winsock use requires `WSADuplicateSocket`/`WSASocket`. The
temporary `ws2_32` change was fully reverted and its AArch64/ARM64EC, i386, and
x86_64 PE outputs were rebuilt from the restored source. The accepted fixture
proves that the kernel handle is inherited and that Winsock rejects its direct
adoption, matching Windows.

## Exact Steam artifacts

- i386 `SteamService.dll`: import, TLS, SEH, and non-persistent dispatch probe
  passed.
- i386 `steamclient.dll`: load, imports, exports, factory, and safe-init probe
  passed.
- x86_64 `steamclient64.dll`: the same probe passed.
- x86_64 `steamwebhelper.exe`: AMD64 image and import closure passed static
  inspection.

`steamwebhelper.exe` is intentionally not treated as a standalone sustained
probe. Its Steam parent supplies Chromium IPC channels, process type, and Steam
window handles; fabricated direct arguments trigger the official binary's own
`CHECK`. The valid automatic parent launch is retained as Phase 6's clean Steam
acceptance gate.

## Preservation checks

- Runner status: `0`.
- Disposable prefix and exact wineserver were stopped and removed.
- No Wine, Steam, or wineserver process remained.
- Build-tree providers were restored byte-for-byte:
  - x86_64: `7b9f55ceabe971ffa1f514570bb54ed7b5640959e4440e7f8a013e9af13ab7e6`
  - i386: `7d2ac83d2c0935e04d033d609c42d8307294225dcb4cb16b88af849e95c694ab`

Canonical runner: `scripts/probe-no-tso-phase5.sh`.
