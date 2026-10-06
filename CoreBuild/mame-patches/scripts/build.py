#!/usr/bin/env python3
"""Build RetroGo's MAME libretro core for arm64 iOS devices from the pinned upstream source plus the patches."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import time

from paths import DRIVERS, EXPORTS, OUTPUT, PATCHES, REVISION, SOURCE, SCAN, read_drivers

# ThinLTO objects are bitcode and must not share the regular object cache; use an APFS clone of the tree.
LTO_SOURCE = SOURCE.parent / (SOURCE.name + "-lto")
# Driver lists per profile: "arcade" is the shipped core; "fbneo" comes from scripts/fbneo_align.py.
PROFILES = {"arcade": DRIVERS, "fbneo": SCAN / "fbneo_selection.json"}


def profile_drivers(profile):
    path = PROFILES[profile]
    if path.suffix == ".json":
        return json.loads(path.read_text())["drivers"]
    return read_drivers(path)


def capture(*args):
    return subprocess.check_output(args, cwd=SOURCE, text=True).strip()


def ensure_patches():
    """Apply the *.patch files to a pristine tree, or verify the tree already equals exactly those patches.

    Each patch covers exactly one file (see README), so the check compares per-file diffs."""
    patches = {}
    for patch in sorted(PATCHES.glob("*.patch")):
        text = patch.read_text()
        path = text.split("\n", 1)[0].split(" b/", 1)[1]
        patches[path] = (patch, text)
    modified = set(capture("git", "diff", "--name-only").split())
    if not modified:
        for patch, _ in patches.values():
            subprocess.check_call(["git", "apply", str(patch)], cwd=SOURCE)
        print(f"Applied {len(patches)} patches from {PATCHES}", flush=True)
        return
    stale = sorted(modified ^ set(patches))
    stale += [path for path in sorted(modified & set(patches))
              if subprocess.check_output(["git", "diff", "--", path], cwd=SOURCE, text=True) != patches[path][1]]
    if stale:
        raise SystemExit("MAME source changes differ from the patches for: " + ", ".join(stale) +
                         "\nRe-export the patches (scripts/export_patches.py) or reset the tree with `git checkout -- .`.")


def sync_lto_source():
    """Create the LTO clone once, then keep its source patches identical to the main tree."""
    if not LTO_SOURCE.exists():
        subprocess.check_call(["cp", "-c", "-R", str(SOURCE), str(LTO_SOURCE)])
        shutil.rmtree(LTO_SOURCE / "build", ignore_errors=True)
    diff = subprocess.check_output(["git", "diff", "--binary"], cwd=SOURCE)
    subprocess.check_call(["git", "checkout", "--", "."], cwd=LTO_SOURCE)
    if diff:
        subprocess.run(["git", "apply"], cwd=LTO_SOURCE, input=diff, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", nargs="?", default="arcade", choices=list(PROFILES))
    parser.add_argument("--jobs", type=int, default=6)
    parser.add_argument("--optimize-link", action="store_true")
    parser.add_argument("--lto", action="store_true", help="ThinLTO build in a clone of the source tree (<source>-lto)")
    args = parser.parse_args()
    if args.lto and not args.optimize_link:
        parser.error("--lto requires --optimize-link")
    ensure_patches()
    source = SOURCE
    if args.lto:
        sync_lto_source()
        source = LTO_SOURCE
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    revision = capture("git", "rev-parse", "HEAD")
    if revision != REVISION:
        raise SystemExit(f"Expected source {REVISION}, found {revision}")
    drivers = profile_drivers(args.profile)
    output = OUTPUT / (args.profile + ("-lto" if args.lto else "-optimized" if args.optimize_link else ""))
    output.mkdir(parents=True, exist_ok=True)
    sdk = capture("xcrun", "--sdk", "iphoneos", "--show-sdk-path")
    subtarget = "rg" + args.profile + ("lto" if args.lto else "opt" if args.optimize_link else "")
    lto = " -flto=thin" if args.lto else ""
    command = ["make", "-f", "Makefile.libretro", f"-j{args.jobs}",
               "platform=ios-arm64", f"SUBTARGET={subtarget}",
               "SOURCES=" + ",".join("src/mame/" + d for d in drivers),
               "ARCHOPTS=-target arm64-apple-ios15.0 -isysroot " + sdk + " -miphoneos-version-min=15.0 -arch arm64" + lto,
               "REGENIE=1", "SYMBOLS=0", "STRIP_SYMBOLS=0", "VERBOSE=0",
               "FORCE_DRC_C_BACKEND=1", "PYTHON_EXECUTABLE=" + sys.executable]
    if args.optimize_link:
        command.append("LDOPTS=-Wl,-dead_strip -Wl,-exported_symbols_list," + str(EXPORTS) +
                       (" -Wl,-cache_path_lto," + str(OUTPUT / "lto-cache") if args.lto else ""))
    manifest = {"revision": revision, "source_diff": capture("git", "diff"),
                "environment_flags": {k: os.environ.get(k) for k in
                                      ("CPPFLAGS", "CFLAGS", "CXXFLAGS", "LDFLAGS", "CPATH", "LIBRARY_PATH")},
                "profile": args.profile, "subtarget": subtarget, "lto": args.lto, "source_dir": str(source), "optimize_link": args.optimize_link,
                "drivers": drivers,
                "xcode": capture("xcodebuild", "-version"), "sdk": sdk,
                "command": command, "started": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(shlex.join(command), flush=True)
    env = dict(os.environ, LC_ALL="C", CLANG_MODULE_CACHE_PATH=str(OUTPUT / "module-cache"))
    # Per-subtarget archives (liboptional.a etc.) are not rebuilt when the device set changes; start clean.
    shutil.rmtree(source / f"build/libretro/bin/mame_{subtarget}", ignore_errors=True)
    with (output / "build.log").open("w") as log:
        result = subprocess.run(command, cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT)
    manifest["exit_code"] = result.returncode
    manifest["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Build exit: {result.returncode}; log: {output / 'build.log'}", flush=True)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
