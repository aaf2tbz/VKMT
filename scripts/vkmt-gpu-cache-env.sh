#!/bin/bash
# Source after WINEPREFIX is set to select VKMT's versioned graphics caches.
VKMT_GPU_CACHE_ROOT="${VKMT_GPU_CACHE_ROOT:-${WINEPREFIX:?WINEPREFIX must be set}/.vkmt/gpu-cache}"
VKMT_GPU_CACHE_MANIFEST="$VKMT_GPU_CACHE_ROOT/MANIFEST.tsv"

if test ! -s "$VKMT_GPU_CACHE_MANIFEST"; then
  "${VKMT_RUNTIME_ROOT:-/Volumes/AverySSD/VKMT}/scripts/stage-gpu-cache-runtime.sh" \
    --prefix "$WINEPREFIX" >/dev/null || return 1 2>/dev/null || exit 1
fi

VKMT_GPU_CACHE_GENERATION="$(awk -F '\t' '$1 == "generation" { print $2 }' "$VKMT_GPU_CACHE_MANIFEST")"
case "$VKMT_GPU_CACHE_GENERATION" in v2-[0-9a-f][0-9a-f]*) ;; *)
  echo "Invalid VKMT GPU cache manifest: $VKMT_GPU_CACHE_MANIFEST" >&2
  return 1 2>/dev/null || exit 1
esac
VKMT_GPU_CACHE_PATH="$VKMT_GPU_CACHE_ROOT/$VKMT_GPU_CACHE_GENERATION"

export VKMT_GPU_CACHE_ROOT VKMT_GPU_CACHE_MANIFEST VKMT_GPU_CACHE_GENERATION VKMT_GPU_CACHE_PATH
export DXVK_SHADER_CACHE="${DXVK_SHADER_CACHE:-1}"
export DXVK_SHADER_CACHE_PATH="$VKMT_GPU_CACHE_PATH/dxvk"
export VKD3D_SHADER_CACHE_PATH="$VKMT_GPU_CACHE_PATH/vkd3d"
export DXMT_SHADER_CACHE_PATH="$VKMT_GPU_CACHE_PATH/dxmt/shaders"
export DXMT_PIPELINE_CACHE_PATH="$VKMT_GPU_CACHE_PATH/dxmt/pipelines"
export METALSHARP_SHADER_CACHE_PATH="$VKMT_GPU_CACHE_PATH/metalsharp/shaders"
export METALSHARP_PIPELINE_CACHE_PATH="$VKMT_GPU_CACHE_PATH/metalsharp/pipelines"
export MTL_SHADER_CACHE_DIR="$VKMT_GPU_CACHE_PATH/metal"
export XDG_CACHE_HOME="$VKMT_GPU_CACHE_PATH/xdg"
export METALSHARP_CACHE_SUMMARY="shader=$METALSHARP_SHADER_CACHE_PATH;pipeline=$METALSHARP_PIPELINE_CACHE_PATH"

if test "${VKMT_GRAPHICS_RUNTIME_LOGS:-0}" = 1; then
  export DXVK_LOG_PATH="$VKMT_GPU_CACHE_PATH/logs"
fi
