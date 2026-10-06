# Visual verification

How screenshots are made in a headless cloud VM, and which render path works.
Tool: `tools/shot.gd` (presets); review procedure: `.claude/skills/visual-review/SKILL.md`.

## Render paths tried (2026-10-06, Godot 4.7-stable, Ubuntu 24.04 VM, no GPU)

| # | Path | Result |
|---|---|---|
| 1 | `godot --headless` + viewport readback | **Does not work.** The headless display server uses the dummy renderer: no pixels. The first attempt hung until killed at 120 s. `shot.gd` now refuses to run headless (exit 2, "NOT ASSESSED"), so it can never write blank images that look like evidence. |
| 2a | `xvfb-run` + Mesa, no Vulkan driver | Works, but Godot falls back to **OpenGL 3 (Compatibility renderer, llvmpipe)**: "Required Vulkan instance extension VK_KHR_surface not found". The game runs Forward+, so lighting, glow and AO differ. **Not used for fidelity judgments.** |
| 2b | `xvfb-run` + Mesa **lavapipe** (`mesa-vulkan-drivers`) | **Works: Vulkan 1.4, Forward+, llvmpipe.** This is the path in use. About 30 s per preset at 1600x900 (4 cores). |
| 3 | Godot MCP server | Not needed (2b works). |

Setup (idempotent; `tools/ci/setup_render.sh` does it):

```bash
apt-get install -y mesa-vulkan-drivers xvfb      # lavapipe ICD: /usr/share/vulkan/icd.d/lvp_icd.json
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
```

## Command

```bash
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
xvfb-run -a -s "-screen 0 1600x900x24" timeout 2500 $GODOT --path . --resolution 1600x900 \
  -s res://tools/shot.gd -- --out production/qa/evidence/<set> [--only uplink,hold] [--list]
```

Exit codes: 0 all presets written; 1 a preset rendered blank (named in the log)
or none matched; 2 run headless; 3 watchdog (`SHOT_TIMEOUT_S`, default 900 s).
A blank frame is detected by sampling a 16x16 grid of pixels.

## Presets

Computed from `assets/data/match/map_front.tres`, so they follow the layout:

| Preset | What |
|---|---|
| `fp-spawn-a`, `fp-spawn-b` | first person (1.7 m) at each HQ spawn, along the spawn yaw |
| `fp-lane-north/center/south` | first person at team A's Outer hardpoint, looking at Mid |
| `topdown` | whole map from 520 m |
| `base-a`, `base-b` | each HQ from above and behind (Uplink, Sanctum, Foundry, Armory) |
| `<obj>-close/-mid/-far/-approach` | `uplink`, `armory`, `mid-hardpoint`, one `hold`, `plant`, `breach` hardpoint: 6 / 15 / 35 m and a first-person walk-up at 25 m, from team A's side |
| `hero-ref` | Vesper (as `HeroModelLoader` builds her, idle) and a Tier II Picket Wardling at the Center Mid hardpoint: the fidelity and scale reference |

Lighting is the map's own (WorldEnvironment and lights in the scene): the
same lighting players see. The objective views are the client's own
(`HardpointView`, `UplinkView`, `ArmoryMarkerView`), spawned from the MapDef the
way `ClientWorld.setup_objectives` does.

## Known limits

- Software Vulkan: correct features, not real-GPU performance or exact
  driver-specific colour. Real-monitor judgments go to
  `docs/visual-review-checklist.md`.
- Still frames: motion, animation timing and VFX feel need the checklist too.
- Every run prints one `ERR_CANT_OPEN` (`Condition "status < 0"`). Its source is
  not identified yet (unverified); all presets still render.
