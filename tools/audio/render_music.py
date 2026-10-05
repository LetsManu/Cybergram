#!/usr/bin/env python3
"""W21-A1: renders the adaptive music (synthwave / darksynth) to assets/audio/music/.

Each looping state is bar-exact and seamless (the reverb / delay spill past the
loop end is folded back onto the start). Match states are four stems
(pad, bass, drums, lead) that MusicDirector mixes by intensity; menu and pick
are single stereo mixes. Loudness: the full stem sum is normalised to
-20 LUFS integrated (music bus default 0.7 = -3.1 dB -> about -23 LUFS), the
same gain is applied to every stem so their balance holds. Deterministic.

    python3 tools/audio/render_music.py [--only <state>]
"""
from __future__ import annotations

import argparse
import sys
import zlib
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import dsp  # noqa: E402
from dsp import RATE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "audio" / "music"
TARGET_LUFS = -20.0
TAIL_S = 3.0


def midi(n: float) -> float:
    return 440.0 * 2 ** ((n - 69) / 12)


# state -> bpm, bars, root midi, minor-ish chord roots (semitones), mood knobs
STATES = {
    "menu": dict(bpm=88, bars=24, root=54, prog=[0, -4, -7, -2], stems=False, drive=0.0, hats=False, seed=1),
    "pick": dict(bpm=96, bars=24, root=48, prog=[0, 3, -4, -2], stems=False, drive=0.2, hats=True, seed=2),
    "match_early": dict(bpm=100, bars=32, root=45, prog=[0, -4, 3, -2], stems=True, drive=0.2, hats=True, seed=3),
    "match_late": dict(bpm=112, bars=32, root=50, prog=[0, -2, -4, -5], stems=True, drive=0.5, hats=True, seed=4),
    "sudden_death": dict(bpm=124, bars=32, root=52, prog=[0, 1, 0, -2], stems=True, drive=0.8, hats=True, seed=5),
}
MINOR = [0, 2, 3, 5, 7, 8, 10]
PHRYGIAN = [0, 1, 3, 5, 7, 8, 10]


class Track:
    def __init__(self, seconds: float, stereo: bool = True):
        n = int(RATE * (seconds + TAIL_S))
        self.buf = np.zeros((n, 2)) if stereo else np.zeros(n)

    def add(self, x: np.ndarray, start_s: float, gain: float = 1.0, pan: float = 0.0):
        i = int(RATE * start_s)
        if self.buf.ndim == 2 and x.ndim == 1:
            x = dsp.pan(x, pan)
        end = min(i + len(x), len(self.buf))
        if end > i:
            self.buf[i:end] += x[: end - i] * gain


def fold(x: np.ndarray, loop_s: float) -> np.ndarray:
    """Folds the spill past the loop end onto the start: seamless loop."""
    n = int(RATE * loop_s)
    out = x[:n].copy()
    spill = x[n:]
    out[: len(spill)] += spill
    return out


# -------------------------------------------------------------- voices
def kick(rng, punch=1.0):
    d = 0.45
    body = dsp.sweep(160 * punch, 45, d, "sine", 0.35) * dsp.env_exp(d, 7, 0.001)
    click = dsp.hp(dsp.noise(rng, 0.01), 2000) * dsp.env_exp(0.01, 400) * 0.3
    return dsp.drive(dsp.mix(body, click) * 1.3, 1.6)


def snare(rng, gated=True):
    d = 0.35
    tone = dsp.osc(185, d, "tri") * dsp.env_exp(d, 25, 0.001) * 0.5
    nz = dsp.bp(dsp.noise(rng, d), 1200, 9000) * dsp.env_exp(d, 14, 0.001)
    x = dsp.mix(tone, nz)
    if gated:  # 80s gated reverb
        wet = dsp.reverb(x, 0.9, 1.0, 6000, seed=7)[: int(RATE * 0.28)]
        wet = dsp.fade(wet, 0.0, 0.03)
        x = dsp.mix(x, wet * 0.6)
    return x


def hat(rng, open_=False):
    d = 0.25 if open_ else 0.05
    return dsp.hp(dsp.noise(rng, d), 7000) * dsp.env_exp(d, 10 if open_ else 70, 0.0005) * (0.5 if open_ else 0.35)


def pad_chord(notes, d, rng, cutoff=1800.0):
    x = sum(dsp.supersaw(midi(n), d, 5, 0.01, rng) for n in notes) / len(notes)
    x = dsp.lp(x, cutoff, 2) * dsp.env_adsr(d, d * 0.25, 0.3, 0.8, d * 0.3)
    return x


