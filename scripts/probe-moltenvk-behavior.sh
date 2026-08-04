#!/bin/bash
# Direct native MoltenVK behavior contract.  This is deliberately independent
# of Wine so feature claims are tested at the Vulkan/Metal boundary itself.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd -P)"
MOLTENVK="$VKMT/third_party/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib"
HEADERS="$VKMT/third_party/MoltenVK/External/Vulkan-Headers/include"
ICD="$VKMT/test/vkmt_icd.json"
SOURCE="$VKMT/test/moltenvk_behavior_contract.c"
SHADER="$VKMT/test/moltenvk_storage_read.comp"
IMAGE_SHADER="$VKMT/test/moltenvk_image_read.comp"
EVIDENCE="$VKMT/docs/validation/moltenvk-behavior-p8-20260803"
RUN_ROOT="$VKMT/build/probe-runs/moltenvk-behavior-p8"
FIXTURE="$RUN_ROOT/moltenvk_behavior_contract"
SPV="$RUN_ROOT/storage_read.spv"
IMAGE_SPV="$RUN_ROOT/image_read.spv"

test "$(uname -m)" = arm64 || { echo "MoltenVK behavior probe must run natively on ARM64" >&2; exit 1; }
for required in "$MOLTENVK" "$HEADERS/vulkan/vulkan.h" "$ICD" "$SOURCE" "$SHADER" "$IMAGE_SHADER"; do
    test -e "$required" || { echo "missing MoltenVK contract input: $required" >&2; exit 1; }
done
command -v glslangValidator >/dev/null || { echo "glslangValidator is required" >&2; exit 1; }
command -v clang >/dev/null || { echo "clang is required" >&2; exit 1; }
mkdir -p "$RUN_ROOT" "$EVIDENCE"

file "$MOLTENVK" | grep -q 'arm64'
/opt/homebrew/bin/glslangValidator -V --target-env vulkan1.3 -o "$SPV" "$SHADER" \
    >"$EVIDENCE/glslang.log" 2>&1
/opt/homebrew/bin/glslangValidator -V --target-env vulkan1.3 -o "$IMAGE_SPV" "$IMAGE_SHADER" \
    >"$EVIDENCE/glslang-image.log" 2>&1
clang -std=c11 -O2 -Wall -Wextra -Werror -I"$HEADERS" "$SOURCE" \
    -o "$FIXTURE" -L/opt/homebrew/opt/vulkan-loader/lib -lvulkan \
    >"$EVIDENCE/compile.log" 2>&1
file "$FIXTURE" | tee "$EVIDENCE/fixture-file.txt" | grep -q 'arm64'

set +e
VK_ICD_FILENAMES="$ICD" MVK_CONFIG_LOG_LEVEL=0 "$FIXTURE" "$SPV" "$IMAGE_SPV" \
    >"$EVIDENCE/probe.log" 2>"$EVIDENCE/driver.log"
status=$?
set -e
printf 'status=%s\n' "$status" >"$EVIDENCE/status.txt"
shasum -a 256 "$MOLTENVK" "$FIXTURE" "$SPV" "$IMAGE_SPV" >"$EVIDENCE/hashes.sha256"
git -C "$VKMT/third_party/MoltenVK" rev-parse HEAD >"$EVIDENCE/moltenvk-revision.txt"

{
    printf 'api\tstatus\tevidence\tpolicy\n'
    if grep -q '^MOLTENVK_NULL_DESCRIPTOR_BEHAVIOR_OK$' "$EVIDENCE/probe.log"; then
        printf 'nullDescriptor\tPASS\tdirect null storage-buffer read returned zero\tadvertise\n'
    else
        printf 'nullDescriptor\tFAIL\tdirect null storage-buffer behavior\tdisable-or-fix\n'
    fi
    if grep -q '^MOLTENVK_ROBUST_BUFFER_BEHAVIOR_OK$' "$EVIDENCE/probe.log"; then
        printf 'robustBufferAccess2\tPASS\tdirect out-of-bounds storage-buffer read returned zero\tadvertise-narrowly\n'
    else
        printf 'robustBufferAccess2\tFAIL\tdirect out-of-bounds storage-buffer behavior\tdisable-or-fix\n'
    fi
    if grep -q '^MOLTENVK_ROBUST_IMAGE_BEHAVIOR_OK$' "$EVIDENCE/probe.log"; then
        printf 'robustImageAccess2\tPASS\tdirect out-of-bounds storage-image read returned zero\tadvertise-narrowly\n'
    else
        printf 'robustImageAccess2\tFAIL\tdirect out-of-bounds storage-image behavior\tdisable-or-fix\n'
    fi
    if grep -q '^MOLTENVK_TRANSFORM_FEEDBACK_NOT_ADVERTISED_OK$' "$EVIDENCE/probe.log"; then
        printf 'transformFeedback\tNOT_ADVERTISED\tno passthrough claim\tkeep-disabled\n'
    else
        printf 'transformFeedback\tFAIL\tadvertised without captured-output proof\tdisable-or-fix\n'
    fi
    if grep -q '^MOLTENVK_DRAW_INDIRECT_COUNT_NOT_ADVERTISED_OK$' "$EVIDENCE/probe.log"; then
        printf 'drawIndirectCount\tNOT_ADVERTISED\tno count-buffer claim\tkeep-disabled\n'
    else
        printf 'drawIndirectCount\tFAIL\tadvertised without count/sync proof\tdisable-or-fix\n'
    fi
    if grep -q '^MOLTENVK_TYPED_BUFFER_ALIGNMENT_QUERY_OK$' "$EVIDENCE/probe.log"; then
        printf 'typedBufferAlignment\tQUERY_ONLY\tdevice alignment was queried; unaligned access remains unproven\tlimit-offsets\n'
    else
        printf 'typedBufferAlignment\tFAIL\tno alignment properties\tdisable-or-fix\n'
    fi
} >"$EVIDENCE/capability.tsv"

{
    printf '# MoltenVK direct behavior contract — P8\n\n'
    printf 'MoltenVK: %s\n\n' "$MOLTENVK"
    printf 'Probe status: %s\n\n' "$status"
    printf 'This fixture distinguishes feature enumeration from behavioral proof.\n\n'
    printf '## Covered behavior\n\n'
    printf '%s\n' \
      '- null storage-buffer descriptors: direct compute readback must be zero;' \
      '- robust storage-buffer access: direct out-of-bounds readback must be zero;' \
      '- robust storage-image access: direct out-of-bounds readback must be zero;' \
      '- transform feedback and indirect count: unsupported claims must be absent;' \
      '- typed-buffer alignment: alignment properties are recorded; unaligned offsets are not advertised as proven.'
    printf '\n## Evidence\n\n- `probe.log`\n- `driver.log`\n- `capability.tsv`\n- `hashes.sha256`\n- `moltenvk-revision.txt`\n'
    if test "$status" -eq 0; then
        printf '\n**MOLTENVK_BEHAVIOR_CONTRACT_OK**\n'
    else
        printf '\n**MOLTENVK_BEHAVIOR_CONTRACT_FAILED**\n'
    fi
} >"$EVIDENCE/RESULTS.md"

cat "$EVIDENCE/probe.log"
if test "$status" -ne 0; then
    echo "MoltenVK behavior contract failed; see $EVIDENCE" >&2
    exit "$status"
fi
echo MOLTENVK_BEHAVIOR_CONTRACT_OK
