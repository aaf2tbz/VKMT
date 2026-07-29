#!/bin/bash
# Read-only inventory for the active VKMT tree.  It deliberately reports
# unstaged optional runtimes instead of treating source presence as proof.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
WINE_BUILD="$VKMT/wine/build-ec"
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal"
missing=0

present() {
  if [ -e "$1" ]; then
    printf 'present  %s\n' "${1#$VKMT/}"
  else
    printf 'MISSING  %s\n' "${1#$VKMT/}" >&2
    missing=1
  fi
}

printf '%s\n' 'VKMT preservation inventory'
present "$WINE_BUILD/wine"
present "$WINE_BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
present "$WINE_BUILD/dlls/win32u/libfreetype.6.dylib"
present "$WINE_BUILD/dlls/win32u/libpng16.16.dylib"
present "$WINE_BUILD/dlls/secur32/libgnutls.30.dylib"
present "$TOOLCHAIN/bin/aarch64-w64-mingw32-clang"
present "$VKMT/third_party/FEX-2607"
present "$VKMT/third_party/dxvk"
present "$VKMT/third_party/vkd3d-proton"
present "$VKMT/third_party/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib"
present "$VKMT/third_party/DXMT-v0.80"
present "$VKMT/third_party/dxmt-src-v0.80"
present "$VKMT/third_party/SDL2-2.32.10"
present "$VKMT/third_party/SDL3-3.4.10"
present "$VKMT/build/fex-wow64/Bin/libwow64fex.dll"
present "$VKMT/scripts/probe-input-runtime.sh"
present "$VKMT/test/input_runtime_probe.c"
present "$VKMT/third_party/inno-setup-6.5.4/innosetup-6.5.4.exe"
present "$VKMT/third_party/inno-setup-6.3.3/innosetup-6.3.3.exe"
present "$VKMT/third_party/innoextract-1.9-g6e9e34e/CMakeLists.txt"
present "$VKMT/patches/innoextract-boost-system-header-only.patch"
present "$VKMT/scripts/build-inno-runtime.sh"
present "$VKMT/scripts/probe-inno-runtime.sh"
present "$VKMT/scripts/classify-installer.sh"
present "$VKMT/scripts/probe-installer-classifier.sh"
present "$VKMT/scripts/probe-installer-extended.sh"
present "$WINE_BUILD/dlls/winebus.sys/winebus.so"
present "$WINE_BUILD/dlls/winexinput.sys/aarch64-windows/winexinput.sys"
present "$WINE_BUILD/dlls/winexinput.sys/x86_64-windows/winexinput.sys"
present "$WINE_BUILD/dlls/winexinput.sys/i386-windows/winexinput.sys"

inno_stage="$WINE_BUILD/installer-runtime/innoextract"
present "$inno_stage/innoextract"
present "$inno_stage/manifest.txt"
inno_missing=0
while IFS= read -r binary; do
  if [ "$(/usr/bin/lipo -archs "$binary")" != arm64 ] ||
     /usr/bin/otool -L "$binary" | grep -Eq '/(opt/homebrew|usr/local)/' ||
     ! /usr/bin/codesign --verify "$binary" 2>/dev/null; then
    printf 'MISSING  invalid staged Inno dependency: %s\n' \
      "${binary#$VKMT/}" >&2
    inno_missing=1
  fi
done < <(find "$inno_stage" -maxdepth 1 -type f \
  \( -name innoextract -o -name '*.dylib' \) -print 2>/dev/null)
if [ "$inno_missing" -eq 0 ] && [ -x "$inno_stage/innoextract" ]; then
  printf '%s\n' 'present  innoextract closure is ARM64-only, signed, and relocatable'
else
  missing=1
fi

for dylib in "$WINE_BUILD/dlls/win32u/libfreetype.6.dylib" \
    "$WINE_BUILD/dlls/win32u/libpng16.16.dylib"; do
  if [ -e "$dylib" ] && [ "$(/usr/bin/lipo -archs "$dylib")" = arm64 ]; then
    printf 'present  %s is ARM64-only\n' "${dylib#$VKMT/}"
  else
    printf 'MISSING  %s is not ARM64-only\n' "${dylib#$VKMT/}" >&2
    missing=1
  fi
done
if /usr/bin/otool -L "$WINE_BUILD/dlls/win32u/libfreetype.6.dylib" 2>/dev/null | \
   grep -Fq '@loader_path/libpng16.16.dylib' &&
   ! /usr/bin/otool -L "$WINE_BUILD/dlls/win32u/libfreetype.6.dylib" \
     "$WINE_BUILD/dlls/win32u/libpng16.16.dylib" 2>/dev/null | \
     grep -Fq /opt/homebrew/; then
  printf '%s\n' 'present  FreeType resolves staged libpng without Homebrew runtime paths'
else
  printf '%s\n' 'MISSING  relocatable staged FreeType/libpng closure' >&2
  missing=1
fi

gnutls_missing=0
while IFS= read -r dylib; do
  if [ "$(/usr/bin/lipo -archs "$dylib")" != arm64 ] ||
     /usr/bin/otool -L "$dylib" | grep -Fq /opt/homebrew/ ||
     ! /usr/bin/codesign --verify "$dylib" 2>/dev/null; then
    printf 'MISSING  invalid staged GnuTLS dependency: %s\n' \
      "${dylib#$VKMT/}" >&2
    gnutls_missing=1
  fi
