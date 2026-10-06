"""World assets on the hero pipeline (docs/model-pipeline.md, docs/art-bible.md).

A WorldAsset is a Hero without a body or a rig: the same bevelled part builders
(box / cyl / sphere / torus from build_hero.Hero), the same colour-block
channels (flat, team, emit, team_emit, chrome), the same painted-light bake
(hero_paint.bake_textures: AO, edge highlights, crease ink, hatching, wear) and
the same texture contract (<key>_albedo / _normal / _mask.png), so the runtime
uses the heroes' spatial_char_toon_rigged material unchanged.

Differences from a hero:
  * no body, no skeleton, no animation: everything is a rigid part on one
    "Root" bone (the bone is never exported);
  * parts are grouped into named pieces (`with a.piece("ring_0"):`). The bake runs
    once on all pieces (one atlas); the export splits them back into one mesh
    per piece, so the runtime can move pieces (rings, prongs, damage stages);
  * a world-scale bevel (`harden(width)`) instead of the hero's 1.8 mm one;
  * hatch spacing follows the texel size (big assets have fewer px per metre).

Usage: see tools/art/world/uplink.py.
"""
import contextlib
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(ART))
sys.path.insert(0, ART)

import bpy  # noqa: E402  (bpy must load before bmesh)
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

import build_hero  # noqa: E402
from build_hero import Hero, _activate, srgb  # noqa: E402

OUT_ROOT = os.path.join(ROOT, "assets", "models", "world")


