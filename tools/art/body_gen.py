"""Bespoke stylised hero bodies without a scanned/MakeHuman base (W16).

A body is built from a parameter set (design/art/hero-art-bible.md §9,
tools/art/README-hero-pipeline.md):

  1. skeleton: the GAME_BONES joints are placed from the proportions (no retarget
     table needed: mocap and the scripted clips aim bones, they never read lengths);
  2. cage: a low-poly quad box-model is lofted ring by ring (8-vertex superellipse
     rings) along the torso, neck, head, arms, chunky mitt hands with a thumb, legs
     and chunky boot feet; limbs are joined through sockets cut in the torso, so the
     whole body is ONE manifold quad mesh with joint loops at elbows / knees;
  3. Catmull-Clark subdivision (`subdiv`, default 2), flat boot soles;
  4. sculpt pass: proportional edits (gaussian falloff blobs along the normal) for
     the muscle / costume masses (deltoids, pecs, glutes, calves, forearms, ...);
  5. skinning: Blender automatic (heat) weights on a temporary armature, then the
     shoulders, elbows, hips and knees are re-blended with an explicit smoothstep
     falloff across the joint (heat weights are uneven exactly there).

Space: Blender metres, X = character right, Y = forward, Z = up, feet at Z = 0.
All length parameters are metres for a 1.85 m figure; they scale with height/1.85.
"""
import math

import bpy  # noqa: F401  (bpy must load before bmesh)
import bmesh
import numpy as np
from mathutils import Matrix, Vector

REF_H = 1.85

# Lengths/radii in metres at REF_H; angles in degrees; scales are factors.
DEFAULT_BODY = {
    "leg": 0.95,            # hip-joint height (legs ~ half the height)
    "thigh_frac": 0.51,     # thigh share of hip -> ankle
    "ankle": 0.085,         # ankle joint height
    "torso": 0.56,          # hip joint -> neck base
    "neck": 0.075,           # neck length
    "neck_r": 0.058,
    "head_h": 0.235, "head_w": 0.165, "head_d": 0.2,
    "shoulder_w": 0.44,     # shoulder joint to joint
    "chest_w": 0.38, "chest_d": 0.25,
    "waist_w": 0.27, "waist_d": 0.19,
    "hip_w": 0.33, "hip_d": 0.22,
    "hip_joint_w": 0.19,
    "upper_arm": 0.30, "forearm": 0.27,
    "arm_r": 0.057, "forearm_r": 0.055, "wrist_r": 0.037,
    "thigh_r": 0.092, "knee_r": 0.062, "calf_r": 0.072, "ankle_r": 0.046,
    "hand": 1.4,            # chunky hands (x a 0.19 m hand)
    "foot": 1.3,            # chunky boots (x a 0.25 m foot)
    "boot_r": 1.0,          # boot shaft girth factor
    "deltoid": 1.0, "pecs": 0.5, "bust": 0.0, "glutes": 0.5, "calves": 0.6, "forearms": 0.5, "traps": 0.5,
    "muscle": 1.0,          # global sculpt strength
    "boxy": 2.6,            # superellipse exponent of the cross sections (2 = ellipse)
    # posture / stance
    "arm_angle": 48.0,      # A-pose: degrees below horizontal
    "chest_lean": 0.0,      # + leans the chest forward (deg)
    "chest_lift": 0.0,      # + proud chest (m forward at the sternum)
    "shoulder_raise": 0.0,  # m
    "stance": 0.0,          # extra foot spread (m, both feet)
    "head_fwd": 0.0,        # m
    "subdiv": 1,            # Catmull-Clark levels (2 = smoother, about +13k body tris)
}


def params(hero):
    p = dict(DEFAULT_BODY)
    p.update(hero.get("body", {}))
    return p


def _S(t, e):
    """Superellipse profile: sign(t) |t|^(2/e)."""
    return math.copysign(abs(t) ** (2.0 / e), t)


