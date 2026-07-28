# OpenGL runtime checkpoint — 2026-07-28

## Accepted gates

`scripts/probe-opengl-all-arch.sh` creates one disposable prefix, runs native
ARM64 `wineboot`, and sequentially proves the same Wine OpenGL runtime for:

- AArch64 / ARM64 PE
- ARM64EC PE
- x86_64 PE through `xtajit64.dll`
- i386 PE through `xtajit.dll` and WoW64

Each architecture passes:

- `opengl32.dll` load and core WGL exports
- hidden window, pixel format, and WGL context creation
- Apple M4 / `2.1 Metal - 91.7` renderer identity
- `EXT_framebuffer_object` discovery through `wglGetProcAddress`
- offscreen RGBA8 texture/FBO creation
- deterministic clear/readback (`51,102,153,255`) with `GL_NO_ERROR`
- GLSL 1.20 vertex/fragment compile, program link, triangle draw, and readback

The final marker is:

```text
OPENGL_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
```

The runner verifies that every host Mach-O artifact is ARM64 and that the
runner is not under Rosetta. It performs an exact wineserver stop between GUI
executables and removes only its external-SSD disposable run root.

## Wine fixes

- Wine's OpenGL 2.x extension parser now marks the actual parsed extension
  enum instead of the first N enum slots. This restores valid
  `wglGetProcAddress` publication such as `GL_EXT_framebuffer_object`.
- Generated WoW64 OpenGL thunks now convert i386 guest virtual addresses
  through Wine's canonical guest-memory manager. The generator is the source
  of truth; the generated `unix_thunks.c` was regenerated from Wine's pinned
  Khronos registry commits.
- Nested WGL pointers, returned strings, client context handles, texture/FBO
  output arrays, shader-source pointer arrays, and readback buffers use the
  same conversion contract.
- User callback dispatch temporarily releases recursively held USER locks
  while an i386 window procedure runs, then restores the exact recursion
  depth. No-op hook notification paths no longer assert merely because no
  hook is installed.

The full non-graphics WoW64 regression was rerun after these changes and
reported `P4_ALL_SYSTEM_CONTRACT_OK`.

## MetalSharp shader translator

`scripts/build-metalsharp-opengl.sh` target-builds only the native ARM64
MetalSharp `metalsharp_opengl32` target and stages it as:

```text
wine/build-ec/dlls/winemac.drv/metalsharp-opengl.dylib
```

Its dependencies are pinned in-tree:

- SPIRV-Cross `bccaa94db814af33d8ef05c153e7c34d8bd4d685`
- glslang `46ef757e048e760b46601e6e77ae0cb72c97bd2f`

`scripts/probe-metalsharp-opengl.sh` proves the ARM64 sidecar translates a
GLSL 3.30 vertex shader through glslang to SPIR-V and through SPIRV-Cross to
MSL. Its marker is:

```text
METALSHARP_GLSL330_SPIRV_MSL_OK
```

## Honest remaining boundary

This checkpoint proves a working OpenGL 2.1/GLSL 1.20 rendering path on all
four guest architectures and proves the separate GLSL 3.30-to-MSL translator.
It does **not** yet claim complete OpenGL 3.x/4.x rendering through Metal.

MetalSharp's `GLMetalRenderer` exists and can compile translated MSL, but the
OpenGL entrypoint layer does not yet own program objects, connect translated
vertex/fragment shader pairs to that renderer, or route guest framebuffer
readback/presentation through its Metal texture. Wine therefore keeps
`glCreateShader` on the working system OpenGL route unless
`VKMT_OPENGL_METAL_EXPERIMENTAL=1` is explicitly selected.

The next gate is a GLSL 3.30 program link and deterministic offscreen
Metal-renderer draw/readback through `opengl32.dll`; presentation remains a
later, separate gate.

## Preserved revisions

- VKMT integration and probes: `9954558`
- Wine 11.12 OpenGL/WoW64 integration: `aaf1da8`
- local FEX WoW64 callback contract: `a745bebae`
- MetalSharp shader enum correction: `89d67a2b`
