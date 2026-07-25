# VKMT wine patch series

- `wine-11.12-vkmt.patch` — apply to pristine wine-11.12.tar.xz (`patch -p1 < patches/wine-11.12-vkmt.patch`).

Also required (not in the patch): the bundled llvm-mingw toolchain header
`aarch64-w64-mingw32/include/winnt.h` has `__mingw_current_teb` moved from x18 to x28
(VKMT keeps the Windows TEB in x28 because the Darwin kernel scrubs x18 on every
kernel->user boundary). All aarch64 PE code is built with `-ffixed-x18 -ffixed-x28`.

arm64ec is currently disabled in `scripts/build-wine.sh` (--enable-archs=aarch64,x86_64,i386).
