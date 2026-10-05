"""W16 hero pipeline: bespoke body + painted texture set + baked cloth.

Selected per hero by `"pipeline": "gen"` in its HEROES entry (hero_defs*.py);
build_hero.py dispatches here. Every other hero keeps the MakeHuman path.
How-to: tools/art/README-hero-pipeline.md.

Steps (timed, printed per hero):
  body     body_gen: skeleton from the body params, cage, subdivision, sculpt, weights
  paint    colour regions (cuts / regions / shells, same API as the old path)
  parts    hero parts (mask, gear), the hero's own weapon builder, garments (cloth_bake)
  rig      armature (GAME_BONES + Weapon + Cloth_ chains), join
  texture  hero_paint: UV pack, Cycles data bakes, Borderlands composite
  anims    hero_anims.author_all (mocap + scripted clips, optional per-hero idle)
  cloth    cloth_bake: Blender cloth sim per clip, baked onto the Cloth_ bones
  export   build_hero.export (glb + sidecars)

Flags: --notex (flat vertex colours, no maps written), --nocloth (garments stay
rigid on their bones), --scripted (no mocap).
"""
import os
import sys
import time

import bpy
from mathutils import Vector

import body_gen
import build_hero
from build_hero import GAME_BONES, Hero, _activate, srgb


class GenHero(Hero):
    """A Hero whose body comes from body_gen instead of the MakeHuman base."""

    def __init__(self, hero):  # noqa: super().__init__ is the MakeHuman path
        self.d = hero
        self.key = hero["key"]
        self.pal = {k: srgb(v) for k, v in hero["palette"].items()}
        self.names = {}
        self.joints = {}
        self.parent = {}
        self.bp = body_gen.params(hero)
        J, lm = body_gen.skeleton(self.bp, hero["height"])
        self.J, self.lm = J, lm
        for name, _a, _b, parent in GAME_BONES:
            self.joints[name] = (J[name][0].copy(), J[name][1].copy())
            self.parent[name] = parent
        self.bone_names = [g[0] for g in GAME_BONES] + ["Weapon"]
        self.parent["Weapon"] = "UpperChest"
        self.palm = {s: lm["palm"][s].copy() for s in ("L", "R")}

    def build_body(self):
        ob = body_gen.build_body_object(self.key, self.J, self.lm, self.bp, self.bone_names)
        ob.data.attributes.new("is_eye", "BOOLEAN", "FACE")  # paint_body API (no eye faces here)
        self.body = ob
        return ob

    def bbox(self, bone, wmin=0.5):
        gi = self.body.vertex_groups[bone].index
        P = [v.co for v in self.body.data.vertices if any(g.group == gi and g.weight > wmin for g in v.groups)]
        if not P:
            h, t = self.joints[bone]
            return Vector(tuple(map(min, h, t))), Vector(tuple(map(max, h, t)))
        lo = Vector(tuple(min(p[i] for p in P) for i in range(3)))
        hi = Vector(tuple(max(p[i] for p in P) for i in range(3)))
        return lo, hi

    def eye(self, s):
        """Virtual eye centre (inside the head, behind the face surface); L = -X."""
        hh, _ht = self.joints["Head"]
        L = self.lm["L"]
        sx = -1.0 if s == "L" else 1.0
        return Vector((sx * 0.032 * self.lm["k"], hh.y + L["head_d"] * 0.25, hh.z + L["head_h"] * 0.5))


def cull_covered(h, reach=0.04):
    """Deletes body faces (hd_kind 0) hidden under an armour shell (hd_kind 1): a ray
    from the face centre along its normal hits a shell within `reach` m. Saves tris and
    atlas space; the shell rim closes the gap visually."""
    import bmesh
    from mathutils.bvhtree import BVHTree
    me = h.body.data
    bm = bmesh.new()
    bm.from_mesh(me)
    kl = bm.faces.layers.int.get("hd_kind")
    if kl is None:
        bm.free()
        return 0
    shell = [f for f in bm.faces if f[kl] == 1]
    if not shell:
        bm.free()
        return 0
    verts = [v.co.copy() for v in bm.verts]
    bm.verts.index_update()
    bvh = BVHTree.FromPolygons(verts, [[v.index for v in f.verts] for f in shell])
    dead = []
    for f in bm.faces:
        if f[kl] != 0:
            continue
        c = f.calc_center_median()
        hit = bvh.ray_cast(c + f.normal * 1e-4, f.normal, reach)
        if hit[0] is not None and all(bvh.ray_cast(v.co + f.normal * 1e-4, f.normal, reach)[0] is not None
                                      for v in f.verts):
            dead.append(f)
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bm.to_mesh(me)
    bm.free()
    me.update()
    return len(dead)


def build(key, hd, out_dir=None):
    import cloth_bake
    import hero_anims
    import hero_defs
    import hero_hd
    T = {}
    t = time.time()

    def lap(name):
        nonlocal t
        T[name] = time.time() - t
        t = time.time()
    build_hero.reset_scene()
    h = GenHero(hd)
    h.build_body()
    lap("body")
    h.paint_body()
    if hd.get("smooth_shells", True):
        hero_hd.smooth_shells(h)
    print("gen: culled %d body faces under shells" % cull_covered(h))
    lap("paint")
    weapon_rest = hero_anims.weapon_rest(h)
    h.weapon_rest = weapon_rest
    h.begin_parts()
    hero_hd.prep_palette(h)
    hd["parts"](h)
    hero_defs.WEAPONS[hd["weapon"]](h, weapon_rest)
    garments = cloth_bake.add_garments(h)
    collider = cloth_bake.make_collider(h) if garments else None
    parts = h.finish_parts()
    hero_hd.harden_parts(parts)
    lap("parts")
    rig = h.build_armature(weapon_rest)
    _activate(h.body)
    parts.select_set(True)
    bpy.ops.object.join()
    body = h.body
    body.name = body.data.name = h.key
    for p in body.data.polygons:
        p.use_smooth = True
    lap("rig")
    tex_sizes = {}
    if "--notex" not in sys.argv:
        import hero_paint
        dst = os.path.join(out_dir or build_hero.OUT_DIR, h.key)
        os.makedirs(dst, exist_ok=True)
        tex_sizes = hero_paint.bake_textures(h, body, dst, int(os.environ.get("HERO_TEX", "1024")))
    elif "hd_kind" in body.data.attributes:
        body.data.attributes.remove(body.data.attributes["hd_kind"])
    lap("texture")
    body.data.materials.clear()
    body.data.materials.append(bpy.data.materials.new("Toon_" + h.key))
    lod = build_hero.make_lod(h, body)
    build_hero.attach_rig(rig, body, lod)
    mocap_info = hero_anims.author_all(h, use_mocap="--scripted" not in sys.argv)
    lap("anims")
    if garments and "--nocloth" not in sys.argv:
        cloth_bake.bake(h, garments, collider)
    elif collider is not None:
        bpy.data.objects.remove(collider, do_unlink=True)
    lap("cloth")
    build_hero.export(h, rig, body, lod, mocap_info, tex_sizes, out_dir)
    lap("export")
    print("timing %s: %s, total %.0f s" % (key, ", ".join("%s %.0f s" % kv for kv in T.items()), sum(T.values())))