def _smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ skeleton
def skeleton(p, H):
    """GAME_BONES joints {name: (head, tail)} + landmarks, from the body params."""
    k = H / REF_H
    L = {n: (v * k if isinstance(v, float) and n not in NOSCALE else v) for n, v in p.items()}
    J = {}
    hipz = L["leg"]
    ank = L["ankle"]
    neckz = hipz + L["torso"]
    lean = math.radians(p["chest_lean"])

    def lean_pt(v):
        """Rotates a torso point about the spine base by the chest lean."""
        base = Vector((0, 0, hipz + 0.08 * k))
        r = Matrix.Rotation(lean, 3, "X")
        return base + r @ (Vector(v) - base) if lean else Vector(v)

    y0 = -0.01 * k
    J["Hips"] = (Vector((0, y0, hipz)), Vector((0, y0, hipz + 0.12 * k)))
    zs = [hipz + 0.08 * k, hipz + 0.08 * k + (L["torso"] - 0.08 * k) * 0.33,
          hipz + 0.08 * k + (L["torso"] - 0.08 * k) * 0.66, neckz]
    pts = [lean_pt((0, y0 - 0.005 * k, z)) for z in zs]
    J["Spine"] = (pts[0], pts[1])
    J["Chest"] = (pts[1], pts[2])
    J["UpperChest"] = (pts[2], pts[3])
    head_base = pts[3] + Vector((0, 0.012 * k + L["head_fwd"], L["neck"]))
    J["Neck"] = (pts[3], head_base)
    J["Head"] = (head_base, head_base + Vector((0, 0.01 * k, L["head_h"] * 0.92)))
    side = {"R": 1.0, "L": -1.0}
    palm = {}
    for s, sx in side.items():
        sh = pts[3] + Vector((sx * L["shoulder_w"] / 2, -0.02 * k, -0.045 * k + L["shoulder_raise"]))
        J["Clavicle_" + s] = (pts[3] + Vector((sx * 0.025 * k, 0.0, -0.04 * k)), sh)
        a = math.radians(p["arm_angle"])
        d = Vector((sx * math.cos(a), 0.04, -math.sin(a))).normalized()
        el = sh + d * L["upper_arm"]
        d2 = (d + Vector((0, 0.14, 0))).normalized()
        wr = el + d2 * L["forearm"]
        J["UpperArm_" + s] = (sh, el)
        J["LowerArm_" + s] = (el, wr)
        J["Hand_" + s] = (wr, wr + d2 * 0.12 * k * p["hand"])
        n = Vector((-sx * math.sin(a), 0, -math.cos(a)))
        n = (n - d2 * n.dot(d2)).normalized()
        palm[s] = n
        hx = sx * L["hip_joint_w"] / 2
        hip = Vector((hx, y0, hipz))
        fx = hx + sx * (0.012 * k + L["stance"] / 2)
        anc = Vector((fx, y0 - 0.01 * k, ank))
        kn = hip.lerp(anc, p["thigh_frac"]) + Vector((0, 0.012 * k, 0))
        J["UpperLeg_" + s] = (hip, kn)
        J["LowerLeg_" + s] = (kn, anc)
        J["Foot_" + s] = (anc, Vector((fx, anc.y + 0.11 * k * p["foot"], 0.03 * k)))
    lm = {"palm": palm, "k": k, "L": L, "hipz": hipz, "neckz": neckz, "y0": y0}
    return J, lm


NOSCALE = {"thigh_frac", "hand", "foot", "boot_r", "deltoid", "pecs", "bust", "glutes", "calves", "forearms", "traps",
           "muscle", "boxy", "arm_angle", "chest_lean", "subdiv"}


