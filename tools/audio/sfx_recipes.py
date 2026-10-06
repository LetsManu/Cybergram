"""W21-A1 sound-effect recipes. Each recipe is `fn(rng, v, **params) -> np.ndarray`
(v = 0-based variant index; rng seeded per file by the catalog). Output is
un-normalised; render_sfx.py normalises to the catalog's loudness target.

Hero palettes (audio direction spec §4):
  Brannoc  low metal + sub-bass      Hex     bitcrush / glitch
  Juniper  mechanical clicks / coils Liora   bright FM chimes
  Ryker    military punch            Sable   phase / reverse swells
  Vesper   plucked-string FM
"""
from __future__ import annotations

import numpy as np

from dsp import (RATE, at, bitcrush, bp, delay, drive, env_adsr, env_exp, fade, fm, hp, karplus,
                 lp, mix, noise, osc, pan, peak_eq, reverb, silence, supersaw, sweep, sweep_lp,
                 t_axis, trim_tail, widen)


def _j(rng, spread: float) -> float:
    """Variation factor around 1.0."""
    return 1.0 + rng.uniform(-spread, spread)


# ================================================================ weapons
def _crack(rng, dur, decay, lo, hi):
    return bp(noise(rng, dur), lo, hi, 2) * env_exp(dur, decay, 0.0003)


def _thump(rng, dur, f0, f1, decay):
    return sweep(f0, f1, dur, "sine", 0.5) * env_exp(dur, decay, 0.0005)


def _mech_click(rng, dur=0.03, f=3200):
    return bp(noise(rng, dur), f * 0.7, f * 1.4, 2) * env_exp(dur, 180, 0.0002)


def gun_rifle(rng, v):
    k = _j(rng, 0.06)
    body = _thump(rng, 0.35, 160 * k, 55, 16) * 1.1
    crack = _crack(rng, 0.25, 38, 900, 7000 * k) * 1.4
    snap = hp(noise(rng, 0.02), 4000) * env_exp(0.02, 300, 0.0001)
    mech = at(_mech_click(rng, 0.03, 2600 * k), 0.035) * 0.25
    x = mix(drive(mix(body, crack, snap) * 1.5, 2.0), mech)
    return trim_tail(reverb(x, 0.35, 0.12, 5000, seed=v + 11))


def gun_smg(rng, v):
    k = _j(rng, 0.07)
    crack = _crack(rng, 0.14, 60, 1800, 9000) * 1.2
    body = _thump(rng, 0.12, 260 * k, 120, 30) * 0.7
    whine = sweep(2400 * k, 900, 0.09, "tri") * env_exp(0.09, 45) * 0.35
    x = drive(mix(crack, body, whine) * 1.4, 1.8)
    return trim_tail(reverb(x, 0.25, 0.1, 6000, seed=v + 12))


def gun_heavy(rng, v):
    k = _j(rng, 0.05)
    sub = _thump(rng, 0.6, 95 * k, 38, 7) * 1.4
    blast = lp(noise(rng, 0.5), 3500 * k, 2) * env_exp(0.5, 11, 0.0005) * 1.3
    crack = _crack(rng, 0.2, 30, 600, 5000) * 1.0
    pump = at(mix(_mech_click(rng, 0.05, 1500), at(_mech_click(rng, 0.05, 1100), 0.07)), 0.32) * 0.18
    x = drive(mix(sub, blast, crack) * 1.6, 2.6)
    return trim_tail(reverb(mix(x, pump), 0.6, 0.16, 3500, seed=v + 13))


def gun_tack(rng, v):
    k = _j(rng, 0.05)
    crack = _crack(rng, 0.3, 26, 700, 8000) * 1.3
    body = _thump(rng, 0.3, 190 * k, 70, 14)
    ring = (osc(1870 * k, 0.5) * 0.6 + osc(2930 * k, 0.5) * 0.4 + osc(4410 * k, 0.5) * 0.2) * env_exp(0.5, 9) * 0.22
    x = mix(drive(mix(crack, body) * 1.6, 2.2), ring)
    return trim_tail(reverb(x, 0.5, 0.14, 6000, seed=v + 14))


def gun_zap(rng, v):
    k = _j(rng, 0.06)
    d = 0.22
    f = 2600 * k * (450 / 2600) ** np.clip(t_axis(d) / 0.12, 0, 1)
    car = osc(f, d)
    mod = osc(f * 1.5, d)
    las = np.sin(2 * np.pi * np.cumsum(f) / RATE + 2.5 * env_exp(d, 18) * mod) * env_exp(d, 16, 0.001)
    sq = osc(f * 0.5, d, "square") * env_exp(d, 30) * 0.2
    air = hp(noise(rng, 0.06), 5000) * env_exp(0.06, 80) * 0.5
    x = mix(las * 0.9, sq, air, car * 0.0)
    return trim_tail(reverb(x, 0.4, 0.18, 7000, seed=v + 15))


def gun_glitch(rng, v):
    k = _j(rng, 0.08)
    d = 0.2
    base = osc(220 * k * (1 + (np.floor(t_axis(d) * 60) % 4) * 0.5), d, "square") * 0.5
    nz = bp(noise(rng, d), 600, 6000) * 0.8
    gate = (np.floor(t_axis(d) * (70 + 20 * v)) % 3 != 1).astype(float)
    x = bitcrush((base + nz) * gate * env_exp(d, 20, 0.0005), 5, 3 + v % 3)
    thump = _thump(rng, 0.1, 180, 80, 40) * 0.6
    return trim_tail(reverb(mix(x, thump), 0.3, 0.12, 5000, seed=v + 16))


