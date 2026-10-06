# Mana Uplink: design brief and review notes

## Brief

| | |
|---|---|
| Purpose | The win condition (C6, C7): each HQ's broadcast spire. Becomes damageable when Exposed; destroying it ends the match. |
| Story | A giant mana crystal held in a chrome frame, broadcasting the team's Cybergram as a beam into the sky (design/art-bible.md §6.5). |
| Silhouette | 45 m vertical spire: wide stone plinth, three converging legs, five rings narrowing upwards, a crystal at 7.3 m, mast and emitter dish at 44 m. Readable from anywhere on the map (the beam orients players). |
| Scale | Plinth 4.6 / 3.6 m radius, 1.5 m high (matches the map's collision cone 4.5 / 3.5 / 1.5). Crystal centre 7.3 m (gameplay core). Pylons 4.6 m (2.5 heroes). |
| States | Protected (shell, smooth ring spin, steady beam) / Exposed (shell gone, rings stop and judder, rune bands glitch, beam jagged) / Integrity 75-50-25 (crack stages, one rune band dies per stage) / Destroyed (beam off, crystal grey). The state logic is UplinkModel's (unchanged); this asset replaces its solid structure. |
| Layers | Primary: plinth, legs, mast, rings. Secondary: armour plates on the legs, cross braces with gussets, pylons with caps, claws with knuckles, emitter fins. Tertiary: rivets, vents, pistons, pipes, neon slits, glyph teeth on the rings. |
| Team colour | Neon channels (`team_emit`): leg channels, collar, pylon slits, ring teeth, claw tips, emitter. Everything else neutral (stone, iron, chrome, brass), so one asset serves both teams by uniform. |
| Built by | `tools/art/world/uplink.py` (seed 1701) on the hero pipeline. Kept procedural on purpose: crystal, rune bands, beam, cracks (holo / crystal shaders, design §10.4). |
| Budget | <= 80k tris (design §10.6). Geometry pass: 42,312 tris in 6 pieces (main 26,320, rings 2.6k-4.2k). Auto LODs at import. |

## Review log

Findings per iteration are appended below (which presets were opened, what was seen).
