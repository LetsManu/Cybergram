# Art Bible: Cybergram

> **Status**: Draft, revision 2 — re-authored autonomously (`modes.automation: autonomous`) by art-director with technical-artist input, following the owner's new art direction (2026-10-02)
> **Owned By**: art-director
> **Last Updated**: 2026-10-02
> **Art Director Sign-Off (AD-ART-BIBLE)**: Not yet reviewed
> **Binding sources**: `design/gdd/game-concept.md` § Canon (C1–C18), `/ideas` (owner notes)
> **Companion**: `design/ux/hud.md` (screen-space UI). This doc owns the world, characters, weapons, VFX and the art pipeline.
> **Owner direction (verbatim, 2026-10-02):** *"For the designs, take examples from Apex Legends or the Valorant characters, make a mix of them, and throw in a bit of Cyberpunk 2077."* Earlier brief, still binding: *"Anime/Cartoon, Futuristic Fantasy."*

This bible follows the nine-section template order (§1–§9) and adds project-specific
sections (§10–§14) that the brief requires: Godot technical art direction, asset standards,
the vertical-slice asset list, the placeholder strategy and the reference board.
Decisions are made, not offered; open items that need the owner are in §15.

**What changed in revision 2:** the touchstones are now **Valorant** (shape, shading,
readability), **Apex Legends** (gear, personality, weapons, frontier tone) and **Cyberpunk 2077**
(neon accent, chrome cyberware, holograms, megastructure density, glitch), fused with our own
fantasy layer, **mana-tech**. Overwatch and Genshin Impact are retired as touchstones. Every
gameplay-readability rule from revision 1 (team colours, colour-blind cues, value keys, mana colour
rule, tier reads, telegraph rules, budgets) is kept unchanged unless a line says otherwise.

**We take inspiration, not copies.** No character, logo, emblem, weapon model, UI layout or
typeface from any reference is reproduced. §14 sets the originality test every design must pass.

---

## 1. Visual Identity Statement

**The one rule:** *"Clean heroes, lived-in gear, neon on the edges: every pixel that can kill
you has a team colour and a shape; everything else steps back."*

When any visual choice is ambiguous, pick the option that makes **team, threat and
progress** easier to read at 30 m through a first-person camera. Beauty is spent on
heroes, guns and the Uplinks; the playfield is calm by comparison, and the city's neon
lives on the skyline and in the HQs, not on the lane floor.

**The fusion in one line — mana-tech:** Halcyra's magic is real and its tech is street-real.
Mana crystals are wired into chrome; spells are drawn as holographic runes; the Uplink is a
neon mana spire. The fantasy layer is *mana*; the tech layer is *chrome, cable and hologram*;
the two always appear bolted together, never as separate worlds.

### 1.1 Visual Pillars

| # | Visual pillar | Design test | Serves game pillar |
| --- | --- | --- | --- |
| V1 | **Read the Fight First** | If an effect, prop, sign or texture competes with an enemy silhouette for attention, it gets darker, less saturated or smaller. Characters always out-contrast the environment behind them. Competitive readability beats every reference. | P2 Shooter Hands |
| V2 | **The Front Is Painted on the World** | Ownership of every hardpoint is visible in-world (banners, floor rings, Barricades, light colour) and matches the HUD. If a state exists only on the HUD, add a world tell. Any team-coloured light in a lane is driven by ownership (`team_tint`), never baked. | P1 The Front Is the Story |
| V3 | **Power You Can See** | Every purchased upgrade changes a mesh, a glow or a muzzle effect. If two tiers of an upgrade look the same at 20 m, the higher tier gets a bigger silhouette change, not just more glow. | P4 Power You Can See |
| V4 | **Squads Are Small and Loyal** | Wardlings are knee-to-waist height, simple and cute, with a team-coloured core. If a Wardling ever reads as a hero at a glance, cut its height or detail. Wardlings carry no neon trim beyond core and markings. | P3 Your Squad at Your Heels |
| V5 | **Mana Blooms, Machines Shine** | Mana is emissive, additive, rounded and **blooms**. Mechanical is opaque, sparky, angular; it may carry neon trim lights, but they stay **under the bloom threshold** and never bloom. Never mix the two vocabularies on one effect. | C16 resource types |
| V6 | **Neon Is the Accent, Never the Signal** | Neon, chrome and holograms season the world; they never imitate a gameplay signal. If a decorative light could be mistaken for a team colour, telegraph or pickup in a greyscale or CVD screenshot, it is recoloured, dimmed or moved above 4 m. | P2, V1 |
| V7 | **Every Scratch Has a Story** | Wear, patches, stickers, tally marks and repairs are placed on purpose, each one tied to a hero's backstory or kit. If a detail tells no story and does not read at ≤ 10 m, cut it. | P2 (hero identity) |

---

## 2. Style Target & Mood

### 2.1 Style Target

**Stylised mana-tech: Valorant-shaped, Apex-weathered, Cyberpunk-lit, anime at heart.**
The target is stylised, never realistic. Characters are built and lit like Valorant agents
(clean, graphic, semi-cel), dressed in gear with Apex-grade tactility and personality, and
accented with Cyberpunk 2077 chrome, neon trim and holograms. Anime/cartoon expression is
kept: large readable eyes, graphic hair shapes, exaggerated poses.

**Where the line sits (binding):**

| Layer | Source | Rule |
| --- | --- | --- |
| **Proportion & silhouette** | Valorant + Apex legend boldness | ~7.5 heads tall (revision 1 was 7), slightly enlarged hands, feet and weapons; one silhouette hook per hero (§5.1). Anime faces: large eyes, simplified nose and mouth, graphic hair masses. |
| **Shading** | Valorant semi-cel | Two hard light bands plus a **narrow soft terminator** (2–6% of the ramp), a tinted shadow tone (never black), a lit-side rim light. No PBR skin, no subsurface scattering, no realistic specular, no ray-traced or screen-space reflections. |
| **Surface (texture layer)** | Apex + Cyberpunk 2077 | Hand-painted wear, stencils, decals, stitching, panel lines and cyberware seams **painted into albedo**, not rendered by physically based roughness. Chrome is a stylised 3-band matcap, not a reflection. |
| **Detail density** | Apex + Cyberpunk 2077, capped by Valorant | Dense at eye level and on silhouette edges within 10 m; collapses to flat colour blocks by 20 m (mip-friendly painting, §3.1 detail zones). |
| **Light & signal** | Cyberpunk 2077 neon + our mana | Emissive neon trims, holograms and signage; **only mana and gameplay signals bloom** (§4.6, §10.3). |
| **Outline** | Our anime brief | Thin inked outline on characters, Wardlings, weapons and interactive props (§10.2). |

**Never:** photoreal rendering, photogrammetry textures, film grain, motion blur, realistic gore,
body-horror cyberware, real-world brands or weapon replicas, night-time darkness in gameplay.

### 2.2 Touchstones — take X / avoid Y

**Valorant** — the *shape and readability* layer.

| Take | Avoid |
| --- | --- |
| Clean stylised characters: simple forms, few large material zones per body (3–5) | Its near-realistic facial proportions; our faces are more anime (bigger eyes, simpler features) |
| Readable silhouettes that survive as solid shapes; one bold accessory per agent | Copying any agent's archetype + silhouette pairing (e.g. a specific hooded-coat-and-mask combination) |
| Flat-ish shading with crisp shape language: hard light bands, minimal gradients | Its sparse, almost empty playfield walls; our lanes may be denser, but only above head height |
| Strong per-agent colour identity (one signature colour carried by cloth, hair or gear) | Signature colours inside the team hue bands (§4.1) |
| Ability VFX as clear geometric telegraphs: walls, domes, rings, lines with crisp edges and defined fill | Its exact ability shapes, icon designs and colour assignments |
| Competitive readability first: enemy highlight options, low clutter, calm environment colour blocks | Treating realism as "neutral"; muted greys make our anime cast look flat |

**Apex Legends** — the *gear, personality and weapon* layer.

| Take | Avoid |
| --- | --- |
| Grounded, tactile gear: straps, buckles, pouches, padded collars, field repairs, worn paint on edges | Its PBR material response and grime levels; our wear is painted, graphic and sparse |
| Personality and backstory written into the kit: trinkets, patches, tally marks, home-made modifications | Lore told only through text; if the backstory is not on the model, it does not count (V7) |
| Chunky, readable weapons: oversized receivers, clear magazines and grips, distinct first-person silhouettes | Real-world firearm replicas or recognisable real gun silhouettes; every gun is an invented mana-tech design |
| The sci-fi frontier feel: rugged, lived-in, repaired tech on a dangerous edge of the world | Camouflage patterns and busy multicolour suits that break silhouettes and fight the team read |
| Bold legend silhouettes, each with one exaggerated element (pack, shoulder, collar, prosthetic) | Its specific legend designs, emblems and squad iconography |

**Cyberpunk 2077** — the *neon, chrome and city* accent. A bit, not a base.

| Take | Avoid |
| --- | --- |
| A neon-on-dark accent palette: thin glowing trims against dark material, signage on dark facades | Neon everywhere; neon on the lane floor or at body height in lanes (V6) |
| Chrome and cyberware augmentations: prosthetic limbs, ports, implants, chrome plates, as clean graphic shapes | Body-horror, exposed gore, invasive implants; cyberware here is clean, designed and readable |
| Holographic UI and signage: scanline holograms, projected labels, rune rings | Dense holo-adverts at eye level that look like pickups or telegraphs |
| Urban megastructure density in the **HQ and Armory** set pieces and the skyline | Its night-time gameplay darkness; our matches are lit for readability (§2.3) |
| Glitch and scanline effects for **Hex** and the **Cybergram signal** itself | Glitch used as general decoration or on screen-space HUD outside Hex/Scramble states |
| Corporate-clean vs street-tech contrast as a faction language (§3.2) | Its typefaces, corporate logos, gang emblems and advertising content |

**Supporting touchstones** (kept from revision 1, minor):

| Reference | Take | Avoid |
| --- | --- | --- |
| **Arcane** | Crystal-in-machine design language (the root of mana-tech and our weapon sockets) | Gritty texture noise and heavy grading |
| **Hi-Fi Rush / Guilty Gear Strive** | Proof that real-time cel shading with inverted-hull outlines holds up in motion | 2D-faked camera tricks that don't work with a free FPS camera |
| **Battlefield Breakthrough** | Front line visible in the world (sector dressing) | Military realism |

### 2.3 Mood per Game State

The city lights up as the war escalates: Skirmish is sunlit, Surge II reaches blue hour and the
skyline neon switches on, Drought dims it. **Exposure floor:** character key + fill lighting never
drops below 70% of the Skirmish value in any phase, so the darker sky never darkens the fight (V1).