def gun_thread(rng, v):
    k = _j(rng, 0.05)
    pl = karplus(392 * k, 0.6, rng, 0.993, 0.8) * 1.2
    fmz = fm(784 * k, 2.01, 3 * env_exp(0.4, 12), 0.4) * env_exp(0.4, 10) * 0.35
    whoosh = sweep_lp(noise(rng, 0.18), 6000, 600) * env_exp(0.18, 18) * 0.4
    x = mix(pl, fmz, whoosh)
    return trim_tail(reverb(x, 0.6, 0.18, 6500, seed=v + 17))


GUN = {"rifle": gun_rifle, "smg_burst": gun_smg, "heavy": gun_heavy, "tack": gun_tack,
       "zap": gun_zap, "glitch": gun_glitch, "thread": gun_thread}


def gun_shot(rng, v, voice):
    return GUN[voice](rng, v)


def gun_tail(rng, v, voice, bright=3000.0, length=1.4):
    """Distant slap / reverb tail played after the shot (own shots + far enemies)."""
    k = _j(rng, 0.05)
    src = mix(lp(noise(rng, 0.05), bright * k) * env_exp(0.05, 40), at(lp(noise(rng, 0.05), bright * 0.6), 0.09) * 0.5)
    x = reverb(src, length, 0.95, bright, predelay=0.03, seed=v + 31)
    return trim_tail(fade(x, 0.02, 0.2), -60)


def reload_part(rng, v, part, voice):
    if voice == "heavy":
        base = 900.0
    elif voice == "tack":
        base = 1600.0
    else:
        base = 1250.0
    k = _j(rng, 0.04)
    if part == "start":
        x = mix(_mech_click(rng, 0.05, base * k), at(lp(noise(rng, 0.12), 2500) * env_exp(0.12, 30), 0.02) * 0.4)
    elif part == "mag_out":
        slide = bp(noise(rng, 0.15), 800, 4000) * env_adsr(0.15, 0.02, 0.05, 0.5, 0.06) * 0.5
        drop = at(mix(_thump(rng, 0.12, 300, 140, 30) * 0.6, _mech_click(rng, 0.04, 900)), 0.18)
        x = mix(slide, drop)
    else:  # done
        seat = mix(_mech_click(rng, 0.04, base * 0.8 * k), _thump(rng, 0.08, 400, 200, 50) * 0.5)
        cock = mix(at(_mech_click(rng, 0.04, base * 1.6 * k), 0.11), at(_mech_click(rng, 0.04, base * 1.2), 0.17))
        x = mix(seat, cock * 0.8)
    return trim_tail(reverb(x, 0.2, 0.08, 6000, seed=v + 41))


def dry_fire(rng, v):
    return trim_tail(mix(_mech_click(rng, 0.03, 2400 * _j(rng, 0.05)), at(_mech_click(rng, 0.02, 1500), 0.012) * 0.5))


def low_ammo(rng, v, mana=False):
    f = 2800 if not mana else 1900
    if mana:
        x = fm(f, 1.5, 1.2 * env_exp(0.08, 30), 0.08) * env_exp(0.08, 40, 0.001)
    else:
        x = mix(osc(f, 0.06, "tri") * env_exp(0.06, 70, 0.0005), _mech_click(rng, 0.02, 4000) * 0.3)
    return trim_tail(x)


def burnout(rng, v):
    d = 0.9
    t = t_axis(d)
    pops = np.zeros(len(t))
    for _ in range(26):
        p = int(rng.uniform(0, d * 0.85) * RATE)
        ln = int(RATE * rng.uniform(0.004, 0.015))
        pops[p:p + ln] += rng.uniform(-1, 1, len(pops[p:p + ln])) * rng.uniform(0.3, 1.0)
    crackle = hp(pops, 1500)
    hum = osc(120 * (1 - 0.4 * t / d), d, "saw") * env_exp(d, 3) * 0.15
    fizz = bitcrush(bp(noise(rng, d), 2000, 9000) * env_exp(d, 4) * 0.4, 6, 2)
    return trim_tail(reverb(mix(crackle, lp(hum, 900), fizz), 0.4, 0.15, 6000, seed=v + 51))


def mana_regen(rng, v):
    d = 0.45
    x = sweep(500, 1500, d, "sine", 0.7) * env_adsr(d, 0.05, 0.1, 0.6, 0.2) * 0.5
    ch = mix(osc(1320, 0.3) * env_exp(0.3, 10), at(osc(1980, 0.3) * env_exp(0.3, 10), 0.08))
    return trim_tail(reverb(mix(x, at(ch * 0.6, 0.3)), 0.6, 0.25, 8000, seed=52))


def impact(rng, v, ammo):
    k = _j(rng, 0.06)
    if ammo == "standard":
        x = mix(_crack(rng, 0.12, 60, 1200, 6000), _thump(rng, 0.12, 220 * k, 90, 35) * 0.8)
    elif ammo == "piercing":
        x = mix(_crack(rng, 0.08, 90, 3000, 12000) * 1.2, osc(3600 * k, 0.15) * env_exp(0.15, 30) * 0.3)
    elif ammo == "sunder":
        x = mix(drive(_thump(rng, 0.2, 140 * k, 50, 18) * 1.6, 2.5),
                bp(noise(rng, 0.2), 300, 2500) * env_exp(0.2, 22) * 0.8)
    else:  # mana
        x = mix(fm(900 * k, 1.41, 4 * env_exp(0.15, 25), 0.15) * env_exp(0.15, 22),
                hp(noise(rng, 0.05), 4000) * env_exp(0.05, 70) * 0.4)
    return trim_tail(reverb(x, 0.2, 0.08, 5000, seed=v + 61))


