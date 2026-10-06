# Performance (Part 5, 2026-10-06)

How to measure, what was measured, what changed, and what CI guards.

## Tools

| What | Command | Measures |
|---|---|---|
| Server tick (dedicated, bots only) | `$GODOT --headless --fixed-fps 30 --path . -- --server --bots-only --seed 3 --quit-after-ticks 3600` | `[server] tick ... avg / max`, Wardling step avg + AI think, and `wardling step ms by section` every 5 s |
| Full offline match (client + server) | `$GODOT --headless --path . -s res://tools/bench_match.gd -- --bots --bench-s 60` | one `[bench]` JSON line: process / physics ms mean, p95, max; server Wardling step / think |
| Wardling animation (client CPU) | `$GODOT --headless --path . -s res://tools/perf_wardlings.gd -- --n 30 --near --frames 600` | process ms per frame for N rigged Wardlings (animation + scripts, no GPU) |
| CI gate | `tests/integration/performance/wardling_perf_gate_test.gd` | below |

**Measuring on a shared machine:** the dev container (4 shared cores) varies up
to 2x between identical runs. Report the minimum of 5 runs (or the median of 5
with all values), never one run. GPU / rendering cost cannot be measured here
(software Vulkan renders the map at <1 fps); that is a manual check on a real
GPU (docs/visual-review-checklist.md).

## Baseline and results (dev container, 2026-10-06)

| Measure | Before | After | Change |
|---|---|---|---|
| Server tick, bots only, ~30 Wardlings | 9.2 ms avg | 6.7 ms avg | -27 % (budget 33.3 ms at 30 Hz) |
| Wardling step | 4.8 ms | 3.2 ms | -33 % |
| ... of which `move` | 3.1 ms | 1.55 ms | navmesh snap 3.75 of 4.28 ms before |
| ... AI think | 1.1-1.2 ms | 1.1-1.2 ms | unchanged |
| Full offline match, physics step (server + client sim) | 14.9 ms mean | 14.0 ms mean | headless, 5v5 bots, 38 Wardlings |
| 30 Wardlings at 12 m, client animation (min of 5) | 5.11 ms | 4.73 ms | -8 % |
| Wardling animation, spread 5-100 m (10 / 30 / 60 / 100) | 3.05 / 4.72 / 7.13 / 8.21 ms | | single runs, includes ~1-2 ms base |

## What changed

1. **Wardling height from the path** (`WardlingWorld._move`): the navmesh
   closest-point query ran for every moving Wardling every tick and was ~80 % of
   the step. A Wardling on a path now takes its height from the path segment
   (path points lie on the navmesh) and runs the full snap every
   `WardlingRulesDef.snap_every` (4) ticks, staggered by id, or when it has no
   path / has left its segment. Height error measured over a full bot match:
   ~2 mm mean, < 3 mm max. Today 41 % of moving ticks still snap.
2. **Shared bone attachments** (`WardlingRig`): one BoneAttachment3D per bone
   instead of one per prop; attachments whose props are all hidden stop
   updating. Engine attachment updates, not the AnimationTree, were the bigger
   per-Wardling cost (turning the trees off saved nothing measurable).
3. **Not changed:** the animation LOD table (stride 1 / 2 / 4 / 8 by distance).
   A tighter table (full rate only below 8 m) measured *slower* (median 5.9 vs
   4.4 ms): manual `advance()` costs about what it saves at these counts.

## CI gate

`wardling_perf_gate_test` (runs in the normal test job):

- snap ratio (snapping moves / moving Wardling ticks) <= 0.50 in a 40 s 5v5 bot
  run: deterministic; watched failing at 1.00 with `snap_every = 1`;
- mean server tick < 20 ms over the same run (measured 7.9 ms; budget 33.3 ms):
  generous on purpose, catches a ~2.5x regression, not noise;
- a tier I squad Wardling has 1 updating bone attachment, more when its props
  show.

## Open

- Rendering cost on a real GPU (Wardlings near: 13k tris each + outline) is not
  measured here: manual check.
- Client physics step in the offline match (14 ms mean headless) includes the
  local server; a dedicated-client measurement needs the online path.
- `bench_match.gd` reports 0 Wardling models headless (the client skips models
  without a display); its Wardling numbers come from the server.
