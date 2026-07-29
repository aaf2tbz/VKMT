#!/bin/bash
# Build and install the ARM64 Wine-to-native-Java server handoff.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM_MINGW="${LLVM_MINGW:-$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
ARM64_CC="$LLVM_MINGW/bin/aarch64-w64-mingw32-clang"
ARM64_OBJDUMP="$LLVM_MINGW/bin/aarch64-w64-mingw32-objdump"
SOURCE="$VKMT/test/java/native_java_wine_handoff.c"
BUILD="$VKMT/build/native-java-stage"
OUTPUT="$BUILD/vkmt-native-java-handoff.exe"
prefix=

if test "$#" -eq 2 && test "$1" = --prefix; then
  prefix=$2
else
  echo "usage: $0 --prefix PREFIX" >&2
  exit 2
fi

test -x "$ARM64_CC"
test -x "$ARM64_OBJDUMP"
test -f "$SOURCE"
test -d "$prefix/drive_c"
mkdir -p "$BUILD" "$prefix/drive_c/vkmt/bin"

if test ! -f "$OUTPUT" || test "$SOURCE" -nt "$OUTPUT"; then
  PATH="$LLVM_MINGW/bin:$PATH" "$ARM64_CC" \
    -O2 -ffixed-x18 -ffixed-x28 "$SOURCE" -o "$OUTPUT"
fi

file "$OUTPUT" | grep -q 'Aarch64'
if "$ARM64_OBJDUMP" -d "$OUTPUT" | grep -Eq '\bx18\b'; then
  echo "ARM64 Wine handoff uses reserved register x18" >&2
  exit 1
fi
install -m 0644 "$OUTPUT" \
  "$prefix/drive_c/vkmt/bin/vkmt-native-java-handoff.exe"
echo "VKMT_NATIVE_JAVA_HANDOFF_PREFIX_OK"