def core_layer(rng, v, tier):
    """Mount Core tonal layer on the own shot (I faint, II clear, III + tail)."""
    d = 0.18 + 0.12 * tier
    f = 660.0 * (1.0 + 0.25 * (tier - 1))
    x = (osc(f, d) + 0.5 * osc(f * 2.0, d) + 0.25 * tier * osc(f * 3.0, d)) * env_exp(d, 18 - tier * 3, 0.002)
    if tier == 3:
        x = mix(x, at(sweep(f * 2, f * 4, 0.25) * env_exp(0.25, 12) * 0.4, 0.04))
    return trim_tail(reverb(x, 0.4, 0.2, 9000, seed=71 + tier))


# ================================================================ combat
def hit_tick(rng, v, head=False):
    f = (2600 if head else 1700) * _j(rng, 0.02)
    x = osc(f, 0.07) * env_exp(0.07, 55, 0.0008)
    if head:
        x = mix(x, osc(f * 1.5, 0.12) * env_exp(0.12, 30, 0.001) * 0.6,
                hp(noise(rng, 0.02), 6000) * env_exp(0.02, 200) * 0.4)
    else:
        x = mix(x, bp(noise(rng, 0.02), 2000, 6000) * env_exp(0.02, 200) * 0.3)
    return trim_tail(x)


def kill_confirm(rng, v):
    notes = [659.0, 988.0, 1319.0]
    x = mix(*[at(fm(n, 2.0, 1.2 * env_exp(0.4, 8), 0.4) * env_exp(0.4, 9, 0.002), i * 0.07) for i, n in enumerate(notes)])
    sub = _thump(rng, 0.2, 120, 60, 18) * 0.5
    return trim_tail(reverb(mix(x, sub), 0.8, 0.2, 9000, seed=81))


def assist(rng, v):
    x = mix(fm(784, 2.0, 0.8 * env_exp(0.3, 10), 0.3) * env_exp(0.3, 12, 0.002),
            at(fm(1046, 2.0, 0.8 * env_exp(0.3, 10), 0.3) * env_exp(0.3, 12, 0.002), 0.08))
    return trim_tail(reverb(x * 0.8, 0.6, 0.2, 8000, seed=82))


def own_death(rng, v):
    d = 1.6
    down = sweep(420, 55, d, "saw", 0.6) * env_adsr(d, 0.01, 0.3, 0.6, 0.8)
    x = lp(down, 1800) * 0.6
    thud = _thump(rng, 0.5, 90, 35, 6) * 1.0
    glitch = bitcrush(bp(noise(rng, 0.4), 500, 4000) * env_exp(0.4, 8) * 0.5, 4, 6)
    return trim_tail(reverb(mix(x, thud, glitch), 1.6, 0.3, 4000, seed=83))


def damage_taken(rng, v):
    k = _j(rng, 0.08)
    x = mix(_thump(rng, 0.14, 180 * k, 70, 30) * 1.0, bp(noise(rng, 0.08), 400, 2500) * env_exp(0.08, 45) * 0.6)
    return trim_tail(drive(x * 1.2, 1.5))


def heartbeat(rng, v):
    one = _thump(rng, 0.18, 70, 45, 22)
    two = _thump(rng, 0.18, 62, 40, 22) * 0.75
    return trim_tail(lp(mix(one, at(two, 0.22)), 400))


# ============================================================== abilities
# A palette voice renders a "gesture" (cast / impact / loop) with a timbre.
def _pal_brannoc(rng, d, f0, kind):
    sub = _thump(rng, d, f0 * 1.5, f0 * 0.5, 4 / d) * 1.2
    metal = (osc(f0 * 4.1, d) + osc(f0 * 6.3, d) * 0.6 + osc(f0 * 9.7, d) * 0.3) * env_exp(d, 6 / d, 0.002) * 0.3
    grit = lp(noise(rng, d), 900) * env_exp(d, 5 / d) * (0.9 if kind == "impact" else 0.4)
    return mix(sub, metal, grit)


def _pal_hex(rng, d, f0, kind):
    t = t_axis(d)
    steps = 1 + (np.floor(t * 24) % 5) * 0.25
    tone = osc(f0 * steps, d, "square") * 0.4
    nz = bp(noise(rng, d), 800, 7000) * 0.5
    gate = (rng.uniform(size=int(d * 40) + 1)[np.minimum((t * 40).astype(int), int(d * 40))] > 0.25).astype(float)
    return bitcrush((tone + nz) * gate * env_adsr(d, 0.005, d * 0.3, 0.6, d * 0.5), 4, 4)


def _pal_juniper(rng, d, f0, kind):
    clicks = mix(*[at(_mech_click(rng, 0.03, f0 * 3 * (1 + 0.2 * i)), i * d / 6) * (0.8 - 0.08 * i) for i in range(5)])
    coil = osc(f0 * (1 + 0.5 * t_axis(d) / d), d, "saw") * env_adsr(d, 0.01, d * 0.4, 0.4, d * 0.4)
    coil = bp(coil, f0 * 0.8, f0 * 6) * 0.35
    spring = (osc(f0 * 2.2, d) * np.sin(2 * np.pi * 14 * t_axis(d))) * env_exp(d, 5 / d) * 0.2
    return mix(clicks, coil, spring)


