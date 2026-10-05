#!/usr/bin/env python3
"""W14 HD layer for the rigged toon heroes (design/art/hero-art-bible.md §8).

Called by build_hero.py. Everything is authored in Blender (bpy):
  * detail kit: surface-conforming belts, straps, bandolier, pouches, holster,
    bracers, arm bands, collar, back cables, power cell, ear vents, rivets
    (skinned by copying the nearest body weights);
  * weapon detail: rail with teeth, sights, muzzle device with ports, trigger
    guard, ejection port, receiver side plates, energy strips;
  * modifier pass on the hard-surface parts: Bevel (chamfer) + Weighted Normal;
  * texture set: Smart UV unwrap, Cycles data bakes (colour, material masks, AO,
    curvature-from-Bevel-node, object position, world normal) composited in numpy
    into a hand-painted albedo + packed mask, and a tangent-space normal map baked
    selected-to-active from a high-poly copy (Bevel 3 seg + Subdivision + cloth
    Displace modifiers, plus panel-line / rivet / seam bump in its material).

Texture conventions (the toon shader samples them as raw data, like COLOR):
  <key>_albedo.png  RGB raw albedo (team faces = neutral value, recoloured in shader)
  <key>_normal.png  OpenGL tangent-space normal map
  <key>_mask.png    R AO, G spec/glint (metal), B emissive, A team
"""
import math
import os

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

# Palette names -> metalness (spec/glint mask). Unlisted: hard parts 0.55, cloth 0.
METAL = {"chrome": 1.0, "iron": 0.85, "brass": 0.95, "gold": 1.0, "hd_metal": 0.9, "hd_gun": 0.75,
         "hd_buckle": 1.0, "trim": 0.6, "screen": 0.7, "mask": 0.5}
CLOTH = {"hoodie", "legs", "trousers", "suit", "tape", "sneaker", "hair", "hd_strap", "hd_cloth"}
NONMETAL = {"rubber", "bone", "ivory", "wood", "sneaker", "skin", "lip", "brow", "eye", "hair", "hd_strap", "soot", "ink"}
KIND_BODY, KIND_SHELL, KIND_PART, KIND_WEAPON, KIND_SOFT = 0, 1, 2, 3, 4

# Per-hero detail kit (all optional; defaults in DEFAULT). Angles: 0 = front, +90 = hero's left.
DEFAULT = {"belt": {"z": 0.0, "off": 0.006, "width": 0.045, "pouches": (60, 115, -115), "buckle": True},
           "bandolier": False, "holster": "R", "bracers": True, "arm_bands": True, "collar": False,
           "thigh_straps": True, "cables": True, "cell": False, "ear_vents": False,
           "weapon": {"energy": True, "rail": True, "muzzle": True}}
HD = {
    "ryker": {"bandolier": True, "ear_vents": True, "cell": True},
    "vesper": {"belt": {"off": 0.03, "pouches": (70, -70)}, "holster": None, "weapon": {"rail": False, "muzzle": False}, "collar": True, "cables": False,
               "cloth_names": ("violet", "plum", "suit")},
    "brannoc": {"belt": {"off": 0.012, "width": 0.06, "pouches": (55, -55, 120, -120)}, "bandolier": True,
                "holster": None, "cell": True, "weapon": {"energy": True}},
    "liora": {"belt": {"off": 0.012, "pouches": (95, -95)}, "holster": None, "weapon": {"rail": False, "muzzle": False}, "collar": True, "thigh_straps": False},
    "sable": {"belt": {"pouches": (75, -110)}, "holster": "L", "ear_vents": True},
    "juniper": {"belt": {"pouches": (60, 110, -60, -110)}, "bandolier": True, "holster": None},
    "hex": {"belt": {"pouches": (80, -80)}, "holster": "R", "weapon": {"muzzle": False}, "ear_vents": True, "cell": True},
}


def cfg(h):
    c = {k: (dict(v) if isinstance(v, dict) else v) for k, v in DEFAULT.items()}
    for k, v in HD.get(h.key, {}).items():
        if isinstance(v, dict) and isinstance(c.get(k), dict):
            c[k].update(v)
        else:
            c[k] = v
    return c


def prep_palette(h):
    pal = h.pal
    names = [n for n in pal if n not in ("team", "eye")]
    lum = lambda c: 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
    dark = min((pal[n] for n in names), key=lum)
    pal.setdefault("hd_strap", tuple(max(0.07, c * 0.62) for c in dark[:3]) + (1.0,))
    metal = next((pal[n] for n in ("iron", "chrome") if n in pal), (0.50, 0.53, 0.57, 1.0))
    pal.setdefault("hd_metal", metal)
    pal.setdefault("hd_gun", (0.27, 0.28, 0.31, 1.0))
    pal.setdefault("hd_buckle", pal.get("brass", pal.get("gold", (0.78, 0.62, 0.34, 1.0))))
    pal.setdefault("hd_ink", (0.06, 0.065, 0.08, 1.0))


# ------------------------------------------------------------------ skinning / surface
class BodySkin:
    """Weights for detail pieces = inverse-distance blend of the 3 nearest body vertices."""

    def __init__(self, h):
        me = h.body.data
        self.kd = KDTree(len(me.vertices))
        for v in me.vertices:
            self.kd.insert(v.co, v.index)
        self.kd.balance()
        names = [g.name for g in h.body.vertex_groups]
        self.w = [{names[g.group]: g.weight for g in v.groups if g.weight > 1e-3} for v in me.vertices]

    def __call__(self, co):
        acc, tot = {}, 0.0
        for _p, i, d in self.kd.find_n(co, 3):
            k = 1.0 / (d + 1e-3)
            for b, w in self.w[i].items():
                acc[b] = acc.get(b, 0.0) + w * k
            tot += k
        top = sorted(acc.items(), key=lambda x: -x[1])[:4]
        s = sum(w for _, w in top) or 1.0
        return {b: w / s for b, w in top}

    def fixed(self, co):
        w = self(co)
        return lambda _co: w


