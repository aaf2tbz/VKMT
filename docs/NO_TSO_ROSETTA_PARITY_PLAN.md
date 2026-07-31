# No-TSO Rosetta-Parity Plan

## Goal

Match Rosetta's observable download, synchronization, and child-process
reliability while keeping:

```text
FEX_TSOENABLED=0
FEX_VECTORTSOENABLED=0
FEX_MEMCPYSETTSOENABLED=0
```

No Rosetta process or x86 Mach-O host component may participate. Rosetta is a
behavioral reference only; it is not acceptance evidence for the final stack.

## Phase 0 — Freeze and instrument the current stack

- Preserve current Wine/FEX source and runtime hashes.
- Record Steam-specific wake and handoff changes separately from generic
  synchronization changes.
- Add bounded counters for:
  - WaitOnAddress registrations.
  - Wake-before-wait events.
  - Delivered and retained wakes.
  - Timeouts and synthetic Steam wakes.
  - i386/x86_64 process creation and provider attachment.
- Assert all three FEX TSO settings at process startup.
- Keep logs and disposable state on the external SSD.

Gate:

- Native ARM64 Wine starts normally.
- i386 and x86_64 probes load.
- Instrumentation remains silent unless explicitly enabled.
- No full Wine rebuild.

## Phase 1 — Reproduce Rosetta's tests through FEX

Status: **complete**. Accepted evidence is
`docs/validation/no-tso-phase1-20260731T024459Z/RESULTS.md`.

Port the direct Rosetta tests into Windows PE fixtures for i386 and x86_64:

- One million release/acquire publications.
- WaitOnAddress wake-before-wait.
- Wake while waiter registration is in progress.
- WakeSingle and WakeAll with multiple waiters.
- Repeated timeout versus real-wake races.
- Condition-variable and critical-section ping-pong.
- APC arrival during waits.
- Second-thread and repeated-thread lifecycle.
- 128 concurrent child processes.
- Eight concurrent HTTPS range downloads from the exact Steam CDN package.

Gate:

- Zero stale reads, lost wakes, or stranded threads.
- 128/128 child completions.
- Eight identical downloaded payload hashes.
- Both i386 and x86_64 pass with TSO disabled.

## Phase 2 — Implement the software x86 memory model in FEX

Status: **complete**. Accepted evidence is
`docs/validation/no-tso-phase2-final-v15-20260731T034214Z/RESULTS.md`.

Audit generated ARM64 for:

- Ordinary x86 loads and stores.
- Locked instructions and interlocked operations.
- Compare/exchange loops and memory fences.
- Self-modifying code publication and code-cache invalidation.
- Guest-to-native and native-to-guest transitions.

Implement a dedicated non-TSO correctness mode:

- Use acquire/release operations where they provide the required edge.
- Use explicit `DMB ISHLD`/`DMB SY` ordering for loads, stores, and x86
  Store-to-Load ordering; LDAR/STLR alone do not fully provide that guarantee.
- Use LSE atomics or LDAXR/STLXR loops for locked operations.
- Place transition barriers at Wine Unix-call, syscall, callback, APC, and
  exception boundaries.
- Make guest writes visible before waking another thread.
- Require an acquire operation after a waiter observes a wake.

Gate:

- Dumped ARM64 shows the intended LDAR/STLR/LSE/DMB sequences.
- Phase 1 ordering and synchronization tests pass with every TSO option off.
- The fixtures require no Steam-specific wake injection.

## Phase 3 — Replace Wine's lossy WoW64 wait bridge

Status: **complete**. Accepted evidence is
`docs/validation/no-tso-phase3-wait-final-20260731T034855Z/RESULTS.md`.

- Detect WoW64 at runtime with `WowTebOffset`, never host compile-time
  `__i386__`.
- Replace raw thread-alert delivery with persistent synchronization state.
- Make wake-before-wait survive registration races.
- Eliminate the fixed raw-pointer pending-wake cache. Wakes without registered
  waiters are not retained, so allocation-generation ambiguity cannot arise.
- Prevent pointer reuse from consuming an old wake.
- Prevent event closure while a waker still owns a reference.
- Preserve legal Windows spurious wakes without manufacturing success for
  unrelated waits.
- Cover WakeSingle, WakeAll, timeout, process exit, APC, and exception
  interruption.

Gate:

- Every Phase 1 wait/wake race passes repeatedly.
- No pending-wake overflow or address-reuse failure occurs.
- Steam's synthetic RtlWaitOnAddress recovery can be disabled.

