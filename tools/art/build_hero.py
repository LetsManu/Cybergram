#!/usr/bin/env python3
"""Builds a rigged toon hero .glb from the CC0 MakeHuman base (W13 pilot).

Usage (Python 3.11 with `pip install bpy`, after tools/art/fetch_base.sh):
    python tools/art/build_hero.py ryker vesper

Steps per hero (design/art/hero-art-bible.md §7):
  1. load the MakeHuman base mesh, apply the hero's macro targets, convert to
     Blender space (Z up, facing +Y -> glTF/Godot facing -Z) at the hero height;
  2. curl the fingers into a grip with the full 163-bone MakeHuman rig (numpy LBS);
  3. collapse the rig to ~23 game bones (fingers -> hand, face -> head) and
     transfer the CC0 skin weights;
  4. decimate the body, cut clean colour borders (bisect planes), paint flat
     vertex colours + a channel id in UV0.x, add armour shells offset from the body;
  5. add rigid gear / weapon parts (one bone each) and skinned threads;
  6. author the keyframe clips (gaits, aim, shoot, reload, casts, death) with
     analytic 2-bone IK on the weapon grips;
  7. export assets/models/heroes/<id>/<id>.glb (one mesh, one material).
"""
import json
import math
import os
import sys

import bpy  # noqa: E402  (bpy must load before bmesh)
import bmesh
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CACHE = os.path.join(HERE, ".cache", "makehuman")
OUT_DIR = os.path.join(ROOT, "assets", "models", "heroes")
FPS = 30

# Vertex channels (UV0.x = channel / 8 + 1/16), see the art bible §3.
CH = {"flat": 0, "team": 1, "emit": 2, "team_emit": 3, "skin": 4, "chrome": 5}

# Game skeleton: name -> (first MakeHuman bone, last bone of the merged chain, parent).
GAME_BONES = [
    ("Hips", "root", None, None),
    ("Spine", "spine05", "spine04", "Hips"),
    ("Chest", "spine03", "spine02", "Spine"),
    ("UpperChest", "spine01", "spine01", "Chest"),
    ("Neck", "neck01", "neck03", "UpperChest"),
    ("Head", "head", "head", "Neck"),
]
for _s, _m in (("L", "L"), ("R", "R")):
    GAME_BONES += [
        ("Clavicle_" + _s, "clavicle." + _m, "shoulder01." + _m, "UpperChest"),
        ("UpperArm_" + _s, "upperarm01." + _m, "upperarm02." + _m, "Clavicle_" + _s),
        ("LowerArm_" + _s, "lowerarm01." + _m, "lowerarm02." + _m, "UpperArm_" + _s),
        ("Hand_" + _s, "wrist." + _m, "wrist." + _m, "LowerArm_" + _s),
        ("UpperLeg_" + _s, "upperleg01." + _m, "upperleg02." + _m, "Hips"),
        ("LowerLeg_" + _s, "lowerleg01." + _m, "lowerleg02." + _m, "UpperLeg_" + _s),
        ("Foot_" + _s, "foot." + _m, "foot." + _m, "LowerLeg_" + _s),
    ]
UPPER_BONES = ["UpperChest", "Neck", "Head", "Clavicle_L", "Clavicle_R", "UpperArm_L", "UpperArm_R",
               "LowerArm_L", "LowerArm_R", "Hand_L", "Hand_R", "Weapon"]


def srgb(hex_str):
    """'#RRGGBB' -> RGBA tuple stored as-is (the project convention: the toon shaders
    feed COLOR straight to ALBEDO, like the procedural builders' Color("#hex"))."""
    h = hex_str.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)) + (1.0,)


def v3(*a):
    return Vector(a[0] if len(a) == 1 else a)