def body_bvh(h, bones):
    cache = h.__dict__.setdefault("_hd_bvh", {})
    key = tuple(sorted(bones))
    if key in cache:
        return cache[key]
    me = h.body.data
    names = [g.name for g in h.body.vertex_groups]
    idx = {names.index(b) for b in bones if b in names}
    dom = [max(v.groups, key=lambda g: g.weight).group if len(v.groups) else -1 for v in me.vertices]
    verts = [v.co.copy() for v in me.vertices]
    polys = [list(p.vertices) for p in me.polygons
             if sum(1 for vi in p.vertices if dom[vi] in idx) * 2 >= len(p.vertices)]
    cache[key] = BVHTree.FromPolygons(verts, polys)
    return cache[key]


def ring(h, c, nrm, bones, n=32, off=0.006, reach=0.7):
    """Closed loop hugging the body in the plane (c, nrm); concavities bridged."""
    bvh = body_bvh(h, bones)
    c, nrm = Vector(c), Vector(nrm).normalized()
    ref = Vector((0, 0, 1)) if abs(nrm.z) < 0.9 else Vector((0, 1, 0))
    u = ref.cross(nrm).normalized()
    v = nrm.cross(u)
    dirs, rad = [], []
    for i in range(n):
        a = 2 * math.pi * i / n
        d = u * math.cos(a) + v * math.sin(a)
        hit = bvh.ray_cast(c + d * reach, -d, reach)
        dirs.append(d)
        rad.append((hit[0] - c).dot(d) if hit[0] is not None else 0.08)
    r = np.array(rad)
    for _ in range(4):  # a belt bridges concavities
        r = np.maximum(r, 0.5 * (np.roll(r, 1) + np.roll(r, -1)))
    return [(c + d * (float(ri) + off), d) for d, ri in zip(dirs, r)]


def strap(h, pts, nrm, width, thick, color, skin, ch="flat", closed=True):
    t = bmesh.new()
    nrm = Vector(nrm).normalized()
    rows = []
    for p, d in pts:
        a, b = p - nrm * width / 2, p + nrm * width / 2
        rows.append([t.verts.new(a), t.verts.new(b), t.verts.new(b + d * thick), t.verts.new(a + d * thick)])
    n = len(rows)
    for i in range(n if closed else n - 1):
        r0, r1 = rows[i], rows[(i + 1) % n]
        for k in range(4):
            t.faces.new([r0[k], r1[k], r1[(k + 1) % 4], r0[(k + 1) % 4]])
    if not closed:
        t.faces.new(rows[0][::-1])
        t.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
    h._add(t, Matrix.Identity(4), "Hips", color, ch, weights=skin, kind=KIND_SOFT if color == "hd_strap" else None)


def frame(pt, out, up):
    out = Vector(out).normalized()
    side = Vector(up).cross(out).normalized()
    up2 = out.cross(side)
    M = Matrix((side, up2, out)).transposed().to_4x4()
    M.translation = pt
    return M


def piece(h, M, c, size, color, w, ch="flat", **kw):
    h.box("Hips", None, size, color, ch, mat=M @ Matrix.Translation(Vector(c)), weights=w, **kw)


def pouch(h, pt, out, up, size, skin, col="hd_strap", flap="hd_strap"):
    M = frame(pt, out, up)
    w = skin.fixed(pt)
    sx, sy, sz = size
    piece(h, M, (0, 0, sz / 2), size, col, w, bevel=0.35)
    piece(h, M, (0, sy * 0.28, sz * 0.58), (sx * 1.08, sy * 0.48, sz * 1.04), flap, w, bevel=0.3, taper=(0.96, 0.9))
    h.cyl("Hips", M @ Vector((0, sy * 0.12, sz * 1.08)), M @ Vector((0, sy * 0.12, sz * 1.08 + 0.005)), 0.008, 0.007,
          "hd_buckle", seg=8, weights=w)


def rivet(h, M, c, skin=None, bone="Hips", r=0.0055, col="hd_metal"):
    p = M @ Vector(c)
    h.sphere(bone, p, (r, r, r * 0.6), col, seg=(6, 4), rot=(0, 0, 0), weights=skin.fixed(p) if skin else None)


