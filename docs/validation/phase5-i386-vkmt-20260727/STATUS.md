# Phase 5 i386 VKMT checkpoint — 2026-07-27

## Fixed execution environment

- Retained diagnostic prefix:
  `build/probe-runs/p5-i386-vkmt.NDwg2k/prefix`
- i386 DXVK PEs: `runtime/dxvk-vkmt-1a5919b/x32` (clang 22.1.8 rebuild)
- i386 vkd3d-proton PEs: `install-win32/bin` from source revision
  `3300fe64cc1ecf5`
- Host: ARM64 Wine, ARM64 Winevulkan, pinned ARM64 MoltenVK, Apple M4.
- Every recorded run used that prefix's exact `wineserver -k` and `-w`; no
  Wine process remains after a run.

## Passing boundaries

1. DLL/export loading is already accepted for i386 `dxgi`, `d3d11`, `d3d12`,
   and `d3d12core`.
2. After Winevulkan's generated WoW64 data-pointer thunks were moved to the
   named guest-memory conversion boundary, DXVK creates a Vulkan instance and
   enumerates Apple M4 without a pointer fault.
3. Fresh x32 DXVK now passes the focused i386 DXGI gate:

   ```text
   P5_I386_DXGI_FACTORY_OK
   P5_I386_DXGI_ADAPTER_OK
   ```

   Evidence: `dxgi-geometryfix.log` and
   `dxvk-geometryfix/dxgi_dxgi.log` in the retained run root.
4. The i386 substrate fixture still passes after the focused FEX rebuild:

   ```text
   VKMT i386 WoW64 execution contract passed
   ```

   Evidence: `substrate-after-fex-rebuild.marker`.

## D3D12 device boundary

### 2026-07-28 — i386 D3D12 call-return gate passes

The retained i386 device probe now completes the native ARM64 Vulkan path and
returns successfully from `D3D12CreateDevice`:

```text
P5_D3D12_CALL_RETURN_OK
exit 0
```

The fixed owner was Winevulkan's manual i386 Unix-thunk boundary.  i386
client-object handles are guest VAs even when the Vulkan type is a
non-dispatchable 64-bit handle (`VkCommandPool`).  The native ARM64 Unix side
must translate both pointer storage and those handle values before accessing
the client object.  `make_vulkan` now generates the required conversions for
command-pool creation, `VkCommandBufferAllocateInfo.commandPool`, and direct
manual command-pool arguments such as `vkFreeCommandBuffers`; the generated
`vulkan_thunks.c` is checked in with that source rule.

Evidence retained under the active run root:

- `20260728T0112-d3d12-freefix.marker` and `.log`: native `VkDevice` creation,
  command-pool / command-buffer creation and teardown, then the successful
  D3D12 return.
- `20260728T0115-p4-after-vulkanfix.marker` and `.log`: all Phase 4 i386
  system-contract markers still pass after the Winevulkan change.

Both probes used the retained prefix and ended with that exact prefix's
`wineserver -k` and `wineserver -w`; no Wine process remains.  This is the
D3D12 call-return gate only.  Queue/fence/resource/readback and the DXVK/DXMT
graphics gates remain outstanding.

vkd3d-proton initially returned `E_INVALIDARG` because MoltenVK does not
provide single-texel-buffer alignment. The current VKMT-specific opt-in
(`VKMT_ALLOW_NON_SINGLE_TEXEL_ALIGNMENT=1`) allows the i386 route to progress
past that policy and create a native MoltenVK `VkDevice` on Apple M4. The
dynamic-rendering-unused-attachments message is warning-only in this source.

The remaining failure occurs **after** `VkDevice` creation and before
`D3D12CreateDevice` returns to the i386 fixture. The focused SEH trace records
an ARM64 JIT load from raw guest address `0x0076ef94` with FEX's provider state
register corrupted (`x19 = 1`). This is an FEX native-call/return invariant
failure, not a MoltenVK feature rejection or a Winevulkan pointer conversion
fault.

Evidence:

- first exact capability diagnosis: `vkd3d-i386-run2.log`
- native Vulkan device creation before the return failure:
  `d3d12-alignment.log`
- raw-guest-address FEX fault and recursive exception sequence:
  `d3d12-postdevice-seh.log`, around lines 45518–45540.

The provider has a targeted in-tree repair in
`FEXCore/Source/Interface/Core/JIT/BranchOps.cpp`: i386 dynamic exits recover
the current `CpuStateFrame`, guest page table, and call-return stack from the
Wine x28 TEB before dereferencing `STATE`. It preserves DXGI acceptance but
does not yet cover the post-`VkDevice` return path; it is intentionally not
claimed as a complete repair.

## 5.3.1 — native-callback return contract (current)

The two latest bounded experiments establish the owner more precisely:

1. `CPUState` preservation from `pf_raw` onward already includes `rip`, all
   `gregs`, call-return state, SIMD state, and segment caches. It is therefore
   not a partial guest-register snapshot bug.
