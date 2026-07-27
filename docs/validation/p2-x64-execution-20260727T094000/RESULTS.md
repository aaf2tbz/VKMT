# Phase 2 x86_64 execution gate

- Host `wine` and `wineserver` were verified as ARM64 Mach-O.
- A fresh disposable prefix was bootstrapped with the in-tree ARM64 wineboot.
- The bootstrap skips only deferred i386 setup and device services for this x64-only gate; those remain Phase 3 work.
- After an exact `wineserver -k/-w` restart, `entry_x64.exe` ran through `xtajit64.dll`, printed `VKMT entry_x64: hello from x86-64 guest`, and returned its expected status `7`.
- The exact run root was removed and no Wine process remains.

The broader DXVK/D3D11 readback script remains a separate graphics regression gate.