# ------------------------------------------------------------------ cage
class Cage:
    """Quad box-model builder: superellipse rings, bridges, caps and sockets."""

    def __init__(self, boxy):
        self.bm = bmesh.new()
        self.e = boxy
        self.part = self.bm.verts.layers.int.new("part")  # 0 body, 1 hand, 2 foot, 3 head
        self.seams = set()  # UV seams on the cage (frozenset vertex pairs); subdivision keeps them

    def seam_line(self, verts, closed=False):
        vs = [v for v in verts if v is not None]
        for a, b in zip(vs, vs[1:] + (vs[:1] if closed else [])):
            self.seams.add(frozenset((a, b)))

    def mark_seams(self):
        for e in self.bm.edges:
            if frozenset(e.verts) in self.seams:
                e.seam = True

    def vert(self, co, part=0):
        v = self.bm.verts.new(co)
        v[self.part] = part
        return v

    def ring(self, c, u, v, rx, ry, n=8, skip=(), part=0, phase=0.0):
        """Ring of n verts: angle 0 along +v ('front'), +90 deg along +u; `skip` indices -> None."""
        out = []
        for j in range(n):
            t = 2 * math.pi * j / n + phase
            if j in skip:
                out.append(None)
                continue
            out.append(self.vert(c + u * (rx * _S(math.sin(t), self.e)) + v * (ry * _S(math.cos(t), self.e)), part))
        return out

    def ring_at(self, angles, c, u, v, rx, ry, part=0):
        return [self.vert(c + u * (rx * _S(math.sin(t), self.e)) + v * (ry * _S(math.cos(t), self.e)), part)
                for t in angles]

    def bridge(self, r0, r1, skip=()):
        n = len(r0)
        for j in range(n):
            if j in skip:
                continue
            a, b, c, d = r0[j], r0[(j + 1) % n], r1[(j + 1) % n], r1[j]
            if None in (a, b, c, d):
                continue
            self.bm.faces.new((a, b, c, d))

    def cap(self, ring, c, part=0):
        n = len(ring)
        m = self.vert(c, part)
        if n == 4:
            self.bm.faces.new(ring)
            self.bm.verts.remove(m)
            return None
        for j in range(0, n, 2):
            self.bm.faces.new((ring[j], ring[(j + 1) % n], ring[(j + 2) % n], m))
        return m

    @staticmethod
    def angles(loop, c, u, v):
        """Angles (0 = +v, +90 = +u) of loop verts around the axis through c."""
        c = sum((vv.co for vv in loop), Vector()) / len(loop)  # the loop centroid: always inside
        out = []
        for vv in loop:
            q = vv.co - c
            out.append(math.atan2(q.dot(u), q.dot(v)))
        # unwrap to a monotonic run
        for i in range(1, len(out)):
            while out[i] - out[i - 1] > math.pi:
                out[i] -= 2 * math.pi
            while out[i] - out[i - 1] < -math.pi:
                out[i] += 2 * math.pi
        return out

    def tube(self, loop, rings, part=0, close=None):
        """Lofts from an existing vertex loop through rings [(c, u, v, rx, ry)];
        ring verts sit at the loop's angles (no twist). Returns the new rings."""
        c0, u0, v0 = rings[0][0], rings[0][1], rings[0][2]
        ang = self.angles(loop, c0, u0, v0)
        prev = loop
        made = []
        for c, u, v, rx, ry in rings:
            cur = self.ring_at(ang, c, u, v, rx, ry, part)
            self.bridge(prev, cur)
            prev = cur
            made.append(cur)
        if close is not None:
            self.cap(prev, close, part)
        return made


def _frame(axis, front):
    """(u, v) perpendicular to `axis`, v ~ `front`, u = v x axis... right-handed: u = axis x v."""
    axis = axis.normalized()
    v = (front - axis * front.dot(axis)).normalized()
    u = v.cross(axis).normalized()
    return u, v


