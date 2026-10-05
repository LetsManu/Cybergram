# HUD v0.12: premium-dark restyle (spec for owner review)

Status: **APPROVED by the owner (2026-10-05).** Ready for implementation. No game code has changed yet.

Owner choices:
- **Top-centre:** variant **D**, which is A's clock plate and framed Uplink bars with C's single-line lanes (§2a).
- **Ready ult:** brass gradient rim only, no shimmer.
- **Idle fade:** 4 s by default, exposed as a HUD setting: Off / 4 s / 8 s.
- **Minimap:** keeps its current size (318×204 at 1080p).
Mockup: `design/ux/mockups/v0.12-hud/Hud.html` (open it in a browser and click the state buttons, or press keys 1–0 and hold Tab). Variant D is the default. A, B and C stay in the mockup for reference only.
Evidence: `production/qa/evidence/w19-hudmock/*.png`.
Base spec: `design/ux/hud.md` (zones §3.2, contexts §14, budget §15, accessibility §16). This document changes the **look** only. Rules, data and zones stay as they are.

## 1. Direction

- The visual system is the approved v0.9 menus: ink `#0B1015`, brass `#C2A267` / `#EAD7A8` as the only accent and action colour, teal `#4FB8B0` for status only, ivory text `#ECE6D6` / muted `#9AA3A8` / dim `#6C757A`.
- Type:
  - **Chakra Petch** for headings, caps labels and every number (tracking .16–.3em on caps).
  - **IBM Plex Sans** for names and body text.
  - **IBM Plex Mono** for keys, lane letters and small counters.
- **No boxes.** Drop the old navy panels with keylines. Readability comes from:
  - two soft ink scrims, top (150 px) and bottom (190 px), at 62–66% maximum opacity and fading to 0;
  - a text shadow on HUD text (`0 1px 2px #000 .75` plus an 8 px ink glow).
- **Shapes:**
  - cut corners (8 px chamfer at 1080p, 5 px on small chips) on the ability slots, death options, the Armory and brass buttons;
  - 1 px brass key chips (Q / E / C / G / 4 / R / K);
  - brass corner ticks frame the minimap.
- **Team colours** come from `HudPalette.TEAM_COLORS` and stay unchanged (Concord `#2E86FF`, Syndicate `#FF5A1F`, plus the presets).
  - Team colour only marks team identity, never decoration.
  - Every team colour is paired with a shape: chevron for allies, diamond for enemies, solid fill for own ground, hatch for enemy ground.
- **Danger colour** stays `HudPalette.damage_color()` (`#FF4A3D`; amber or pink under the presets). The menu `danger` token (`#C8574A`) is too dull over the purple lanes.
- **Sizes:** all sizes below are 1080p design units (`HudLayout`, scale 1.0). The mockup is 1280×720 = 2/3 of these. At runtime, 720p uses the 0.9 floor scale, so its text is larger than in the mockup.

## 2. Elements

Columns: **Zone / position** (1080p design units, inside the 3% safe margin) · **Size and colours** · **Idle fade** · **Implemented by**.

**Idle fade** applies after the last combat event, using the new HUD setting `hud.idle_fade`: Off, 4 s (the default) or 8 s. It is restored instantly on damage, firing, a cast or an objective change.

