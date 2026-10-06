# Plant kit (Cell Cradle, Mana Cell, Charge Cradle): design brief and review notes

The Plant task (C4, match-flow-and-map.md §3.4): an attacker takes a **Mana Cell**
from their team's **Cell Cradle** (1 s interact), carries it to the Plant
hardpoint and plants it in the **Charge Cradle**, then defends it while it
charges. Before Phase 6 the Cradles were flat orange / blue octagons, the Cell a
prism, the Charge Cradle a white box "Y": nothing said "pick up here" or "plant
here".

## Briefs

| | Cell Cradle (`cell_cradle`) | Mana Cell (`mana_cell`) | Charge Cradle (`charge_cradle`) |
|---|---|---|---|
| Purpose | Where a team takes its Cell. One per attacking team, at the adjacent hardpoint toward its HQ (or its HQ lane gate). | The carried objective. | The plant socket at the Plant hardpoint's centre. |
| Read | A team-coloured charging station that **holds a Cell in clamps**: when the Cell is there you can take it; empty clamps = the Cradle is making a new one. Inward chevrons on the plate = "take it here". | A glowing capsule in a chrome cage (art bible §6.3), in the carrying team's colour. | Tuning-fork "Y" pylon (skyline silhouette, art bible §6.3) whose socket takes the Cell at 2.9 m; square pad with team corner brackets (Plant floor shape). |
| Scale | 2.0 m square plate, clamps to 1.45 m; the Cell rests at 1.0 m (HardpointView lift at CRADLE). | 0.4 x 0.8 m, pivot at its centre (HardpointView moves and spins it). | Stem = map collision (0.9 x 2.2 m); prong tips 4.1 m; brackets 3 m legs, 0.5 m high, at the zone half-width. |
| Team colour | Owning team (fixed per Cradle). | The Cell's team (re-tinted when it changes). | The hardpoint owner (re-tinted on capture, like the Holdstone). |
| Layers | Plate, skirt, pedestal, clamp arms / brass trim, rivets, chevrons, corner brackets, console / bolts, piston, cable. | Core, end caps / cage bars, brass rings, pins, rune tag. | Base, stem, prongs, socket / stone cladding, brass band, team channels / bolts, braces, cables, lamps. |
| Built by | `tools/art/world/plant_kit.py --only cell_cradle` | `--only mana_cell` | `--only charge_cradle` (pieces `main`, `bracket`) |

Not in this pass: the prongs lighting base-to-tip with charge progress (design
§6.3; the channel strips are in place for it), the Cell on the carrier's back
(it floats above the carrier as before).

## C5 placement markers (Garrison posts, Supply Cache)

The teal hexagon discs (Garrison posts) and the teal box (Supply Cache) are map
markers for C5 features that are **not in the game yet**: no Sentinels spawn and
the cache refills nothing. They are hidden at runtime (HardpointView) until
those systems exist, so the world does not promise a mechanic it lacks.

## Review log

Findings per iteration are appended below.

### Iteration 1 (2026-10-06): first bake

Builds: Cell Cradle 8,158 tris (1024 maps), Mana Cell 1,872 (512), Charge
Cradle 5,722 + bracket 1,258 (1024). Opened
`production/qa/evidence/p6b/after/cradle-close, cradle-mid, plant-close,
plant-mid, plant-approach, hold-mid.png`.

- Cell Cradle: the Cell in the four clamps reads as "take it here"; plate,
  chevrons and corner brackets are team-blue; sits on the adjacent Hold dais
  as the map places it. An empty Cradle (no Cell) shows open clamps (`hold-mid`).
- Charge Cradle: the "Y" reads from the zone edge; four corner brackets mark
  the square pad at the zone half-width. Fixed in this iteration: the planted
  beam started at the floor and hid the Cell; it now starts above the socket
  (`PLANT_BEAM_BASE_M`), and the Cell is visible between the prongs.
- Kit bugs found by looking at the atlases: zero-area faces (sphere clip on its
  equator, bevel collapsing thin chevrons) unwrapped to giant slivers and left
  the real islands in one corner (Mana Cell, Charge Cradle). Both removed in
  `world_kit.py`; the Charge Cradle was rebaked and its atlas checked.
- Garrison posts and the Supply Cache box no longer show (`hold-mid`).
- Not verified as frames: Cell carried / dropped, ownership swap of the Charge
  Cradle (code paths covered by `world_assets_test.gd`), prongs lighting with
  charge (not built).
