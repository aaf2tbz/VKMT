#!/bin/bash
# Rebuild MetalSharp's CEF launcher wrapper and child hook for both guest ABIs.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$VKMT/third_party/metalsharp-cef"
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
OUTPUT="$VKMT/build/cef-compat"

mkdir -p "$OUTPUT/i386" "$OUTPUT/x86_64"

build_arch()
{
  arch=$1
  compiler=$2
  "$compiler" -O2 -Wall -Wextra -mwindows \
    "$SOURCE/cefcompat-wrapper.c" -o "$OUTPUT/$arch/cefcompat-wrapper.exe" \
    -ladvapi32 -lshell32
  "$compiler" -O2 -Wall -Wextra -shared \
    "$SOURCE/cefchildhook.c" -o "$OUTPUT/$arch/metalsharp-cefchildhook.dll" \
    -ladvapi32 -lshell32
  "$compiler" -O2 -Wall -Wextra -shared \
    "$SOURCE/chrome_elf_compat.c" "$SOURCE/chrome_elf_compat.def" \
    -o "$OUTPUT/$arch/chrome_elf.dll"
}

build_arch i386 "$TOOLCHAIN/i686-w64-mingw32-gcc"
build_arch x86_64 "$TOOLCHAIN/x86_64-w64-mingw32-gcc"

file "$OUTPUT/i386/cefcompat-wrapper.exe" \
  "$OUTPUT/i386/metalsharp-cefchildhook.dll" \
  "$OUTPUT/i386/chrome_elf.dll" \
  "$OUTPUT/x86_64/cefcompat-wrapper.exe" \
  "$OUTPUT/x86_64/metalsharp-cefchildhook.dll" \
  "$OUTPUT/x86_64/chrome_elf.dll"
echo METALSHARP_CEF_COMPAT_BUILD_OK
