#!/bin/bash
# Prove the pinned native MetalSharp GLSL 3.30 -> SPIR-V -> MSL path.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
RUNS="$VKMT/build/probe-runs"
SOURCE="$VKMT/test/metalsharp_glsl_translation_probe.c"
SIDECAR="$VKMT/wine/build-ec/dlls/winemac.drv/metalsharp-opengl.dylib"

test -f "$SOURCE"
test -f "$SIDECAR"
test "$(/usr/bin/lipo -archs "$SIDECAR")" = arm64
if translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null)"; then
  test "$translated" = 0 || { echo "MetalSharp probe runner is under Rosetta" >&2; exit 1; }
fi

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/metalsharp-opengl.XXXXXX")"
cleanup()
{
  status=$?
  case "$run_root" in
    "$RUNS"/*)
      if test "${VKMT_KEEP_PROBE_RUN:-0}" = 1; then
        echo "Retained disposable MetalSharp run: $run_root" >&2
      else
        /usr/bin/trash "$run_root" 2>/dev/null || true
      fi
      ;;
  esac
  exit "$status"
}
trap cleanup EXIT

clang -O2 -g -Wall -Wextra -arch arm64 "$SOURCE" -o "$run_root/probe"
test "$(/usr/bin/lipo -archs "$run_root/probe")" = arm64
"$run_root/probe" "$SIDECAR" | tee "$run_root/probe.log"
grep -q 'PASS GLSL330 glslang -> SPIR-V -> MSL translation' "$run_root/probe.log"
echo METALSHARP_GLSL330_SPIRV_MSL_OK
