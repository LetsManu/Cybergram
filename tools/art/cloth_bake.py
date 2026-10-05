"""Baked cloth for the W16 hero pipeline (contract: design/art/baked-cloth.md).

A garment (coat skirt, tails, cape...) is a thick, layered mesh skinned to chains
of `Cloth_<part>_<chain>_<n>` bones. At build time a Blender cloth simulation runs
per animation clip on a single-layer proxy of the garment (pinned at its top row,
colliding with a decimated copy of the skinned body); every frame the chain bones
are fitted to the simulated proxy (bone direction = the proxy column, twist = the
tangent across the columns) and keyed into the clip. The glb therefore carries
plain bone animation: zero runtime cost, deterministic, identical on every tier.

Loops (LOOP_CLIPS) are simulated twice after a pre-roll and the second pass is
kept; the last SEAM frames are blended (quaternion offset, smoothstep) so the end
pose equals the start pose. One-shots get the pre-roll only.

Garment spec ("cloth" list in the hero def), angles in degrees with 0 = front
(+Y) and +90 = the hero's right (+X); lengths in metres at 1.85 m (scaled):
  part        name used in the bone names ("coat")
  kind        "skirt" (a ring around the hips; the only kind so far)
  top         top row height above the Hips joint (m)
  hem         hem height above the ground (m)
  offset      gap between the body and the top row (m)
  flare       extra radius at the hem (m)
  clear       minimum clearance from the body/legs at rest (m)
  open_front  gap at the front (deg, 0 = closed ring)
  slits       [(angle, fraction of the length from the hem), ...] (tails)
  chains      [(name, angle), ...] one bone chain per entry (never on a slit)
  bones       bones per chain (default 3)
  rows, col_deg   proxy resolution (default 10 rows, 10 deg columns)
  thick       garment thickness (m)
  colors      {"outer", "inner", "hem", "trim"} palette names
  hem_rows    rows of the layered hem band (default 2); trim_cols: front edge trim
  sim         overrides of SIM (Blender cloth settings)
"""
import math
import time

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

LOOP_CLIPS = {"idle", "walk", "run", "run_back", "strafe_l", "strafe_r", "crouch_idle", "crouch_walk", "showcase"}
PREROLL = 24
SEAM = 8
SIM = {"quality": 6, "mass": 0.35, "tension": 15.0, "compression": 15.0, "shear": 5.0, "bending": 2.0,
       "air": 1.5, "distance": 0.012, "self": False, "pin_stiffness": 1.0, "friction": 3.0}
KIND_SOFT = 4


class Garment:
    pass


