# MAME for RetroGo (iOS, no JIT)

Patches, driver list and build scripts for the [MAME libretro core](https://github.com/libretro/mame)
as shipped in RetroGo, an iOS emulator front end based on RetroArch.

RetroGo ships an arcade build of MAME: about 980 driver source files (over 11,000 runnable sets),
built for arm64 iOS devices with the C back end of MAME's dynamic recompiler, because App Store
apps cannot use JIT. The patches fix problems found when one process loads several games in a
row, and add a small C API the front end uses for `-listxml` export and MAME's own cheat engine.
Everything else is upstream MAME.

## Upstream base

| | |
|---|---|
| Repository | https://github.com/libretro/mame |
| Commit | `9069f39340f2d2b1795df8e71bb1d3d0fbc76598` (`lrmame0289-10`: MAME 0.289 plus 10 libretro-layer commits) |
| License | GPL-2.0, as stated in MAME's `COPYING` (some files, e.g. `cheat.cpp`, `clifront.cpp`, `sound.cpp`, are BSD-3-Clause). These patches and scripts are released under GPL-2.0; see `COPYING`. |

## Contents

| File | Purpose |
|---|---|
| `0001-libretro-terminate-parsed-system-name.patch` | `parseSystemName` in `retro_init.cpp` copied the name with `strncpy` and no terminator, so a shorter folder name kept the tail of the previous one. |
| `0002-clifront-recreate-machine-manager-on-each-load.patch` | `retro_finish` only runs after a successful load, so a failed load left the `mame_machine_manager` behind and the next load reused it. `lua_engine::initialize()` then ran twice on the same Lua state, and the orphaned sol2 usertype storage crashed later inside the Lua GC. Delete any leftover manager before creating a new one. |
| `0003-sound-skip-lua-sound-hook-without-hooked-devices.patch` | `sound_manager::streams_update` called the Lua `sound_hook` on every update, allocating Lua tables even when no plugin hooked a device. Skip the call when nothing is hooked. |
| `0004-libretro-export-listxml-and-native-cheat-api.patch` | Exports used by the front end through `dlsym`: `retrogo_mame_write_listxml` (writes `-listxml` for the sets compiled into this build) and eleven `retrogo_mame_cheat_*` functions that drive MAME's native cheat engine (list entries, kind, description, on/off state, parameter position; switch, select a parameter value, run one-shot cheats; hand over cheat XML in memory and reload it). Requests that change the cheat state are queued and applied at the start of `retro_run`, on the emulation thread. |
| `0005-retromain-fresh-options-on-each-load.patch` | `retro_options` was a function-local static reused by every load. `emu_options` only applies a driver's default slot option when the slot option does not exist yet, so the previous game's cartridge (e.g. Neo Geo `cslot1`) stayed selected: the next game booted to the BIOS test screen or crashed while decrypting. Create the options object for each load; the old one is leaked on purpose because the previous OSD interface and machine manager may still reference it. |
| `0006-cheat-frontend-xml-and-direct-parameter-selection.patch` | `cheat_manager::reload()` loads cheat XML handed over by the front end (parsing moved into `parse_cheat_file`) instead of only searching the cheat path, and no longer writes a debug `output.xml`. Adds `cheat_parameter::position`/`set_position` and `cheat_entry::select_parameter_position`, so a value can be selected directly instead of stepping through the values in between. |
| `0007-cheat-header-for-frontend-xml-and-parameter-selection.patch` | Declarations for 0006. |
| `drivers.txt` | Driver source files (relative to `src/mame`) compiled into the core. |
| `libretro.exports` | Exported symbols: the libretro API plus the `retrogo_mame_*` functions. `package.py` checks that all of them are present. |
| `COPYING` | GNU General Public License, version 2 (from MAME's `docs/legal/GPL-2.0`). |
| `build_ios.sh` | Build and package the core for arm64 iOS devices. |
| `scripts/` | The build, packaging and driver-selection scripts (see below). |

Each patch is the `git diff` of exactly one file, applied with `git apply` (not `git am`).

### Scripts

| Script | Purpose |
|---|---|
| `scripts/build.py` | Apply the patches to a clean checkout (or verify that the checkout matches them), then run `make -f Makefile.libretro` with the drivers from `drivers.txt`. Writes `build-ios/<profile>/manifest.json` (command, revision, full source diff) and `build.log`. |
| `scripts/package.py` | Strip the dylib and wrap it into `emu.mame.framework` with `core.info`, MAME's `COPYING` and `docs/legal`, a list of compiled sets, and an ad-hoc signature; verify the exports. |
| `scripts/export_patches.py` | Re-export the patches after changing the MAME source. |
| `scripts/driver_scan.py` | Measure the size each driver file adds on top of a small baseline, one build per driver. Slow (hours); only needed when reselecting drivers. |
| `scripts/select_drivers.py` | Choose the driver set from the scan and write `drivers.txt`. |
| `scripts/fbneo_align.py` | Optional: match the FBNeo arcade set list (`--dats` from a libretro-fbneo checkout) against the MAME driver files and estimate the size of an FBNeo-sized build. The `fbneo` profile of `build.py` reads a `build-ios/scan/fbneo_selection.json` written by hand from its result. |
| `scripts/naomi_scan.py` | Check whether Demul/Flycast NAOMI/Atomiswave dumps can be cut into MAME sets (they cannot; kept for reference). |
| `scripts/paths.py` | Shared locations and the pinned upstream revision. |

## Driver selection

`select_drivers.py` keeps every arcade driver file with at least one working game and excludes:

- files without a working parent set;
- gambling, fruit, pinball and medal machines (by manufacturer folder, game names and source comments);
- PC-based or very large platforms (a single driver adding more than 4 MiB to the baseline);
- drivers that fail to build on their own.

Some files are always kept (`KEEP` in the script): the systems RetroGo started with (CPS1/CPS2,
Neo Geo, PGM/PGM2 and others), Cave CV1000 and Atomiswave/NAOMI, which need extra source files the
`SOURCES=` dependency scan misses (`cave/cv1k_v_blit0-8.cpp`; `sega/dc.cpp` and `sega/naomi.cpp`),
and a few classics whose size is mostly shared netlist or CPU code (Galaxian, Mario Bros.,
Carnival, Sega G80, Tetris Plus 2, Seta 2, Hard Drivin').

The rules are heuristics; `build-ios/scan/selection.md` lists every kept and excluded file.

## Build

Requirements: macOS with Xcode and the iOS SDK, Python 3.9+. MAME's own build files are generated
with GENie by `Makefile.libretro`; no CMake is needed.

The script expects the source in `../mame-libretro`, next to this folder:

```sh
git clone https://github.com/libretro/mame.git mame-libretro
git -C mame-libretro checkout 9069f39340f2d2b1795df8e71bb1d3d0fbc76598
sh mame-patches/build_ios.sh
```

`build.py` applies the patches on the first run. The first build compiles all of MAME's core and
the selected drivers and takes a long time; later builds reuse the objects in `mame-libretro/build`.

Outputs, in `mame-libretro/build-ios/arcade-optimized/`:

- `emu.mame.framework`: the packaged core (about 101 MiB).
- `unstripped.dylib`: the same binary with symbols, to symbolicate crash logs with
  `atos -l 0 -o unstripped.dylib <addresses>`.
- `manifest.json`, `build.log`, `report.json`: build command, source diff, sizes, exports.

Build settings, in `scripts/build.py`:

- `platform=ios-arm64`, deployment target iOS 15.0, `SUBTARGET=rgarcadeopt`,
  `SOURCES=` with the drivers from `drivers.txt`.
- `FORCE_DRC_C_BACKEND=1`: CPU cores with a recompiler use its C back end, no executable memory.
- `-Wl,-dead_strip` and `-exported_symbols_list libretro.exports`, which let the linker drop code
  that is unreachable from the exported functions.
- `SYMBOLS=0`, `STRIP_SYMBOLS=0`; `package.py` strips the framework copy.

Before each build, `build.py` deletes `build/libretro/bin/mame_<subtarget>`: the per-subtarget
archives (`liboptional.a` and others) are not rebuilt when the set of devices changes, which
otherwise ends in missing symbols at link time.

In the RetroGo repository, `build_ios.sh --copy` also replaces
`RetroGo/Resources/Cores/emu.mame.framework` (the previous one is deleted).

Unlike the other RetroGo cores, MAME does not go through [`../framework/build_core_framework.py`](../framework/README.md):
`package.py` builds the complete framework itself and writes its `core.info`, so `--copy`
installs the framework rather than a dylib and `.info` pair. After upgrading MAME, update the
version strings in `package.py` (`core.info`, `Info.plist`, `compiled-drivers.json`).

## Updating to a newer upstream

1. Reset the checkout (all changes live in the patches) and switch to the new revision:

   ```sh
   cd mame-libretro
   git checkout -- .
   git fetch origin
   git checkout <revision>
   ```

2. Apply the patches with a three-way merge and resolve conflicts:

   ```sh
   for p in ../mame-patches/000*.patch; do git apply --3way "$p" || echo "conflict: $p"; done
   ```

   Check each patch against upstream before keeping it:

   | Patch | Drop it when |
   |---|---|
   | 0001 | `parseSystemName` terminates the copied name. |
   | 0002 | The failure path of `retro_load_game` releases the machine manager. |
   | 0003 | `streams_update` only calls the Lua hook when a device is hooked. |
   | 0004 | Never; check that `info_xml_creator` and the cheat manager interfaces still match. |
   | 0005 | `retromain.cpp` no longer keeps `retro_options` in a static, or `emu_options::add_and_remove_slot_options()` resets existing slot options. |
   | 0006, 0007 | Never; `src/frontend/mame/cheat.cpp` changes now and then upstream. |

   Also check that the libretro layer did not start requesting something the front end lacks.
   Upstream added VFS support in `eb34274`: the core asks for VFS v4, RetroGo's RetroArch offers
   v3, so VFS stays off and files are read through the POSIX layer. With a v4 front end, note that
   `fexists` no longer falls back to `osd_stat` and `libretro_vfs_file_exists` checks `stat` but
   calls `stat_64`.

3. Export the patches and update the pinned revision in `scripts/paths.py`, `build_ios.sh` and
   this README:

   ```sh
   python3 ../mame-patches/scripts/export_patches.py
   ```

4. Driver files move between folders upstream (0.289: `neogeo/` into `snk/`,
   `cave/ep1c12_blit*` renamed to `cave/cv1k_v_blit*`, `midway/` split into `bally/` and
   `williams/`). Update `KEEP` in `select_drivers.py` and `BASELINE` in `driver_scan.py`, then
   rescan and reselect:

   ```sh
   python3 ../mame-patches/scripts/driver_scan.py list
   python3 ../mame-patches/scripts/driver_scan.py baseline
   python3 ../mame-patches/scripts/driver_scan.py run
   python3 ../mame-patches/scripts/driver_scan.py report
   python3 ../mame-patches/scripts/select_drivers.py
   ```

   Compare the new `drivers.txt` with the old one by set name, not by file name, to tell renamed
   files from removed ones.

5. Build, then check that `report.json` lists all exports and that the size is reasonable.

6. Regression test on a device, without restarting the app between steps:

   - Neo Geo, CPS1/CPS2, PGM/PGM2, Cave, NAOMI/Atomiswave: start, sound, coins, a save state round trip.
   - Switch games: `mslug` ↔ `kof98` and `kog` ↔ `ct2k3sp` (patch 0005), `snowbros` → `bgaregga`.
   - Start two games with missing files so they fail to load, then play `blswhstl` for a few
     minutes (patch 0002).
   - Cheats: switch, select a parameter value, run a one-shot cheat, reset the game, reopen it.
   - Export `-listxml` from the app; the front end rebuilds its catalog when the core changes.

## Notes for RetroGo

- iOS does not unload `emu.mame` on `dlclose`, so static state survives between games in one
  process; this is why patches 0002 and 0005 matter here.
- The front end calls `retrogo_mame_write_listxml` on a background thread and never while a game
  runs.
- Cheat files come from Pugsy's MAME Cheat Collection (mamecheat.co.uk), imported by the user;
  no cheat data is part of the core or these patches.
