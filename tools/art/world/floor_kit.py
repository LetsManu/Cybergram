"""Painted floor trim sheet for spatial_env_panel.gdshader (docs/assets/floor.md).

Eight square floor tiles modelled in Blender (bevelled slabs, plates, bolts,
grate bars, a drain cover, a cable-trench cover, a hazard-striped kerb), baked
selected-to-active onto one plane (tangent normal, AO, bevel edge, position,
paint ids), then painted in numpy in the heroes' language (hero_paint.py:
crease AO, bright edge strokes, crease ink, shadow-side hatching, grit, wear).

Sheet: 4 x 2 slots of 512 px = 2048 x 1024. A tile is modelled at 2 m, the
shader stretches it over one panel (panel_size 1.5-4 m), so the texel density
is 512 / panel_size: 128 px/m on 4 m panels, 171 on 3 m, 256 on 2 m
(docs/art-bible.md §2: terrain 64-128 + tiling detail, kit 128-200).

Slot order (row-major, row 0 = top of the image) = the shader's variant index:
  0 plain slab     1 inset panel     2 bolted tread plate   3 worn / cracked tiles
  4 grate          5 drain cover     6 cable-trench cover   7 hazard-stripe kerb

Outputs (assets/textures/world/floor/):
  floor_tiles_albedo.png  RGB greyscale VALUE (0.5 = the material's base_color;
                          the shader multiplies by 2 * base_color): stone grain,
                          ink, hatching, cracks, stripes, grit
  floor_tiles_normal.png  OpenGL tangent normal (R +u, G image-up)
  floor_tiles_mask.png    R AO / wear (1 = open), G edge highlight, B grime,
                          A = 1 (the shader's "maps are bound" test)

Decal atlas (--decals): 8 x 2 cells of 256 px = 2048 x 512 RGBA, painted in numpy
(flat paint + ink stroke + chips + grit, the same language). Cell order = DECALS =
WorldDecalsDef.cells: arrows (white, Accent tier at runtime), hazard chevrons,
Concord / Syndicate glyphs (white, tinted by the team colour at runtime), crew tags
(sign_pink / sign_teal / holo_white only), cracks, grime, oil, puddle, scorch.
Output: assets/textures/world/decals/world_decals_albedo.png.

Run:  /tmp/venv/bin/python tools/art/world/floor_kit.py [--out DIR] [--preview PNG]
      /tmp/venv/bin/python tools/art/world/floor_kit.py --decals [--out DIR]
Then: tools/art/tex_import.sh after the first Godot import.
"""
import math
import os
import random
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(ART))
sys.path.insert(0, ART)

import bpy  # noqa: E402  (bpy before bmesh)
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

from hero_hd import _fbm  # noqa: E402
from hero_paint import _blur, _dilate, _lines  # noqa: E402

OUT = os.path.join(ROOT, "assets", "textures", "world", "floor")
KEY = "floor_tiles"
COLS, ROWS, SLOT_PX = 4, 2, 512
TILE_M = 2.0           # modelled tile size (m)
HALF = TILE_M * 0.5
SEED = 7

# paint kinds (face attribute fk_kind)
STONE, METAL, STRIPE, PIT, RUBBER = 0, 1, 2, 3, 4
NAMES = ["plain slab", "inset panel", "bolted tread plate", "worn cracked tiles", "grate", "drain cover",
         "cable trench", "hazard kerb"]

PAINT = {
    "ink": 0.07,            # ink value
    "edge_bevel": 0.02,     # tile border chamfer (m)
    "hatch_spacing": 0.03,  # m between hatch lines (>= 3 texels at 256 px/m)
    "hatch_width": 0.32,
    "hatch": 0.45,
    "grit": 0.06,
    "grain": 0.05,
    "ink_px": 3,
}