| State | Emotional target | Lighting character | Descriptors | Energy |
| --- | --- | --- | --- | --- |
| **Deploy (0:00–1:00)** | Anticipation, "gear up" | Golden-hour key light; HQ interiors lit by Foundry conveyor lamps, Armory holo walls and neon gun-shop signage | busy, bright, mechanical, hopeful | Medium |
| **Skirmish (1:00–15:00)** | Clear, fast, competitive | Clean late-afternoon sky, high sun, crisp shadows; skyline neon off or faint; Leyfall mana-sea glows violet below | clear, open, airy, legible | Medium-high |
| **Surge I** | Escalation | Sunset (key light −400 K, sky saturation +10%); skyline neon flickers on in distant towers; Leyfall glow intensifies; lightning in distant cloud-shards | charged, louder, hotter | High |
| **Surge II** | Peak escalation | Blue hour: sky dark indigo, skyline neon fully on, holo-billboards awake on far shards; characters stay at the exposure floor with a stronger rim light | electric, urban, intense | High |
| **Mana Drought (45:00+)** | Scarcity, desperation | Leyfall dims, sky desaturates 20%, skyline neon browns out block by block, Uplink beams flicker with signal glitch, ambient particles thin out | thin, tense, fading | High |
| **Uplink Exposed** (local) | Siege, danger | Spire shield shell gone, warning strobes in owner colour around the HQ, beam turns jagged and glitches | alarmed, broken, urgent | Very high |
| **Sudden Death** | Arena duel | Mid Plaza isolated by a violet Leyfall ring wall; outside the ring is desaturated 60% and all city neon is off | stark, gladiatorial, focused | Maximum |
| **Victory / Defeat** | Release | Victory: the enemy Uplink goes dark, its neon dies tower by tower, your beam flares white-gold. Defeat: your Uplink collapses, your HQ neon cuts out, the world desaturates, mana drains from your guns | triumphant / hollow | Spike → calm |
| **Menus / Lobby** | Identity, collection | Hero turntables in a hangar on a city-shard: dark backdrop, neon faction backlight, holo name plates, studio key light | stylish, premium, "legend reveal" | Low |

Each in-match state must be identifiable from a single screenshot without HUD (QA test).

---

## 3. Shape Language

### 3.1 Global Grammar

- **Circles / soft curves = mana, support, safety** (Uplink rings, holo rune rings, Mender Wardlings, heal effects, Hold zones).
- **Squares / blocks = mechanical, defence, structure** (Barricades, Brannoc, Supply Caches, Plant cradles, chip racks).
- **Triangles / spikes = threat, offence, breach** (Strikers, damage abilities, Breach generators, enemy telegraph edges).
- **Mana-tech joins (new):** wherever mana meets machine, the join is shown: a crystal held in a chrome claw, a rune ring projected from a chrome emitter, a cable feeding a crystal socket. Mana never floats free of a mechanism except Liora's halo and Vesper's spindles, which are held by visible hard-light tethers.
- **Cyberware grammar (new):** chrome parts are bevelled cylinders and plates with clean panel seams; each chrome part carries **at most one** neon trim line, drawn as a single continuous stroke following a seam (never dotted, never more than one per part).
- Characters use **one dominant shape + one accent**; the environment uses **large calm shapes with detail only at eye level** and density on the skyline.
- Proportions: heroes are ~7.5 heads tall (stylised-heroic, slightly enlarged hands, feet and weapons); Wardlings 2–3 heads tall (chibi).

**Detail zones (applies to every hero, weapon and prop):**

| Zone | Read distance | Share of surface | Content |
| --- | --- | --- | --- |
| Silhouette | 40 m + | — | The hook and the overall shape; must pass the shadow test (§5.1) |
| Primary blocks | 20 m | ~70% of surface as calm "rest areas" | 3–5 flat material zones: signature colour, faction trim, neutral, chrome, skin |
| Secondary shapes | 10–20 m | ~20% | Straps, pouches, plates, cyberware, neon trims |
| Fine detail | ≤ 10 m | ~10% | Stencils, scratches, stitching, stickers, tally marks; painted so it vanishes into the block colour at mip 2 |

### 3.2 Per Faction (cosmetic sides, C-Faction rule)

The two factions are **corporate-clean mana guild** vs **street-tech salvage syndicate**.

| | **Azure Concord** — the mana guild | **Ember Syndicate** — the street-tech syndicate |
| --- | --- | --- |
| Fiction look | A civic mana utility run like a premium corporation: spotless spire-cities, uniforms, branded equipment, everything licensed and serial-numbered | A federation of salvage crews from the lower shards: rebuilt war-tech, hand-painted crew tags, everything repaired twice |
| Core shape | Circle and hexagon lattices, long tapering verticals, arches | Chevrons, trapezoids, notched teeth, stacked horizontals |
| Construction | Seamless shells, floating parts held by hard-light, glyph inlays, flush panel seams | Riveted plates, exposed pistons, welded seams, furnace grilles, zip-tied cables, taped grips |
| Material set | Porcelain-white composite, brushed gold, **cool polished chrome**, blue glass, holo-glyph emissive | Blackened iron, brass, **warm scuffed chrome**, orange-hot furnace glow, hazard paint, sprayed stencils |
| Neon character | Thin, precise, white-core trims in panel seams; holograms crisp and stable | Neon tubing bent by hand, slightly uneven, with exposed transformer boxes; holograms with a mild flicker |
| Wear | Minimal: polished edges, a few service decals | Heavy but graphic: chipped paint on edges, crew tags, patched plates |
| Value key | **Light** (high-value surfaces, dark accents) | **Dark** (low-value surfaces, hot accents) |
| Glyph motif | Six-point "ring-and-ray" glyph | Three-tooth "cog-and-flame" glyph |

The value key is the most important colour-blind backup in the game: Concord things are
light-bodied, Syndicate things are dark-bodied, at every scale (heroes' faction trims,
Wardling shells, Barricades, banners, HQs). Neon and chrome never override it: a Syndicate
Barricade with neon tubing is still dark-bodied.

### 3.3 Per Role

| Role | Dominant shape | Silhouette rule | Cyberware / mana-tech accent |
| --- | --- | --- | --- |
| Minionmancer (Vesper) | Inverted triangle + orbiting circles | Floating elements around the body | Chrome thimble fingertips that emit threads; spine-mounted halo rig |
| Infiltrator (Sable) | Thin diagonal | Lowest, narrowest profile; trailing cloth | Optic implant behind a slit visor; chrome calf struts |
| Trapper (Juniper) | Square on top of a thin base | Top-heavy pack silhouette | Chrome multi-tool prosthetic left forearm |
| Soldier (Ryker) | Upright V-taper | The "default soldier" every other hero contrasts against | Chrome stim-port forearm; visor bar |
| Tank (Brannoc) | Big square | Widest and tallest; shield arm breaks symmetry | Mana furnace-heart in the chest behind a grille |
| Healer (Liora) | Circle | Halo ring; flowing curved hem | Holo-lens monocle; mana IV lines on the forearms |
| Hacker (Hex) | Hunched square + antennae | Oversized hood/headset; floating rectangular screens | Neural jacks behind the ears; wrist decks projecting holo panels |

---

## 4. Color System

### 4.1 Primary Palette

| Token | Hex (sRGB) | Meaning |
| --- | --- | --- |
| `azure_core` | `#2E86FF` | Concord team colour (rims, cores, banners, territory, Concord-owned neon) |
| `azure_light` | `#EAF3FF` | Concord body value (porcelain) |
| `concord_gold` | `#E8B547` | Concord accent trim (never used as a signal colour) |
| `ember_core` | `#FF5A1F` | Syndicate team colour; orange-red, not pure red, to keep luminance for protanopia |
| `ember_dark` | `#1E1A1C` | Syndicate body value (blackened iron) |
| `leyfall_violet` | `#8E5CFF` | Raw mana / the Leyfall / neutral (unowned Mid, Sudden Death ring) |
| `halcyra_stone` | `#B9B2A6` | Neutral environment base (ancient crystal ruins, plazas) |
| `chrome_cool` | `#C9D4E2` (matcap mid band) | Concord chrome, neutral cyberware |
| `chrome_warm` | `#BFA68A` (matcap mid band) | Syndicate chrome (brass-tinted, scuffed) |
| `night_ink` | `#141726` | The "dark" of neon-on-dark: facades, sky at blue hour, holo backplates; never a character body colour |

**Team hue bands (exclusion zones, HSV hue):** azure **195°–235°**, ember **0°–25°**. No
decorative colour, crystal family hue, hero signature colour (at > 40% saturation) or city neon may
sit in these bands.

**Mana colour rule:** raw mana is white-core violet (`leyfall_violet`). Once broadcast by
an Uplink (the Cybergram), mana takes the **team colour on its outer edge** and keeps a
**white-hot core**. So every mana projectile, beam and shield is "white core + team rim".
Crystal families (§7) may tint the core band, never the rim. Holographic runes drawn by mana
follow the same rule (white core lines, team-coloured outer glow).

### 4.2 Semantic Colours (non-team)