# ------------------------------------------------------------------ detail kit
def detail_kit(h):
    prep_palette(h)
    c = cfg(h)
    skin = BodySkin(h)
    k = h.d["height"] / 1.85
    right = 1.0 if h.jh("UpperLeg_R").x > 0 else -1.0
    TORSO = ("Hips", "Spine", "Chest", "UpperChest", "Clavicle_L", "Clavicle_R")

    def at_angle(pts, deg):
        """Ring sample nearest the angle (0 front, +90 hero's left)."""
        a = math.radians(deg)
        want = Vector((-right * math.sin(a), math.cos(a), 0))
        return max(pts, key=lambda pd: pd[1].dot(want))

    b = c["belt"]
    if b:
        z = h.jh("Hips").z + 0.075 * k + b["z"] * k
        pts = ring(h, Vector((0, h.jh("Hips").y, z)), (0, 0, 1), ("Hips", "Spine", "UpperLeg_L", "UpperLeg_R"),
                   n=36, off=b["off"])
        strap(h, pts, (0, 0, 1), b["width"] * k, 0.009, "hd_strap", skin)
        if b.get("buckle"):
            p, d = at_angle(pts, 0)
            M = frame(p + d * 0.008, d, Vector((0, 0, 1)))
            piece(h, M, (0, 0, 0.004), (0.07 * k, b["width"] * k * 1.2, 0.012), "hd_buckle", skin.fixed(p), bevel=0.4)
            piece(h, M, (0, 0, 0.011), (0.045 * k, b["width"] * k * 0.6, 0.006), "team", skin.fixed(p), "team_emit",
                  bevel=0.4)
        for ang in b.get("pouches", ()):
            p, d = at_angle(pts, ang)
            pouch(h, p + d * 0.008, d, Vector((0, 0, 1)), (0.075 * k, 0.085 * k, 0.04 * k), skin)
        for ang in range(-150, 180, 60):
            p, d = at_angle(pts, ang + 30)
            rivet(h, frame(p, d, Vector((0, 0, 1))), (0, 0, 0.01), skin)
    if c["bandolier"]:
        ctr = h.jl("Chest", 0.6)
        nrm = Vector((right * 0.62, 0.0, 0.78)).normalized()
        pts = ring(h, ctr, nrm, TORSO, n=40, off=0.008)
        strap(h, pts, nrm, 0.05 * k, 0.008, "hd_strap", skin)
        front = [pd for pd in pts if pd[1].y > 0.35]
        for p, d in front[::2]:
            M = frame(p + d * 0.006, d, nrm)
            piece(h, M, (0, 0, 0.012), (0.018 * k, 0.034 * k, 0.022), "hd_buckle", skin.fixed(p), bevel=0.35)
    if c["holster"]:
        s = c["holster"]
        up = (h.jh("UpperLeg_" + s) - h.jh("LowerLeg_" + s)).normalized()
        for t, wd in ((0.35, 0.035), (0.62, 0.03)):
            pts = ring(h, h.jl("UpperLeg_" + s, t), up, ("UpperLeg_" + s,), n=24, off=0.004)
            strap(h, pts, up, wd * k, 0.007, "hd_strap", skin)
        p, d = max(ring(h, h.jl("UpperLeg_" + s, 0.45), up, ("UpperLeg_" + s,), n=24, off=0.012),
                   key=lambda pd: pd[1].x * (1 if (h.jh("UpperLeg_" + s).x > 0) else -1))
        M = frame(p, d, up)
        w = skin.fixed(p)
        piece(h, M, (0, -0.02, 0.022), (0.075 * k, 0.19 * k, 0.04), "hd_strap", w, bevel=0.35, taper=(0.8, 0.9))
        piece(h, M, (0, 0.09 * k, 0.03), (0.04 * k, 0.07 * k, 0.03), "hd_gun", w, bevel=0.3)  # pistol grip
        piece(h, M, (0, 0.035 * k, 0.045), (0.06 * k, 0.02 * k, 0.012), "hd_buckle", w, bevel=0.4)
    elif c["thigh_straps"]:
        for s in ("L", "R"):
            up = (h.jh("UpperLeg_" + s) - h.jh("LowerLeg_" + s)).normalized()
            pts = ring(h, h.jl("UpperLeg_" + s, 0.5), up, ("UpperLeg_" + s,), n=24, off=0.004)
            strap(h, pts, up, 0.03 * k, 0.007, "hd_strap", skin)
    for s in ("L", "R"):
        if c["bracers"]:
            ax = (h.jt("LowerArm_" + s) - h.jh("LowerArm_" + s)).normalized()
            for t, wd, th, col in ((0.62, 0.075, 0.012, "hd_metal"), (0.86, 0.03, 0.008, "hd_strap")):
                pts = ring(h, h.jl("LowerArm_" + s, t), ax, ("LowerArm_" + s,), n=20, off=0.004, reach=0.3)
                strap(h, pts, ax, wd * k, th, col, skin)
                if col == "hd_metal":
                    for p, d in pts[::5]:
                        rivet(h, frame(p, d, ax), (0, 0, th + 0.002), skin, r=0.005)
                    p, d = max(pts, key=lambda pd: pd[1].z)
                    M = frame(p + d * th, d, ax)
                    piece(h, M, (0, 0, 0.003), (0.03 * k, 0.05 * k, 0.006), "team", skin.fixed(p), "team_emit",
                          bevel=0.4)
        if c["arm_bands"]:
            ax = (h.jt("UpperArm_" + s) - h.jh("UpperArm_" + s)).normalized()
            pts = ring(h, h.jl("UpperArm_" + s, 0.55), ax, ("UpperArm_" + s,), n=20, off=0.004, reach=0.3)
            strap(h, pts, ax, 0.03 * k, 0.007, "hd_strap", skin)
    if c["collar"]:
        ax = (h.jt("Neck") - h.jh("Neck")).normalized()
        pts = ring(h, h.jl("Neck", 0.05), ax, ("Neck", "UpperChest", "Clavicle_L", "Clavicle_R"), n=28, off=0.006,
                   reach=0.4)
        pts = [(p + ax * 0.012, d) for p, d in pts]
        strap(h, pts, ax, 0.055 * k, 0.012, "hd_strap", skin)
    if c["cables"] or c["cell"]:
        zc = h.jl("UpperChest", 0.4).z
        p, n = h.surface(0.0, zc, side=-1)
        M = frame(p, -Vector((0, 1, 0)) if n.y > 0 else n, Vector((0, 0, 1)))
        if c["cell"]:
            w = skin.fixed(p)
            piece(h, M, (0, 0, 0.025), (0.11 * k, 0.17 * k, 0.05), "hd_gun", w, bevel=0.3)
            piece(h, M, (0, 0, 0.052), (0.02 * k, 0.12 * k, 0.008), "team", w, "team_emit", bevel=0.4)
            for sx in (-1, 1):
                for i in range(3):
                    piece(h, M, (sx * 0.035 * k, (i - 1) * 0.035 * k, 0.051), (0.03 * k, 0.012 * k, 0.006), "hd_ink",
                          w, bevel=0.2)
        if c["cables"]:
            for sx in (-1, 1):
                a = M @ Vector((sx * 0.04 * k, -0.07 * k, 0.02))
                pb, nb = h.surface(sx * 0.07 * k, h.jh("Hips").z + 0.12 * k, side=-1)
                bpt = pb + Vector((0, -0.025, 0))
                prev = a
                for i in range(1, 7):
                    t = i / 6
                    q = a.lerp(bpt, t) + Vector((sx * 0.03 * math.sin(t * math.pi), -0.03 * math.sin(t * math.pi), 0))
                    h.cyl("Hips", prev, q, 0.008, 0.008, "hd_ink", seg=6, weights=skin.fixed(prev.lerp(q, 0.5)),
                          caps=False)
                    prev = q
    if c["ear_vents"]:
        hc = h.jl("Head", 0.45)
        bvh = body_bvh(h, ("Head",))
        for sx in (-1, 1):
            d = Vector((sx, 0, 0))
            hit = bvh.ray_cast(hc + d * 0.4 + Vector((0, -0.01, 0)), -d, 0.5)
            if hit[0] is None:
                continue
            p = hit[0]
            h.cyl("Head", p - d * 0.006, p + d * 0.018, 0.034 * k, 0.03 * k, "hd_metal", seg=14)
            h.torus("Head", p + d * 0.018, d, 0.026 * k, 0.005, "hd_gun", seg=(14, 5))
            M = frame(p + d * 0.019, d, Vector((0, 0, 1)))
            for i in range(3):
                piece(h, M, (0, (i - 1) * 0.012 * k, 0.002), (0.03 * k, 0.005, 0.006), "hd_ink", None, bevel=0.2)
            h.cyl("Head", p + d * 0.019 + Vector((0, 0.02, -0.01)), p + d * 0.012 + Vector((0, 0.07, -0.04)),
                  0.004, 0.003, "hd_metal", seg=6)