class WorldAsset(Hero):
    """`palette`: name -> hex. `paint`: hero_paint overrides. `tex`: map size."""

    def __init__(self, key, palette, paint=None, tex=1024, texel_m=None):
        self.key = key
        self.d = {"key": key, "height": 1.85, "palette": palette, "paint": dict(paint or {})}
        self.pal = {k: srgb(v) for k, v in palette.items()}
        self.names = {}
        self.bone_names = ["Root"]
        self.joints = {"Root": (Vector((0, 0, 0)), Vector((0, 0, 0.1)))}
        self.parent = {"Root": None}
        self.tex = tex
        # Hatching: >= 3 texels between lines, never finer than the heroes' 2.4 cm.
        if texel_m:
            p = self.d["paint"]
            p.setdefault("hatch_spacing", max(0.024, 3.2 * texel_m))
            p.setdefault("ao_dist", max(0.025, 2.0 * texel_m))
            p.setdefault("ink_px", 3)
        self._piece = "main"
        self.pieces = ["main"]
        self.apart = {}
        self.T = {}
        self._t = time.time()
        build_hero.reset_scene()
        self.begin_parts()
        self.ppiece = self.pbm.faces.layers.int.new("w_piece")

    # ---------------------------------------------------------------- pieces
    @contextlib.contextmanager
    def piece(self, name, apart=None):
        """Faces added inside belong to piece `name` (one mesh node in the glb).
        `apart` = (x, y, z): the piece is built that far away from the rest, so the
        AO / crease bake does not shade it against parts it is never shown with
        (alternative or optional pieces), and is exported back in place."""
        prev = self._piece
        if name not in self.pieces:
            self.pieces.append(name)
        self._piece = name
        n0 = len(self.pbm.faces)
        try:
            yield self
        finally:
            self._piece = prev
            if apart is not None:
                self.pbm.faces.ensure_lookup_table()
                vs = {v for f in list(self.pbm.faces)[n0:] for v in f.verts}
                for v in vs:
                    v.co += Vector(apart)
                self.apart[name] = tuple(apart)

    def _add(self, tmp, mat, bone, color, ch, weights=None, kind=None):
        # Zero-area faces (a clip plane on an existing vertex ring, a cone tip) unwrap
        # to huge slivers and wreck the atlas pack: drop them before they join.
        bmesh.ops.dissolve_degenerate(tmp, dist=1e-5, edges=tmp.edges[:])
        for f in [f for f in tmp.faces if f.calc_area() < 1e-9]:
            tmp.faces.remove(f)
        n0 = len(self.pbm.faces)
        super()._add(tmp, mat, "Root", color, ch, None, kind)
        self.pbm.faces.ensure_lookup_table()
        pid = self.pieces.index(self._piece)
        for i in range(n0, len(self.pbm.faces)):
            self.pbm.faces[i][self.ppiece] = pid

    def lap(self, name):
        self.T[name] = time.time() - self._t
        self._t = time.time()

    # ---------------------------------------------------------------- helpers
    def ring_of(self, n, radius, y, fn, phase=0.0):
        """Calls fn(i, angle, x, z) for n points on a circle at height y (Blender: Z up)."""
        for i in range(n):
            a = phase + 2 * math.pi * i / n
            fn(i, a, math.cos(a) * radius, math.sin(a) * radius)

    def prism(self, center, radius, height, sides, color, ch="flat", bevel=0.0, rot_deg=0.0, taper=1.0, inset=None):
        """Faceted column (n-gon prism), optionally tapered and with a bevel on its edges.
        `inset` = (depth, ratio): every side face gets an inset panel (seam + recess)."""
        t = bmesh.new()
        bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=sides, radius1=radius,
                              radius2=radius * taper, depth=height)
        bmesh.ops.rotate(t, verts=t.verts, cent=(0, 0, 0),
                         matrix=__import__("mathutils").Matrix.Rotation(math.radians(rot_deg), 3, "Z"))
        if inset:
            sides_f = [f for f in t.faces if abs(f.normal.z) < 0.5]
            r = bmesh.ops.inset_individual(t, faces=sides_f, thickness=min(radius, height) * inset[1],
                                           depth=-inset[0], use_even_offset=True)
            _ = r
        if bevel > 0:
            bmesh.ops.bevel(t, geom=[e for e in t.edges if e.calc_face_angle(0) > math.radians(30)],
                            offset=bevel, offset_type="OFFSET", segments=1, affect="EDGES", profile=0.5)
        from mathutils import Matrix
        self._add(t, Matrix.Translation(Vector(center)), "Root", color, ch)

    # ---------------------------------------------------------------- build
    def finish(self, bevel_m=0.02, smooth_deg=40, drop_floor=False):
        """Joins the parts into one object, world-scale bevel + weighted normals.
        `drop_floor`: deletes the downward faces lying on the floor (z < 3 cm), which
        nobody sees on a grounded asset but which take atlas space."""
        ob = self.finish_parts()
        ob.name = ob.data.name = self.key
        _activate(ob)
        if drop_floor:
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            gone = [f for f in bm.faces if f.normal.z < -0.99 and all(v.co.z < 0.03 for v in f.verts)]
            bmesh.ops.delete(bm, geom=gone, context="FACES_ONLY")
            bm.to_mesh(ob.data)
            bm.free()
            print("finish %s: dropped %d floor faces" % (self.key, len(gone)))
        if bevel_m > 0:  # 0: the parts' own bevels only (tight budgets, e.g. Wardlings)
            m = ob.modifiers.new("w_bevel", "BEVEL")
            m.width = bevel_m
            m.segments = 1
            m.limit_method = "ANGLE"
            m.angle_limit = math.radians(smooth_deg)
            m.use_clamp_overlap = True
            bpy.ops.object.modifier_apply(modifier=m.name)
            # the bevel collapses thin parts (floor chevrons) into zero-area faces
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:])
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_area() < 1e-9], context="FACES")
            bm.to_mesh(ob.data)
            bm.free()
        wn = ob.modifiers.new("w_wn", "WEIGHTED_NORMAL")
        wn.keep_sharp = True
        bpy.ops.object.modifier_apply(modifier=wn.name)
        for p in ob.data.polygons:
            p.use_smooth = True
        self.ob = ob
        self.lap("geometry")
        return ob

    def bake(self, out_dir):
        import hero_hd
        import hero_paint
        hero_hd.prep_palette(self)
        os.makedirs(out_dir, exist_ok=True)
        sizes = hero_paint.bake_textures(self, self.ob, out_dir, self.tex)
        self.lap("texture")
        return sizes

    def export(self, out_dir, sizes=None, centred=(), rebase=None):
        """One mesh node per piece (shared atlas), one material Toon_<key>, glb + report.
        Pieces named in `centred` get their pivot at their bounds centre (moving parts:
        the node position is then the part's centre); the rest keep the asset origin.
        `rebase` = {piece: (x, y, z)}: that point (Blender space) becomes the piece's
        local origin and the node sits at the asset origin. For parts that are built
        apart from the rest (so the bake does not shade them against each other) and
        placed or swung by the runtime (bracket corners, legs at the hip)."""
        ob = self.ob
        ob.data.materials.clear()
        ob.data.materials.append(bpy.data.materials.new("Toon_" + self.key))
        objs = _split_pieces(ob, self.pieces)
        from mathutils import Matrix
        rebase = dict(self.apart, **(rebase or {}))
        for o in objs:
            if o.name in centred:
                _activate(o)
                o.select_set(True)
                bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
            if rebase and o.name in rebase:
                o.data.transform(Matrix.Translation(-Vector(rebase[o.name])))
        for o in objs:
            if "Color" in o.data.color_attributes:
                o.data.color_attributes.active_color = o.data.color_attributes["Color"]
        out = os.path.join(out_dir, self.key + ".glb")
        _activate(objs[0])
        for o in objs:
            o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_animations=False,
                                  export_vertex_color="NAME", export_vertex_color_name="Color",
                                  export_all_vertex_colors=False, export_skins=False, export_yup=True,
                                  export_materials="EXPORT", export_image_format="NONE", export_tangents=False)
        self.lap("export")
        tris = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs}
        P = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
        lo = Vector((min(p.x for p in P), min(p.y for p in P), min(p.z for p in P)))
        hi = Vector((max(p.x for p in P), max(p.y for p in P), max(p.z for p in P)))
        print("built %s: %d tris in %d pieces %s, bounds %.1f x %.1f x %.1f m (x, depth, height), %.2f MB, textures %s" % (
            out, sum(tris.values()), len(objs), tris, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z,
            os.path.getsize(out) / 1e6, {k: round(v / 1e6, 2) for k, v in (sizes or {}).items()}))
        print("timing %s: %s, total %.0f s" % (self.key, ", ".join("%s %.0f s" % kv for kv in self.T.items()),
                                               sum(self.T.values())))
        return out


def _split_pieces(ob, pieces):
    """Splits `ob` by the w_piece face attribute into one object per piece."""
    me = ob.data
    attr = me.attributes.get("w_piece")
    if attr is None or len(pieces) == 1:
        return [ob]
    ids = [attr.data[p.index].value for p in me.polygons]
    out = []
    for pid, name in enumerate(pieces):
        if pid not in ids:
            continue
        o = ob.copy()
        o.data = me.copy()
        o.name = o.data.name = name
        bpy.context.scene.collection.objects.link(o)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        lay = bm.faces.layers.int.get("w_piece")
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f[lay] != pid], context="FACES")
        bm.to_mesh(o.data)
        bm.free()
        o.data.attributes.remove(o.data.attributes["w_piece"])
        out.append(o)
    bpy.data.objects.remove(ob)
    return out


def out_dir(key, argv=None):
    argv = argv if argv is not None else sys.argv
    root = argv[argv.index("--out") + 1] if "--out" in argv else OUT_ROOT
    return os.path.join(root, key)