def _pal_liora(rng, d, f0, kind):
    notes = [1.0, 1.25, 1.5, 2.0]
    parts = []
    for i, r in enumerate(notes):
        parts.append(at(fm(f0 * r, 3.5, 2.5 * env_exp(d, 4 / d), d) * env_exp(d, 3.5 / d, 0.002) * (0.6 - 0.08 * i), i * d * 0.08))
    shimmer = hp(noise(rng, d), 7000) * env_adsr(d, d * 0.2, 0.1, 0.3, d * 0.5) * 0.15
    return mix(*parts, shimmer)


def _pal_ryker(rng, d, f0, kind):
    punch = drive(_thump(rng, min(d, 0.4), f0 * 2.5, f0, 12) * 1.5, 2.5)
    snap = _crack(rng, min(d, 0.2), 30, 800, 6000) * 0.8
    tail = lp(noise(rng, d), 1500) * env_exp(d, 4 / d) * 0.3
    radio = bp(osc(f0 * 8, d, "square"), 1000, 3000) * env_adsr(d, 0.005, 0.03, 0.0, 0.02) * 0.2
    return mix(punch, snap, tail, radio)


def _pal_sable(rng, d, f0, kind):
    t = t_axis(d)
    swell = (supersaw(f0, d, 4, 0.01, rng)) * (t / d) ** 2
    lfo = 0.5 + 0.5 * np.sin(2 * np.pi * (0.5 + 6 * t / d) * t)
    phased = lp(swell, 400 + 4000 * lfo.mean()) * lfo
    rev_noise = bp(noise(rng, d), 1000, 8000) * (t / d) ** 3 * 0.4
    return fade(mix(phased * 0.7, rev_noise), 0.002, 0.03)


def _pal_vesper(rng, d, f0, kind):
    pl = karplus(f0, d, rng, 0.995, 0.7)
    pl2 = at(karplus(f0 * 1.498, d * 0.8, rng, 0.994, 0.6) * 0.6, d * 0.06)
    fmz = fm(f0 * 2, 1.003, 2 * env_exp(d, 3 / d), d) * env_exp(d, 3 / d, 0.004) * 0.25
    return mix(pl, pl2, fmz)


PALETTE = {"brannoc": _pal_brannoc, "hex": _pal_hex, "juniper": _pal_juniper, "liora": _pal_liora,
           "ryker": _pal_ryker, "sable": _pal_sable, "vesper": _pal_vesper}
PAL_ROOT = {"brannoc": 55.0, "hex": 220.0, "juniper": 330.0, "liora": 880.0, "ryker": 80.0,
            "sable": 110.0, "vesper": 294.0}
PAL_SPACE = {"brannoc": (0.9, 0.18, 3000), "hex": (0.4, 0.12, 6000), "juniper": (0.3, 0.1, 7000),
             "liora": (1.4, 0.3, 10000), "ryker": (0.6, 0.15, 4000), "sable": (1.2, 0.3, 5000),
             "vesper": (1.0, 0.25, 8000)}


def ability(rng, v, hero, gesture, semis=0.0, dur=0.6, ult=False):
    """One hero-palette gesture: cast (rising), impact (hit), loop (seamless bed)."""
    f0 = PAL_ROOT[hero] * 2 ** (semis / 12.0) * _j(rng, 0.01)
    fn = PALETTE[hero]
    if gesture == "loop":
        x = fn(rng, dur, f0, "loop")
        x = x / (np.max(np.abs(x)) + 1e-9)
        k = int(RATE * 0.25)
        x[:k] *= np.linspace(0, 1, k)
        x[-k:] *= np.linspace(1, 0, k)
        x = mix(x, at(x, dur - 0.25))[: int(RATE * (dur * 2 - 0.25))]
        return x[int(RATE * (dur - 0.25)):int(RATE * (2 * dur - 0.5))] if dur > 0.6 else x
    x = fn(rng, dur, f0, gesture)
    if gesture == "cast":
        rise = sweep(f0 * 2, f0 * (8 if ult else 4), dur * 0.7, "sine", 1.5) * env_adsr(dur * 0.7, dur * 0.4, 0.05, 0.5, dur * 0.25) * 0.25
        x = mix(x, rise)
        if ult:
            boom = at(_thump(rng, 0.8, f0 * 1.2, max(f0 * 0.35, 30), 5) * 1.2, dur * 0.55)
            u = t_axis(dur) / dur
            air_env = np.where(u < 0.55, (u / 0.55) ** 2, np.exp(-(u - 0.55) * 9.0))
            air = sweep_lp(noise(rng, dur), 300, 7000) * air_env * 0.25
            x = mix(x, boom, air)
    else:
        x = mix(x, _thump(rng, 0.3, f0 * 2, f0, 12) * 0.6)
    length, wet, damp = PAL_SPACE[hero]
    return trim_tail(reverb(x, length * (1.6 if ult else 1.0), wet, damp, seed=v + 91))


def explosion(rng, v, size=1.0):
    k = _j(rng, 0.06)
    d = 1.4 * size
    sub = _thump(rng, d, 110 * k, 32, 3.5 / size) * 1.4
    body = lp(noise(rng, d), 2200 * k) * env_exp(d, 4.5 / size, 0.002) * 1.4
    crack = _crack(rng, 0.2, 25, 500, 8000) * 0.9
    debris = mix(*[at(hp(noise(rng, 0.03), 3000) * env_exp(0.03, 150) * rng.uniform(0.1, 0.3), rng.uniform(0.15, d * 0.7)) for _ in range(14)])
    x = drive(mix(sub, body, crack) * 1.5, 2.4)
    return trim_tail(reverb(mix(x, debris), 1.5, 0.22, 3000, seed=v + 101))