2. The generated i386 `Syscall` operation was temporarily changed to tail
   branch to `DispatcherLoopTop` after its native handler. The same raw-guest
   address fault remained. The SEH trace proves why: Wine's callback/SJLJ
   transition bypasses that generated post-call continuation entirely. This
   experiment is not retained as a source change.
3. The first post-`VkDevice` fault is still a generated ARM64 load through
   raw guest address `0x0076ef94`, with `x19 = 1`; its trace is
   `d3d12-dispatch-tail-seh.log` at lines 45506–45528. The preceding native
   callback-side fault has a valid provider state register and appears at
   lines 14254–14276. Thus the state is lost in the FEX
   `SEHFrameTrampoline2Args` / Wine callback-unwind handoff, before the JIT
   continuation can repair it.

The repair sequence is fixed:

1. Map Wine's callback transition and `SEHFrameTrampoline2Args` stack/unwind
   contract instruction by instruction, including the exact nonlocal-return
   target. Do not alter vkd3d-proton, DXVK, Winevulkan, or MoltenVK while
   doing this.
2. Add a focused provider fixture that enters a Unix call which performs an
   i386 callback and verifies FEX's reserved host registers and canonical
   `CpuStateFrame` on return. Its pass condition is no raw low guest pointer
   used as a host address.
3. Repair the trampoline or Wine handoff at the owner boundary, preserving
   ARM64 ABI callee-saved registers and supplying a canonical dispatcher
   re-entry when a callback exits nonlocally.
4. Rebuild only `xtajit.dll`, stage it into this retained prefix, and run the
   focused D3D12 device probe. First required result:
   `P5_I386_D3D12_DEVICE_OK`.
5. Only after that marker, re-run the retained i386 substrate fixture and the
   DXGI factory/adapter probe as regression gates. If either regresses, repair
   the same trampoline owner before advancing to queue/fence/readback.

No fresh prefix is authorized for 5.3.1. Every retained-prefix run is followed
by `wine/build-ec/server/wineserver -k` and `-w`; the most recent run has no
Wine process remaining.

### 2026-07-27 callback-unwind checkpoint

The focused `+seh` trace has now identified the nonlocal-return producer. It
is not an arbitrary native Unix-call escape: i386 `NtCallbackReturn` calls
Wine's `wow64_NtCallbackReturn`, which performs `longjmp()` through the
`Wow64KiUserCallbackDispatcher` frame. Wine then restores its saved ARM64
callee-saved registers and targets `cpu_simulate`'s loop. The saved values
include FEX-reserved register positions (`x19 = 0xfc521000`, `x23 = 0x30`,
`x24 = 0x20`), which makes the next generated ARM64 block dereference an i386
guest virtual address as a host pointer.

The D3D12 trace proves this sequence immediately before the first corrupt
load, after native `VkDevice` creation:

```text
RtlRestoreContext FEX longjmp buffer=... lr=cpu_simulate-loop
x19=0xfc521000 x23=0x30 x24=0x20
handle_syscall_fault ... pc=0x105d20cc4 ... x19=0x1 x24=0x76ef40
```

This does **not** authorize moving `BTCpuUserCallbackReturn` before Wine's
`longjmp` or jumping directly to FEX's dispatcher: Wine must first restore the
saved i386 `orig_ctx`, then invoke that provider hook. The next repair phase
is therefore narrowly constrained:

1. Add an isolated i386 user-callback fixture with FEX-side entry, longjmp,
   post-`orig_ctx` restoration, and reserved-register/state assertions.
2. Capture the required FEX dispatcher entry state at that exact boundary and
   identify whether the callee-save loss belongs to Wine's unwind context or
   FEX's `BTCpuSimulate` re-entry.
3. Repair only that owner boundary, rebuild only `xtajit.dll` and any directly
   affected Wine PE target, then rerun the retained D3D12-device probe.

No new D3D12 loop, new prefix, graphics translation change, or full Wine/FEX
rebuild is justified until the isolated callback contract supplies those
assertions.

### 2026-07-27 late checkpoint — recovery artifact and lifetime

The retained-prefix marker fixture `p5-i386-d3d12-call-contract.exe` narrows
the live failure without graphics tracing:

```text
P5_D3D12_CALL_ENTER
exit 5
```

Thus the i386 vkd3d `d3d12.dll` loads and resolves `D3D12CreateDevice`, but
the call does not return to its caller. A 28 KiB, file-size-capped `+seh`
trace proved two implementation facts which must be preserved in the next
repair:

1. The active recovery implementation is in the ARM64 PE
   `dlls/ntdll/aarch64-windows/ntdll.dll`, not `ntdll.so`. Rebuilding only the
   Unix library does not test a `RtlRestoreContext` change.
2. The FEX outer recovery record is valid and armed at the longjmp boundary,
   but `UnixStateArmed == 0`. The Unix-call snapshot was already cleared, so
   this is a callback/SJLJ return after the direct Unix call, not a direct
   escape from `WineUnixCall`. Redirecting it with the generic FEX recovery
   record produces an invalid unwind frame and must not be treated as the
   final contract.

