# Phase 7 VKMT D3D9 loading acceptance

Status: **pass** on 2026-07-28.

The authoritative command is:

```sh
scripts/probe-p7-vkmt-d3d9.sh
```

One fresh prefix and one wineserver lifetime produced:

```text
P7_VKMT_D3D9_ARM64_OK
P7_VKMT_D3D9_ARM64EC_OK
P7_VKMT_D3D9_X86_64_OK
P7_VKMT_D3D9_I386_OK
P7_VKMT_D3D9_ALL_ARCHITECTURES_OK
```

## Acceptance contract

For each guest architecture the probe:

1. loads the matching app-local DXVK 3.0.2 `d3d9.dll`;
2. resolves and calls `Direct3DCreate9`;
3. enumerates one D3D9 adapter;
4. obtains D3D9 device capabilities, including vertex shader 3.0 and pixel
   shader 3.0;
5. proves that DXVK selected Apple M4 through the pinned MoltenVK ICD.

The host `wine`, `wineserver`, `ntdll.so`, `winevulkan.so`, Vulkan ICD, and
MoltenVK path remain native ARM64. The i386 frontend executes through the
ARM64 FEX/WoW64 provider and loads the `IMAGE_FILE_MACHINE_I386` DXVK DLL.
The x86_64 guest uses the source-built ARM64EC DXVK DLL so no x86_64 Mach-O
or Rosetta route is introduced.

The i386 headless run reports `D3DERR_INVALIDCALL` from
`GetAdapterIdentifier` because DXVK's Win32 WSI cannot obtain a default
monitor name in that route. This call is recorded but is intentionally not
part of the loading gate: `GetAdapterCount` and the display-independent
`GetDeviceCaps` both pass. Phase 7 does not claim D3D9 device creation,
rendering, swapchain, or presentation.

## Staged DLLs

```text
ARM64:
  SHA-256 a10f538f034b48b8f39ed39fd0f8915a29cab37ab8af591bf2ab8184a984d2be
ARM64EC:
  SHA-256 d6b1ede701826246ba20bfec59d8897009eff91d4e9f08ce850659f973d4dcad
i386:
  SHA-256 bcb93034c769ae910bf4439a81e09b0cfcbd3093f949b65788147be991ed9d91
```

The ARM64 and ARM64EC D3D9 DLLs were post-linked with the in-tree
`fix-x18-tls.py` repair and audited to contain no remaining x18-based TLS
loads. The first ARM64EC attempt exposed a stale pre-MoltenVK-policy D3D9
stage; `build-dxvk-arm64ec-d3d9.sh` now rebuilds and stages the focused target.
The accepted DXVK source revision is
`58f17bb4839631aae49bdf221d01cfb17ed79aa8`, which preserves the i386
cross-build configuration in the nested repository.

The retained evidence is limited to logs in this directory. The successful
prefix was stopped through its exact wineserver and removed after archival.