# ================================================================ world
def wardling(rng, v, event):
    k = _j(rng, 0.06)
    if event == "spawn":
        x = mix(sweep(200 * k, 900 * k, 0.35, "square", 1.2) * env_adsr(0.35, 0.02, 0.1, 0.5, 0.15) * 0.3,
                bp(noise(rng, 0.35), 1500, 6000) * env_adsr(0.35, 0.2, 0.05, 0.3, 0.1) * 0.4)
        x = bitcrush(x, 6, 2)
    elif event == "attack":
        x = mix(fm(1200 * k, 0.5, 3 * env_exp(0.12, 30), 0.12) * env_exp(0.12, 35, 0.001),
                hp(noise(rng, 0.03), 4000) * env_exp(0.03, 120) * 0.4)
    else:  # death
        x = mix(sweep(700 * k, 90, 0.5, "square", 0.6) * env_exp(0.5, 6) * 0.35,
                bitcrush(bp(noise(rng, 0.4), 500, 5000) * env_exp(0.4, 9), 4, 5) * 0.6,
                _thump(rng, 0.2, 160, 60, 20) * 0.5)
    return trim_tail(reverb(x, 0.4, 0.15, 6000, seed=v + 111))


def objective(rng, v, event):
    if event == "capture":
        notes = [523.0, 659.0, 784.0, 1046.0]
        x = mix(*[at(fm(n, 2.0, 1.5 * env_exp(0.8, 4), 0.8) * env_exp(0.8, 5, 0.003), i * 0.09) for i, n in enumerate(notes)])
        x = mix(x, lp(supersaw(130.8, 1.2, 5, 0.01, rng), 1500) * env_adsr(1.2, 0.05, 0.3, 0.5, 0.6) * 0.35)
    elif event == "contest":
        t = t_axis(0.9)
        x = osc(740 + 120 * np.sign(np.sin(2 * np.pi * 6 * t)), 0.9, "square") * env_adsr(0.9, 0.01, 0.1, 0.7, 0.2)
        x = lp(x, 3000) * 0.4
    elif event == "lost":
        notes = [784.0, 659.0, 523.0, 392.0]
        x = mix(*[at(fm(n, 1.5, 2.0 * env_exp(0.9, 4), 0.9) * env_exp(0.9, 4.5, 0.003), i * 0.11) for i, n in enumerate(notes)])
        x = mix(x, lp(supersaw(98.0, 1.4, 5, 0.012, rng), 900) * env_adsr(1.4, 0.05, 0.3, 0.5, 0.6) * 0.35)
    elif event == "uplink_alarm":
        t = t_axis(1.2)
        x = osc(880 * (1 + 0.25 * (np.floor(t * 4) % 2)), 1.2, "saw") * env_adsr(1.2, 0.01, 0.1, 0.8, 0.2)
        x = mix(bp(x, 500, 4000) * 0.5, _thump(rng, 0.3, 120, 60, 12) * 0.5)
    else:  # sudden_death warning
        d = 2.2
        x = mix(sweep(55, 220, d, "saw", 2.0) * env_adsr(d, 0.5, 0.2, 0.8, 0.6) * 0.5,
                at(_thump(rng, 1.0, 90, 30, 3) * 1.4, d * 0.75),
                at(osc(1760, 0.8) * env_exp(0.8, 5) * 0.2, d * 0.75))
        x = lp(x, 6000)
    return trim_tail(reverb(x, 1.2, 0.25, 7000, stereo=True, seed=121))


def generator(rng, v, event):
    """Ward Generator (docs/assets/ward_generator.md): shield collapse, a crack
    per damage stage, the breach."""
    k = _j(rng, 0.05)
    if event == "shield_down":
        d = 1.1
        glass = mix(*[at(osc(f * k, 0.6) * env_exp(0.6, 7) * 0.25, i * 0.05) for i, f in enumerate((2400, 1810, 1350, 990))])
        x = mix(sweep(900 * k, 120, d, "saw", 0.7) * env_adsr(d, 0.01, 0.2, 0.6, 0.5) * 0.35, glass,
                bp(noise(rng, d), 2000, 9000) * env_exp(d, 4) * 0.25)
        x = lp(x, 7000)
    elif event == "crack":
        snap = hp(noise(rng, 0.05), 2500) * env_exp(0.05, 90) * 0.9
        ring = mix(*[osc(f * k, 0.5) * env_exp(0.5, 12) * a for f, a in ((1830, 0.3), (2710, 0.2), (3990, 0.12))])
        crackle = bitcrush(bp(noise(rng, 0.3), 800, 6000) * env_exp(0.3, 14), 6, 3) * 0.35
        x = mix(snap, ring, at(crackle, 0.03), _thump(rng, 0.15, 140 * k, 70, 25) * 0.4)
    else:  # breach
        d = 1.8
        boom = _thump(rng, 0.9, 90 * k, 32, 5) * 1.2
        shatter = mix(*[at(hp(noise(rng, 0.25), 2000) * env_exp(0.25, 18) * 0.35, t) for t in (0.0, 0.07, 0.16, 0.3)])
        zap = bitcrush(fm(220 * k, 3.3, 6 * env_exp(d, 3), d) * env_exp(d, 2.5), 5, 4) * 0.25
        x = mix(boom, shatter, zap, at(sweep(1600, 90, 1.0, "square", 0.5) * env_exp(1.0, 4) * 0.12, 0.1))
        x = lp(x, 9000)
    return trim_tail(reverb(x, 0.9, 0.22, 6500, seed=v + 131))