| Token | Hex | Use | Never use for |
| --- | --- | --- | --- |
| `heal_verdant` | `#4CE38A` | Healing, Mender, heal numbers | Team identity, decoration |
| `crit_solar` | `#FFD447` | Weak-spot hits, critical hit markers | Ally/enemy, neon signage |
| `aether_violet` | `#B07CFF` | Skill points, Resonance/level | Neutral ownership (that's `leyfall_violet`, desaturated) |
| `warning_white` | `#FFFFFF` + black stroke | Danger telegraph cores, low-HP pulses | Decoration |
| `lumen_gold` | `#FFC93C` | Money pickups and HUD | Neon signage |

### 4.3 Team Colour Policy

- **Default = absolute faction colours.** Concord is blue, Syndicate is orange-red, for
  everyone. This keeps the map, VO ("they took blue North Outer") and world dressing
  consistent for both teams (V2).
- **Relative mode (option):** ally = `azure_core`, enemy = `ember_core` regardless of side.
  Team colour is a single global shader uniform (`team_tint`) per team, so relative mode
  is a per-client uniform swap; faction *shapes and value keys* stay true, so faction
  identity survives. Team-coloured neon trims on heroes swap with it (they use `team_tint`).
- **Enemy highlight colour (option):** enemies' outline may be overridden to Yellow
  `#FFE600` or Magenta `#FF2BD6` (Valorant-style) for colour-vision deficiency.

### 4.4 Colour-Blind-Safe Secondary Cues (mandatory)

Team hue must never be the only cue. Every team-coloured signal carries at least two of:

| Cue | Ally / Concord | Enemy / Syndicate |
| --- | --- | --- |
| Value key (§3.2) | Light bodies | Dark bodies |
| Outline | Thin (1.5 px @1080p), soft | Thick (2.5 px), with hard edge |
| Nameplate glyph | Chevron ▲ over head, visible through walls | Diamond ◆ over head, only in line of sight |
| Ownership pattern (banners, map, floor rings) | Solid fill + ring glyph | Diagonal hatch + tooth glyph |
| Telegraph border | Smooth line | Serrated outward ticks |
| Audio | Team-specific ability VO / chime sets | Distinct enemy VO line per ability |

Validated presets: Deuteranopia, Protanopia, Tritanopia shift `ember_core` toward
`#FFB000` (protan/deutan) or `#FF3B7A` (tritan) and `azure_core` toward `#2B6CFF`/`#00C2D1`;
all presets must hold ≥ 3:1 luminance contrast between the two team colours and pass a
Coblis/Color Oracle simulation on the five test screenshots listed in §11 item 6.
City neon reroutes with the presets (§4.6 rule 5).

### 4.5 Area Temperature

- Concord half of Halcyra: cool key light (6500 K), white stone, blue shadows.
- Syndicate half: warm key light (4800 K), dark metal, plum shadows.
- Mid row and Mid Plaza: neutral (5600 K), violet Leyfall bounce from below.
- Shadow tones are always tinted (blue-violet), never neutral grey or black.
- Neon spill onto the playfield is faked by small unshadowed coloured fill zones only above 4 m
  and on facades, never on lane floors (§4.6).

### 4.6 Neon Accent Policy (new)

Neon is the Cyberpunk 2077 seasoning. It must never break team readability (V6).

**Three emission tiers** (HDR emission energy; glow threshold is 1.1, §10.3):

| Tier | Energy | Blooms? | Who may use it |
| --- | --- | --- | --- |
| **Signal** | 1.2–4.0 | Yes | Mana (projectiles, beams, shields, crystals Tier II+), team telegraphs, Uplink beam, Wardling cores, ownership emissives on hardpoints |
| **Accent** | 0.4–1.0 | **No** | Neon trims on heroes and weapons, cyberware lights, chip-rack LEDs, holo labels, in-lane signage |
| **Set-piece** | up to 1.5 | Limited | HQ interiors, Armory, Foundry, the skyline beyond the playable edge, menus; never inside a lane's playable volume |

**Rules:**

1. **Team-coloured neon only where ownership is true.** On heroes, neon trims use `team_tint`
   (they are part of the 15–25% faction trim, §5.1), so they *reinforce* the team read. In the HQ,
   neon may use the owning team's colour because HQ ownership never changes. In lanes, any
   team-coloured light must be an ownership emissive that swaps on capture (V2); no baked team neon.
2. **City neon** (signage, facades, skyline) uses only two hues outside the team bands:
   `sign_teal` `#34D8C4` (≈172°) and `sign_pink` `#E255B5` (≈318°), plus `holo_white` `#E6F7FF`
   for holograms. Never amber/yellow (pickup and crit colours) or green (heal).
3. **Placement:** in lanes, city neon sits **above 4 m** or on facades behind the playable edge,
   never on the floor, never at body height (0.5–2.2 m), never within 3 m of a hardpoint task object.
4. **Coverage cap:** in the five readability screenshots (§11), Accent + city neon pixels cover
   **≤ 4%** of the frame, and pixels above the glow threshold cover **≤ 6%** (Signal tier included).
5. **Preset reroute:** `sign_pink` is a global uniform. When the Magenta enemy highlight or the
   Tritanopia preset (which pushes `ember_core` to pink) is active, `sign_pink` swaps to `sign_teal`
   so no decorative pink competes with an enemy signal.
6. **Mechanical neon never blooms** (V5); a Mechanical hero's glowing trims are Accent tier.
7. **Drought and Sudden Death** switch city neon off progressively (§2.3), which is itself a world tell.

### 4.7 Hero Signature Colours (new)

Per-agent colour identity, Valorant-style. Signature colours live mostly in **non-emissive** cloth,
hair and paint, cover **≤ 30%** of the surface, and stay outside the team bands at > 40% saturation.
Team trim covers 15–25%; the rest is neutral (blacks, greys, chrome, skin).

| Hero | Signature colour | Secondary | Note |
| --- | --- | --- | --- |
| Vesper Loom | Plum `#5B2A6E` | Spool gold `#D9A441` (thread accents) | Gold also marks her Elites |
| Sable | Ink charcoal `#22252B` | Jade `#3FBF8F` (lining, scarf underside) | Darkest hero; lining flashes jade in motion |
| Juniper Quill | Mustard `#D9A21B` | Olive `#6B7B3A` | Pack and canisters carry the mustard |
| Ryker Vance | Field olive `#4E5A45` | Bone `#E3DCC8` | The most neutral, by design (he is the baseline) |
| Brannoc | Oxide teal `#2F6E6A` | Soot `#2A2826` | Teal paint on plate, worn to bare iron on edges |
| Liora Vale | Ivory `#F2EDE4` | Sage `#8DBF9A` | Sage is desaturated so it never reads as `heal_verdant` |
| Hex | Acid lime `#B6F23A` | Black hoodie `#18181C` | Lime is the only lime in the cast |

---

## 5. Character Design Direction

### 5.1 Telling Things Apart

- **Hero vs Wardling:** heroes ≥ 1.70 m (Sable is the smallest at 1.70 m), Wardlings ≤ 1.1 m (Sentinels 1.4 m, but static and tripod-shaped). Wardlings never carry hero-shaped guns.
- **Ally vs enemy:** value key + outline weight + nameplate glyph (§4.4). Faction trims, **including team-coloured neon trims**, are 15–25% of a hero's surface: enough to read, not enough to change the hero.
- **Which hero:** each hero has one **silhouette hook** that survives at 40 m (64 px tall at 1080p, 90° FOV) and is recognisable as a solid black shape (QA "shadow test"). Signature colour (§4.7) is the second read; it never replaces the hook.
- **Personality in the kit (Apex rule):** every hero carries at least **three story props** (a trinket, a repair, a mark) that tie to their backstory and are readable at ≤ 10 m. Story props live in the secondary and fine detail zones (§3.1) and never add to the silhouette except the hook.
- **Expression:** anime faces with large readable eyes, but faces are the least important read in FPS; pose and props carry personality. Idle and emote poses exaggerate the silhouette hook.
- **Cyberware rule:** each hero has **one hero cyberware piece** (§3.3), designed as clean chrome with one neon trim line. Cyberware is never gory, never exposes muscle or bone, and never sits where it would be mistaken for a mount socket or a gadget.

### 5.2 Hero Silhouettes

**Vesper Loom — Minionmancer (Mana).** A tall, slender former Foundry choreographer who used
to stage the parades of new Wardlings off the conveyor, and still dresses for the show: a long
asymmetric plum performer's coat split into ribbon-tails at the back, its lining stitched with
dozens of tiny brass name-tags, one for every Wardling she has rebuilt. The hook is the **floating
"Loom halo"**: four chrome spindle-arms hovering behind the shoulders in a semicircle, each tipped
with a violet mana crystal in a claw socket, mounted on a slim spine rig and linked by thin glowing
threads to her **chrome thimble fingertips** (her cyberware: emitter needles that spin mana into
thread). The threads pull taut when she commands. Inverted-triangle torso (high wide collar,
narrow corseted waist), long legs, a sharp bob with one long gold-wrapped braid. Her gun, the
*Threadcaster*, is a long-barrelled semi-auto mana carbine with a chrome receiver and a spindle
drum as its conduit. Her ultimate makes the halo flare open to eight spindles, so the threat is
visible from across a lane before the Wardlings change.

**Sable — Infiltrator (Mana).** The smallest hero (1.70 m), an undershard courier who smuggled
cargo through faction Barricades long before she learned to fight; always in a forward-leaning,
crouch-ready pose. The hook is a **long split scarf** whose two tails trail 1.5 m behind her, plus
a single swept-back hood horn on one side, so the silhouette is a thin diagonal with a streamer.
The scarf is phase-weave cloth patched with scraps cut from both factions' banners (her trophies).
A matte half-mask with a single **slit visor** hides an optic implant; the slit glows in her team
colour. Her cyberware is a pair of **chrome calf struts** with a jade-lit hinge at the ankle, which
explains the uncanny crouch and the silent step. Charcoal armour is minimal and matte, lined in
jade that flashes when she moves. Weapon: the *Whisperfang*, a compact twin-grip mana SMG with a
tanto-blade underslung and a courier's tally of notches on the grip. While phased (Barricade
passage), her body becomes a dark glass silhouette with only the scarf tails and visor slit
glowing in her team colour, so stealth is never fully invisible to an attentive enemy.

**Juniper Quill — Trapper (Mechanical).** A pump-hall kid from the Leyfall Pumpworks who
builds traps out of whatever the docks throw away. A medium build carrying a **huge square
tool-pack** taller than her head, built from a salvaged pump housing in mustard paint covered in
stickers, hand-written labels and a "do not touch" stencil, with a cable spool wheel on one side
and a folded mine-launcher arm on the other: a top-heavy box on slim legs. Her cyberware is a
**chrome multi-tool prosthetic left forearm** (she lost the arm to a pump; the replacement is
clearly home-made, with a fold-out pliers finger and a little neon trim she added "for luck").
Brass goggles with a cracked holo-lens pushed up into a messy bun stuck with quill-darts (the
tripwire anchors). Utility belt of trap canisters, each with a stripe and hand-painted letter for
its type. Weapon: the *Tackhammer*, a lever-action rail-tack rifle with a box magazine and a
visible spool feeding tripwire line along the frame.

**Ryker Vance — Soldier (Mechanical).** The baseline every other hero is measured against: a
laconic ex-sergeant of the Shardline Guard who has fought on both ends of every lane, in
upright V-taper light combat armour in field olive and bone. The hook is a **single oversized left
pauldron** with a rising antenna fin, its paint chipped to bare metal and covered in a strip of
kill-tally tape, plus a closed helmet with a horizontal **visor bar** that glows in his team colour.
A grenade bandolier crosses the chest diagonally. His cyberware is a **chrome right forearm with a
stim port**: Combat Stim visibly injects through it, and the port's neon ring brightens while the
stim is active. Weapon: the *Breakline AR-7*, a bulky full-auto rifle with a top rail, a scuffed
unit serial and a big receiver that carries the chip rack; it is the most "classic gun" in the
cast so new players have an anchor.

**Brannoc — Tank (Mechanical).** 2.2 m, the widest silhouette in the game: a gentle former
shard-miner who survived a mine collapse because the crew rebuilt him around a mana furnace. A
block of oxide-teal plate armour, worn to bare iron on every edge, with a small head sunk between
huge square shoulders. The hook is the **right arm shield generator**, a slab-shaped forearm
emitter that unfolds into the shield wall, making him visibly asymmetric; small charms and tags
from people he has shielded hang from its rim. His cyberware is the **furnace-heart**: a mana
reactor behind a chest grille that glows in his team colour and breathes heat through a back vent
in time with his footsteps. Weapon: the *Ironmaw*, a short, fat pump scattergun with a jaw-shaped
muzzle, held low at the hip. He walks with a heavy, grounded gait so his tankiness reads in motion too.

**Liora Vale — Healer (Mana).** A Concord-trained trauma medic who walked out of the spire
hospitals to run a free clinic on the lower shards, and dresses like both: built from circles, an
ivory round-hemmed long coat with sage panels, very long hair in a loose ribbon, soft rounded armour
with field-patched elbows. The hook is a **halo ring** orbiting her back at shoulder height,
carrying two docked Med-Pack drones like lantern beads; when she throws one, the ring visibly has a
gap until it recharges. Her cyberware is a **holo-lens monocle** over the right eye that projects
small vital-sign readouts, plus mana IV lines running along both forearms into the weapon grip
(she heals with the same mana she fights with). Her medical emblem is an original **leaf-in-ring**
glyph; the cast never uses the red cross or any real medical emblem. Weapon: the *Halo Repeater*,
a full-auto mana rifle with a glass bulb conduit that fires slow, glowing bolts.