| Element | Zone / position | Size and colours | Idle fade | Implemented by |
|---|---|---|---|---|
| Match header + front strip | Top-centre | See §2a (reworked, variants A / B / C) | lanes 42% | `match_header.gd` + `front_strip.gd` |
| Objective card | Right-middle, 366 wide, top 294 | <ul><li>A 3 px left rule in the owning team's colour; no box.</li><li>Task glyph, then the verb in caps 22.</li><li>Hardpoint plus "in zone" or the distance, muted.</li><li>Progress: 4 px bar.</li><li>State: caps 16 (CONTESTED pulses), plus `%` and the presence counts ▲2 ◆1.</li><li>Task cue line in 18 body.</li></ul> | collapses to the glyph and verb only, unless in or near a task | `objective_tracker.gd` + `task_cue.gd` |
| Kill feed | Top-right, right-aligned, rows 33 tall | <ul><li>`glyph killer → glyph victim` in 19 body.</li><li>A right-fading ink gradient behind each row instead of a frame.</li><li>Rows that involve you get a 3 px brass right rule and "You" in brass-hi.</li><li>The oldest row is at 55%.</li></ul> | hidden when empty (as today) | `kill_feed.gd` / `kill_feed_model.gd` |
| Toasts | Under the objective card | <ul><li>18 body ivory.</li><li>A 3 px teal right rule (status).</li></ul> | n/a | `toast_lane.gd` |
| Lane minimap | Top-left, 318×204 | <ul><li>A radial ink backdrop with 4 brass corner ticks (no frame).</li><li>Lanes: 1 px ivory 35%. Flanks: dashed 18%.</li><li>Hardpoint glyphs as on the front strip; HQ squares.</li><li>Allies: chevrons. Enemy last-known: a diamond at 60%.</li><li>You: a brass-hi arrow.</li><li>Below: "SHARDLINE · WAVE 0:18" in caps 16.</li></ul> | label 42% | `lane_minimap.gd` (wave timer added from hud.md §3.2) |
| Squad strip | Bottom-left, above the vitals | <ul><li>"SQUAD" caps, plus the command (FOLLOW) in caps 18 ivory.</li><li>Up to 6 pips of 45 px: an ally chevron, a 3 px HP line, and the slot number plus the state letter in mono 15.</li><li>`!` (in combat) is in warn colour.</li><li>Empty slots: a hollow chevron at 30%.</li></ul> | 42% | `squad_strip.gd` |
| Vitals | Bottom-left, bottom 33 | <ul><li>Portrait (93 px) inside a 114 px level ring: a brass Resonance arc on a 14% track.</li><li>Level: a cut-corner brass chip.</li><li>HP: 51 numerals, plus "/ max" 22 muted, plus a shield chip with an ivory outline.</li><li>Status chips: caps 15. Teal for buffs, warn for debuffs.</li><li>Segmented HP bar: 354×10, one segment = 50 HP (`hud_tuning`), the shield block outlined.</li><li>Lumen row: a brass-hi diamond glyph, `1,240` in 22, `+35` mono brass.</li><li>`RES 63%` muted.</li><li>`+1 SP`: a solid brass cut chip (an action).</li></ul> | RES 55% | `vitals_panel.gd` |
| Ability bar | Bottom-centre, bottom 30 | <ul><li>4 cut-corner slots of 87 px, 18 px apart: an ink 66% fill with a 1 px brass 55% rim. The ult rim is a brass gradient.</li><li>Line icons (45 px, 1.6 stroke, ivory); they replace the THRD / RLLY text.</li><li>Rank pips: brass diamonds above the slot.</li><li>Key chip below (30 px mono brass-hi).</li><li>Cooldown: a conic brass sweep on the rim plus an ink sweep inside, and seconds in 27 numerals (tenths ≤ 3 s).</li><li>Locked: the icon at 22%, a padlock, "LV 6" in caps above.</li><li>Active (wall up): a teal rim.</li><li>`+` (point available): a brass corner chip.</li><li>Med-Pack: a 66 px slot after a hairline divider, with `×2` and key `4`.</li></ul> | key chips and pips 55% | `skill_bar.gd` |
| Weapon panel | Bottom-right, 393 wide | <ul><li>Name: caps 20 ivory; "MANA" (or "AMMO") caps muted.</li><li>Value: 54 numerals plus `%`.</li><li>Pool bar: 20 segments, 8 px, ivory 85% (BURNOUT = dim grey, plus the label).</li><li>Mechanical weapons: magazine 54 / reserve 22, the tick strip, `[R]` key chip at ≤ 25%.</li><li>Mounts CORE / FRAME / CHAMBER: hairline brass-dim cells with tier diamonds; empty = a dashed hairline.</li></ul> | mounts 42% | `weapon_panel.gd` |
| Crosshair + spread | Centre | <ul><li>4 ivory lines (13×3) with a 1 px ink outline.</li><li>The gap follows the eased spread cone; while firing or casting, a faint 22% spread circle shows the cone.</li></ul> | never | `center_feedback.gd` |
| Centre dot | Exact centre | 4.5 px, brass-hi, 1 px ink outline. It stays during pause and death, as today. | never | `comfort_overlay.gd` |
| Hit markers / damage numbers | Centre / world | <ul><li>Body hits: a white X.</li><li>Headshots: a yellow `#FFD447` X plus a "!" number.</li><li>Kill: a diamond burst (unchanged).</li><li>Numbers: Chakra Petch 25.</li></ul> | n/a | `center_feedback.gd`, `world_overlay.gd`, `damage_number_model.gd` |
| World plates | World | <ul><li>Name in 16 body.</li><li>A 96×6 bar in team colour on an ink track.</li><li>Chevron or diamond glyph.</li></ul> | n/a | `world_overlay.gd` / `name_plate_model.gd` |
| Damage direction | Ring, r = 177 around the centre | <ul><li>A 75° arc, 7 px, in the damage colour, fading at both ends.</li><li>A chevron tip that points at the attacker.</li><li>A 1 px ivory 8% guide ring.</li></ul> | n/a | `comfort_overlay.gd` |
| Damage vignette | Full screen | Edge radial in the damage colour, 55%, biased to the hit side | n/a | `comfort_overlay.gd` |
| Low HP (≤ 25%) | Vitals + edges | <ul><li>HP number and bar in the damage colour, with a static 1 px red frame around the bar.</li><li>A soft red edge vignette and a 3 px static edge line. No flash.</li></ul> | n/a | `vitals_panel.gd` + `comfort_overlay.gd` |
| Ring warning (Sudden Death) | Centre-upper, top 321 | <ul><li>"OUTSIDE THE RING": Chakra Petch Bold 33, tracking .32em, damage colour.</li><li>Hairline wings on each side.</li><li>A radial ink backing.</li><li>Sub-line: "Return inside · 12 HP/s · ring closes in 0:41".</li><li>A red edge vignette.</li><li>The header phase reads SUDDEN DEATH in the damage colour.</li><li>Front strip, squad, Lumen and the objective card are hidden (hud.md §14).</li></ul> | n/a | `ring_warning.gd` |
| Comfort vignette | Full screen | Ink-tinted (`#0B1015` 78% at the edge) instead of black | n/a | `comfort_overlay.gd` |
| Net graph (debug) | Top-right, under the kill feed | <ul><li>Mono 15 muted, right-aligned.</li><li>A teal RTT sparkline.</li><li>No panel.</li></ul> | n/a | `src/ui/debug/net_graph.gd` |
| Scoreboard (Tab) | Overlay, 1470 wide, top 84 | <ul><li>Backdrop: the game blurred 4 px plus ink 60%.</li><li>Header: team kills and Uplink, then the clock and phase.</li><li>Rows (45 tall): face crop (39 px, team ring), name, BOT tag, muted hero name, LV, K/D/A, Lumen (own team brass-hi, enemy "—"), Forks (mono), status (teal ALIVE / warn RESPAWN n).</li><li>Own row: brass 10% tint plus a 3 px brass left rule.</li><li>Extra detail on Tab: front per lane with hardpoint names, squad count and the next wave, the objective, team Lumen.</li><li>Only HP and the crosshair stay on screen.</li></ul> | n/a | `scoreboard.gd` / `scoreboard_model.gd` |
| Armory | Left panel, 1170 wide, between the header and the vitals | <ul><li>Ink 94% fading to 72%.</li><li>Title in caps 30, tabs with a 2 px brass underline, Lumen top right.</li><li>Cut-corner item cards: hairline; brass rim when selected; 45% when you can't afford it; OWNED in teal; REC in brass.</li><li>Detail pane: tier rows, a teal delta line, a brass BUY button with an ↵ chip, a ghost SELL button.</li><li>The header and the vitals stay visible.</li></ul> | n/a | `armory_panel.gd` (+ `shop_icons.gd` glyphs restyled to brass line art) |
| Death / respawn | Centre overlay; the game is greyscale and 45% bright | <ul><li>"KILLED BY" caps.</li><li>Killer: face (84 px, enemy ring), plus a diamond and the name in caps 36, plus "ability · damage · assists" muted.</li><li>"RESPAWN IN": 126 brass-hi numerals.</li><li>Spawn options: cut-corner cells. Selected = brass rim. Unavailable = 45% with the reason in warn.</li><li>`+1 SP` hint with the K chip.</li><li>Only the header stays.</li></ul> | n/a | `death_screen.gd` |
| Match end banner | Upper third | <ul><li>VICTORY / DEFEAT / DRAW: 108 numerals in brass-hi, tracking .34em, with brass hairline wings.</li><li>Reason in 24 body.</li><li>"Final stats in 3 s" caps.</li><li>DEFEAT uses ivory, not brass.</li></ul> | n/a | `end_banner.gd` (then `match_end_screen.gd`) |

