#!/bin/sh
# VKMT: rebuild mingw-w64 CRT (libmingwex, libmingw32, crt objects) and
# winpthreads with -ffixed-x18 -ffixed-x28, then install them into the
# llvm-mingw toolchain.
#
# Why: VKMT PE binaries keep the TEB in x28 (Darwin scrubs x18 on every
# kernel->user crossing). The stock llvm-mingw CRT objects are built for
# the standard Windows aarch64 ABI, where x28 is an ordinary callee-saved
# scratch register. Any PE code that calls into CRT routines (mingw
# printf family, gdtoa, winpthreads, ...) clobbers x28 and the next TEB
# access crashes. Rebuilding the CRT with both registers fixed makes the
# toolchain safe for every VKMT PE link.
#
# Stock archives are preserved in <toolchain>/aarch64-w64-mingw32/lib-backup-stock.
set -e

TC=${LLVM_MINGW:-/Volumes/AverySSD/toolchains/llvm-mingw-20260616-ucrt-macos-universal}
SRC=$(cd "$(dirname "$0")/../third_party" && pwd)
TCLIB=$TC/aarch64-w64-mingw32/lib
FLAGS='-O2 -ffixed-x18 -ffixed-x28'
export PATH=$TC/bin:$PATH

[ -d "$SRC/mingw-w64" ] || git clone --depth 1 https://github.com/mingw-w64/mingw-w64.git "$SRC/mingw-w64"

# --- CRT (arm64 only) ---
mkdir -p "$SRC/build-mingw-crt" && cd "$SRC/build-mingw-crt"
[ -f Makefile ] || "$SRC/mingw-w64/mingw-w64-crt/configure" \
    --host=aarch64-w64-mingw32 --prefix="$PWD/stage" --with-sysroot="$TC/aarch64-w64-mingw32" \
    --disable-lib32 --disable-lib64 --disable-libarm32 --enable-libarm64 \
    CC=aarch64-w64-mingw32-clang CFLAGS="$FLAGS"
make -j8
make install

# --- winpthreads ---
mkdir -p "$SRC/build-winpthread" && cd "$SRC/build-winpthread"
[ -f Makefile ] || "$SRC/mingw-w64/mingw-w64-libraries/winpthreads/configure" \
    --host=aarch64-w64-mingw32 --prefix="$PWD/stage" --with-sysroot="$TC/aarch64-w64-mingw32" \
    CC=aarch64-w64-mingw32-clang CFLAGS="$FLAGS"
make -j8
make install

# --- install into toolchain (back up stock files once) ---
BK=$TC/aarch64-w64-mingw32/lib-backup-stock
mkdir -p "$BK"
for f in "$SRC/build-mingw-crt/stage/lib/"*; do
    b=$(basename "$f")
    if [ -f "$TCLIB/$b" ]; then
        [ -f "$BK/$b" ] || cp "$TCLIB/$b" "$BK/$b"
        cp "$f" "$TCLIB/$b"
    fi
done
for b in libwinpthread.a libwinpthread.dll.a libpthread.a libpthread.dll.a libwinpthread.la; do
    [ -f "$BK/$b" ] || cp "$TCLIB/$b" "$BK/$b" 2>/dev/null || true
    cp "$SRC/build-winpthread/stage/lib/$b" "$TCLIB/$b"
done

echo "VKMT CRT installed into $TCLIB (stock copies in $BK)"
echo "NOTE: any PE binary linked against the stock CRT must be RELINKED (not recompiled)."
echo "NOTE: run scripts/fix-x18-tls.py on every freshly linked PE binary."
