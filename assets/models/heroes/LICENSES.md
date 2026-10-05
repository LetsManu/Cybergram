# Hero model sources and licences

## Base body, rig and skin weights — MakeHuman (CC0 1.0)

| Field | Value |
|---|---|
| Asset | MakeHuman default base mesh `base.obj` (hm08), default skeleton `default.mhskel`, skin weights `default_weights.mhw`, macro targets `universal-*-young-*` and `*-idealproportions` |
| Source | https://github.com/makehumancommunity/makehuman (pinned commit `a8bc2d54ff0ac92e78ff71431b1023eda42bf482`) |
| Exact files | `makehuman/data/3dobjs/base.obj`, `makehuman/data/rigs/default.mhskel`, `makehuman/data/rigs/default_weights.mhw`, `makehuman/data/targets/macrodetails/...` |
| Licence | CC0 1.0 Universal — repo `LICENSE.ASSETS.md`; each file header states "explicitly released as CC0 in september 2020"; `.mhskel`/`.mhw` carry `"license": "CC0"` |
| Authors | Manuel Bastioni (original), Data Collection AB, Joel Palmius, Jonas Hauquier (MakeHuman team) |
| Attribution | Not required (CC0). Credited here as a courtesy. |

Fetched by `tools/art/fetch_base.sh` into `tools/art/.cache/` (gitignored); only the
built `.glb` files are committed.

## Everything else — original work for Cybergram

Armour, helmets, hair, coats, gear, weapons, colour atlases and **all animations** (idle,
locomotion, jump, aim, shoot, reload, casts, death) are authored procedurally by
`tools/art/build_hero.py` in this repo and are project-owned.

## Candidates evaluated and NOT used (2026-10-05)

| Candidate | Licence | Why not |
|---|---|---|
| three.js `examples/models/gltf/RobotExpressive` (Quaternius) | CC0 | Robot with chibi proportions; no aim/shoot/reload clips |
| KenneyNL/Starter-Kit-3D-Platformer `models/character.glb` | CC0 | Chibi platformer figure, not a ~7.5-head human |
| GDQuest third-person controller `gdbot.glb` | project licence, not CC0 | Robot; licence not CC0 |
| KhronosGroup glTF-Sample-Assets CesiumMan / RiggedFigure | CC-BY 4.0 | Walk only, low-fidelity, attribution burden |
| three.js Xbot / Soldier / Michelle | Mixamo | Mixamo — forbidden |
| Quaternius / Kenney / poly.pizza / OpenGameArt sites | CC0 | Not reachable from the build environment |

No CC0 humanoid with idle/run/jump/shoot clips was reachable, so the base is the CC0
MakeHuman mesh + rig and the animations are authored keyframes (the brief's fallback for
the animation half only).

## Locomotion animation — CMU Graphics Lab Motion Capture Database

The data used in this project was obtained from mocap.cs.cmu.edu.
The database was created with funding from NSF EIA-0196217.

| Field | Value |
|---|---|
| Source | http://mocap.cs.cmu.edu (terms: "free for use in research and commercial projects") |
| BVH conversion | Bruce Hahne (cgspeed), mirrored at https://github.com/una-dinosauria/cmu-mocap (commit `09a07f54f3`) |
| Fetch | `tools/art/fetch_mocap.sh` -> `tools/art/.cache/cmu/` (gitignored) |
| Retarget | `tools/art/mocap.py` (direction-based onto the game rig, in place, loop drift-corrected, legs exaggerated x1.1-1.15) |

| Game clip | CMU subject_trial | CMU description | Use |
|---|---|---|---|
| `idle` | 40_10 | wait for bus | calmest 3 s window, looped |
| `walk` | 16_15 | walk | one stride cycle (autocorrelation period) |
| `run` | 16_35 | run/jog | one stride cycle; played up to x2.2 at sprint speed |
| `run_back` | 16_15 | walk | the walk cycle reversed |
| `jump` | 16_01 | jump | take-off to just before landing |
| `death` | 90_16 | fall on face | collapse to rest |

Scripted (project-owned) clips layered on top or used where CMU has no fit: `aim_up/mid/down`,
`shoot`, `reload`, `hit`, `cast_0..3`, `crouch_idle`, `crouch_walk`, `strafe_l/r`.
Per-hero trial record: `assets/models/heroes/<id>/<id>.anim.json`.
