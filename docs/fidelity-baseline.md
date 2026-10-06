# Fidelity baseline: heroes vs world (2026-10-06)

Measured read-only (glb parsing and headless Godot scene walks; the asset-auditor
pass), plus the screenshot set `production/qa/evidence/p5-world/before/` (looked
at, findings in its README). Numbers, not opinions; "not measured" says so.

## The bar: heroes (`assets/models/heroes/`)

| | Measured |
|---|---|
| Triangles (3P main mesh) | 12,174 (Hex) to 25,266 (Liora); Vesper 21,500 |
| LOD | every hero has an 8,000-tri `<key>_lod` mesh (ink hull up close) |
| Materials | 1 (`Toon_<key>`) -> `spatial_char_toon_rigged` + `spatial_char_outline_hull` |
| Texture set | albedo 1024², normal 1024², mask 512² (R AO, G spec, B emissive, A team); painted light, AO, creases, hatching, wear baked in |
| UV atlas use | 75-85 % |
| Texel density (3P) | 256 (Brannoc) to 493 px/m (Hex); typical ~350 px/m |
| First-person arms + weapon | 8.3k-14.2k tris, 782-1,133 px/m, same map set |
| Rig / clips | 21-42 joints, 22 clips (3P); FP 37 joints, 12 clips |
| Build | Blender `bpy` pipeline, 296 s per hero (verified here, `docs/model-pipeline.md`) |

## The world today

| Asset family | Triangles | Material | Maps | LOD | Animation / audio |
|---|---|---|---|---|---|
| Map structure (3,208 MeshInstances, all unique meshes: 2,873 BoxMesh, 110 Cylinder, 106 ArrayMesh steps/ramps) | 93.7k total; 12 per box | 2,128 instances `spatial_env_panel` (procedural seams, no textures); 1,080 **unshaded** StandardMaterial3D (289 with alpha) | 0 | none (0 visibility ranges) | static |
| Hardpoint Shield dome / zone ring (map) | 4,224 / 4,096 each (default sphere and torus segments) | unshaded alpha | 0 | none | static |
| Garrison posts (45), Cell Cradles (20), Generator cores (5), Uplink spire / plinth / core, Sanctum canopy | 36-192 each | unshaded / panel | 0 | none | static |
| Supply Cache, Foundry, Armory (map) | 12-24 each (boxes) | unshaded / panel | 0 | none | static |
| `HardpointView` (runtime) | torus ring, box segments, sphere shield, quad bars, prism cell, cylinder beam | unshaded StandardMaterial3D | 0 | - | sine pulses in `_process`; **no audio** |
| `UplinkView` + UplinkModel | 5,556 (procedural ArrayMesh) | toon + holo + crystal | 0 | none | code rotation / judder; **no audio** |
| `ArmoryMarkerView` | torus, disc, beam cylinder, Label3D | unshaded alpha + beacon shader | 0 | - | code pulse; no audio |
| Wardling (procedural, `part_builder`) | ~2.2k (tier 1) | `spatial_char_toon` (per-vertex zones) + outline | 0 | none | code bob, no skeleton |
| Weapons (procedural, 3P) | 484-1,632 | toon + conduit | 0 | none | - |
| Lighting / env | 1 shadowed DirectionalLight (+1 rim at runtime), 71 Omni; SSAO, glow, fog on; SDFGI / SSIL / SSR off | - | - | - | 1,080 unshaded instances ignore all lights |

Client-side dressing adds 13 MultiMeshes (895 instances, 12-48 tris each: skyline,
spires, crystals, traffic, neon frames, fog banks) for 113k tris in total.

## Gap table

| Asset | Current | Hero-level spec | Gap | Fix type |
|---|---|---|---|---|
| Mana Uplink (spire, plinth, core, shell) | 5.6k procedural tris + 36-192-tri map cylinders; no maps; code motion | art bible §6.5 (45 m spire, rings, rune bands, crack stages); hero texture set; LODs | no bevels, no baked detail, no damage stages, no audio | regenerate with hero pipeline + new VFX/animation/audio |
| Holdstone (Hold) | cylinder plinth + beam + torus | §6.3 chrome ring plinth around a dormant crystal, 12 m light pillar | primitive | regenerate with hero pipeline + new VFX |
| Charge Cradle (Plant) + Mana Cell | white "Y" of cylinders, prism cell | §6.3 twin-pronged chrome pylon, prongs light base to tip | primitive | regenerate with hero pipeline |
| Ward Generator (Breach) | 4.2k-tri default sphere dome over a 36-tri cylinder | §6.3 hex-faceted shield, spinning crystal core, 3 crack stages | no generator model, no stages | regenerate + new shader/material + VFX |
| Barricade | not modelled as an asset (sockets only) | §6.4 two faction styles, 3 damage states, rubble | missing | regenerate with hero pipeline |
| Garrison socket / Supply Cache / Forward Beacon | 12-36-tri boxes / cylinders | §6.4 | primitive | regenerate with hero pipeline |
| HQ set (Sanctum, Foundry, Armory) | boxes, slabs, floating label | §6.5 set-pieces | primitive | regenerate + layout/lighting |
| Map kit (walls, floors, cover, stairs, rails) | 3,208 unique primitive meshes, 0 maps, 1/3 unshaded | §6.1-6.2, §10.6 modular pieces 200-5k tris + trim sheets | no bevels, no texture, no instancing, no LOD | regenerate with hero pipeline (modular kit) + layout/lighting |
| Wardlings | ~2.2k-tri primitives, code bob | §10.6 4k (Sentinel 6k), shared 1024 atlas | no maps, no rig | regenerate with hero pipeline (later phase) |
| 3P weapons | 0.5-1.6k primitives | §10.6 6k, 1024 | no maps | regenerate with hero pipeline (later phase; FP weapons already done) |

Not measured: GPU frame time and draw calls (software Vulkan is not
representative), per-asset file sizes for the map (one 3.1 MB scene).
