# ClownMDEmu for RetroGo (iOS)

Patches and build script for the [ClownMDEmu](https://github.com/Clownacy/clownmdemu-libretro)
libretro core as shipped in RetroGo, an iOS emulator front end based on RetroArch. RetroGo uses
it for Mega Drive / Genesis and Mega-CD games.

The patches fix front-end behaviour and a few compatibility problems found while testing;
everything else is upstream ClownMDEmu.

## Upstream base

| | |
|---|---|
| Repository | https://github.com/Clownacy/clownmdemu-libretro |
| Commit | `de598ed95e881a234a470c33459cd9eeaa66d38f` (core version v1.6.12) |
| Submodules | The revisions recorded in that commit (`common`, `common/core`, `libretro-common`, ...) |
| License | AGPLv3 or later (these patches are released under the same license) |

## Contents

| File | Applies to | Purpose |
|---|---|---|
| `0001-refresh-palette-after-savestate-load.patch` | repository root | The front end's colour lookup table is only filled by CRAM writes and is not part of a save state. Rebuild it from the restored CRAM on the next frame after `retro_unserialize`, so loading a state into a freshly loaded core no longer shows a black picture. |
| `0002-auto-detect-region-from-cartridge-header.patch` | repository root | Add an `Auto` value (now the default) to the Region and TV Standard options and pick them from the cartridge header (`J`/`U`/`E` letters or the hex bitmask). Japan- and Europe-only games no longer stop at a region lock screen. Headers with non-ASCII bytes (common in hacked ROMs) fall back to International / NTSC. |
| `0003-load-interleaved-smd-dumps.patch` | repository root | Load Super Magic Drive dumps: a 512-byte header with `0xAA 0xBB` at bytes 8/9 and 16 KiB interleaved blocks are de-interleaved on load. `.smd` is added to the extensions; plain binaries named `.smd` are left alone. |
| `0004-cap-emulator-warning-logs.patch` | repository root | Report at most 100 emulator warnings per loaded game. Some games trigger hundreds of thousands of warnings while booting (e.g. Golden Axe II), which stalls a front end that logs synchronously. |
| `0005-common-core-delay-vint-to-end-of-hblank.patch` | `common/core` submodule | Raise V-Int near H-counter 0x1FF instead of at the end of active display, as upstream's own TODO notes. Fixes games that check the H-blank status bit in their V-Int handler and otherwise stay on a black screen (e.g. Double Dragon II). |
| `build_ios.sh` | | Build the core for arm64 iOS devices. |
| `clownmdemu_libretro.info` | | libretro core info file written for RetroGo. ClownMDEmu has no entry in libretro-core-info, so this file is not taken from upstream. |
| `COPYING` | | GNU Affero General Public License v3, copied from ClownMDEmu's `LICENCE.txt`. |

The patches are plain `git diff` output, applied with `git apply` (not `git am`). Patch 0005
has paths relative to the `common/core` submodule.

## Build

Requirements: Xcode with the iOS SDK. The core builds with the upstream Makefile; no CMake is
needed.

The script expects the source in `../clownmdemu-libretro`, next to this folder:

```sh
git clone https://github.com/Clownacy/clownmdemu-libretro.git clownmdemu-libretro
cd clownmdemu-libretro
git checkout de598ed95e881a234a470c33459cd9eeaa66d38f
git submodule update --init --recursive
git apply ../clownmdemu-patches/0001-*.patch ../clownmdemu-patches/0002-*.patch \
          ../clownmdemu-patches/0003-*.patch ../clownmdemu-patches/0004-*.patch
git -C common/core apply "$PWD"/../clownmdemu-patches/0005-*.patch
cd ..
sh clownmdemu-patches/build_ios.sh
```

The output is `clownmdemu-libretro/clownmdemu_libretro_ios.dylib`.

Notes:

- The core is a unity build (`unity.c` includes every source file) and the Makefile does not
  track those includes. `build_ios.sh` therefore always runs `make clean` first; when building
  by hand, do the same, or source changes are silently ignored.
- The Makefile sets an iOS 8.0 deployment target. RetroGo's [`../framework/build_core_framework.py`](../framework/README.md) rewrites
  it to iOS 15.0 with `vtool` when it wraps the dylib, so the Makefile is left unchanged.
- `libretro-interface.c` and the other files in `source/` use CRLF line endings, while
  `options.h` uses LF. Keep the existing line endings when editing, otherwise the patches turn
  into whole-file diffs.

In the RetroGo repository, `build_ios.sh --copy` also copies the dylib and
`clownmdemu_libretro.info` into `CoreBuild/framework/using/`, where
`build_core_framework.py` wraps cores into frameworks (see [`../framework/README.md`](../framework/README.md)).
`--install` packages the core directly and replaces
`RetroGo/Resources/Cores/emu.clownmdemu.framework`; both options can be given together. Set `CLOWNMDEMU_SRC` to build a checkout
in another location.

## Updating to a newer upstream

1. Update the checkout and its submodules:

   ```sh
   cd clownmdemu-libretro
   git checkout -- . && git -C common/core checkout -- .
   git fetch origin
   git checkout origin/master
   git submodule update --init --recursive
   ```

2. Apply the patches again (see Build) and resolve conflicts, keeping the intent of each patch.
   Where they are likely:

   | Patch | File | Notes |
   |---|---|---|
   | 0001 | `source/libretro-interface.c` | `ScanlineRenderedCallback` and `retro_unserialize`. If upstream now restores the colour table on state load, drop the patch. |
   | 0002 | `source/libretro-interface.c`, `source/options.h` | `UpdateOptions`, `retro_load_game_special` and the option definitions. If upstream adds region auto-detection, drop the patch and make sure its default is the automatic value. |
   | 0003 | `source/libretro-interface.c` | `CreateROMBuffer` and `CARTRIDGE_FILE_EXTENSIONS`. Drop it if upstream loads SMD dumps itself. |
   | 0004 | `source/libretro-interface.c` | `ClownMDEmuLog`. Drop it if upstream rate-limits its warnings. |
   | 0005 | `common/core/source/clownmdemu.c` | The `scanline == console_vertical_resolution` branch of the frame loop. Drop it once upstream raises V-Int at the right H position (for example after the VDP becomes slot-based). |

3. Export the patches again. Patches 0001–0004 are diffs of the repository root, each
   relative to the previous patches; patch 0005 is the diff of `common/core`:

   ```sh
   # with only patches 0001..N-1 applied and committed (or staged), then N applied:
   git diff > ../clownmdemu-patches/000N-<name>.patch
   git -C common/core diff --relative > ../clownmdemu-patches/0005-common-core-delay-vint-to-end-of-hblank.patch
   ```

   Then replace the commit hash in `build_ios.sh` and in this README, and update
   `display_version` in `clownmdemu_libretro.info` if the core version changed.

4. Check that the patches reproduce the working tree exactly: apply them to a fresh checkout of
   the new base commit and compare `source/` and `common/core/source/` with your working copy
   (`diff -r` should print nothing).

5. Rebuild and package the framework (`build_ios.sh --install`), and run a regression test.

## Regression test

On a device, with RetroGo's auto save/load state turned on (the default):

- Open a Mega Drive game, play, close it, then open it again from a cold start of the app: the
  picture must appear right away with correct colours (patch 0001).
- A Japan-only game and a Europe-only game start without a region lock screen; the Europe-only
  game runs at 50 Hz (patch 0002).
- An interleaved `.smd` dump starts; a plain binary named `.smd` still starts (patch 0003).
- Golden Axe II starts with picture and sound within a few seconds (patch 0004).
- Double Dragon II reaches its title screen (patch 0005).
- A Mega-CD game boots without a BIOS, with CD audio.
- Cheats, save states, and closing and reopening different games without restarting the app.

Known issues that are not addressed by these patches:

- Cartridge mappers (e.g. the Super Street Fighter II mapper), EEPROM saves, 32X and
  Master System mode are not emulated upstream.
- `Mazin Saga (Japan)` stops on a white screen after its intro (an animation table lookup goes
  out of alignment and ends in an address error); the USA version works.
- ROM hacks that write words to odd addresses crash with an address error, as on real hardware.
  PicoDrive and Gens ignore alignment, so such hacks may only work there.

## Notes for RetroGo

- RetroGo runs this core on its independent game-logic thread and uses the `genesis` on-screen layout
  (A/B/C → RetroPad Y/B/A, X/Y/Z → L/X/R, Mode → Select), the same convention as other
  Mega Drive cores.
- RetroGo ships its own core option catalog for this core; the Debug group is hidden.