Shared code:
- `hud_widget.gd` gets the new helpers: scrim, cut-corner polygon, key chip, hatch, caps text with tracking, and text shadow.
- `HudPalette` keeps the team, damage and preset colours. The panel and keyline constants are retired in favour of `UiKitTokens`.
- `hud_root.gd` draws the two scrims and runs the idle-fade timer: one `modulate:a` tween per widget through `UiKit.animate` (300 ms; reduce motion skips it).

## 2a. Top-centre unit (reworked after owner feedback "work on the top mid part")

The match header and the front strip are now one designed unit. In the mockup, switch it with **TOP-MID: A · Crest / B · Tug / C · Minimal**, the phase buttons (Skirmish / Overtime / Sudden Death) and **Contested / capturing**.

- **Approved:** **D**.
- **Screenshots:**
  - `top-D-{normal,contested,suddendeath}.png` show D.
  - `top-{A,B,C}-*.png` show the reference variants.

### Variant D (APPROVED, default)

- **From A:** the clock plate (with the phase treatments below) and the framed Uplink bars, with threshold ticks, the lost region and EXPOSED.
- **From C:** the lanes. All three sit on **one line** under the plate (`N ▸ 5 chips · C ▸ 5 chips · S ▸ 5 chips`), with groups 30 apart at 1080p.
  - Chips: 12 px at 1080p, on ink halos.
  - Track: ally-coloured up to the brass-hi front needle, enemy-coloured (dimmer) beyond it.
  - Each group runs from own HQ (left) to enemy HQ (right).
