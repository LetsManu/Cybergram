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
    "ao": 0.5, "ao_dist": 0.025,   # painted crease AO (short reach: creases only, not garment gaps)
    "hatch": 0.5,                  # hatching darkness (0 = off)
    "hatch_threshold": -0.05,      # N.L below which hatching starts (lit side never: < terminator - soft)
    "hatch_fade": 0.3,             # N.L range over which it fades in toward the dark side
    "hatch_density": 0.5,          # share of the shadow zone covered by stroke clusters (0..1)
    "hatch_spacing": 0.024,        # metres between hatch lines (scaled by height)
    "hatch_width": 0.3,            # line width as a fraction of the spacing
    "cross": 0.35,                 # crease depth where the cross-hatch starts
    "edge": 0.5,                   # convex edge highlight strength
    "ink": (0.06, 0.05, 0.09),     # ink colour (lines, hatching)
    "ink_border": 1.0,             # ink on colour-block borders (0 = off)
    "ink_px": 3,                   # border ink width in supersampled pixels
    "crease_ink": 0.7,             # ink in the deepest creases
    "grit": 0.05,                  # painterly value noise
    "normal_bump": 0.3,            # detail normal strength
    "uv_margin": 0.0017,           # pack margin (SCALED; measured >= 1-2 texels between islands at 1024)
    "uv_head": 1.0,                # linear UV scale of the head islands (mask/helmet texel density, W16-B)
    "detail": None,                # optional fn(ctx): painted markings / wear / sheen (see composite)
}


def paint_cfg(h):
    c = dict(DEFAULT_PAINT)
    c.update(h.d.get("paint", {}))
    return c


def _part_seams(bm, faces, sharp_deg=50.0):
    """Seams that turn every part island into a disk: sharp edges (> sharp_deg),
    kind borders, then one shortest-path cut on each island that is still a ring,
    a tube or a closed shell (Euler characteristic != 1)."""
    from collections import deque
    fs = set(faces)
    lim = math.radians(sharp_deg)
    for f in faces:
        for e in f.edges:
            lf = e.link_faces
            if len(lf) != 2 or not (lf[0] in fs and lf[1] in fs) or e.calc_face_angle(0.0) > lim:
                e.seam = True
    seen = set()
    for f0 in faces:
        if f0 in seen:
            continue
        isl, q = [], deque([f0])
        seen.add(f0)
        while q:
            f = q.popleft()
            isl.append(f)
            for e in f.edges:
                if e.seam:
                    continue
                for g in e.link_faces:
                    if g in fs and g not in seen:
                        seen.add(g)
                        q.append(g)
        iset = set(isl)
        V = {v for f in isl for v in f.verts}
        E = {e for f in isl for e in f.edges}
        inner = {e for e in E if not e.seam and all(g in iset for g in e.link_faces)}
        # Euler characteristic of the island cut along its seams (boundary edges count once).
        chi = len(V) - len(E) + len(isl)
        if chi == 1 or len(isl) < 2:
            continue
        bverts = {v for e in E if e not in inner for v in e.verts}
        loops = _boundary_groups(bverts, E - inner)
        if len(loops) >= 2:
            src, dst = loops[0], set().union(*loops[1:])
        else:
            start = next(iter(V))
            far = _bfs_far(start, inner)
            src, dst = {far}, {_bfs_far(far, inner)}
        path = _bfs_path(src, dst, inner)
        for e in path:
            e.seam = True


def _adj(v, edges):
    for e in v.link_edges:
        if e in edges:
            yield e, e.other_vert(v)


def _boundary_groups(bverts, bedges):
    groups, seen = [], set()
    for v0 in bverts:
        if v0 in seen:
            continue
        g, st = set(), [v0]
        seen.add(v0)
        while st:
            v = st.pop()
            g.add(v)
            for _e, o in _adj(v, bedges):
                if o not in seen:
                    seen.add(o)
                    st.append(o)
        groups.append(g)
    return groups


def _bfs_far(start, edges):
    from collections import deque
    dist, q, last = {start: 0}, deque([start]), start
    while q:
        v = q.popleft()
        last = v
        for _e, o in _adj(v, edges):
            if o not in dist:
                dist[o] = dist[v] + 1
                q.append(o)
    return last


def _bfs_path(src, dst, edges):
    from collections import deque
    prev = {v: None for v in src}
    q = deque(src)
    while q:
        v = q.popleft()
        if v in dst and v not in src:
            out = []
            while prev[v] is not None:
                e, v = prev[v]
                out.append(e)
            return out
        for e, o in _adj(v, edges):
            if o not in prev:
                prev[o] = (e, v)
                q.append(o)
    return []


