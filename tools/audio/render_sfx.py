#!/usr/bin/env python3
"""W21-A1: renders every catalog FILE to assets/audio/<folder>/<stem>_NN.ogg.

Deterministic: each file's RNG seed is crc32(stem) + variant. Loudness is
normalised to the catalog target (momentary max for one-shots, integrated for
beds) with a -1 dBTP ceiling. Usage (from the repo root):

    python3 tools/audio/render_sfx.py [--only <substring>] [--jobs N]
"""
from __future__ import annotations

import argparse
import sys
import zlib
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import catalog  # noqa: E402
import dsp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "audio"


def render_one(idx: int) -> list[str]:
    spec = catalog.FILES[idx]
    done = []
    for v in range(spec.variants):
        seed = zlib.crc32(spec.stem.encode()) + v
        rng = np.random.default_rng(seed)
        x = spec.recipe(rng, v, **spec.params)
        if spec.stereo and x.ndim == 1:
            x = dsp.widen(x, 0.008)
        if not spec.stereo and x.ndim == 2:
            x = x.mean(axis=1)
        x = dsp.fade(x, 0.0005, 0.005)
        x = dsp.normalize(x, spec.target, spec.mode)
        path = OUT / spec.folder / f"{spec.stem}_{v + 1:02d}.ogg"
        dsp.write_ogg(path, x, spec.quality)
        done.append(str(path.relative_to(ROOT)))
    return done


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--jobs", type=int, default=3)
    a = ap.parse_args()
    idx = [i for i, s in enumerate(catalog.FILES) if a.only in s.stem]
    with ProcessPoolExecutor(max_workers=a.jobs) as ex:
        n = sum(len(r) for r in ex.map(render_one, idx))
    print(f"rendered {n} files from {len(idx)} specs")


if __name__ == "__main__":
    main()