- **Sudden Death:** the line is replaced by the alive pips plus the ring timer.
- **Height:** about 0–16% H, so the unit fits close to the hud.md §3.2 zone.

The sections below describe the shared rules and the three reference variants. D uses the shared rules unchanged.

Reading order for all variants: **clock + phase**, then **Uplink integrity**, then **lane fronts**. The unit spans about 0–20% H, more than hud.md §3.2's 14%. In exchange, the lanes fade to 42% when idle and the whole unit hides on Tab and on death.

### Shared rules (A, B, C)

**Uplink**
- Own team on the left (chevron, "YOU" tag); enemy on the right (diamond).
- Integrity `%` in Chakra numerals.
- The bar has segment ticks at the 75 / 50 / 25% damage thresholds.
- The darker "lost" region stays at the inner end, so a bar never appears to heal.

**EXPOSED**
- The bar gets a white diagonal hatch overlay.
- An `EXPOSED` tag (cracked-shield icon in A) appears next to the team name.
- Both pulse at 1.8 s, which counts as one animated element.
- Under reduce motion they are static.

**Lanes**
- One row each for N / C / S, with the lane letter in mono on the left.
- Every row runs from **own HQ (solid ally square, left)** to **enemy HQ (hatched square, right)**, with 5 hardpoints at fixed, aligned columns: AI, AO, MID, BO, BI.
- The track is ally-coloured up to the front and enemy-coloured (dimmer) beyond it, so each row reads as a push from your base to theirs.
- **Front marker:** a brass-hi `#EAD7A8` 2 px needle, full row height, with small notches top and bottom. It sits between the last own and the first non-own hardpoint.

**Task types**
- Same size box for all three (10 px in the mockup, 15 at 1080p), each on an ink halo so it reads over the track.
  - **Hold** = circle with a hole.
  - **Plant** = square with a core.
  - **Breach** = triangle.
- Ownership:
  - own = solid team colour with an ink inner mark;
  - enemy = enemy outline with a diagonal hatch;
  - neutral = ivory hollow.

**Contested / capturing**
- A thin ivory ring around the chip pulses (1.6 s, opacity 1 → .4).
- A 2 px progress arc in the capturing team's colour fills clockwise.
- Static under reduce motion and at effects 0%; the arc still shows the progress.

**Phases**

| Phase | Clock | Label colour | Plate accent (A) | Lanes |
|---|---|---|---|---|
| Skirmish (and Deploy / Surge / Drought) | `14:32` ivory | brass-hi `SKIRMISH`, then mono muted "SURGE I IN 2:03" | 2 px brass-hi top rule | normal |
| Capture Overtime (hud.md §12) | `OT 0:24` in warn `#D0904E` | `CAPTURE OVERTIME` warn, "2 tasks in progress" | warn top rule | in-progress chips pulse faster (0.9 s) with a warn arc; all other chips drop to 32% with a padlock |
| Sudden Death | `31:07` ivory | `SUDDEN DEATH` in damage colour, "ROUND 1 · NO RESPAWNS" | damage-colour top rule | replaced by **alive pips** `CONCORD ▲▲▲▲△ 4 · RING 0:41 → 4 m · 2 ◆◆◇◇◇ SYNDICATE` (shape plus count, not colour only) |