**Hex — Hacker (Mana).** A chaotic gremlin of the signal who live-streams their own break-ins:
a slouched, hunched figure in an oversized black hoodie with acid-lime drawstrings and patches, and a
**cat-ear headset** whose antennae stick up past the hood, giving a horned square silhouette.
Cyberware: **neural jacks** behind both ears, cabled into the headset, and chrome wrist decks that
project two to three floating **holo-panels** orbiting the wrists; the panels show scrolling code
and an original cartoon "face" glyph that reacts to hacks, and flicker with glitch scanlines (team
colour, chromatic offset). Shorts and oversized lime-soled sneakers: the cast's most cartoonish
proportions. Weapon: the *Glitchcaster*, a chunky mana pistol-SMG whose barrel is a stack of offset
hex rings that visibly misalign when firing, plastered with stickers. Hex is the only hero whose
own VFX use the glitch vocabulary (§8.1).

### 5.3 Wardlings (C15)

**Base form:** a small hover-biped construct ~0.9 m tall, designed as a clean Valorant-style
toy-soldier with Apex-style stencilling: a rounded shell torso, stubby arms, two short legs that
hover-skip, a single **holo-LED visor eye**, and a **mana core** in the chest that is visible from
front and back (the core is the team-colour signal; it pulses when the Wardling takes damage). The
core sits in a chrome cage: the smallest mana-tech join in the game. Faction skin: Concord =
white porcelain shell + gold trim + a printed serial; Syndicate = black iron shell + brass rivets +
a sprayed crew tag. No neon trims beyond the core, the eye and the class markings (V4). Each bound
Wardling shows a small holographic slot-number glyph (1–7; Vesper carries up to 7) above it to its
owner only, matching the HUD squad strip.

| Variant | Shape hook | Height | Behaviour read |
| --- | --- | --- | --- |
| **Picket** (free default) | Round shell, single crystal eye, short back fin | 0.9 m | Neutral idle bob |
| **Shieldling** | Large slab shield on the front arm, hunched square stance | 0.9 m, 1.2× wider | Shield faces the threat |
| **Striker** | Forward lean, long barrel arm, triangular head fin | 1.0 m | Lunging posture |
| **Seeker** | Antenna crest + sweeping scan-light cone (white, 12 m) | 0.95 m | Head turns constantly; scan sweep every 0.5 s |
| **Mender** | Round body, floating halo, green tether beam to its heal target | 0.85 m | Floats higher, soft bob |
| **Sapper** | Backpack charge + drill arm | 0.9 m | Drill spins up near Barricades/Generators |
| **Sentinel** (Garrison only) | Tripod turret-construct anchored to the hardpoint plinth | 1.4 m | Never moves; rotates head only |

Variant names and traits are owned by `wardlings-and-economy.md` §6; silhouettes above match its
"silhouette" column. Squad upgrades have tells per its §7 (plating rim / full plating for
Reinforced Cores, brighter muzzle for Amplifier Emitters, owner-colour trail for Harmonic Tether,
small ground shield in Hold for Bulwark Protocol).

**Tiers (Surge I/II, C15):** each tier adds silhouette, not just glow.

| Tier | Additions | Core | Scale |
| --- | --- | --- | --- |
| I | Bare shell, 1 tier pip on the back fin | Single core, soft pulse | 1.0 |
| II | Shoulder armour plates + head crest, 2 pips | Core ringed by a bright band | 1.08 |
| III | Crown of three crystal shards in chrome claws over the head + short trailing mana ribbon, 3 pips | Core white-hot with team rim, faint bloom | 1.15 |

A Surge upgrades every living Wardling in place with a 3 s invulnerable morph and a crystal-bloom VFX (`match-flow-and-map.md` §3.1).

### 5.4 Three Kinds of Wardling — Personal, Vanguard, Garrison

C15 (revised 2026-10-02) puts up to 108 constructs on the map (Canon C1 budget ≤ 110): personal squads (≤ 54, incl. 2 Vespers),
Garrisons (≤ 30) and ownerless **Vanguard waves** (4 per lane per team every 60 s, ≤ 24 live).
All three are team-coloured; their *ownership class* must read as fast as their team.

| Class | Shell & markings | Core | Head marker | Movement read |
| --- | --- | --- | --- | --- |
| **Personal squad** | Faction shell + a **bright owner band** (a ribbon-sash in team colour around the torso); for the owner only, a 1 px owner-accent outline and 0.6 m ground ring (`wardlings-and-economy.md` §8) | Team colour, soft pulse | To the owner: slot number 1–7. To allies: owner's hero icon (tiny). To enemies: nothing extra | Loose cluster near a hero, hover-skip |
| **Vanguard** | Faction shell with **no sash**; instead a **pennant pole rising 0.4 m above the back fin** (narrow flag, team colour with the faction glyph; tier pips stay on the fin below it) and a single shoulder stripe | Team colour, **steady** (no pulse) | Lane-letter glyph (N / C / S) to allies only | **Marching formation**: a 2×2 block walking in step along the lane, pennants aligned — the formation itself is the read |
| **Garrison Sentinel** | Tripod turret, no legs, anchored | Team colour, slow rotate | None | Static on hardpoint sockets |

- The **pennant** is the Vanguard's silhouette hook: no personal Wardling or Sentinel ever
  carries one, so "flag on back = wave" holds at 60 m and in CVD presets (shape, not hue).
- Vanguard waves use the same tier rules as all Wardlings (Tier I/II/III by Surge).
- If Vesper takes control of a Vanguard (C15 Minionmancer exception), its pennant is replaced by
  her spindle and gains her owner band, so it visibly becomes "personal".
- Vanguard spawn: the Foundry's outer gate opens with a horn sting and a team-coloured light
  sweep down each lane mouth every 60 s (world tell for the wave timer on the HUD).

### 5.5 Command Markers in the World (C15 commands)

Each of the four squad commands leaves a world-space marker visible to the **owner** (full
strength) and **allies** (50% opacity); enemies see none of them except Attack Target's laser
(below). Markers are drawn as clean holographic geometry (Valorant-style crisp shapes, a faint
scanline texture at ≤ 10% opacity); they obey the telegraph fill rules in §8.2.

| Command | World marker | Wardling pose |
| --- | --- | --- |
| **Follow** (default) | No marker; Wardlings' owner band glows steadily | Trailing the owner |
| **Hold Here** | Circular ground ring with an anchor glyph at the spot, 3 m radius, team colour; fades to a small anchor pin after 3 s | Shields up, facing outward |
| **Attack Target** | Diamond reticle with a down-arrow over the target, in team colour; each attacking Wardling draws a thin laser thread to it for 1 s (the **target sees these threads**, a fair warning) | Lunging, eye flashes white |
| **Go Capture** | A tall ping column at the chosen hardpoint with that task's icon (§6.3) and a dotted path ribbon on the ground from squad to node (owner only) | March pose, like a Vanguard but without pennants |

**Vesper's rewritten elites:** shell gains gold thread-lines and a second floating
spindle above the head; enemy Wardlings she turns show their original faction shell with the
core flipped to her team colour, wrapped in a visible thread tether back to her and a violet `leyfall_violet` ring under their
feet (the "Turned" icon colour in `wardlings-and-economy.md`), with a glitch flicker so the
ownership change is obvious. Elite scale is **×1.3** (unified in `heroes.md` and `wardlings-and-economy.md`, consistency pass 2026-10-02).

---

## 6. Environment Design Language — Halcyra

### 6.1 Architecture

Halcyra is a chain of floating city-shards over the Leyfall. Each lane is a **bridge
of shards**: plazas (hardpoints) joined by causeways, with the violet Leyfall visible
through gaps and below edges (a natural fall boundary). The ancient crystal ruins form the
neutral base (pale stone, giant dormant crystals); each faction's architecture is grown on top
(Concord lattices and clean corporate towers on their half, Syndicate scaffolding, container
stacks and hand-bent neon on theirs). The visual front line literally changes the dressing: when a
hardpoint flips, its banners, floor ring, Barricade and local light colour swap to the new owner
over 1.5 s.

**Two-layer density rule (new):** the **playable layer** (floor to 4 m) is calm: large flat colour
blocks, neutral `halcyra_stone` floor, detail only on cover edges and at eye level. The **skyline
layer** (above 4 m and beyond the playable edge) carries the Cyberpunk 2077 megastructure density:
stacked arcologies, cable bundles, holo-billboards, neon signage, traffic of distant skiffs. The
skyline uses lower contrast and is pushed back by violet depth fog so it frames the fight without
competing with it.

### 6.2 Lanes

| Lane | Biome dressing | Neon & holo character | Landmark |
| --- | --- | --- | --- |
| **North** | High spire-district: bridges over the Leyfall, wind banners, gatehouses, corporate tower faces | Sparse, crisp holo-glyph billboards on distant towers; `sign_teal` mostly | **Belfry Ruin** (N-Mid), a ruined crystal bell tower wrapped in a holo rune scaffold; Lattice Bridge / Rivet Span (the 90 m sightline) |
| **Center** | Market arcology: stalls, awnings, food-cart holo-menus, indoor atria | Densest street neon (`sign_pink` + `sign_teal`), all above 4 m; stall holo-signs dim (Accent tier, non-signal colours) | **The Spindle** (C-Mid), a raised dais in Mid Plaza (Sudden Death arena) under a ring of dead holo-projectors that wake in Sudden Death as the ring wall |
| **South** | Industrial docks: docked skiffs, canal locks, mana pipelines, shallow mana-water | Sodium-amber work lamps are **forbidden** (pickup colour); instead teal hazard strips on crane tops and pipe-gauge holograms | **Leyfall Pumpworks** (S-Mid), a two-level pump hall |

Hardpoint names, positions and the "Shardline Front" layout are owned by `match-flow-and-map.md` §3.2–3.3.

Rule: every lane must be identifiable from any screenshot in it, through a landmark plus a
dominant prop family; floor colour stays neutral `halcyra_stone` so characters pop. Flank
paths are visually narrower and darker with lit floor arrows pointing toward the lane they join
(arrows are white, Accent tier).

### 6.3 Hardpoint Task Types — distinct at a glance (C4)

Each task type has a unique **skyline silhouette** readable at 80 m, a unique floor shape,
and a matching HUD/map icon. Ownership colours the emissive parts. Every task object is a mana-tech
machine: a crystal held by chrome, with holographic rune segments showing progress.

| Task | World object | Skyline silhouette | Floor shape | Icon |
| --- | --- | --- | --- | --- |
| **Hold** | *Holdstone*: a 12 m pillar of light rising from a chrome ring plinth around a dormant crystal | Single vertical beam | Large circle with 12 holo segments that fill as progress | Circle |
| **Plant** | *Charge Cradle*: a twin-pronged chrome pylon with an open socket; the carried Mana Cell is a glowing capsule in a chrome cage on the carrier's back | Tuning-fork "Y" pylon | Square pad with corner brackets | Square with down-arrow |
| **Breach** | *Ward Generator*: a hex-faceted holographic shield dome over a spinning crystal core | Dome bubble | Hexagon with spikes at the vertices | Triangle with crack |

