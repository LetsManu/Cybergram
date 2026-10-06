# P7 floor tiles + world decals (2026-10-06)

`tools/shot.gd`, xvfb + Mesa lavapipe (Forward+), 1600x900, presets
`fp-lane-*`, `fp-spawn-*`, `hold-approach`, `plant-approach`, `breach-approach`,
`mid-hardpoint-mid`, `base-a`, `topdown`.

- `before/` - this branch before the work (flat panel floors, no decals).
- `after-v1/` - first iteration: painted tiles split per panel, decals, no parallax.
  Owner: "it is not 3D, it looks just like painted on".
- `after/` - final: parallax occlusion, real 5 cm joints, stronger normal / AO,
  2 m tiles in running bond with 4 m feature plates, sunk tiles, calmer variant mix.

All frames listed in `docs/assets/floor.md` (review log) were opened. Findings,
including what is still below standard, are there.
