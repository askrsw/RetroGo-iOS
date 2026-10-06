#!/bin/sh
# Build the jitless Flycast libretro core for iOS (arm64 device).
# Upstream: https://github.com/flyinghead/flycast @ 59ed35a7ea7c1940d4c8ac221a662d0e6d6dc9ea
# Usage: CoreBuild/flycast-patches/build_ios.sh [--copy] [--install]   (run after applying the patches in this folder)
#   --copy     also copy the dylib (as flycast_libretro_ios.dylib) and flycast_libretro.info
#              into CoreBuild/framework/using/ for build_core_framework.py
#   --install  also package the core and replace RetroGo/Resources/Cores/emu.flycast.framework
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/../flycast-libretro" && pwd)"

COPY=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --copy) COPY=1 ;;
    --install) INSTALL=1 ;;
    *) echo "Unknown option: $arg" >&2; echo "Usage: $0 [--copy] [--install]" >&2; exit 1 ;;
  esac
done

# TARGET_NO_REC compiles out the SH4/ARM7/DSP dynarecs (upstream uses it for the simulator).
# IOS selects the OpenGLES headers in libretro-common.
FLAGS="-DTARGET_NO_REC -DIOS"
cmake -S "$SRC" -B "$SRC/build-ios" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_BUILD_TYPE=Release \
  -DLIBRETRO=ON -DUSE_OPENMP=OFF -DUSE_VULKAN=OFF -DUSE_BREAKPAD=OFF -DUSE_LUA=OFF \
  -DCMAKE_C_FLAGS="$FLAGS" -DCMAKE_CXX_FLAGS="$FLAGS"
cmake --build "$SRC/build-ios"

DYLIB="$SRC/build-ios/flycast_libretro.dylib"
echo "Output: $DYLIB"

if [ "$COPY" = 1 ]; then
  USING="$(cd "$HERE/../framework/using" && pwd)"
  # The libretro .info is not part of the core repo (it comes from libretro-core-info),
  # so a copy is kept next to the patches.
  cp "$DYLIB" "$USING/flycast_libretro_ios.dylib"
  cp "$HERE/flycast_libretro.info" "$USING/flycast_libretro.info"
  echo "Copied to $USING: flycast_libretro_ios.dylib, flycast_libretro.info"
fi

if [ "$INSTALL" = 1 ]; then
  python3 "$HERE/../framework/build_core_framework.py" --install "$DYLIB" "$HERE/flycast_libretro.info"
fi