def _uv_islands(bm, faces, uvl):
    """Face islands by shared (vertex, uv) loops."""
    parent = {f: f for f in faces}

    def find(a):
        while parent[a] is not a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    key = {}
    for f in faces:
        for lp in f.loops:
            k = (lp.vert.index, round(lp[uvl].uv[0], 5), round(lp[uvl].uv[1], 5))
            if k in key:
                a, b = find(key[k]), find(f)
                if a is not b:
                    parent[a] = b
            else:
                key[k] = f
    out = {}
    for f in faces:
        out.setdefault(find(f), []).append(f)
    return list(out.values())


def _fill(isl, uvl):
    """UV area / area of the island's PCA-aligned bounding box."""
    pts = np.array([lp[uvl].uv[:] for f in isl for lp in f.loops])
    area = 0.0
    for f in isl:
        uv = [lp[uvl].uv for lp in f.loops]
        for i in range(1, len(uv) - 1):
            a, b = uv[i] - uv[0], uv[i + 1] - uv[0]
            area += abs(a.x * b.y - a.y * b.x) * 0.5
    c = pts - pts.mean(0)
    if len(c) < 3:
        return 1.0
    _w, v = np.linalg.eigh(c.T @ c)
    q = c @ v
    box = np.ptp(q[:, 0]) * np.ptp(q[:, 1])
    return area / box if box > 1e-12 else 1.0


def _split_low_fill(bm, faces, uvl, thresh=0.65, min_faces=8):
    """Cuts islands that fill < `thresh` of their box (arcs, C shapes, bells) in two along
    the plane through their centroid normal to their main 3D axis. Returns the cut count."""
    n = 0
    for isl in _uv_islands(bm, faces, uvl):
        if len(isl) < min_faces or _fill(isl, uvl) >= thresh:
            continue
        C = np.array([tuple(f.calc_center_median()) for f in isl])
        W = np.array([f.calc_area() for f in isl])
        m = (C * W[:, None]).sum(0) / max(W.sum(), 1e-12)
        d = C - m
        _w, v = np.linalg.eigh((d * W[:, None]).T @ d)
        ax = v[:, -1]
        side = {f: float(np.dot(np.array(tuple(f.calc_center_median())) - m, ax)) > 0 for f in isl}
        for f in isl:
            for e in f.edges:
                lf = [g for g in e.link_faces if g in side]
                if len(lf) == 2 and side[lf[0]] != side[lf[1]]:
                    e.seam = True
        n += 1
    return n


def _bm_usage(bm, uvl):
    a = 0.0
    for f in bm.faces:
        uv = [lp[uvl].uv for lp in f.loops]
        for i in range(1, len(uv) - 1):
            p, q = uv[i] - uv[0], uv[i + 1] - uv[0]
            a += abs(p.x * q.y - p.y * q.x) * 0.5
    return a


def _boost_head(ob, bm, uvl, scale):
    """Scales the UV islands that sit on the Head bone by `scale` (linear) before the
    pack, so the mask or helmet gets more texels than the body. Returns the island count."""
    if scale == 1.0 or "Head" not in ob.vertex_groups:
        return 0
    gi = ob.vertex_groups["Head"].index
    dl = bm.verts.layers.deform.active
    if dl is None:
        return 0
    n = 0
    for isl in _uv_islands(bm, list(bm.faces), uvl):
        vs = {v for f in isl for v in f.verts}
        w = sum(v[dl].get(gi, 0.0) for v in vs) / max(len(vs), 1)
        if w < 0.5:
            continue
        lps = [lp for f in isl for lp in f.loops]
        cu = sum(lp[uvl].uv.x for lp in lps) / len(lps)
        cv = sum(lp[uvl].uv.y for lp in lps) / len(lps)
        for lp in lps:
            lp[uvl].uv = ((lp[uvl].uv.x - cu) * scale + cu, (lp[uvl].uv.y - cv) * scale + cv)
        n += 1
    return n