def build_cage(J, lm, p):
    k = lm["k"]
    L = lm["L"]
    cg = Cage(p["boxy"])
    Z, Y, X = Vector((0, 0, 1)), Vector((0, 1, 0)), Vector((1, 0, 0))
    hipz, neckz = lm["hipz"], lm["neckz"]
    lean = math.radians(p["chest_lean"])
    R = Matrix.Rotation(lean, 3, "X")
    base = Vector((0, 0, hipz + 0.08 * k))

    def tc(z, y=0.0):
        """Torso ring centre at height z (lean applied above the spine base)."""
        c = Vector((0, lm["y0"] + y, z))
        if z > base.z and lean:
            c = base + R @ (c - base)
        return c
    tu, tv = R @ X, R @ Y
    tz = R @ Z
    T = L["torso"]
    chest_y = 0.01 * k + L["chest_lift"]
    # (z offset from the hip joint, half width, half depth, y offset)
    rows = [
        ("B", 0.0, L["hip_w"] * 0.49, L["hip_d"] * 0.5, 0.0),
        ("P", 0.09 * k, L["hip_w"] * 0.47, L["hip_d"] * 0.47, 0.0),
        ("W", 0.20 * k, L["waist_w"] * 0.5, L["waist_d"] * 0.5, 0.005 * k),
        ("C0", T * 0.55, (L["waist_w"] + L["chest_w"]) * 0.25, (L["waist_d"] + L["chest_d"]) * 0.25, chest_y * 0.5),
        ("S0", T * 0.71, L["chest_w"] * 0.5, L["chest_d"] * 0.5, chest_y),
        ("S1", T * 0.84, L["chest_w"] * 0.52, L["chest_d"] * 0.48, chest_y * 0.8),
        ("S2", T * 0.96, L["shoulder_w"] * 0.42, L["chest_d"] * 0.40, 0.0),
    ]
    ring = {}
    for name, dz, rx, ry, y in rows:
        z = hipz + dz
        skip = (2, 6) if name == "S1" else ()
        if name in ("B", "P", "W"):
            u, v, c = X, Y, Vector((0, lm["y0"] + y, z))
        else:
            u, v, c = tu, tv, tc(z, y)
        ring[name] = cg.ring(c, u, v, rx, ry, skip=skip)
    order = [r[0] for r in rows]
    for a, b in zip(order, order[1:]):
        sk = ()
        if (a, b) in (("S0", "S1"), ("S1", "S2")):
            sk = (1, 2, 5, 6)  # arm sockets: 2x2 quads cut on each side
        cg.bridge(ring[a], ring[b], skip=sk)
    # UV seams: front / back halves split at the sides (k = 2, 6) below the arm sockets.
    for kk in (2, 6):
        cg.seam_line([ring[n][kk] for n in ("B", "P", "W", "C0", "S0")])
    # Neck and head.
    nh, nt = J["Neck"]
    nu, nv = _frame(nt - nh, Y)
    n0 = cg.ring(nh + (nt - nh) * 0.1, nu, nv, L["neck_r"] * 1.15, L["neck_r"] * 1.05)
    cg.bridge(ring["S2"], n0)
    n1 = cg.ring(nt, nu, nv, L["neck_r"], L["neck_r"] * 0.95)
    cg.bridge(n0, n1)
    for kk in (2, 6):
        cg.seam_line([ring["S2"][kk], n0[kk], n1[kk]])
    cg.seam_line(n1, closed=True)
    hh, ht = J["Head"]
    hu, hv = _frame(ht - hh, Y)
    hw, hd, hH = L["head_w"], L["head_d"], L["head_h"]
    up = (ht - hh).normalized()
    prev = n1
    head_rings = [n1]
    for f, wx, dy, yo in ((0.12, 0.40, 0.42, 0.025), (0.38, 0.5, 0.5, 0.012), (0.66, 0.52, 0.52, 0.0),
                          (0.88, 0.40, 0.42, -0.005)):
        r = cg.ring(hh + up * (hH * f) + hv * (yo * k), hu, hv, hw * wx, hd * dy, part=3)
        cg.bridge(prev, r)
        prev = r
        head_rings.append(r)
    top_v = cg.cap(prev, hh + up * hH + hv * (-0.005 * k), part=3)
    cg.seam_line([r[4] for r in head_rings] + [top_v])  # back of the head
    # Arms through the sockets.
    for s, sx in (("R", 1.0), ("L", -1.0)):
        if sx > 0:
            loop = [ring["S0"][1], ring["S0"][2], ring["S0"][3], ring["S1"][3], ring["S2"][3], ring["S2"][2],
                    ring["S2"][1], ring["S1"][1]]
        else:
            loop = [ring["S0"][5], ring["S0"][6], ring["S0"][7], ring["S1"][7], ring["S2"][7], ring["S2"][6],
                    ring["S2"][5], ring["S1"][5]]
        cg.seam_line(loop, closed=True)
        _arm(cg, loop, J, lm, p, s, sx)
    # Legs through the crotch loops.
    cz = hipz - 0.075 * k
    hr = L["hip_d"] * 0.5
    cf = cg.vert(Vector((0, lm["y0"] + hr * 0.55, cz + 0.02 * k)))
    cm = cg.vert(Vector((0, lm["y0"] + 0.0, cz)))
    cb = cg.vert(Vector((0, lm["y0"] - hr * 0.6, cz + 0.025 * k)))
    B = ring["B"]
    legs = {"R": [B[0], B[1], B[2], B[3], B[4], cb, cm, cf], "L": [B[0], cf, cm, cb, B[4], B[5], B[6], B[7]]}
    for s, sx in (("R", 1.0), ("L", -1.0)):
        loop = legs[s] if sx > 0 else legs[s][::-1]
        cg.seam_line(loop, closed=True)
        _leg(cg, loop, J, lm, p, s, sx, loop.index(cm))
    cg.mark_seams()
    bm = cg.bm
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def _arm(cg, loop, J, lm, p, s, sx):
    k, L = lm["k"], lm["L"]
    sh, el = J["UpperArm_" + s]
    wr = J["LowerArm_" + s][1]
    d = (el - sh).normalized()
    d2 = (wr - el).normalized()
    n = lm["palm"][s]
    u, v = _frame(d, Vector((0, 1, 0)))
    dl = p["deltoid"]
    ua, fa = L["upper_arm"], L["forearm"]
    ar, fr = L["arm_r"], L["forearm_r"]
    rings = [
        (sh + d * (0.035 * k), u, v, ar * 1.55 * dl, ar * 1.5 * dl),
        (sh + d * (ua * 0.30), u, v, ar * 1.12, ar * 1.12),
        (sh + d * (ua * 0.62), u, v, ar * 1.0, ar * 1.02),
        (sh + d * (ua * 0.88), u, v, ar * 0.9, ar * 0.92),
    ]
    up_rings = cg.tube(loop, rings)
    last = up_rings[-1]
    ue, ve = _frame((d + d2).normalized(), Vector((0, 1, 0)))
    ring_e = cg.ring_at(Cage.angles(last, el, ue, ve), el, ue, ve, fr * 0.92, fr * 0.95)
    cg.bridge(last, ring_e)
    uf, vf = _frame(d2, Vector((0, 1, 0)))
    fore = cg.tube(ring_e, [
        (el + d2 * (fa * 0.12), uf, vf, fr * 1.0, fr * 1.02),
        (el + d2 * (fa * 0.35), uf, vf, fr * 1.12, fr * 1.05),
        (el + d2 * (fa * 0.72), uf, vf, fr * 0.86, fr * 0.84),
        (wr - d2 * (0.01 * k), uf, vf, L["wrist_r"], L["wrist_r"] * 0.9),
    ])
    last = fore[-1]
    cg.seam_line([r[1] for r in [loop] + up_rings + [ring_e] + fore])  # under the arm
    cg.seam_line(last, closed=True)  # wrist
    _hand(cg, last, J, lm, p, s, sx, d2, n)


