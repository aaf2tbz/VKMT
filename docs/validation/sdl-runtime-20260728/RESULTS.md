# SDL2/SDL3 multi-architecture gate — 2026-07-28

Result: **PASS**

One fresh disposable Wine prefix and one wineserver lifetime passed SDL2
2.32.10 and SDL3 3.4.10 on AArch64, native ARM64EC, x86_64, and i386/WoW64.
The prefix was shut down exactly and removed after the run.

## Source revisions

- SDL2 upstream release: `5d249570393f7a37e037abf22cd6012a4cc56a71`
- SDL2 VKMT source: `8f57bf76c15f5ddade4a1156ed24462da5ef5fe2`
- SDL3 upstream release: `8e37db5e797b6167f3a00d697d816a684bd259c7`
- SDL3 VKMT source: `1f46ec8b0761a248448371735ee020f1f58703e4`
- Wine source: `0805c29a251a9d47e6bc2edfc446f2847451090e`

## Behavioral gates

Each SDL generation passed version validation, dummy audio/video
initialization, hidden-window creation, RGBA software-surface fill/readback,
event push/poll, worker-thread return, `LoadLibrary`-equivalent object and
symbol loading, and clean subsystem teardown.

The final output was:

```text
VKMT_SDL_X86_64_MOVNT_OK
VKMT_SDL2_AARCH64_OK
VKMT_SDL3_AARCH64_OK
VKMT_SDL2_ARM64EC_OK
VKMT_SDL3_ARM64EC_OK
VKMT_SDL2_X86_64_OK
VKMT_SDL3_X86_64_OK
VKMT_SDL2_I386_OK
VKMT_SDL3_I386_OK
VKMT_SDL2_SDL3_ALL_ARCHITECTURES_OK
```

## Architecture and host audit

- AArch64 DLLs: `IMAGE_FILE_MACHINE_ARM64`
- ARM64EC DLLs: `IMAGE_FILE_MACHINE_ARM64EC`
- x86_64 DLLs: `IMAGE_FILE_MACHINE_AMD64`
- i386 DLLs: `IMAGE_FILE_MACHINE_I386`
- `wine`, `wineserver`, and `ntdll.so`: ARM64-only Mach-O
- `sysctl.proc_translated`: `0`
- i386 SDL2/SDL3 disassembly: no `MOVNT*` instructions

The staged runtime is `wine/build-ec/sdl-runtime`; its manifest records both
upstream and VKMT source revisions. No failed prefix or diagnostic log was
retained.
