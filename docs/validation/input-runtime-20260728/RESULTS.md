# Input runtime acceptance — 2026-07-28

## Result

`scripts/probe-input-runtime.sh` passed in one fresh prefix for:

- ARM64
- ARM64EC
- x86_64 through the native ARM64 execution provider
- i386/WoW64 through the native ARM64 execution provider

The final marker was:

```text
INPUT_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
```

Every architecture loaded and exercised `xinput1_1.dll`, `xinput1_2.dll`,
`xinput1_3.dll`, `xinput1_4.dll`, `xinput9_1_0.dll`, and `xinputuap.dll`.
The gate resolves state, capabilities, and vibration exports, verifies invalid
controller indices, polls all four valid indices, and sends a zero-vibration
request when a controller is connected.

DirectInput 7 and DirectInput 8 creation and enumeration passed. DirectInput 8
also created Wine's keyboard and mouse devices.

## Host route

`wine`, `wineserver`, and `dlls/winebus.sys/winebus.so` were verified as
ARM64-only Mach-O files before execution. The PE-facing input stacks include
the architecture-appropriate XInput, DInput, `winexinput.sys`, and
`hidclass.sys` modules. The host-facing route is Wine's macOS IOHID backend in
`winebus.so`; Rosetta is not used.

## Physical-controller scope

No game controller was attached during this session. Every architecture
therefore emitted:

```text
INPUT_NO_CONTROLLER_ATTACHED
```

This is a passing provider/API result, not a fabricated physical-device claim.
Connect/disconnect, buttons, axes, triggers, nonzero vibration, multiple
controllers, Raw Input/HID reports, and DirectInput force feedback remain a
live-hardware acceptance pass. The same probe automatically takes its
connected-device path when hardware is present.

The disposable prefix was stopped using its exact wineserver and removed after
the successful run.
