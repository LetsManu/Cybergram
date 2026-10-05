"""W21-A1 offline DSP primitives for the Cybergram sound generators.

Everything here is deterministic: callers pass a numpy Generator built from a
fixed seed. Signals are float64 numpy arrays at RATE (44.1 kHz); mono = 1-D,
stereo = shape (n, 2). The output of these generators is our own work (CC0).
"""
from __future__ import annotations

import math
import subprocess
from pathlib import Path

import numpy as np
import pyloudnorm as pyln
from scipy import signal

RATE = 44100


# ---------------------------------------------------------------- basics
def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(RATE * seconds)) / RATE


def silence(seconds: float) -> np.ndarray:
    return np.zeros(int(RATE * seconds))


def noise(rng: np.random.Generator, seconds: float) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, int(RATE * seconds))


def env_exp(seconds: float, decay: float, attack: float = 0.001) -> np.ndarray:
    """Exponential decay (1/s) with a linear attack of `attack` seconds."""
    t = t_axis(seconds)
    a = np.clip(t / max(attack, 1e-5), 0.0, 1.0)
    return a * np.exp(-t * decay)


def env_adsr(seconds: float, a: float, d: float, s: float, r: float) -> np.ndarray:
    n = int(RATE * seconds)
    t = np.arange(n) / RATE
    e = np.ones(n) * s
    e[t < a] = t[t < a] / max(a, 1e-5)
    m = (t >= a) & (t < a + d)
    e[m] = 1.0 - (1.0 - s) * (t[m] - a) / max(d, 1e-5)
    rel_start = seconds - r
    m = t >= rel_start
    e[m] *= np.clip(1.0 - (t[m] - rel_start) / max(r, 1e-5), 0.0, 1.0)
    return e


def osc(freq, seconds: float, shape: str = "sine", phase: float = 0.0) -> np.ndarray:
    """Oscillator; `freq` is a scalar or a per-sample array (Hz)."""
    n = int(RATE * seconds)
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    ph = phase + np.cumsum(f) / RATE
    x = ph % 1.0
    if shape == "sine":
        return np.sin(2 * np.pi * ph)
    if shape == "saw":
        return 2.0 * x - 1.0
    if shape == "square":
        return np.where(x < 0.5, 1.0, -1.0)
    if shape == "tri":
        return 4.0 * np.abs(x - 0.5) - 1.0
    raise ValueError(shape)


def supersaw(freq: float, seconds: float, voices: int = 5, detune: float = 0.012,
             rng: np.random.Generator | None = None) -> np.ndarray:
    out = np.zeros(int(RATE * seconds))
    for k in range(voices):
        d = (k - (voices - 1) / 2) / max(voices - 1, 1) * 2 * detune
        ph = rng.uniform() if rng is not None else k / voices
        out += osc(freq * (1 + d), seconds, "saw", ph)
    return out / voices


def fm(carrier: float, ratio: float, index, seconds: float) -> np.ndarray:
    """Two-operator FM: index may be an envelope array."""
    t = t_axis(seconds)
    idx = np.broadcast_to(np.asarray(index, dtype=float), t.shape)
    mod = np.sin(2 * np.pi * carrier * ratio * t)
    return np.sin(2 * np.pi * carrier * t + idx * mod)


def sweep(f0: float, f1: float, seconds: float, shape: str = "sine", curve: float = 1.0) -> np.ndarray:
    u = np.linspace(0, 1, int(RATE * seconds), endpoint=False) ** curve
    return osc(f0 * (f1 / f0) ** u, seconds, shape)


# --------------------------------------------------------------- filters
def _sos(kind: str, freq, order: int = 2):
    nyq = RATE / 2
    if isinstance(freq, (tuple, list)):
        wn = [min(max(f / nyq, 1e-4), 0.999) for f in freq]
    else:
        wn = min(max(freq / nyq, 1e-4), 0.999)
    return signal.butter(order, wn, btype=kind, output="sos")