# ---------------------------------------------------------------- base body
class Base:
    """The MakeHuman base after targets, in Blender space (metres, Z up, facing +Y)."""

    def __init__(self, hero):
        self.hero = hero
        verts, groups = [], {}
        g = None
        with open(os.path.join(CACHE, "base.obj")) as f:
            for line in f:
                if line.startswith("v "):
                    verts.append([float(x) for x in line.split()[1:4]])
                elif line.startswith("g "):
                    g = line.split()[1]
                elif line.startswith("f "):
                    groups.setdefault(g, []).append([int(t.split("/")[0]) - 1 for t in line.split()[1:]])
        V = np.array(verts, dtype=np.float64)
        for name, w in hero["targets"].items():
            data = np.loadtxt(os.path.join(CACHE, "targets", name + ".target"), comments="#", ndmin=2)
            if data.size == 0:
                continue
            V[data[:, 0].astype(int)] += w * data[:, 1:4]
        B = np.stack([-V[:, 0], V[:, 2], V[:, 1]], axis=1)  # MH (Y up, +Z fwd) -> Blender
        body_idx = np.unique(np.array(groups["body"]).ravel())
        zmin, zmax = B[body_idx, 2].min(), B[body_idx, 2].max()
        s = hero["height"] / (zmax - zmin)
        B = (B - np.array([0.0, 0.0, zmin])) * s
        self.groups = groups
        self.V = B
        self.sk = json.load(open(os.path.join(CACHE, "default.mhskel")))
        mhw = json.load(open(os.path.join(CACHE, "default_weights.mhw")))["weights"]
        self.W = {b: (np.array([p[0] for p in l], int), np.array([p[1] for p in l])) for b, l in mhw.items()}
        cy = self.joint(self.sk["bones"]["spine05"]["head"])[1]
        self.V[:, 1] -= cy
        self._scale_head(hero.get("head_scale", 1.0))
        self._curl_fingers()

    def joint(self, name):
        return self.V[self.sk["joints"][name]].mean(axis=0)

    def head(self, bone):
        return self.joint(self.sk["bones"][bone]["head"])

    def tail(self, bone):
        return self.joint(self.sk["bones"][bone]["tail"])

    def _descendants(self, root):
        out = [root]
        for b, d in self.sk["bones"].items():
            if d["parent"] in out and b not in out:
                out.append(b)
        changed = True
        while changed:
            changed = False
            for b, d in self.sk["bones"].items():
                if d["parent"] in out and b not in out:
                    out.append(b)
                    changed = True
        return out

    def _scale_head(self, k):
        if abs(k - 1.0) < 1e-4:
            return
        c = self.head("head")
        w = np.zeros(len(self.V))
        for b in self._descendants("head"):
            if b in self.W:
                idx, ww = self.W[b]
                w[idx] += ww
        w = np.clip(w, 0.0, 1.0)
        self.V = c + (self.V - c) * (1.0 - (1.0 - k) * w)[:, None]

    def _lbs(self, rot):
        """Linear blend skinning with rotations {bone: 3x3 about its head} on the full rig."""
        bones = self.sk["bones"]
        G = {}

        def glob(b):
            if b in G:
                return G[b]
            p = bones[b]["parent"]
            M = glob(p).copy() if p else np.eye(4)
            if b in rot:
                h = self.head(b)
                L = np.eye(4)
                L[:3, :3] = rot[b]
                L[:3, 3] = h - rot[b] @ h
                M = M @ L
            G[b] = M
            return M

        disp = np.zeros_like(self.V)
        wsum = np.zeros(len(self.V))
        for b, (idx, w) in self.W.items():
            M = glob(b)
            p = self.V[idx]
            gp = p @ M[:3, :3].T + M[:3, 3]
            disp[idx] += w[:, None] * (gp - p)
            wsum[idx] += w
        ok = wsum > 1e-6
        self.V[ok] += disp[ok] / wsum[ok][:, None]

    def _curl_fingers(self):
        rot = {}
        for s in ("L", "R"):
            d_h = self.head("finger3-1." + s) - self.head("wrist." + s)
            a = self.head("finger2-1." + s) - self.head("finger5-1." + s)
            n = np.cross(d_h, a)
            n /= np.linalg.norm(n)
            if np.dot(n, np.array([-np.sign(self.head("wrist." + s)[0]), 0.0, 0.0])) < 0:
                n = -n
            angles = {1: (25, 30, 30), 2: (55, 80, 55), 3: (60, 85, 55), 4: (62, 85, 55), 5: (65, 85, 55)}
            for f, angs in angles.items():
                for k in (1, 2, 3):
                    b = "finger%d-%d.%s" % (f, k, s)
                    d = self.tail(b) - self.head(b)
                    ax = np.cross(d, n)
                    if np.linalg.norm(ax) < 1e-9:
                        continue
                    ax /= np.linalg.norm(ax)
                    rot[b] = _axis_angle(ax, math.radians(angs[k - 1]))
        self._lbs(rot)


