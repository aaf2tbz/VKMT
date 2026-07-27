# FEX WoW64 Phase 1 gate

- Fresh disposable prefix; the run root was removed after `wineserver -k/-w`.
- `xtajit.dll` loaded as the native ARM64 CPU provider.
- The provider import `RtlWow64SuspendThread` resolves from the rebuilt ARM64X `ntdll.dll`.
- FEX process and thread initialization returned to Wine.
- Wine then entered `BTCpuSimulate` at `00006FFFFBB54570`.
- The bootstrap was deliberately bounded at 15 seconds (`gtimeout` status 124); later guest execution is Phase 2 work.

The raw bounded trace is `wineboot.log`; `key-lines.txt` contains the gate sequence.