def _smooth(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


# ------------------------------------------------------------------ geometry
def add_garments(h):
    """Adds every garment in h.d["cloth"] to the parts mesh and its bones to the skeleton."""
    return [_skirt(h, spec) for spec in h.d.get("cloth", [])]


def _skirt(h, spec):
    import hero_hd
    k = h.d["height"] / 1.85
    g = Garment()
    g.spec = spec
    g.part = spec["part"]
    gap = spec.get("open_front", 0.0)
    a0, a1 = gap / 2.0, 360.0 - gap / 2.0
    slits = sorted(spec.get("slits", []))
    marks = [a0] + [s for s, _ in slits] + [a1]
    cols = []
    for x, y in zip(marks, marks[1:]):
        n = max(1, int(math.ceil((y - x) / spec.get("col_deg", 10.0))))
        cols += [x + (y - x) * i / n for i in range(n)]
    if gap > 0:
        cols.append(a1)
    closed = gap <= 0
    nc = len(cols)
    R = spec.get("rows", 10)
    nb = spec.get("bones", 3)
    ang = np.radians(np.array(cols))
    slit_rs = {}
    for s, frac in slits:
        c = int(np.argmin(np.abs(np.array(cols) - s)))
        slit_rs[c] = R - int(round(frac * R))
    g.chains = []
    for name, a in spec["chains"]:
        c = int(np.argmin(np.abs(np.array(cols) - a)))
        assert c not in slit_rs, "cloth chain %s sits on a slit" % name
        g.chains.append((name, c))
    hips = h.jh("Hips")
    yc = hips.y
    z_top = hips.z + spec.get("top", 0.03) * k
    z_hem = spec.get("hem", 0.45) * k
    bvh = hero_hd.body_bvh(h, ("Hips", "Spine", "Chest", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R"))

    def body_r(z, a):
        d = Vector((math.sin(a), math.cos(a), 0.0))
        c = Vector((0.0, yc, z))
        hit = bvh.ray_cast(c + d * 0.9, -d, 0.9)
        return (hit[0] - c).dot(d) if hit[0] is not None else 0.08 * k
    G = np.zeros((R + 1, nc, 3))
    top_r = np.array([body_r(z_top, a) for a in ang]) + spec.get("offset", 0.012) * k
    for r in range(R + 1):
        f = r / R
        z = z_top + (z_hem - z_top) * f
        rr = top_r + spec.get("flare", 0.1) * k * f ** 1.3
        need = np.array([body_r(z, a) for a in ang]) + spec.get("clear", 0.02) * k
        rr = np.maximum(rr, need)
        for _ in range(6):  # a garment bridges the gaps between the legs
            nb_ = np.roll(rr, 1) * 0.5 + np.roll(rr, -1) * 0.5 if closed else np.concatenate(
                [[rr[1]], (rr[:-2] + rr[2:]) * 0.5, [rr[-2]]])
            rr = np.maximum(rr, nb_)
        G[r, :, 0] = np.sin(ang) * rr
        G[r, :, 1] = yc + np.cos(ang) * rr
        G[r, :, 2] = z
    g.G, g.R, g.nc, g.cols, g.ang, g.slit_rs, g.closed, g.nb = G, R, nc, cols, ang, slit_rs, closed, nb
    # Vertex table: A = copy used as a face's left column, B = as its right column (slits split rows > rs).
    pos, meta = [], []
    A = [[0] * nc for _ in range(R + 1)]
    B = [[0] * nc for _ in range(R + 1)]
    for r in range(R + 1):
        for c in range(nc):
            A[r][c] = len(pos)
            pos.append(G[r, c].copy())
            split = c in slit_rs and r > slit_rs[c]
            meta.append((c, r, "A" if split else None))
            if split:
                B[r][c] = len(pos)
                pos.append(G[r, c].copy())
                meta.append((c, r, "B"))
            else:
                B[r][c] = A[r][c]
    g.A, g.B, g.pos, g.meta = A, B, np.array(pos), meta
    faces = []
    for r in range(R):
        for c in range(nc if closed else nc - 1):
            c2 = (c + 1) % nc
            faces.append(((A[r][c], B[r][c2], B[r + 1][c2], A[r + 1][c]), r, c))
    g.faces = faces
    # Bones: one chain per entry, nb bones from the top row to the hem.
    g.nodes = [int(round(i * R / nb)) for i in range(nb + 1)]
    parent = spec.get("parent", "Hips")
    g.bones = {}
    for name, c in g.chains:
        names = ["Cloth_%s_%s_%d" % (g.part, name, i + 1) for i in range(nb)]
        for i, bn in enumerate(names):
            h.joints[bn] = (Vector(G[g.nodes[i], c]), Vector(G[g.nodes[i + 1], c]))
            h.parent[bn] = parent if i == 0 else names[i - 1]
            h.bone_names.append(bn)
        g.bones[name] = names
    g.parent = parent
    g.W = [_weights(g, i) for i in range(len(pos))]
    _emit(h, g, k)
    print("cloth: %s %d cols x %d rows, chains %s" % (g.part, nc, R + 1, [n for n, _ in g.chains]))
    return g


def _valid(g, chain_c, c, copy, r):
    """False if a slit (open at row r) separates the chain column from vertex column c."""
    for s, rs in g.slit_rs.items():
        if r <= rs:
            continue
        lo, hi = min(chain_c, c), max(chain_c, c)
        if lo < s < hi:
            return False
        if s == c and ((copy == "A" and chain_c < c) or (copy == "B" and chain_c > c)):
            return False
    return True


def _weights(g, i):
    c, r, copy = g.meta[i]
    s = r / g.R * g.nb
    bi = min(int(s), g.nb - 1)
    fr = s - bi
    along = [(bi, 1.0)]
    if fr > 0.7 and bi + 1 < g.nb:
        t = (fr - 0.7) / 0.3
        along = [(bi, 1 - 0.5 * t), (bi + 1, 0.5 * t)]
    elif fr < 0.3 and bi > 0:
        t = (0.3 - fr) / 0.3
        along = [(bi, 1 - 0.5 * t), (bi - 1, 0.5 * t)]
    ok = [(n, cc) for n, cc in g.chains if _valid(g, cc, c, copy, r)]
    left = [x for x in ok if x[1] <= c]
    right = [x for x in ok if x[1] >= c]
    L = max(left, key=lambda x: x[1]) if left else None
    Rr = min(right, key=lambda x: x[1]) if right else None
    if L and Rr and L[1] != Rr[1]:
        t = (g.ang[c] - g.ang[L[1]]) / (g.ang[Rr[1]] - g.ang[L[1]])
        across = [(L[0], 1 - t), (Rr[0], t)]
    else:
        across = [((L or Rr)[0], 1.0)]
    w = {}
    for chain, cw in across:
        for b, bw in along:
            bn = g.bones[chain][b]
            w[bn] = w.get(bn, 0.0) + cw * bw
    t = _smooth(s / 0.5)  # soft root: the top rows follow the parent bone
    w = {b: v * t for b, v in w.items()}
    w[g.parent] = w.get(g.parent, 0.0) + (1 - t)
    top = sorted(w.items(), key=lambda x: -x[1])[:4]
    tot = sum(v for _, v in top) or 1.0
    return {b: v / tot for b, v in top if v > 1e-4}


def _normals(g):
    P = g.pos
    N = np.zeros_like(P)
    for (a, b, c, d), _r, _c in g.faces:
        n = np.cross(P[c] - P[a], P[d] - P[b])
        for i in (a, b, c, d):
            N[i] += n
    yc = g.G[0, :, 1].mean()
    for i in range(len(P)):
        radial = np.array([P[i][0], P[i][1] - yc, 0.0])
        if np.dot(N[i], radial) < 0:
            N[i] = -N[i]
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
    return N


def _emit(h, g, k):
    """Layered solid: main shell, hem band and front edge trims, skinned like the grid."""
    from build_hero import _paint_face
    sp = g.spec
    col = dict({"outer": "plum", "inner": "ink", "hem": "gold", "trim": "gold"}, **sp.get("colors", {}))
    th = sp.get("thick", 0.012) * k
    N = _normals(g)
    hb = sp.get("hem_rows", 2)
    tc = sp.get("trim_cols", 1)
    all_faces = g.faces
    layers = [(all_faces, 0.0, th, col["outer"], col["inner"], col["hem"])]
    lt = 0.005 * k  # layer thickness; layers sit clearly outside the shell (no intersection)
    lo = th * 0.5 + lt * 0.5 + 0.0015 * k
    layers.append(([f for f in all_faces if f[1] >= g.R - hb], lo, lt, col["hem"], col["hem"], col["hem"]))
    if not g.closed and tc > 0:
        layers.append(([f for f in all_faces if f[2] < tc or f[2] >= g.nc - 1 - tc], lo + lt * 0.2, lt,
                       col["trim"], col["trim"], col["trim"]))
    drop = sp.get("hem_drop", 0.005) * k  # the hem band hangs a little below the shell: a solid trim edge
    bm, dl = h.pbm, h.pdl
    for faces, off, t, c_out, c_in, c_rim in layers:
        used = sorted({i for f in faces for i in f[0]})
        outer, inner = {}, {}
        for i in used:
            for store, sgn in ((outer, 1.0), (inner, -1.0)):
                p = g.pos[i] + N[i] * (off + sgn * t / 2)
                if off > 0 and g.meta[i][1] == g.R:
                    p = p - np.array([0.0, 0.0, drop])
                v = bm.verts.new(Vector(p))
                for b, w in g.W[i].items():
                    v[dl][h.bone_names.index(b)] = w
                store[i] = v
        new = []
        edges = {}
        for (a, b, c, d), r, _c in faces:
            fo = bm.faces.new([outer[a], outer[b], outer[c], outer[d]])
            fi = bm.faces.new([inner[d], inner[c], inner[b], inner[a]])
            _paint_face(fo, h.pcol, h.puv, h.color(c_rim if r >= g.R - hb else c_out), "flat")
            # The hem rows are trim-coloured outside and inside: where skinning lets the lining
            # poke through the layered hem band while the coat flares, it stays gold.
            _paint_face(fi, h.pcol, h.puv, h.color(c_rim if r >= g.R - hb else c_in), "flat")
            new += [fo, fi]
            for e in ((a, b), (b, c), (c, d), (d, a)):
                key = tuple(sorted(e))
                edges[key] = edges.get(key, 0) + 1
        for (a, b, c, d), _r, _c in faces:
            for x, y in ((a, b), (b, c), (c, d), (d, a)):
                if edges[tuple(sorted((x, y)))] == 1:
                    f = bm.faces.new([outer[y], outer[x], inner[x], inner[y]])
                    _paint_face(f, h.pcol, h.puv, h.color(c_rim), "flat")
                    new.append(f)
        for f in new:
            f[h.pkind] = KIND_SOFT
            f.smooth = True


# ------------------------------------------------------------------ bake
def make_collider(h, tris=3000):
    """Decimated copy of the body (+ shells) for the cloth collisions (call before the join)."""
    from build_hero import _activate
    ob = h.body.copy()
    ob.data = h.body.data.copy()
    ob.name = ob.data.name = h.key + "_cloth_collider"
    bpy.context.scene.collection.objects.link(ob)
    _activate(ob)
    dec = ob.modifiers.new("dec", "DECIMATE")
    dec.ratio = min(1.0, tris / max(1, sum(len(p.vertices) - 2 for p in ob.data.polygons)))
    bpy.ops.object.modifier_apply(modifier=dec.name)
    # Out of the scene until bake(): a coincident copy would occlude the texture bakes (AO).
    bpy.context.scene.collection.objects.unlink(ob)
    return ob


def _proxy(h, g):
    me = bpy.data.meshes.new("cloth_proxy_" + g.part)
    me.from_pydata([tuple(p) for p in g.pos], [], [f[0] for f in g.faces])
    me.update()
    ob = bpy.data.objects.new("cloth_proxy_" + g.part, me)
    bpy.context.scene.collection.objects.link(ob)
    pin = ob.vertex_groups.new(name="pin")
    par = ob.vertex_groups.new(name=g.parent)
    for i, (c, r, _cp) in enumerate(g.meta):
        par.add([i], 1.0, "REPLACE")
        if r == 0:
            pin.add([i], 1.0, "REPLACE")
        elif r == 1:
            pin.add([i], 0.35, "REPLACE")
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = h.rig
    return ob


def _add_cloth(ob, spec):
    for m in list(ob.modifiers):
        if m.type == "CLOTH":
            ob.modifiers.remove(m)
    s = dict(SIM, **spec.get("sim", {}))
    m = ob.modifiers.new("cloth", "CLOTH")
    cs = m.settings
    cs.quality = s["quality"]
    cs.mass = s["mass"]
    cs.tension_stiffness = s["tension"]
    cs.compression_stiffness = s["compression"]
    cs.shear_stiffness = s["shear"]
    cs.bending_stiffness = s["bending"]
    cs.air_damping = s["air"]
    cs.vertex_group_mass = "pin"
    cs.pin_stiffness = s["pin_stiffness"]
    cc = m.collision_settings
    cc.distance_min = s["distance"]
    cc.use_self_collision = s["self"]
    cc.collision_quality = 3
    return m


def _sample(rig, act):
    """Per-frame pose (quaternion, location) of every non-cloth bone of an action."""
    sc = bpy.context.scene
    rig.animation_data.action = act
    f0, f1 = int(round(act.frame_range[0])), int(round(act.frame_range[1]))
    out = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        out.append({pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in rig.pose.bones
                    if not pb.name.startswith("Cloth_")})
    return f0, out


def _frame3(y, side):
    y = y.normalized()
    x = (side - y * side.dot(y))
    x = x.normalized() if x.length > 1e-6 else y.orthogonal().normalized()
    z = x.cross(y)
    return Matrix((x, y, z)).transposed()


class _Fit:
    """Fits a garment's chain bones to the simulated proxy, per frame."""

    def __init__(self, h, g):
        self.g = g
        self.rig = h.rig
        bones = self.rig.data.bones
        self.rest = {}
        for name, c in g.chains:
            for i, bn in enumerate(g.bones[name]):
                b = bones[bn]
                side = self._side(g.pos, c, g.nodes[i])
                y = (b.tail_local - b.head_local)
                self.rest[bn] = (b.matrix_local.copy(), _frame3(Vector(y), side), b.length)
        self.prest = bones[g.parent].matrix_local.copy()

    def _side(self, P, c, r):
        g = self.g
        ia = g.A[r][c - 1] if (c - 1 >= 0 or g.closed) else g.A[r][c]
        ib = g.B[r][(c + 1) % g.nc] if (c + 1 < g.nc or g.closed) else g.B[r][c]
        return Vector(P[ib]) - Vector(P[ia])

    def fit(self, P):
        """P: proxy vertex positions (armature space). Returns {bone: quaternion basis}."""
        g = self.g
        out = {}
        Mp = self.rig.pose.bones[g.parent].matrix.copy()
        for name, c in g.chains:
            parent_pose, parent_rest = Mp, self.prest
            head = None
            for i, bn in enumerate(g.bones[name]):
                rest, Frest, length = self.rest[bn]
                if head is None:
                    head = Mp @ self.prest.inverted() @ rest.translation
                tgt = Vector(P[g.A[g.nodes[i + 1]][c]])
                d = tgt - head
                if d.length < 1e-6:
                    d = rest.to_3x3() @ Vector((0, 1, 0))
                Fnow = _frame3(d, self._side(P, c, g.nodes[i]))
                Rm = Fnow @ Frest.transposed()
                pose = Matrix.Translation(head) @ (Rm @ rest.to_3x3()).to_4x4()
                basis = (parent_rest.inverted() @ rest).inverted() @ (parent_pose.inverted() @ pose)
                out[bn] = basis.to_quaternion()
                head = head + d.normalized() * length
                parent_pose, parent_rest = pose, rest
        return out


def bake(h, garments, collider):
    """Simulates every multi-frame clip and keys the Cloth_ bones into it."""
    sc = bpy.context.scene
    rig = h.rig
    t_all = time.time()
    sc.collection.objects.link(collider)
    m = collider.modifiers.new("Armature", "ARMATURE")
    m.object = rig
    collider.modifiers.new("collision", "COLLISION")
    collider.collision.thickness_outer = 0.008
    collider.collision.cloth_friction = 5.0
    proxies = [(_proxy(h, g), g, _Fit(h, g)) for g in garments]
    state = {"seq": []}

    def handler(scene, *_a):
        seq = state["seq"]
        if not seq:
            return
        pose = seq[min(max(scene.frame_current - 1, 0), len(seq) - 1)]
        for name, (q, loc) in pose.items():
            pb = rig.pose.bones[name]
            pb.rotation_quaternion = q
            pb.location = loc
    bpy.app.handlers.frame_change_pre.append(handler)
    clips = [a for a in bpy.data.actions if a.frame_range[1] - a.frame_range[0] >= 1]
    report = []
    try:
        for act in clips:
            t0 = time.time()
            f0, poses = _sample(rig, act)
            loop = act.name in LOOP_CLIPS
            seq = [poses[0]] * PREROLL + ((poses[:-1] * 2 + [poses[-1]]) if loop else list(poses))
            rec0 = len(seq) - len(poses)
            rig.animation_data.action = None
            state["seq"] = seq
            for ob, g, _f in proxies:
                cm = _add_cloth(ob, g.spec)
                cm.point_cache.frame_start = 1
                cm.point_cache.frame_end = len(seq)
            sc.frame_start, sc.frame_end = 1, len(seq)
            rec = {id(g): [] for _o, g, _f in proxies}
            for f in range(1, len(seq) + 1):
                sc.frame_set(f)
                if f - 1 < rec0:
                    continue
                dg = bpy.context.evaluated_depsgraph_get()
                for ob, g, fit in proxies:
                    ev = ob.evaluated_get(dg)
                    n = len(ev.data.vertices)
                    P = np.zeros(n * 3)
                    ev.data.vertices.foreach_get("co", P)
                    rec[id(g)].append(fit.fit(P.reshape(n, 3)))
            state["seq"] = []
            rig.animation_data.action = act
            for _ob, g, _f in proxies:
                frames = rec[id(g)]
                if loop:
                    frames = _close_loop(frames)
                for j, qs in enumerate(frames):
                    for bn, q in qs.items():
                        pb = rig.pose.bones[bn]
                        pb.rotation_quaternion = q
                        pb.keyframe_insert("rotation_quaternion", frame=f0 + j)
            report.append("%s %d f %.1f s" % (act.name, len(seq), time.time() - t0))
    finally:
        bpy.app.handlers.frame_change_pre.remove(handler)
        rig.animation_data.action = None
        for ob, _g, _f in proxies:
            bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.objects.remove(collider, do_unlink=True)
        for pb in rig.pose.bones:
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)
    print("cloth: baked %d clips in %.0f s (%s)" % (len(clips), time.time() - t_all, ", ".join(report)))


def _close_loop(frames):
    """Blends the last SEAM frames so the loop's end pose equals its start pose."""
    L = len(frames) - 1
    B = max(1, min(SEAM, L // 2))
    out = [dict(f) for f in frames]
    for bn in frames[0]:
        q0, qL = frames[0][bn], frames[L][bn]
        corr = q0 @ qL.inverted()
        for j in range(L - B, L + 1):
            w = _smooth((j - (L - B)) / B)
            out[j][bn] = Quaternion((1, 0, 0, 0)).slerp(corr, w) @ frames[j][bn]
    return out
