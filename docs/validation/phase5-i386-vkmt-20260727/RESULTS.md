# Phase 5 i386 VKMT acceptance

Status: **complete** on 2026-07-28.

## Accepted route

```text
i386 DXVK dxgi.dll + d3d11.dll
i386 vkd3d-proton d3d12.dll + d3d12core.dll
                    |
          i386 Wine PE/WoW64 boundary
                    |
 ARM64 xtajit.dll + wow64.dll + wow64win.dll
                    |
 ARM64 ntdll.so + win32u.so + winevulkan.so
                    |
       pinned ARM64 MoltenVK -> Apple M4 Metal
```

No Rosetta or x86 Mach-O component participates.

## Final gate

The authoritative command is:

```sh
VKMT_P5_TIMEOUT=180 scripts/probe-p5-i386-vkmt.sh
```

`20260728-final-enforced-runner.log` contains:

```text
P5_I386_DLL_LOAD_OK
P5_I386_DXGI_FACTORY_ADAPTER_OK
P5_I386_D3D12_DEVICE_QUEUE_FENCE_COPY_READBACK_OK
P5_I386_D3D11_DEVICE_CLEAR_COPY_READBACK_OK
P5_I386_VKMT_OK
```

The detailed final logs are:

- `20260728-final-clang-wineboot.log`
- `20260728-final-clang-substrate.log` and `.marker`
- `20260728-final-clang-load.log` and `.marker`
- `20260728-final-clang-dxgi.log`
- `20260728-final-clang-d3d12.log`
- `20260728-final-clang-d3d11.log`

The D3D12 fixture proves device creation, a direct command queue, upload to a
default buffer, an explicit resource transition, copy to readback, fence
completion, and exact CPU readback of `0x4b4d5456`. The D3D11 fixture proves
device creation and deterministic offscreen clear/copy/readback, including
clean object teardown.

## Accepted source and reproducibility

- Wine: `97ff7730c9397b6a5d612d638ada7085770b1dad`
- FEX: `baaca85657574a429368e368e99045f2fab04af4`
- DXVK: `ab0f99aca78c1aec72a97f8334ac704f4c9b19f5`
- vkd3d-proton: `3300fe64cc1ecf53ccf06db67f4888b3d84b4a86`

Targeted reproduction commands:

```sh
scripts/build-fex-wow64.sh
scripts/build-dxvk-vkmt.sh 32
scripts/build-vkd3d-proton-i386.sh
scripts/stage-wine-host-libs.sh wine/build-ec
```

Wine itself was never rebuilt wholesale. Only the affected `ntdll`, `wow64`,
`wow64win`, `win32u`, and `winevulkan` targets were rebuilt.

The final i386 runtime DLL SHA-256 values and exact architecture report are in
`20260728-architecture-audit.log`. DXVK and vkd3d-proton were rebuilt with the
in-tree LLVM-MinGW 22.1.8 toolchain immediately before final acceptance.

## Architecture and dependency audit

The audit records:

- ARM64 Mach-O for `wine`, `wineserver`, `ntdll.so`, `win32u.so`,
  `winevulkan.so`, staged FreeType, and staged libpng.
- `IMAGE_FILE_MACHINE_ARM64` for `xtajit.dll`, `wow64.dll`, and
  `wow64win.dll`.
- `IMAGE_FILE_MACHINE_I386` for the accepted DXVK and vkd3d-proton DLLs.
- `sysctl.proc_translated = 0`.
- no remaining Wine/wineserver process.
- valid signatures for staged FreeType and libpng.
- `@loader_path/libpng16.16.dylib` linkage and no absolute Homebrew runtime
  path in that staged closure.

`scripts/probe-p5-i386-vkmt.sh` enforces these invariants before creating its
prefix. `scripts/verify-preservation.sh` independently checks the preserved
runtime inventory.

## Cleanup

Every run used its exact `wine/build-ec/server/wineserver -k` and `-w`.
The final disposable roots and the former 2.6-GiB retained diagnostic root
were moved out of `build/probe-runs`; no Phase 5 prefix remains active.