# ------------------------------------------------------------------ weapon detail
def weapon_detail(h, W):
    prep_palette(h)
    c = cfg(h)["weapon"]
    Wi = W.inverted()
    wi = h.bone_names.index("Weapon")
    P = np.array([tuple(Wi @ v.co) for v in h.pbm.verts if v[h.pdl].get(wi, 0.0) > 0.5])
    if len(P) == 0:
        return
    lo, hi = P.min(axis=0), P.max(axis=0)
    L = hi[1] - lo[1]

    def wb(cc, s, col, ch="flat", **kw):
        h.box("Weapon", None, s, col, ch, mat=W @ Matrix.Translation(Vector(cc)), **kw)

    # Receiver column above the grip: the top surface near y in [0, 0.35 L].
    sel = P[(P[:, 1] > lo[1] + 0.25 * L) & (P[:, 1] < lo[1] + 0.75 * L)]
    top = float(sel[:, 2].max()) if len(sel) else float(hi[2])
    xm = float(np.median(sel[:, 0])) if len(sel) else 0.0
    y0, y1 = lo[1] + 0.3 * L, lo[1] + 0.68 * L
    if c.get("rail", True):
        _rail(wb, h, W, xm, y0, y1, top)
    if c.get("muzzle", True):
        _muzzle(wb, h, W, P, hi)
    _lower(wb, h, W, P, lo, L, sel, top, c)


def _rail(wb, h, W, xm, y0, y1, top):
    wb((xm, (y0 + y1) / 2, top + 0.004), (0.022, y1 - y0, 0.008), "hd_gun", bevel=0.3)
    y = y0 + 0.008
    while y < y1 - 0.006:
        wb((xm, y, top + 0.010), (0.027, 0.0055, 0.006), "hd_gun", bevel=0.0)
        y += 0.0125
    for sx in (-1, 1):  # rear sight posts
        wb((xm + sx * 0.009, y0 + 0.006, top + 0.022), (0.006, 0.01, 0.022), "hd_metal", bevel=0.3)
    wb((xm, y1 - 0.01, top + 0.02), (0.006, 0.012, 0.024), "hd_metal", bevel=0.3, taper=(0.6, 0.6))
    wb((xm, y1 - 0.01, top + 0.034), (0.004, 0.004, 0.004), "team", "team_emit", bevel=0.0)


def _muzzle(wb, h, W, P, hi):
    front = P[P[:, 1] > hi[1] - 0.03]
    mc = front.mean(axis=0)
    r = max(0.012, float(np.max(np.hypot(front[:, 0] - mc[0], front[:, 2] - mc[2]))) * 0.9)
    m0, m1 = W @ Vector((mc[0], hi[1] - 0.01, mc[2])), W @ Vector((mc[0], hi[1] + 0.055, mc[2]))
    h.cyl("Weapon", m0, m1, r * 0.95, r * 0.9, "hd_gun", seg=12)
    for t in (0.25, 0.85):
        h.torus("Weapon", m0.lerp(m1, t), (W.to_3x3() @ Vector((0, 1, 0))), r * 0.95, 0.004, "hd_metal", seg=(12, 4))
    for sx in (-1, 1):
        for i in range(2):
            wb((mc[0] + sx * r * 0.9, hi[1] + 0.012 + i * 0.02, mc[2]), (0.006, 0.01, r * 0.9), "hd_ink", bevel=0.2)


def _lower(wb, h, W, P, lo, L, sel, top, c):
    # Trigger guard under the receiver, ahead of the grip (origin).
    gz = float(P[(np.abs(P[:, 1] - 0.05) < 0.03)][:, 2].min()) if np.any(np.abs(P[:, 1] - 0.05) < 0.03) else -0.03
    wb((0, 0.055, gz - 0.028), (0.012, 0.075, 0.006), "hd_gun", bevel=0.4)
    wb((0, 0.092, gz - 0.014), (0.012, 0.006, 0.03), "hd_gun", bevel=0.4)
    wb((0, 0.045, gz - 0.012), (0.006, 0.008, 0.024), "hd_metal", bevel=0.4)  # trigger
    # Side plates, ejection port, bolt handle.
    for sx in (-1, 1):
        xs = float(sel[:, 0].max() if sx > 0 else sel[:, 0].min()) if len(sel) else sx * 0.03
        wb((xs + sx * 0.002, lo[1] + 0.42 * L, top - 0.03), (0.004, 0.16 * L, 0.03), "hd_metal", bevel=0.35)
        for i in range(3):
            rv = W @ Vector((xs + sx * 0.0045, lo[1] + (0.36 + i * 0.06) * L, top - 0.042))
            h.sphere("Weapon", rv, (0.003, 0.003, 0.003), "hd_buckle", seg=(6, 4))
        if c.get("energy"):
            wb((xs + sx * 0.0045, lo[1] + 0.42 * L, top - 0.018), (0.003, 0.14 * L, 0.004), "team", "team_emit",
               bevel=0.0)
    xs = float(sel[:, 0].max()) if len(sel) else 0.03
    wb((xs + 0.004, lo[1] + 0.55 * L, top - 0.012), (0.004, 0.05, 0.016), "hd_ink", bevel=0.2)
    h.cyl("Weapon", W @ Vector((xs, lo[1] + 0.5 * L, top - 0.012)), W @ Vector((xs + 0.03, lo[1] + 0.5 * L, top - 0.012)),
          0.004, 0.005, "hd_metal", seg=6)


# ------------------------------------------------------------------ modifiers
def harden_parts(ob):
    from build_hero import _activate
    _activate(ob)
    m = ob.modifiers.new("hd_bevel", "BEVEL")
    m.width = 0.0018
    m.segments = 1
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(40)
    m.use_clamp_overlap = True
    bpy.ops.object.modifier_apply(modifier=m.name)
    wn = ob.modifiers.new("hd_wn", "WEIGHTED_NORMAL")
    wn.keep_sharp = True
    bpy.ops.object.modifier_apply(modifier=wn.name)


