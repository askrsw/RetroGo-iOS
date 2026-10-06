#!/usr/bin/env python3
"""Pick an arcade driver set from the scan results: drop gambling/fruit machines, PC-based
hardware and drivers without working games. Writes drivers.txt (read by build.py) plus build-ios/scan/selection.json and selection.md.

Heuristics only (source text + measured size); review selection.md before shipping.
"""
import json
from pathlib import Path
import re

from paths import DRIVERS, SCAN, SOURCE

SRC = SOURCE / "src/mame"
# Drivers already shipped to users; always kept.
KEEP = ["capcom/cps1.cpp", "capcom/cps2.cpp", "snk/neogeo.cpp", "igs/pgm.cpp", "igs/pgm2.cpp",
        "promat/1945kiii.cpp", "psikyo/psikyosh.cpp", "seta/downtown.cpp", "jaleco/megasys1.cpp",
        "vsystem/aerofgt.cpp", "irem/m72.cpp", "atlus/cave.cpp",
        # Cave CV1000: cv1k_v blitters (ep1c12 before 0.289) live in src/mame, so SOURCES= dependency scanning misses them.
        "cave/cv1k.cpp"] + [f"cave/cv1k_v_blit{i}.cpp" for i in range(9)] + [
        # Atomiswave: dc_state::naomi_aw_base() is defined in naomi.cpp (pulls in NAOMI sets too).
        "sega/dc_atomiswave.cpp", "sega/dc.cpp", "sega/naomi.cpp",
        # Hard/Race Drivin': classic; 0.289 pushed its standalone delta over PC_BYTES.
        "atari/harddriv.cpp",
        # Classics whose standalone delta exceeds PC_BYTES mostly through shared netlist/devices.
        "galaxian/galaxian.cpp", "nintendo/mario.cpp", "sega/vicdual.cpp", "sega/segag80r.cpp",
        "sega/segag80v.cpp", "jaleco/tetrisp2.cpp", "seta/seta2.cpp"]
# Manufacturers whose MAME drivers are (almost) all slot, fruit, poker or pinball machines.
GAMBLING_DIRS = {"aristocrat", "barcrest", "bfm", "igt", "jpm", "maygay", "cirsa", "astrocorp", "subsino",
                 "funworld", "recfranco", "pinball", "ainsworth", "novomatic", "sigma"}
PC_DIRS = {"pc"}
PC_BYTES = 4 * 2**20  # drivers pulling a whole x86/PCI/Amiga platform land far above this
GAMBLING_WORDS = re.compile(r"poker|slot|bingo|casino|fruit|roulette|black ?jack|keno|lotto|pachi|"
                            r"gambl|cherry|bonus|jackpot|reel|medal|amusement with prize|\bawp\b|"
                            r"skill with prize|\bswp\b|video lottery|\bvlt\b", re.I)


def descriptions(text):
    out = []
    for line in re.findall(r"^\s*GAMEL?\s*\((.*)$", text, re.M):
        if "NOT_WORKING" in line or "IS_BIOS_ROOT" in line:
            continue
        quoted = re.findall(r'"([^"]*)"', line)
        out.append((quoted[1] if len(quoted) > 1 else "", "MECHANICAL" in line))
    return out


def classify(meta, result):
    driver = meta["driver"]
    if driver in KEEP:
        return None
    if "delta" not in result:
        return "构建失败"
    if meta["working_parents"] == 0:
        return "无可运行游戏"
    top = driver.split("/")[0]
    if top in PC_DIRS or result["delta"] > PC_BYTES:
        return "PC/大平台"
    if top in GAMBLING_DIRS:
        return "博彩/水果/弹珠厂商"
    text = (SRC / driver).read_text(errors="replace")
    games = descriptions(text)
    header = text[:4000]
    hits = sum(bool(GAMBLING_WORDS.search(d)) or mech for d, mech in games)
    if games and hits * 2 >= len(games):
        return "博彩（游戏名）"
    if re.search(r"slot machine|fruit machine|gambling|casino|poker machine|video slot|pachi-?slot", header, re.I):
        return "博彩（源码说明）"
    return None


def main():
    drivers = json.loads((SCAN / "drivers.json").read_text())
    results = {json.loads(l)["driver"]: json.loads(l) for l in (SCAN / "results.jsonl").read_text().splitlines()}
    keep, dropped = list(KEEP), {}
    for meta in drivers:
        if not meta["arcade"] or meta["driver"] in KEEP:
            continue
        reason = classify(meta, results.get(meta["driver"], {}))
        if reason:
            dropped.setdefault(reason, []).append(meta["driver"])
        else:
            keep.append(meta["driver"])
    kept_meta = {d["driver"]: d for d in drivers}
    est = sum(results.get(d, {}).get("delta", 0) for d in keep if d not in KEEP[:4])
    (SCAN / "selection.json").write_text(json.dumps({"drivers": keep, "dropped": dropped}, indent=1) + "\n")
    header = DRIVERS.read_text().splitlines()[:2] if DRIVERS.exists() else []
    DRIVERS.write_text("\n".join([l for l in header if l.startswith("#")] + keep) + "\n")
    lines = ["# 街机驱动选择（排除博彩/水果/PC）", "",
             f"保留 {len(keep)} 个驱动文件，可运行主游戏约 "
             f"{sum(kept_meta.get(d, {}).get('working_parents', 0) for d in keep)} 个；独立增量之和 {est / 2**20:.1f} MiB（上限估计）。", ""]
    for reason, items in dropped.items():
        lines.append(f"- 排除·{reason}：{len(items)} 个")
    lines += ["", "## 保留清单", ""] + [f"- {d}" for d in keep]
    for reason, items in dropped.items():
        lines += ["", f"## 排除·{reason}", ""] + [f"- {d}" for d in items]
    (SCAN / "selection.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines[:10]))


if __name__ == "__main__":
    main()
