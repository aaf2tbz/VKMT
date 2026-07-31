# Direct Rosetta boundary probe — 2026-07-30

These probes exercised Apple's installed Rosetta runtime directly. Wine and
Game Porting Toolkit were not involved.

## Runtime identity

- `arch -x86_64 sysctl -n sysctl.proc_translated` returned `1`.
- An x86_64 child shell also returned `1` and reported `x86_64`.
- `vmmap` identified the process as `X86-64 (translated)`.
- The process mapped `/usr/libexec/rosetta/runtime`,
  `/Library/Apple/usr/libexec/oah/libRosettaRuntime`, dedicated Rosetta thread
  context and return-stack regions, and a 128 MiB Rosetta JIT region.
- The translated process used Apple's x86_64 dyld, libsystem kernel, pthread,
  dispatch, malloc, unwind, and C runtime libraries.

## Concurrent Steam-CDN transfer

Eight concurrent Rosetta-translated `/usr/bin/curl` children each fetched the
same 4 MiB range from the exact Steam package URL that had returned zero-byte
package failures in VKMT.

- Aggregate result: success.
- Total bytes: 33,554,432.
- Unique SHA-256 payload hashes: 1.
- Temporary transfer files were deleted after validation.

## Child-process handoff

One Rosetta-translated shell created 128 concurrent child processes. Every
child reported `sysctl.proc_translated=1` and reached its completion marker.

- Translated children: 128/128.
- Completed handoffs: 128/128.
- Temporary child files were deleted after validation.

## Ordering and wake behavior

`test/rosetta_sync_probe.c` was compiled as x86_64 and run directly through
Rosetta. It passed:

- 1,000,000 release/acquire data publications with zero stale payload reads.
- 200,000 condition-variable ping-pong rounds per thread with no lost wake.
- Total elapsed time: 838 ms.

The x86_64 compiler emitted ordinary `movl` instructions for the
release/acquire sequence and payload accesses, with no fence or locked
instruction on the successful path. Therefore the successful result depends
on Rosetta preserving x86 ordering semantics beneath the program.

## Finding

Rosetta translates the entire x86_64 Mach-O process and integrates its thread
contexts, child selection, x86_64 libsystem calls, and wait/wake behavior with
macOS. Every x86_64 child automatically receives the same Rosetta contract.

VKMT instead mixes translated Windows guest execution with a native ARM64 Wine
Unix boundary and a custom FEX provider. Guest pointers, thread identities,
wait/wake delivery, exceptions, and process bootstrap all cross that explicit
boundary. Steam's failures are therefore not evidence of a bad CDN or a weak
Rosetta network workaround; they expose an incomplete ordering/wake contract
at the custom FEX/Wine boundary.

The probe cannot establish whether Apple's private runtime uses a hardware TSO
mode, LDAR/STLR, DMB, or a mixture. macOS exposes no memory-ordering TSO sysctl;
the visible `net.inet.tcp.tso` setting is TCP segmentation offload and is
unrelated. The observable contract is what matters: ordinary x86 loads/stores,
pthreads, syscalls, and child processes behave coherently under Rosetta.
