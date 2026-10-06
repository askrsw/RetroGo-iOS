"""Shared locations for the RetroGo MAME build scripts.

The scripts live in mame-patches/scripts; the upstream checkout defaults to ../mame-libretro
next to mame-patches (override with MAME_SRC), and all build products go to its build-ios folder.
"""
import os
from pathlib import Path

PATCHES = Path(__file__).resolve().parent.parent
SOURCE = Path(os.environ.get("MAME_SRC", PATCHES.parent / "mame-libretro")).resolve()
OUTPUT = SOURCE / "build-ios"
SCAN = OUTPUT / "scan"
EXPORTS = PATCHES / "libretro.exports"
DRIVERS = PATCHES / "drivers.txt"
# Pinned upstream: libretro/mame lrmame0289 + 10 libretro-layer commits.
REVISION = "9069f39340f2d2b1795df8e71bb1d3d0fbc76598"


def read_drivers(path=DRIVERS):
    return [line.strip() for line in path.read_text().splitlines() if line.strip() and not line.startswith("#")]