Progress is shown in-world too: Holdstone ring segments fill; the Cradle's prongs light from
base to tip as the cell charges; the Generator dome cracks in three stages (with glitch tearing on
each crack), then shatters. Hardpoints that cannot yet be attacked (C3 prerequisite) show their
emissives dimmed and a locked glyph on the plinth.

### 6.4 Barricades, Garrisons, Supply Caches (C5)

- **Barricade:** a wall across the lane's main path. Concord style = hard-light lattice
  panes in a white frame with flush chrome seams; Syndicate style = riveted blast gate with an
  ember grid, crew tags and a hand-bent neon tube along the top (Accent tier). To the
  owning team it renders 50% translucent with forward chevrons (passable); to enemies it is
  opaque with serrated hostile trim. Three damage states (intact / cracked / failing with
  sparks or mana leaks), then collapse into rubble that stays as cover. A Hex Breach Gate shows as a
  3 m glitch-torn opening (§8.1).
- **Garrison Sentinels:** placed on raised sockets at the hardpoint's corners; their sockets
  stay visible (empty, dim) while a Sentinel respawns.
- **Supply Cache:** a squat mechanical crate with an ammo-belt icon, brass trim and a small holo
  label, always mechanical in style regardless of faction (it serves Mechanical guns).
- **Forward Beacon (held Mid):** a tall team-coloured banner-mast with a holographic spawn halo on
  the ground; the halo dims and strobes when "under attack" (spawning disabled).

### 6.5 HQ Set-Piece and the Mana Uplink (C6, C7)

The HQ is a fortified megastructure shard with a clear front gate facing the Inner hardpoints.
This is where Cyberpunk 2077 density is allowed to peak (Set-piece emission tier, §4.6): the HQ is
never contested ground, so its neon is always truthful about the owner.

- **Concord HQ:** a clean corporate atrium tower: white composite, glass, gold, ranks of crisp
  azure and white holo-glyph signage, an indoor sky-garden around the Uplink base.
- **Syndicate HQ:** a fortress of stacked containers, scaffolds and rebuilt war-machines, with
  hand-bent ember and amber-free neon (ember + `sign_pink`), crew murals made of original glyphs, and
  steam from furnace stacks.

The **Mana Uplink** is the game's dominant landmark: a **45 m neon mana spire**, a giant crystal
held in a chrome frame of rings and wrapped in rotating bands of holographic runes, firing a
team-coloured beam into the sky that is visible from anywhere on the map (each team's beam orients
players toward home/enemy). It is the Cybergram made visible, so its failure states use the
**signal glitch** vocabulary (§8.1).

| Uplink state | Visual |
| --- | --- |
| Protected | Hexagonal shield shell around the base; frame rings and rune bands rotate smoothly; steady beam |
| **Exposed** | Shield shell shatters and stays gone; rings stop and judder; rune bands tear with glitch blocks; beam turns jagged; warning strobes ring the HQ in owner colour; enemy outline on the core becomes damageable highlight |
| Integrity 75/50/25% | Crystal cracks in three permanent stages, chunks fall, beam narrows, one rune band dies per stage (damage is permanent, so are the cracks) |
| Destroyed | Beam collapses downward, crystal goes grey, every HQ neon sign of that team cuts out, every mana effect on that team fizzles out |

Supporting set-pieces: **Sanctum** (spawn chapel with a healing glow, soft holo hymn-glyphs and a
10 m floor ring marking the anti-camp zone), **Foundry** (a neon-lit conveyor of half-built
Wardlings on cradles with robot arms; your squad hops off and joins you), **Armory** (a neon gun
shop: weapon racks, a holo display wall of crystals and chips, and a workbench where the
gun-socketing animation plays).

---

## 7. Weapon Art & the Visible Upgrade System

Visible weapon growth is the owner's top visual request (`/ideas`) and Pillar 4. Rules,
lines, prices and tiers are owned by `design/gdd/weapons-and-mods.md` (§3.6–3.8); this
section owns how they **look**. Every weapon uses the same four mounts, and mount meshes are
shared per line (placed by per-weapon scale/offset presets), so art cost is *lines × tiers*,
not *lines × tiers × weapons*.

