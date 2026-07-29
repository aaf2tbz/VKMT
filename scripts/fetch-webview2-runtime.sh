#!/bin/bash
# Fetch and extract the pinned Microsoft WebView2 fixed runtimes and matched SDK.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION='149.0.4022.98'
SDK_VERSION='1.0.4022.49'
DEST="$VKMT/third_party/webview2-$VERSION"

fetch()
{
  url=$1
  name=$2
  expected=$3
  mkdir -p "$DEST"
  if test ! -f "$DEST/$name"; then
    curl -L --fail --show-error --progress-bar "$url" -o "$DEST/$name.part"
    mv "$DEST/$name.part" "$DEST/$name"
  fi
  actual="$(shasum -a 256 "$DEST/$name" | awk '{print $1}')"
  if test "$actual" != "$expected"; then
    echo "$name SHA-256 mismatch: $actual" >&2
    exit 1
  fi
}

fetch \
  'https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/2943b6d1-31d1-42c5-8cfa-c2c31485974d/Microsoft.WebView2.FixedVersionRuntime.149.0.4022.98.x64.cab' \
  "Microsoft.WebView2.FixedVersionRuntime.$VERSION.x64.cab" \
  81a1a5b8c72d7f8317b9fffc5f4f17f3efe8db42655e869ea4b2a05b65512af2
fetch \
  'https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/61bcab01-0f1c-4c9c-89b0-c1e380ad95f8/Microsoft.WebView2.FixedVersionRuntime.149.0.4022.98.x86.cab' \
  "Microsoft.WebView2.FixedVersionRuntime.$VERSION.x86.cab" \
  e1dad6c83520336797a5cbce957c2390c693f9c92e454ea3dcaddc91dba7e1a9
fetch \
  "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$SDK_VERSION/microsoft.web.webview2.$SDK_VERSION.nupkg" \
  "microsoft.web.webview2.$SDK_VERSION.nupkg" \
  ee9de67e5bb9ef3a96c5689b2efc8188e2df160a0e79234c0404243782fde5fb

if test ! -f "$DEST/sdk/build/native/include/WebView2.h"; then
  mkdir -p "$DEST/sdk"
  unzip -q -o "$DEST/microsoft.web.webview2.$SDK_VERSION.nupkg" -d "$DEST/sdk"
fi
for arch in x64 x86; do
  runtime="$DEST/runtime-$arch"
  if test ! -f "$runtime/msedgewebview2.exe"; then
    mkdir -p "$runtime"
    bsdtar -xf "$DEST/Microsoft.WebView2.FixedVersionRuntime.$VERSION.$arch.cab" \
      -C "$runtime" --strip-components 1
  fi
done

echo WEBVIEW2_FIXED_149_X64_X86_STAGE_OK
