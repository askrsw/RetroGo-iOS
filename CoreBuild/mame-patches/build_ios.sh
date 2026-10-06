#!/bin/sh
# Build RetroGo's MAME libretro core (arcade driver set) for iOS (arm64 device).
# Upstream: https://github.com/libretro/mame @ 9069f39340f2d2b1795df8e71bb1d3d0fbc76598 (lrmame0289-10)
# Usage: CoreBuild/mame-patches/build_ios.sh [--copy] [--jobs N]
#   The patches in this folder are applied automatically to a clean checkout; a checkout that
#   already carries changes must match them exactly, otherwise the build stops.
#   --copy    also replace RetroGo/Resources/Cores/emu.mame.framework with the new build
#   --jobs N  parallel compile jobs (default: number of CPU cores)
# Set MAME_SRC to build a checkout other than ../mame-libretro.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "${MAME_SRC:-$HERE/../mame-libretro}" && pwd)"
export MAME_SRC="$SRC"

COPY=0
JOBS="$(sysctl -n hw.ncpu)"
while [ $# -gt 0 ]; do
  case "$1" in
    --copy) COPY=1 ;;
    --jobs) shift; JOBS="$1" ;;
    *) echo "Unknown option: $1" >&2; echo "Usage: $0 [--copy] [--jobs N]" >&2; exit 1 ;;
  esac
  shift
done

# Compile the drivers listed in drivers.txt, export only libretro.exports, dead-strip, then
# wrap the dylib into emu.mame.framework (strip, core.info, licenses, ad-hoc signature).
python3 "$HERE/scripts/build.py" arcade --optimize-link --jobs "$JOBS"
python3 "$HERE/scripts/package.py" arcade --optimize-link

OUT="$SRC/build-ios/arcade-optimized"
echo "Output: $OUT/emu.mame.framework"
echo "        $OUT/unstripped.dylib (symbols, for atos)"

if [ "$COPY" = 1 ]; then
  CORES="$(cd "$HERE/../../RetroGo/Resources/Cores" && pwd)"
  rm -rf "$CORES/emu.mame.framework"
  cp -R "$OUT/emu.mame.framework" "$CORES/"
  echo "Copied to $CORES/emu.mame.framework"
fi
