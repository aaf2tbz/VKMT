#!/bin/bash
# Build and verify a relocatable native ARM64 GLib/GObject/GStreamer closure.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
STAGE="${VKMT_GSTREAMER_RUNTIME:-$BUILD/runtime/gstreamer-arm64}"
SOURCE_LIB="${VKMT_GSTREAMER_SOURCE_LIB:-/opt/homebrew/opt/gstreamer/lib}"
SOURCE_PLUGINS="${VKMT_GSTREAMER_SOURCE_PLUGINS:-/opt/homebrew/lib/gstreamer-1.0}"
SOURCE_TYPELIBS="${VKMT_GSTREAMER_SOURCE_TYPELIBS:-/opt/homebrew/lib/girepository-1.0}"
SOURCE_SCANNER="${VKMT_GSTREAMER_SOURCE_SCANNER:-/opt/homebrew/opt/gstreamer/libexec/gstreamer-1.0/gst-plugin-scanner}"
SOURCE_INSPECT="${VKMT_GSTREAMER_SOURCE_INSPECT:-/opt/homebrew/opt/gstreamer/bin/gst-inspect-1.0}"
MANIFEST="$STAGE/MANIFEST.sha256"
mode="${1:---ensure}"

case "$mode" in
  --stage|--ensure|--verify) ;;
  *) echo "usage: $0 [--stage|--ensure|--verify]" >&2; exit 2 ;;
esac

verify_stage()
{
  test -s "$MANIFEST" || return 1
  (cd "$STAGE" && shasum -a 256 -c MANIFEST.sha256 >/dev/null) || return 1
  test "$(/usr/bin/lipo -archs "$STAGE/lib/libgstreamer-1.0.0.dylib")" = arm64 || return 1
  test -f "$STAGE/girepository-1.0/Gst-1.0.typelib" || return 1
  test -x "$STAGE/libexec/gstreamer-1.0/gst-plugin-scanner" || return 1
  if find "$STAGE/lib" "$STAGE/libexec" -type f \( -name '*.dylib' -o -perm -111 \) -print0 |
     xargs -0 /usr/bin/otool -L 2>/dev/null | grep -Fq /opt/homebrew/; then
    echo "GStreamer stage still contains a Homebrew load path" >&2
    return 1
  fi
  if find "$STAGE/lib" "$STAGE/libexec" -type f \( -name '*.dylib' -o -perm -111 \) -print0 |
     xargs -0 /usr/bin/otool -l 2>/dev/null | grep -Fq /opt/homebrew/; then
    echo "GStreamer stage still contains a Homebrew runtime search path" >&2
    return 1
  fi
}

if test "$mode" = --verify; then
  verify_stage || { echo "Invalid staged GStreamer runtime: $STAGE" >&2; exit 1; }
  echo VKMT_GSTREAMER_RUNTIME_VERIFY_OK
  exit 0
fi
if test "$mode" = --ensure && verify_stage; then
  echo VKMT_GSTREAMER_RUNTIME_VERIFY_OK
  exit 0
fi

for path in "$SOURCE_LIB/libgstreamer-1.0.0.dylib" "$SOURCE_PLUGINS" \
            "$SOURCE_TYPELIBS/Gst-1.0.typelib" "$SOURCE_SCANNER" "$SOURCE_INSPECT"; do
  test -e "$path" || { echo "Missing GStreamer input: $path" >&2; exit 1; }
done

mkdir -p "$BUILD/runtime"
work="$(mktemp -d "$BUILD/runtime/.gstreamer-arm64.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/lib/gstreamer-1.0" "$work/girepository-1.0" \
         "$work/libexec/gstreamer-1.0"