**Weapon look (new):** guns are **chunky, readable, invented** (Apex lesson): oversized receivers,
clear grips and magazines or conduits, big first-person silhouettes, no replica of any real gun.
Each gun is mana-tech: a mechanical body with visible cable runs, chrome mount hardware and one or
two Accent-tier neon trims in the owner's team colour along a seam. Each gun carries one or two
story marks from its hero (Sable's notches, Ryker's serial, Hex's stickers). The mount sockets are
always the clearest shapes on the gun; trims and story marks never sit on or next to a socket.

### 7.1 Mount Layout (all 7 weapons)

| Socket (marker) | Position | Visible in FP view | Changes |
| --- | --- | --- | --- |
| **Core** (`socket_core`) | Top/heart of the receiver, just ahead of the sight | Always (centre-bottom of screen) | The gun's idle glow; muzzle flash takes the line's family hue |
| **Barrel** (`socket_barrel`) | Muzzle and barrel shroud | Yes, the leading tip | Lens rings (Crystal) or shroud/rail (Chip); ring count = tier; tracer length/shape |
| **Frame** (`socket_frame`) | Grip, stock and camera-facing side plates | Yes, left edge | Side crystals pulse during mana regen (pulse speed = regen rate) / stock LED counter = rounds left |
| **Chamber** (`socket_chamber`) | Mana conduit (Mana) / magazine window (Mech) | Yes | Conduit glow / tinted rounds = loaded **Ammo Type**; Ammo Mod adds a small rune/cap on the conduit or mag base |

Empty sockets are visible as open **chrome claws with brass knuckles** (Mana) or empty chip slots
with a dark LED (Mechanical), so players see what they *could* buy. Third-person mount meshes are
scaled 1.3× relative to the viewmodel (a standard cheat so they survive distance).

### 7.2 Crystals (Mana guns: Halo Repeater, Threadcaster, Whisperfang, Glitchcaster)

- Physical, faceted, emissive meshes gripped by chrome claw mounts, fed by a visible cable from the
  conduit (the mana-tech join), all using `spatial_fx_crystal`: interior parallax glow, fresnel rim,
  **core band in the line's family hue**, slow internal swirl.
- **Family hue never sits in a team range.** Exclusion zones: azure 195°–235°, ember 0°–25°
  (HSV hue). The GDD hues map to these tokens: amber `#FFB534` (≈40°), violet `#A970FF`,
  white `#F4F1FF`, green `#57E07F`, teal-green `#2FD3A0` (≈160°), magenta `#F24FD0`.
- **Each line also has a cut shape** (the colour-blind backup), so two amber lines never look alike:

| Line (socket) | Cut shape | Hue |
| --- | --- | --- |
| Ember Heart (Core) | Heart-shaped twin-lobe crystal | amber |
| Tempest Shard (Core) | Jagged lightning spike | violet |
| Prism Eye (Core) | Faceted orb with a pupil-like inner facet | white |
| Wellspring (Core) | Droplet with a rising bubble mote | green |
| Focus Lens (Barrel) | Flat lens rings | white |
| Stillwater Ring (Barrel) | Smooth torus rings | teal-green |
| Velocity Facet (Barrel) | Swept arrow-head facets | magenta |
| Reservoir (Frame) | Capsule vials along the side plate | green |
| Flux Coil (Frame) | Helix crystal wrapped around the grip | violet |
| Anchor Crystal (Frame) | Squat hexagonal blocks on the stock | amber |

- **Socketing moment:** on purchase the crystal flies into its claw mount, the claws clamp with a
  metallic "chk", a ring of holographic runes runs down the barrel, and the next shot plays a one-off
  brighter flash. The same animation drives the Armory turntable preview (HUD doc §10).
- Mana state is diegetic: crystal glow tracks the current pool %, and **Burnout** turns every
  crystal dark grey with a crackle of sparks until regen starts.

### 7.3 Chips (Mechanical guns: Breakline AR-7, Ironmaw, Tackhammer)

Chips are cyberdeck-style cartridges slotted into a **chip rack** with an LED strip and a small
holo label that projects the line's glyph above the rack in first person (Accent tier); every line
also adds a physical module so the change is a silhouette, not just an LED.

| Line (socket) | Card glyph | Physical module |
| --- | --- | --- |
| Overclock (Core) | Lightning | Heat-sink fins on the receiver; glow orange-hot while firing (3 fins at Mk III) |
| Cyclic Governor (Core) | Spinning gear | Exposed spinning flywheel |
| Ballistic Solver (Core) | Crosshair | Small computer housing with a lens above the rail |
| Feedback Loop (Core) | Circular arrows | Looped cable from receiver to magazine |
| Rifling (Barrel) | Spiral | Lengthened barrel shroud with spiral grooves |
| Stabilizer (Barrel) | Level bars | Muzzle brake with side ports |
| Penetrator (Barrel) | Arrow through plate | Spiked muzzle tip |
| Extended Mag (Frame) | Stacked bars | Longer / drum magazine housing |
| Quickload (Frame) | Double chevron | Spring-loaded mag guide flared at the well |
| Gyro (Frame) | Gyroscope | Gyroscope ring on the stock that spins while firing |

Chip LEDs and holo labels are Accent tier (≤ 1.0, no bloom, V5). Overclock's orange-hot fins are a
heat colour on an opaque mesh, not bloom.

### 7.4 Tiers and the FPS-Distance Read

Tier names per GDD: Crystals **Shard / Facet / Heart**, Chips **Mk I / Mk II / Mk III**. Tiers
read by **size, facet/fin count, glow and idle animation**, never by colour.

| Tier | Crystal | Chip | 3P read at 20–40 m |
| --- | --- | --- | --- |
| I | Thumb-size shard, low glow | Single card, 1 LED | Socket looks filled; no bloom |
| II | Twin facets + 1–2 orbiting motes, slow pulse | Card + heat-sink fins + LED strip | Visibly larger; faint bloom (Mana) |
| III | Large heart crystal with a floating holo rune ring and sparse particles | Full module, exposed core, moving parts | Halo/moving module adds ≥ 15 cm of silhouette, readable at 40 m |

- Core Tier III adds a **halo-ring muzzle flash every 5th shot** (every shot on Ironmaw and Tackhammer, per GDD).
- At > 25 m we only guarantee the read of *how many sockets are filled* and *which are Tier III*;
  finer detail comes from the scoreboard build icons and the death recap (HUD doc §8, §9).
- Acceptance (from GDD): QA can identify each socket's tier from 20 m in third person on a **greyscale** screenshot.
- Cosmetic VFX unlocks may recolour Core/Barrel/Frame family hues only; tier size/glow and
  ammo-type impact VFX are gameplay information and never recolourable.
- Neon trims and story marks never change with tier, so they never muddy the tier read.

### 7.5 Ammo Types and Mods (Chamber)

Ammo type is the strongest channel for the **victim**, so it gets hue + tracer pattern + impact shape.
The team colour stays on the projectile's outer rim; the ammo type owns its core and impact.

| Ammo Type (Mana: Infusion / Mech: Round) | Core hue | Tracer pattern | Impact shape | Status icon |
| --- | --- | --- | --- | --- |
| Standard | White | Solid | Small spark/puff | — |
| Piercing | Silver | Long thin needle dashes | Exit-hole spike | Broken shield |
| Incendiary | Amber | Flickering flame flecks | Ember splash + lingering flame on target (Burn/Scorched) | Flame |
| Shock | Violet | Zig-zag micro-arcs | Arc jump to nearby targets (Overload) | Lightning |
| Siphon | Green | Spiral that curls back toward the shooter | Motes flowing to shooter | Droplet |
| Cryo | Frost white (desaturated, never azure) | Crystalline beads | Frost-star; Brittle adds ice shell | Snowflake |
| Sunder | Magenta | Serrated cog shards | Shatter shards on constructs | Cracked gear |

Ammo Mods add a small cap/rune on the magazine or conduit (Saturated = filled dot, Lingering = clock,
Volatile = burst, Tracer = eye, Overcharged = double chevron) and the **Tracer** mod's mark is an
ally-visible outline in the shooter's team colour (through walls, 1.5 s).

---

## 8. VFX Language

### 8.1 Vocabulary

Two core vocabularies (unchanged) plus one restricted vocabulary for the signal.

| | **Mana** (Mana heroes, Wardlings, Uplink, crystals) | **Mechanical** (Mechanical heroes, chips, traps, Supply) | **Signal glitch** (Hex, hacked gadgets, the Cybergram itself) |
| --- | --- | --- | --- |
| Blend | Additive, emissive HDR > 1.0, blooms | Alpha-blended / opaque, HDR ≤ 1.0, never blooms | Alpha-blended overlay on an existing effect or mesh; bloom only if the host effect is mana |
| Shapes | Rounded ribbons, rings, **holographic rune glyphs**, hex glyphs, motes | Hard sparks, smoke puffs, shell casings, debris chunks | Rectangular block displacement, horizontal scanlines, RGB channel split (≤ 4 px at 1080p) |
| Motion | Swirl, ease-in-out, hovering | Ballistic, gravity, fast decay | Stepped (no easing), 8–12 Hz jitter in bursts of ≤ 0.3 s, never continuous flashing above 3 Hz |
| Colour | White core + team rim (+ family core band) | Neutral brass/steel/smoke + team-coloured *decal or light* only | Team colour + its chromatic offset; never a new hue |
| Audio pairing (visual mood only; audio-director owns sound) | Choral, airy | Heavy, metallic | Digital, crackling |

**Where glitch is allowed (exhaustive):** Hex's skills and weapon; any gadget currently
Malfunctioning or Hijacked; Hex's Breach Gate on Barricades; Vesper's Turned Wardlings (ownership
flicker); the Uplink in Exposed / damage / Drought states; Ward Generator crack stages; Scramble's
HUD treatment (owned by `design/ux/hud.md`). Nowhere else. Under **Reduced Motion** every glitch
becomes a static scanline overlay with the RGB split frozen.

**Holographic runes (mana-tech):** mana abilities draw their shapes as crisp rune geometry
(Valorant-style geometric telegraphs): a ring, a dome, a line or a wall, outlined by a single rune
band. One rune alphabet is shared across the game (original glyphs, designed in-house), so players
learn "rune band = mana ability edge".

### 8.2 Team-Coloured Effects and Telegraphs

- **Every hostile area effect** has a team-coloured border with serrated outward ticks and a
  low-opacity fill (≤ 25%); allied areas have a smooth thin border and ≤ 12% fill; the
  player's own effects ≤ 8% fill. Damage zones add a white inner pulse every 0.5 s.
- **Geometric clarity (Valorant rule):** every area effect is one primitive (circle, dome, line,
  wall, cone) with a crisp edge; no soft-edged clouds as the only boundary. Particles may decorate
  the inside but never define the edge.
- **Ability wind-up:** every damaging ability with a cast time shows a ground or volume
  telegraph for its full cast (min 0.3 s) in the caster's team colour; ultimates add a world-space
  audio sting and a vertical light column visible over cover.
- **Projectiles:** core white, rim team colour, length proportional to speed; enemy projectiles
  are 20% thicker than ally ones at the same distance.
- **Traps (Juniper):** invisible-by-design traps still show a 0.5 m team-coloured glint
  every 2 s to enemies within 8 m; Hex-hacked enemy gadgets get a glitch overlay (RGB-split, scanline
  flicker) in Hex's team colour.
- **Skill Forks and Mastery (`heroes.md` §3.5):** a learned Fork shifts that skill's effect
  core band cool (Fork A, toward white-teal `#BDF5EC`) or warm (Fork B, toward white-gold
  `#FFE7B0`) and adds a small shape accent (A: rings, B: sparks); the team rim never changes.
  Each Mastery adds a glyph to the hero's level ring (over-head nameplate and HUD portrait).
- **Heals:** `heal_verdant` green core always, rim = healer's team colour; healed targets get a
  rising plus-motes effect (shape cue).
- **Cyberware activations** (Ryker's stim port, Brannoc's furnace-heart, Sable's struts) brighten
  their neon trim within the Accent tier; they never produce a team-coloured area telegraph unless
  the skill itself is an area effect.

### 8.3 Budgets

Per effect: ≤ 64 particles, ≤ 2 overdraw layers at screen centre, ≤ 1 dynamic light (no
shadows) and ≤ 1.0 s lifetime for hit effects. Wardling effects use half budgets. Holographic and
glitch layers count as overdraw layers. Global per-frame cap enforced by an effect-priority manager:
enemy telegraphs > own feedback > ally effects > ambient (city neon, holo signage).

---

## 9. UI/HUD Visual Direction (summary; spec in `design/ux/hud.md`)

- **Screen-space HUD** with **diegetic echoes**: ammo/mana is also shown on the gun (the core
  crystal dims as mana drains; mechanical mag has a back-counter LED); hardpoint progress is in-world.
- **Holographic flavour, UX rules first:** the HUD borrows Cyberpunk 2077's holographic look only
  where it costs no readability: chamfered panel corners, a 1 px light keyline, a scanline texture
  inside panel backgrounds at ≤ 4% opacity, and a ≤ 150 ms holo-flicker on panel *entry* only
  (removed by Reduced Motion, counted in the HUD's animated-element budget). Text, numbers and
  icons are always solid, never scanlined, never chromatic-split.
- **Typography:** display face *Chakra Petch* (OFL) for numbers and headers; body face *Noto
  Sans* (OFL, wide script coverage for localisation). Minimum 18 px at 1080p; numbers bold.
- **Iconography:** flat two-tone icons on a hexagon (mana) or rounded-square (mechanical) frame;
  team-coloured edges, white glyphs. Task icons match §6.3 exactly.
- **Animation feel:** snappy (≤ 150 ms in, ≤ 250 ms out), slight overshoot on gains, no motion on
  steady states. All motion respects the Reduced Motion setting.
- **Conflict decided:** art wanted translucent glassy holo panels over the world; UX readability
  won: panels are ≤ 65% opaque dark (`#0B0E18`) with a 1 px light keyline, and text never sits
  directly on the world. The holographic flavour above lives within that rule.

---

## 10. Godot Technical Art Direction (Godot 4.7, Forward+)

> Engine reference in `docs/engine-reference/godot/` is verified for 4.6; 4.7 deltas are
> **unverified**. Items below marked ⚠ must be checked against the 4.7 docs before
> implementation. Shader implementation belongs to technical-artist; this section sets direction.

### 10.1 Semi-Cel Toon Shader

- One master spatial shader for characters/weapons/Wardlings (`spatial_char_toon.gdshader`)
  and one for environment (`spatial_env_toon.gdshader`), both using a custom `light()` function:
  - **Diffuse (semi-cel):** `NdotL × attenuation` (shadow included) sampled into a **shared 256×16
    ramp texture**: two hard bands plus a narrow soft terminator (the ramp's transition is painted
    2–6% wide, so the softness is authored, not computed), with a tinted shadow colour. Rows: skin,
    cloth, leather/rubber, painted metal, **chrome**, porcelain, iron, crystal, hair, env stone, env
    metal, env glass; 4 spare. The row is a per-material uniform (`ramp_row`).
  - **Specular:** thresholded Blinn highlight; anisotropic strip for hair and brushed metal (masked).
  - **Chrome (new):** chrome is **not** a reflection. Masked chrome areas sample a 3-band stylised
    **matcap** (256², one per faction: `chrome_cool`, `chrome_warm`) with the view-space normal in
    `fragment()`; the chrome ramp row keeps shadows shallow so the matcap carries the look. Cost: one
    extra texture sample on masked pixels.
  - **Rim:** fresnel rim in the light colour on the lit side (0.25–0.4 strength on characters, the
    Valorant-style edge pop), plus the optional `team_tint` rim at 0.15 strength.
  - **Mask texture (RGBA):** R = shadow bias (painted AO), G = spec mask (0–0.5) / chrome mask
    (0.5–1.0), B = emissive mask (neon trims, crystals, visor slits), A = outline width.
- **Emissive neon trims:** emission = mask B × `emission_color` × `emission_energy`. Hero and weapon
  trims set `emission_color` from `team_tint` (or the signature colour for non-team accents), and
  `emission_energy` is clamped by a global uniform `accent_emission_cap = 1.0` (Accent tier, below
  the 1.1 glow threshold, so trims glow without blooming). Only mana materials and signal materials
  may exceed it (§4.6).
- Emissive is the only route to bloom; artists must not push albedo above 0.9.
- **Weathering is painted:** edge wear, stencils and grime are in the albedo; no runtime
  roughness/metallic workflow on characters. Large repeat-free decals on characters are baked into
  the texture, not placed as `Decal` nodes.
- Environment shader skips specular and uses 2 bands only (cheaper; calmer read, V1); chrome matcap
  is available on env props through the same mask convention.
- Cost note: custom `light()` runs per light in Forward+; keep ≤ 4 dynamic omni/spot lights
  affecting any character at once (VFX lights have shadows off).

### 10.2 Outlines

- **Characters, Wardlings, weapons, interactive props:** inverted-hull outline as a `next_pass`
  material (`spatial_fx_outline.gdshader`, `cull_front`, `unshaded`), vertices pushed along
  **smoothed normals baked into a vertex attribute** (CUSTOM0/UV2) at import, width from vertex
  colour/mask A, constant screen-space width clamped by distance (1.5–2.5 px at 1080p).
  Outline colour = darkened albedo for allies, team colour for enemies (or the enemy highlight override).
- **Environment:** no outlines in the vertical slice. A screen-space depth/normal edge pass
  via `Compositor` + `CompositorEffect` is an Alpha experiment, kept only if it costs < 0.5 ms at 1080p.
- **Ally through-wall silhouettes:** separate pass with `depth_test_disabled`, flat ally colour at
  25% opacity. Enemies never get through-wall rendering (no wallhack feel), except during
  effects the design explicitly grants (e.g. reveal abilities).
- **Viewmodel:** thin outline only (1 px), rendered by the viewmodel camera layer, so it never clips into the world.

### 10.3 Post-Processing (WorldEnvironment + CameraAttributes)

| Feature | Setting | Note |
| --- | --- | --- |
| Tonemap | Filmic, exposure tuned per lane | AgX (4.6 contrast/white-point controls) evaluated at VS; pick whichever keeps team colours and neon saturated ⚠ |
| Colour grading | 3D LUT per match phase (Skirmish, Surge I, Surge II blue hour, Drought, Sudden Death), blended over 3 s | Each LUT must keep the character exposure floor (§2.3) |
| Glow (bloom) | On, HDR threshold **1.1**, only Signal and Set-piece emissives exceed it; 3 glow levels max in gameplay | Glow is processed before tonemapping since 4.6 — retune after any engine bump. Bloom budget: ≤ 6% of pixels above threshold in the §11 screenshots; GPU cost target ≤ 0.5 ms at 1080p ⚠ measure |
| SSAO | Off (painted AO in mask) | Saves ~1 ms |
| SSR / SSIL / SDFGI / VoxelGI | Off | Chrome uses matcaps; lighting is baked |
| GI | `LightmapGI` baked for static shards; few `ReflectionProbe`s for crystals and HQ glass | |
| Fog | Depth fog tinted `leyfall_violet` for distant shards and the skyline layer; volumetric fog only on High and in HQ haze (neon light shafts in HQ) | |
| AA | SMAA 1x default; TAA optional (ghosts outlines and thin neon trims) | SMAA available since 4.5 |
| Upscaling | FSR 2 option on low-end | ⚠ check 4.7 options |
| Motion blur / chromatic aberration / film grain | None in gameplay (readability); CA and scanlines only inside glitch-vocabulary effects (§8.1), as per-material effects, never as a full-screen pass | |

### 10.4 Holograms, Glitch and Signage Shaders (new)

- `spatial_fx_holo.gdshader`: unshaded, additive or alpha, fresnel edge, world-space scanlines,
  optional slow flicker; used for rune rings, holo labels, command markers, Armory display walls,
  signage. Counts as one overdraw layer. Emission tier per §4.6 (Accent in lanes, Set-piece in HQ).
- `spatial_fx_glitch.gdshader`: applied as `next_pass` or overlay only on glitch-allowed targets
  (§8.1): stepped vertex block displacement + 3-tap RGB split in screen UV + scanline mask, driven by
  a `glitch_amount` uniform (0 = off, so the pass can be skipped). Reduced Motion forces the static mode.
- **City signage:** baked into trim-sheet emissive on the skyline layer (no lights, no shadows);
  `sign_pink` and `sign_teal` read from global uniforms so the CVD preset reroute (§4.6 rule 5) is a
  uniform change, not a material swap.
- **Neon spill:** faked with emissive + small unshadowed `OmniLight3D`s only in HQ set pieces (≤ 6
  per HQ room); lanes get no neon lights.

### 10.5 LOD and Culling

- Mesh LODs auto-generated at import (Godot mesh LOD) for all props and characters; artists may supply hand LODs for heroes.
- Wardlings: two MeshInstances per Wardling (body + outline override) with
  `visibility_range_end` on the outline instance at 60 m; beyond 80 m the body swaps to a 300-tri
  proxy with the core still emissive (the core must always read).
- Third-person crystal/chip meshes: Tier I/II particles off beyond 25 m, Tier III halo kept to 60 m.
  Weapon neon trims and chip holo labels off beyond 30 m.
- Skyline megastructure: single-mesh impostor rings per lane with baked signage; no per-building
  draw calls beyond the playable edge.
- `OccluderInstance3D` on shard architecture; lanes are designed with occluding walls between them.
- Shader Baker (4.5+) enabled for exports to avoid first-use hitches on ability VFX, holo and glitch passes.

### 10.6 Budgets (target: 1080p, 144 fps on a recommended GPU, 60 fps on min spec)

| Category | Tris (LOD0) | Materials | Textures |
| --- | --- | --- | --- |
| Hero (3P) | 30k (max 40k); cyberware detail goes into texture, not tris | ≤ 3 + outline | 2048 albedo, 1024 mask, shared ramp + faction matcap; normal map only for armour |
| Hero first-person arms | 15k | 1 | 2048 |
| Viewmodel weapon | 20k | 2 | 2048 albedo + 1024 mask |
| 3P weapon | 6k | 1 | 1024 |
| Crystal / chip / module | 300–1,000 | shared | 1024 atlas for all families |
| Wardling | 4k (Sentinel 6k) | 1 | 1024 atlas shared by all variants, faction swap via palette row |
| Uplink spire | 80k | ≤ 4 (incl. holo rune bands) | trim sheets |
| Modular env piece | 200–5k | 1–2 | 2048 trim sheets per faction + neutral |
| Skyline impostor ring (per lane) | ≤ 60k | 2 | 2048 trim sheet + emissive signage atlas |
| VFX texture | — | — | ≤ 512, flipbooks ≤ 1024 atlas |
| Environment `Decal` nodes | — | — | ≤ 48 visible in any lane view ⚠ measure clustered cost |

Scene-level: ≤ 2,000 draw calls and ≤ 3.5 M visible tris in the worst view (team fight
at a Mid with 10 heroes + 50 Wardlings, of which up to 8 Vanguards and 4 Sentinels; the
map-wide AI budget is ≤ 110 per Canon C1); texture memory ≤ 2.5 GB at High; VFX (including holo and
glitch passes) ≤ 1.5 ms GPU; glow ≤ 0.5 ms. These are art-side proposals; `technical-preferences.md`
still has budgets unconfigured, so technical-director must ratify them. If the semi-cel + matcap +
neon stack exceeds budget on min spec, the cut order is: volumetric HQ fog → skyline signage
animation → weapon neon trims beyond 15 m → rim light on Wardlings. Signals and outlines are never cut.

### 10.7 glTF Pipeline

- **Source:** Blender 4.x `.blend` in `art_source/` (not imported by Godot); export **`.glb`** (glTF 2.0
  binary) to `assets/`. Metres, +Y up, applied transforms, one asset per file, no embedded lights/cameras.
- **Rigs:** one shared humanoid skeleton naming compatible with Godot's `SkeletonProfileHumanoid`
  for retargeting; Wardlings share one small rig. Animations as NLA actions, names
  `idle`, `run_fwd`, `cast_q`, … no root motion for players.
- **Sockets:** empty nodes in the weapon glb named `socket_core`, `socket_barrel`, `socket_frame`,
  `socket_chamber` (names fixed by `weapons-and-mods.md` §3.6.1), plus `fx_muzzle`, `fx_eject`; characters export `HAND_R_weapon`, `BACK_attach`, `HEAD_nameplate`.
  Godot attaches via `BoneAttachment3D` / `Marker3D`.
- **Import hints:** use Godot's node-name suffixes for collisions (`-col`, `-convcolonly`, `-colonly`) and
  occluders (`-occ`); an `EditorScenePostImport` script assigns the toon/outline materials by
  material-name prefix (`M_toon_*`, `M_env_*`, `M_crystal_*`, `M_holo_*`) and bakes smoothed normals for outlines.
- **Textures:** PNG sources, imported as VRAM Compressed (BPTC/S3TC), mipmaps on, sRGB for albedo, linear for masks and matcaps.

### 10.8 Naming

Pattern (from art-director standard): `[category]_[name]_[variant]_[size].[ext]`, lower snake case.

| Category | Example |
| --- | --- |
| Character | `char_brannoc_body.glb`, `char_brannoc_fparms.glb` |
| Weapon | `wpn_ryker_rifle_fp.glb`, `wpn_ryker_rifle_tp.glb` |
| Upgrade | `upg_crystal_solar_t3.glb`, `upg_chip_overclock_t2.glb` |
| Wardling | `wdl_striker_t2.glb` |
| Environment | `env_concord_wall_straight_4m.glb`, `env_neutral_plaza_floor_8m.glb`, `env_skyline_north_ring.glb` |
| Prop | `prop_supply_cache_a.glb` |
| Texture | `tex_brannoc_body_albedo_2048.png` (`albedo`/`mask`/`normal`/`emit`), `tex_matcap_chrome_cool_256.png` |
| VFX | `vfx_crystal_solar_muzzle_small.tscn`, `vfx_hex_glitch_overlay.tscn` |
| Shader | `spatial_char_toon.gdshader`, `spatial_fx_crystal.gdshader`, `spatial_fx_holo.gdshader`, `spatial_fx_glitch.gdshader`, `particles_fx_hit.gdshader` (per shader rules) |
| Placeholder | any of the above with suffix `_ph` (§13) |

---

## 11. Asset Standards Checklist (per incoming asset)

1. Passes the **shadow test** (recognisable as a black silhouette at gameplay distance).
2. Uses the master toon shader, shared ramp and faction matcap; no bespoke shaders without technical-artist sign-off.
3. Within §10.6 budget; LODs generated; collision named.
4. Team-coloured parts, including team-coloured neon trims, are driven by `team_tint` (never baked into textures).
5. Correct name, folder, and licence entry (placeholders in `assets/LICENSES.md`).
6. Five readability test screenshots (Mid team fight, Hold in North, Plant in South, Uplink Exposed, Sudden Death) still pass CVD simulation, the neon coverage caps (§4.6 rule 4) and the exposure floor (§2.3).
7. Emission energy within its tier (§4.6); Mechanical assets never above 1.0.
8. Passes the **originality test** (§14.1) and has its story props listed in the asset ticket (§5.1).

---

## 12. Vertical-Slice Asset List (M1)

M1 = the one-lane **Slice Map "Shardline Causeway"** (`match-flow-and-map.md` §3.7: 5
hardpoints using all 3 task types, staged within M1, both HQs, reduced Mid Plaza, one flank loop per half), **2 heroes
(Vesper Loom, Brannoc)**, levels with a reduced skill tree, Lumen shop with the minimal mount pipeline, Surge I, Vanguard waves,
Forward Beacon spawn. Garrisons, Barricades and Supply Caches (M3), Sudden Death (M3), Ryker and Liora (M3), Wardling
variants and the full crystal/chip set (Alpha) are later; the slice includes a minimal read-test of the socket system.

| # | Asset | Quantity | Fidelity in VS |
| --- | --- | --- | --- |
| 1 | Hero 3P models + FP arms: Vesper, Brannoc (incl. cyberware pieces and story props) | 2 + 2 | Final-quality body, 1 faction trim swap |
| 2 | Hero weapons FP + TP (Threadcaster, Ironmaw) with four `socket_*` markers | 2 × 2 | Final |
| 3 | Hero animation sets (locomotion, fire, reload/vent, 4 skills, death, emote idle) | 2 | Final for FP, blockout-plus for TP |
| 4 | Slice mounts per `weapons-and-mods.md` §3.10: Ember Heart + Flux Coil crystals (Threadcaster), Overclock + Quickload chips (Ironmaw), Tiers I–III each; Piercing + Sunder tracers/impacts (no Barrel socket, no Ammo Mods) | 12 mounts + 2 ammo FX | Greybox primitives per GDD; final art for Ember Heart + Overclock as the Pillar 4 read-test |
| 5 | Wardling base form, both faction skins, Tiers I–III; owner sash + Vanguard pennant variants | 1 rig, 3 tier states, 2 class markings | Final |
| 5b | Command world markers: Hold ring, Attack reticle + threads, Go Capture ping column + path ribbon | 4 | Final |
| 6 | Slice Map: 1 lane × 5 hardpoints (Glasswork/Furnace Gate, Signal Market/Scrap Bazaar, Spindle kits), causeways, 2 flank loops, Barricade sockets | 5 nodes | Stylised neutral kit + 1 faction kit each side; full 15-node map is Alpha |
| 6b | Skyline impostor ring for the slice lane with baked signage | 1 | Blockout-plus (silhouette + emissive signage atlas) |
| 7 | Task objects: Holdstone, Charge Cradle + Mana Cell, Ward Generator (3 crack stages) | 3 + cell | Final |
| 7b | Barricade (Concord lattice / Syndicate blast gate), 3 damage states + rubble | 2 | Greybox in M1 (sockets only, inactive); final for M3 when Barricades go live |
| 8 | HQ ×2: Uplink spire (protected/exposed/3 crack stages/destroyed, with holo rune bands), Sanctum, Foundry, Armory | 2 | Uplink final; rooms stylised kit with neon set-dressing |
| 9 | Reduced Mid Plaza (r = 25 m); Leyfall ring wall for Sudden Death built in M3 | 1 | Final |
| 10 | Skybox: Leyfall sea, distant shards, per-phase LUTs (Skirmish, Surge I, Surge II, Drought) | 1 + 4 | Final |
| 11 | VFX: 2 heroes × (weapon fire, impact, 4 skills), Vesper Elite/Turned, Rally Beacon heal, Wardling hit/death, capture flip, Uplink damage + exposure glitch, Surge transition | ~25 | Final for gameplay-critical, simple for ambient |
| 12 | Shaders: semi-cel toon (char/env) with matcap chrome and neon trims, outline, crystal, holo, glitch, team-tint, telegraph decal, Leyfall, LUT grading | 9 | Final |
| 13 | UI kit (scope per HUD doc §19): icons for 2 heroes × 4 skills, task types, ownership patterns, squad command states (F/H/A/C), Vanguard flag, status effects, mount/ammo icons | ~60 icons | Final |

---

## 13. Placeholder-Art Strategy

Code must not wait for art. Placeholder art follows the same pipeline, naming (`_ph`), sockets and
`team_tint` uniform as final art, so swapping is a file replace.

1. **Greybox first (week 0):** CSG/`MeshInstance3D` blockouts with **Kenney Prototype Textures**
   (CC0) grids; hardpoint task objects as primitive stand-ins that already obey §6.3 skyline shapes
   (cylinder beam = Hold, Y-shape = Plant, sphere = Breach).
2. **Characters:** CC0 humanoids from **Quaternius** (e.g. Ultimate Modular Characters / Universal
   Animation Library) or **KayKit** character packs (CC0), recoloured via `team_tint` and the hero's
   signature colour (§4.7), plus a primitive "hook" bolted on (ring for Liora, slab for Brannoc,
   spindles for Vesper, pauldron for Ryker, scarf ribbon for Sable, box pack for Juniper, ear
   antennae for Hex) and a primitive chrome cyberware piece (a cylinder on the right limb) to test
   silhouette and matcap rules immediately.
3. **Weapons:** **Kenney Blaster Kit** (CC0) guns with added `socket_*` markers and one emissive
   trim strip (Accent tier); crystals as coloured `PrismMesh`/`SphereMesh` primitives in the right
   cut shapes.
4. **Wardlings:** capsule + sphere core with emissive team colour, sized per §5.3.
5. **Environment:** Kenney/Quaternius CC0 sci-fi kits for HQ dressing; skyline as untextured box
   stacks with emissive quads in `sign_teal`/`sign_pink` (tests the neon caps); **Poly Haven** /
   **ambientCG** (CC0) only for skies and reference, never for in-world PBR textures (style mismatch).
6. **Shaders from day one:** the real semi-cel toon + outline shader, a placeholder 3-band chrome
   matcap (generated in-house, CC0-clean), the holo shader and the glitch pass run on placeholders,
   so readability, bloom coverage and performance are tested on the true render path from the prototype.
7. **Rules:** no Mixamo or other non-redistributable assets in the repository; no ripped or traced
   assets from any reference game; every third-party file is listed in `assets/LICENSES.md` with
   source URL and licence; all placeholders live under `assets/placeholder/` and a pre-release check
   fails the build if any `_ph` asset is referenced.

---

## 14. Reference Board

The reference board is a **written** board: descriptions of what to study, plus links to
official public pages where useful. **No copyrighted images are committed to the repository**, no
screenshots are pasted into project docs, and no asset is traced, kit-bashed or colour-picked
directly from a reference. Teams may view references privately while working.

### 14.1 Originality Test (binding)

We take inspiration, not copies: no direct copies of characters, logos, emblems, weapon designs,
UI layouts or typefaces. Every hero, weapon, faction mark and set piece that draws on a reference
must differ from its nearest reference design in **all three** of: (1) silhouette hook, (2) colour
identity, (3) story/function. Art-director checks this at concept sign-off; a design that fails one
of the three goes back to concept. Real-world emblems (e.g. the red cross) and real brands are never used.

### 14.2 What to Collect, per Reference and Department

**Valorant — shape, shading, readability**

| Department | Collect (described, not copied) |
| --- | --- |
| Character | How agents divide the body into 3–5 flat material zones; how one accessory carries the silhouette; signature-colour placement on cloth and hair; face simplification at FPS distance |
| Weapons | First-person framing: how much screen the viewmodel occupies, where the eye lands, how skins keep the base silhouette |
| Environment | Flat colour blocking of walls and floors; how site letters and landmarks orient players; clutter levels at eye height |
| VFX | Ability telegraphs as primitives (walls, domes, lines, cones); edge crispness vs fill opacity; how ally and enemy versions differ |
| UI / HUD | Enemy highlight options; icon simplicity; information density at screen edges |
| Tech art | Shading band count and softness; rim light strength; how outline-free characters still separate from backgrounds (to calibrate our outline weight) |
| Animation | Readable idle poses; ability wind-up timing as a telegraph |

**Apex Legends — gear, personality, weapons, frontier**

| Department | Collect (described, not copied) |
| --- | --- |
| Character | How backstory sits on the model (trinkets, patches, repairs, tallies); strap and buckle construction; bold single-element silhouettes; personality in idle and emote poses |
| Weapons | Chunky receiver proportions; readable magazines and grips; how attachments change silhouette (directly relevant to our mounts); wear on edges and grips |
| Environment | Frontier set dressing: repaired structures, cargo, cable runs, signage on rugged architecture |
| VFX | Ability effects that read in third person at long range; how tactical abilities are distinguished from damage |
| UI / HUD | Legend reveal and lobby presentation; ping-like world markers (for our command markers) |
| Tech art | Hand-painted vs procedural wear: note where wear appears and how it is kept low-noise at distance |
| Animation | First-person reload and inspect animations that show off the gun; character weight and gait differences between body types |

**Cyberpunk 2077 — neon, chrome, holograms, density, glitch**

| Department | Collect (described, not copied) |
| --- | --- |
| Character | Cyberware design language: where chrome meets skin, port and jack placement, how augmentations read as designed objects (study clean examples only, not body horror) |
| Weapons | Neon trim and holo readouts on weapon bodies; smart-gun display ideas for our chip holo labels |
| Environment | Megastructure stacking, skyline silhouettes, signage density by height, corporate vs street district contrast (feeds Concord vs Syndicate) |
| VFX | Glitch and scanline vocabulary: block displacement, channel split, timing of bursts (for Hex and the Uplink) |
| UI / HUD | Holographic panel treatments: keylines, chamfers, scanline textures; note where they hurt legibility so we avoid it |
| Tech art | Neon bloom behaviour against dark surfaces; how emissive signage stays readable in fog; colour grading at dusk and night (for Surge II and Drought LUTs) |
| Animation | Hologram flicker and boot-up timings; cyberware activation moments |

**Mana-tech (our own layer; supporting reference: Arcane)**

| Department | Collect (described, not copied) |
| --- | --- |
| Character / Weapons | Crystal-in-machine joins: claws, cages, cables feeding a crystal; how a magical object is made to look engineered |
| Environment | Ancient crystal ruins as a base layer under newer construction |
| VFX | Rune-drawing as an effect language; crystal internal glow and swirl |

**Audio:** audio-director owns its own reference board; this board notes only the visual mood
audio should match (choral-airy for mana, heavy-metallic for machines, digital-crackling for glitch).

---

## 15. Open Questions for the Owner

| # | Question | Decision taken (pending owner) |
| --- | --- | --- |
| A1 | Team colours absolute (Concord always blue) or relative (my team always blue)? | Absolute by default; Relative as an option |
| A2 | Damage numbers on by default? (UX decision mirrored here) | On, compact; can be turned off |
| A3 | ~~Ryker's rifle name collides with Vanguard waves~~ | Resolved in consistency pass 2026-10-02: renamed **Breakline AR-7** |
| A4 | Environment outlines (post edge-detect) | None in VS; Alpha experiment with a < 0.5 ms budget |
| A5 | Performance budgets in §10.6 | Proposed; technical-director to ratify in `technical-preferences.md` |
| A6 | ~~Pillar 3's design test vs C15's 4 commands~~ | Resolved in consistency pass 2026-10-02: Pillar 3 now reads "more than four squad commands" |
| A7 | ~~Elite (Rewrite) scale differs between GDDs~~ | Resolved in consistency pass 2026-10-02: ×1.3 everywhere |
| A8 | How much Cyberpunk 2077? ("a bit") | Accent only: neon trims on heroes/guns below bloom, city neon above 4 m in lanes, full density only in HQs, Armory, skyline and menus (§4.6). Owner may ask for more in HQs or less on heroes |
| A9 | Time of day escalates to blue hour at Surge II (skyline neon on) | Adopted, with a character exposure floor of 70% of Skirmish (§2.3); fallback is to keep late afternoon all match and only light the skyline |
| A10 | Proportions moved from 7 to ~7.5 heads to sit closer to Valorant/Apex | Adopted; anime faces and enlarged hands/feet/weapons kept |
| A11 | Hero backstory hooks written into the kits (§5.2: Vesper ex-Foundry choreographer, Sable ex-courier, Juniper Pumpworks kid, Ryker ex-Shardline Guard, Brannoc rebuilt miner, Liora clinic medic, Hex signal streamer) | Proposed by art for visual storytelling; narrative owner to confirm or replace (art will keep the props, re-theme the story) |
