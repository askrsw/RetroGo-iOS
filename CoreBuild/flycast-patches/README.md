# Flycast for RetroGo (iOS, no JIT)

Patches and build script for the [Flycast](https://github.com/flyinghead/flycast) libretro core
as shipped in RetroGo, an iOS emulator front end based on RetroArch.

iOS apps distributed through the App Store cannot use JIT, so this build compiles out all
dynamic recompilers and runs the SH4, ARM7 and DSP on Flycast's interpreters. Everything else
is upstream Flycast.

## Upstream base

| | |
|---|---|
| Repository | https://github.com/flyinghead/flycast |
| Commit | `59ed35a7ea7c1940d4c8ac221a662d0e6d6dc9ea` |
| License | GPLv2 (these patches are released under the same license) |

## Contents

| File | Purpose |
|---|---|
| `0001-libretro-allow-jitless-iOS-builds-and-fall-back-to-G.patch` | Skip the libretro "Cannot run without JIT" check when no dynarec is compiled in; fall back to GLES3 when the frontend prefers an API this build lacks (Vulkan). |
| `0002-sh4-interpreter-rebind-context-on-reset-after-the-ad.patch` | On Apple platforms the emulator stays initialized across `retro_deinit`/`retro_init` while the address space is released and reserved again; rebind the interpreter's context so a second game launch does not use freed memory. |
| `0003-libretro-log-instead-of-mame-romset-warning.patch` | Log instead of showing "Please upgrade to MAME romsets" on screen for `.lst`/`.bin`/`.dat` arcade dumps. |
| `0004-naomi-restore-coin-setting-when-free-play-off.patch` | Free play is written into the saved NAOMI EEPROM, so turning the option off changed nothing; restore the game's default coin setting instead. |
| `build_ios.sh` | Configure and build the core for arm64 iOS devices. |
| `flycast_libretro.info` | libretro core info file, taken from [libretro-core-info](https://github.com/libretro/libretro-core-info) (not part of the Flycast repository). |
| `COPYING` | GNU General Public License v2, copied from Flycast's `LICENSE`. |

No patch touches memory protection: VRAM pages stay write-protected as upstream, because the
texture cache relies on write faults to invalidate textures, also in the interpreter.

## Build

Requirements: Xcode with the iOS SDK, CMake 3.22+, Ninja.

The script expects the source in `../flycast-libretro`, next to this folder:

```sh
git clone https://github.com/flyinghead/flycast.git flycast-libretro
cd flycast-libretro
git checkout 59ed35a7ea7c1940d4c8ac221a662d0e6d6dc9ea
git submodule update --init --recursive
git switch -c retrogo-ios
git am ../flycast-patches/000*.patch
cd ..
sh flycast-patches/build_ios.sh
```

The output is `flycast-libretro/build-ios/flycast_libretro.dylib`.

Build settings, all in `build_ios.sh`:

- `-DTARGET_NO_REC` compiles out the SH4/ARM7/DSP dynarecs. Upstream uses it for the iOS
  simulator; here it is used for devices too.
- `-DIOS` makes libretro-common pick the OpenGL ES headers.
- `LIBRETRO=ON`, `USE_VULKAN=OFF`, `USE_OPENMP=OFF`, `USE_BREAKPAD=OFF`, `USE_LUA=OFF`,
  deployment target iOS 15.0, Release.

In the RetroGo repository, `build_ios.sh --copy` also copies the dylib (as
`flycast_libretro_ios.dylib`) and `flycast_libretro.info` into
`CoreBuild/framework/using/`, where `build_core_framework.py` wraps cores into
frameworks (see [`../framework/README.md`](../framework/README.md)). `--install` packages the
core directly and replaces `RetroGo/Resources/Cores/emu.flycast.framework`; both options can be
given together.

Some submodules (e.g. `core/deps/tinygettext/external/tinycmmc`) can fail to clone on a slow
connection; rerun `git submodule update --init --recursive` until it completes.

## Updating to a newer upstream

Keep the patches as separate commits on the `retrogo-ios` branch and rebase them; do not
`git pull` (a merge commit makes the patches impossible to export cleanly).

1. Fetch and rebase:

   ```sh
   cd flycast-libretro
   git fetch origin
   git rebase origin/master
   git submodule update --init --recursive
   ```

   If the clone is shallow and Git cannot find the base commit, run `git fetch --unshallow`
   first.

2. Resolve conflicts, keeping the intent of each patch. Where they are likely:

   | Patch | File | Notes |
   |---|---|---|
   | 0001, 0003 | `shell/libretro/libretro.cpp` | Changes often upstream. The JIT check lives in `retro_load_game`; the GLES fallback after the render API selection; the romset message where `.lst`/`.bin`/`.dat` are detected. |
   | 0002 | `core/hw/sh4/interpr/sh4_interpreter.cpp` | If upstream now re-initializes the interpreter (or its context) on every load, drop this patch. |
   | 0004 | `core/hw/naomi/naomi_flashrom.cpp` | End of `configure_naomi_eeprom`. If upstream already restores the coin setting, drop it. |

   Also check that nothing new reintroduces JIT-only paths or `PROT_EXEC` mappings outside
   `#if FEAT_SHREC == DYNAREC_JIT`, and that `retro_load_game` has no new iOS-only refusal.

3. Export the patches again and update the base commit:

   ```sh
   rm ../flycast-patches/000*.patch
   git format-patch origin/master -o ../flycast-patches
   ```

   Then replace the commit hash in `build_ios.sh` and in this README with
   `git rev-parse origin/master`.

4. Check that the patches reproduce the branch exactly (empty diff expected):

   ```sh
   git worktree add --detach /tmp/flycast-check origin/master
   git -C /tmp/flycast-check am "$PWD"/../flycast-patches/000*.patch
   git diff --stat retrogo-ios "$(git -C /tmp/flycast-check rev-parse HEAD)"
   git worktree remove --force /tmp/flycast-check
   ```

5. Rebuild from scratch (`rm -rf build-ios`, then `build_ios.sh`), update the core info file if
   the upstream `flycast_libretro.info` in libretro-core-info changed (new extensions or
   firmware), and package the framework.

6. Regression test on a device, launched without the debugger (Xcode stops on every VRAM write
   fault):

   - A 2D game with frequently changing text or sprites (texture cache invalidation), e.g. a
     dialogue scene that used to break when VRAM protection was disabled.
   - A 3D game, for speed and audio.
   - Close and reopen the same game, then switch games, without restarting the app (patch 0002).
   - A NAOMI game with free play turned on and off, reopening the game each time (patch 0004);
     an Atomiswave game with coins.
   - A second launch after the app was in the background, and a save state round trip.

## Notes for RetroGo

- The core must not use RetroGo's independent game-logic thread; it runs on the DisplayLink
  runner, and Flycast's threaded rendering paces emulation to `retro_run`. The core options
  that turn threaded rendering off or report swap-interval changes are hidden for this reason.
- GL `context_reset` has to run on the main thread, where the EAGL context is current; this is
  handled in RetroGo's RetroArch fork, not in these patches.
