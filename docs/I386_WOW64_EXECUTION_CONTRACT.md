# i386/WoW64 execution contract

This document is the implementation and acceptance contract for Phase 3. It
does not describe a low-address compatibility mode. The supported design is a
native ARM64 Wine process hosting a native ARM64 FEX `xtajit.dll`, with i386
addresses represented independently from Darwin host pointers.

## Address ownership

- Wine owns the i386 guest virtual-address space and is the sole authority for
  assigning, mapping, protecting, and retiring guest ranges.
- A guest address is always a 32-bit value. A host pointer may be anywhere in
  the ARM64 address space and must never be truncated, biased, or used as the
  source of a guest address.
- Wine publishes explicit `(guest page, host page)` records to FEX. FEX may
  resolve a host notification back through those records, but it may not
  invent a mapping or derive a guest address by truncating a host pointer.
- The guest page size is 4 KiB. Host VM operations must respect Darwin's actual
  host page size, currently 16 KiB on Apple Silicon. Adjacent guest pages are
  not required to have adjacent host backing.

## Publication and invalidation ordering

Successful allocation or section mapping is published in this order:

1. Wine commits the native mapping and assigns its guest range.
2. Wine commits the range to its authoritative registry.
3. Wine publishes the guest-page records to FEX with release ordering.
4. Wine sends the host-range protection/image notification to FEX.

Successful release or unmap is retired in this order:

1. Wine retains the guest identity and host range before invoking the native
   operation.
2. FEX invalidates translated code and prevents new use of the retiring host
   range.
3. Wine commits the successful native release/unmap.
4. Wine unpublishes the guest pages and retires the registry entry.

Protect, dirty, and instruction-cache notifications keep the guest identity
stable. Guest-map publication and host-range code invalidation are separate
interfaces even when one VM operation triggers both.

## FEX execution invariants

- EIP, ESP, all i386 GPRs, FS base, stack entries, BOP return addresses,
  callback frames, APC frames, and exception frames remain guest values.
- Instruction fetch and every generated guest-memory access resolve through
  the published page map. Cross-page accesses translate every participating
  guest page and never assume contiguous host backing.
- Unmapped, non-executable, or inaccessible guest pages raise the corresponding
  guest exception. A null page-table entry must not become a host address.
- Mapping changes are observed through acquire/release publication of the
  page-table entries. Wine's serialized memory notifications evict guest-keyed
  decode and execution-cache entries before stale code can run.
- FEX code-cache memory is host-only. Every dispatcher, initial thunk, compiled
  block, link patch, and unlink patch follows one audited Darwin W^X protocol
  and flushes the ARM64 instruction cache before execution.

## Extended independent gate ladder

This follow-on ladder is intentionally split so a failure has one likely
owner. The current Phase 3 fixture implements the basic, SMC, and lock cases,
plus loader/syscall-boundary coverage needed to reach them:

1. `basic`: arithmetic, branches, calls, returns, and process exit.
2. `stack`: deep calls and a return frame crossing a guest-page boundary.
3. `memory`: lifecycle and scalar/vector accesses across non-contiguous host
   pages, including 32-bit effective-address wrapping.
4. `fetch`: an i386 instruction crossing a guest-page boundary.
5. `smc`: RW -> RX execution, RX -> RW modification, flush, and re-execution.
6. `locks`: interlocked operations and a contended critical section using two
   guest threads.
7. `boundary`: BOP syscall and Wine Unix-call argument/return frames.
8. `exceptions`: breakpoint, access violation, APC, and user callback delivery.
9. `lifecycle`: imports, TLS, second-thread startup/exit, `wineboot`, and clean
   wineserver shutdown.

The aggregate i386 smoke probe is acceptance evidence only after all focused
gates pass in a new prefix. Every disposable run root lives below
`build/probe-runs` on the external SSD and is stopped through its exact
`wine/build-ec/server/wineserver` before the exact run root is moved to Trash.

## Current Phase 3 completion evidence

The current Phase 3 execution contract is complete when its aggregate fixture
passes arithmetic, branches, stack calls, critical sections, locked atomics,
executable allocation, and self-modifying-code re-execution in a fresh prefix;
the CPU provider and native Wine processes are ARM64; and no Rosetta or x86
Mach-O dependency participates. The remaining extended ladder items are
separate regression expansion, not evidence already claimed by this fixture.