The next source change is constrained to the callback-return owner: preserve
or reconstruct the canonical FEX continuation only after Wine restores the
callback's `orig_ctx`. Do not broaden the generic `STATUS_LONGJUMP` recovery
predicate, and do not change vkd3d-proton, DXVK, Winevulkan, or MoltenVK.

### 2026-07-28 — callback routing regression result

`RtlRestoreContext` now consumes the FEX recovery record only when its
Unix-call snapshot is explicitly armed. This keeps the normal i386
`NtCallbackReturn` longjmp on Wine's intended path through
`Wow64KiUserCallbackDispatcher`, `orig_ctx` restoration, and
`BTCpuUserCallbackReturn`.

The retained-prefix, source-built Phase 4 fixture was rerun after staging the
targeted ARM64 `ntdll.dll` and `wow64.dll` outputs. It passed every marker,
including `P4_USER_CALLBACK_OK` and `P4_ALL_SYSTEM_CONTRACT_OK`.

The marker-based D3D12 call still stops at `P5_D3D12_CALL_ENTER` (exit 5).
Its new bounded trace repeats callback-return longjmps whose saved target is
inside `Wow64KiUserCallbackDispatcher`; unlike the ordinary fixture, this is
the nested callback case entered while an FEX Unix BOP is active. The next
repair must therefore keep a persistent post-BOP continuation for that nested
return path. A stack-local Unix snapshot is insufficient because it is no
longer armed when the callback longjmp occurs.

An initial provider-owned continuation experiment was built and staged, then
removed after it left this D3D12 marker unchanged while the callback suite
continued to pass. It is not retained as a source change. The next attempt
must first identify the exact native continuation that is live after
`Wow64KiUserCallbackDispatcher` returns; merely overwriting the guest BOP
state from `BTCpuUserCallbackReturn` is insufficient.

### 2026-07-28 — exact post-callback corruption site

The retained-prefix trace is now precise enough to rule out the Vulkan
translation stack and guest-memory publication as the immediate cause.  The
fault is delivered as a write to host `0x7fffb1bcfff0`, which Wine correctly
converts to i386 guest address `0xb1bcfff0`.  The concrete i386 allocation
arena ends at `0xb1aaffff`; this is an invalid guest address.

The reconstructed i386 context names the exact instruction as
`winevulkan.dll+0x5b9e`, inside `is_device_extension_supported()`, at its
call to `strcmp(extension, literal)`.  Both i386 arguments are valid mapped
guest addresses (`edi=0x017a839c` and a literal in the winevulkan image), yet
the generated ARM64 continuation attempts the unrelated write above.  This
proves stale FEX JIT/SRA continuation state after nested callback return; it
is not a Winevulkan import, DLL routing, MoltenVK, or guest-page-table
translation failure.

The next repair is therefore limited to the FEX callback resume contract:
capture and restore the complete provider execution frame required to leave
`BTCpuSetContext(orig_ctx)` and resume the outer simulated call.  Do not alter
Winevulkan, vkd3d-proton, DXVK, DXMT, or VM mappings until that contract makes
the focused D3D12 marker return normally.  Temporary fault-register tracing
used for this result was removed and the targeted `wow64.dll`/`xtajit.dll`
outputs were restaged cleanly.

### 2026-07-28 — rejected callback-resume hypotheses

Three bounded experiments were built only as targeted `wow64fex`/`wow64.dll`
updates and tested against the retained prefix.  All preserved the complete
Phase 4 callback contract, and all left the D3D12 marker at exactly
`P5_D3D12_CALL_ENTER` with exit 5:

1. An explicit Wine-to-FEX pre-callback snapshot and restoration of the
   shadow call-return pointer.
2. Conditional restoration of FEX's upstream cached call-return pointer
   during a scoped Wine user callback.
3. A request to resume the outer Unix-call BOP through FEX's `FillSRA`
   dispatcher entry after `BTCpuUserCallbackReturn`.

The last experiment's capped SEH trace was byte-for-byte equivalent at the
important boundary: the final callback returned through Wine, followed by an
access violation writing guest `0xb1bcfff0`.  The reconstructed guest PC varies
with the JIT code cache (`0x7bdb3846` / `0x7bdc9f13`) while the invalid write
does not, confirming that the continued compiled state—not a stable guest
instruction or Vulkan object—is invalid.

These experiments were removed from the staged runtime.  The retained prefix
is back on the source-built Phase 4-passing baseline:
`phase5-callback-contract-20260728T0022-baseline.markers` contains
`P4_ALL_SYSTEM_CONTRACT_OK`.

The next action is diagnostic, not another resume-policy edit: instrument the
existing `BTCpuUserCallbackReturn` handoff and the outer Unix-BOP return to
prove whether the provider hook is reached and which frame fields differ at
that point.  Keep traces capped and use no relay tracing.
