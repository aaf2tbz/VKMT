#!/bin/bash
# Build and stage the ARM64 CLR pieces missing from the official Wine Mono tarball.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=11.2.0
TAG="wine-mono-$VERSION"
SOURCE="$VKMT/third_party/$TAG-src"
STAGE="$VKMT/wine/mono/$TAG"
IMAGE="$SOURCE/image"
WINE_SOURCE="$VKMT/wine/wine-11.12"
WINE_BUILD="$VKMT/wine/build-ec"
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
BUILD_PATH="/opt/homebrew/opt/libtool/libexec/gnubin:/opt/homebrew/bin:$TOOLCHAIN"
ABI_FLAGS="-ffixed-x18 -ffixed-x28"

if test "${VKMT_WINE_MONO_FETCHED:-0}" != 1; then
  VKMT_WINE_MONO_BUILD_ARM64=0 "$VKMT/scripts/fetch-wine-mono-runtime.sh"
fi

for tool in gmake cmake automake libtool aarch64-w64-mingw32-gcc; do
  env PATH="$BUILD_PATH:$PATH" command -v "$tool" >/dev/null || {
    echo "Missing Wine Mono ARM64 build dependency: $tool" >&2
    exit 1
  }
done
test -f "$SOURCE/GNUmakefile"
test -d "$STAGE"
test -f "$WINE_BUILD/Makefile"

if ! grep -q "VKMT: Wine's native ARM64 mscoree" \
     "$SOURCE/mono/mono/metadata/coree.c"; then
  patch --directory="$SOURCE" -p1 \
    <"$VKMT/patches/wine-mono-11.2.0-arm64-coree.patch"
fi

if git -C "$WINE_SOURCE" apply --check \
     "$VKMT/patches/wine-11.12-arm64-mono-fusion.patch" 2>/dev/null; then
  git -C "$WINE_SOURCE" apply \
    "$VKMT/patches/wine-11.12-arm64-mono-fusion.patch"
elif ! git -C "$WINE_SOURCE" apply --reverse --check \
       "$VKMT/patches/wine-11.12-arm64-mono-fusion.patch" 2>/dev/null; then
  echo "Wine Mono integration patch is only partially applied" >&2
  exit 1
fi

# Reconfigure BTLS explicitly so an older CMake cache cannot silently omit the
# VKMT reserved-register contract.
env PATH="$BUILD_PATH:$PATH" cmake \
  -S "$SOURCE/mono/mono/btls" \
  -B "$SOURCE/build/btls-arm64" \
  -DCMAKE_TOOLCHAIN_FILE="$SOURCE/toolchain-arm64.cmake" \
  -DCMAKE_C_COMPILER=aarch64-w64-mingw32-gcc \
  "-DCMAKE_C_FLAGS=-D__WINCRYPT_H__ -D_WIN32_WINNT=0x0600 $ABI_FLAGS" \
  -DCMAKE_CXX_COMPILER=aarch64-w64-mingw32-g++ \
  "-DCMAKE_CXX_FLAGS=$ABI_FLAGS" \
  -DOPENSSL_NO_ASM=1 \
  -DBTLS_ROOT="$SOURCE/mono/external/boringssl" \
  -DBUILD_SHARED_LIBS=1

env PATH="$BUILD_PATH:$PATH" /opt/homebrew/bin/gmake \
  -C "$SOURCE" -j"${VKMT_BUILD_JOBS:-8}" \
  ENABLE_ARM64=1 \
  ENABLE_DEBUG_SYMBOLS=0 \
  AUTO_LLVM_MINGW=0 \
  MINGW_PATH="$BUILD_PATH" \
  LLVM_MINGW_PATH="$TOOLCHAIN" \
  "PDB_CFLAGS_arm64=$ABI_FLAGS" \
  libmono-2.0-arm64.dll \
  MonoPosixHelper-arm64.dll \
  libmono-btls-shared-arm64.dll

CLR="$IMAGE/bin/libmono-2.0-arm64.dll"
POSIX="$IMAGE/lib/arm64/MonoPosixHelper.dll"
BTLS="$IMAGE/lib/arm64/libmono-btls-shared.dll"

python3 "$VKMT/scripts/fix-x18-tls.py" "$CLR" "$POSIX" "$BTLS"
for pe in "$CLR" "$POSIX" "$BTLS"; do
  file "$pe" | grep -q 'PE32+ executable (DLL).*Aarch64'
  if "$TOOLCHAIN/llvm-objdump" -d --no-show-raw-insn "$pe" |
     grep -E '\[x18([,\]])' >/dev/null; then
    echo "ARM64 Wine Mono binary still contains x18-based TLS: $pe" >&2
    exit 1
  fi
done

mkdir -p "$STAGE/bin" "$STAGE/lib/arm64"
install -m 0644 "$CLR" "$STAGE/bin/libmono-2.0.dll"
install -m 0644 "$POSIX" "$STAGE/lib/arm64/MonoPosixHelper.dll"
install -m 0644 "$BTLS" "$STAGE/lib/arm64/libmono-btls-shared.dll"

file "$STAGE/bin/libmono-2.0.dll" | grep -q 'PE32+ executable (DLL).*Aarch64'

# Rebuild only mscoree, the Windows/Unix ntdll loaders, and wineserver after
# applying the unified-prefix Fusion and PE32+ IL-only process contract. A
# full Wine rebuild is neither needed nor permitted for this step.
env PATH="$BUILD_PATH:$PATH" /opt/homebrew/bin/gmake \
  -C "$WINE_BUILD" -j"${VKMT_BUILD_JOBS:-8}" \
  dlls/mscoree/aarch64-windows/mscoree.dll \
  dlls/ntdll/aarch64-windows/ntdll.dll \
  dlls/ntdll/ntdll.so \
  server/wineserver
MSCOREE="$WINE_BUILD/dlls/mscoree/aarch64-windows/mscoree.dll"
NTDLL="$WINE_BUILD/dlls/ntdll/aarch64-windows/ntdll.dll"
file "$MSCOREE" | grep -q 'PE32+ executable (DLL).*Aarch64'
"$TOOLCHAIN/llvm-readobj" --file-headers "$MSCOREE" |
  grep -q 'IMAGE_FILE_MACHINE_ARM64X'
file "$NTDLL" | grep -q 'PE32+ executable (DLL).*Aarch64'
"$TOOLCHAIN/llvm-readobj" --file-headers "$NTDLL" |
  grep -q 'IMAGE_FILE_MACHINE_ARM64X'
"$TOOLCHAIN/llvm-objdump" -d --no-show-raw-insn "$NTDLL" |
  grep -E '\[x18([,\]])' >/dev/null && {
    echo "ARM64X ntdll still contains x18 operands" >&2
    exit 1
  }

echo "VKMT_WINE_MONO_11_2_0_ARM64_BUILD_OK"