def lp(x: np.ndarray, freq: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(_sos("lowpass", freq, order), x, axis=0)


def hp(x: np.ndarray, freq: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(_sos("highpass", freq, order), x, axis=0)


def bp(x: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(_sos("bandpass", (lo, hi), order), x, axis=0)


def peak_eq(x: np.ndarray, freq: float, gain_db: float, q: float = 1.0) -> np.ndarray:
    a = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * freq / RATE
    alpha = np.sin(w0) / (2 * q)
    b = [1 + alpha * a, -2 * np.cos(w0), 1 - alpha * a]
    den = [1 + alpha / a, -2 * np.cos(w0), 1 - alpha / a]
    return signal.lfilter(b, den, x, axis=0)


def sweep_lp(x: np.ndarray, f0: float, f1: float, blocks: int = 64) -> np.ndarray:
    """Time-varying one-pole low-pass (exponential cutoff sweep), block-wise."""
    out = np.zeros_like(x)
    n = len(x)
    z = 0.0
    edges = np.linspace(0, n, blocks + 1).astype(int)
    for b in range(blocks):
        f = f0 * (f1 / f0) ** (b / max(blocks - 1, 1))
        k = 1 - math.exp(-2 * math.pi * f / RATE)
        seg = x[edges[b]:edges[b + 1]]
        y, zf = signal.lfilter([k], [1, -(1 - k)], seg, zi=[z * (1 - k)])
        out[edges[b]:edges[b + 1]] = y
        z = y[-1] if len(y) else z
    return out


def bitcrush(x: np.ndarray, bits: int, hold: int) -> np.ndarray:
    q = 2 ** (bits - 1)
    y = np.round(x * q) / q
    if hold > 1:
        idx = (np.arange(len(y)) // hold) * hold
        y = y[np.minimum(idx, len(y) - 1)]
    return y


def drive(x: np.ndarray, amount: float) -> np.ndarray:
    return np.tanh(x * amount) / np.tanh(amount)


def karplus(freq: float, seconds: float, rng: np.random.Generator, damp: float = 0.996,
            bright: float = 0.5) -> np.ndarray:
    """Karplus-Strong plucked string (vectorised per period)."""
    n = int(RATE * seconds)
    p = max(int(RATE / freq), 2)
    buf = rng.uniform(-1, 1, p)
    buf = lp(buf, 2000 + 8000 * bright, 1)
    out = np.zeros(n)
    i = 0
    while i < n:
        m = min(p, n - i)
        out[i:i + m] = buf[:m]
        nxt = damp * 0.5 * (buf + np.roll(buf, -1))
        buf = nxt
        i += p
    return out


# ---------------------------------------------------------------- space
def reverb(x: np.ndarray, seconds: float = 1.2, mix: float = 0.25, damp: float = 6000.0,
           predelay: float = 0.01, stereo: bool = False, seed: int = 1) -> np.ndarray:
    """Convolution with a synthetic exponentially decaying noise tail."""
    rng = np.random.default_rng(seed)
    n = int(RATE * seconds)
    t = np.arange(n) / RATE
    decay = np.exp(-t * 6.9 / seconds)
    chans = 2 if stereo else 1
    irs = []
    for _ in range(chans):
        ir = rng.standard_normal(n) * decay
        ir = lp(ir, damp, 1)
        ir = np.concatenate([np.zeros(int(RATE * predelay)), ir])
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
        irs.append(ir)
    if x.ndim == 1 and not stereo:
        wet = signal.fftconvolve(x, irs[0])[: len(x) + len(irs[0]) - 1]
        dry = np.concatenate([x, np.zeros(len(wet) - len(x))])
        return dry * (1 - mix) + wet * mix
    src = x if x.ndim == 2 else np.stack([x, x], axis=1)
    outs = []
    for c in range(2):
        wet = signal.fftconvolve(src[:, c], irs[c % chans])
        dry = np.concatenate([src[:, c], np.zeros(len(wet) - len(src))])
        outs.append(dry * (1 - mix) + wet * mix)
    return np.stack(outs, axis=1)


def delay(x: np.ndarray, seconds: float, feedback: float = 0.35, mix: float = 0.3, taps: int = 6) -> np.ndarray:
    d = int(RATE * seconds)
    out = np.concatenate([x, np.zeros((d * taps,) + x.shape[1:])])
    for k in range(1, taps + 1):
        out[d * k: d * k + len(x)] += x * mix * feedback ** (k - 1)
    return out


def pan(x: np.ndarray, p: float) -> np.ndarray:
    """Equal-power pan, p in [-1, 1]."""
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


def widen(x: np.ndarray, ms: float = 0.012, seed: int = 3) -> np.ndarray:
    """Mono -> stereo with a short Haas offset and decorrelated tail."""
    d = int(RATE * ms)
    left = np.concatenate([x, np.zeros(d)])
    right = np.concatenate([np.zeros(d), x])
    return np.stack([left, right], axis=1) * 0.8


def mix(*parts) -> np.ndarray:
    """Sums arrays of different lengths (pads with zeros); mono+stereo -> stereo."""
    stereo = any(p.ndim == 2 for p in parts)
    n = max(len(p) for p in parts)
    out = np.zeros((n, 2)) if stereo else np.zeros(n)
    for p in parts:
        if stereo and p.ndim == 1:
            p = np.stack([p, p], axis=1) * 0.7071
        out[: len(p)] += p
    return out


def at(x: np.ndarray, offset_s: float) -> np.ndarray:
    pad = np.zeros((int(RATE * offset_s),) + x.shape[1:])
    return np.concatenate([pad, x])


def fade(x: np.ndarray, fin: float = 0.002, fout: float = 0.01) -> np.ndarray:
    n = len(x)
    e = np.ones(n)
    a = min(int(RATE * fin), n)
    b = min(int(RATE * fout), n)
    if a:
        e[:a] = np.linspace(0, 1, a)
    if b:
        e[n - b:] *= np.linspace(1, 0, b)
    return x * (e[:, None] if x.ndim == 2 else e)


def trim_tail(x: np.ndarray, floor_db: float = -70.0) -> np.ndarray:
    mag = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=1)
    thr = np.max(mag) * 10 ** (floor_db / 20)
    idx = np.nonzero(mag > thr)[0]
    if len(idx) == 0:
        return x
    return fade(x[: idx[-1] + int(RATE * 0.01)], 0.0, 0.01)


def loopable(x: np.ndarray, xfade_s: float = 1.0) -> np.ndarray:
    """Cross-fades the tail over the head so the result loops seamlessly."""
    k = int(RATE * xfade_s)
    head = x[:k]
    tail = x[-k:]
    ramp = np.linspace(0, 1, k)
    if x.ndim == 2:
        ramp = ramp[:, None]
    body = x[k:-k].copy() if len(x) > 2 * k else x[k:].copy()
    joined = tail * (1 - ramp) + head * ramp
    return np.concatenate([joined, body]) if len(x) > 2 * k else x


# ------------------------------------------------------------- loudness
def _meter():
    return pyln.Meter(RATE)


def k_weight(x: np.ndarray) -> np.ndarray:
    m = _meter()
    y = x if x.ndim == 2 else x[:, None]
    for f in m._filters.values():
        y = f.apply_filter(y)
    return y


def momentary_max(x: np.ndarray) -> float:
    """Max momentary loudness (400 ms window, 100 ms hop), LUFS."""
    pad = np.zeros((int(RATE * 0.4),) + x.shape[1:])
    y = k_weight(np.concatenate([x, pad]))
    p = np.sum(y ** 2, axis=1)
    w = int(RATE * 0.4)
    c = np.concatenate([[0.0], np.cumsum(p)])
    hop = int(RATE * 0.01)
    sums = (c[w::hop] - c[: len(c) - w:hop])[: max((len(p) - w) // hop + 1, 1)]
    ms = np.max(sums) / w
    return -0.691 + 10 * math.log10(max(ms, 1e-12))


def integrated(x: np.ndarray) -> float:
    return float(_meter().integrated_loudness(x if len(x) > RATE * 0.5 else np.concatenate([x, x, x])))


def true_peak_db(x: np.ndarray) -> float:
    up = signal.resample_poly(x, 4, 1, axis=0)
    return 20 * math.log10(max(np.max(np.abs(up)), 1e-9))


def soft_limit(x: np.ndarray, ceiling_db: float = -1.2) -> np.ndarray:
    c = 10 ** (ceiling_db / 20)
    return np.tanh(x / c) * c


def normalize(x: np.ndarray, target: float, mode: str = "M", tp_ceiling: float = -1.0) -> np.ndarray:
    """Gain to `target` LUFS (M = momentary max, I = integrated) with a true-peak ceiling."""
    measure = momentary_max if mode == "M" else integrated
    y = x / (np.max(np.abs(x)) + 1e-9) * 0.5
    for _ in range(6):
        y = y * 10 ** ((target - measure(y)) / 20)
        if true_peak_db(y) > tp_ceiling:
            y = soft_limit(y, tp_ceiling - 0.4)
        if abs(measure(y) - target) < 0.3 and true_peak_db(y) <= tp_ceiling + 0.05:
            break
    if true_peak_db(y) > tp_ceiling:
        y *= 10 ** ((tp_ceiling - 0.1 - true_peak_db(y)) / 20)
    return y


# ------------------------------------------------------------------ io
def write_ogg(path: Path, x: np.ndarray, quality: float = 4.0) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    chans = 2 if x.ndim == 2 else 1
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(RATE), "-ac", str(chans),
           "-i", "pipe:0", "-c:a", "libvorbis", "-q:a", str(quality),
           "-fflags", "+bitexact", "-flags:a", "+bitexact", "-map_metadata", "-1", str(path)]
    subprocess.run(cmd, input=pcm, check=True)