done < <(find "$WINE_BUILD/dlls/secur32" -maxdepth 1 -type f -name '*.dylib' -print)
if [ "$gnutls_missing" -eq 0 ] &&
   [ -e "$WINE_BUILD/dlls/secur32/libgnutls.30.dylib" ]; then
  printf '%s\n' 'present  GnuTLS closure is ARM64-only, signed, and relocatable'
else
  missing=1
fi

for arch in aarch64 x86_64 i386; do
  for dll in dxgi/dxgi.dll d3d12/d3d12.dll d3d12core/d3d12core.dll; do
    present "$WINE_BUILD/dlls/${dll%/*}/$arch-windows/${dll##*/}"
  done
done

printf '%s\n' 'SDL2/SDL3 multi-architecture runtime stage:'
for spec in \
    "aarch64:IMAGE_FILE_MACHINE_ARM64" \
    "arm64ec:IMAGE_FILE_MACHINE_ARM64EC" \
    "x86_64:IMAGE_FILE_MACHINE_AMD64" \
    "i386:IMAGE_FILE_MACHINE_I386"; do
  IFS=: read -r arch expected <<<"$spec"
  for family in SDL2 SDL3; do
    dll="$WINE_BUILD/sdl-runtime/$arch/$family.dll"
    present "$dll"
    if [ -e "$dll" ]; then
      machine="$("$TOOLCHAIN/bin/llvm-readobj" --file-headers "$dll" |
        awk '/Machine:/ {print $2; exit}')"
      if [ "$machine" = "$expected" ]; then
        printf 'present  %s has %s\n' "${dll#$VKMT/}" "$expected"
      else
        printf 'MISSING  %s has %s, expected %s\n' \
          "${dll#$VKMT/}" "$machine" "$expected" >&2
        missing=1
      fi
    fi
  done
done
present "$WINE_BUILD/sdl-runtime/manifest.txt"
native_sdl2="$WINE_BUILD/dlls/ntdll/libSDL2-2.0.0.dylib"
present "$native_sdl2"
if [ -e "$native_sdl2" ]; then
  if [ "$(/usr/bin/lipo -archs "$native_sdl2")" = arm64 ] &&
     ! otool -L "$native_sdl2" | tail -n +2 |
       grep -Eq '/(opt/homebrew|usr/local)/'; then
    printf '%s\n' 'present  native SDL2 winebus provider is ARM64-only and relocatable'
  else
    printf '%s\n' 'MISSING  native SDL2 winebus provider validation failed' >&2
    missing=1
  fi
fi

printf '%s\n' 'DXMT stage (must be present before DXMT is claimed as runnable):'
for runtime in aarch64-windows/winemetal.dll aarch64-unix/winemetal.so aarch64-unix/libunwind.1.dylib; do
  if [ -e "$WINE_BUILD/dxmt-v0.80/$runtime" ]; then
    printf 'present  wine/build-ec/dxmt-v0.80/%s\n' "$runtime"
  else
    printf 'PENDING  wine/build-ec/dxmt-v0.80/%s (run scripts/build-dxmt-arm64ec.sh)\n' "$runtime" >&2
    missing=1
  fi
done
if otool -L "$WINE_BUILD/dxmt-v0.80/aarch64-unix/winemetal.so" 2>/dev/null | \
   grep -Fq '@loader_path/libunwind.1.dylib'; then
  printf '%s\n' 'present  DXMT winemetal.so resolves staged libunwind relatively'
else
  printf '%s\n' 'MISSING  DXMT winemetal.so relative staged libunwind reference' >&2
  missing=1
fi

printf '%s\n' 'Additional requested runtime stages:'
if find "$VKMT/third_party/vkd3d-proton" -xdev -type f -name d3d12.dll -print -quit 2>/dev/null | grep -q .; then
  printf '%s\n' 'present  third_party/vkd3d-proton external d3d12 runtime stage'
else
  printf '%s\n' 'PENDING  separate vkd3d-proton runtime stage (source is preserved; no staged d3d12.dll exists)' >&2
  missing=1
fi
if find "$VKMT/third_party/dxvk" -xdev -type f \( -name d3d11.dll -o -name dxgi.dll \) -print -quit 2>/dev/null | grep -q .; then
  printf '%s\n' 'present  third_party/dxvk external runtime stage'
else
  printf '%s\n' 'PENDING  separate DXVK runtime stage (source is preserved; no staged DXVK DLL exists)' >&2
  missing=1
fi
if [ -e "$WINE_BUILD/dxmt-v0.80/i386-windows/winemetal.dll" ] && \
   [ -e "$WINE_BUILD/dxmt-v0.80/aarch64-unix/winemetal.so" ]; then
  printf '%s\n' 'present  i386 winemetal.dll paired with native ARM64 winemetal.so'
else
  printf '%s\n' 'PENDING  i386 winemetal.dll paired with native ARM64 winemetal.so' >&2
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  printf '%s\n' 'Inventory incomplete; no files were changed.' >&2
  exit 1
fi
printf '%s\n' 'Inventory complete.'
