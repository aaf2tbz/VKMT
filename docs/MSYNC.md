# macOS MSync backend

VKMT Wine includes the Mach-semaphore MSync backend used by current
CodeWeavers Wine. The implementation was ported from the CrossOver 26.3.0
FOSS Wine 11.0 source bundle to this Wine 11.12 tree, then adapted to Wine
11.12's current in-process synchronization interfaces.

Source provenance:

- Upstream bundle: `crossover-sources-26.3.0.tar.gz`
- Download page: <https://www.codeweavers.com/crossover/source>
- Bundle SHA-256:
  `ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872`
- Preserved reference tree: `third_party/crossover-wine-26.3.0`
- Historical MSync reference: `third_party/wine-msync`

## Toggle

MSync is off by default. Enable it for every process using a prefix:

```sh
WINEMSYNC=1 wine program.exe
```

Explicitly disable it with `WINEMSYNC=0`, or leave `WINEMSYNC` unset. The
optional `WINEMSYNC_QLIMIT` variable changes the Mach message-port queue limit;
the default is 50.

The toggle is a wineserver-lifetime property. Do not mix enabled and disabled
clients under one running prefix server. Stop that exact prefix's server before
changing modes:

```sh
WINEPREFIX=/path/to/prefix wineserver -k
WINEPREFIX=/path/to/prefix wineserver -w
```

The client deliberately rejects a mismatched mode instead of silently using a
different synchronization contract.

## Focused rebuild

Only the server and ntdll Unix library are affected:

```sh
make -C wine/build-ec -j8 server/wineserver
make -C wine/build-ec -j8 dlls/ntdll/ntdll.so
```

If `server/protocol.def` changes, regenerate the checked-in protocol files
first:

```sh
(cd wine/wine-11.12 && ./tools/make_requests)
```

## Acceptance

Run:

```sh
scripts/probe-msync.sh
```

The probe uses one fresh native ARM64 prefix and exact wineserver restarts to
prove unset, explicit-off, and enabled modes. It covers manual and auto-reset
events, semaphore counts and limits, recursive and abandoned mutexes,
wait-all, signal-and-wait, alertable APC delivery, a second thread, and a
named event shared with a child process.

The broader architecture regression also passes with MSync enabled:

```sh
WINEMSYNC=1 scripts/probe-p8-single-prefix-architectures.sh
```

That gate proves ARM64, ARM64EC, x86_64, and i386/WoW64 execution in one fresh
prefix while every host executable and Unix library remains ARM64.
