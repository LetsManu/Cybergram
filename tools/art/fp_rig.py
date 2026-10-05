"""W19-VM first-person rig: hands with real fingers, gloves and sleeves, the hero's
own weapon at FP detail, an FP skeleton and the pose solver used by fp_anims.py.

Space: Blender eye space (eye at the origin, X right, Y forward, Z up), metres.
Skeleton (37 bones): Root; Weapon (+ Mag, the reload part); per side LowerArm_s,
Hand_s and three bones per finger (Thumb1..3, Index1..3, Middle1..3, Ring1..3,
Pinky1..3). Upper arms are off screen: the forearm is solved from a fixed
shoulder with analytic two-bone IK, so the hands can go anywhere.

Hand canon (right hand): wrist at the origin, fingers +Y, back of the hand +Z,
thumb on -X. The left hand is the mirror (x -> -x). Every bone frame is
right-handed with Z = back of the finger, so a curl is a rotation about local X
(negative = toward the palm) on both sides.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

from build_hero import CH, Hero, _activate, _paint_face, srgb

KIND_PART, KIND_WEAPON, KIND_SOFT = 2, 3, 4
UPPER_ARM = 0.30
FOREARM = 0.265
SHOULDER = {"R": Vector((0.19, -0.07, -0.26)), "L": Vector((-0.19, -0.07, -0.26))}
POLE = {"R": Vector((0.7, -0.2, -1.0)), "L": Vector((-0.7, -0.2, -1.0))}
FINGERS = ["Thumb", "Index", "Middle", "Ring", "Pinky"]
# name: (base, direction, phalanx lengths, radius); canonical right hand at scale 1.
FINGER_SPEC = {
    "Index": ((-0.026, 0.086, 0.003), (-0.10, 1.0, 0.0), (0.040, 0.025, 0.021), 0.0098),
    "Middle": ((-0.008, 0.090, 0.004), (-0.02, 1.0, 0.0), (0.044, 0.028, 0.022), 0.0102),
    "Ring": ((0.010, 0.086, 0.003), (0.06, 1.0, 0.0), (0.041, 0.026, 0.021), 0.0097),
    "Pinky": ((0.0265, 0.076, 0.0), (0.16, 1.0, 0.0), (0.032, 0.021, 0.018), 0.0088),
    "Thumb": ((-0.022, 0.022, -0.012), (-0.72, 0.60, -0.30), (0.036, 0.031, 0.026), 0.0112),
}
THUMB_UP = Vector((-0.50, -0.10, 0.86))
MAX_CURL = {"Thumb": (40, 55, 60), "Index": (85, 100, 75), "Middle": (90, 100, 75), "Ring": (90, 100, 75),
            "Pinky": (90, 100, 75)}
# Finger shapes (curl degrees per joint) for the free hand.
SHAPES = {
    "open": {"Thumb": (0, 0, 0), "Index": (2, 3, 2), "Middle": (2, 3, 2), "Ring": (3, 4, 2), "Pinky": (4, 4, 2)},
    "relax": {"Thumb": (8, 12, 10), "Index": (14, 20, 12), "Middle": (20, 26, 14), "Ring": (26, 30, 16),
              "Pinky": (32, 32, 18)},
    "fist": {"Thumb": (25, 40, 40), "Index": (85, 100, 70), "Middle": (88, 100, 70), "Ring": (90, 100, 70),
             "Pinky": (90, 100, 70)},
    "conduct": {"Thumb": (18, 26, 20), "Index": (4, 6, 3), "Middle": (10, 12, 6), "Ring": (55, 72, 50),
                "Pinky": (62, 78, 55)},
    "pinch": {"Thumb": (30, 30, 28), "Index": (38, 48, 30), "Middle": (45, 55, 30), "Ring": (55, 62, 35),
              "Pinky": (60, 66, 38)},
    "claw": {"Thumb": (15, 30, 30), "Index": (30, 45, 40), "Middle": (32, 46, 40), "Ring": (34, 48, 40),
             "Pinky": (36, 50, 40)},
    "spread": {"Thumb": (-5, 0, 0), "Index": (-4, 0, 0), "Middle": (-4, 0, 0), "Ring": (-4, 0, 0),
               "Pinky": (-4, 0, 0)},
}
SPREAD_DEG = {"Thumb": 10.0, "Index": 7.0, "Middle": 0.0, "Ring": -6.0, "Pinky": -12.0}


def frame(y, z):
    """3x3 with Y along `y`, Z = `z` made orthogonal, X = Y x Z."""
    y = Vector(y).normalized()
    z = Vector(z)
    z = (z - y * y.dot(z)).normalized()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed()


def mat(pos, y, z):
    M = frame(y, z).to_4x4()
    M.translation = Vector(pos)
    return M


def euler_deg(rx, ry, rz):
    """Pitch (about X), roll (about Y), yaw (about Z), applied yaw * pitch * roll."""
    return (Matrix.Rotation(math.radians(rz), 4, "Z") @ Matrix.Rotation(math.radians(rx), 4, "X")
            @ Matrix.Rotation(math.radians(ry), 4, "Y"))


def bone_list():
    names = ["Root", "Weapon", "Mag"]
    for s in ("R", "L"):
        names += ["LowerArm_" + s, "Hand_" + s]
        for f in FINGERS:
            names += ["%s%d_%s" % (f, i, s) for i in (1, 2, 3)]
    return names


def parent_of(b):
    if b == "Root":
        return None
    if b in ("Weapon",) or b.startswith("LowerArm"):
        return "Root"
    if b == "Mag":
        return "Weapon"
    s = b[-1]
    if b.startswith("Hand"):
        return "LowerArm_" + s
    i = int(b[-3])
    return "Hand_" + s if i == 1 else "%s%d_%s" % (b[:-3], i - 1, s)


# ------------------------------------------------------------------ canonical hand
class Canon:
    """Canonical hand + forearm for one side at `scale`: finger chains (rest, straight)."""

    def __init__(self, side, scale):
        self.side, self.s = side, scale
        m = -1.0 if side == "L" else 1.0
        self.m = m
        self.fingers = {}
        for f, (base, d, lens, r) in FINGER_SPEC.items():
            b = Vector((base[0] * m, base[1], base[2])) * scale
            dv = Vector((d[0] * m, d[1], d[2])).normalized()
            up = Vector((THUMB_UP.x * m, THUMB_UP.y, THUMB_UP.z)) if f == "Thumb" else Vector((0, 0, 1))
            up = (up - dv * dv.dot(up)).normalized()
            self.fingers[f] = (b, dv, up, [x * scale for x in lens], r * scale)

    def bones(self):
        """name -> (head, tail, z) in the canonical frame."""
        s, side = self.s, self.side
        out = {"LowerArm_" + side: (Vector((0, -FOREARM, 0)), Vector((0, 0, 0)), Vector((0, 0, 1))),
               "Hand_" + side: (Vector((0, 0, 0)), Vector((0, 0.09 * s, 0)), Vector((0, 0, 1)))}
        for f, (b, d, up, lens, _r) in self.fingers.items():
            p = b.copy()
            for i, L in enumerate(lens):
                out["%s%d_%s" % (f, i + 1, side)] = (p.copy(), p + d * L, up.copy())
                p = p + d * L
        return out

    def chain_points(self, f, H, angles):
        """Joint and tip positions of finger `f` under hand matrix H with curl `angles` (deg)."""
        b, d, up, lens, r = self.fingers[f]
        x = d.cross(up)
        pts = [b.copy()]
        A = 0.0
        for a, L in zip(angles, lens):
            A += math.radians(a)
            seg = d * math.cos(A) - up * math.sin(A)
            pts.append(pts[-1] + seg * L)
        return [H @ p for p in pts], r, x


def rbox_sdf(p, shapes):
    """Signed distance to the union of rounded boxes (centre, size, rx deg, radius)."""
    best = 1e9
    for c, size, rx, rad in shapes:
        R = Matrix.Rotation(math.radians(rx), 3, "X")
        q = R.transposed() @ (p - Vector(c))
        e = Vector(size) * 0.5 - Vector((rad, rad, rad))
        d = Vector((abs(q.x) - e.x, abs(q.y) - e.y, abs(q.z) - e.z))
        out = Vector((max(d.x, 0), max(d.y, 0), max(d.z, 0))).length
        best = min(best, out + min(max(d.x, d.y, d.z), 0.0) - rad)
    return best


def solve_grip(canon, G, shapes, extra=None):
    """Curl each finger joint (base first) until the finger touches the grip shapes.
    G = hand matrix in weapon space. Returns {finger: (a0, a1, a2)} in degrees."""
    out = {}
    for f in FINGERS:
        ang = [0.0, 0.0, 0.0]
        for j in range(3):
            lim = MAX_CURL[f][j]
            a = 0.0
            while a < lim:
                ang[j] = a + 3.0
                pts, r, _x = canon.chain_points(f, G, ang)
                hit = False
                for k in range(j, 3):
                    for t in (0.35, 0.7, 1.0):
                        if rbox_sdf(pts[k].lerp(pts[k + 1], t), shapes) < r * 0.85:
                            hit = True
                            break
                    if hit:
                        break
                if hit:
                    break
                a += 3.0
            ang[j] = a
        if extra and f in extra:
            ang = [a + e for a, e in zip(ang, extra[f])]
        out[f] = tuple(ang)
    return out


# ------------------------------------------------------------------ geometry
def ring(c, X, Z, rx, rz, n=12, p=2.6, bump=0.0, flat_bottom=0.0):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        ca, sa = math.cos(a), math.sin(a)
        x = math.copysign(abs(ca) ** (2 / p), ca) * rx
        z = math.copysign(abs(sa) ** (2 / p), sa) * rz
        if sa > 0 and bump:
            z += bump * sa ** 6
        if sa < 0 and flat_bottom:
            z *= 1.0 - flat_bottom
        pts.append(c + X * x + Z * z)
    return pts


class MeshAdder:
    """Writes skinned, painted geometry straight into the Hero part bmesh."""

    def __init__(self, h):
        self.h = h

    def add(self, verts, faces, weights, color, ch="flat", kind=KIND_SOFT):
        h = self.h
        bm = h.pbm
        vs = []
        for co, w in zip(verts, weights):
            v = bm.verts.new(co)
            for b, x in w.items():
                v[h.pdl][h.bone_names.index(b)] = x
            vs.append(v)
        for f in faces:
            try:
                nf = bm.faces.new([vs[i] for i in f])
            except ValueError:
                continue
            nf.smooth = True
            nf[h.pkind] = kind
            _paint_face(nf, h.pcol, h.puv, h.color(color), ch)

    def loft(self, rings, weights, color, ch="flat", cap0=False, cap1=False, M=None, kind=KIND_SOFT, tip=None,
             flip=False):
        """Rings (lists of n points) joined into a tube; optional fan caps / a tip point.
        Normals point out for rings stepping along +Y of their frame; `flip` for -Y."""
        n = len(rings[0])
        verts, wts, faces = [], [], []
        for r, w in zip(rings, weights):
            verts += r
            wts += [w] * n
        for i in range(len(rings) - 1):
            for k in range(n):
                a, b = i * n + k, i * n + (k + 1) % n
                faces.append((a, b, b + n, a + n) if flip else (a, a + n, b + n, b))
        if cap0:
            c = sum(rings[0], Vector()) / n
            verts.append(c)
            wts.append(weights[0])
            ci = len(verts) - 1
            faces += [(ci, k, (k + 1) % n) for k in range(n)]
        if tip is not None or cap1:
            c = tip if tip is not None else sum(rings[-1], Vector()) / n
            verts.append(c)
            wts.append(weights[-1])
            ci = len(verts) - 1
            o = (len(rings) - 1) * n
            faces += [(o + (k + 1) % n, o + k, ci) for k in range(n)]
        if M is not None:
            verts = [M @ v for v in verts]
        self.add(verts, faces, wts, color, ch, kind)


class ArmBuilder:
    """Glove, fingers, cuff and sleeve of one side, built in the hand canon and placed by `Hrest`."""

    def __init__(self, h, canon, Hrest, arm, adder):
        self.h, self.c, self.H, self.arm, self.a = h, canon, Hrest, arm, adder
        self.side = canon.side

    def b(self, name):
        return name + "_" + self.side

    def build(self):
        s, m, side = self.c.s, self.c.m, self.side
        glove = self.arm["glove"]
        X, Z = Vector((1, 0, 0)), Vector((0, 0, 1))
        hand, fore = self.b("Hand"), self.b("LowerArm")
        # Palm: superellipse loft from the wrist to the knuckles, capped.
        st = [(-0.014, 0.029, 0.019, 0.0, {fore: 0.5, hand: 0.5}), (0.012, 0.036, 0.020, 0.0, {hand: 1.0}),
              (0.042, 0.044, 0.019, 0.002, {hand: 1.0}), (0.072, 0.046, 0.017, 0.003, {hand: 1.0}),
              (0.090, 0.044, 0.014, 0.003, {hand: 1.0})]
        rings = [ring(Vector((m * 0.0015 * s, y * s, -0.002 * s)), X, Z, rx * s, rz * s, 14, 2.8, bump * s, 0.25)
                 for y, rx, rz, bump, _w in st]
        self.a.loft(rings, [w for *_x, w in st], glove, cap1=True, M=self.H)
        # Thenar pad (thumb muscle under the glove).
        t = bmesh.new()
        bmesh.ops.create_uvsphere(t, u_segments=12, v_segments=8, radius=1.0)
        T = Matrix.Translation(Vector((m * -0.024, 0.036, -0.007)) * s) @ Matrix.Diagonal((0.017 * s, 0.032 * s,
                                                                                            0.014 * s, 1))
        thumb1 = "Thumb1_" + side
        self.a.add([self.H @ (T @ v.co) for v in t.verts], [[v.index for v in f.verts] for f in t.faces],
                   [{hand: 0.6, thumb1: 0.4}] * len(t.verts), glove)
        t.free()
        for f in FINGERS:
            self.finger(f, glove)
        # Knuckle plate (glove armour) on the back of the hand.
        if self.arm.get("plate"):
            self.box(hand, Vector((m * -0.002, 0.066, 0.018)) * s, Vector((0.07, 0.034, 0.008)) * s, self.arm["plate"],
                     "flat", tilt=-8)
            for k in range(4):
                fx = FINGER_SPEC[FINGERS[k + 1]][0][0]
                self.box(hand, Vector((m * fx, 0.088, 0.015)) * s, Vector((0.014, 0.012, 0.007)) * s,
                         self.arm["plate"], "flat")
        self.forearm(glove)
        extras = self.arm.get("extras")
        if extras:
            extras(self.h, side, self)

    def box(self, bone, c, size, color, ch, tilt=0.0, weights=None):
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        for v in t.verts:
            v.co = Vector((v.co.x * size.x, v.co.y * size.y, v.co.z * size.z))
        bmesh.ops.bevel(t, geom=t.edges[:] + t.verts[:], offset=0.35 * 0.5 * min(size), offset_type="OFFSET",
                        segments=2, affect="EDGES", profile=0.5)
        M = self.H @ Matrix.Translation(c) @ Matrix.Rotation(math.radians(tilt), 4, "X")
        self.a.add([M @ v.co for v in t.verts], [[v.index for v in f.verts] for f in t.faces],
                   [weights or {bone: 1.0}] * len(t.verts), color, ch, KIND_PART)
        t.free()

    def finger(self, f, color):
        b, d, up, lens, r = self.c.fingers[f]
        x = d.cross(up)
        side = self.side
        names = ["%s%d_%s" % (f, i, side) for i in (1, 2, 3)]
        L0, L1, L2 = lens
        hand = self.b("Hand")
        st = [(-0.010, 1.04, {hand: 0.7, names[0]: 0.3}, 0.0), (L0 * 0.45, 1.0, {names[0]: 1.0}, 0.0),
              (L0, 0.97, {names[0]: 0.5, names[1]: 0.5}, 0.14), (L0 + L1 * 0.5, 0.92, {names[1]: 1.0}, 0.0),
              (L0 + L1, 0.9, {names[1]: 0.5, names[2]: 0.5}, 0.12), (L0 + L1 + L2 * 0.5, 0.86, {names[2]: 1.0}, 0.0),
              (L0 + L1 + L2 - r * 0.55, 0.78, {names[2]: 1.0}, 0.0)]
        rings = [ring(b + d * dist, x, up, r * k, r * k * 0.88, 10, 2.4, r * bump) for dist, k, _w, bump in st]
        tip = b + d * (L0 + L1 + L2 + r * 0.12) - up * r * 0.15
        self.a.loft(rings, [w for _d, _k, w, _b in st], color, M=self.H, tip=tip)

    def ring_on(self, f, seg, t, color, ch, thick):
        """A thin torus around finger `f` phalanx `seg` at fraction `t` (rings, threads)."""
        b, d, up, lens, r = self.c.fingers[f]
        x = d.cross(up)
        c = b + d * (sum(lens[:seg]) + lens[seg] * t)
        bone = "%s%d_%s" % (f, seg + 1, self.side)
        verts, faces, n, k = [], [], 12, 5
        R = r * 1.02
        for i in range(n):
            a = 2 * math.pi * i / n
            for j in range(k):
                bb = 2 * math.pi * j / k
                rr = R + thick * math.cos(bb)
                verts.append(self.H @ (c + x * rr * math.cos(a) + up * rr * math.sin(a) * 0.9 + d * thick * math.sin(bb)))
        for i in range(n):
            for j in range(k):
                a, b2 = i * k + j, ((i + 1) % n) * k + j
                faces.append((a, b2, ((i + 1) % n) * k + (j + 1) % k, i * k + (j + 1) % k))
        self.a.add(verts, faces, [{bone: 1.0}] * len(verts), color, ch, KIND_PART)

    def forearm(self, glove):
        """Arm skin under the sleeve + the hero's bands (cuff, sleeve) as shells, rims as tori."""
        fore, hand = self.b("LowerArm"), self.b("Hand")
        X, Z = Vector((1, 0, 0)), Vector((0, 0, 1))
        sa = self.arm.get("arm_scale", 1.0)
        st = [(0.0, 0.029, 0.023), (0.05, 0.034, 0.028), (0.12, 0.041, 0.035), (0.2, 0.045, 0.039),
              (0.28, 0.046, 0.040), (0.40, 0.046, 0.040)]

        def rad(dd):
            for (d0, rx0, rz0), (d1, rx1, rz1) in zip(st, st[1:]):
                if d0 <= dd <= d1:
                    t = (dd - d0) / (d1 - d0)
                    return (rx0 + (rx1 - rx0) * t) * sa, (rz0 + (rz1 - rz0) * t) * sa
            return st[-1][1] * sa, st[-1][2] * sa

        def w(dd):
            return {fore: 0.5, hand: 0.5} if dd < 0.01 else {fore: 1.0}
        for d0, d1, col, off, flare, rim in self.arm["bands"]:
            n = max(2, int((d1 - d0) / 0.04) + 2)
            ds = [d0 + (d1 - d0) * i / (n - 1) for i in range(n)]
            rings = []
            for dd in ds:
                rx, rz = rad(dd)
                fl = flare * max(0.0, 1.0 - (dd - d0) / 0.06)
                rings.append(ring(Vector((0, -dd, 0)), X, Z, rx + off + fl, rz + off + fl * 0.8, 16, 2.4))
            inner = [ring(Vector((0, -dd, 0)), X, Z, rad(dd)[0] + off * 0.3, rad(dd)[1] + off * 0.3, 16, 2.4)
                     for dd in (d0,)]
            self.a.loft(inner + rings, [w(d0)] + [w(dd) for dd in ds], col, M=self.H, flip=True)
            if rim:
                rx, rz = rad(d0)
                r0 = [ring(Vector((0, -d0 + dy, 0)), X, Z, rx + off + flare + dr, rz + off + flare * 0.8 + dr, 16, 2.4)
                      for dy, dr in ((0.004, 0.0), (0.0, 0.004), (-0.006, 0.003), (-0.008, 0.0))]
                self.a.loft(r0, [w(d0)] * 4, rim, M=self.H, kind=KIND_PART, flip=True)