def unwrap_pack(ob, margin, tries=10, target=0.75, max_tries=30, head=1.0):
    """Body + shells (hd_kind 0/1): angle-based unwrap along the body_gen cage seams.
    Parts, garments, weapon: generated seams (_part_seams) + angle-based unwrap, so
    every island is a flat disk (no annuli, few shards). Then one pack of everything."""
    from build_hero import _activate
    _activate(ob)
    me = ob.data
    bpy.ops.object.mode_set(mode="EDIT")

    def select(pred):
        bm = bmesh.from_edit_mesh(me)
        kl = bm.faces.layers.int.get("hd_kind")
        for f in bm.faces:
            f.select_set(pred(f[kl] if kl is not None else 0))
        bmesh.update_edit_mesh(me)
        return bm, kl
    bm, kl = select(lambda k: True)
    _part_seams(bm, [f for f in bm.faces if kl is not None and f[kl] not in (0, 1)])
    bmesh.update_edit_mesh(me)
    select(lambda k: True)
    bpy.ops.uv.unwrap(method="ANGLE_BASED", margin=0.0, correct_aspect=True)
    for _ in range(3):  # cut low-fill islands (arcs, bells) and unwrap again
        bm = bmesh.from_edit_mesh(me)
        uvl = bm.loops.layers.uv.active
        cuts = _split_low_fill(bm, list(bm.faces), uvl)
        bmesh.update_edit_mesh(me)
        if not cuts:
            break
        select(lambda k: True)
        bpy.ops.uv.unwrap(method="ANGLE_BASED", margin=0.0, correct_aspect=True)
    if head != 1.0:
        bm = bmesh.from_edit_mesh(me)
        print("paint: head UV x%.2f on %d islands" % (head, _boost_head(ob, bm, bm.loops.layers.uv.active, head)))
        bmesh.update_edit_mesh(me)
    bpy.ops.uv.select_all(action="SELECT")
    # SCALED margin: measured >= 2 texels between islands at 1024 for margin 0.002.
    # Blender's packer is not deterministic: keep the best of `tries` packs, and keep
    # packing (up to `max_tries`) while the atlas is below `target`.
    best, best_uv = -1.0, None
    for i in range(max_tries):
        if i >= tries and best >= target:
            break
        bpy.ops.uv.pack_islands(rotate=True, rotate_method="ANY", scale=True, margin_method="SCALED", margin=margin,
                                shape_method="CONCAVE")
        bm = bmesh.from_edit_mesh(me)
        uvl = bm.loops.layers.uv.active
        use = _bm_usage(bm, uvl)
        if use > best:
            best = use
            best_uv = [lp[uvl].uv.copy() for f in bm.faces for lp in f.loops]
    bm = bmesh.from_edit_mesh(me)
    uvl = bm.loops.layers.uv.active
    it = iter(best_uv)
    for f in bm.faces:
        for lp in f.loops:
            lp[uvl].uv = next(it)
    bmesh.update_edit_mesh(me)
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