# ------------------------------------------------------------------ bake
def _classify(h, ob):
    """Face attributes for the bake + channel id moved to Color.a (UV0 becomes real UVs)."""
    from build_hero import CH
    me = ob.data
    c = cfg(h)
    cloth_names = set(CLOTH) | set(c.get("cloth_names", ()))
    names = {tuple(round(x, 3) for x in rgba[:3]): n for rgba, n in h.names.items()}
    anames = ("hd_metal", "hd_cloth", "hd_skin", "hd_emit", "hd_team", "hd_hard")
    for n in anames:  # create first: adding attributes invalidates fetched .data
        me.attributes.new(n, "FLOAT", "FACE")
    attrs = {n: me.attributes[n] for n in anames}
    uvl = me.uv_layers["UVMap"].data
    col = me.color_attributes["Color"].data
    kind = me.attributes["hd_kind"].data if "hd_kind" in me.attributes else None
    cloth_vg = ob.vertex_groups.new(name="hd_clothvg")
    hard_vg = ob.vertex_groups.new(name="hd_hardvg")
    cloth_v, hard_v = set(), set()
    for p in me.polygons:
        li = p.loop_start
        ch = int(uvl[li].uv[0] * 8)
        rgb = tuple(round(x, 3) for x in col[li].color[:3])
        name = names.get(rgb, "")
        kd = kind[p.index].value if kind else 0
        metal = METAL.get(name, 0.15 if kd in (KIND_SHELL, KIND_PART, KIND_WEAPON) else 0.0)
        cl = 1.0 if (name in cloth_names or kd in (KIND_BODY, KIND_SOFT)) and ch != CH["skin"] and name not in METAL else 0.0
        if name in cloth_names or name in NONMETAL:
            metal = 0.0
        if ch == CH["chrome"]:
            metal = 1.0
        vals = {"hd_metal": metal, "hd_cloth": cl, "hd_skin": float(ch == CH["skin"]),
                "hd_emit": float(ch in (CH["emit"], CH["team_emit"])), "hd_team": float(ch in (CH["team"], CH["team_emit"])),
                "hd_hard": float(kd in (KIND_SHELL, KIND_PART, KIND_WEAPON) and cl < 0.5)}
        if kd in (KIND_PART, KIND_WEAPON) and cl < 0.5:
            hard_v.update(p.vertices)
        for n, v in vals.items():
            attrs[n].data[p.index].value = v
        if cl > 0.5:
            cloth_v.update(p.vertices)
        for i in range(li, li + p.loop_total):
            cc = col[i].color
            col[i].color = (cc[0], cc[1], cc[2], (ch + 0.5) / 8.0)
    cloth_vg.add(list(cloth_v), 1.0, "REPLACE")
    hard_vg.add(list(hard_v), 1.0, "REPLACE")
    print("hd: cloth verts %d / %d, groups %s" % (len(cloth_v), len(me.vertices), [g.name for g in ob.vertex_groups][-3:]))