### Variant A · Crest (reference)

**Clock plate**
- 240×114 at 1080p, centred.
- Ink at 86% fading to 66%, with chamfered bottom corners.
- A 2 px top rule in the phase colour and brass corner ticks.
- Clock 48, phase in caps 15, next-phase line in mono 15.

**Uplink blocks**
- 340 wide, either side of the plate.
- Header: name in caps 18 team colour, the tag, and `%` in 30 numerals.
- **Framed bar**, 21 tall:
  - a 1 px brass-dim frame with an outer-end chamfer;
  - an ink well inside, and a team-colour fill with a top sheen;
  - 3 px ink segment gaps, plus brass threshold notches above the bar.

**Lane grid**
- 534 wide, rows 28 tall, under the plate.
- A dashed MID guide runs through the centre column.

A was the first recommendation. The owner kept its plate and bars, and replaced its three-row grid with C's single line, which became D.

### Variant B · Tug (reference)

- No plate. The clock floats between two slim 10 px **ribbons** whose inner ends are chamfered towards the clock.
- Lanes are **tug-of-war bars** (495×9): solid ally from the left up to the front, hatched enemy beyond it, with the hardpoint chips sitting on the bar.
- The most compact lane read (who is pushing where). Busier hatching, less premium.

### Variant C · Minimal (reference)

- Integrity as large `%` numerals over a 4 px hairline bar; `EXPOSED` as a caps tag next to the number.
- The three lanes sit side by side in **one line** (N · C · S, 12 px chips, front needle).
- Lowest height (about 0–16% H) and closest to Valorant. The lane layout is the least explicit; the full-detail lanes are on Tab.

### Implementation mapping

- `match_header.gd` draws the plate or ribbons, the bars, the threshold ticks, EXPOSED and the phase colours (it reads phase, OT and Sudden Death state).
- `front_strip.gd` draws D's single lane line: the fixed column x from the hardpoint index; track colours split at the front; chip shapes moved into a shared `hud_widget.gd` helper so the minimap and the scoreboard use the same glyphs; capture arc and pulse.
- The Sudden Death alive pips are a new mode of `front_strip.gd`, shown when `ClientWorld.sudden_death` is active.
- The pulses go through `UiKit.reduce_motion()` and `comfort_fx_intensity`.

## 3. Accessibility

- **Colour-blind:** the presets switch `--ally`, `--enemy` and `--dmg` (in the mockup: the Deuteranopia button).
  - Every team or ownership cue also has a shape (chevron / diamond, solid / hatch, task shape), a letter (squad states) or a position (the front tick).
  - Brass, teal and ivory UI colours do not change with the presets. None of them is a team cue.
- **Text scale (hud.md §16: 75–150%):**
  - All text above is set from role sizes (caps 15/16, body 18/19, numbers 22–54), so a text-scale factor multiplies them.
  - Rows reflow; kill feed names truncate, and glyphs never do.
  - Not built yet: `GameSettings` has no `text_scale` key, so it is a follow-up.
- **Reduce motion:**
  - No CONTESTED / EXPOSED pulses.
  - The idle fade and the cooldown sweep easing snap.
  - No damage-number float (the number fades in place).
  - The ring banner is static.
  - Uses `UiKit.reduce_motion()`.
- **Effects intensity (`comfort_fx_intensity`):**
  - At 0%: no damage or low-HP vignette, no hit flash, no pulses.
  - The **direction arcs, centre dot and low-HP frame stay**, because they carry information (the "Effects 0%" button).
- **Contrast:**
  - Scrims plus text shadows keep text at 4.5:1 or better against the brightest lane (lane-center-market) without panels.
  - Re-measure in-engine after implementation.
- **Input:** every key chip shows the current binding (gamepad glyphs swap in), and the Tab overlay respects the hold / toggle option.

## 4. Owner decisions (resolved 2026-10-05)

1. **Top-centre:** variant D, described in §2a.
2. **Ready ult:** a brass gradient rim, no shimmer. The animation budget stays free.
3. **Idle fade:**
   - The delay is 4 s by default.
   - It becomes a HUD setting, `[hud] idle_fade` in `user://settings.cfg` (`HudSettings`), with the options Off / 4 s / 8 s. Off means the HUD never fades.
   - The strings are new `HUD_` keys in `assets/localization/hud.csv`.
4. **Minimap:** keeps the current size, 318×204 at 1080p.
