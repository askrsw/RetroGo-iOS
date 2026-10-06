#!/usr/bin/env python3
"""Map FBNeo arcade sets onto the MAME driver files of the checkout and estimate the size of an FBNeo-aligned build.

Reads the FBNeo ClrMamePro DATs (Arcade + Neogeo), matches set names against MAME GAME() entries,
and joins with build-ios/scan results. Writes build-ios/scan/fbneo_align.{json,md}. No build is run.
"""
import argparse
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from paths import SCAN, SOURCE

SRC = SOURCE / "src/mame"
DAT_FILES = ["FinalBurn Neo (ClrMame Pro XML, Arcade only).dat", "FinalBurn Neo (ClrMame Pro XML, Neogeo only).dat"]
GAME = re.compile(r"^\s*GAMEL?\s*\((.*)$", re.M)


def mame_sets():
    sets = {}
    for path in SRC.rglob("*.cpp"):
        for line in GAME.findall(path.read_text(errors="replace")):
            f = [x.strip() for x in line.split(",")]
            if len(f) > 2:
                sets[f[1]] = {"driver": str(path.relative_to(SRC)), "parent": f[2] == "0",
                              "working": "NOT_WORKING" not in line}
    return sets


def fbneo_sets(dats):
    out = {}
    for name in DAT_FILES:
        for g in ET.parse(dats / name).getroot().iter("game"):
            out[g.get("name")] = {"clone": bool(g.get("cloneof")), "bios": g.get("isbios") == "yes",
                                  "desc": g.findtext("description", ""), "fb_source": g.get("sourcefile", "")}
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dats", type=Path, required=True, help="the dats folder of a libretro-fbneo checkout")
    args = parser.parse_args()
    mame, fb = mame_sets(), fbneo_sets(args.dats)
    results = {json.loads(l)["driver"]: json.loads(l) for l in (SCAN / "results.jsonl").read_text().splitlines()}
    base = json.loads((SCAN / "baseline.json").read_text())

    per_driver, missing = {}, []
    for name, info in fb.items():
        m = mame.get(name)
        if not m:
            missing.append(name)
            continue
        d = per_driver.setdefault(m["driver"], {"sets": 0, "parents": 0, "working": 0, "examples": []})
        d["sets"] += 1
        d["parents"] += not info["clone"] and not info["bios"]
        d["working"] += m["working"]
        if not info["clone"] and len(d["examples"]) < 4:
            d["examples"].append(info["desc"])
    for drv, d in per_driver.items():
        r = results.get(drv, {})
        d["delta"] = 0 if drv in base["drivers"] else r.get("delta")

    rows = sorted(per_driver.items(), key=lambda kv: -(kv[1]["delta"] or 0))
    known = [d["delta"] for _, d in rows if d["delta"] is not None]
    (SCAN / "fbneo_align.json").write_text(json.dumps(
        {"drivers": [k for k, _ in rows], "per_driver": per_driver, "unmatched_sets": sorted(missing)}, indent=1) + "\n")
    lines = ["# FBNeo 对齐分析", "",
             f"FBNeo 街机+NeoGeo set：{len(fb)}；在当前 MAME 源码中找到同名 set：{len(fb) - len(missing)}；"
             f"未匹配：{len(missing)}（多为 FBNeo 独有的 hack/bootleg 或改名）。", "",
             f"涉及 MAME 驱动文件：{len(rows)} 个；独立增量之和 {sum(known) / 2**20:.1f} MiB"
             f"（上限估计，合并构建会小很多）；无增量数据 {len(rows) - len(known)} 个。", "",
             "| 驱动文件 | 增量 KiB | FBNeo set | FBNeo 主游戏 | MAME 可运行 | 示例 |", "|---|---:|---:|---:|---:|---|"]
    for drv, d in rows:
        delta = "—" if d["delta"] is None else f"{d['delta'] / 1024:.1f}"
        lines.append(f"| {drv} | {delta} | {d['sets']} | {d['parents']} | {d['working']} | "
                     f"{'; '.join(d['examples']).replace('|', '/')} |")
    lines += ["", "## FBNeo 有、MAME 同名未找到的 set", "", ", ".join(sorted(missing))]
    (SCAN / "fbneo_align.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines[:6]))


if __name__ == "__main__":
    main()