def _hand(cg, wrist_ring, J, lm, p, s, sx, d, n):
    """Chunky mitt hand curled into a grip, with a thumb."""
    k = lm["k"]
    hs = p["hand"]
    wr = J["Hand_" + s][0]
    side = n.cross(d).normalized()  # across the knuckles
    w = 0.047 * k * hs  # half width
    t = 0.023 * k * hs  # half thickness
    # Frame for the hand rings: u across the palm, v = back of the hand (-palm normal).
    hu, hv = side, -n
    ang = Cage.angles(wrist_ring, wr, hu, hv)
    rings = []
    for f, rw, rt in ((0.035, 0.85, 1.05), (0.075, 1.0, 1.0), (0.105, 1.02, 0.95)):
        rings.append((wr + d * (f * k * hs), rw * w, rt * t))
    prev = wrist_ring
    made = []
    hand_rings = [wrist_ring]
    for c, rx, ry in rings:
        r = cg.ring_at(ang, c, hu, hv, rx, ry, part=1)
        cg.bridge(prev, r)
        made.append(r)
        hand_rings.append(r)
        prev = r
    # Fingers: curl toward the palm; the ring frame turns with the curl (no twist).
    kn = rings[-1][0]
    pos, dirc, vcur = kn, d.copy(), hv.copy()
    sgn = 1.0
    if (Matrix.Rotation(math.radians(30), 3, side) @ d).dot(n) < d.dot(n):
        sgn = -1.0
    for ln, ang_c, sc in ((0.04, 50, 1.0), (0.034, 60, 0.94), (0.026, 55, 0.86)):
        q = Matrix.Rotation(math.radians(ang_c * sgn), 3, side)
        nd = (q @ dirc).normalized()
        pos = pos + (dirc + nd).normalized() * (ln * k * hs)
        dirc = nd
        vcur = (q @ vcur).normalized()
        r = cg.ring_at(ang, pos, side, vcur, w * sc, t * 1.1, part=1)
        cg.bridge(prev, r)
        prev = r
        hand_rings.append(r)
    tipv = cg.cap(prev, pos + dirc * (0.012 * k * hs), part=1)
    cg.seam_line([r[1] for r in hand_rings] + [tipv])
    # Thumb: from the quad between the first two palm rings that faces most along +Y.
    r0, r1 = made[0], made[1]
    best, bj = -9, 0
    for j in range(len(r0)):
        mid = (r0[j].co + r0[(j + 1) % 8].co + r1[j].co + r1[(j + 1) % 8].co) / 4 - (rings[0][0] + rings[1][0]) / 2
        sc_ = mid.normalized().dot(Vector((0, 1, 0))) + 0.4 * mid.normalized().dot(n)
        if sc_ > best:
            best, bj = sc_, j
    j2 = (bj + 1) % 8
    face = None
    for f in r0[bj].link_faces:
        if r0[j2] in f.verts and r1[bj] in f.verts:
            face = f
    if face is None:
        return
    loop = [r0[bj], r0[j2], r1[j2], r1[bj]]
    cc = sum((vv.co for vv in loop), Vector()) / 4
    bmesh.ops.delete(cg.bm, geom=[face], context="FACES_ONLY")
    cg.seam_line(loop, closed=True)
    out = (cc - (rings[0][0] + rings[1][0]) / 2).normalized()
    tdir = (out * 0.8 + d * 0.5 + n * 0.5).normalized()
    tu, tv = _frame(tdir, d)
    tr = 0.016 * k * hs
    cg.tube(loop, [(cc + tdir * (0.018 * k * hs), tu, tv, tr * 1.1, tr * 1.1),
                   (cc + tdir * (0.04 * k * hs) + n * (0.01 * k * hs), tu, tv, tr * 0.95, tr * 0.95)],
            part=1, close=cc + tdir * (0.055 * k * hs) + n * (0.016 * k * hs))


