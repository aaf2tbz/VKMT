#!/bin/bash
# Stage and audit the pinned i386 and x86_64 Windows Java runtimes separately.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$VKMT/third_party/windows-java"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
STAGE_ROOT="$BUILD/java-runtime"
OBJDUMP="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin/llvm-objdump"
READOBJ="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin/llvm-readobj"

I386_NAME=OpenJDK8U-jre_x86-32_windows_hotspot_8u472b08.zip
I386_SHA=21a2c5af684a658f1484daa85eabf4961ab9de28c0efbf31da2381d77fce3b5f
X64_NAME=OpenJDK8U-jre_x64_windows_hotspot_8u492b09.zip
X64_SHA=bb25b002556afc7ef158cd95ec6270dddb3eecba69acdd7abb9d28b2e9ff0f5e

cleanup()
{
  status=$?
  if test -n "${temporary:-}" && test -d "$temporary"; then
    rm -rf "$temporary"
  fi
  exit "$status"
}
trap cleanup EXIT

pe_machine()
{
  case "$1" in
    i386) printf '%s\n' 'IMAGE_FILE_MACHINE_I386' ;;
    x86_64) printf '%s\n' 'IMAGE_FILE_MACHINE_AMD64' ;;
    *) return 2 ;;
  esac
}

verify_pe_tree()
{
  arch=$1
  tree=$2
  expected="$(pe_machine "$arch")"
  count=0

  while IFS= read -r -d '' pe; do
    machine="$("$READOBJ" --file-headers "$pe" |
      awk '/^[[:space:]]*Machine:/ {print $2; exit}')"
    test "$machine" = "$expected" || {
      echo "Wrong PE architecture in $pe: expected $expected, got $machine" >&2
      exit 1
    }
    count=$((count + 1))
  done < <(find "$tree" -type f \( -iname '*.exe' -o -iname '*.dll' \) -print0)

  test "$count" -gt 0 || {
    echo "No native PE files found in $tree" >&2
    exit 1
  }
  printf '%s\n' "$count"
}

verify_crt_closure()
{
  arch=$1
  tree=$2
  case "$arch" in
    i386) wine_arch=i386 ;;
    x86_64) wine_arch=x86_64 ;;
    *) return 2 ;;
  esac

  test -f "$BUILD/dlls/ucrtbase/$wine_arch-windows/ucrtbase.dll"
  test -f "$BUILD/dlls/vcruntime140/$wine_arch-windows/vcruntime140.dll"

  imports="$temporary/$arch-imports.txt"
  : >"$imports"
  while IFS= read -r -d '' pe; do
    "$OBJDUMP" -p "$pe" |
      awk '/DLL Name:/ {print tolower($3)}' >>"$imports"
  done < <(find "$tree" -type f \( -iname '*.exe' -o -iname '*.dll' \) -print0)
  sort -u "$imports" -o "$imports"
  grep -q '^vcruntime140\.dll$' "$imports"
  grep -Eq '^(ucrtbase\.dll|api-ms-win-crt-.*\.dll)$' "$imports"
}

stage_one()
{
  arch=$1
  archive=$2
  expected_sha=$3
  manifest=$4
  vm_rel=$5
  destination="$STAGE_ROOT/$arch"

  printf '%s  %s\n' "$expected_sha" "$archive" | shasum -a 256 -c -
  if test ! -d "$destination"; then
    extract="$temporary/extract-$arch"
    mkdir -p "$extract"
    ditto -x -k "$archive" "$extract"
    source_tree="$(find "$extract" -mindepth 1 -maxdepth 1 -type d -print -quit)"
    test -n "$source_tree"
    test -f "$source_tree/bin/java.exe"
    test -f "$source_tree/$vm_rel"
    install_parent="$(dirname "$destination")"
    mkdir -p "$install_parent"
    mv "$source_tree" "$destination"
  fi

  test -f "$destination/bin/java.exe"
  test -f "$destination/bin/javaw.exe"
  test -f "$destination/$vm_rel"
  native_count="$(verify_pe_tree "$arch" "$destination")"
  verify_crt_closure "$arch" "$destination"
  install -m 0644 "$manifest" "$destination/PROVENANCE.txt"
  {
    printf 'architecture=%s\n' "$arch"
    printf 'archive_sha256=%s\n' "$expected_sha"
    printf 'native_pe_files=%s\n' "$native_count"
    printf 'vm=%s\n' "$vm_rel"
  } >"$destination/ARCHITECTURE.txt"
}

test -x "$OBJDUMP"
test -x "$READOBJ"
"$VKMT/scripts/fetch-windows-java-runtime.sh"
mkdir -p "$VKMT/build"
temporary="$(mktemp -d "$VKMT/build/windows-java-stage.XXXXXX")"

stage_one i386 "$ROOT/$I386_NAME" "$I386_SHA" \
  "$VKMT/runtime-manifests/temurin-jre-8u472-b08-windows-i386.txt" \
  bin/client/jvm.dll
stage_one x86_64 "$ROOT/$X64_NAME" "$X64_SHA" \
  "$VKMT/runtime-manifests/temurin-jre-8u492-b09-windows-x86_64.txt" \
  bin/server/jvm.dll

echo "VKMT_WINDOWS_JAVA_STAGE_OK"
