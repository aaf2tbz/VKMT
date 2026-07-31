#!/bin/bash
# Stage Wine's GnuTLS Schannel backend as a relocatable ARM64 dylib closure.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${1:-$VKMT/wine/build-ec}"
STAGES=("$BUILD/dlls/secur32" "$BUILD/dlls/crypt32")
ROOT="${GNUTLS_SOURCE:-/opt/homebrew/opt/gnutls/lib/libgnutls.30.dylib}"

test -f "$ROOT" || { echo "Missing GnuTLS source dylib: $ROOT" >&2; exit 1; }
test -f "${STAGES[0]}/secur32.so" || {
  echo "Missing Wine secur32.so: ${STAGES[0]}/secur32.so" >&2
  exit 1
}
test -f "${STAGES[1]}/crypt32.so" || {
  echo "Missing Wine crypt32.so: ${STAGES[1]}/crypt32.so" >&2
  exit 1
}
mkdir -p "${STAGES[@]}"

sources=("$ROOT")
index=0
while test "$index" -lt "${#sources[@]}"; do
  source="${sources[$index]}"
  index=$((index + 1))
  while IFS= read -r dependency; do
    case "$dependency" in
      /opt/homebrew/*)
        found=0
        for known in "${sources[@]}"; do
          if test "$known" = "$dependency"; then found=1; break; fi
        done
        test "$found" = 1 || sources+=("$dependency")
        ;;
    esac
  done < <(/usr/bin/otool -L "$source" | awk 'NR > 1 {print $1}')
done

for source in "${sources[@]}"; do
  test -f "$source" || { echo "Missing GnuTLS dependency: $source" >&2; exit 1; }
  test "$(/usr/bin/lipo -archs "$source")" = arm64 || {
    echo "GnuTLS dependency is not ARM64-only: $source" >&2
    exit 1
  }
  for stage in "${STAGES[@]}"; do
    /usr/bin/ditto "$source" "$stage/$(basename "$source")"
  done
done

for stage in "${STAGES[@]}"; do
  for source in "${sources[@]}"; do
    staged="$stage/$(basename "$source")"
    /usr/bin/install_name_tool -id "@loader_path/$(basename "$source")" "$staged"
    while IFS= read -r dependency; do
      case "$dependency" in
        /opt/homebrew/*)
          /usr/bin/install_name_tool -change "$dependency" \
            "@loader_path/$(basename "$dependency")" "$staged"
          ;;
      esac
    done < <(/usr/bin/otool -L "$source" | awk 'NR > 1 {print $1}')
    /usr/bin/codesign --force --sign - "$staged"
  done
done

for stage in "${STAGES[@]}"; do
  for source in "${sources[@]}"; do
    staged="$stage/$(basename "$source")"
    /usr/bin/codesign --verify "$staged"
    if /usr/bin/otool -L "$staged" | grep -Fq /opt/homebrew/; then
      echo "Staged GnuTLS dependency still references Homebrew: $staged" >&2
      exit 1
    fi
  done
done

for consumer in "${STAGES[0]}/secur32.so" "${STAGES[1]}/crypt32.so"; do
  /usr/bin/otool -l "$consumer" | awk '
    /LC_RPATH/ { rpath = 1; next }
    rpath && /path @loader_path\// { found = 1 }
    rpath && /path / { rpath = 0 }
    END { exit !found }
  ' || {
    echo "$consumer does not search its loader directory for GnuTLS" >&2
    exit 1
  }
done

printf 'Staged %u relocatable ARM64 GnuTLS dylibs for %u Wine consumers\n' \
  "${#sources[@]}" "${#STAGES[@]}"