# ---------------------------------------------------------------- geometry
class Kit:
    """Accumulates bevelled parts into one bmesh with per-face paint ids."""

    def __init__(self):
        self.bm = bmesh.new()
        self.val = self.bm.faces.layers.float.new("fk_val")
        self.kind = self.bm.faces.layers.float.new("fk_kind")
        self.off = Vector((0, 0, 0))

    def _merge(self, t, val, kind, bevel):
        if bevel > 0:
            bmesh.ops.bevel(t, geom=[e for e in t.edges if e.calc_face_angle(0) > math.radians(30)], offset=bevel,
                            offset_type="OFFSET", segments=2, affect="EDGES", profile=0.5, clamp_overlap=True)
        vmap = {}
        for v in t.verts:
            vmap[v] = self.bm.verts.new(v.co + self.off)
        for f in t.faces:
            try:
                nf = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            nf[self.val] = val
            nf[self.kind] = kind
            nf.smooth = f.smooth
        t.free()

    def box(self, x0, x1, y0, y1, z0, z1, val, kind=STONE, bevel=0.006, rot=0.0):
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
        bmesh.ops.scale(t, vec=(abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)), verts=t.verts)
        if rot:
            bmesh.ops.rotate(t, verts=t.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(rot, 3, "Z"))
        bmesh.ops.translate(t, vec=(cx, cy, (z0 + z1) * 0.5), verts=t.verts)
        self._merge(t, val, kind, bevel)

    def prism(self, pts, z0, z1, val, kind=STONE, bevel=0.006):
        """Extruded 2D polygon (counter-clockwise points)."""
        t = bmesh.new()
        vs = [t.verts.new((x, y, z0)) for x, y in pts]
        f = t.faces.new(vs)
        if f.normal.z > 0:
            f.normal_flip()
        r = bmesh.ops.extrude_face_region(t, geom=[f])
        top = [v for v in r["geom"] if isinstance(v, bmesh.types.BMVert)]
        bmesh.ops.translate(t, vec=(0, 0, z1 - z0), verts=top)
        bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
        self._merge(t, val, kind, bevel)

    def cyl(self, x, y, r, z0, z1, val, kind=METAL, seg=20, bevel=0.003, axis="Z", length=None):
        t = bmesh.new()
        depth = (z1 - z0) if axis == "Z" else length
        bmesh.ops.create_cone(t, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=depth)
        if axis == "X":
            bmesh.ops.rotate(t, verts=t.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
            bmesh.ops.translate(t, vec=(x, y, (z0 + z1) * 0.5), verts=t.verts)
        elif axis == "Y":
            bmesh.ops.rotate(t, verts=t.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
            bmesh.ops.translate(t, vec=(x, y, (z0 + z1) * 0.5), verts=t.verts)
        else:
            bmesh.ops.translate(t, vec=(x, y, (z0 + z1) * 0.5), verts=t.verts)
        self._merge(t, val, kind, bevel)

    def bolt(self, x, y, r=0.022, h=0.012, z=0.0):
        self.cyl(x, y, r, z, z + h, 0.62, METAL, seg=6, bevel=0.003)

    def arc(self, r0, r1, a0, a1, z0, z1, val, kind=METAL, n=10, bevel=0.003):
        pts = [(math.cos(a0 + (a1 - a0) * i / n) * r1, math.sin(a0 + (a1 - a0) * i / n) * r1) for i in range(n + 1)]
        pts += [(math.cos(a1 - (a1 - a0) * i / n) * r0, math.sin(a1 - (a1 - a0) * i / n) * r0) for i in range(n + 1)]
        self.prism(pts, z0, z1, val, kind, bevel)


def slab(k, x0=-HALF, x1=HALF, y0=-HALF, y1=HALF, val=0.55, top=0.0, kind=STONE, bevel=None):
    k.box(x0, x1, y0, y1, top - 0.12, top, val, kind, PAINT["edge_bevel"] if bevel is None else bevel)


def t_plain(k, rnd):
    slab(k, val=0.56)
    # a shallow chip on one corner: the slab reads as stone, not a quad
    k.prism([(HALF - 0.16, -HALF + 0.001), (HALF - 0.001, -HALF + 0.001), (HALF - 0.001, -HALF + 0.12)],
            -0.02, -0.012, 0.5, STONE, 0.004)


def t_inset(k, rnd):
    b = 0.24
    for (x0, x1, y0, y1) in ((-HALF, HALF, -HALF, -HALF + b), (-HALF, HALF, HALF - b, HALF),
                             (-HALF, -HALF + b, -HALF + b, HALF - b), (HALF - b, HALF, -HALF + b, HALF - b)):
        k.box(x0, x1, y0, y1, -0.12, 0.0, 0.58, STONE, 0.014)
    k.box(-HALF + b + 0.025, HALF - b - 0.025, -HALF + b + 0.025, HALF - b - 0.025, -0.12, -0.018, 0.47, STONE, 0.012)
    for sx in (-1, 1):
        for sy in (-1, 1):
            k.bolt(sx * (HALF - b * 0.5), sy * (HALF - b * 0.5), 0.03, 0.012)


def t_tread(k, rnd):
    slab(k, val=0.5, kind=METAL, bevel=0.016)
    n = 11
    step = (TILE_M - 0.3) / n
    for i in range(n):
        for j in range(n):
            x = -HALF + 0.15 + (i + 0.5) * step
            y = -HALF + 0.15 + (j + 0.5) * step
            rot = math.radians(45 if (i + j) % 2 == 0 else -45)
            k.box(x - 0.055, x + 0.055, y - 0.013, y + 0.013, 0.0, 0.006, 0.56, METAL, 0.003, rot=rot)
    for t in range(-4, 5):
        p = t * (TILE_M - 0.1) / 8.0
        for (x, y) in ((p, -HALF + 0.05), (p, HALF - 0.05), (-HALF + 0.05, p), (HALF - 0.05, p)):
            if abs(x) < HALF - 0.02 and abs(y) < HALF - 0.02:
                k.bolt(x, y, 0.018, 0.01)


def t_cracked(k, rnd):
    n = 4
    s = TILE_M / n
    gap = 0.012
    for i in range(n):
        for j in range(n):
            x0, y0 = -HALF + i * s + gap, -HALF + j * s + gap
            x1, y1 = x0 + s - 2 * gap, y0 + s - 2 * gap
            sink = -rnd.uniform(0.0, 0.012)
            v = 0.52 + rnd.uniform(-0.05, 0.05)
            if (i, j) in ((1, 2), (3, 0)):  # cracked in two along a zig-zag
                zz = [(x0, y0 + s * 0.42)]
                for q in range(1, 5):
                    zz.append((x0 + (x1 - x0) * q / 5, y0 + s * (0.3 + 0.25 * rnd.random())))
                zz.append((x1, y0 + s * 0.55))
                lo = [(x0, y0), (x1, y0)] + [(x, y - 0.006) for x, y in reversed(zz)]
                hi = [(x, y + 0.006) for x, y in zz] + [(x1, y1), (x0, y1)]
                k.prism(lo, -0.12, sink, v, STONE, 0.008)
                k.prism(hi, -0.12, sink - 0.008, v - 0.03, STONE, 0.008)
            elif (i, j) == (2, 3):  # broken corner: a missing chunk shows the bed below
                k.prism([(x0, y0), (x1, y0), (x1, y0 + s * 0.45), (x0 + s * 0.5, y1), (x0, y1)], -0.12, sink, v,
                        STONE, 0.008)
                k.box(x0, x1, y0, y1, -0.16, -0.06, 0.3, PIT, 0.004)
            else:
                k.box(x0, x1, y0, y1, -0.12, sink, v, STONE, 0.01)
    k.box(-HALF, HALF, -HALF, HALF, -0.2, -0.1, 0.25, PIT, 0.0)  # grout bed


def t_grate(k, rnd):
    f = 0.16
    for (x0, x1, y0, y1) in ((-HALF, HALF, -HALF, -HALF + f), (-HALF, HALF, HALF - f, HALF),
                             (-HALF, -HALF + f, -HALF + f, HALF - f), (HALF - f, HALF, -HALF + f, HALF - f)):
        k.box(x0, x1, y0, y1, -0.12, 0.0, 0.5, METAL, 0.012)
    n = 13
    w = TILE_M - 2 * f
    for i in range(n):
        x = -HALF + f + (i + 0.5) * w / n
        k.box(x - 0.022, x + 0.022, -HALF + f - 0.01, HALF - f + 0.01, -0.07, -0.008, 0.55, METAL, 0.005)
    for y in (-0.35, 0.35):
        k.box(-HALF + f, HALF - f, y - 0.03, y + 0.03, -0.14, -0.07, 0.4, METAL, 0.005)
    k.box(-HALF + f, HALF - f, -HALF + f, HALF - f, -0.42, -0.38, 0.12, PIT, 0.0)
    for x in (-0.4, 0.15, 0.5):  # pipes in the pit
        k.cyl(x, 0, 0.05, -0.37, -0.27, 0.3, METAL, axis="Y", length=w)
    for sx in (-1, 1):
        for sy in (-1, 1):
            k.bolt(sx * (HALF - f * 0.5), sy * (HALF - f * 0.5), 0.024, 0.01)


def t_drain(k, rnd):
    slab(k, val=0.56)
    k.cyl(0, 0, 0.66, -0.004, 0.012, 0.5, METAL, seg=48, bevel=0.006)
    k.cyl(0, 0, 0.6, 0.012, 0.014, 0.12, PIT, seg=48, bevel=0.0)
    for r0, r1, n in ((0.1, 0.2, 6), (0.26, 0.38, 10), (0.44, 0.56, 14)):
        for i in range(n):
            a0 = 2 * math.pi * i / n + 0.06
            a1 = 2 * math.pi * (i + 1) / n - 0.06
            k.arc(r0, r1, a0, a1, 0.014, 0.026, 0.55, METAL, n=6)
    k.cyl(0, 0, 0.05, 0.014, 0.03, 0.6, METAL, seg=12)
    for i in range(6):
        a = 2 * math.pi * i / 6
        k.bolt(math.cos(a) * 0.62, math.sin(a) * 0.62, 0.016, 0.02, 0.006)


def t_trench(k, rnd):
    hw = 0.3
    slab(k, -HALF, HALF, -HALF, -hw, 0.56)
    slab(k, -HALF, HALF, hw, HALF, 0.56)
    k.box(-HALF, HALF, -hw, hw, -0.4, -0.36, 0.12, PIT, 0.0)
    for y in (-0.15, -0.02, 0.12):  # cable bundle
        k.cyl(0, y, 0.055, -0.36, -0.25, 0.2, RUBBER, seg=12, axis="X", length=TILE_M)
    xs = [-HALF, -0.36, 0.3, HALF]
    for p in range(3):
        x0, x1 = xs[p] + 0.012, xs[p + 1] - 0.012
        if p == 1:  # one cover lifted off: the cables show
            continue
        k.box(x0, x1, -hw + 0.01, hw - 0.01, -0.03, 0.004, 0.46, METAL, 0.008)
        cx = (x0 + x1) * 0.5
        k.box(cx - 0.09, cx + 0.09, -0.025, 0.025, -0.006, 0.0045, 0.15, PIT, 0.004)  # finger slot
        for sx in (x0 + 0.05, x1 - 0.05):
            for sy in (-hw + 0.06, hw - 0.06):
                k.bolt(sx, sy, 0.016, 0.008, 0.004)
    k.box(-0.36 + 0.012, 0.3 - 0.012, -hw - 0.02, -hw + 0.03, -0.06, -0.02, 0.4, METAL, 0.004)  # ledge


def t_hazard(k, rnd):
    slab(k, -HALF, HALF, -HALF, HALF - 0.5, 0.56)
    k.box(-HALF, HALF, HALF - 0.5, HALF, -0.12, 0.03, 0.8, STRIPE, 0.02)  # painted kerb
    for i in range(5):
        k.bolt(-HALF + 0.2 + i * 0.4, HALF - 0.25, 0.02, 0.008, 0.03)


TILES = [t_plain, t_inset, t_tread, t_cracked, t_grate, t_drain, t_trench, t_hazard]


def slot_center(i):
    """Blender XY centre of slot i (row 0 = top of the image = high Y)."""
    c, r = i % COLS, i // COLS
    return Vector(((c + 0.5) * TILE_M, (ROWS - r - 0.5) * TILE_M, 0.0))


def build_geometry():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    k = Kit()
    rnd = random.Random(SEED)
    for i, fn in enumerate(TILES):
        k.off = slot_center(i)
        fn(k, rnd)
    me = bpy.data.meshes.new("floor_high")
    k.bm.to_mesh(me)
    k.bm.free()
    for p in me.polygons:
        p.use_smooth = True
    hi = bpy.data.objects.new("floor_high", me)
    bpy.context.scene.collection.objects.link(hi)
    # low: one plane over the sheet, UV 0..1
    lme = bpy.data.meshes.new("floor_low")
    W, H = COLS * TILE_M, ROWS * TILE_M
    lme.from_pydata([(0, 0, 0), (W, 0, 0), (W, H, 0), (0, H, 0)], [], [(0, 1, 2, 3)])
    uv = lme.uv_layers.new(name="UV")
    for li, (u, v) in zip(range(4), ((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[li].uv = (u, v)
    lo = bpy.data.objects.new("floor_low", lme)
    bpy.context.scene.collection.objects.link(lo)
    print("floor_kit: %d faces in %d tiles" % (len(me.polygons), len(TILES)))
    return hi, lo


# ---------------------------------------------------------------- bake
def _node_mat(name, build):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    build(nt, out)
    return m


def _attr(nt, name):
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_name = name
    a.attribute_type = "GEOMETRY"
    return a.outputs["Fac"]


def _emit(fn):
    def build(nt, out):
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(fn(nt), em.inputs["Color"])
        nt.links.new(em.outputs[0], out.inputs["Surface"])
    return build


def _combine(nt, *socks):
    c = nt.nodes.new("ShaderNodeCombineXYZ")
    for i, s in enumerate(socks):
        if isinstance(s, (int, float)):
            c.inputs[i].default_value = s
        else:
            nt.links.new(s, c.inputs[i])
    return c.outputs[0]


def bake(hi, lo, src_mat, w, h, kind="EMIT", samples=1):
    img = bpy.data.images.new("bk", w, h, alpha=False, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    hi.data.materials.clear()
    hi.data.materials.append(src_mat)
    tm = bpy.data.materials.new("target")
    tm.use_nodes = True
    node = tm.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    tm.node_tree.nodes.active = node
    lo.data.materials.clear()
    lo.data.materials.append(tm)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.render.bake.margin = 0
    for o in bpy.context.scene.objects:
        o.select_set(False)
    hi.select_set(True)
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    bpy.ops.object.bake(type=kind, use_selected_to_active=True, cage_extrusion=0.5, max_ray_distance=1.0,
                        normal_space="TANGENT", margin=0)
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    return a.reshape(h, w, 4)[::-1]  # row 0 = top


def bake_all(hi, lo, ss):
    if bpy.context.scene.world is None:
        bpy.context.scene.world = bpy.data.worlds.new("w")
    W, H = COLS * SLOT_PX, ROWS * SLOT_PX
    t = time.time()
    ids = bake(hi, lo, _node_mat("ids", _emit(lambda nt: _combine(nt, _attr(nt, "fk_val"), _attr(nt, "fk_kind"), 0.0))),
               W * ss, H * ss)
    pos = bake(hi, lo, _node_mat("pos", _emit(lambda nt: nt.nodes.new("ShaderNodeTexCoord").outputs["Object"])),
               W * ss, H * ss)

    def shade_n(nt):
        bev = nt.nodes.new("ShaderNodeBevel")
        bev.samples = 8
        bev.inputs["Radius"].default_value = 0.012
        return bev.outputs[0]
    nrm_w = bake(hi, lo, _node_mat("nw", _emit(shade_n)), W * ss, H * ss, samples=4)

    def ao_edge(nt):
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.samples = 16
        ao.inputs["Distance"].default_value = 0.18
        bev = nt.nodes.new("ShaderNodeBevel")
        bev.samples = 8
        bev.inputs["Radius"].default_value = 0.012
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        d = nt.nodes.new("ShaderNodeVectorMath")
        d.operation = "DOT_PRODUCT"
        nt.links.new(bev.outputs[0], d.inputs[0])
        nt.links.new(geo.outputs["Normal"], d.inputs[1])
        one = nt.nodes.new("ShaderNodeMath")
        one.operation = "SUBTRACT"
        one.inputs[0].default_value = 1.0
        nt.links.new(d.outputs["Value"], one.inputs[1])
        return _combine(nt, ao.outputs["AO"], one.outputs[0], 0.0)
    aoe = bake(hi, lo, _node_mat("aoe", _emit(ao_edge)), W, H, samples=16)

    def nmat(nt, out):
        bsdf = nt.nodes.new("ShaderNodeBsdfDiffuse")
        bev = nt.nodes.new("ShaderNodeBevel")
        bev.samples = 8
        bev.inputs["Radius"].default_value = 0.008
        nt.links.new(bev.outputs[0], bsdf.inputs["Normal"])
        nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    nrm = bake(hi, lo, _node_mat("nrm", nmat), W, H, kind="NORMAL", samples=4)
    print("floor_kit: bakes %.0f s" % (time.time() - t))
    return ids, pos, nrm_w, aoe, nrm


# ---------------------------------------------------------------- paint
def _down(a, ss):
    if ss == 1:
        return a
    h, w = a.shape[0] // ss, a.shape[1] // ss
    return a.reshape(h, ss, w, ss, *a.shape[2:]).mean(axis=(1, 3))


def _crack_strokes(S, rnd, slots, n_per, px_per_m):
    """Ink crack polylines (random walks) inside the given slots, rasterised at S scale."""
    from PIL import Image, ImageDraw
    W, H = COLS * SLOT_PX * S, ROWS * SLOT_PX * S
    im = Image.new("L", (W, H), 0)
    dr = ImageDraw.Draw(im)
    for si, n in zip(slots, n_per):
        c, r = si % COLS, si // COLS
        ox, oy = c * SLOT_PX * S, r * SLOT_PX * S
        for _ in range(n):
            x = ox + rnd.uniform(0.15, 0.85) * SLOT_PX * S
            y = oy + rnd.uniform(0.15, 0.85) * SLOT_PX * S
            a = rnd.uniform(0, 2 * math.pi)
            pts = [(x, y)]
            for _s in range(rnd.randint(5, 10)):
                a += rnd.uniform(-0.7, 0.7)
                L = rnd.uniform(0.04, 0.1) * px_per_m * S
                x = min(max(x + math.cos(a) * L, ox + 4), ox + SLOT_PX * S - 4)
                y = min(max(y + math.sin(a) * L, oy + 4), oy + SLOT_PX * S - 4)
                pts.append((x, y))
            dr.line(pts, fill=255, width=max(2, S * 2))
            if rnd.random() < 0.6:  # a branch
                b = pts[len(pts) // 2]
                ba = a + rnd.choice((-1, 1)) * 1.1
                dr.line([b, (b[0] + math.cos(ba) * 0.12 * px_per_m * S, b[1] + math.sin(ba) * 0.12 * px_per_m * S)],
                        fill=200, width=max(1, S))
    return np.asarray(im, dtype=np.float32) / 255.0


def paint(ids, pos, nrm_w, aoe, nrm, ss):
    rnd = random.Random(SEED + 1)
    val = ids[..., 0]
    kind = np.rint(ids[..., 1]).astype(np.int32)
    P = pos[..., :3]
    n3 = nrm_w[..., :3]
    n3 = n3 / np.maximum(np.linalg.norm(n3, axis=-1, keepdims=True), 1e-6)
    Hs, Ws = val.shape
    px_per_m = SLOT_PX / TILE_M
    # AO / edge at 1x, upsampled to the paint resolution
    ao1 = np.clip(aoe[..., 0], 0, 1)
    edge1 = np.clip((aoe[..., 1] - 0.03) / 0.15, 0, 1)
    ao = np.repeat(np.repeat(ao1, ss, 0), ss, 1)
    edge = np.repeat(np.repeat(edge1, ss, 0), ss, 1)
    ao_s = np.sqrt(np.clip(_blur(ao, 1.5 * ss), 0, 1))
    crease = 1.0 - ao_s
    lam = n3[..., 2]  # painted key light from straight above: tile rotation keeps it consistent
    lit = np.clip((lam - 0.55) / 0.2, 0, 1)
    lit = lit * lit * (3 - 2 * lit)
    convex = np.clip((ao - 0.8) * 5.0, 0, 1)
    # Edge strokes: the chamfers seen from above are where the shading normal tilts off
    # vertical on unoccluded geometry (the Bevel-node delta is tiny on modelled chamfers).
    edge = np.maximum(edge, np.clip((0.99 - lam) / 0.18, 0, 1) * convex)
    # value: base, stone grain / metal brushing, painted terminator, grit
    v = val.copy()
    grain = _fbm(P * np.array([3.0, 3.0, 3.0]) + 5.0, 3) - 0.5
    fine = _fbm(P * 18.0 + 2.0, 2) - 0.5
    is_stone = (kind == STONE).astype(np.float32)
    is_metal = (kind == METAL).astype(np.float32)
    v = v * (1.0 + is_stone * (PAINT["grain"] * 2 * grain + 0.05 * fine))
    brush = np.sin(P[..., 0] * 260.0 + 3.0 * _fbm(P * 6.0, 2)) * 0.5 + 0.5
    v = v * (1.0 + is_metal * 0.03 * (brush - 0.5))
    v = v * (0.72 + 0.28 * lit)  # painted shadow on the steep faces
    v = v * (1.0 + PAINT["grit"] * (_fbm(P * 40.0 + 9.0, 2) - 0.5) * 2)
    # hazard stripes on the kerb (diagonal, tile space)
    stripe = (kind == STRIPE).astype(np.float32)
    sv = _lines((P[..., 0] + P[..., 1]) / 0.22, 0.5, 0.02)
    v = np.where(stripe > 0.5, np.where(sv > 0.5, 0.86, 0.2) * (0.72 + 0.28 * lit), v)
    # chipped paint on the stripes: bare stone shows through near edges and at random
    chip = np.clip((_fbm(P * 14.0 + 3.0, 3) - 0.62) * 8, 0, 1) * stripe
    v = v * (1 - chip) + 0.48 * chip
    # wear: lighter scuffs on convex edges (hero_decals.wear style)
    wear = np.clip((_fbm(P * 22.0 + 1.0, 3) - 0.45) * 5, 0, 1) * edge * convex
    v = v + (0.9 - v) * wear * 0.35
    # hatching: shadow side (steep faces) and the deep creases / pits, tile-space diagonals
    sp = PAINT["hatch_spacing"]
    aa = 0.06
    u1 = (P[..., 0] * 0.7 + P[..., 1] * 0.7) / sp
    u2 = (-P[..., 0] * 0.7 + P[..., 1] * 0.7) / sp
    zone = np.clip(np.maximum(1.0 - lit, (crease - 0.25) * 2.0), 0, 1)
    cluster = np.clip((_fbm(P * 4.0 + 11.0, 2) - 0.42) / 0.12, 0, 1)
    h1 = _lines(u1, PAINT["hatch_width"], aa) * zone * cluster
    deep = np.clip((crease - 0.45) * 3.0, 0, 1)
    h2 = _lines(u2, PAINT["hatch_width"] * 0.9, aa) * deep
    hatch = np.clip(h1 + h2, 0, 1) * PAINT["hatch"]
    ink = PAINT["ink"]
    v = v * (1 - hatch) + (v * 0.35 + ink * 0.5) * hatch
    # ink: block borders (paint id changes) + deep creases + cracks
    q = np.rint(val * 40).astype(np.int32) * 10 + kind
    bd = np.zeros_like(v)
    for dy, dx in ((0, 1), (1, 0)):
        bd = np.maximum(bd, (q != np.roll(np.roll(q, -dy, 0), -dx, 1)).astype(np.float32))
    border = _dilate(bd, PAINT["ink_px"] * ss // 2 + 1) * 0.85
    cink = np.clip((crease - 0.5) * 4.0, 0, 1) * (1 - convex) * 0.75
    cracks = _crack_strokes(ss, rnd, [3, 0, 1, 6], [5, 1, 1, 2], px_per_m)
    cracks = cracks * (kind == STONE)
    inkm = np.clip(np.maximum(np.maximum(border, cink), cracks * 0.9), 0, 1)
    v = v * (1 - inkm) + ink * inkm
    v = np.clip(v, 0.03, 0.97)
    # mask
    tile_u = np.mod(P[..., 0] + HALF, TILE_M) - HALF  # tile-local coordinates
    tile_v = np.mod(P[..., 1] + HALF, TILE_M) - HALF
    to_edge = HALF - np.maximum(np.abs(tile_u), np.abs(tile_v))
    gn = _fbm(P * 2.5 + 21.0, 3)
    grime = np.clip(crease * 1.6, 0, 1) * 0.8
    grime = np.maximum(grime, np.clip(1 - to_edge / 0.3, 0, 1) * np.clip((gn - 0.35) * 3, 0, 1) * 0.7)
    grime = np.maximum(grime, np.clip((gn - 0.62) * 4, 0, 1) * 0.45)
    grime = np.maximum(grime, (kind == PIT) * 0.9)
    edge_hl = np.clip(edge * convex * (0.6 + 0.4 * lit) * 1.2, 0, 1) * (1 - inkm)
    ao_w = np.clip(0.35 + 0.65 * ao_s - 0.15 * wear, 0, 1)
    mask = np.stack([ao_w, edge_hl, np.clip(grime, 0, 1), np.ones_like(v)], -1)
    alb = _down(v, ss)
    mask = _down(mask, ss)
    return alb, mask, nrm


def save(alb, mask, nrm, out):
    from PIL import Image
    os.makedirs(out, exist_ok=True)

    def u8(a):
        return (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    g = u8(alb)
    Image.merge("RGB", [Image.fromarray(g, "L")] * 3).save(os.path.join(out, KEY + "_albedo.png"), optimize=True)
    m = u8(mask)
    Image.merge("RGBA", [Image.fromarray(m[..., i], "L") for i in range(4)]).save(
        os.path.join(out, KEY + "_mask.png"), optimize=True)
    n = u8(np.concatenate([nrm[..., :2], np.ones_like(nrm[..., :1])], -1))
    Image.merge("RGB", [Image.fromarray(n[..., i], "L") for i in range(3)]).save(
        os.path.join(out, KEY + "_normal.png"), optimize=True)
    return {k: os.path.getsize(os.path.join(out, KEY + "_%s.png" % k)) for k in ("albedo", "normal", "mask")}


def preview(alb, mask, path, tint=(0.36, 0.34, 0.47)):
    """Look-dev composite the way the shader combines the maps (flat lit, no seams)."""
    from PIL import Image
    t = np.array(tint, dtype=np.float32)[None, None]
    c = t * (alb[..., None] * 2.0)
    c = c * (0.55 + 0.45 * mask[..., 0:1])
    c = c * (1 - 0.45 * mask[..., 2:3]) + np.array([0.08, 0.07, 0.06])[None, None] * 0.45 * mask[..., 2:3]
    c = c + (1 - c) * mask[..., 1:2] * 0.35
    Image.fromarray((np.clip(c, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8)).save(path)


# ---------------------------------------------------------------- decal atlas
DECAL_OUT = os.path.join(ROOT, "assets", "textures", "world", "decals")
DECAL_KEY = "world_decals"
DECAL_CELL = 256
DECAL_COLS, DECAL_ROWS = 8, 2
# Cell order = WorldDecalsDef.cells (assets/data/world/world_decals.tres); keep in sync.
DECALS = ["arrow", "arrow_double", "chevrons", "glyph_concord", "glyph_syndicate", "tag_a", "tag_b", "tag_c",
          "crack_a", "crack_b", "crack_c", "grime_a", "grime_b", "oil", "puddle", "scorch"]
# design/art-bible.md §4.6 rule 2: decoration only in sign_teal / sign_pink / holo_white, never the team bands.
SIGN_TEAL, SIGN_PINK, HOLO_WHITE = (0.20, 0.85, 0.77), (0.89, 0.33, 0.71), (0.90, 0.97, 1.0)
INK_RGB = (0.06, 0.05, 0.09)


def _noise2(S, scale, seed, octaves=3):
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S
    P = np.stack([x * scale, y * scale, np.full_like(x, seed * 3.1)], -1)
    return _fbm(P, octaves)


def _shape(S, draw_fn):
    from PIL import Image, ImageDraw
    im = Image.new("L", (S, S), 0)
    draw_fn(ImageDraw.Draw(im), S)
    return np.asarray(im, dtype=np.float32) / 255.0


def _paint_mark(S, a, rgb, seed, ink=True, wear=0.35, ink_px=None):
    """Painted floor marking: flat paint with an ink stroke, worn-through chips, grit."""
    out = np.zeros((S, S, 4), np.float32)
    ink_px = ink_px or max(3, S // 64)
    rim = np.clip(_dilate(a, ink_px * 2 + 1) - a, 0, 1) if ink else np.zeros_like(a)
    n = _noise2(S, 9.0, seed)
    chips = np.clip((n - (0.72 - wear * 0.3)) * 7, 0, 1)
    grit = (_noise2(S, 60.0, seed + 5, 2) - 0.5) * 0.12
    shade = 1.0 + grit + (_noise2(S, 3.0, seed + 9, 2) - 0.5) * 0.12
    col = np.array(rgb, np.float32)[None, None] * shade[..., None]
    a_paint = a * (1 - chips * 0.85)
    a_rim = rim * (1 - chips * 0.6) * 0.9
    tot = np.clip(a_paint + a_rim, 0, 1)
    c = (col * a_paint[..., None] + np.array(INK_RGB)[None, None] * a_rim[..., None]) / np.maximum(tot, 1e-4)[..., None]
    out[..., :3] = c
    out[..., 3] = tot
    return out


def _stain(S, seed, rgb, density, scale=4.0, edge=0.08, rim=0.0):
    """Soft blotch: radial falloff x noise, optional darker rim (dried edge)."""
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S - 0.5
    r = np.sqrt(x * x + y * y) * 2
    n = _noise2(S, scale, seed)
    f = np.clip((1.0 - r) * 1.3 + (n - 0.5) * 1.2, 0, 1)
    a = np.clip((f - (1 - density)) / edge, 0, 1) * (0.55 + 0.45 * _noise2(S, 14.0, seed + 2, 2))
    out = np.zeros((S, S, 4), np.float32)
    col = np.array(rgb, np.float32)[None, None] * (0.85 + 0.3 * _noise2(S, 20.0, seed + 4, 2))[..., None]
    if rim > 0:
        ring = np.clip(_dilate(a, S // 64 * 2 + 1) - _blur(a, S / 100), 0, 1) * rim
        a = np.clip(a + ring, 0, 1)
    out[..., :3] = col
    out[..., 3] = a
    return out


def _crack(S, seed, branches):
    from PIL import Image, ImageDraw
    rnd = random.Random(seed)
    dark = Image.new("L", (S, S), 0)
    lite = Image.new("L", (S, S), 0)
    dd, dl = ImageDraw.Draw(dark), ImageDraw.Draw(lite)

    def walk(x, y, a, n, w):
        pts = [(x, y)]
        for _ in range(n):
            a += rnd.uniform(-0.6, 0.6)
            L = rnd.uniform(0.04, 0.08) * S
            x, y = x + math.cos(a) * L, y + math.sin(a) * L
            pts.append((x, y))
        dl.line([(px + w * 0.8, py + w * 0.8) for px, py in pts], fill=255, width=max(1, int(w * 0.6)))
        dd.line(pts, fill=255, width=max(1, int(w)))
        return pts
    main_pts = walk(S * 0.5, S * 0.5, rnd.uniform(0, 6.28), 6, S / 80)
    walk(S * 0.5, S * 0.5, rnd.uniform(0, 6.28), 5, S / 90)
    for _ in range(branches):
        b = rnd.choice(main_pts)
        walk(b[0], b[1], rnd.uniform(0, 6.28), rnd.randint(2, 4), S / 150)
    a_d = np.asarray(dark, np.float32) / 255.0
    a_l = np.clip(np.asarray(lite, np.float32) / 255.0 - a_d, 0, 1) * 0.5
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S - 0.5
    keep = np.clip((0.48 - np.sqrt(x * x + y * y)) / 0.05, 0, 1)
    out = np.zeros((S, S, 4), np.float32)
    c = np.array(INK_RGB)[None, None] * a_d[..., None] + np.array([0.75, 0.73, 0.78])[None, None] * a_l[..., None]
    out[..., :3] = c / np.maximum(a_d + a_l, 1e-4)[..., None]
    out[..., 3] = np.clip((a_d + a_l) * keep, 0, 1)
    return out


def _tag(S, seed, rgb):
    """Crew tag: a spray-painted scrawl (wavy strokes, underline swoosh, overspray, drips)."""
    from PIL import Image, ImageDraw
    rnd = random.Random(seed)
    im = Image.new("L", (S, S), 0)
    dr = ImageDraw.Draw(im)
    x = S * 0.16
    w = S / 22
    while x < S * 0.8:
        pts = []
        for _i in range(5):
            pts.append((x + rnd.uniform(-0.03, 0.06) * S, S * (0.35 + 0.3 * rnd.random())))
            x += S * 0.025
        dr.line(pts, fill=255, width=int(w), joint="curve")
        x += S * 0.03
    dr.line([(S * 0.14, S * 0.7), (S * 0.86, S * 0.62)], fill=255, width=int(w * 0.6))
    for _ in range(3):
        dx = rnd.uniform(0.2, 0.8) * S
        dr.line([(dx, S * 0.62), (dx, S * (0.7 + 0.12 * rnd.random()))], fill=255, width=max(2, int(w * 0.3)))
    a = np.asarray(im, np.float32) / 255.0
    spray = _blur(a, S / 60) * 0.35
    core = _paint_mark(S, a, rgb, seed, ink=True, wear=0.45, ink_px=max(2, S // 128))
    out = core.copy()
    halo = np.clip(spray - core[..., 3], 0, 1)
    tot = np.clip(core[..., 3] + halo, 0, 1)
    out[..., :3] = (core[..., :3] * core[..., 3:4] + np.array(rgb)[None, None] * halo[..., None]) / np.maximum(
        tot, 1e-4)[..., None]
    out[..., 3] = tot
    return out


def _arrow(dr, S):
    dr.polygon([(S * .5, S * .08), (S * .86, S * .46), (S * .64, S * .46), (S * .64, S * .9), (S * .36, S * .9),
                (S * .36, S * .46), (S * .14, S * .46)], fill=255)


def _chev(dr, S, rows, h):
    for y0 in rows:
        dr.polygon([(S * .5, S * y0), (S * .88, S * (y0 + h)), (S * .88, S * (y0 + h + .13)), (S * .5, S * (y0 + .13)),
                    (S * .12, S * (y0 + h + .13)), (S * .12, S * (y0 + h))], fill=255)


def _glyph_concord(dr, S):
    """Clean lattice: hexagon ring, inner diamond, four ticks (flush, precise, design §3.2)."""
    c = S * 0.5
    hexo = [(c + math.cos(math.pi / 6 + i * math.pi / 3) * S * .44, c + math.sin(math.pi / 6 + i * math.pi / 3) * S * .44)
            for i in range(6)]
    dr.polygon(hexo, fill=255)
    dr.polygon([(c + (x - c) * 0.8, c + (y - c) * 0.8) for x, y in hexo], fill=0)
    dr.polygon([(c, c - S * .26), (c + S * .17, c), (c, c + S * .26), (c - S * .17, c)], fill=255)
    dr.polygon([(c, c - S * .14), (c + S * .08, c), (c, c + S * .14), (c - S * .08, c)], fill=0)
    for i in range(4):
        a = i * math.pi / 2
        dr.line([(c + math.cos(a) * S * .2, c + math.sin(a) * S * .2), (c + math.cos(a) * S * .3, c + math.sin(a) * S * .3)],
                fill=255, width=int(S * .035))


def _glyph_syndicate(dr, S):
    """Crew mark: serrated ring + three claw slashes (riveted, scuffed, design §3.2)."""
    c = S * 0.5
    pts = []
    for i in range(24):
        r = S * (0.45 if i % 2 == 0 else 0.39)
        a = i * 2 * math.pi / 24
        pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
    dr.polygon(pts, fill=255)
    dr.ellipse([c - S * .32, c - S * .32, c + S * .32, c + S * .32], fill=0)
    for k in (-1, 0, 1):
        x = c + k * S * .11
        dr.polygon([(x - S * .03, c - S * .22), (x + S * .04, c - S * .22), (x, c + S * .24), (x - S * .06, c + S * .2)],
                   fill=255)


def _puddle(S):
    """Toon water: dark pool, light rim stroke, two painted glints."""
    o = _stain(S, 44, (0.1, 0.1, 0.18), 0.6, 2.0, 0.03)
    a = (o[..., 3] > 0.3).astype(np.float32)
    rim = np.clip(a - _blur(a, S / 90), 0, 1) * 2

    def gl(dr, S):
        dr.line([(S * .38, S * .42), (S * .55, S * .38)], fill=255, width=int(S * .025))
        dr.line([(S * .5, S * .52), (S * .6, S * .5)], fill=255, width=int(S * .018))
    hl = np.clip(np.maximum(rim, _shape(S, gl) * a), 0, 1)
    o[..., :3] = o[..., :3] * (1 - hl[..., None]) + np.array([0.7, 0.75, 0.9])[None, None] * hl[..., None]
    o[..., 3] = np.clip(np.maximum(o[..., 3] * 0.85, hl * 0.9), 0, 1)
    return o


def _scorch(S):
    """Soot burst: dark core, ragged soot rays (no ember hue: team band)."""
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S - 0.5
    r = np.sqrt(x * x + y * y) * 2
    ang = np.arctan2(y, x)
    rays = 0.5 + 0.5 * np.sin(ang * 13 + 3 * _noise2(S, 3.0, 51))
    f = np.clip(1.0 - r / (0.55 + 0.4 * rays * _noise2(S, 4.0, 52)), 0, 1)
    o = np.zeros((S, S, 4), np.float32)
    o[..., :3] = np.array([0.05, 0.045, 0.05])[None, None] * (0.8 + 0.5 * _noise2(S, 18.0, 53, 2))[..., None]
    o[..., 3] = np.clip(f * 1.6, 0, 1) * (0.75 + 0.25 * _noise2(S, 25.0, 54, 2))
    return o


def paint_decal(name, S):
    white = (0.95, 0.95, 0.95)
    table = {
        "arrow": lambda: _paint_mark(S, _shape(S, _arrow), white, 11),
        "arrow_double": lambda: _paint_mark(S, _shape(S, lambda dr, S: _chev(dr, S, (0.12, 0.5), 0.26)), white, 12),
        "chevrons": lambda: _paint_mark(S, _shape(S, lambda dr, S: _chev(dr, S, (0.1, 0.38, 0.66), 0.14)), white, 13,
                                        wear=0.5),
        "glyph_concord": lambda: _paint_mark(S, _shape(S, _glyph_concord), white, 14, wear=0.2),
        "glyph_syndicate": lambda: _paint_mark(S, _shape(S, _glyph_syndicate), white, 15, wear=0.55),
        "tag_a": lambda: _tag(S, 21, SIGN_PINK),
        "tag_b": lambda: _tag(S, 22, SIGN_TEAL),
        "tag_c": lambda: _tag(S, 23, HOLO_WHITE),
        "crack_a": lambda: _crack(S, 31, 3),
        "crack_b": lambda: _crack(S, 32, 5),
        "crack_c": lambda: _crack(S, 33, 2),
        "grime_a": lambda: _stain(S, 41, (0.09, 0.08, 0.1), 0.6, 3.0, 0.3),
        "grime_b": lambda: _stain(S, 42, (0.12, 0.1, 0.1), 0.5, 5.0, 0.25),
        "oil": lambda: _stain(S, 43, (0.03, 0.03, 0.05), 0.55, 2.5, 0.06, rim=0.5),
        "puddle": lambda: _puddle(S),
        "scorch": lambda: _scorch(S),
    }
    return table[name]()


def build_decals(out):
    from PIL import Image, ImageFilter
    ss = 2
    S = DECAL_CELL * ss
    sheet = np.zeros((DECAL_ROWS * S, DECAL_COLS * S, 4), np.float32)
    for i, name in enumerate(DECALS):
        c, r = i % DECAL_COLS, i // DECAL_COLS
        cell = paint_decal(name, S)
        g = 4 * ss  # transparent gutter: no bleed between cells
        cell[:g, :, 3] = 0
        cell[-g:, :, 3] = 0
        cell[:, :g, 3] = 0
        cell[:, -g:, 3] = 0
        sheet[r * S:(r + 1) * S, c * S:(c + 1) * S] = cell
    pm = sheet.copy()  # premultiplied downsample (no dark fringes), then un-premultiply
    pm[..., :3] *= pm[..., 3:4]
    pm = _down(pm, ss)
    a = pm[..., 3]
    rgb = pm[..., :3] / np.maximum(a[..., None], 1e-4)
    inside = a[..., None] > 0.01
    filled = np.where(inside, rgb, 0.0)
    for _ in range(8):  # bleed colour into transparent texels so filtering and mips stay clean
        grown = np.stack([np.asarray(Image.fromarray((np.clip(filled[..., k], 0, 1) * 255).astype(np.uint8)).filter(
            ImageFilter.MaxFilter(3)), np.float32) / 255 for k in range(3)], -1)
        filled = np.where(inside, rgb, np.maximum(filled, grown))
    os.makedirs(out, exist_ok=True)
    u8 = (np.clip(np.concatenate([filled, a[..., None]], -1), 0, 1) * 255 + 0.5).astype(np.uint8)
    path = os.path.join(out, DECAL_KEY + "_albedo.png")
    Image.fromarray(u8, "RGBA").save(path, optimize=True)
    print("built %s: %dx%d, %d cells of %d px (%s), %.2f MB" % (path, u8.shape[1], u8.shape[0], len(DECALS), DECAL_CELL,
                                                                 ", ".join(DECALS), os.path.getsize(path) / 1e6))
    return path


def main(argv):
    if "--decals" in argv:
        build_decals(argv[argv.index("--out") + 1] if "--out" in argv else DECAL_OUT)
        return
    out = argv[argv.index("--out") + 1] if "--out" in argv else OUT
    ss = int(argv[argv.index("--ss") + 1]) if "--ss" in argv else 2
    t = time.time()
    hi, lo = build_geometry()
    passes = bake_all(hi, lo, ss)
    alb, mask, nrm = paint(*passes, ss)
    sizes = save(alb, mask, nrm, out)
    if "--preview" in argv:
        preview(alb, mask, argv[argv.index("--preview") + 1])
    print("built %s: %dx%d, %d tiles (%s), %s, %.0f s" % (
        os.path.join(out, KEY), COLS * SLOT_PX, ROWS * SLOT_PX, len(TILES), ", ".join(NAMES),
        {k: round(v / 1e6, 2) for k, v in sizes.items()}, time.time() - t))


if __name__ == "__main__":
    main(sys.argv)