def _unwrap(ob):
    from build_hero import _activate
    _activate(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.0025, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def _node_mat(name, build):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    build(nt, out)
    return m


def _emit_tree(fn):
    """Material whose Emission colour = fn(nt) socket; for EMIT data bakes."""
    def build(nt, out):
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(fn(nt), em.inputs["Color"])
        nt.links.new(em.outputs[0], out.inputs["Surface"])
    return build


def _attr(nt, name, sock="Fac"):
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_name = name
    a.attribute_type = "GEOMETRY"
    return a.outputs[sock]


def _combine(nt, r, g, b):
    c = nt.nodes.new("ShaderNodeCombineXYZ")
    for i, s in enumerate((r, g, b)):
        if isinstance(s, float):
            c.inputs[i].default_value = s
        else:
            nt.links.new(s, c.inputs[i])
    return c.outputs[0]


def _math(nt, op, a, b=None, vec=False):
    n = nt.nodes.new("ShaderNodeVectorMath" if vec else "ShaderNodeMath")
    n.operation = op
    for i, s in enumerate((a, b)):
        if s is None:
            continue
        if isinstance(s, (float, int)):
            n.inputs[i].default_value = s if not vec else (s, s, s)
        else:
            nt.links.new(s, n.inputs[i])
    return n.outputs["Value" if (vec and op in ("DOT_PRODUCT", "LENGTH")) else 0]


def _bake(ob, mat, size, samples=1, kind="EMIT", float_buf=True, selected=None):
    img = bpy.data.images.new("bake_%s" % mat.name, size, size, alpha=False, float_buffer=float_buf)
    img.colorspace_settings.name = "Non-Color"
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    node.interpolation = "Closest"
    for n in mat.node_tree.nodes:
        n.select = False
    node.select = True
    mat.node_tree.nodes.active = node
    sc = bpy.context.scene
    sc.cycles.samples = samples
    sc.render.bake.margin = 6
    sc.render.bake.margin_type = "EXTEND"
    from build_hero import _activate
    if selected is not None:
        _activate(selected)
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.bake(type=kind, use_selected_to_active=True, cage_extrusion=0.006, max_ray_distance=0.02,
                            normal_space="TANGENT")
    else:
        _activate(ob)
        bpy.ops.object.bake(type=kind)
    a = np.array(img.pixels[:], dtype=np.float32).reshape(size, size, 4)[::-1]
    return a


def _high(ob):
    """High-poly copy: chamfer rounding, subdivision and cloth folds (Displace)."""
    from build_hero import _activate
    hi = ob.copy()
    hi.data = ob.data.copy()
    hi.name = ob.name + "_high"
    bpy.context.scene.collection.objects.link(hi)
    for mod in list(hi.modifiers):
        hi.modifiers.remove(mod)
    _activate(hi)
    bv = hi.modifiers.new("b", "BEVEL")
    bv.width, bv.segments, bv.limit_method, bv.angle_limit = 0.0035, 3, "ANGLE", math.radians(35)
    bv.use_clamp_overlap = True
    bv.vertex_group = "hd_hardvg"  # chamfers on hard parts only; organic shells keep their shape
    sd = hi.modifiers.new("s", "SUBSURF")
    sd.subdivision_type, sd.levels, sd.render_levels = "SIMPLE", 1, 1
    tex = bpy.data.textures.new("folds", "CLOUDS")
    tex.noise_scale = 0.06
    tex.noise_depth = 2
    dp = hi.modifiers.new("d", "DISPLACE")
    dp.texture, dp.strength, dp.mid_level, dp.vertex_group = tex, 0.006, 0.5, "hd_clothvg"
    dp.texture_coords = "OBJECT"
    for m in list(hi.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    return hi


def _detail_bump(nt, out):
    """High-poly material: panel lines + rivets on hard surface, seams + weave on cloth."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
    groove = nt.nodes.new("ShaderNodeMapRange")
    groove.inputs[1].default_value, groove.inputs[2].default_value = 0.0, 0.035
    groove.inputs[3].default_value, groove.inputs[4].default_value = 0.0, 1.0
    nt.links.new(vor.outputs["Distance"], groove.inputs[0])
    riv = nt.nodes.new("ShaderNodeTexVoronoi")
    riv.inputs["Scale"].default_value = 30.0
    nt.links.new(tc.outputs["Object"], riv.inputs["Vector"])
    dome = nt.nodes.new("ShaderNodeMapRange")
    dome.inputs[1].default_value, dome.inputs[2].default_value = 0.0, 0.12
    dome.inputs[3].default_value, dome.inputs[4].default_value = 1.0, 0.0
    nt.links.new(riv.outputs["Distance"], dome.inputs[0])
    hard = _math(nt, "MULTIPLY", _attr(nt, "hd_hard"), 1.0)
    hard_h = _math(nt, "ADD", _math(nt, "MULTIPLY", groove.outputs[0], 1.0), _math(nt, "MULTIPLY", dome.outputs[0], 0.6))
    seam = nt.nodes.new("ShaderNodeTexVoronoi")
    seam.feature = "DISTANCE_TO_EDGE"
    seam.inputs["Scale"].default_value = 2.5
    nt.links.new(tc.outputs["Object"], seam.inputs["Vector"])
    sm = nt.nodes.new("ShaderNodeMapRange")
    sm.inputs[1].default_value, sm.inputs[2].default_value = 0.0, 0.02
    sm.inputs[3].default_value, sm.inputs[4].default_value = 0.0, 1.0
    nt.links.new(seam.outputs["Distance"], sm.inputs[0])
    weave = nt.nodes.new("ShaderNodeTexNoise")
    weave.inputs["Scale"].default_value = 260.0
    nt.links.new(tc.outputs["Object"], weave.inputs["Vector"])
    cloth_h = _math(nt, "ADD", sm.outputs[0], _math(nt, "MULTIPLY", weave.outputs["Fac"], 0.25))
    height = _math(nt, "ADD", _math(nt, "MULTIPLY", hard_h, _math(nt, "MINIMUM", hard, 1.0)),
                   _math(nt, "MULTIPLY", cloth_h, _attr(nt, "hd_cloth")))
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.55
    bump.inputs["Distance"].default_value = 0.0012
    nt.links.new(height, bump.inputs["Height"])
    bsdf = nt.nodes.new("ShaderNodeBsdfDiffuse")
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])


# numpy procedural noise for the hand-painted composite
def _vnoise(P):
    i = np.floor(P)
    f = P - i
    f = f * f * (3 - 2 * f)

    def hsh(a):
        return np.modf(np.sin(a[..., 0] * 127.1 + a[..., 1] * 311.7 + a[..., 2] * 74.7) * 43758.5453)[0] % 1.0
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * \
                    (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * np.abs(hsh(i + np.array([dx, dy, dz])))
    return out


def _fbm(P, octaves=3):
    s, a, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        s = s + a * _vnoise(P * (2.0 ** o) + o * 17.0)
        tot += a
        a *= 0.5
    return s / tot


def bake_textures(h, ob, out_dir, size=1024):
    """Unwraps `ob`, bakes the data passes and writes <key>_albedo/_normal/_mask.png."""
    from PIL import Image
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(me)
    bm.free()
    me.validate(clean_customdata=False)
    _classify(h, ob)
    _unwrap(ob)
    H = h.d["height"]
    S = size * 2  # supersampled data passes, filtered down
    col = _bake(ob, _node_mat("c", _emit_tree(lambda nt: _attr(nt, "Color", "Color"))), S)
    mat = _bake(ob, _node_mat("m", _emit_tree(lambda nt: _combine(nt, _attr(nt, "hd_metal"), _attr(nt, "hd_cloth"),
                                                                     _attr(nt, "hd_skin")))), S)
    et = _bake(ob, _node_mat("e", _emit_tree(lambda nt: _combine(nt, _attr(nt, "hd_emit"), _attr(nt, "hd_team"), 0.0))), S)

    def ao_edge(nt):
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.samples = 16
        ao.inputs["Distance"].default_value = 0.09
        bev = nt.nodes.new("ShaderNodeBevel")
        bev.samples = 8
        bev.inputs["Radius"].default_value = 0.005
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        d = _math(nt, "DOT_PRODUCT", bev.outputs[0], geo.outputs["Normal"], vec=True)
        edge = _math(nt, "SUBTRACT", 1.0, d)
        # convex vs concave: sign via pointiness (Cycles curvature attribute)
        return _combine(nt, ao.outputs["AO"], edge, geo.outputs["Pointiness"])
    aoe = _bake(ob, _node_mat("a", _emit_tree(ao_edge)), S, samples=12)

    def pos(nt):
        tc = nt.nodes.new("ShaderNodeTexCoord")
        return tc.outputs["Object"]
    P = _bake(ob, _node_mat("p", _emit_tree(pos)), S)

    def wn(nt):
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        return geo.outputs["Normal"]
    N = _bake(ob, _node_mat("n", _emit_tree(wn)), S)
    print("hd: groups before high", [g.name for g in ob.vertex_groups][-2:])
    hi = _high(ob)
    hi.data.materials.clear()
    hi.data.materials.append(_node_mat("hi", _detail_bump))
    lowmat = _node_mat("nrm", lambda nt, out: nt.links.new(nt.nodes.new("ShaderNodeBsdfDiffuse").outputs[0],
                                                          out.inputs["Surface"]))
    nrm = _bake(ob, lowmat, size, samples=1, kind="NORMAL", selected=hi)
    bpy.data.objects.remove(hi, do_unlink=True)

    dbg = os.environ.get("HERO_DEBUG")
    if dbg:
        np.savez_compressed(os.path.join(dbg, h.key + "_passes.npz"), col=col, mat=mat, et=et, aoe=aoe, P=P, N=N,
                            nrm=nrm)
    return composite(h, out_dir, size, col, mat, et, aoe, P, N, nrm, ob)


def composite(h, out_dir, size, col, mat, et, aoe, P, N, nrm, ob=None):
    """Hand-painted albedo + packed mask from the data passes (numpy); writes the PNGs."""
    from PIL import Image
    H = h.d["height"] if hasattr(h, "d") else h["height"]
    base = col[..., :3]
    metal, cloth, skin = mat[..., 0], mat[..., 1], mat[..., 2]
    emit, team = et[..., 0], et[..., 1]
    from PIL import ImageFilter
    ao_im = Image.fromarray((np.clip(aoe[..., 0], 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.0))
    ao = np.sqrt(np.asarray(ao_im, dtype=np.float32) / 255.0)
    edge = np.clip((aoe[..., 1] - 0.08) / 0.2, 0, 1)
    convex = np.clip((aoe[..., 2] - 0.5) * 6 + 0.5, 0, 1)
    p3 = P[..., :3]
    z = p3[..., 2] / H
    nz = N[..., 2]
    hard = np.clip(1 - cloth - skin, 0, 1)
    grad = (0.84 + 0.22 * np.clip(z, 0, 1)) * (0.94 + 0.08 * nz)
    stroke = 0.94 + 0.12 * _fbm(p3 * 3.0, 3)  # broad painterly value variation
    weave = 0.96 + 0.06 * _fbm(p3 * 90.0, 2)
    alb = base * (grad * stroke * np.where(cloth > 0.5, weave, 1.0))[..., None]
    alb *= (0.55 + 0.45 * ao + skin * (1 - ao) * 0.2)[..., None]
    hl = edge * convex * (0.32 * hard + 0.10 * cloth)
    alb = alb + (1.0 - alb) * hl[..., None]
    wn_ = _fbm(p3 * 16.0, 4)
    wear = np.clip((wn_ - 0.6) * 8, 0, 1) * edge * np.clip(metal * 1.5, 0, 1)
    scr = (np.abs(np.sin(p3[..., 0] * 61 + p3[..., 2] * 23 + _fbm(p3 * 5.0, 2) * 9)) < 0.05) * \
          (_fbm(p3 * 7.0 + 3.0, 2) > 0.58) * metal
    steel = np.array([0.80, 0.82, 0.85])
    alb = alb + (steel - alb) * (np.clip(wear * 0.55 + scr * 0.12, 0, 1))[..., None]
    alb = np.where(emit[..., None] > 0.5, base * (0.9 + 0.1 * stroke[..., None]), alb)
    alb = np.clip(alb, 0, 1)
    spec = np.clip(metal * (0.55 + 0.45 * edge) + wear * 0.4, 0, 1)
    mask = np.stack([ao, spec, emit, team], axis=-1)

    def save(a, path, sz, mode):
        u8 = (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
        # Per-channel resize: PIL premultiplies RGBA by alpha when resampling.
        bands = [Image.fromarray(u8[..., i], "L") for i in range(u8.shape[-1])]
        if bands[0].size[0] != sz:
            bands = [b.resize((sz, sz), Image.LANCZOS) for b in bands]
        im = Image.merge(mode, bands)
        im.save(path, optimize=True)
        return os.path.getsize(path)

    key = h.key if hasattr(h, "key") else h["key"]
    sizes = {
        "albedo": save(alb, os.path.join(out_dir, key + "_albedo.png"), size, "RGB"),
        "mask": save(mask, os.path.join(out_dir, key + "_mask.png"), size // 2, "RGBA"),
        "normal": save(nrm[..., :3], os.path.join(out_dir, key + "_normal.png"), size, "RGB"),
    }
    if ob is None:
        return sizes
    # The bake attributes / helper group are not exported.
    me = ob.data
    for n in ("hd_metal", "hd_cloth", "hd_skin", "hd_emit", "hd_team", "hd_hard", "hd_kind"):
        if n in me.attributes:
            me.attributes.remove(me.attributes[n])
    for vg in ("hd_clothvg", "hd_hardvg"):
        if vg in ob.vertex_groups:
            ob.vertex_groups.remove(ob.vertex_groups[vg])
    ob.data.materials.clear()
    return sizes


def smooth_shells(h, iters=8):
    """Relaxes the armour shells (hd_kind 1) and the body surface normals so the
    higher HD poly budget does not carry anatomical bumps into the 2-band cel ramp."""
    me = h.body.data
    bm = bmesh.new()
    bm.from_mesh(me)
    kl = bm.faces.layers.int.get("hd_kind")
    shell_v = list({v for f in bm.faces if f[kl] == 1 for v in f.verts})
    for _ in range(iters):
        old = {v: (v.co.copy(), v.normal.copy()) for v in shell_v}
        bmesh.ops.smooth_vert(bm, verts=shell_v, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
        for v in shell_v:  # volume preserving: undo the inward (shrinking) part of the move
            co, n = old[v]
            s = (v.co - co).dot(n)
            if s < 0:
                v.co -= n * s
        bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.update()


# ------------------------------------------------------------------ secondary (spring) bones
# Contract: design/art/secondary-motion.md (W14-P2). Bones Sec_<part>[_<side>]_<n>, root parented
# to a body bone, skinned to the dangling geometry, never keyed by the clips.
def _sec_specs(h):
    k = h.d["height"] / 1.85
    neck = h.jh("Neck").z
    hips = h.jh("Hips").z
    back = lambda co: co.y < h.surface(co.x, co.z, side=-1)[0].y - 0.05 * k

    def sel(names=None, bones=None, extra=None):
        def f(co, name, dom):
            return ((names is None or name in names) and (bones is None or dom in bones)
                    and (extra is None or extra(co)))
        return f
    S = {
        "vesper": [("Sec_coat_L", "Hips", 3, "top", sel({"plum", "gold"}, {"Hips", "UpperLeg_L", "UpperLeg_R"},
                                                        lambda co: co.z < hips and co.x < -0.05 * k and back(co))),
                   ("Sec_coat_B", "Hips", 3, "top", sel({"plum", "gold"}, {"Hips", "UpperLeg_L", "UpperLeg_R"},
                                                        lambda co: co.z < hips and abs(co.x) <= 0.05 * k and back(co))),
                   ("Sec_coat_R", "Hips", 3, "top", sel({"plum", "gold"}, {"Hips", "UpperLeg_L", "UpperLeg_R"},
                                                        lambda co: co.z < hips and co.x > 0.05 * k and back(co)))],
        "liora": [("Sec_halo_1", "UpperChest", 1, "bottom", sel({"chrome", "team"}, {"UpperChest"},
                                                               lambda co: co.y < h.jh("UpperChest").y - 0.12 * k)),
                  ("Sec_coat_B", "Hips", 2, "top", sel({"ivory", "sage"}, {"Hips", "UpperLeg_L", "UpperLeg_R"},
                                                       lambda co: co.y < -0.08 * k and co.z < hips))],
        "hex": [("Sec_antenna_L", "Head", 2, "bottom", sel({"chrome", "team"}, {"Head"},
                                                           lambda co: co.z > neck + 0.2 * k and co.x * _lx(h) > 0.04)),
                ("Sec_antenna_R", "Head", 2, "bottom", sel({"chrome", "team"}, {"Head"},
                                                           lambda co: co.z > neck + 0.2 * k and co.x * _lx(h) < -0.04))],
        "juniper": [("Sec_pack_1", "UpperChest", 1, "top", sel({"mustard", "olive", "team", "chrome", "lime"}, None,
                                                              lambda co: back(co) and co.z > hips))],
        "sable": [("Sec_strap_L", "UpperChest", 4, "top", sel(None, None, lambda co: back(co) and co.x * _lx(h) > 0
                                                              and hips - 0.3 * k < co.z < neck)),
                  ("Sec_strap_R", "UpperChest", 4, "top", sel(None, None, lambda co: back(co) and co.x * _lx(h) <= 0
                                                              and hips - 0.3 * k < co.z < neck))],
        "ryker": [("Sec_antenna_1", "Clavicle_L", 2, "bottom", sel({"olive", "team"}, {"Clavicle_L"}, _ryker_fin(h, k)))],
        "brannoc": [],
    }
    return S.get(h.key, [])


def _ryker_fin(h, k):
    """The antenna fin on Ryker's left pauldron (hero_defs.ryker_parts)."""
    pc = h.jh("UpperArm_L") + Vector((-0.02, -0.005, 0.045)) * k
    fin = pc + Vector((-0.04, 0.0, 0.11)) * k
    return lambda co: abs(co.x - fin.x) < 0.05 * k and abs(co.y - fin.y) < 0.06 * k and co.z > pc.z + 0.035 * k


def _islands(vs, min_frac=0.25):
    """Expands a vertex selection to the connected islands it touches (>= min_frac selected)."""
    sel = set(vs)
    seen, out = set(), []
    for v0 in vs:
        if v0 in seen:
            continue
        isl, stack = [], [v0]
        seen.add(v0)
        while stack:
            v = stack.pop()
            isl.append(v)
            for e in v.link_edges:
                o = e.other_vert(v)
                if o not in seen:
                    seen.add(o)
                    stack.append(o)
        if sum(1 for v in isl if v in sel) >= min_frac * len(isl):
            out += isl
    return out


def _lx(h):
    """+1 if the hero's left is +X."""
    return 1.0 if h.jh("UpperLeg_L").x > 0 else -1.0


def add_secondary(h):
    """Fits Sec_ chains to the selected part geometry and re-skins it (call before finish_parts)."""
    bm, dl, cl = h.pbm, h.pdl, h.pcol
    names = h.bone_names
    rgb_name = {tuple(round(x, 3) for x in c[:3]): n for c, n in h.names.items()}
    vname = {}
    for f in bm.faces:
        n = rgb_name.get(tuple(round(x, 3) for x in f.loops[0][cl][:3]), "")
        for v in f.verts:
            vname.setdefault(v, n)
    made = []
    for chain, parent, nb, root_mode, pred in _sec_specs(h):
        vs = []
        for v in bm.verts:
            w = v[dl]
            if not w:
                continue
            dom = names[max(w.keys(), key=lambda g: w[g])]
            if dom.startswith("Sec_") or dom == "Weapon":
                continue
            if pred(v.co, vname.get(v, ""), dom):
                vs.append(v)
        vs = _islands(vs)  # whole connected pieces, never a torn partial selection
        if len(vs) < 8:
            print("hd: secondary %s skipped (%d verts)" % (chain, len(vs)))
            continue
        P = np.array([tuple(v.co) for v in vs])
        r = P[np.argmax(P[:, 2])] if root_mode == "top" else P[np.argmin(P[:, 2])]
        root = Vector(P[np.argsort(np.abs(P[:, 2] - r[2]))[:max(3, len(P) // 20)]].mean(axis=0))
        tip = Vector(P[np.argmax(np.linalg.norm(P - np.array(root), axis=1))])
        L = (tip - root).length
        if L < 0.04:
            continue
        d = (tip - root).normalized()
        pts = [root + d * (L * i / nb) for i in range(nb + 1)]
        bnames = ["%s_%d" % (chain, i + 1) for i in range(nb)]
        for i, bn in enumerate(bnames):
            h.joints[bn] = (pts[i], pts[i + 1])
            h.parent[bn] = parent if i == 0 else bnames[i - 1]
            h.bone_names.append(bn)
        for v in vs:
            s = max(0.0, min(0.999, (v.co - root).dot(d) / L))
            fb = s * nb
            i = int(fb)
            fr = fb - i
            new = {h.bone_names.index(bnames[i]): 1.0}
            if fr > 0.7 and i + 1 < nb:
                t = (fr - 0.7) / 0.3
                new = {h.bone_names.index(bnames[i]): 1.0 - 0.5 * t, h.bone_names.index(bnames[i + 1]): 0.5 * t}
            if s < 0.15:  # soft root: blend with the original (body) weights
                t = s / 0.15
                old = dict(v[dl])
                new = {g: w * t for g, w in new.items()}
                for g, w in old.items():
                    new[g] = new.get(g, 0.0) + w * (1.0 - t)
            top = sorted(new.items(), key=lambda x: -x[1])[:4]
            tot = sum(w for _, w in top) or 1.0
            v[dl].clear()
            for g, w in top:
                v[dl][g] = w / tot
        made.append("%s x%d (%d verts, %.2f m)" % (chain, nb, len(vs), L))
    print("hd: secondary chains:", made)
    return made