# Start with every GStreamer library and plugin. Recursively close all
# non-system dylib references so the resulting runtime has no package-manager
# dependency at launch time.
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(
  find -L "$SOURCE_LIB" -maxdepth 1 -type f -name '*.dylib' -print
  # GTK3 and GTK4 sinks register duplicate Objective-C class names when both
  # scanners load them in one macOS process. Wine supplies its own display
  # path, so keep these UI-only plugins out of the media/codec closure.
  find -L "$SOURCE_PLUGINS" -maxdepth 1 -type f -name '*.dylib' \
    ! -name 'libgstgtk.dylib' ! -name 'libgstgtk4.dylib' -print
)
index=0
while test "$index" -lt "${#sources[@]}"; do
  source="${sources[$index]}"
  index=$((index + 1))
  while IFS= read -r dependency; do
    case "$dependency" in
      /opt/homebrew/*)
        resolved="$dependency"
        ;;
      @rpath/*)
        name="$(basename "$dependency")"
        resolved="$(dirname "$source")/$name"
        if test ! -f "$resolved"; then
          resolved="$(find -L /opt/homebrew/opt -maxdepth 3 -type f -name "$name" -print -quit)"
        fi
        test -n "$resolved" || continue
        ;;
      *) continue ;;
    esac
    test -f "$resolved" || { echo "Missing dependency: $resolved" >&2; exit 1; }
    known=0
    for candidate in "${sources[@]}"; do
      test "$candidate" = "$resolved" && { known=1; break; }
    done
    test "$known" = 1 || sources+=("$resolved")
  done < <(/usr/bin/otool -L "$source" | awk 'NR > 1 {print $1}')
done

for source in "${sources[@]}"; do
  name="$(basename "$source")"
  case "$source" in
    "$SOURCE_PLUGINS"/*) destination="$work/lib/gstreamer-1.0/$name" ;;
    *) destination="$work/lib/$name" ;;
  esac
  if test -f "$destination"; then
    cmp -s "$destination" "$source" || {
      echo "Non-identical runtime basename collision: $name" >&2
      exit 1
    }
    continue
  fi
  /usr/bin/ditto "$source" "$destination"
done

# The typelibs directly used by Wine/GStreamer. Copy bytes, not Homebrew links.
for name in GLib-2.0 GObject-2.0 GModule-2.0 Gio-2.0 GIRepository-3.0 Gst-1.0; do
  source="$SOURCE_TYPELIBS/$name.typelib"
  test -f "$source" || { echo "Missing typelib: $source" >&2; exit 1; }
  /usr/bin/ditto "$source" "$work/girepository-1.0/$name.typelib"
done
/usr/bin/ditto "$SOURCE_SCANNER" "$work/libexec/gstreamer-1.0/gst-plugin-scanner"
chmod 0755 "$work/libexec/gstreamer-1.0/gst-plugin-scanner"

rewrite_macho()
{
  file=$1
  relation=$2
  if test "$relation" = library; then
    /usr/bin/install_name_tool -id "@loader_path/$(basename "$file")" "$file"
    prefix=@loader_path
  elif test "$relation" = plugin; then
    /usr/bin/install_name_tool -id "@loader_path/$(basename "$file")" "$file"
    prefix=@loader_path/..
  else
    prefix=@executable_path/../../lib
  fi
  while IFS= read -r dependency; do
    case "$dependency" in
      /opt/homebrew/*)
        /usr/bin/install_name_tool -change "$dependency" "$prefix/$(basename "$dependency")" "$file"
        ;;
      @rpath/*)
        if test -f "$work/lib/$(basename "$dependency")"; then
          /usr/bin/install_name_tool -change "$dependency" "$prefix/$(basename "$dependency")" "$file"
        fi
        ;;
    esac
  done < <(/usr/bin/otool -L "$file" | awk 'NR > 1 {print $1}')
  while IFS= read -r rpath; do
    case "$rpath" in
      /opt/homebrew/*) /usr/bin/install_name_tool -delete_rpath "$rpath" "$file" ;;
    esac
  done < <(/usr/bin/otool -l "$file" | awk '
    $1 == "cmd" && $2 == "LC_RPATH" { want = 1; next }
    want && $1 == "path" { print $2; want = 0 }
  ')
  /usr/bin/codesign --force --sign - "$file" >/dev/null 2>&1
}

while IFS= read -r file; do rewrite_macho "$file" library; done < <(
  find "$work/lib" -maxdepth 1 -type f -name '*.dylib' -print | LC_ALL=C sort
)
while IFS= read -r file; do rewrite_macho "$file" plugin; done < <(
  find "$work/lib/gstreamer-1.0" -type f -name '*.dylib' -print | LC_ALL=C sort
)
rewrite_macho "$work/libexec/gstreamer-1.0/gst-plugin-scanner" executable

# Force a clean registry scan of every shipped plugin. Any loader warning is
# a closure failure; do not publish a runtime that only happens to load its
# core element while optional plugins are broken.
scan_out="$work/.plugin-scan.out"
scan_err="$work/.plugin-scan.err"
env DYLD_LIBRARY_PATH="$work/lib" \
    GI_TYPELIB_PATH="$work/girepository-1.0" \
    GST_PLUGIN_PATH_1_0="$work/lib/gstreamer-1.0" \
    GST_PLUGIN_SYSTEM_PATH_1_0="$work/lib/gstreamer-1.0" \
    GST_PLUGIN_SCANNER_1_0="$work/libexec/gstreamer-1.0/gst-plugin-scanner" \
    GST_REGISTRY="$work/.plugin-registry.bin" \
    "$SOURCE_INSPECT" coreelements >"$scan_out" 2>"$scan_err"
test ! -s "$scan_err" || {
  echo "GStreamer plugin closure emitted loader diagnostics:" >&2
  sed -n '1,160p' "$scan_err" >&2
  exit 1
}
grep -Fq "Name                     coreelements" "$scan_out" || {
  echo "GStreamer coreelements scan did not complete" >&2
  exit 1
}
rm -f "$scan_out" "$scan_err" "$work/.plugin-registry.bin"

(
  cd "$work"
  find lib girepository-1.0 libexec -type f -print | LC_ALL=C sort |
    while IFS= read -r file; do shasum -a 256 "$file"; done >MANIFEST.sha256
)

backup="$STAGE.previous.$$"
test ! -e "$STAGE" || mv "$STAGE" "$backup"
mv "$work" "$STAGE"
test ! -e "$backup" || rm -rf "$backup"
trap - EXIT

verify_stage || { echo "New GStreamer runtime failed verification" >&2; exit 1; }
echo VKMT_GSTREAMER_RUNTIME_STAGE_OK
