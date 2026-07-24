#!/bin/bash
# Fetch VKMT third-party sources at pinned revisions and apply VKMT patches.
set -euo pipefail
cd "$(dirname "$0")/.."
TP=third_party
mkdir -p "$TP"

MOLTENVK_REV=db66022459ffb663aa2b50f6b018bc2e124f5edf
VKD3D_REV=3dfc6f07d0953b1e8b41705275c2c59cc7374fc5

if [ ! -d "$TP/MoltenVK/.git" ]; then
  git clone https://github.com/KhronosGroup/MoltenVK.git "$TP/MoltenVK"
fi
git -C "$TP/MoltenVK" fetch --quiet origin
git -C "$TP/MoltenVK" checkout --quiet "$MOLTENVK_REV"
git -C "$TP/MoltenVK" apply --check ../../patches/MoltenVK-vkmt-phase2-fatal-gaps.patch 2>/dev/null \
  && git -C "$TP/MoltenVK" apply ../../patches/MoltenVK-vkmt-phase2-fatal-gaps.patch \
  || echo "MoltenVK patch already applied or conflicts; check git -C $TP/MoltenVK status"

if [ ! -d "$TP/vkd3d-proton/.git" ]; then
  git clone --recurse-submodules https://github.com/HansKristian-Work/vkd3d-proton.git "$TP/vkd3d-proton"
fi
git -C "$TP/vkd3d-proton" fetch --quiet origin
git -C "$TP/vkd3d-proton" checkout --quiet "$VKD3D_REV"
git -C "$TP/vkd3d-proton" submodule update --init --recursive

if [ ! -d "$TP/dxvk/.git" ]; then
  git clone --depth 1 https://github.com/doitsujin/dxvk.git "$TP/dxvk"   # reference only
fi

echo "Fetch complete. Build with scripts/build-moltenvk.sh and scripts/build-vkd3d-proton.sh"
