"""W16 Borderlands texture pass for the gen pipeline (design/art/hero-art-bible.md §9).

Same files and shader contract as the W14 set (hero_hd.py), so RiggedHeroModel and
spatial_char_toon_rigged need no change:
  <key>_albedo.png  RGB: flat material blocks with the light PAINTED IN
  <key>_normal.png  RGB OpenGL tangent: small surface detail only
  <key>_mask.png    RGBA (half size): R AO, G spec/glint, B emissive, A team

What changes against W14:
  * UVs: Smart UV Project + pack_islands (rotation, concave shapes) -> >= 75 % used
    (W14 used ~46 %), printed per build;
  * painted light: a top-down key light (`key_dir`) split into a lit and a shadow
    zone with a short soft terminator, warm lit / cool shadow tint, top-to-bottom
    falloff, painted crease AO, diagonal hatching in the shadow zone (cross-hatch in
    the deep creases), bright edge strokes on convex edges, ink lines on every colour
    block border and in deep creases, a little grit;
  * normals: one bake of the low mesh's own shading (Bevel-rounded hard edges,
    panel lines, cloth seams) at low strength; no high-poly copy, no cloth
    displacement folds (those broke the 2-band cel ramp into blotches in v0.10).
Controls: DEFAULT_PAINT, overridden per hero by its "paint" dict.
"""
import math
import os

import bmesh
import bpy
import numpy as np

import hero_hd
from hero_hd import _attr, _bake, _classify, _combine, _emit_tree, _fbm, _math, _node_mat

DEFAULT_PAINT = {
    "key_dir": (0.3, 0.55, 1.0),   # painted key light (object space, X right, Y front, Z up)
    "terminator": 0.12,            # N.L where the painted shadow starts
    "soft": 0.06,                  # half width of the soft terminator
    "lit": 1.04, "shadow": 0.72,   # value multipliers of the two zones
    "warm": (1.04, 1.0, 0.93), "cool": (0.88, 0.9, 1.06),
    "top": 0.12,                   # top-to-bottom value falloff
    "ao": 0.5, "ao_dist": 0.06,    # painted crease AO
    "hatch": 0.55,                 # hatching darkness (0 = off)
    "hatch_spacing": 0.03,         # metres between hatch lines (scaled by height)
    "hatch_width": 0.36,           # line width as a fraction of the spacing
    "cross": 0.35,                 # crease depth where the cross-hatch starts
    "edge": 0.5,                   # convex edge highlight strength
    "ink": (0.06, 0.05, 0.09),     # ink colour (lines, hatching)
    "ink_border": 1.0,             # ink on colour-block borders (0 = off)
    "ink_px": 3,                   # border ink width in supersampled pixels
    "crease_ink": 0.7,             # ink in the deepest creases
    "grit": 0.05,                  # painterly value noise
    "normal_bump": 0.3,            # detail normal strength
    "uv_margin": 0.004,            # pack margin (fraction of the atlas)
}


def paint_cfg(h):
    c = dict(DEFAULT_PAINT)
    c.update(h.d.get("paint", {}))
    return c


