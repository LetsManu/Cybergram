#!/usr/bin/env python3
"""W19-VM: builds a hero's first-person viewmodel glb (hands, gloves, sleeves, the
hero's own weapon at FP detail, FP clips) -> assets/models/heroes/<id>/<id>_fp.glb.

    /tmp/venv/bin/python tools/art/build_fp.py vesper
      --notex          no texture bake (flat vertex colours; fast iteration)
      --out <dir>      another output root

Writes, next to the 3P set:
  <id>_fp.glb                       one skinned mesh + the FP skeleton + 12 clips
  <id>_fp_albedo/_normal/_mask.png  the Borderlands painted set (hero_paint, FP light)
  <id>_fp.tres                      Godot sidecar: fp_pos, sockets, clip info, tris
Definitions: tools/art/fp_defs.py. Rig and clips: fp_rig.py, fp_anims.py.
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import build_hero  # noqa: E402

OUT_DIR = build_hero.OUT_DIR


def gd(v):
    """Blender (Z up, +Y forward) -> Godot (Y up, -Z forward)."""
    return (v.x, v.z, -v.y)


def build(key, out_root=None):
    import fp_anims
    import fp_defs
    import fp_rig
    import hero_defs
    import hero_hd
    t0 = time.time()
    fd = fp_defs.HEROES[key]
    hd = dict(hero_defs.HEROES[fd["hero"]])
    if fd.get("palette"):  # W16 palette of a hero whose gen def lives on its own branch (fp_weapons_w16)
        hd["palette"] = fd["palette"]
    paint = {k: v for k, v in hd.get("paint", {}).items() if k != "shader"}
    paint.update(fp_defs.FP_PAINT)
    paint.update(fd.get("paint", {}))
    hd["paint"] = paint
    build_hero.reset_scene()
    fk = key + "_fp"
    h = fp_rig.FpHero(fk, hd, fd)
    rig = fp_rig.FpRig(h, fd)
    wkey = fd.get("weapon") or hd["weapon"]
    import fp_weapons_w16
    parts = rig.build_meshes(hero_defs.WEAPONS.get(wkey) or fp_weapons_w16.WEAPONS[wkey])
    parts.name = parts.data.name = fk
    for p in parts.data.polygons:
        p.use_smooth = True
    dst = os.path.join(out_root or OUT_DIR, key)
    os.makedirs(dst, exist_ok=True)
    tex = {}
    if "--notex" not in sys.argv:
        import hero_paint
        hero_hd.HD[fk] = hero_hd.HD.get(fd["hero"], {})
        tex = hero_paint.bake_textures(h, parts, dst, int(os.environ.get("FP_TEX", "1024")))
    elif "hd_kind" in parts.data.attributes:
        parts.data.attributes.remove(parts.data.attributes["hd_kind"])
    parts.data.materials.clear()
    parts.data.materials.append(bpy.data.materials.new("Toon_" + fk))
    arm = rig.build_armature()
    build_hero.attach_rig(arm, parts, None)
    info = fp_anims.author_all(rig)
    tris = sum(len(p.vertices) - 2 for p in parts.data.polygons)
    sockets = rig.sockets_armature()
    arm.location = -rig.grip  # the glb root sits at the grip: the runtime pivots / FOV-fits there
    out = os.path.join(dst, fk + ".glb")
    build_hero._activate(arm)
    parts.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_vertex_color="NAME",
                              export_vertex_color_name="Color", export_all_vertex_colors=False, export_skins=True,
                              export_yup=True, export_force_sampling=True, export_optimize_animation_size=True,
                              export_materials="EXPORT", export_image_format="NONE", export_tangents=False,
                              export_def_bones=False, export_leaf_bone=False)
    with open(os.path.join(dst, fk + ".tres"), "w") as fh:
        fh.write('[gd_resource type="Resource" format=3]\n\n[resource]\n')
        fh.write("metadata/fp_pos = Vector3(%.4f, %.4f, %.4f)\n" % gd(rig.grip))
        fh.write("metadata/sockets = {\n%s\n}\n" % ",\n".join(
            '"%s": Vector3(%.4f, %.4f, %.4f)' % ((k,) + gd(v)) for k, v in sorted(sockets.items())))
        fh.write("metadata/clip_length = {\n%s\n}\n" % ",\n".join(
            '"%s": %.4f' % (k, v["length"]) for k, v in sorted(info.items())))
        fh.write("metadata/tris = %d\n" % tris)
        fh.write('metadata/weapon = "%s"\n' % wkey)
        fh.write("metadata/fallback = %s\n" % ("true" if fd.get("fallback") else "false"))
    print("built %s: %d tris, %d bones, %d clips, %.2f MB glb, textures %s, %.0f s" % (
        out, tris, len(arm.data.bones), len(info), os.path.getsize(out) / 1e6,
        {k: round(v / 1e6, 2) for k, v in tex.items()}, time.time() - t0))


if __name__ == "__main__":
    root = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else None
    skip = {root}
    for k in [a for a in sys.argv[1:] if not a.startswith("--") and a not in skip]:
        build(k, root)