def _drop_degenerate(ob, area=1e-7):
    """Dissolves near zero-area garment faces (hd_kind 4): one of them blows an angle-based
    unwrap up into an island the size of the atlas (Sable's mantle: atlas 51 %)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    kl = bm.faces.layers.int.get("hd_kind")
    bad = [f for f in bm.faces if f.calc_area() < area and (kl is None or f[kl] == 4)]
    if bad:
        edges = list({e for f in bad for e in f.edges})
        bmesh.ops.dissolve_degenerate(bm, dist=1e-4, edges=edges)
        bm.to_mesh(ob.data)
        ob.data.update()
    bm.free()
    print("paint: %d degenerate garment faces dissolved" % len(bad))


def bake_textures(h, ob, out_dir, size=1024):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    cfg = paint_cfg(h)
    me = ob.data
    _classify(h, ob)
    _drop_degenerate(ob)
    unwrap_pack(ob, cfg["uv_margin"], head=cfg.get("uv_head", 1.0))  # on quads: triangles give worse islands (58 % vs 76 %)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(me)
    bm.free()
    me.validate(clean_customdata=False)
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
    aoe = _bake(ob, _node_mat("a", _emit_tree(ao_edge)), S, samples=16)
    P = _bake(ob, _node_mat("p", _emit_tree(lambda nt: nt.nodes.new("ShaderNodeTexCoord").outputs["Object"])), S)
    N = _bake(ob, _node_mat("n", _emit_tree(lambda nt: nt.nodes.new("ShaderNodeNewGeometry").outputs["Normal"])), S)
    nrm = _bake(ob, _node_mat("nrm", _normal_mat(cfg["normal_bump"])), size, samples=4, kind="NORMAL")
    cov = coverage(T, S)
    dbg = os.environ.get("HERO_DEBUG")
    if dbg:
        np.savez_compressed(os.path.join(dbg, h.key + "_w16_passes.npz"), col=col, mat=mat, et=et, aoe=aoe, P=P, N=N,
                            nrm=nrm, cov=cov)
    sizes = composite(h, cfg, out_dir, size, col, mat, et, aoe, P, N, nrm, cov)
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
    # Per-hero painted detail (W16-B: mask markings, kintsugi, edge wear, sheen). The hook
    # edits ctx in place: "base" (flat colour, before the painted light), "emit" (0..1),
    # "spec" (added to the mask G), "noink" (suppresses the colour-border ink there).
    spec_add = np.zeros(emit.shape, dtype=np.float32)
    noink = np.zeros(emit.shape, dtype=np.float32)
    base_blocks = base  # colour-block ink follows the modelled blocks, never the painted detail
    if cfg.get("detail") is not None:
        ctx = {"h": h, "cfg": cfg, "P": p3, "N": n3, "base": base.copy(), "emit": emit.copy(), "spec": spec_add,
               "noink": noink, "aoe": aoe, "cov": cov, "metal": metal, "hard": hard, "k": k, "S": S}
        cfg["detail"](ctx)
        base, emit, spec_add, noink = ctx["base"], ctx["emit"], ctx["spec"], ctx["noink"]
    L = np.array(cfg["key_dir"], dtype=np.float32)
    L /= np.linalg.norm(L)
    lam = n3 @ L
    t0, sf = cfg["terminator"], cfg["soft"]
    lit = np.clip((lam - (t0 - sf)) / (2 * sf), 0, 1)
    lit = lit * lit * (3 - 2 * lit)
    ao = np.sqrt(np.clip(_blur(aoe[..., 0], 3.0), 0, 1))
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
    # Sparse, Borderlands-style: only below hatch_threshold, fading in toward the dark
    # side, in stroke clusters (a noise mask covering hatch_density of the zone).
    zone = np.clip((cfg["hatch_threshold"] - lam) / max(cfg["hatch_fade"], 1e-3), 0, 1) * (1.0 - skin)
    zone = zone * zone * (3 - 2 * zone) * (1.0 - lit)
    dens = float(np.clip(cfg["hatch_density"], 0.0, 1.0))
    cl = _fbm(p3 * 5.0 + 11.0, 2)
    cluster = np.clip((cl - (1.0 - dens) * 0.9 - 0.05) / 0.12, 0, 1)
    h1 = _lines(u1, cfg["hatch_width"], aa) * zone * cluster
    deep = np.clip((crease - cfg["cross"]) * 3.0, 0, 1)
    h2 = _lines(u2, cfg["hatch_width"] * 0.9, aa) * deep * zone
    hatch = np.clip(h1 + h2, 0, 1) * cfg["hatch"] * (1 - emit)
    ink = np.array(cfg["ink"], dtype=np.float32)[None, None]
    alb = alb * (1 - hatch[..., None]) + (alb * 0.35 + ink * 0.5) * hatch[..., None]
    # Edge strokes: bright on convex edges, strongest on hard parts.
    hl = edge * convex * (cfg["edge"] * (0.5 + 0.5 * hard) + 0.1 * cloth) * (0.6 + 0.4 * lit)
    alb = alb + (1.0 - alb) * hl[..., None]
    # Ink: colour-block borders (inside the islands only) + the deepest creases.
    q = np.round(base_blocks * 24).astype(np.int32)
    idm = q[..., 0] * 10000 + q[..., 1] * 100 + q[..., 2]
    inside = cov > 0.5
    bd = np.zeros((S, S), dtype=np.float32)
    for dy, dx in ((0, 1), (1, 0)):
        a, b = idm, np.roll(np.roll(idm, -dy, 0), -dx, 1)
        ia, ib = inside, np.roll(np.roll(inside, -dy, 0), -dx, 1)
        bd = np.maximum(bd, ((a != b) & ia & ib).astype(np.float32))
    border = _dilate(bd, int(cfg["ink_px"])) * cfg["ink_border"] * (1 - emit) * (1 - noink)
    cink = np.clip((crease - 0.55) * 4.0, 0, 1) * (1 - convex) * cfg["crease_ink"] * (1 - emit)
    inkm = np.clip(np.maximum(border, cink), 0, 1)
    alb = alb * (1 - inkm[..., None]) + ink * inkm[..., None]
    alb = np.where(emit[..., None] > 0.5, base, alb)
    alb = np.clip(alb, 0, 1)
    spec = np.clip(metal * (0.55 + 0.45 * edge) + spec_add, 0, 1)
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