def unwrap_pack(ob, margin):
    from build_hero import _activate
    _activate(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.0, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, rotate_method="ANY", scale=True, margin_method="FRACTION", margin=margin,
                            shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")


def uv_triangles(ob):
    me = ob.data
    uv = me.uv_layers.active.data
    tris = []
    for p in me.polygons:
        ls = list(p.loop_indices)
        for i in range(1, len(ls) - 1):
            tris.append((uv[ls[0]].uv[:], uv[ls[i]].uv[:], uv[ls[i + 1]].uv[:]))
    return np.array(tris)


def uv_usage(T):
    """Fraction of the atlas covered by UV triangles (islands do not overlap)."""
    a = T[:, 1] - T[:, 0]
    b = T[:, 2] - T[:, 0]
    return float(np.abs(a[:, 0] * b[:, 1] - a[:, 1] * b[:, 0]).sum() * 0.5)


def coverage(T, S):
    """Rasterised island mask (S x S, row 0 = top, like the bake arrays)."""
    from PIL import Image, ImageDraw
    im = Image.new("L", (S, S), 0)
    dr = ImageDraw.Draw(im)
    for t in T:
        dr.polygon([(u * S, (1 - v) * S) for u, v in t], fill=255)
    return np.asarray(im, dtype=np.float32) / 255.0


def _normal_mat(strength):
    """Shading normal of the low mesh: Bevel-rounded hard parts + panel lines / seams bump."""
    def build(nt, out):
        tc = nt.nodes.new("ShaderNodeTexCoord")
        vor = nt.nodes.new("ShaderNodeTexVoronoi")
        vor.feature = "DISTANCE_TO_EDGE"
        vor.inputs["Scale"].default_value = 7.0
        nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
        groove = nt.nodes.new("ShaderNodeMapRange")
        groove.inputs[1].default_value, groove.inputs[2].default_value = 0.0, 0.03
        nt.links.new(vor.outputs["Distance"], groove.inputs[0])
        seam = nt.nodes.new("ShaderNodeTexVoronoi")
        seam.feature = "DISTANCE_TO_EDGE"
        seam.inputs["Scale"].default_value = 2.5
        nt.links.new(tc.outputs["Object"], seam.inputs["Vector"])
        sm = nt.nodes.new("ShaderNodeMapRange")
        sm.inputs[1].default_value, sm.inputs[2].default_value = 0.0, 0.015
        nt.links.new(seam.outputs["Distance"], sm.inputs[0])
        height = _math(nt, "ADD", _math(nt, "MULTIPLY", groove.outputs[0], _attr(nt, "hd_hard")),
                       _math(nt, "MULTIPLY", _math(nt, "MULTIPLY", sm.outputs[0], 0.6), _attr(nt, "hd_cloth")))
        bev = nt.nodes.new("ShaderNodeBevel")
        bev.samples = 8
        bev.inputs["Radius"].default_value = 0.003
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "VECTOR"
        nt.links.new(_attr(nt, "hd_hard"), mix.inputs[0])
        nt.links.new(geo.outputs["Normal"], mix.inputs[4])
        nt.links.new(bev.outputs[0], mix.inputs[5])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = strength
        bump.inputs["Distance"].default_value = 0.001
        nt.links.new(height, bump.inputs["Height"])
        nt.links.new(mix.outputs[1], bump.inputs["Normal"])
        bsdf = nt.nodes.new("ShaderNodeBsdfDiffuse")
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return build


def bake_textures(h, ob, out_dir, size=1024):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    cfg = paint_cfg(h)
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(me)
    bm.free()
    me.validate(clean_customdata=False)
    _classify(h, ob)
    unwrap_pack(ob, cfg["uv_margin"])
    T = uv_triangles(ob)
    use = uv_usage(T)
    print("paint: UV atlas used %.1f %%" % (use * 100))
    S = size * 2
    col = _bake(ob, _node_mat("c", _emit_tree(lambda nt: _attr(nt, "Color", "Color"))), S)
    mat = _bake(ob, _node_mat("m", _emit_tree(lambda nt: _combine(nt, _attr(nt, "hd_metal"), _attr(nt, "hd_cloth"),
                                                                     _attr(nt, "hd_skin")))), S)
    et = _bake(ob, _node_mat("e", _emit_tree(lambda nt: _combine(nt, _attr(nt, "hd_emit"), _attr(nt, "hd_team"),
                                                                    _attr(nt, "hd_hard")))), S)

    def ao_edge(nt):
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.samples = 16
        ao.inputs["Distance"].default_value = cfg["ao_dist"]
        bev = nt.nodes.new("ShaderNodeBevel")
        bev.samples = 8
        bev.inputs["Radius"].default_value = 0.006
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        d = _math(nt, "DOT_PRODUCT", bev.outputs[0], geo.outputs["Normal"], vec=True)
        return _combine(nt, ao.outputs["AO"], _math(nt, "SUBTRACT", 1.0, d), geo.outputs["Pointiness"])
    aoe = _bake(ob, _node_mat("a", _emit_tree(ao_edge)), S, samples=12)
    P = _bake(ob, _node_mat("p", _emit_tree(lambda nt: nt.nodes.new("ShaderNodeTexCoord").outputs["Object"])), S)
    N = _bake(ob, _node_mat("n", _emit_tree(lambda nt: nt.nodes.new("ShaderNodeNewGeometry").outputs["Normal"])), S)
    nrm = _bake(ob, _node_mat("nrm", _normal_mat(cfg["normal_bump"])), size, samples=4, kind="NORMAL")
    cov = coverage(T, S)
    dbg = os.environ.get("HERO_DEBUG")
    if dbg:
        np.savez_compressed(os.path.join(dbg, h.key + "_w16_passes.npz"), col=col, mat=mat, et=et, aoe=aoe, P=P, N=N,
                            nrm=nrm, cov=cov)
    sizes = composite(h, cfg, out_dir, size, col, mat, et, aoe, P, N, nrm, cov)
    sizes["uv_used"] = use
    me = ob.data
    for n in ("hd_metal", "hd_cloth", "hd_skin", "hd_emit", "hd_team", "hd_hard", "hd_kind"):
        if n in me.attributes:
            me.attributes.remove(me.attributes[n])
    for vg in ("hd_clothvg", "hd_hardvg"):
        if vg in ob.vertex_groups:
            ob.vertex_groups.remove(ob.vertex_groups[vg])
    ob.data.materials.clear()
    return sizes


def _blur(a, r):
    from PIL import Image, ImageFilter
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r)), dtype=np.float32) / 255.0


