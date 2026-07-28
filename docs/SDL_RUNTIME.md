# SDL2 and SDL3 runtime

VKMT carries source-built Windows SDL runtimes for every supported guest ABI:

| Guest ABI | PE machine |
|---|---|
| AArch64 | `IMAGE_FILE_MACHINE_ARM64` |
| ARM64EC | `IMAGE_FILE_MACHINE_ARM64EC` |
| x86_64 | `IMAGE_FILE_MACHINE_AMD64` |
| i386/WoW64 | `IMAGE_FILE_MACHINE_I386` |

The pinned inputs are SDL2 2.32.10 and SDL3 3.4.10. Their upstream release
commits and the VKMT compatibility commits are recorded in
`wine/build-ec/sdl-runtime/manifest.txt`.

Build or restage all architectures:

```sh
scripts/build-sdl-runtime.sh
```

Limit a rebuild with `VKMT_SDL_ARCHES`, for example:

```sh
VKMT_SDL_ARCHES="arm64ec i386" scripts/build-sdl-runtime.sh
```

Run the authoritative single-prefix acceptance gate:

```sh
scripts/probe-sdl-runtime.sh
```

The probe validates SDL version, dummy audio/video initialization, a hidden
window, software-surface fill/readback, event delivery, a worker thread,
dynamic DLL loading, and clean teardown for both SDL generations on every
guest ABI. It also verifies the x86_64 emulator instructions needed by these
builds and rejects Rosetta or non-ARM64 host Wine artifacts.

The i386 runtime is intentionally scalar. Its build disables MMX/SSE and
compiler vectorization, avoiding FEX paths that would otherwise carry a
non-temporal vector store across the guest-page translation boundary.
