# P3 loader and session acceptance — 2026-08-01

Status: PASS

- Host Wine and wineserver were ARM64 Mach-O and `sysctl.proc_translated=0`.
- The same committed Wine binary was measured with historical re-exec forced
  by `VKMT_FORCE_WINE_REEXEC=1` and with the production retained wrapper.
- Across three paired runs, initial-process dyld resolutions fell from 1,140
  to 590 and failed path probes fell from 10 to 5: exactly 50% fewer failures.
- Production traces loaded no Homebrew or `/usr/local` dependency.
- The warm i386 resolver trace had zero failed Wine builtin probes, only two
  `tzres.dll` search-tree scans (one per relevant loader), and no false builtin
  search for either FEX provider.
- The prefix-scoped 120-second warm-session helper verified its runtime
  generation receipt and performed exact prefix shutdown.
- Scalar, vector, and memcpy/set TSO settings were all zero.

Terminal marker: `P3_LOADER_SESSION_ACCEPTANCE_OK`
