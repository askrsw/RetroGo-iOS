#!/usr/bin/env python3
"""Measure the size cost of each MAME driver file, one at a time, on top of a fixed baseline.

Method: independent increments. Every build is baseline + exactly one extra driver file, so each
delta is order-independent and reproducible. Shared devices (CPUs, sound chips) are counted in
every driver that pulls them in, so the sum of deltas over-estimates a combined build.

Nothing here touches RetroGo/ or the packaged framework; products are measured and discarded.

    python3 CoreBuild/mame-patches/scripts/driver_scan.py list            # enumerate drivers -> build-ios/scan/drivers.json
    python3 CoreBuild/mame-patches/scripts/driver_scan.py baseline
    python3 CoreBuild/mame-patches/scripts/driver_scan.py run [--all] [--limit N]
    python3 CoreBuild/mame-patches/scripts/driver_scan.py report
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

from paths import EXPORTS, OUTPUT, SCAN as OUT, SOURCE
BASELINE = ["capcom/cps1.cpp", "capcom/cps2.cpp", "snk/neogeo.cpp", "igs/pgm.cpp"]
SUBTARGET = "rgscan"
MACRO = re.compile(r"^\s*(GAMEL?|SYST|CONS|COMP)\s*\(", re.M)


def enumerate_drivers():
    drivers = []
    for path in sorted((SOURCE / "src/mame").rglob("*.cpp")):
        text = path.read_text(errors="replace")
        kinds = {}
        for m in MACRO.finditer(text):
            kind = "GAME" if m.group(1).startswith("GAME") else m.group(1)
            kinds[kind] = kinds.get(kind, 0) + 1
        if kinds:
            rel = str(path.relative_to(SOURCE / "src/mame"))
            drivers.append(dict({"driver": rel, "arcade": "GAME" in kinds, "sets": kinds}, **count_working(text)))
    return drivers


def count_working(text):
    """Working sets = GAME entries without MACHINE_NOT_WORKING or BIOS root; parents = distinct games."""
    working = parents = 0
    for line in re.findall(r"^\s*GAMEL?\s*\((.*)$", text, re.M):
        if "NOT_WORKING" in line or "IS_BIOS_ROOT" in line:
            continue
        fields = [f.strip() for f in line.split(",")]
        working += 1
        parents += len(fields) > 2 and fields[2] == "0"
    return {"working": working, "working_parents": parents}


def build(extra, jobs):
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
    shutil.rmtree(SOURCE / f"build/libretro/bin/mame_{SUBTARGET}", ignore_errors=True)
    product = SOURCE / f"{SUBTARGET}_libretro_ios.dylib"
    product.unlink(missing_ok=True)
    drivers = BASELINE + ([extra] if extra else [])
    command = ["make", "-f", "Makefile.libretro", f"-j{jobs}", "platform=ios-arm64", f"SUBTARGET={SUBTARGET}",
               "SOURCES=" + ",".join("src/mame/" + d for d in drivers),
               "ARCHOPTS=-target arm64-apple-ios15.0 -isysroot " + sdk + " -miphoneos-version-min=15.0 -arch arm64",
               "REGENIE=1", "SYMBOLS=0", "STRIP_SYMBOLS=0", "VERBOSE=0", "FORCE_DRC_C_BACKEND=1",
               "PYTHON_EXECUTABLE=" + sys.executable,
               "LDOPTS=-Wl,-dead_strip -Wl,-exported_symbols_list," + str(EXPORTS)]
    env = dict(os.environ, LC_ALL="C", CLANG_MODULE_CACHE_PATH=str(OUTPUT / "module-cache"))
    start = time.time()
    result = subprocess.run(command, cwd=SOURCE, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    entry = {"driver": extra, "exit": result.returncode, "seconds": round(time.time() - start, 1)}
    m = re.search(r"(\d+) driver\(s\) found", result.stdout)
    entry["sets"] = int(m.group(1)) if m else None
    if result.returncode == 0 and product.is_file():
        stripped = OUT / "stripped.dylib"
        shutil.copy2(product, stripped)
        subprocess.check_call(["xcrun", "strip", "-S", "-x", str(stripped)])
        entry["bytes"] = stripped.stat().st_size
        stripped.unlink()
        product.unlink()
    else:
        errors = [l for l in result.stdout.splitlines() if "error" in l.lower()]
        entry["error"] = "\n".join(errors[:5]) or result.stdout[-1500:]
    return entry


def load_results():
    path = OUT / "results.jsonl"
    if not path.exists():
        return {}
    return {e["driver"]: e for e in map(json.loads, path.read_text().splitlines()) if e.get("driver")}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("action", choices=["list", "baseline", "run", "report"])
    parser.add_argument("--all", action="store_true", help="include non-arcade (SYST/CONS/COMP) drivers")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--jobs", type=int, default=os.cpu_count())
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    if args.action == "list":
        drivers = enumerate_drivers()
        (OUT / "drivers.json").write_text(json.dumps(drivers, indent=1) + "\n")
        print(f"{len(drivers)} driver files, {sum(d['arcade'] for d in drivers)} arcade")
        return 0
    if args.action == "baseline":
        entry = build(None, args.jobs)
        (OUT / "baseline.json").write_text(json.dumps(dict(entry, drivers=BASELINE), indent=2) + "\n")
        print(entry)
        return entry["exit"]
    if args.action == "report":
        return report()

    base = json.loads((OUT / "baseline.json").read_text())
    done = load_results()
    todo = [d["driver"] for d in json.loads((OUT / "drivers.json").read_text())
            if (args.all or d["arcade"]) and d["driver"] not in done and d["driver"] not in BASELINE]
    for i, driver in enumerate(todo[:args.limit]):
        entry = build(driver, args.jobs)
        if "bytes" in entry:
            entry["delta"] = entry["bytes"] - base["bytes"]
        with (OUT / "results.jsonl").open("a") as f:
            f.write(json.dumps(entry) + "\n")
        print(f"[{i + 1}/{len(todo)}] {driver}: {entry.get('delta', 'FAIL')} ({entry['seconds']}s)", flush=True)
    return 0


def report():
    base = json.loads((OUT / "baseline.json").read_text())
    meta = {d["driver"]: d for d in json.loads((OUT / "drivers.json").read_text())}
    results = sorted(load_results().values(), key=lambda e: -e.get("delta", -1))
    ok = [e for e in results if "delta" in e]
    lines = ["# MAME 单驱动增量测试", "",
             f"基准：{', '.join(base['drivers'])}；剥离后 {base['bytes']:,} 字节"
             f"（{base['bytes'] / 2**20:.2f} MiB），{base['sets']} 个 set。", "",
             "方法：每次 = 基准 + 1 个驱动文件（独立增量），限制导出 + dead_strip + strip -S -x。"
             "共享 CPU/音源设备在每个用到它的驱动里都会计入，因此多个驱动增量之和大于合并构建的实际增量。", "",
             f"成功 {len(ok)}，失败 {len(results) - len(ok)}。", "",
             "性价比 = 增量 KiB ÷ 可运行主游戏数（parent=0、无 MACHINE_NOT_WORKING、非 BIOS），越小越划算。"
             "set 数来自源码静态统计，未经真机验证。", "",
             "## 有可运行游戏的驱动（按性价比排序）", "",
             "| 驱动文件 | 增量 KiB | 可运行主游戏 | 可运行 set | 全部 set | KiB/主游戏 |", "|---|---:|---:|---:|---:|---:|"]
    def info(e):
        d = meta.get(e["driver"], {})
        return d.get("working", 0), d.get("working_parents", 0), (e["sets"] or 0) - base["sets"]
    useful = sorted((e for e in ok if info(e)[1]), key=lambda e: e["delta"] / info(e)[1])
    for e in useful:
        w, p, n = info(e)
        lines.append(f"| {e['driver']} | {e['delta'] / 1024:.1f} | {p} | {w} | {n} | {e['delta'] / 1024 / p:.1f} |")
    dead = [e for e in ok if not info(e)[1]]
    lines += ["", f"## 无可运行主游戏的驱动（{len(dead)} 个，按增量排序）", "",
              "| 驱动文件 | 增量 KiB | 可运行 set | 全部 set |", "|---|---:|---:|---:|"]
    for e in dead:
        w, p, n = info(e)
        lines.append(f"| {e['driver']} | {e['delta'] / 1024:.1f} | {w} | {n} |")
    failed = [e for e in results if "delta" not in e]
    if failed:
        lines += ["", "## 构建失败", ""] + [f"- {e['driver']}: `{e['error'].splitlines()[0][:200] if e['error'] else ''}`"
                                         for e in failed]
    (OUT / "report.md").write_text("\n".join(lines) + "\n")
    with (OUT / "report.csv").open("w") as f:
        f.write("driver,arcade,delta_bytes,new_sets,working_sets,working_parents,seconds,exit\n")
        for e in results:
            f.write(f"{e['driver']},{meta.get(e['driver'], {}).get('arcade')},{e.get('delta', '')},"
                    f"{(e['sets'] or 0) - base['sets'] if e.get('sets') else ''},"
                    f"{meta.get(e['driver'], {}).get('working', '')},{meta.get(e['driver'], {}).get('working_parents', '')},{e['seconds']},{e['exit']}\n")
    print(f"{len(ok)} ok, {len(failed)} failed -> {OUT / 'report.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
