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
- opt-in GLSL 3.30 translation to SPIR-V/MSL, Metal pipeline creation,
  fullscreen triangle submission, and deterministic readback
- the same Wine-facing compile/link/Metal draw/readback path with GLSL 4.50

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

The native `test_metal_renderer` regression passes 29/29, including translated
MSL pipeline creation and command submission.

## Accepted Wine-facing Metal draw boundary

With `VKMT_OPENGL_METAL_EXPERIMENTAL=1`, MetalSharp owns GLSL 3.30 shader and
program handles, preserves OpenGL glslang semantics, assigns omitted
pre-4.30 SPIR-V locations, creates the MSL pipeline, submits `glDrawArrays`,
and reads its offscreen render target through a synchronized, aligned Metal
staging-buffer blit. The Windows fixture reaches this path through Wine's
`opengl32.dll`, not through a native-only shortcut.

Wine routes experimental `glReadPixels` directly to MetalSharp. The normal
macdrv wrapper reads Wine's legacy OpenGL drawable, which is a different
framebuffer from the Metal render target.

The required per-architecture markers are
`OPENGL_<ARCH>_GLSL330_METAL_DRAW_OK` and
`OPENGL_<ARCH>_GLSL450_METAL_DRAW_OK`. ARM64, ARM64EC, x86_64, and i386 all
pass both sequentially in one fresh prefix. The default GL2 path remains
unchanged when the experimental variable is absent.

## Honest remaining boundary

This proves real GLSL 3.30 and GLSL 4.50 rendering through the Windows/Wine
path. It does not by itself prove every OpenGL 3.x/4.x API feature. Indexed
drawing, general vertex layouts and buffers, uniforms, textures/samplers,
guest framebuffer integration, visible presentation, and the broader GL3/4
state/entrypoint surface need their own behavioral gates before making a
complete-API claim.

## Preserved revisions

- VKMT integration and probes: `9954558` plus the GL3.3 gate commit
- Wine 11.12 OpenGL/WoW64 integration: `aaf1da8` plus the Metal readback
  routing commit
- local FEX WoW64 callback contract: `a745bebae`
- MetalSharp shader enum correction: `89d67a2b` plus the program/pipeline/draw
  integration commit