def _leg(cg, loop, J, lm, p, s, sx, inner):
    k, L = lm["k"], lm["L"]
    hip, kn = J["UpperLeg_" + s]
    an = J["LowerLeg_" + s][1]
    d = (kn - hip).normalized()
    d2 = (an - kn).normalized()
    Y = Vector((0, 1, 0))
    u, v = _frame(d, Y)
    if u.x * sx < 0:
        u = -u
    tr, kr, cr, ar = L["thigh_r"], L["knee_r"], L["calf_r"], L["ankle_r"]
    th = (kn - hip).length
    sh = (an - kn).length
    rings = [
        (hip + d * (0.12 * k) + Vector((sx * 0.0, 0.004 * k, 0)), u, v, tr * 1.08, tr * 1.08),
        (hip + d * (th * 0.45), u, v, tr * 0.98, tr * 1.0),
        (hip + d * (th * 0.82), u, v, tr * 0.78, tr * 0.8),
    ]
    leg_rings = [loop] + cg.tube(loop, rings)
    last = leg_rings[-1]
    uk, vk = _frame((d + d2).normalized(), Y)
    if uk.x * sx < 0:
        uk = -uk
    leg_rings += cg.tube(last, [(kn + Vector((0, 0.006 * k, 0)), uk, vk, kr * 1.05, kr * 1.12)])
    last = leg_rings[-1]
    us, vs = _frame(d2, Y)
    if us.x * sx < 0:
        us = -us
    br = p["boot_r"]
    leg_rings += cg.tube(last, [
        (kn + d2 * (sh * 0.12), us, vs, kr * 1.0, kr * 1.05),
        (kn + d2 * (sh * 0.36) + Vector((0, -0.012 * k, 0)), us, vs, cr * 1.0 * br, cr * 1.05 * br),
        (kn + d2 * (sh * 0.70), us, vs, ar * 1.35 * br, ar * 1.4 * br),
        (an + Vector((0, 0, 0.012 * k)), us, vs, ar * 1.25 * br, ar * 1.35 * br),
    ])
    last = leg_rings[-1]
    cg.seam_line([r[inner] for r in leg_rings])  # inner leg
    cg.seam_line(last, closed=True)  # ankle (boot island)
    _foot(cg, last, J, lm, p, s, sx)