def beacon(rng, v, event):
    """Forward Beacon spawn pad (docs/assets/forward_beacon.md): attunement starts
    (a rising power-up hum), the Beacon is ready (a bright three-note chime),
    it comes under attack (a dimming double warble; the halo blinks with it)."""
    k = _j(rng, 0.03)
    if event == "attune":
        d = 1.4
        hum = sweep(110 * k, 220 * k, d, "saw", 0.6) * env_adsr(d, 0.3, 0.3, 0.8, 0.5) * 0.25
        shimmer = sweep(880 * k, 1760 * k, d) * env_adsr(d, 0.6, 0.2, 0.5, 0.5) * 0.12
        x = lp(mix(hum, shimmer, bp(noise(rng, d), 1500, 6000) * env_adsr(d, 0.5, 0.2, 0.3, 0.4) * 0.06), 5000)
    elif event == "ready":
        notes = [at(mix(osc(f * k, 0.9), osc(f * 2.01 * k, 0.9) * 0.3) * env_exp(0.9, 5) * 0.28, i * 0.11)
                 for i, f in enumerate((784, 988, 1319))]
        x = mix(*notes, _thump(rng, 0.2, 160 * k, 90, 20) * 0.25)
    else:  # threat
        d = 0.75
        warble = mix(*[at(fm(620 * k, 2.0, 1.5, 0.28) * env_adsr(0.28, 0.01, 0.05, 0.7, 0.12) * 0.3, t)
                       for t in (0.0, 0.36)])
        x = mix(warble, at(sweep(700 * k, 380 * k, 0.3) * env_exp(0.3, 8) * 0.12, 0.42))
        x = lp(bitcrush(x, 7, 2), 6000)
        _ = d
    return trim_tail(reverb(x, 0.8, 0.2, 7000, seed=v + 151))


# ============================================================ footsteps
SURFACE = {"concrete": (95.0, 2500.0, 0.0), "metal": (140.0, 4500.0, 1.0),
           "grate": (180.0, 6000.0, 0.6), "water": (70.0, 1800.0, 0.0)}


def footstep(rng, v, surface):
    f, bright, ring = SURFACE[surface]
    k = _j(rng, 0.08)
    if surface == "water":
        splash = bp(noise(rng, 0.22), 400, 3500) * env_adsr(0.22, 0.01, 0.06, 0.4, 0.12)
        bloop = sweep(500 * k, 1100 * k, 0.06) * env_exp(0.06, 40) * 0.3
        return trim_tail(mix(splash, at(bloop, 0.03), _thump(rng, 0.1, f, 40, 35) * 0.5))
    heel = _thump(rng, 0.12, f * k, f * 0.5, 38)
    scuff = bp(noise(rng, 0.08), 300, bright) * env_exp(0.08, 60, 0.002) * 0.6
    toe = at(bp(noise(rng, 0.04), 600, bright) * env_exp(0.04, 90) * 0.35, 0.045 * k)
    x = mix(heel, scuff, toe)
    if ring:
        rng_f = 900 if surface == "grate" else 1700
        tone = (osc(rng_f * k, 0.25) + osc(rng_f * 2.7 * k, 0.25) * 0.5) * env_exp(0.25, 18, 0.001) * 0.12 * ring
        x = mix(x, tone)
    if surface == "grate":
        x = mix(x, at(_mech_click(rng, 0.03, 2000) * 0.25, 0.02))
    return trim_tail(x)


def body_move(rng, v, kind):
    k = _j(rng, 0.06)
    if kind == "jump":
        x = mix(sweep_lp(noise(rng, 0.2), 500, 3000) * env_adsr(0.2, 0.02, 0.05, 0.4, 0.1) * 0.5,
                _thump(rng, 0.08, 120 * k, 70, 40) * 0.5)
    elif kind == "land_light":
        x = mix(_thump(rng, 0.15, 110 * k, 50, 28), bp(noise(rng, 0.1), 200, 2500) * env_exp(0.1, 40) * 0.5)
    else:  # land_heavy
        x = mix(drive(_thump(rng, 0.3, 90 * k, 35, 14) * 1.5, 2.0),
                bp(noise(rng, 0.2), 150, 2000) * env_exp(0.2, 20) * 0.7,
                at(_mech_click(rng, 0.03, 1200) * 0.3, 0.03))
    return trim_tail(x)


def water(rng, v, kind):
    k = _j(rng, 0.06)
    if kind == "splash":
        x = mix(bp(noise(rng, 0.7), 300, 5000) * env_adsr(0.7, 0.01, 0.15, 0.3, 0.4),
                _thump(rng, 0.2, 90 * k, 40, 15) * 0.8,
                *[at(sweep(rng.uniform(500, 1200), rng.uniform(1300, 2400), 0.05) * env_exp(0.05, 40) * 0.15,
                     rng.uniform(0.1, 0.5)) for _ in range(8)])
    else:  # wade
        x = mix(bp(noise(rng, 0.35), 250, 2200) * env_adsr(0.35, 0.08, 0.1, 0.5, 0.15) * 0.8,
                at(sweep(300 * k, 700 * k, 0.08) * env_exp(0.08, 30) * 0.2, 0.12))
    return trim_tail(x)


