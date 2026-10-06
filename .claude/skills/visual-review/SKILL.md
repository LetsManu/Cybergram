---
name: visual-review
description: "Capture the standard camera presets of the map, objectives and a hero reference, LOOK at them, and write down what was checked. Use after every visual change to the world, objectives or props."
argument-hint: "[set-name] [--only name,fragments]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash, Write, Edit
---

# Visual review

Evidence over claims: a visual change is not done until its presets were
rendered **and looked at**. Never describe how something looks without having
opened the PNG in this session.

## 1. Capture

```bash
GODOT=~/godot/Godot_v4.7-stable_linux.x86_64      # tools/ci/install_godot.sh prints it
$GODOT --headless --path . --import               # after new class_names / assets
bash tools/ci/setup_render.sh                      # once: lavapipe Vulkan + xvfb
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
xvfb-run -a -s "-screen 0 1600x900x24" timeout 2500 $GODOT --path . --resolution 1600x900 \
  -s res://tools/shot.gd -- --out production/qa/evidence/<set>/<before|after> [--only uplink,hold]
```

- `--list` prints the preset names (they come from `assets/data/match/map_front.tres`).
- Render path and why: `docs/visual-verification.md`. Headless (`--headless`) gives
  no pixels: always use xvfb. Without `VK_ICD_FILENAMES` Godot silently falls back
  to OpenGL (log says "switching to OpenGL 3"): then the set is **NOT ASSESSED**
  for fidelity, because the game renders Forward+.
- `shot.gd` exits non-zero and names the preset when a frame is blank. A preset
  that was not rendered, or an image you did not open, is **NOT ASSESSED**,
  never "looks fine".
- Keep sets small and named after the change (`p6-uplink/before`, `p6-uplink/after`).
  Same presets before and after, same resolution.

## 2. Look

Open every image you will talk about with the Read tool. For each preset check:

1. **Fidelity vs the hero** (`hero-ref`, and any hero in frame): bevelled edges,
   layered forms (primary / secondary / tertiary), painted light and ink outline
   like the heroes. Flat untextured boxes, grid-only surfaces and primitive
   cylinders are below standard.
2. **Readability**: team colour reads at a glance, the objective's state reads
   from `-far` and from `-approach` (first person at 25 m).
3. **Grounding**: no floating or clipping pieces; the asset sits in the floor
   (rubble, decals, trim) instead of on it.
4. **Scale**: against the 1.85 m hero; doors, steps, cover heights plausible.
5. **Noise**: no z-fighting, no shimmering detail at `-far`, no blown-out emissive.

## 3. Write down

Append to the asset's notes file (`docs/assets/<asset>.md`) or the phase report:
which presets were opened, what was found (issue + preset name), and what is
still below standard. Judgments a virtual display cannot make (colour on a real
monitor, motion, feel at 144 Hz) go to `docs/visual-review-checklist.md`.
