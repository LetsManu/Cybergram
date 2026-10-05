#!/usr/bin/env python3
"""W21-A1: measures every assets/audio/**/*.ogg with ffmpeg ebur128 (an
implementation independent of dsp.py). One-shots are padded with 0.5 s of
silence so the 400 ms momentary window covers them. Prints a TSV per file,
then a per-category summary (stdout). Usage:

    python3 tools/audio/measure_loudness.py [--summary]
"""
from __future__ import annotations

import argparse
import re
import subprocess
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUDIO = ROOT / "assets" / "audio"


def measure(path: Path) -> tuple[float, float, float]:
    cmd = ["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "apad=pad_dur=0.5,ebur128=peak=true",
           "-f", "null", "-"]
    out = subprocess.run(cmd, capture_output=True, text=True).stderr
    ms = [float(m) for m in re.findall(r"M:\s*(-?[0-9.]+)", out)]
    i = re.search(r"I:\s*(-?[0-9.]+) LUFS", out.split("Summary:")[-1])
    tp = re.search(r"Peak:\s*(-?[0-9.]+) dBFS", out.split("Summary:")[-1])
    return (max(ms) if ms else -120.0, float(i.group(1)) if i else -120.0, float(tp.group(1)) if tp else -120.0)


def category(rel: Path) -> str:
    stem = rel.stem
    if rel.parts[0] == "abilities":
        return "abilities/" + ("ult cast" if any(u in stem for u in ("earthbreaker_cast", "zero_day_cast", "killbox_cast",
                                                                       "aurora_cast", "overdrive_cast", "eclipse_step_cast",
                                                                       "rewrite_cast")) else
                               "loop" if "_loop" in stem else "cast/impact")
    if rel.parts[0] == "weapons":
        for k in ("_shot_", "_tail_", "_reload_", "_combat_", "_impact_", "_core_layer_"):
            if k in stem:
                return "weapons" + k.rstrip("_")
        return "weapons/other"
    if rel.parts[0] == "music":
        return "music/stinger" if "stinger" in stem else "music/loop stem"
    return rel.parts[0]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary", action="store_true")
    a = ap.parse_args()
    rows = []
    for p in sorted(AUDIO.rglob("*.ogg")):
        rel = p.relative_to(AUDIO)
        m, i, tp = measure(p)
        rows.append((rel, category(rel), m, i, tp))
    if not a.summary:
        print("file\tcategory\tM_max_LUFS\tI_LUFS\tpeak_dBTP")
        for r in rows:
            print(f"{r[0]}\t{r[1]}\t{r[2]:.1f}\t{r[3]:.1f}\t{r[4]:.1f}")
    agg = defaultdict(list)
    for r in rows:
        agg[r[1]].append(r)
    print("\ncategory\tfiles\tM_max (min..max)\tI (median)\tpeak max")
    for c in sorted(agg):
        rs = agg[c]
        ms = sorted(r[2] for r in rs)
        iss = sorted(r[3] for r in rs)
        print(f"{c}\t{len(rs)}\t{ms[0]:.1f}..{ms[-1]:.1f}\t{iss[len(iss) // 2]:.1f}\t{max(r[4] for r in rs):.1f}")


if __name__ == "__main__":
    main()