def _axis_angle(ax, ang):
    x, y, z = ax
    c, s, t = math.cos(ang), math.sin(ang), 1 - math.cos(ang)
    return np.array([[t * x * x + c, t * x * y - s * z, t * x * z + s * y],
                     [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
                     [t * x * z - s * y, t * y * z + s * x, t * z * z + c]])


# ---------------------------------------------------------------- the hero
class Hero:
    def __init__(self, hero):
        self.d = hero
        self.key = hero["key"]
        self.base = Base(hero)
        self.pal = {k: srgb(v) for k, v in hero["palette"].items()}
        self.joints = {}
        self.parent = {}
        self._game_skeleton()

    # -- skeleton -------------------------------------------------------
    def _game_skeleton(self):
        b = self.base
        for name, first, last, parent in GAME_BONES:
            if name == "Hips":
                h = (b.head("upperleg01.L") + b.head("upperleg01.R")) / 2.0
                h[1] = b.head("spine05")[1]
                t = h + np.array([0.0, 0.0, 0.12])
            elif name.startswith("Hand_"):
                h = b.head(first)
                t = b.head("finger3-1." + name[-1]) * 0.7 + b.tail("finger3-3." + name[-1]) * 0.3
            elif name.startswith("Foot_"):
                h = b.head(first)
                t = b.head("toe3-1." + name[-1])
            else:
                h = b.head(first)
                t = b.tail(last)
            self.joints[name] = (Vector(h), Vector(t))
            self.parent[name] = parent
        # MakeHuman bone -> game bone (walk up until a mapped bone).
        direct = {}
        for name, first, last, parent in GAME_BONES:
            chain = [first]
            cur = last
            while cur and cur != first:
                chain.append(cur)
                cur = b.sk["bones"][cur]["parent"]
            for c in chain:
                direct[c] = name
        self.bone_map = {}
        for mb in b.sk["bones"]:
            cur = mb
            while cur not in direct:
                cur = b.sk["bones"][cur]["parent"]
            self.bone_map[mb] = direct[cur]
        names = [g[0] for g in GAME_BONES]
        Wd = np.zeros((len(b.V), len(names)))
        for mb, (idx, w) in b.W.items():
            Wd[idx, names.index(self.bone_map[mb])] += w
        self.Wd = Wd
        self.bone_names = names + ["Weapon"]
        self.parent["Weapon"] = "UpperChest"
        self.palm = {}
        for s in ("L", "R"):
            d_h = b.head("finger3-1." + s) - b.head("wrist." + s)
            a = b.head("finger2-1." + s) - b.head("finger5-1." + s)
            n = np.cross(d_h, a)
            n /= np.linalg.norm(n)
            if np.dot(n, np.array([-np.sign(b.head("wrist." + s)[0]), 0.0, 0.0])) < 0:
                n = -n
            self.palm[s] = Vector(n)

    def jh(self, bone):
        return self.joints[bone][0].copy()

    def jt(self, bone):
        return self.joints[bone][1].copy()

    def bbox(self, bone, wmin=0.5):
        i = self.bone_names.index(bone)
        body = np.unique(np.array(self.base.groups["body"]).ravel())
        sel = body[self.Wd[body, i] > wmin]
        P = self.base.V[sel]
        return Vector(P.min(axis=0)), Vector(P.max(axis=0))

    def eye(self, s):
        g = self.base.groups["helper-%s-eye" % ("l" if s == "L" else "r")]
        return Vector(self.base.V[np.unique(np.array(g).ravel())].mean(axis=0))

    def side(self, bone, t, c):
        """Signed distance of `c` past the plane at `t` along `bone` (normal = bone direction)."""
        h, tl = self.joints[bone]
        return (Vector(c) - h.lerp(tl, t)).dot((tl - h).normalized())

    def cut(self, bone, t):
        h, tl = self.joints[bone]
        return h.lerp(tl, t), (tl - h).normalized()

    def jl(self, bone, t):
        h, tl = self.joints[bone]
        return h.lerp(tl, t)

    # -- body mesh ------------------------------------------------------
    def build_body(self):
        b = self.base
        faces = [f for f in b.groups["body"]]
        for g in ("helper-l-eye", "helper-r-eye"):
            faces += b.groups[g]
        used = sorted({i for f in faces for i in f})
        remap = {o: n for n, o in enumerate(used)}
        verts = [tuple(b.V[i]) for i in used]
        eye_faces = set(range(len(b.groups["body"]), len(faces)))
        me = bpy.data.meshes.new(self.key + "_body")
        me.from_pydata(verts, [], [[remap[i] for i in f] for f in faces])
        me.update()
        ob = bpy.data.objects.new(self.key + "_body", me)
        bpy.context.scene.collection.objects.link(ob)
        groups = {n: ob.vertex_groups.new(name=n) for n in self.bone_names}
        W = np.concatenate([self.Wd[used], np.zeros((len(used), 1))], axis=1)
        for vi in range(len(used)):
            row = W[vi]
            top = np.argsort(row)[::-1][:4]
            tot = row[top].sum()
            if tot <= 1e-6:
                groups["Hips"].add([vi], 1.0, "REPLACE")
                continue
            for k in top:
                if row[k] > 1e-4:
                    groups[self.bone_names[k]].add([vi], float(row[k] / tot), "REPLACE")
        eye = me.attributes.new("is_eye", "BOOLEAN", "FACE")
        for fi in eye_faces:
            eye.data[fi].value = True
        _activate(ob)
        mod = ob.modifiers.new("dec", "DECIMATE")
        mod.ratio = self.d.get("decimate", 0.3)
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
        self.body = ob
        return ob

    def face_bone(self, bm, f, dl):
        acc = {}
        for v in f.verts:
            for gi, w in v[dl].items():
                acc[gi] = acc.get(gi, 0.0) + w
        gi = max(acc, key=acc.get) if acc else 0
        return self.body.vertex_groups[gi].name

    def paint_body(self):
        """Bisect colour borders, classify faces, add armour shells; writes Color + UV0."""
        me = self.body.data
        bm = bmesh.new()
        bm.from_mesh(me)
        dl = bm.verts.layers.deform.verify()
        eye_l = bm.faces.layers.bool.get("is_eye")
        for bones, co, no in self.d["cuts"](self):
            sel = [f for f in bm.faces if self.face_bone(bm, f, dl) in bones and not f[eye_l]]
            geom = list({v for f in sel for v in f.verts}) + list({e for f in sel for e in f.edges}) + sel
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, dist=1e-5)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.normal_update()
        col = bm.loops.layers.float_color.new("Color")
        uv = bm.loops.layers.uv.new("UVMap")
        info = {}
        for f in bm.faces:
            c = f.calc_center_median()
            bone = self.face_bone(bm, f, dl)
            if f[eye_l]:
                name, ch = "eye", "flat"
            else:
                name, ch = self.d["regions"](self, c, bone, f.normal)
            info[f.index] = (bone, name)
            _paint_face(f, col, uv, self.color(name), ch)
        # Armour shells: duplicated region faces pushed out along the normals, with a rim.
        for shell in self.d.get("shells", []):
            sel = [f for f in bm.faces if f.index in info and shell["pick"](self, f.calc_center_median(),
                                                                                info[f.index][0], f.normal)]
            if not sel:
                continue
            ret = bmesh.ops.duplicate(bm, geom=sel)
            nf = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMFace)]
            nv = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]
            off = shell["offset"]
            normals = {}
            for v in nv:
                n = Vector((0, 0, 0))
                for f in v.link_faces:
                    n += f.normal
                normals[v] = n.normalized() if n.length > 1e-6 else Vector((0, 0, 1))
            for v in nv:
                v.co += normals[v] * off
            for f in nf:
                c = f.calc_center_median()
                name, ch = shell["paint"](self, c) if callable(shell["paint"]) else shell["paint"]
                _paint_face(f, col, uv, self.color(name), ch)
            boundary = [e for e in {e for f in nf for e in f.edges} if len([lf for lf in e.link_faces if lf in nf]) == 1]
            if boundary:
                ex = bmesh.ops.extrude_edge_only(bm, edges=boundary)
                ev = [g for g in ex["geom"] if isinstance(g, bmesh.types.BMVert)]
                for v in ev:
                    n = Vector((0, 0, 0))
                    for e in v.link_edges:
                        o = e.other_vert(v)
                        if o in normals:
                            n = normals[o]
                    v.co -= n * off * 0.9
                rim = shell.get("rim", shell["paint"] if not callable(shell["paint"]) else ("trim", "flat"))
                for f in {f for v in ev for f in v.link_faces}:
                    _paint_face(f, col, uv, self.color(rim[0]), rim[1])
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.to_mesh(me)
        bm.free()
        me.attributes.remove(me.attributes["is_eye"])
        me.update()

    def color(self, name):
        return self.pal[name]

    # -- rigid / skinned parts -----------------------------------------
    def begin_parts(self):
        self.pbm = bmesh.new()
        self.pdl = self.pbm.verts.layers.deform.verify()
        self.pcol = self.pbm.loops.layers.float_color.new("Color")
        self.puv = self.pbm.loops.layers.uv.new("UVMap")

    def _add(self, tmp, mat, bone, color, ch, weights=None):
        """Merges bmesh `tmp` (local space) into the part mesh with matrix `mat`."""
        tmp.transform(mat)
        vmap = {}
        for v in tmp.verts:
            nv = self.pbm.verts.new(v.co)
            vmap[v] = nv
            if weights is not None:
                for bn, w in weights(v.co).items():
                    nv[self.pdl][self.bone_names.index(bn)] = w
            else:
                nv[self.pdl][self.bone_names.index(bone)] = 1.0
        for f in tmp.faces:
            try:
                nf = self.pbm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            nf.smooth = True
            _paint_face(nf, self.pcol, self.puv, self.color(color), ch)
        tmp.free()

    def box(self, bone, center, size, color, ch="flat", rot=(0, 0, 0), bevel=0.25, taper=(1.0, 1.0), weights=None,
            mat=None):
        """Bevelled box: `size` full extents (m), `bevel` = fraction of the smallest half extent,
        `taper` scales the +Z face (x, y)."""
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        sz = v3(size)
        for v in t.verts:
            v.co = Vector((v.co.x * sz.x, v.co.y * sz.y, v.co.z * sz.z))
            if v.co.z > 0:
                v.co.x *= taper[0]
                v.co.y *= taper[1]
        if bevel > 0:
            bmesh.ops.bevel(t, geom=t.edges[:] + t.verts[:], offset=bevel * 0.5 * min(sz), offset_type="OFFSET",
                            segments=1, affect="EDGES", profile=0.5)
        m = Matrix.Translation(v3(center)) @ _euler(rot) if mat is None else mat
        self._add(t, m, bone, color, ch, weights)

    def cyl(self, bone, p0, p1, r0, r1, color, ch="flat", seg=10, weights=None, caps=True, clip=None, flip=False):
        p0, p1 = v3(p0), v3(p1)
        d = p1 - p0
        t = bmesh.new()
        bmesh.ops.create_cone(t, cap_ends=caps, cap_tris=False, segments=seg, radius1=r0, radius2=r1, depth=d.length)
        for co, no in (clip or []):
            bmesh.ops.bisect_plane(t, geom=t.verts[:] + t.edges[:] + t.faces[:], plane_co=v3(co), plane_no=v3(no),
                                   clear_outer=True)
        if flip:
            bmesh.ops.reverse_faces(t, faces=t.faces[:])
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        m = Matrix.Translation((p0 + p1) / 2) @ q.to_matrix().to_4x4()
        self._add(t, m, bone, color, ch, weights)

    def sphere(self, bone, center, radii, color, ch="flat", seg=(12, 8), rot=(0, 0, 0), clip=None, weights=None):
        """Ellipsoid; `clip` = list of (plane_co_local, plane_no_local) halves removed (unit space)."""
        t = bmesh.new()
        bmesh.ops.create_uvsphere(t, u_segments=seg[0], v_segments=seg[1], radius=1.0)
        for co, no in (clip or []):
            bmesh.ops.bisect_plane(t, geom=t.verts[:] + t.edges[:] + t.faces[:], plane_co=v3(co), plane_no=v3(no),
                                   clear_outer=True)
        r = v3(radii)
        m = Matrix.Translation(v3(center)) @ _euler(rot) @ Matrix.Diagonal(r).to_4x4()
        self._add(t, m, bone, color, ch, weights)

    def torus(self, bone, center, axis, R, r, color, ch="flat", seg=(14, 6)):
        t = bmesh.new()
        vs = []
        for i in range(seg[0]):
            a = 2 * math.pi * i / seg[0]
            ring = []
            for j in range(seg[1]):
                b = 2 * math.pi * j / seg[1]
                ring.append(t.verts.new(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a),
                                         r * math.sin(b))))
            vs.append(ring)
        for i in range(seg[0]):
            for j in range(seg[1]):
                a, b_ = vs[i][j], vs[(i + 1) % seg[0]][j]
                c, d = vs[(i + 1) % seg[0]][(j + 1) % seg[1]], vs[i][(j + 1) % seg[1]]
                t.faces.new([a, b_, c, d])
        q = Vector((0, 0, 1)).rotation_difference(v3(axis).normalized())
        self._add(t, Matrix.Translation(v3(center)) @ q.to_matrix().to_4x4(), bone, color, ch)

    def surface(self, x, z, side=1, y0=None):
        """Point and normal on the body surface along +-Y at (x, z); side=1 front, -1 back."""
        if not hasattr(self, "_bvh"):
            bm = bmesh.new()
            bm.from_mesh(self.body.data)
            self._bvh = BVHTree.FromBMesh(bm)
            bm.free()
        start = Vector((x, side * 1.0 if y0 is None else y0, z))
        hit = self._bvh.ray_cast(start, Vector((0, -side, 0)))
        if hit[0] is None:
            return Vector((x, 0, z)), Vector((0, side, 0))
        return hit[0], hit[1]

    def finish_parts(self):
        me = bpy.data.meshes.new(self.key + "_parts")
        self.pbm.to_mesh(me)
        self.pbm.free()
        ob = bpy.data.objects.new(self.key + "_parts", me)
        bpy.context.scene.collection.objects.link(ob)
        for n in self.bone_names:
            ob.vertex_groups.new(name=n)
        return ob

    # -- armature -------------------------------------------------------
    def build_armature(self, weapon_rest):
        arm = bpy.data.armatures.new(self.key + "_rig")
        ob = bpy.data.objects.new("Armature", arm)
        bpy.context.scene.collection.objects.link(ob)
        _activate(ob)
        bpy.ops.object.mode_set(mode="EDIT")
        for name in self.bone_names[:-1]:
            eb = arm.edit_bones.new(name)
            h, t = self.joints[name]
            eb.head, eb.tail = h, t
            eb.roll = 0.0
        for name in self.bone_names[:-1]:
            if self.parent[name]:
                arm.edit_bones[name].parent = arm.edit_bones[self.parent[name]]
        eb = arm.edit_bones.new("Weapon")
        eb.head = weapon_rest.translation
        eb.tail = weapon_rest.translation + weapon_rest.to_3x3() @ Vector((0, 0.15, 0))
        eb.align_roll(weapon_rest.to_3x3() @ Vector((0, 0, 1)))
        eb.parent = arm.edit_bones["UpperChest"]
        bpy.ops.object.mode_set(mode="OBJECT")
        self.rig = ob
        for pb in ob.pose.bones:
            pb.rotation_mode = "QUATERNION"
        return ob


