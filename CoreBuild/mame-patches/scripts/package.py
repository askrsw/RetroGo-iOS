#!/usr/bin/env python3
"""Wrap a successful build into emu.mame.framework (strip, core.info, licenses, codesign) without touching the app."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

from paths import OUTPUT, PATCHES, SOURCE

# Shipped frameworks use com.haharsw; override when building a derivative app.
BUNDLE_ID_PREFIX = os.environ.get("BUNDLE_ID_PREFIX", "com.haharsw")

# RetroGo's privacy manifest for core frameworks; skipped when building outside the RetroGo repository.
PRIVACY_INFO = PATCHES.parent / "framework/PrivacyInfo.xcprivacy"


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", nargs="?", default="arcade", choices=["arcade", "fbneo"])
    parser.add_argument("--optimize-link", action="store_true")
    parser.add_argument("--lto", action="store_true")
    args = parser.parse_args()
    output = OUTPUT / (args.profile + ("-lto" if args.lto else "-optimized" if args.optimize_link else ""))
    manifest = json.loads((output / "manifest.json").read_text())
    if manifest.get("exit_code") != 0:
        raise SystemExit("A successful build is required")
    subtarget = manifest.get("subtarget", "rg" + args.profile)
    source_dir = Path(manifest.get("source_dir", SOURCE))
    source = source_dir / f"{subtarget}_libretro_ios.dylib"
    if not source.is_file():
        raise SystemExit(f"Missing build product: {source}")
    framework = output / "emu.mame.framework"
    framework.mkdir(exist_ok=True)
    binary = framework / "emu.mame"
    shutil.copy2(source, output / "unstripped.dylib")
    shutil.copy2(source, binary)
    run("xcrun", "strip", "-S", "-x", str(binary))
    run("xcrun", "install_name_tool", "-id", "@rpath/emu.mame.framework/emu.mame", str(binary))
    arch = run("xcrun", "lipo", "-archs", str(binary))
    if arch != "arm64":
        raise SystemExit(f"Unexpected architectures: {arch}")
    exports = run("xcrun", "nm", "-gU", str(binary))
    required = ["init", "deinit", "api_version", "get_system_info", "get_system_av_info",
                "set_environment", "set_video_refresh", "set_audio_sample", "set_audio_sample_batch",
                "set_input_poll", "set_input_state", "set_controller_port_device", "reset", "run",
                "serialize_size", "serialize", "unserialize", "cheat_reset", "cheat_set",
                "load_game", "load_game_special", "unload_game", "get_region", "get_memory_data", "get_memory_size"]
    symbols = {line.split()[-1] for line in exports.splitlines()}
    missing = [name for name in required if "_retro_" + name not in symbols]
    missing += [name for name in ["_retrogo_mame_write_listxml", "_retrogo_mame_cheat_count", "_retrogo_mame_cheat_kind",
                                      "_retrogo_mame_cheat_description", "_retrogo_mame_cheat_is_enabled",
                                      "_retrogo_mame_cheat_set_enabled", "_retrogo_mame_cheat_parameter_position",
                                      "_retrogo_mame_cheat_set_parameter", "_retrogo_mame_cheat_activate",
                                      "_retrogo_mame_cheat_set_xml", "_retrogo_mame_cheat_reload", "_retrogo_mame_cheat_load_generation"] if name not in symbols]
    if missing:
        raise SystemExit(f"Missing libretro exports: {missing}")
    with (framework / "Info.plist").open("wb") as f:
        plistlib.dump({"CFBundleExecutable": "emu.mame", "CFBundleName": "mame",
                      "CFBundleIdentifier": BUNDLE_ID_PREFIX + ".emu.mame", "CFBundlePackageType": "FMWK",
                      "CFBundleShortVersionString": "0.289.0", "CFBundleVersion": "1",
                      "CFBundleInfoDictionaryVersion": "6.0", "MinimumOSVersion": "15.0",
                      "CFBundleSupportedPlatforms": ["iPhoneOS"]}, f)
    (framework / "core.info").write_text(f'''display_name = "Arcade (MAME - RetroGo)"
authors = "MAME Team"
supported_extensions = "zip|7z"
corename = "MAME"
license = "GPLv2"
display_version = "0.289-{args.profile}"
categories = "Emulator"
manufacturer = "Arcade"
systemname = "Arcade"
systemid = "mame"
supports_no_game = "false"
savestate = "true"
cheats = "false"
input_descriptors = "true"
memory_descriptors = "false"
libretro_saves = "true"
core_options = "true"
core_options_version = "1.0"
load_subsystem = "false"
hw_render = "false"
needs_fullpath = "true"
disk_control = "false"
database = "MAME"
description = "MAME 0.289 reduced RetroGo build ({args.profile}); only the selected driver families are included. Not every compiled set is verified to run."
''')
    if PRIVACY_INFO.is_file():
        shutil.copy2(PRIVACY_INFO, framework)
    shutil.copy2(source_dir / "COPYING", framework / "COPYING")
    shutil.copytree(source_dir / "docs/legal", framework / "legal", dirs_exist_ok=True)
    driver_source = source_dir / "build/generated/mame" / subtarget / "drivlist.cpp"
    drivers = sorted(set(re.findall(r"GAME_EXTERN\((\w+)\)", driver_source.read_text())) - {"___empty"})
    (framework / "compiled-drivers.json").write_text(json.dumps({
        "mame_version": "0.289", "revision": manifest["revision"],
        "driver_families": manifest["drivers"], "compiled_sets": drivers,
        "note": "Compilation inventory, not a verified compatibility list. Includes BIOS and non-working sets."
    }, indent=2) + "\n")
    run("codesign", "--force", "--sign", "-", str(framework))
    run("codesign", "--verify", "--strict", str(framework))
    report = {"profile": args.profile, "unstripped_bytes": source.stat().st_size,
              "framework_binary_bytes": binary.stat().st_size,
              "sha256": hashlib.sha256(binary.read_bytes()).hexdigest(), "arch": arch,
              "build_version": run("xcrun", "vtool", "-show-build", str(binary)),
              "dependencies": run("otool", "-L", str(binary)),
              "segments": run("xcrun", "size", "-m", str(binary)),
              "libretro_exports_verified": len(required), "runtime_verified": False}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