# ------------------------------------------------------------------ the FP hero
class FpHero(Hero):
    """Hero-like holder for the part API (box/cyl/sphere/torus write into one bmesh)."""

    def __init__(self, key, hd, fd):  # noqa: no MakeHuman base
        self.d = dict(hd)
        self.d["height"] = 1.85
        self.key = key
        self.fd = fd
        self.pal = {k: srgb(v) for k, v in hd["palette"].items()}
        self.names = {}
        self.joints = {}
        self.parent = {}
        self.bone_names = bone_list()
        self.palm = {}

    # FP detail: the 3P builders are reused with denser primitives.
    def cyl(self, bone, p0, p1, r0, r1, color, ch="flat", seg=10, **kw):
        super().cyl(bone, p0, p1, r0, r1, color, ch, seg=min(32, int(seg * 1.8)), **kw)

    def torus(self, bone, center, axis, R, r, color, ch="flat", seg=(14, 6)):
        super().torus(bone, center, axis, R, r, color, ch, seg=(min(32, int(seg[0] * 1.6)), seg[1] + 2))

    def sphere(self, bone, center, radii, color, ch="flat", seg=(12, 8), **kw):
        super().sphere(bone, center, radii, color, ch, seg=(int(seg[0] * 1.5), int(seg[1] * 1.5)), **kw)

    def box(self, bone, center, size, color, ch="flat", rot=(0, 0, 0), bevel=0.25, taper=(1.0, 1.0), weights=None,
            mat=None):
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        sz = Vector(size)
        for v in t.verts:
            v.co = Vector((v.co.x * sz.x, v.co.y * sz.y, v.co.z * sz.z))
            if v.co.z > 0:
                v.co.x *= taper[0]
                v.co.y *= taper[1]
        if bevel > 0:
            bmesh.ops.bevel(t, geom=t.edges[:] + t.verts[:], offset=bevel * 0.5 * min(sz), offset_type="OFFSET",
                            segments=2, affect="EDGES", profile=0.5)
        from build_hero import _euler
        m = Matrix.Translation(Vector(center)) @ _euler(rot) if mat is None else mat
        self._add(t, m, bone, color, ch, weights)