def _euler(rot):
    from mathutils import Euler
    return Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()


def _paint_face(f, col, uv, rgba, ch):
    u = (CH[ch] + 0.5) / 8.0
    for lp in f.loops:
        lp[col] = rgba
        lp[uv].uv = (u, 0.5)


def _activate(ob):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


def build(key):
    sys.path.insert(0, HERE)
    import hero_defs
    import hero_anims
    hd = hero_defs.HEROES[key]
    reset_scene()
    h = Hero(hd)
    h.build_body()
    h.paint_body()
    weapon_rest = hero_anims.weapon_rest(h)
    h.weapon_rest = weapon_rest
    h.begin_parts()
    hd["parts"](h)
    hero_defs.WEAPONS[hd["weapon"]](h, weapon_rest)
    parts = h.finish_parts()
    rig = h.build_armature(weapon_rest)
    _activate(h.body)
    parts.select_set(True)
    bpy.ops.object.join()
    body = h.body
    body.name = h.key
    body.data.name = h.key
    for p in body.data.polygons:
        p.use_smooth = True
    mat = bpy.data.materials.new("Toon_" + h.key)
    body.data.materials.append(mat)
    body.parent = rig
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    body.data.color_attributes.active_color = body.data.color_attributes["Color"]
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    mocap_info = hero_anims.author_all(h, use_mocap="--scripted" not in sys.argv)
    out = os.path.join(OUT_DIR, h.key, h.key + ".glb")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    _activate(rig)
    body.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_vertex_color="NAME", export_vertex_color_name="Color",
                              export_all_vertex_colors=False, export_skins=True, export_yup=True,
                              export_force_sampling=True, export_optimize_animation_size=True,
                              export_materials="EXPORT", export_image_format="NONE", export_tangents=False,
                              export_def_bones=False, export_leaf_bone=False)
    side = {"clips": mocap_info, "credit": "The data used in this project was obtained from mocap.cs.cmu.edu. "
            "The database was created with funding from NSF EIA-0196217."} if mocap_info else {"clips": {}}
    with open(out[:-4] + ".anim.json", "w") as fh:
        json.dump(side, fh, indent=1, sort_keys=True)
    print("built %s: %d tris, %d bones, %d clips, %.2f MB" % (out, tris, len(rig.data.bones), len(bpy.data.actions),
                                                             os.path.getsize(out) / 1e6))


if __name__ == "__main__":
    if "--out" in sys.argv:
        OUT_DIR = sys.argv[sys.argv.index("--out") + 1]
    keys = [a for i, a in enumerate(sys.argv[1:]) if not a.startswith("--") and sys.argv[i] != "--out"]
    for k in keys or ["ryker", "vesper"]:
        build(k)