# =================================================================== ui
def ui(rng, v, kind):
    if kind == "hover":
        x = osc(2400, 0.035) * env_exp(0.035, 120, 0.001) * 0.6
    elif kind == "click":
        x = mix(osc(1500, 0.05) * env_exp(0.05, 80, 0.0005), bp(noise(rng, 0.01), 2000, 8000) * env_exp(0.01, 400) * 0.3)
    elif kind == "back":
        x = mix(osc(1200, 0.06) * env_exp(0.06, 60, 0.0005), at(osc(900, 0.07) * env_exp(0.07, 60, 0.0005), 0.04))
    elif kind == "confirm":
        x = mix(fm(1046, 2.0, 1.0 * env_exp(0.25, 15), 0.25) * env_exp(0.25, 14, 0.001),
                at(fm(1568, 2.0, 1.0 * env_exp(0.25, 15), 0.25) * env_exp(0.25, 14, 0.001), 0.06))
    elif kind == "error":
        x = osc(220, 0.22, "square") * env_adsr(0.22, 0.005, 0.05, 0.6, 0.08) * 0.4
        x = lp(mix(x, at(osc(185, 0.2, "square") * env_adsr(0.2, 0.005, 0.05, 0.6, 0.08) * 0.4, 0.09)), 2500)
    elif kind == "buy":
        x = mix(*[at(fm(n, 3.0, 1.2 * env_exp(0.3, 14), 0.3) * env_exp(0.3, 14, 0.001), i * 0.05) for i, n in enumerate([1175.0, 1568.0, 2093.0])],
                bp(noise(rng, 0.03), 3000, 9000) * env_exp(0.03, 150) * 0.3)
    elif kind == "sell":
        x = mix(*[at(fm(n, 3.0, 1.0 * env_exp(0.25, 16), 0.25) * env_exp(0.25, 16, 0.001), i * 0.05) for i, n in enumerate([1568.0, 1175.0])])
    elif kind == "denied":
        x = lp(mix(osc(196, 0.18, "saw") * env_adsr(0.18, 0.004, 0.04, 0.6, 0.06),
                   at(osc(196, 0.18, "saw") * env_adsr(0.18, 0.004, 0.04, 0.6, 0.06), 0.12)), 1800) * 0.5
    elif kind == "levelup":
        notes = [523.0, 659.0, 784.0, 1046.0, 1319.0]
        x = mix(*[at(fm(n, 2.0, 1.5 * env_exp(0.6, 6), 0.6) * env_exp(0.6, 6, 0.002), i * 0.06) for i, n in enumerate(notes)],
                at(hp(noise(rng, 0.5), 6000) * env_adsr(0.5, 0.1, 0.1, 0.3, 0.3) * 0.15, 0.2))
    elif kind == "lumen":
        f = 1760 * _j(rng, 0.04)
        x = mix(osc(f, 0.15) * env_exp(0.15, 25, 0.001), at(osc(f * 1.5, 0.15) * env_exp(0.15, 25, 0.001) * 0.6, 0.035))
    elif kind == "fork":
        x = mix(fm(740, 2.0, 1.5 * env_exp(0.35, 10), 0.35) * env_exp(0.35, 9, 0.002),
                at(fm(988, 2.0, 1.5 * env_exp(0.35, 10), 0.35) * env_exp(0.35, 9, 0.002), 0.09))
    elif kind == "lock":
        x = mix(_thump(rng, 0.25, 160, 70, 16) * 0.7,
                at(fm(784, 2.0, 1.5 * env_exp(0.4, 8), 0.4) * env_exp(0.4, 8, 0.002), 0.03),
                at(fm(1175, 2.0, 1.5 * env_exp(0.4, 8), 0.4) * env_exp(0.4, 8, 0.002), 0.09))
    elif kind == "match_found":
        notes = [392.0, 523.0, 659.0, 784.0]
        x = mix(*[at(supersaw(n, 0.9, 5, 0.008, rng) * env_adsr(0.9, 0.01, 0.2, 0.5, 0.5), i * 0.1) for i, n in enumerate(notes)])
        x = lp(x, 5000) * 0.6
    elif kind == "ready_check":
        x = mix(*[at(fm(n, 2.0, 2.0 * env_exp(0.5, 6), 0.5) * env_exp(0.5, 6, 0.002), i * 0.18) for i, n in enumerate([880.0, 880.0, 1175.0])])
    elif kind == "countdown_tick":
        x = mix(osc(1320, 0.12) * env_exp(0.12, 30, 0.001), _thump(rng, 0.08, 200, 120, 40) * 0.4)
    elif kind == "countdown_go":
        x = mix(fm(1760, 2.0, 2.0 * env_exp(0.6, 6), 0.6) * env_exp(0.6, 5, 0.001), _thump(rng, 0.3, 160, 60, 10) * 0.8)
    elif kind == "victory":
        x = mix(*[at(supersaw(n, 2.2, 6, 0.009, rng) * env_adsr(2.2, 0.02, 0.4, 0.6, 1.2), i * 0.12) for i, n in enumerate([261.6, 329.6, 392.0, 523.3])])
        x = mix(lp(x, 6000) * 0.6, _thump(rng, 0.6, 110, 40, 5))
    elif kind == "defeat":
        x = mix(*[at(supersaw(n, 2.4, 6, 0.012, rng) * env_adsr(2.4, 0.05, 0.6, 0.5, 1.2), i * 0.16) for i, n in enumerate([220.0, 207.7, 174.6, 146.8])])
        x = mix(lp(x, 2500) * 0.6, _thump(rng, 0.8, 80, 30, 4))
    else:
        raise ValueError(kind)
    x = reverb(x, 0.7, 0.18, 9000, stereo=True, seed=131)
    return trim_tail(x)


