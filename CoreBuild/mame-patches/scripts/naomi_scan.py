#!/usr/bin/env python3
"""Check whether Demul/Flycast NAOMI/Atomiswave dumps (.bin/.dat + .lst) can be split into MAME sets.

Each .lst maps one image file into the cartridge address space. For every MAME set in naomi.cpp and
dc_atomiswave.cpp, the "rom_board" ROM entries are cut out of that image (ROM_LOAD / ROM_LOAD32_WORD)
and compared by CRC32. Read-only: nothing is written except the report under build-ios/naomi_scan.
"""
import argparse
import json
import mmap
from pathlib import Path
import re
import zlib

from paths import OUTPUT, SOURCE

SEGA = SOURCE / "src/mame/sega"
OUT = OUTPUT / "naomi_scan"
LOAD = re.compile(r'^\s*(ROM_LOAD32_WORD|ROM_LOAD)\s*\(\s*"([^"]+)"\s*,\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*'
                  r'(0x[0-9a-fA-F]+|\d+)\s*,\s*(?:CRC\(([0-9a-fA-F]+)\)|NO_DUMP)')


def parse_sets():
    """Return {set: {"file": src, "parent": p, "board": [...], "other": [...], "disk": bool}}."""
    sets = {}
    for src in ("naomi.cpp", "dc_atomiswave.cpp"):
        text = (SEGA / src).read_text(errors="replace")
        parents = {}
        for line in re.findall(r"^\s*GAMEL?\s*\((.*)$", text, re.M):
            f = [x.strip() for x in line.split(",")]
            parents[f[1]] = f[2]
        for name, body in re.findall(r"ROM_START\(\s*(\w+)\s*\)(.*?)ROM_END", text, re.S):
            region, board, other = None, [], []
            for line in body.splitlines():
                m = re.search(r'ROM_REGION\w*\(\s*[^,]+,\s*"([^"]+)"', line)
                if m:
                    region = m.group(1)
                    continue
                m = LOAD.match(line)
                if not m or m.group(5) is None:
                    continue
                entry = {"method": m.group(1), "name": m.group(2), "offset": int(m.group(3), 0),
                         "size": int(m.group(4), 0), "crc": m.group(5).lower()}
                (board if region == "rom_board" else other).append(dict(entry, region=region))
            sets[name] = {"file": src, "parent": parents.get(name, "?"), "board": board, "other": other,
                          "disk": "DISK_IMAGE" in body}
    return sets


def extract_crc(image, method, offset, size):
    if method == "ROM_LOAD":
        if offset + size > len(image):
            return None
        return format(zlib.crc32(image[offset:offset + size]), "08x")
    # ROM_LOAD32_WORD: 16-bit words placed every 4 bytes starting at offset.
    if offset + size * 2 > len(image):
        return None
    crc, step = 0, 4 * 0x40000
    for pos in range(offset, offset + size * 2, step):
        chunk = image[pos:min(pos + step, offset + size * 2)]
        data = b"".join(chunk[i:i + 2] for i in range(0, len(chunk), 4))
        crc = zlib.crc32(data, crc)
    return format(crc, "08x")


def read_lst(path):
    entries = []
    for line in path.read_text(errors="replace").splitlines():
        m = re.match(r'\s*"([^"]+)"\s*,\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*(0x[0-9a-fA-F]+|\d+)', line)
        if m:
            entries.append((m.group(1), int(m.group(2), 0), int(m.group(3), 0)))
    return entries


def scan_game(folder, sets):
    lst = next(iter(sorted(folder.glob("*.lst"))), None)
    if not lst:
        return {"status": "无 .lst"}
    entries = read_lst(lst)
    files = {p.name.lower(): p for p in folder.iterdir()}
    if len(entries) != 1 or entries[0][1] != 0 or entries[0][0].lower() not in files:
        return {"status": "不支持的 .lst", "lst": [e[0] for e in entries]}
    path = files[entries[0][0].lower()]
    result = {"image": path.name, "image_bytes": path.stat().st_size}
    with path.open("rb") as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as image:
        cache, best = {}, None
        for name, s in sets.items():
            if not s["board"]:
                continue
            ok = 0
            for i, e in enumerate(s["board"]):
                key = (e["method"], e["offset"], e["size"])
                if key not in cache:
                    cache[key] = extract_crc(image, *key)
                if cache[key] == e["crc"]:
                    ok += 1
                elif i == 0:
                    break  # cheap reject: the first chip must match
            if ok and (best is None or ok / len(s["board"]) > best[1] / best[2]):
                best = (name, ok, len(s["board"]))
    if not best:
        result["status"] = "无匹配（可能是解密版、GD-ROM 镜像或不同版本）"
        return result
    name, ok, total = best
    s = sets[name]
    result.update(set=name, source=s["file"], parent=s["parent"], matched=ok, total=total,
                  extra_files=[f'{e["region"]}:{e["name"]}' for e in s["other"]], needs_disk=s["disk"])
    result["status"] = "可转换" if ok == total else "部分匹配"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path, help="folder of Demul/Flycast dumps (.lst + .bin/.dat)")
    args = parser.parse_args()
    sets = parse_sets()
    OUT.mkdir(parents=True, exist_ok=True)
    report = {}
    for game in sorted(p for p in args.folder.iterdir() if p.is_dir()):
        report[game.name] = scan_game(game, sets)
        r = report[game.name]
        print(f"{game.name}: {r['status']} {r.get('set', '')} {r.get('matched', '')}/{r.get('total', '')}", flush=True)
    (OUT / "naomi_scan.json").write_text(json.dumps(report, indent=1, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
