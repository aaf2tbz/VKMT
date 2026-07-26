#!/bin/bash
# Fetch VKMT third-party sources at pinned revisions and apply VKMT patches.
set -euo pipefail
cd "$(dirname "$0")/.."
TP=third_party
mkdir -p "$TP"

MOLTENVK_REV=db66022459ffb663aa2b50f6b018bc2e124f5edf
VKD3D_REV=3dfc6f07d0953b1e8b41705275c2c59cc7374fc5
DXMT_REV=589adb780354b461645b29999cefaf533594ee99
DXMT_RELEASE_URL=https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz
DXMT_RELEASE_SHA256=8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d

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

# DXMT v0.80 is the final MIT-licensed release.  Keep both the official
# release archive (for provenance) and the source/submodules needed to build
# the native arm64 Unix driver and ARM64EC PE thunk.
if [ ! -f "$TP/DXMT-v0.80/dxmt-v0.80-builtin.tar.gz" ]; then
  mkdir -p "$TP/DXMT-v0.80"
  curl --fail --location --retry 3 --output "$TP/DXMT-v0.80/dxmt-v0.80-builtin.tar.gz" "$DXMT_RELEASE_URL"
fi
echo "$DXMT_RELEASE_SHA256  $TP/DXMT-v0.80/dxmt-v0.80-builtin.tar.gz" | shasum -a 256 -c -

if [ ! -d "$TP/dxmt-src-v0.80/.git" ]; then
  git clone --recurse-submodules https://github.com/3Shain/dxmt.git "$TP/dxmt-src-v0.80"
fi
git -C "$TP/dxmt-src-v0.80" fetch --quiet origin --tags
git -C "$TP/dxmt-src-v0.80" checkout --quiet --detach "$DXMT_REV"
git -C "$TP/dxmt-src-v0.80" submodule update --init --recursive
git -C "$TP/dxmt-src-v0.80" apply --check ../../patches/dxmt-v0.80-xcode27-arm64.patch 2>/dev/null \
  && git -C "$TP/dxmt-src-v0.80" apply ../../patches/dxmt-v0.80-xcode27-arm64.patch \
  || echo "DXMT patch already applied or conflicts; check git -C $TP/dxmt-src-v0.80 status"

echo "Fetch complete. Build with scripts/build-moltenvk.sh and scripts/build-vkd3d-proton.sh"
