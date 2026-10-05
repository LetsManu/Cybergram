"""W19-VM first-person clips, authored per frame on the FpRig pose model (fp_rig.py).

Clips (30 fps; the runtime rescales one-shots to gameplay timing, never the reverse):
  idle (breathing, loop) . walk / sprint (sway, loop) . jump / land
  fire (visual kick; the aim kick stays RecoilKick's) . reload (choreography per hero)
  draw / holster . cast (Q/E/C) / cast_ult (G) . inspect
A pose is a dict: W (weapon matrix, eye space), mag (Mag bone local matrix), R (right
hand override or None = on the grip), L (left hand matrix), curl {side: {finger: (a0, a1, a2)}},
spread {side: 0..1}.
"""
import math

import bpy
from mathutils import Matrix, Vector

from fp_rig import SHAPES, euler_deg, mat

FPS = 30
CLIPS = {}  # name -> (frames, loop)


def sm(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def env(t, a, b):
    return sm((t - a) / (b - a)) if b > a else float(t >= a)


def kf(t, keys):
    """Piecewise smooth interpolation through (t, value) keys."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1:
            return v0 + (v1 - v0) * sm((t - t0) / (t1 - t0))
    return keys[-1][1]


def blend(A, B, w):
    if w <= 0.0:
        return A.copy()
    if w >= 1.0:
        return B.copy()
    la, ra, _ = A.decompose()
    lb, rb, _ = B.decompose()
    M = ra.slerp(rb, w).to_matrix().to_4x4()
    M.translation = la.lerp(lb, w)
    return M


def mix(a, b, w):
    return {f: tuple(x + (y - x) * w for x, y in zip(a[f], b[f])) for f in a}


def add(a, d):
    return {f: tuple(x + y for x, y in zip(a[f], d.get(f, (0, 0, 0)))) for f in a}


class Ctx:
    def __init__(self, rig):
        self.rig = rig
        self.fd = rig.fd
        self.two = bool(rig.fd.get("two_handed"))
        self.spool = rig.fd.get("reload") == "spool"
        self.left_shape = SHAPES[rig.fd.get("left_idle", {}).get("shape", "relax")] if not self.two else None

    def W(self, dx=0.0, dy=0.0, dz=0.0, rx=0.0, ry=0.0, rz=0.0):
        """Weapon offset about the grip: eye-space translation, then pitch/roll/yaw (deg)."""
        return Matrix.Translation(Vector((dx, dy, dz))) @ self.rig.W0 @ euler_deg(rx, ry, rz)

    def L_eye(self, dx=0.0, dy=0.0, dz=0.0, rx=0.0, ry=0.0, rz=0.0):
        return Matrix.Translation(Vector((dx, dy, dz))) @ self.rig.L0 @ euler_deg(rx, ry, rz)

    def pose(self, W, L=None, lcurl=None, mag=None, trig=0.0, spread=0.0, follow=0.35):
        """One-handed: the free hand follows a share of the weapon sway (`follow`)."""
        rig = self.rig
        if L is None:
            if self.two:
                L = W @ rig.G["L"]
            else:
                d = (W.translation - rig.W0.translation) * follow
                L = Matrix.Translation(d) @ rig.L0
        if lcurl is None:
            lcurl = rig.curl["L"] if self.two else self.left_shape
        rc = add(rig.curl["R"], {"Index": (10 * trig, 14 * trig, 8 * trig)})
        return {"W": W, "L": L, "R": None, "mag": mag if mag is not None else Matrix.Identity(4),
                "curl": {"R": rc, "L": lcurl}, "spread": {"L": spread}}

    def spin(self, deg):
        return Matrix.Rotation(math.radians(deg), 4, self.rig.mag_axis)


# ------------------------------------------------------------------ clips
def idle(c, t):
    ph = 2 * math.pi * t
    W = c.W(0, 0, 0.0035 * math.sin(ph), 0.7 * math.sin(ph + 0.6), 0.5 * math.sin(ph), 0.3 * math.sin(ph))
    if c.two:
        return c.pose(W)
    L = c.L_eye(0.002 * math.sin(ph), 0.004 * math.sin(ph + 1), 0.006 * math.sin(ph + 1.2),
                2.0 * math.sin(ph + 0.4), 0, 1.5 * math.sin(ph))
    return c.pose(W, L, mix(c.left_shape, SHAPES["conduct"], 0.15 + 0.12 * math.sin(ph)))


def walk(c, t):
    ph = 2 * math.pi * t
    W = c.W(0.009 * math.sin(ph), 0.004 * math.sin(2 * ph), -0.006 * (1 - math.cos(2 * ph)) / 2,
            1.2 * math.sin(2 * ph), 2.2 * math.sin(ph), 1.2 * math.sin(ph))
    if c.two:
        return c.pose(W)
    L = c.L_eye(-0.008 * math.sin(ph), 0.012 * math.sin(ph), -0.008 * (1 - math.cos(2 * ph)) / 2,
                3 * math.sin(ph), 0, 2 * math.sin(ph))
    return c.pose(W, L)


def sprint(c, t):
    ph = 2 * math.pi * t
    b = (1 - math.cos(2 * ph)) / 2
    W = c.W(0.035 + 0.016 * math.sin(ph), -0.05, -0.075 - 0.014 * b, -24 + 3 * math.sin(2 * ph),
            -26 + 4 * math.sin(ph), 14 + 3 * math.sin(ph))
    if c.two:
        return c.pose(W)
    L = c.L_eye(0.015, 0.06 * math.sin(ph + math.pi), -0.05 + 0.025 * math.cos(ph), -20 + 12 * math.sin(ph), 0, 0)
    return c.pose(W, L, SHAPES["fist"])


def jump(c, t):
    dz = kf(t, [(0, 0.0), (0.3, -0.03), (0.7, 0.008), (1, 0.0)])
    rx = kf(t, [(0, 0.0), (0.3, -5.0), (0.7, 2.0), (1, 0.0)])
    W = c.W(0, 0, dz, rx, 0, 0)
    return c.pose(W, None if c.two else c.L_eye(0, 0, dz * 1.3, rx, 0, 0))


def land(c, t):
    dz = kf(t, [(0, 0.0), (0.22, -0.04), (0.6, 0.006), (1, 0.0)])
    rx = kf(t, [(0, 0.0), (0.22, -6.0), (0.6, 1.5), (1, 0.0)])
    W = c.W(0, 0, dz, rx, 0, 0)
    return c.pose(W, None if c.two else c.L_eye(0, 0, dz * 1.4, rx * 1.3, 0, 0))


def fire(c, t):
    k = kf(t, [(0, 0.0), (0.14, 1.0), (0.45, 0.35), (1, 0.0)])
    W = c.W(0, -0.04 * k, 0.012 * k, 8 * k, 1.5 * k, -1.0 * k)
    trig = 1.0 - sm(t / 0.5)
    mag = c.spin(-60 * sm(t / 0.6)) if c.spool else None
    if c.two:
        return c.pose(W, mag=mag, trig=trig)
    return c.pose(W, c.L_eye(0, -0.006 * k, 0.004 * k, 3 * k, 0, 0), mag=mag, trig=trig)


def reload(c, t):
    if c.spool:
        return _reload_spool(c, t)
    return _reload_mag(c, t)


def _reload_spool(c, t):
    """Vesper: tilt the carbine, the left hand spins the spool drum (re-threading),
    pulls the new thread along the needle barrel, back to idle."""
    a = env(t, 0.0, 0.18) - env(t, 0.82, 1.0)
    W = c.W(-0.045 * a, 0.04 * a, 0.035 * a, 6 * a, -38 * a, 14 * a)
    u = max(0.0, min(1.0, (t - 0.24) / 0.38))
    phi = -35 * math.sin(2 * math.pi * 2 * u) * env(t, 0.22, 0.3) * (1 - env(t, 0.58, 0.64))
    spool = Matrix.Translation(c.rig.mag_c) @ c.spin(phi) @ Matrix.Translation(-c.rig.mag_c)
    on = mat((-0.115, -0.02, 0.0), (0.45, 0.62, 0.62), (-1.0, 0.15, 0.1))
    pull = mat((-0.12, 0.26, 0.02), (0.35, 0.8, 0.45), (-1.0, 0.2, 0.3))
    Lw = blend(spool @ on, pull, env(t, 0.62, 0.78))
    wL = env(t, 0.08, 0.24) - env(t, 0.78, 0.95)
    L = blend(c.L_eye(), W @ Lw, wL)
    shape = mix(c.left_shape, SHAPES["pinch"], wL)
    mag = c.spin(-540 * sm(u) - 90 * env(t, 0.64, 0.78))
    return c.pose(W, L, shape, mag=mag)


def _reload_mag(c, t):
    """Magazine / drum / cell guns: tilt, the part ejects along `mag.eject`, the off hand
    brings it back, seats it and slaps it home."""
    rig = c.rig
    ej = Vector(c.fd["mag"].get("eject", (0.0, -0.02, -0.35)))
    side = ej.normalized()
    a = env(t, 0.0, 0.15) - env(t, 0.85, 1.0)
    slap = kf(t, [(0, 0), (0.62, 0), (0.66, 1), (0.74, 0), (1, 0)])
    # raise the gun into view and roll it onto its right flank: the mag well faces
    # the eye and the off hand works it from the left, on screen
    roll = c.fd.get("reload_roll", 78.0)  # big guns (Brannoc's drum) roll less or they fill the view
    tilt = (-0.08 * a, 0.03 * a, 0.09 * a, 12 * a, roll * a, 12 * a)
    W = c.W(tilt[0], tilt[1], tilt[2] + 0.01 * slap, tilt[3] + 3 * slap, tilt[4], tilt[5])
    out = env(t, 0.15, 0.3) * (1 - env(t, 0.42, 0.62))
    mag = Matrix.Translation(ej * out)
    dorsal = (side * 0.8 + Vector((-0.6, 0.0, 0.0))).normalized()
    fingers = (-side + Vector((0.0, 0.35, 0.0))).normalized()
    at = mat(rig.mag_c + side * 0.08 + Vector((-0.05, -0.03, 0.0)), fingers, dorsal)
    away = Matrix.Translation(ej * 0.55) @ at  # stays in view: the swap reads on screen
    Lw = blend(away, Matrix.Translation(ej * out) @ at, env(t, 0.3, 0.6))
    wL = env(t, 0.12, 0.3) - env(t, 0.72, 0.9)
    base = c.W(*tilt) @ rig.G["L"] if c.two else c.L_eye()
    L = blend(base, W @ Lw, wL)
    shape = mix(rig.curl["L"] if c.two else c.left_shape, SHAPES["claw"], wL)
    return c.pose(W, L, shape, mag=mag)


def draw(c, t):
    a = 1 - sm(t / 0.8)
    o = 3 * math.sin(math.pi * max(0.0, (t - 0.6) / 0.4)) * (t > 0.6)
    W = c.W(0.04 * a, -0.08 * a, -0.24 * a, -55 * a + o, -20 * a, 10 * a)
    if c.two:
        return c.pose(W)
    return c.pose(W, c.L_eye(-0.02 * a, -0.05 * a, -0.22 * a, -30 * a, 0, 0))


def holster(c, t):
    a = sm(t)
    W = c.W(0.04 * a, -0.08 * a, -0.24 * a, -55 * a, -20 * a, 10 * a)
    if c.two:
        return c.pose(W)
    return c.pose(W, c.L_eye(-0.02 * a, -0.05 * a, -0.22 * a, -30 * a, 0, 0))


def cast(c, t):
    """Q/E/C: the off hand thrusts out, palm forward, fingers flick open."""
    p = kf(t, [(0, 0.0), (0.3, 1.0), (0.6, 0.85), (1, 0.0)])
    W = c.W(0.006 * p, 0, -0.014 * p, -3 * p, 2 * p, 0)
    L = c.L_eye(0.09 * p, 0.2 * p, 0.12 * p, -55 * p, 0, -10 * p)
    if c.two:
        L = blend(W @ c.rig.G["L"], L, env(t, 0.0, 0.2) - env(t, 0.7, 1.0))
    base = c.rig.curl["L"] if c.two else c.left_shape
    flick = env(t, 0.18, 0.32) - env(t, 0.6, 0.9)
    shape = mix(mix(base, SHAPES["claw"], env(t, 0.0, 0.18) * (1 - flick)), SHAPES["spread"], flick)
    mag = c.spin(-120 * sm(t)) if c.spool else None
    return c.pose(W, L, shape, mag=mag, spread=flick)


def cast_ult(c, t):
    """G: the weapon swings low and out, the off hand rises high, gathers (claw,
    trembling), then slams forward open."""
    a = env(t, 0.0, 0.22) - env(t, 0.78, 1.0)
    W = c.W(0.05 * a, -0.03 * a, -0.075 * a, -14 * a, 26 * a, -10 * a)
    up = env(t, 0.05, 0.3) * (1 - env(t, 0.5, 0.62))
    slam = env(t, 0.5, 0.62) * (1 - env(t, 0.8, 1.0))
    tr = 0.004 * math.sin(t * 90) * env(t, 0.28, 0.32) * (1 - env(t, 0.48, 0.5))
    L = c.L_eye(0.11 * up + 0.12 * slam + tr, 0.1 * up + 0.24 * slam, 0.25 * up + 0.12 * slam,
                40 * up - 60 * slam, 0, -15 * up)
    if c.two:
        L = blend(W @ c.rig.G["L"], L, env(t, 0.0, 0.15) - env(t, 0.82, 1.0))
    base = c.rig.curl["L"] if c.two else c.left_shape
    shape = mix(mix(base, SHAPES["claw"], up), SHAPES["spread"], slam)
    mag = c.spin(-720 * sm(t)) if c.spool else None
    return c.pose(W, L, shape, mag=mag, spread=slam)


def inspect(c, t):
    """Show the left flank (the off hand strokes the barrel), flip to the right flank, back."""
    a = env(t, 0.0, 0.2) - env(t, 0.82, 1.0)
    b = env(t, 0.42, 0.55) - env(t, 0.72, 0.82)
    W = c.W(-0.08 * a, 0.02 * a, 0.05 * a, 8 * a + 16 * b, -70 * a + 100 * b, 28 * a - 14 * b)
    stroke = env(t, 0.18, 0.4)
    Lw = mat((-0.1, 0.08 + 0.16 * stroke, 0.0), (0.35, 0.85, 0.35), (-1.0, 0.1, 0.25))
    wL = (env(t, 0.12, 0.22) - env(t, 0.4, 0.5))
    if c.two:
        L = blend(W @ c.rig.G["L"], W @ Lw, wL)
        shape = mix(c.rig.curl["L"], SHAPES["conduct"], wL)
    else:
        L = blend(c.L_eye(), W @ Lw, wL)
        shape = mix(c.left_shape, SHAPES["conduct"], wL)
    mag = c.spin(-360 * env(t, 0.5, 0.75)) if c.spool else None
    return c.pose(W, L, shape, mag=mag)


CLIP_TABLE = [("idle", 90, True, idle), ("walk", 32, True, walk), ("sprint", 20, True, sprint),
              ("jump", 14, False, jump), ("land", 14, False, land), ("fire", 8, False, fire),
              ("reload", 54, False, reload), ("draw", 14, False, draw), ("holster", 12, False, holster),
              ("cast", 20, False, cast), ("cast_ult", 36, False, cast_ult), ("inspect", 96, False, inspect)]


def author_all(rig):
    c = Ctx(rig)
    ob = rig.rig
    ob.animation_data_create()
    info = {}
    for name, frames, loop, fn in CLIP_TABLE:
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        ob.animation_data.action = act
        rig._lastq = {}
        for f in range(frames + 1):
            rig.key(fn(c, f / frames), f)
        info[name] = {"frames": frames, "loop": loop, "length": frames / FPS}
    ob.animation_data.action = bpy.data.actions["idle"]
    return info


def pose_at(rig, name, t):
    """Pose dict of clip `name` at t in [0, 1] (previews / tests)."""
    c = Ctx(rig)
    for n, _f, _l, fn in CLIP_TABLE:
        if n == name:
            return fn(c, t)
    raise KeyError(name)