class FpRig:
    """Rest layout, armature and the per-frame pose evaluation of one FP set."""

    def __init__(self, h, fd):
        self.h, self.fd = h, fd
        self.s = fd.get("hand_scale", 1.1)
        self.canon = {s: Canon(s, self.s) for s in ("R", "L")}
        self.grip = Vector(fd["grip"])
        self.W0 = Matrix.Translation(self.grip) @ euler_deg(*fd["weapon_rot"])
        hr = fd["hand_r"]
        self.G = {"R": self._hand_on(self.canon["R"], hr)}
        self.curl = {"R": solve_grip(self.canon["R"], self.G["R"], fd["grip_shapes"])}
        if fd.get("two_handed"):
            self.G["L"] = self._hand_on(self.canon["L"], fd["hand_l"])
            self.curl["L"] = solve_grip(self.canon["L"], self.G["L"], fd["grip_l_shapes"])
            self.L0 = self.W0 @ self.G["L"]
        else:
            li = fd["left_idle"]
            self.L0 = mat(li["wrist"], li["fingers"], li["dorsal"])
        mg = fd.get("mag")
        self.mag_c = Vector(mg["center"]) if mg else Vector((0, 0.05, -0.05))
        self.mag_axis = Vector(mg["axis"]) if mg else Vector((0, 0, 1))
        print("fp: grip curl R %s" % {f: tuple(round(a) for a in v) for f, v in self.curl["R"].items()})

    def _hand_on(self, canon, spec):
        """Hand matrix in weapon space from the middle-knuckle position and the hand axes."""
        R = frame(spec["fingers"], spec["dorsal"]).to_4x4()
        base = canon.fingers["Middle"][0]
        M = R.copy()
        M.translation = Vector(spec["knuckle"]) - R.to_3x3() @ base
        return M

    def rest(self):
        """Armature-space rest matrices of every bone (fingers straight)."""
        out = {"Root": Matrix.Identity(4), "Weapon": self.W0.copy(),
               "Mag": self.W0 @ Matrix.Translation(self.mag_c)}
        for s in ("R", "L"):
            H = self.W0 @ self.G[s] if s in self.G else self.L0
            self.Hrest = getattr(self, "Hrest", {})
            self.Hrest[s] = H
            for name, (hd, tl, z) in self.canon[s].bones().items():
                out[name] = (H, hd, tl, z)
        return out

    def build_armature(self):
        h = self.h
        arm = bpy.data.armatures.new(h.key + "_rig")
        ob = bpy.data.objects.new("Armature", arm)
        bpy.context.scene.collection.objects.link(ob)
        _activate(ob)
        bpy.ops.object.mode_set(mode="EDIT")
        R = self.rest()
        for name in h.bone_names:
            eb = arm.edit_bones.new(name)
            r = R[name]
            if isinstance(r, Matrix):
                eb.head = r.translation
                eb.tail = r.translation + r.to_3x3() @ Vector((0, 0.08 if name != "Root" else 0.05, 0))
                eb.align_roll(r.to_3x3() @ Vector((0, 0, 1)))
            else:
                H, hd, tl, z = r
                eb.head, eb.tail = H @ hd, H @ tl
                eb.align_roll(H.to_3x3() @ z)
        for name in h.bone_names:
            p = parent_of(name)
            if p:
                arm.edit_bones[name].parent = arm.edit_bones[p]
        bpy.ops.object.mode_set(mode="OBJECT")
        for pb in ob.pose.bones:
            pb.rotation_mode = "QUATERNION"
        self.rig = ob
        self.ML = {b.name: b.matrix_local.copy() for b in arm.bones}
        return ob

    # -- geometry ----------------------------------------------------------
    def build_meshes(self, weapon_fn):
        h = self.h
        h.begin_parts()
        import hero_hd
        hero_hd.prep_palette(h)
        self.rest()
        n0 = len(h.pbm.verts)
        weapon_fn(h, self.W0)
        if self.fd.get("detail"):
            self.fd["detail"](h, self.W0)
        n1 = len(h.pbm.verts)
        self._split_mag(n0, n1)
        adder = MeshAdder(h)
        for s in ("R", "L"):
            ArmBuilder(h, self.canon[s], self.Hrest[s], self.fd["arm"], adder).build()
        parts = h.finish_parts()
        hero_hd.harden_parts(parts)
        return parts

    def _split_mag(self, n0, n1):
        """Weapon vertices in the reload part's region move to the Mag bone (whole faces)."""
        mg = self.fd.get("mag")
        if not mg:
            return
        h = self.h
        Wi = self.W0.inverted()
        bm = h.pbm
        bm.verts.index_update()
        bm.verts.ensure_lookup_table()
        wi, mi = h.bone_names.index("Weapon"), h.bone_names.index("Mag")
        sel = set()
        for f in bm.faces:
            if all(n0 <= v.index < n1 for v in f.verts) and mg["region"](Wi @ f.calc_center_median()):
                sel.update(f.verts)
        for v in sel:
            dv = v[h.pdl]
            if wi in dv:
                del dv[wi]
            dv[mi] = 1.0
        print("fp: %d weapon verts on the Mag bone" % len(sel))

    # -- posing ------------------------------------------------------------
    def hand_world(self, side, P):
        if side == "R":
            return P["W"] @ self.G["R"] if P.get("R") is None else P["R"]
        return P["L"]

    def solve_arm(self, side, wristM):
        S = SHOULDER[side]
        w = wristM.translation
        to = w - S
        d = max(0.05, min(to.length, (UPPER_ARM + FOREARM) * 0.999))
        dr = to.normalized()
        ca = max(-1.0, min(1.0, (UPPER_ARM ** 2 + d * d - FOREARM ** 2) / (2 * UPPER_ARM * d)))
        pole = POLE[side]
        bend = (pole - dr * pole.dot(dr)).normalized()
        elbow = S + dr * ca * UPPER_ARM + bend * math.sqrt(1 - ca * ca) * UPPER_ARM
        y = (w - elbow).normalized()
        z = wristM.to_3x3() @ Vector((0, 0, 1))
        M = mat(w - y * FOREARM, y, z)
        return M

    def world(self, P):
        """Armature-space pose matrices of every bone for pose dict P (see fp_anims)."""
        out = {"Root": Matrix.Identity(4), "Weapon": P["W"]}
        out["Mag"] = P["W"] @ Matrix.Translation(self.mag_c) @ P.get("mag", Matrix.Identity(4))
        for s in ("R", "L"):
            H = self.hand_world(s, P)
            out["LowerArm_" + s] = self.solve_arm(s, H)
            out["Hand_" + s] = H
            curls = P["curl"][s]
            for f in FINGERS:
                parent = H
                for i in (1, 2, 3):
                    b = "%s%d_%s" % (f, i, s)
                    rel = self._rest_rel(b)
                    rot = Matrix.Rotation(math.radians(-curls[f][i - 1]), 4, "X")
                    if i == 1 and P.get("spread", {}).get(s):
                        sp = SPREAD_DEG[f] * P["spread"][s] * (1 if s == "R" else -1)
                        rot = Matrix.Rotation(math.radians(sp), 4, "Z") @ rot
                    parent = parent @ rel @ rot
                    out[b] = parent
        return out

    def _rest_rel(self, b):
        p = parent_of(b)
        return self.ML[p].inverted() @ self.ML[b]

    def key(self, P, frame):
        Wd = self.world(P)
        for pb in self.rig.pose.bones:
            b = pb.name
            p = parent_of(b)
            rel = self._rest_rel(b) if p else self.ML[b]
            pw = Wd[p] if p else Matrix.Identity(4)
            basis = rel.inverted() @ pw.inverted() @ Wd[b]
            loc, rot, _sc = basis.decompose()
            q = Quaternion(rot)
            last = self._lastq.get(b)
            if last is not None and last.dot(q) < 0:
                q.negate()
            self._lastq[b] = q
            pb.location = loc
            pb.rotation_quaternion = q
            pb.keyframe_insert("location", frame=frame)
            pb.keyframe_insert("rotation_quaternion", frame=frame)

    _lastq = {}

    def sockets_armature(self):
        """Socket positions in armature space at rest (weapon space -> eye space)."""
        return {k: self.W0 @ Vector(v) for k, v in self.fd["sockets"].items()}