def _foot(cg, ankle_ring, J, lm, p, s, sx):
    """Chunky boot: heel block + toe box extruded forward, flat sole."""
    k = lm["k"]
    fs = p["foot"]
    an = J["Foot_" + s][0]
    X, Y, Z = Vector((sx, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
    u, v = Vector((1, 0, 0)), Y
    ang = Cage.angles(ankle_ring, an, u, v)
    fw = 0.05 * k * fs
    fd = 0.056 * k * fs
    heel = an + Vector((0, -0.006 * k, 0))
    h1 = cg.ring_at(ang, Vector((heel.x, heel.y, 0.07 * k)), u, v, fw * 1.0, fd * 1.05, part=2)
    cg.bridge(ankle_ring, h1)
    s0 = cg.ring_at(ang, Vector((heel.x, heel.y, 0.0)), u, v, fw * 1.04, fd * 1.08, part=2)
    # Front 2 quads between h1 and s0 become the toe socket: find the vertex facing +Y.
    j0 = max(range(8), key=lambda j: (h1[j].co - heel).normalized().dot(Y))
    jm, jp = (j0 - 1) % 8, (j0 + 1) % 8
    cg.bridge(h1, s0, skip=(jm, j0))
    cg.cap(s0[::-1], Vector((heel.x, heel.y, 0.0)), part=2)
    cg.seam_line(s0, closed=True)  # sole
    jb = min(range(8), key=lambda j: (h1[j].co - heel).normalized().dot(Y))
    cg.seam_line([ankle_ring[jb], h1[jb], s0[jb]])  # back of the heel
    loop = [h1[jm], h1[j0], h1[jp], s0[jp], s0[j0], s0[jm]]
    c0 = sum((vv.co for vv in loop), Vector()) / 6
    prev = loop
    for f, sw, sz in ((0.09, 1.12, 0.95), (0.165, 1.06, 0.78)):
        c = Vector((heel.x + sx * 0.004 * k, heel.y + f * k * fs, 0.0))
        cur = []
        for vv in loop:
            rel = vv.co - c0
            cur.append(cg.vert(Vector((c.x + rel.x * sw, c.y + rel.y * 0.3, max(0.0, c0.z + rel.z) * sz)), 2))
        cg.bridge(prev, cur)
        prev = cur
    tip = sum((vv.co for vv in prev), Vector()) / 6 + Vector((0, 0.018 * k * fs, -0.004 * k))
    cg.cap(prev, tip, part=2)


# ------------------------------------------------------------------ sculpt
def sculpt(V, N, J, lm, p, part):
    """Proportional edits: gaussian blobs pushing the surface along its normal."""
    k = lm["k"]
    m = p["muscle"]
    blobs = []  # (centre, radius, amount, side mask fn or None)
    for s, sx in (("R", 1.0), ("L", -1.0)):
        sh, el = J["UpperArm_" + s]
        d = (el - sh).normalized()
        blobs += [
            (sh + d * 0.04 * k + Vector((0, 0, 0.02 * k)), 0.07 * k, 0.014 * k * p["deltoid"]),
            (sh.lerp(el, 0.5) + Vector((0, 0.02 * k, 0)), 0.06 * k, 0.006 * k),
            (J["LowerArm_" + s][0].lerp(J["LowerArm_" + s][1], 0.3), 0.06 * k, 0.008 * k * p["forearms"]),
            (J["UpperLeg_" + s][0].lerp(J["UpperLeg_" + s][1], 0.35) + Vector((0, 0.03 * k, 0)), 0.09 * k, 0.008 * k),
            (J["LowerLeg_" + s][0].lerp(J["LowerLeg_" + s][1], 0.33) + Vector((0, -0.04 * k, 0)), 0.07 * k,
             0.012 * k * p["calves"]),
            (Vector((sx * 0.075 * k, lm["y0"] - 0.1 * k, lm["hipz"] + 0.02 * k)), 0.09 * k, 0.016 * k * p["glutes"]),
            (Vector((sx * 0.08 * k, 0.0, 0)) + J["UpperChest"][0] + Vector((0, 0.11 * k, -0.02 * k)), 0.085 * k,
             0.010 * k * p["pecs"] + 0.03 * k * p["bust"]),
            (J["Clavicle_" + s][0].lerp(J["Clavicle_" + s][1], 0.5) + Vector((0, -0.02 * k, 0.04 * k)), 0.07 * k,
             0.012 * k * p["traps"]),
        ]
    for c, r, a in blobs:
        c = np.array(tuple(c))
        d2 = ((V - c) ** 2).sum(1)
        w = np.exp(-d2 / (r * r)) * (part == 0)
        V += N * (w * a * m)[:, None]
    return V


# ------------------------------------------------------------------ weights
def _fix_joint(ob, parent, child, joint, axis, width, radius, side=None):
    """Re-blends parent/child weights across a joint with a smoothstep falloff."""
    gi = {g.name: g.index for g in ob.vertex_groups}
    pi, ci = gi[parent], gi[child]
    me = ob.data
    joint = Vector(joint)
    axis = Vector(axis).normalized()
    for v in me.vertices:
        if (v.co - joint).length > radius:
            continue
        if side is not None and v.co.x * side < 0:
            continue
        w = {g.group: g.weight for g in v.groups}
        tot = w.get(pi, 0.0) + w.get(ci, 0.0)
        if tot < 0.5:
            continue
        t = _smooth(-width, width, (v.co - joint).dot(axis))
        ob.vertex_groups[child].add([v.index], tot * t, "REPLACE")
        ob.vertex_groups[parent].add([v.index], tot * (1 - t), "REPLACE")


def _limit(ob, maxn=4):
    for v in ob.data.vertices:
        gs = sorted(((g.group, g.weight) for g in v.groups), key=lambda x: -x[1])
        keep = [(g, w) for g, w in gs[:maxn] if w > 1e-3]
        tot = sum(w for _, w in keep) or 1.0
        for g, _ in gs:
            ob.vertex_groups[g].remove([v.index])
        for g, w in keep:
            ob.vertex_groups[g].add([v.index], w / tot, "REPLACE")


def skin(ob, J, names, lm):
    """Heat weights from a temporary armature, then explicit joint falloffs."""
    k = lm["k"]
    arm = bpy.data.armatures.new("tmp_rig")
    rig = bpy.data.objects.new("tmp_rig", arm)
    bpy.context.scene.collection.objects.link(rig)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    from build_hero import GAME_BONES
    for name, _a, _b, parent in GAME_BONES:
        eb = arm.edit_bones.new(name)
        eb.head, eb.tail = J[name]
        if parent:
            eb.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    ob.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    ob.parent = None
    for m in list(ob.modifiers):
        ob.modifiers.remove(m)
    for n in names:
        if n not in ob.vertex_groups:
            ob.vertex_groups.new(name=n)
    unweighted = [v.index for v in ob.data.vertices if not any(g.weight > 1e-3 for g in v.groups)]
    if unweighted:
        print("body_gen: %d verts without heat weights -> nearest bone" % len(unweighted))
        _nearest_bone(ob, J, unweighted)
    for s, sx in (("R", 1.0), ("L", -1.0)):
        sh, el = J["UpperArm_" + s]
        _fix_joint(ob, "Clavicle_" + s, "UpperArm_" + s, sh, el - sh, 0.05 * k, 0.17 * k, side=sx)
        _fix_joint(ob, "UpperArm_" + s, "LowerArm_" + s, el, J["LowerArm_" + s][1] - el, 0.035 * k, 0.1 * k, side=sx)
        wr = J["Hand_" + s][0]
        _fix_joint(ob, "LowerArm_" + s, "Hand_" + s, wr, J["Hand_" + s][1] - wr, 0.02 * k, 0.07 * k, side=sx)
        hip, kn = J["UpperLeg_" + s]
        _fix_joint(ob, "Hips", "UpperLeg_" + s, hip + Vector((0, 0, -0.04 * k)), kn - hip + Vector((0, 0.3 * k, 0)) * 0,
                   0.06 * k, 0.2 * k, side=sx)
        _fix_joint(ob, "UpperLeg_" + s, "LowerLeg_" + s, kn, J["LowerLeg_" + s][1] - kn, 0.04 * k, 0.12 * k, side=sx)
        an = J["Foot_" + s][0]
        _fix_joint(ob, "LowerLeg_" + s, "Foot_" + s, an + Vector((0, 0, 0.02 * k)), Vector((0, 0, -1)), 0.025 * k,
                   0.09 * k, side=sx)
    _limit(ob)
    bpy.data.objects.remove(rig, do_unlink=True)
    bpy.data.armatures.remove(arm)
    bpy.context.view_layer.update()  # drops the stale view-layer entry of the removed rig


def _nearest_bone(ob, J, idx):
    segs = [(n, np.array(tuple(h)), np.array(tuple(t))) for n, (h, t) in J.items()]
    for i in idx:
        p = np.array(tuple(ob.data.vertices[i].co))
        best, bn = 1e9, "Hips"
        for n, a, b in segs:
            ab = b - a
            t = np.clip(np.dot(p - a, ab) / max(np.dot(ab, ab), 1e-9), 0, 1)
            d = np.linalg.norm(a + ab * t - p)
            if d < best:
                best, bn = d, n
        ob.vertex_groups[bn].add([i], 1.0, "REPLACE")


# ------------------------------------------------------------------ the body object
def build_body_object(key, J, lm, p, names):
    """Cage -> subdivided, sculpted, skinned body object (also returns per-vertex part ids)."""
    bm = build_cage(J, lm, p)
    me = bpy.data.meshes.new(key + "_body")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(key + "_body", me)
    bpy.context.scene.collection.objects.link(ob)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    if p["subdiv"] > 0:
        m = ob.modifiers.new("sd", "SUBSURF")
        m.levels = m.render_levels = int(p["subdiv"])
        m.boundary_smooth = "ALL"
        bpy.ops.object.modifier_apply(modifier=m.name)
    me = ob.data
    n = len(me.vertices)
    V = np.zeros(n * 3)
    me.vertices.foreach_get("co", V)
    V = V.reshape(n, 3)
    part = np.zeros(n, dtype=np.int32)
    if "part" in me.attributes:
        me.attributes["part"].data.foreach_get("value", part)
    Nn = np.zeros(n * 3)
    me.vertices.foreach_get("normal", Nn)
    Nn = Nn.reshape(n, 3)
    V = sculpt(V, Nn, J, lm, p, part)
    # Flat boot soles.
    k = lm["k"]
    V[:, 2] -= max(0.0, V[:, 2].min())
    sole = V[:, 2] < 0.012 * k
    V[sole, 2] = 0.0
    me.vertices.foreach_set("co", V.ravel())
    me.update()
    for poly in me.polygons:
        poly.use_smooth = True
    if "part" in me.attributes:
        me.attributes.remove(me.attributes["part"])
    skin(ob, J, names, lm)
    print("body_gen: body %d verts, %d tris" % (len(me.vertices), sum(len(q.vertices) - 2 for q in me.polygons)))
    return ob