def _dilate(a, px):
    from PIL import Image, ImageFilter
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.MaxFilter(px | 1)), dtype=np.float32) / 255.0


def _lines(u, width, aa):
    """Anti-aliased line pattern: 1 on the lines, 0 between (u in line periods)."""
    d = np.abs(u - np.floor(u) - 0.5)  # 0.5 on the line centre, 0 halfway between
    return np.clip((d - (0.5 - width / 2)) / max(aa, 1e-4) + 0.5, 0, 1)


def composite(h, cfg, out_dir, size, col, mat, et, aoe, P, N, nrm, cov):
    """Paints the albedo + mask from the data passes (numpy) and writes the PNGs."""
    from PIL import Image
    H = h.d["height"]
    k = H / 1.85
    S = col.shape[0]
    base = col[..., :3]
    metal, cloth, skin = mat[..., 0], mat[..., 1], mat[..., 2]
    emit, team, hard = et[..., 0], et[..., 1], et[..., 2]
    n3 = N[..., :3]
    n3 = n3 / np.maximum(np.linalg.norm(n3, axis=-1, keepdims=True), 1e-6)
    p3 = P[..., :3]
    L = np.array(cfg["key_dir"], dtype=np.float32)
    L /= np.linalg.norm(L)
    lam = n3 @ L
    t0, sf = cfg["terminator"], cfg["soft"]
    lit = np.clip((lam - (t0 - sf)) / (2 * sf), 0, 1)
    lit = lit * lit * (3 - 2 * lit)
    ao = np.sqrt(np.clip(_blur(aoe[..., 0], 2.0), 0, 1))
    crease = 1.0 - ao
    edge = np.clip((aoe[..., 1] - 0.06) / 0.2, 0, 1)
    convex = np.clip((aoe[..., 2] - 0.5) * 6 + 0.5, 0, 1)
    z = np.clip(p3[..., 2] / H, 0, 1)
    val = cfg["shadow"] + (cfg["lit"] - cfg["shadow"]) * lit
    val = val * (1.0 - cfg["top"] + cfg["top"] * z) * (1.0 - cfg["ao"] * crease)
    val = val * (1.0 + cfg["grit"] * (_fbm(p3 * 9.0, 3) - 0.5) * 2)
    tint = np.array(cfg["cool"])[None, None] * (1 - lit[..., None]) + np.array(cfg["warm"])[None, None] * lit[..., None]
    alb = base * val[..., None] * tint
    # Hatching: diagonal object-space line families, only in the painted shadow zone.
    sp = cfg["hatch_spacing"] * k
    aa = 0.05 * 2048.0 / S  # ~1 texel of the 2048 bake in line periods at the default spacing
    u1 = (p3[..., 0] * 0.55 + p3[..., 1] * 0.35 + p3[..., 2] * 0.76) / sp
    u2 = (-p3[..., 0] * 0.6 + p3[..., 1] * 0.5 + p3[..., 2] * 0.62) / sp
    shade = (1.0 - lit) * (1.0 - skin)
    h1 = _lines(u1, cfg["hatch_width"], aa) * np.clip(shade * 1.4 - 0.1, 0, 1)
    deep = np.clip((crease + (1 - lit) * 0.3 - cfg["cross"]) * 3.0, 0, 1)
    h2 = _lines(u2, cfg["hatch_width"] * 0.9, aa) * deep * shade
    hatch = np.clip(h1 + h2, 0, 1) * cfg["hatch"] * (1 - emit)
    ink = np.array(cfg["ink"], dtype=np.float32)[None, None]
    alb = alb * (1 - hatch[..., None]) + (alb * 0.35 + ink * 0.5) * hatch[..., None]
    # Edge strokes: bright on convex edges, strongest on hard parts.
    hl = edge * convex * (cfg["edge"] * (0.5 + 0.5 * hard) + 0.1 * cloth) * (0.6 + 0.4 * lit)
    alb = alb + (1.0 - alb) * hl[..., None]
    # Ink: colour-block borders (inside the islands only) + the deepest creases.
    q = np.round(base * 24).astype(np.int32)
    idm = q[..., 0] * 10000 + q[..., 1] * 100 + q[..., 2]
    inside = cov > 0.5
    bd = np.zeros((S, S), dtype=np.float32)
    for dy, dx in ((0, 1), (1, 0)):
        a, b = idm, np.roll(np.roll(idm, -dy, 0), -dx, 1)
        ia, ib = inside, np.roll(np.roll(inside, -dy, 0), -dx, 1)
        bd = np.maximum(bd, ((a != b) & ia & ib).astype(np.float32))
    border = _dilate(bd, int(cfg["ink_px"])) * cfg["ink_border"] * (1 - emit)
    cink = np.clip((crease - 0.55) * 4.0, 0, 1) * (1 - convex) * cfg["crease_ink"] * (1 - emit)
    inkm = np.clip(np.maximum(border, cink), 0, 1)
    alb = alb * (1 - inkm[..., None]) + ink * inkm[..., None]
    alb = np.where(emit[..., None] > 0.5, base, alb)
    alb = np.clip(alb, 0, 1)
    spec = np.clip(metal * (0.55 + 0.45 * edge), 0, 1)
    mask = np.stack([np.clip(0.4 + 0.6 * ao, 0, 1), spec, emit, team], axis=-1)

    def save(a, path, sz, mode):
        u8 = (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
        bands = [Image.fromarray(u8[..., i], "L") for i in range(u8.shape[-1])]
        if bands[0].size[0] != sz:
            bands = [b.resize((sz, sz), Image.LANCZOS) for b in bands]
        Image.merge(mode, bands).save(path, optimize=True)
        return os.path.getsize(path)
    key = h.key
    return {
        "albedo": save(alb, os.path.join(out_dir, key + "_albedo.png"), size, "RGB"),
        "mask": save(mask, os.path.join(out_dir, key + "_mask.png"), size // 2, "RGBA"),
        "normal": save(np.concatenate([nrm[..., :2], np.ones_like(nrm[..., :1])], -1),
                       os.path.join(out_dir, key + "_normal.png"), size, "RGB"),
    }


def recompose(npz, key):
    """Look-dev loop: re-runs only the composite from HERO_DEBUG passes (see README)."""
    import hero_defs

    class _H:
        pass
    h = _H()
    h.key = key
    h.d = hero_defs.HEROES[key]
    d = np.load(npz)
    out = os.path.dirname(npz)
    return composite(h, paint_cfg(h), out, d["nrm"].shape[0], d["col"], d["mat"], d["et"], d["aoe"], d["P"], d["N"],
                     d["nrm"], d["cov"])
