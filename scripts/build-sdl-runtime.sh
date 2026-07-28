#!/bin/bash
# Build and stage SDL2/SDL3 Windows DLLs for every VKMT guest ABI.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal"
BIN="$TOOLCHAIN/bin"
SDK="$TOOLCHAIN/generic-w64-mingw32/include"
BUILD_ROOT="$VKMT/build/sdl-runtime"
STAGE="$VKMT/wine/build-ec/sdl-runtime"
JOBS="${VKMT_SDL_JOBS:-8}"

SDL2_VERSION=2.32.10
SDL2_UPSTREAM_COMMIT=5d249570393f7a37e037abf22cd6012a4cc56a71
SDL2_COMMIT=8f57bf76c15f5ddade4a1156ed24462da5ef5fe2
SDL2_SOURCE="$VKMT/third_party/SDL2-$SDL2_VERSION"
SDL3_VERSION=3.4.10
SDL3_UPSTREAM_COMMIT=8e37db5e797b6167f3a00d697d816a684bd259c7
SDL3_COMMIT=1f46ec8b0761a248448371735ee020f1f58703e4
SDL3_SOURCE="$VKMT/third_party/SDL3-$SDL3_VERSION"

test "$(git -C "$SDL2_SOURCE" rev-parse HEAD)" = "$SDL2_COMMIT"
test "$(git -C "$SDL3_SOURCE" rev-parse HEAD)" = "$SDL3_COMMIT"
git -C "$SDL2_SOURCE" merge-base --is-ancestor "$SDL2_UPSTREAM_COMMIT" "$SDL2_COMMIT"
git -C "$SDL3_SOURCE" merge-base --is-ancestor "$SDL3_UPSTREAM_COMMIT" "$SDL3_COMMIT"
mkdir -p "$BUILD_ROOT" "$STAGE"

build_one()
{
    family=$1
    version=$2
    source=$3
    arch=$4
    triple=$5
    processor=$6
    expected_machine=$7
    build="$BUILD_ROOT/$family-$version/$arch"
    stage="$STAGE/$arch"
    cflags="-isystem $SDK"

    case "$arch" in
        aarch64) cflags="-ffixed-x18 -ffixed-x28 $cflags" ;;
        arm64ec)
            cflags="-ffixed-x18 -ffixed-x28 -DSDL_DISABLE_IMMINTRIN_H \
-DSDL_DISABLE_MMINTRIN_H -DSDL_DISABLE_XMMINTRIN_H \
-DSDL_DISABLE_EMMINTRIN_H -DSDL_DISABLE_PMMINTRIN_H $cflags"
            ;;
        x86_64)
            cflags="-fno-jump-tables $cflags"
            ;;
        i386)
            cflags="-mno-mmx -mno-sse -mno-sse2 -fno-vectorize -fno-slp-vectorize \
-DSDL_DISABLE_MMINTRIN_H -DSDL_DISABLE_XMMINTRIN_H \
-DSDL_DISABLE_EMMINTRIN_H $cflags"
            ;;
    esac

    mkdir -p "$build"
    cmake --fresh -S "$source" -B "$build" -G Ninja \
        -DCMAKE_SYSTEM_NAME=Windows \
        -DCMAKE_SYSTEM_PROCESSOR="$processor" \
        -DCMAKE_C_COMPILER="$BIN/$triple-clang" \
        -DCMAKE_CXX_COMPILER="$BIN/$triple-clang++" \
        -DCMAKE_RC_COMPILER="$BIN/$triple-windres" \
        "-DCMAKE_C_FLAGS=$cflags" \
        "-DCMAKE_CXX_FLAGS=$cflags" \
        -DCMAKE_BUILD_TYPE=Release \
        -DSDL_SHARED=ON \
        -DSDL_STATIC=OFF \
        -DSDL_TEST=OFF \
        -DSDL_TESTS=OFF \
        -DSDL_INSTALL_TESTS=OFF \
        -DSDL_EXAMPLES=OFF \
        -DSDL_MMX=OFF \
        -DSDL_SSE=OFF \
        -DSDL_SSE2=OFF \
        -DSDL_SSE3=OFF \
        -DSDL_SSE4_1=OFF \
        -DSDL_SSE4_2=OFF \
        -DSDL_AVX=OFF \
        -DSDL_AVX2=OFF \
        -DSDL_AVX512F=OFF \
        >"$build.configure.log"

    cmake --build "$build" -j"$JOBS"
    mkdir -p "$stage"

    if test "$family" = SDL2; then
        dll=SDL2.dll
        import=libSDL2.dll.a
    else
        dll=SDL3.dll
        import=libSDL3.dll.a
    fi

    test -f "$build/$dll"
    test -f "$build/$import"
    install -m 0644 "$build/$dll" "$stage/$dll"
    install -m 0644 "$build/$import" "$stage/$import"

    machine="$("$BIN/llvm-readobj" --file-headers "$stage/$dll" |
        awk '/Machine:/ {print $2; exit}')"
    test "$machine" = "$expected_machine" || {
        echo "$stage/$dll is $machine, expected $expected_machine" >&2
        exit 1
    }
}

ARCHES="${VKMT_SDL_ARCHES:-aarch64 arm64ec x86_64 i386}"
for spec in \
    "aarch64:aarch64-w64-mingw32:aarch64:IMAGE_FILE_MACHINE_ARM64" \
    "arm64ec:arm64ec-w64-mingw32:arm64ec:IMAGE_FILE_MACHINE_ARM64EC" \
    "x86_64:x86_64-w64-mingw32:x86_64:IMAGE_FILE_MACHINE_AMD64" \
    "i386:i686-w64-mingw32:i686:IMAGE_FILE_MACHINE_I386"; do
    IFS=: read -r arch triple processor machine <<<"$spec"
    case " $ARCHES " in *" $arch "*) ;; *) continue ;; esac
    build_one SDL2 "$SDL2_VERSION" "$SDL2_SOURCE" "$arch" "$triple" "$processor" "$machine"
    build_one SDL3 "$SDL3_VERSION" "$SDL3_SOURCE" "$arch" "$triple" "$processor" "$machine"
done

mkdir -p "$STAGE/include"
cmake -E copy_directory "$SDL2_SOURCE/include" "$STAGE/include/SDL2"
cmake -E copy_directory "$SDL3_SOURCE/include" "$STAGE/include/SDL3"

{
    echo "SDL2_VERSION=$SDL2_VERSION"
    echo "SDL2_UPSTREAM_COMMIT=$SDL2_UPSTREAM_COMMIT"
    echo "SDL2_COMMIT=$SDL2_COMMIT"
    echo "SDL3_VERSION=$SDL3_VERSION"
    echo "SDL3_UPSTREAM_COMMIT=$SDL3_UPSTREAM_COMMIT"
    echo "SDL3_COMMIT=$SDL3_COMMIT"
} >"$STAGE/manifest.txt"

echo "SDL_RUNTIME_STAGE_OK $STAGE"