## Phase 4 — Fix asynchronous networking

Status: **complete**. Accepted evidence is
`docs/validation/no-tso-phase4-final-v5-20260731T040055Z/RESULTS.md`.

Run the exact Steam CDN fixture through Windows APIs:

- WS2_32 connection and TLS traffic.
- Multiple simultaneous package requests.
- Partial reads and completion callbacks.
- Connection reuse and HTTP range restart.
- Server close during a pending receive.
- IOCP/threadpool completion.
- Worker shutdown while callbacks are outstanding.

Trace only these transitions:

```text
request submitted
socket readable
bytes received
completion queued
completion consumed
package committed
```

Gate:

- No HTTP 200 response completes with zero bytes.
- No package is reported missing after reaching its expected byte count.
- Eight concurrent i386 and x86_64 transfers match native/Rosetta hashes.
- No wake injection occurs while traffic is actively progressing.

## Phase 5 — Match Rosetta's child-process contract

Status: child-process/provider mechanics accepted on 2026-07-31. Evidence:
`docs/validation/no-tso-phase5-v8-20260731T041911Z/RESULTS.md`.

The accepted fresh-prefix fixture proves the i386-to-x86_64 provider handoff,
inherited environment/CWD/standard handles/events/raw kernel handles, and exact
wait/exit behavior. Exact SteamService plus i386/x86_64 Steam client probes
pass. Raw inherited socket handles follow Windows semantics: they remain valid
kernel handles but require `WSADuplicateSocket`/`WSASocket` before Winsock use.
No `ws2_32` compatibility deviation was retained.

Validate the full Steam architecture chain:

```text
SteamSetup.exe (i386)
  -> steam.exe bootstrapper
  -> SteamService.exe
  -> x86_64 Steam update
  -> final Steam.exe
  -> steamwebhelper.exe
```

For every child:

- Attach the correct FEX provider before its first guest instruction.
- Preserve inherited handles, environment, current directory, sockets, and
  standard handles.
- Stage i386 and x86_64 modules from the same prefix.
- Preserve process-exit and wait semantics.
- Prevent fallback to Rosetta.
- Keep the native host side ARM64.

Gate:

- 128/128 generic CreateProcess fixtures pass.
- SteamService loads and exits correctly.
- i386-to-x86_64 updater transition occurs in one prefix.
- Final Steam and WebHelper children start without manual intervention.

The last two application-specific transition bullets are exercised by Phase 6
with the real Steam parent. `steamwebhelper.exe` cannot validly be sustained as
a fabricated standalone child because Steam supplies its Chromium IPC and
window-handle command line.

## Phase 6 — Clean Steam acceptance run

Use a fresh Steam installation in the existing all-architecture prefix.

Gate ladder:

1. Installer UI completes.
2. First download reaches the exact expected byte count.
3. Extraction completes.
4. Installation completes.
5. `Update complete, launching Steam` appears.
6. The updater exits naturally.
7. The next Steam process starts automatically.
8. The x64 follow-on update completes.
9. SteamUI.dll and both steamclient DLLs exist and load.
10. Steam WebHelper starts.
11. The login UI paints and remains responsive.

Rules:

- A log observer may report progress but must not influence execution.
- Synthetic Steam wakes and external forced-relaunch supervisors do not count
  as success.
- Failed attempts remove only exact Steam state and temporary logs before the
  next run.

## Phase 7 — Remove compatibility scaffolding

- Disable or remove the Steam-specific synthetic wake path.
- Remove the forced updater-relaunch workaround.
- Retain the generic FEX memory-ordering and Wine wait/wake corrections.
- Run ARM64, ARM64EC, x86_64, and i386 single-prefix gates.
- Run Java, CEF, Vulkan, DXMT, OpenGL, SDL, and controller regressions.

Final audit:

- Every host Mach-O executable and Unix bridge is ARM64.
- `vmmap` shows no Rosetta runtime mapping.
- No translated macOS process exists.
- All three FEX TSO options are confirmed disabled.
- Generated ARM64 contains the required acquire/release and barrier operations.
- Commit accepted Wine/FEX changes and update `AGENTS.md`.
- Produce a new `.tar.zst` recovery archive.

## Immediate next action

Begin Phase 6 with a clean all-architecture Steam prefix. Run SteamSetup and
observe—without influencing—the download, extraction, install, natural updater
exit, i386-to-x86_64 client transition, real Steam-parent WebHelper launch, and
responsive login UI. Keep all TSO options and synthetic wake/relaunch recovery
disabled.
