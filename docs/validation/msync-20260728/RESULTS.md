# MSync acceptance — 2026-07-28

Result: PASS

## Build gates

- `make -j8 server/wineserver`: PASS
- `make -j8 dlls/ntdll/ntdll.so`: PASS
- Host `wine`, `wineserver`, and `ntdll.so`: ARM64 Mach-O

Only the affected Wine targets were rebuilt. No full Wine rebuild was run.

## Toggle and synchronization contract

Command:

```sh
scripts/probe-msync.sh
```

Results in one fresh prefix with an exact wineserver stop between modes:

- `WINEMSYNC` unset: PASS
- `WINEMSYNC=0`: PASS
- `WINEMSYNC=1`: PASS
- Enabled server printed `msync: bootstrapped mach port` and
  `msync: up and running`.

All modes passed manual and auto-reset events, semaphore count/limit behavior,
recursive mutexes, abandoned mutex recovery, wait-all, signal-and-wait,
alertable APC delivery, second-thread lifecycle, and a named manual-reset event
opened and signaled by a child process.

## Architecture regression with MSync enabled

Command:

```sh
WINEMSYNC=1 VKMT_P6_TIMEOUT=120 scripts/probe-p6-single-prefix-architectures.sh
```

Markers:

```text
P6_SINGLE_PREFIX_ARM64_OK
P6_SINGLE_PREFIX_ARM64EC_OK
P6_SINGLE_PREFIX_X86_64_OK
P6_SINGLE_PREFIX_I386_OK
P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
```

The successful and failed disposable run roots were stopped through their
exact wineservers and removed. No Wine process or probe prefix remains.