# ============================================================== announcer
def announce(rng, v, tier):
    """Announcer stinger (Voice bus, until recorded lines land): 3 tiers."""
    if tier == "triumph":
        notes = [523.3, 659.3, 784.0, 1046.5]
        x = mix(*[at(supersaw(n, 1.0, 6, 0.01, rng) * env_adsr(1.0, 0.01, 0.2, 0.5, 0.5), i * 0.07) for i, n in enumerate(notes)])
        x = mix(lp(x, 7000) * 0.6, _thump(rng, 0.4, 120, 50, 8))
    elif tier == "alert":
        x = mix(*[at(fm(n, 1.5, 3 * env_exp(0.5, 6), 0.5) * env_exp(0.5, 6, 0.002), i * 0.12) for i, n in enumerate([880.0, 659.3, 880.0])])
        x = mix(x, _thump(rng, 0.3, 140, 60, 12) * 0.6)
    elif tier == "streak":
        notes = [659.3, 830.6, 987.8, 1318.5]
        x = mix(*[at(fm(n, 2.0, 2.0 * env_exp(0.5, 7), 0.5) * env_exp(0.5, 7, 0.002), i * 0.05) for i, n in enumerate(notes)])
        x = mix(x, bitcrush(hp(noise(rng, 0.2), 3000) * env_exp(0.2, 15) * 0.3, 6, 2))
    else:  # neutral
        x = mix(fm(659.3, 2.0, 1.5 * env_exp(0.5, 6), 0.5) * env_exp(0.5, 6, 0.002),
                at(fm(987.8, 2.0, 1.5 * env_exp(0.5, 6), 0.5) * env_exp(0.5, 6, 0.002), 0.1))
    return trim_tail(reverb(x, 1.0, 0.25, 9000, stereo=True, seed=141))


# ============================================================== ambient
def ambient_bed(rng, v, zone, seconds=24.0):
    """Seamless stereo bed per zone (loops; whole-cycle tones + crossfaded noise)."""
    from dsp import loopable
    total = seconds + 2.0
    t = t_axis(total)
    if zone == "base":
        hum = (osc(55, total) * 0.5 + osc(110, total) * 0.25 + osc(165, total) * 0.1) * (0.8 + 0.2 * np.sin(2 * np.pi * t / 8))
        mach = lp(noise(rng, total), 300) * 2.0
        beeps = np.zeros(len(t))
        for _ in range(10):
            p = int(rng.uniform(0, total - 0.3) * RATE)
            b = osc(rng.choice([1320.0, 1760.0, 2093.0]), 0.12) * env_exp(0.12, 30) * 0.1
            beeps[p:p + len(b)] += b
        l = mix(hum * 0.6, mach * 0.6, beeps)
        r = mix(hum * 0.6, lp(noise(rng, total), 300) * 1.2, np.roll(beeps, int(RATE * 0.3)))
    elif zone == "jungle":
        drip = np.zeros(len(t))
        for _ in range(40):
            p = int(rng.uniform(0, total - 0.2) * RATE)
            d = sweep(rng.uniform(900, 1600), rng.uniform(1800, 3000), 0.04) * env_exp(0.04, 60) * rng.uniform(0.05, 0.15)
            drip[p:p + len(d)] += d
        steam = bp(noise(rng, total), 1500, 7000) * (0.25 + 0.2 * np.sin(2 * np.pi * t / 6.5) ** 2)
        insects = bp(noise(rng, total), 4000, 6000) * (0.5 + 0.5 * np.sin(2 * np.pi * 23 * t)) * 0.15
        low = lp(noise(rng, total), 150) * 1.5
        l = mix(drip, steam * 0.5, insects, low)
        r = mix(np.roll(drip, int(RATE * 1.7)), bp(noise(rng, total), 1500, 7000) * 0.25, insects * 0.8, low)
    elif zone == "water":
        lap = bp(noise(rng, total), 200, 1200) * (0.4 + 0.4 * np.sin(2 * np.pi * t / 3.0) ** 2)
        hiss = bp(noise(rng, total), 2000, 8000) * 0.12
        l = mix(lap, hiss)
        r = mix(bp(noise(rng, total), 200, 1200) * (0.4 + 0.4 * np.cos(2 * np.pi * t / 3.0) ** 2), hiss * 0.9)
    else:  # lane: city wash, distant traffic swells, far sirens
        wash = lp(noise(rng, total), 700) * (0.6 + 0.3 * np.sin(2 * np.pi * t / 12.0))
        hum = osc(60, total) * 0.08 + osc(120, total) * 0.04
        siren = osc(700 + 120 * np.sin(2 * np.pi * 0.6 * t), total, "tri") * 0.012 * np.clip(np.sin(2 * np.pi * t / total), 0, 1) ** 4
        l = mix(wash, hum, siren)
        r = mix(lp(noise(rng, total), 700) * (0.6 + 0.3 * np.cos(2 * np.pi * t / 12.0)), hum, siren * 0.6)
    x = np.stack([l[: len(t)], r[: len(t)]], axis=1)
    return loopable(x, 2.0)
