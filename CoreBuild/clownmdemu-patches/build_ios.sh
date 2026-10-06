#!/bin/sh
# Build the ClownMDEmu libretro core for iOS (arm64 device).
# Upstream: https://github.com/Clownacy/clownmdemu-libretro @ de598ed95e881a234a470c33459cd9eeaa66d38f
# Usage: CoreBuild/clownmdemu-patches/build_ios.sh [--copy] [--install]   (run after applying the patches in this folder)
#   --copy     also copy the dylib and clownmdemu_libretro.info
#              into CoreBuild/framework/using/ for build_core_framework.py
#   --install  also package the core and replace RetroGo/Resources/Cores/emu.clownmdemu.framework
# Set CLOWNMDEMU_SRC to build a checkout other than ../clownmdemu-libretro.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "${CLOWNMDEMU_SRC:-$HERE/../clownmdemu-libretro}" && pwd)"

COPY=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --copy) COPY=1 ;;
    --install) INSTALL=1 ;;
    *) echo "Unknown option: $arg" >&2; echo "Usage: $0 [--copy] [--install]" >&2; exit 1 ;;
  esac
done

# The core is a unity build (unity.c includes every source file) and the Makefile does not
# track those includes, so always start clean or source changes are silently ignored.
cd "$SRC"
make clean >/dev/null
make platform=ios-arm64 -j"$(sysctl -n hw.ncpu)"

DYLIB="$SRC/clownmdemu_libretro_ios.dylib"
echo "Output: $DYLIB"

if [ "$COPY" = 1 ]; then
  USING="$(cd "$HERE/../framework/using" && pwd)"
  # The libretro .info is not part of the core repo (it comes from libretro-core-info),
  # so a copy is kept next to the patches.
  cp "$DYLIB" "$USING/clownmdemu_libretro_ios.dylib"
  cp "$HERE/clownmdemu_libretro.info" "$USING/clownmdemu_libretro.info"
  echo "Copied to $USING: clownmdemu_libretro_ios.dylib, clownmdemu_libretro.info"
fi

if [ "$INSTALL" = 1 ]; then
  python3 "$HERE/../framework/build_core_framework.py" --install "$DYLIB" "$HERE/clownmdemu_libretro.info"
fi
