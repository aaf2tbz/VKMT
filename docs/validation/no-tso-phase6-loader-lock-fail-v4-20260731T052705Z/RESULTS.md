# No-TSO Phase 6 loader-lock failure v4

## Runtime policy

- `FEX_TSOENABLED=0`
- `FEX_VECTORTSOENABLED=0`
- `FEX_MEMCPYSETTSOENABLED=0`
- `VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY=0`
- No Rosetta, wake injection, relaunch supervisor, or broad `WINEDEBUG` tracing.

## Progress boundary

The clean v15 provider run downloaded exactly 336229/336229 KiB, extracted the package, installed and committed the update, cleaned up, and reached:

```
Update complete, launching Steam...
Shutdown
```

No successor Steam client or WebHelper appeared.

## Live wait graph

- Main Windows thread 348 waits for Windows thread 356 to terminate.
- Worker threads 356, 372, and 376 each wait in i386 `RtlWaitOnAddress` on guest address `0x7bdff1f8`.
- `0x7bdff1f8` is `loader_section.LockSemaphore` in the loaded i386 ntdll.
- The i386 futex queue contains exactly those three waiters.

## Loader-lock invariant violation

The i386 loader critical section at guest `0x7bdff1e8` contained:

```
LockCount       3
RecursionCount  1
OwningThread    0x160 (Windows thread 352)
LockSemaphore   0
```

Windows thread 352 had already terminated and was absent from the wineserver thread list and process thread-handle table. The active process retained only threads 348, 356, 372, and 376. Therefore the shutdown handoff is deadlocked behind a translated i386 thread that terminated while still owning the loader lock.

## Next diagnostic

Add a fixed-size in-memory trace ring, filtered to loader-lock operations and thread termination, to distinguish:

1. self-termination while recursively owning the loader lock;
2. remote termination while owning the loader lock;
3. exceptional/nonlocal escape from `loader_init` or `LdrShutdownThread`.

The trace must not write to disk or enable broad debugging because those alter Steam download timing.
