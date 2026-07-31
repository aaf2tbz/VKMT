# No-TSO Phase 6 extraction failure v3

- Fresh all-architecture prefix.
- `FEX_TSOENABLED=0`, `FEX_VECTORTSOENABLED=0`, and
  `FEX_MEMCPYSETTSOENABLED=0`.
- No Steam wake recovery, forced relaunch, or broad Wine tracing.
- Steam downloaded exactly 336,229/336,229 KiB and entered
  `Extracting package...`, where it stalled.

Live command-line LLDB inspection found the active failure, without waking or
modifying Steam:

- Windows process/thread: PID `0x158`, TID `0x1ac`.
- Host fault: execute access violation at native `PC=0`, with native `SP=0`.
- Wine then called `virtual_setup_exception()` with stack pointer zero. It
  returned `0xfffffffffffffba0`, and `setup_raise_exception()` faulted while
  copying the exception record there.
- The FEX recovery record was valid and armed:
  magic `0x465845574f573634`, dispatcher `0x10004360038`, guest page table
  `0x6ffffac283f0`, current frame `0x7ffd70001140`, call-return cursor
  `0x7ffedb4f1000`, native returning stack `0x7ffedb4f1000`.
- The authoritative guest state remained valid: i386 EIP `0x004fa0f6` and ESP
  `0x01d4fd34`. EIP is the instruction immediately after Steam's direct call
  at `0x004fa0f1`.

This is a native FEX dispatcher-control corruption/re-entry failure followed
by an invalid Wine exception-stack choice. It is not a download, TLS, disk,
Steam wake-polling, or TSO failure.