def bass_note(n, d, drive=0.0):
    f = midi(n)
    x = dsp.osc(f, d, "saw") * 0.6 + dsp.osc(f / 2, d, "square") * 0.3
    x = dsp.sweep_lp(x, 1400, 300, 8) * dsp.env_adsr(d, 0.004, d * 0.6, 0.6, 0.02)
    return dsp.drive(x * (1 + drive * 2), 1.0 + drive * 2)


def lead_note(n, d, rng):
    f = midi(n)
    x = dsp.fm(f, 2.0, 2.2 * dsp.env_exp(d, 6), d) * 0.6 + dsp.osc(f * 1.003, d, "saw") * 0.15
    return dsp.lp(x, 5000) * dsp.env_adsr(d, 0.01, 0.15, 0.55, min(0.08, d * 0.4))


def arp_note(n, d):
    f = midi(n)
    return dsp.fm(f, 1.0, 1.5 * dsp.env_exp(d, 18), d) * dsp.env_exp(d, 12, 0.002) * 0.5


# --------------------------------------------------------------- state
def render_state(name: str, cfg: dict) -> dict[str, np.ndarray]:
    rng = np.random.default_rng(zlib.crc32(name.encode()))
    beat = 60.0 / cfg["bpm"]
    bar = beat * 4
    bars = cfg["bars"]
    loop = bar * bars
    scale = PHRYGIAN if name == "sudden_death" else MINOR
    root = cfg["root"]
    pad, bass, drums, lead = (Track(loop) for _ in range(4))
    side = np.ones(len(pad.buf))  # sidechain pump from the kick
    k_snd, s_snd = kick(rng, 1.0 + cfg["drive"] * 0.2), snare(rng)
    for b in range(bars):
        chord_root = root + cfg["prog"][(b // 2) % len(cfg["prog"])]
        t0 = b * bar
        section = (b // 8) % 4  # A B A' C: arrangement so the loop breathes
        # pad: one chord per 2 bars
        if b % 2 == 0:
            notes = [chord_root + 12, chord_root + 15, chord_root + 19, chord_root + 24]
            cut = 1400 + 900 * (section == 1) + 400 * cfg["drive"]
            pad.add(dsp.widen(pad_chord(notes, bar * 2 + 0.6, rng, cut), 0.011), t0, 0.55)
        # bass: rolling eighths (menu: half notes)
        if name == "menu":
            for k in range(2):
                bass.add(bass_note(chord_root - 12, beat * 2 - 0.02), t0 + k * beat * 2, 0.6)
        else:
            for k in range(8):
                n = chord_root - 12 + (12 if k % 4 == 3 and cfg["drive"] > 0.4 else 0)
                bass.add(bass_note(n, beat / 2 - 0.01, cfg["drive"]), t0 + k * beat / 2, 0.55)
        # drums
        if name != "menu" and not (section == 3 and b % 8 >= 6):
            for k in range(4):
                tk = t0 + k * beat
                if k in (0, 2) or (cfg["drive"] > 0.4):
                    drums.add(k_snd, tk, 0.9)
                    i = int(RATE * tk)
                    m = min(int(RATE * beat), len(side) - i)
                    side[i:i + m] = np.minimum(side[i:i + m], 1 - 0.45 * np.exp(-np.arange(m) / RATE * 9))
                if k in (1, 3):
                    drums.add(s_snd, tk, 0.6)
            if cfg["hats"]:
                for k in range(8 if cfg["drive"] < 0.6 else 16):
                    step = bar / (8 if cfg["drive"] < 0.6 else 16)
                    drums.add(hat(rng, open_=(k % 4 == 2 and cfg["drive"] < 0.6)), t0 + k * step, 0.45 if k % 2 else 0.3,
                              pan=0.3 if k % 2 else -0.2)
        # lead: arp in sections A / A', melody in C; silent in B (breathing room)
        if section in (0, 2):
            tones = [0, 3, 7, 10, 12, 10, 7, 3] if scale is MINOR else [0, 1, 5, 7, 12, 7, 5, 1]
            for k in range(8):
                lead.add(arp_note(chord_root + 12 + tones[k], beat / 2), t0 + k * beat / 2, 0.35, pan=0.4 * ((k % 2) * 2 - 1))
        elif section == 3:
            mrng = np.random.default_rng(cfg["seed"] * 100 + b % 4)
            pos = 0.0
            while pos < 4 - 1e-6:
                ln = float(mrng.choice([0.5, 1.0, 1.5])) if pos + 0.5 < 4 else 0.5
                ln = min(ln, 4 - pos)
                deg = scale[int(mrng.integers(0, len(scale)))]
                lead.add(lead_note(root + 24 + deg, ln * beat * 0.95, rng), t0 + pos * beat, 0.4)
                pos += ln
    lead.buf = dsp.mix(lead.buf, dsp.delay(lead.buf, beat * 0.75, 0.4, 0.35, 4)[: len(lead.buf)])
    pad.buf *= side[:, None]
    bass.buf *= side[:, None]
    stems = {}
    for k, tr in (("pad", pad), ("bass", bass), ("drums", drums), ("lead", lead)):
        x = tr.buf
        if k == "pad":
            x = dsp.reverb(x, 2.5, 0.35, 5000, stereo=True, seed=11)
        elif k == "lead":
            x = dsp.reverb(x, 1.8, 0.3, 7000, stereo=True, seed=12)
        elif k == "drums":
            x = dsp.reverb(x, 0.8, 0.12, 6000, stereo=True, seed=13)
        x = x[: int(RATE * (loop + TAIL_S))]
        stems[k] = fold(x, loop)
    return stems, loop


def stinger(kind: str) -> np.ndarray:
    rng = np.random.default_rng(zlib.crc32(kind.encode()))
    if kind == "victory":
        notes = [[57, 60, 64, 69], [59, 62, 66, 71], [61, 64, 69, 73]]
        parts = [dsp.at(pad_chord(n, 1.6 if i < 2 else 3.0, rng, 3500), i * 0.55) for i, n in enumerate(notes)]
        x = dsp.mix(*parts, dsp.at(kick(rng) * 0.8, 1.1), dsp.at(snare(rng) * 0.5, 1.1))
    elif kind == "defeat":
        notes = [[57, 60, 64], [56, 59, 63], [53, 57, 60], [50, 53, 57]]
        parts = [dsp.at(pad_chord(n, 1.4 if i < 3 else 3.2, rng, 1500), i * 0.6) for i, n in enumerate(notes)]
        x = dsp.mix(*parts, dsp.at(kick(rng, 0.7) * 0.6, 1.8))
    elif kind == "phase":
        x = dsp.mix(dsp.sweep_lp(dsp.noise(rng, 1.2), 200, 6000) * dsp.env_adsr(1.2, 0.9, 0.05, 0.3, 0.25) * 0.4,
                    dsp.at(kick(rng) * 0.9, 0.95), dsp.at(pad_chord([57, 64, 69], 2.0, rng, 2500), 0.95))
    elif kind == "final":
        x = dsp.mix(*[dsp.at(bass_note(45 + (i % 2) * 3, 0.24, 0.6), i * 0.25) for i in range(8)],
                    dsp.at(pad_chord([57, 60, 63, 66], 2.4, rng, 2200), 0.0) * 0.8)
    else:  # sudden_death
        x = dsp.mix(dsp.sweep(55, 440, 1.5, "saw", 2.0) * dsp.env_adsr(1.5, 1.2, 0.05, 0.5, 0.2) * 0.3,
                    dsp.at(kick(rng, 1.3) * 1.2, 1.4), dsp.at(pad_chord([52, 53, 59, 64], 2.6, rng, 1800), 1.4))
    x = dsp.reverb(x if x.ndim == 2 else dsp.widen(x), 2.2, 0.3, 6000, stereo=True, seed=21)
    return dsp.trim_tail(x)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    for name, cfg in STATES.items():
        if a.only and a.only != name:
            continue
        stems, loop = render_state(name, cfg)
        full = sum(stems.values())
        gain = 10 ** ((TARGET_LUFS - dsp.integrated(full)) / 20)
        tp = dsp.true_peak_db(full * gain)
        if tp > -1.0:  # glue: soft-limit every stem by the same ceiling share
            gain *= 10 ** ((-1.0 - tp) / 20) ** 0.5
            stems = {k: dsp.soft_limit(v * gain, -2.0) / gain for k, v in stems.items()}
        if cfg["stems"]:
            for k, v in stems.items():
                mono = k in ("bass", "drums")
                y = v.mean(axis=1) if mono else v
                dsp.write_ogg(OUT / f"music_{name}_{k}_01.ogg", np.clip(y * gain, -1, 1), 1.0)
        else:
            dsp.write_ogg(OUT / f"music_{name}_mix_01.ogg", np.clip(full * gain, -1, 1), 2.0)
        print(f"{name}: loop {loop:.2f} s, {cfg['bpm']} bpm, {cfg['bars']} bars, "
              f"I {dsp.integrated(full * gain):.1f} LUFS, TP {dsp.true_peak_db(full * gain):.1f} dBTP")
    if not a.only or a.only == "stingers":
        for kind in ("victory", "defeat", "phase", "final", "sudden_death"):
            x = dsp.normalize(stinger(kind), -18.0, "I")
            dsp.write_ogg(OUT / f"music_stinger_{kind}_01.ogg", x, 3.0)
        print("stingers done")


if __name__ == "__main__":
    main()
