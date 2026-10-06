#!/usr/bin/env python3
"""Re-export the RetroGo patches from the working tree of the MAME checkout.

Each patch is the `git diff` of exactly one file. Existing patches keep their names; a newly
modified file gets the next number and a name derived from its path (rename it to describe the
change, then update the README). Patches whose file is no longer modified are removed.
"""
import re
import subprocess

from paths import PATCHES, SOURCE


def git(*args):
    return subprocess.check_output(["git", *args], cwd=SOURCE, text=True)


def main():
    existing = {}
    for patch in sorted(PATCHES.glob("[0-9][0-9][0-9][0-9]-*.patch")):
        path = patch.read_text().split("\n", 1)[0].split(" b/", 1)[1]
        existing[path] = patch
    modified = git("diff", "--name-only").split()
    number = max((int(p.name[:4]) for p in existing.values()), default=0)
    for path in modified:
        patch = existing.pop(path, None)
        if patch is None:
            number += 1
            slug = re.sub(r"[^a-z0-9]+", "-", path.removeprefix("src/").rsplit(".", 1)[0].lower()).strip("-")
            patch = PATCHES / f"{number:04d}-{slug}.patch"
            print(f"new   {patch.name}  ({path})")
        patch.write_text(git("diff", "--", path))
    for path, patch in existing.items():
        patch.unlink()
        print(f"removed {patch.name}  ({path} is no longer modified)")
    print(f"{len(modified)} patches in {PATCHES}")


if __name__ == "__main__":
    main()
