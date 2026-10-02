# Art Bible: Cybergram

> **Status**: Draft — authored autonomously (`modes.automation: autonomous`) by art-director with technical-artist input
> **Owned By**: art-director
> **Last Updated**: 2026-10-02
> **Art Director Sign-Off (AD-ART-BIBLE)**: Not yet reviewed
> **Binding sources**: `design/gdd/game-concept.md` § Canon (C1–C18), `/ideas` (owner notes)
> **Companion**: `design/ux/hud.md` (screen-space UI). This doc owns the world, characters, weapons, VFX and the art pipeline.

This bible follows the nine-section template order (§1–§9) and adds project-specific
sections (§10–§14) that the brief requires: weapon socket system, VFX language,
Godot technical art direction, the vertical-slice asset list and the placeholder strategy.
Decisions are made, not offered; open items that need the owner are in §15.

---

## 1. Visual Identity Statement

**The one rule:** *"Bright anime heroes on a readable battlefield: every pixel that
can kill you has a team colour and a shape; everything else steps back."*

When any visual choice is ambiguous, pick the option that makes **team, threat and
progress** easier to read at 30 m through a first-person camera. Beauty is spent on
heroes, guns and the Uplinks; the playfield is calm by comparison.

### 1.1 Visual Pillars

| # | Visual pillar | Design test | Serves game pillar |
| --- | --- | --- | --- |
| V1 | **Read the Fight First** | If an effect, prop or texture competes with an enemy silhouette for attention, it gets darker, less saturated or smaller. Characters always out-contrast the environment behind them. | P2 Shooter Hands |
| V2 | **The Front Is Painted on the World** | Ownership of every hardpoint is visible in-world (banners, floor rings, Barricades, light colour) and matches the HUD. If a state exists only on the HUD, add a world tell. | P1 The Front Is the Story |
| V3 | **Power You Can See** | Every purchased upgrade changes a mesh, a glow or a muzzle effect. If two tiers of an upgrade look the same at 20 m, the higher tier gets a bigger silhouette change, not just more glow. | P4 Power You Can See |
| V4 | **Squads Are Small and Loyal** | Wardlings are knee-to-waist height, simple and cute, with a team-coloured core. If a Wardling ever reads as a hero at a glance, cut its height or detail. | P3 Your Squad at Your Heels |
| V5 | **Magic Glows, Machines Clank** | Mana is emissive, additive, rounded and blooms; mechanical is opaque, sparky, angular and never blooms. Never mix the two vocabularies on one effect. | C16 resource types |

---

## 2. Style Target & Mood

### 2.1 Style Target

**3D cel-shaded anime/cartoon, futuristic fantasy.** Two to three hard light bands,
a coloured shadow tone rather than black, crisp ink outlines on characters and weapons,
painted-flat textures with hand-placed shading accents, and emissive mana as the only
light source that is allowed to bloom.

| Touchstone | What we take | What we avoid |
| --- | --- | --- |
| **Overwatch** | Hero silhouette discipline, chunky readable proportions, ally/enemy outline language, ability telegraph conventions | Its semi-realistic PBR materials; we stay flatter and more "drawn" |
| **Genshin Impact** | Cel ramp + rim-light character shading, anime faces, elemental colour coding, flowing cloth tails | Pastel low-contrast environments and lots of soft particles, which kill FPS readability; we use a darker, calmer playfield |
| **Arcane** | Painterly environment surfaces, hextech crystal-in-machine design language (the core of our weapon sockets), dramatic coloured lighting | Gritty texture noise and heavy grading; our surfaces stay clean at distance |
| **Valorant** | Readability rules: simple flat environment colour blocks, strong enemy highlight, clean ability shapes, low clutter | Its muted realism in characters; we want anime expressiveness |
| **Guilty Gear Strive / Hi-Fi Rush** | Proof that real-time cel shading with inverted-hull outlines holds up in motion | 2D-faked camera tricks that don't work with a free FPS camera |

### 2.2 Mood per Game State

| State | Emotional target | Lighting character | Descriptors | Energy |
| --- | --- | --- | --- | --- |
| **Deploy (0:00–1:00)** | Anticipation, "gear up" | Golden-hour key light, HQ interiors warm-lit by Foundry and Armory screens | busy, bright, mechanical, hopeful | Medium |
| **Skirmish (1:00–15:00)** | Clear, fast, competitive | Clean midday sky, high sun, crisp shadows, Leyfall mana-sea glows violet below | clear, open, airy, legible | Medium-high |
| **Surge I / II** | Escalation | Sky shifts warmer per Surge (key light −400 K, sky saturation +10%), Leyfall glow intensifies, lightning in distant cloud-shards | charged, louder, hotter | High |
| **Mana Drought (45:00+)** | Scarcity, desperation | Leyfall dims, sky desaturates 20%, Uplink beams flicker, ambient particles thin out | thin, tense, fading | High |
| **Uplink Exposed** (local) | Siege, danger | Spire shield shell gone, warning strobes in owner colour around the HQ, beam turns jagged | alarmed, broken, urgent | Very high |
| **Sudden Death** | Arena duel | Mid Plaza isolated by a violet Leyfall ring wall; outside the ring is desaturated 60% | stark, gladiatorial, focused | Maximum |
| **Victory / Defeat** | Release | Victory: the enemy Uplink goes dark, your beam flares white-gold. Defeat: your Uplink collapses, the world desaturates, mana drains from your guns | triumphant / hollow | Spike → calm |
| **Menus / Lobby** | Identity, collection | Studio-lit hero turntables in a hangar on a city-shard, faction colour backlight | stylish, calm, premium | Low |

Each in-match state must be identifiable from a single screenshot without HUD (QA test).

---

## 3. Shape Language

### 3.1 Global Grammar

- **Circles / soft curves = mana, support, safety** (Uplink rings, Mender Wardlings, heal effects, Hold zones).
- **Squares / blocks = mechanical, defence, structure** (Barricades, Brannoc, Supply Caches, Plant cradles).
- **Triangles / spikes = threat, offence, breach** (Strikers, damage abilities, Breach generators, enemy telegraph edges).
- Characters use **one dominant shape + one accent**; the environment uses **large calm shapes with detail only at eye level**.
- Proportions: heroes are ~7 heads tall (anime-heroic, slightly enlarged hands, feet and weapons); Wardlings 2–3 heads tall (chibi).

### 3.2 Per Faction (cosmetic sides, C-Faction rule)

| | **Azure Concord** | **Ember Syndicate** |
| --- | --- | --- |
| Core shape | Circle and hexagon lattices, long tapering verticals, arches | Chevrons, trapezoids, notched teeth, stacked horizontals |
| Construction | Seamless shells, floating parts held by hard-light, glyph inlays | Riveted plates, exposed pistons, welded seams, furnace grilles |
| Material set | Porcelain white, brushed gold, blue glass, holo-glyph emissive | Blackened iron, brass, orange-hot furnace glow, hazard paint |
| Value key | **Light** (high-value surfaces, dark accents) | **Dark** (low-value surfaces, hot accents) |
| Glyph motif | Six-point "ring-and-ray" glyph | Three-tooth "cog-and-flame" glyph |

The value key is the most important colour-blind backup in the game: Concord things are
light-bodied, Syndicate things are dark-bodied, at every scale (heroes' faction trims,
Wardling shells, Barricades, banners, HQs).

### 3.3 Per Role

| Role | Dominant shape | Silhouette rule |
| --- | --- | --- |
| Minionmancer (Vesper) | Inverted triangle + orbiting circles | Floating elements around the body |
| Infiltrator (Sable) | Thin diagonal | Lowest, narrowest profile; trailing cloth |
| Trapper (Juniper) | Square on top of a thin base | Top-heavy pack silhouette |
| Soldier (Ryker) | Upright V-taper | The "default soldier" every other hero contrasts against |
| Tank (Brannoc) | Big square | Widest and tallest; shield arm breaks symmetry |
| Healer (Liora) | Circle | Halo ring; flowing curved hem |
| Hacker (Hex) | Hunched square + antennae | Oversized hood/headset; floating rectangular screens |

---

## 4. Color System

### 4.1 Primary Palette

| Token | Hex (sRGB) | Meaning |
| --- | --- | --- |
| `azure_core` | `#2E86FF` | Concord team colour (rims, cores, banners, territory) |
| `azure_light` | `#EAF3FF` | Concord body value (porcelain) |
| `concord_gold` | `#E8B547` | Concord accent trim (never used as a signal colour) |
| `ember_core` | `#FF5A1F` | Syndicate team colour; orange-red, not pure red, to keep luminance for protanopia |
| `ember_dark` | `#1E1A1C` | Syndicate body value (blackened iron) |
| `leyfall_violet` | `#8E5CFF` | Raw mana / the Leyfall / neutral (unowned Mid, Sudden Death ring) |
| `halcyra_stone` | `#B9B2A6` | Neutral environment base (ancient crystal ruins, plazas) |

**Mana colour rule:** raw mana is white-core violet (`leyfall_violet`). Once broadcast by
an Uplink (the Cybergram), mana takes the **team colour on its outer edge** and keeps a
**white-hot core**. So every mana projectile, beam and shield is "white core + team rim".
Crystal families (§7) may tint the core band, never the rim.

### 4.2 Semantic Colours (non-team)

| Token | Hex | Use | Never use for |
| --- | --- | --- | --- |
| `heal_verdant` | `#4CE38A` | Healing, Mender, heal numbers | Team identity |
| `crit_solar` | `#FFD447` | Weak-spot hits, critical hit markers | Ally/enemy |
| `aether_violet` | `#B07CFF` | Skill points, Resonance/level | Neutral ownership (that's `leyfall_violet`, desaturated) |
| `warning_white` | `#FFFFFF` + black stroke | Danger telegraph cores, low-HP pulses | Decoration |
| `lumen_gold` | `#FFC93C` | Money pickups and HUD | — |

### 4.3 Team Colour Policy

- **Default = absolute faction colours.** Concord is blue, Syndicate is orange-red, for
  everyone. This keeps the map, VO ("they took blue North Outer") and world dressing
  consistent for both teams (V2).
- **Relative mode (option):** ally = `azure_core`, enemy = `ember_core` regardless of side.
  Team colour is a single global shader uniform (`team_tint`) per team, so relative mode
  is a per-client uniform swap; faction *shapes and value keys* stay true, so faction
  identity survives.
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
Coblis/Color Oracle simulation on the five test screenshots listed in §11.6.

### 4.5 Area Temperature

- Concord half of Halcyra: cool key light (6500 K), white stone, blue shadows.
- Syndicate half: warm key light (4800 K), dark metal, plum shadows.
- Mid row and Mid Plaza: neutral (5600 K), violet Leyfall bounce from below.
- Shadow tones are always tinted (blue-violet), never neutral grey or black.

---

## 5. Character Design Direction

### 5.1 Telling Things Apart

- **Hero vs Wardling:** heroes ≥ 1.75 m, Wardlings ≤ 1.1 m (Sentinels 1.4 m, but static and tripod-shaped). Wardlings never carry hero-shaped guns.
- **Ally vs enemy:** value key + outline weight + nameplate glyph (§4.4). Faction trims are 15–25% of a hero's surface: enough to read, not enough to change the hero.
- **Which hero:** each hero has one **silhouette hook** that survives at 40 m (64 px tall at 1080p, 90° FOV) and is recognisable as a solid black shape (QA "shadow test").
- **Expression:** anime faces with large readable eyes, but faces are the least important read in FPS; pose and props carry personality. Idle and emote poses exaggerate the silhouette hook.

### 5.2 Hero Silhouettes

**Vesper Loom — Minionmancer (Mana).** A tall, slender puppeteer in a long asymmetric
coat split into ribbon-tails at the back. The hook is a **floating "Loom halo"**: four
spindle-arms hovering behind the shoulders in a semicircle, linked to the fingers by thin
glowing threads that pull taut when she commands. Inverted-triangle torso (wide collar,
narrow waist), long legs. Her gun, the *Threadcaster*, is a long-barrelled semi-auto mana carbine
with a spindle drum as its conduit. Her ultimate makes the halo flare open to eight spindles,
so the threat is visible from across a lane before the Wardlings change.

**Sable — Infiltrator (Mana).** The smallest hero (1.70 m), always in a forward-leaning
crouch-ready pose. The hook is a **long split scarf** whose two tails trail 1.5 m behind
her, plus a single swept-back hood horn on one side, so the silhouette is a thin diagonal
with a streamer. A half-mask with a slit visor; armour minimal and matte. Weapon: a compact
twin-grip mana SMG with a tanto-blade underslung. While phased (Barricade passage), her
body becomes a dark glass silhouette with only the scarf tails and visor slit glowing in
her team colour, so stealth is never fully invisible to an attentive enemy.

**Juniper Quill — Trapper (Mechanical).** A medium build carrying a **huge square
tool-pack** taller than her head, with a cable spool wheel on one side and a folded
mine-launcher arm on the other: a top-heavy box on slim legs. Brass goggles pushed up into
a messy bun stuck with quill-darts (the tripwire anchors). Utility belt of trap
canisters, each with a stripe for its type. Weapon: the *Tackhammer*, a lever-action rail-tack
rifle with a box magazine and a visible spool feeding tripwire line along the frame.

**Ryker Vance — Soldier (Mechanical).** The baseline every other hero is measured against: an
upright V-taper in light combat armour. The hook is a **single oversized left pauldron**
with a rising antenna fin, plus a closed helmet with a horizontal visor bar. A grenade
bandolier crosses the chest diagonally. Weapon: the *Breakline AR-7*, a bulky full-auto rifle with a top
rail and a big receiver that carries the chip rack; it is the most "classic gun" in the cast
so new players have an anchor.

**Brannoc — Tank (Mechanical).** 2.2 m, the widest silhouette in the game: a block of plate
armour with a small head sunk between huge square shoulders. The hook is the **right arm
shield generator**, a slab-shaped forearm emitter that unfolds into the shield wall,
making him visibly asymmetric. A furnace vent on the back glows (team colour) and breathes
heat. Weapon: the *Ironmaw*, a short, fat pump scattergun with a jaw-shaped
muzzle, held low at the hip. He
walks with a heavy, grounded gait so his tankiness reads in motion too.

**Liora Vale — Healer (Mana).** Built from circles: a flowing round-hemmed long coat, very
long hair in a loose ribbon, soft rounded armour. The hook is a **halo ring** orbiting her
back at shoulder height, carrying two docked Med-Pack drones like lantern beads; when she
throws one, the ring visibly has a gap until it recharges. Weapon: the *Halo Repeater*, a
full-auto mana rifle with a glass bulb conduit that fires slow, glowing bolts.

**Hex — Hacker (Mana).** A slouched, hunched figure in an oversized hoodie with a
**cat-ear headset** whose antennae stick up past the hood, giving a horned square silhouette.
Two to three floating holo-panels orbit the wrists and flicker with glitch scanlines (team
colour, chromatic offset). Shorts and oversized sneakers: the cast's most cartoonish
proportions. Weapon: the *Glitchcaster*, a chunky mana pistol-SMG whose barrel is a stack of
offset hex rings that visibly misalign when firing.

### 5.3 Wardlings (C15)

**Base form:** a small hover-biped construct ~0.9 m tall: rounded shell torso, stubby arms,
two short legs that hover-skip, a single visor eye, and a **mana core** in the chest that is
visible from front and back (the core is the team-colour signal; it pulses when the Wardling
takes damage). Faction skin: Concord = white porcelain shell + gold trim; Syndicate = black
iron shell + brass rivets. Each bound Wardling shows a small slot-number glyph (1–7; Vesper
carries up to 7) above it to its owner only, matching the HUD squad strip.

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
| III | Crown of three crystal shards over the head + short trailing mana ribbon, 3 pips | Core white-hot with team rim, faint bloom | 1.15 |

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
(below).

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
(Concord lattices on their half, Syndicate scaffolding on theirs). The visual front line
literally changes the dressing: when a hardpoint flips, its banners, floor ring, Barricade and
local light colour swap to the new owner over 1.5 s.

### 6.2 Lanes

| Lane | Biome dressing | Landmark |
| --- | --- | --- |
| **North** | High spire-district: bridges over the Leyfall, wind banners, gatehouses | **Belfry Ruin** (N-Mid), a ruined crystal bell tower; Lattice Bridge / Rivet Span (the 90 m sightline) |
| **Center** | Market arcology: stalls, awnings, holo-signs (dim, non-signal colours), indoor atria | **The Spindle** (C-Mid), a raised dais in Mid Plaza (Sudden Death arena) |
| **South** | Industrial docks: docked skiffs, canal locks, mana pipelines, shallow mana-water | **Leyfall Pumpworks** (S-Mid), a two-level pump hall |

Hardpoint names, positions and the "Shardline Front" layout are owned by `match-flow-and-map.md` §3.2–3.3.

Rule: every lane must be identifiable from any screenshot in it, through a landmark plus a
dominant prop family; floor colour stays neutral `halcyra_stone` so characters pop. Flank
paths are visually narrower and darker with lit floor arrows pointing toward the lane they join.

### 6.3 Hardpoint Task Types — distinct at a glance (C4)

Each task type has a unique **skyline silhouette** readable at 80 m, a unique floor shape,
and a matching HUD/map icon. Ownership colours the emissive parts.

| Task | World object | Skyline silhouette | Floor shape | Icon |
| --- | --- | --- | --- | --- |
| **Hold** | *Holdstone*: a 12 m pillar of light rising from a ring plinth | Single vertical beam | Large circle with 12 segments that fill as progress | Circle |
| **Plant** | *Charge Cradle*: a twin-pronged pylon with an open socket; the carried Mana Cell is a glowing capsule on the carrier's back | Tuning-fork "Y" pylon | Square pad with corner brackets | Square with down-arrow |
| **Breach** | *Ward Generator*: a hex-faceted shield dome over a spinning core | Dome bubble | Hexagon with spikes at the vertices | Triangle with crack |

Progress is shown in-world too: Holdstone ring segments fill; the Cradle's prongs light from
base to tip as the cell charges; the Generator dome cracks in three stages, then shatters.
Hardpoints that cannot yet be attacked (C3 prerequisite) show their emissives dimmed and a
locked glyph on the plinth.

### 6.4 Barricades, Garrisons, Supply Caches (C5)

- **Barricade:** a wall across the lane's main path. Concord style = hard-light lattice
  panes in a white frame; Syndicate style = riveted blast gate with an ember grid. To the
  owning team it renders 50% translucent with forward chevrons (passable); to enemies it is
  opaque with serrated hostile trim. Three damage states (intact / cracked / failing with
  sparks or mana leaks), then collapse into rubble that stays as cover.
- **Garrison Sentinels:** placed on raised sockets at the hardpoint's corners; their sockets
  stay visible (empty, dim) while a Sentinel respawns.
- **Supply Cache:** a squat mechanical crate with an ammo-belt icon and brass trim, always
  mechanical in style regardless of faction (it serves Mechanical guns).
- **Forward Beacon (held Mid):** a tall team-coloured banner-mast with a spawn halo on the
  ground; the halo dims and strobes when "under attack" (spawning disabled).

### 6.5 HQ Set-Piece and the Mana Uplink (C6, C7)

The HQ is a fortified shard with a clear front gate facing the Inner hardpoints. The **Mana
Uplink** is the game's dominant landmark: a 45 m crystal-and-steel broadcast spire, a giant
crystal held in a frame of rings, firing a team-coloured beam into the sky that is visible
from anywhere on the map (each team's beam orients players toward home/enemy).

| Uplink state | Visual |
| --- | --- |
| Protected | Hexagonal shield shell around the base; frame rings rotate smoothly; steady beam |
| **Exposed** | Shield shell shatters and stays gone; rings stop and judder; beam turns jagged; warning strobes ring the HQ in owner colour; enemy outline on the core becomes damageable highlight |
| Integrity 75/50/25% | Crystal cracks in three permanent stages, chunks fall, beam narrows (damage is permanent, so are the cracks) |
| Destroyed | Beam collapses downward, crystal goes grey, every mana effect on that team fizzles out |

Supporting set-pieces: **Sanctum** (spawn chapel with a healing glow and a 10 m floor ring
marking the anti-camp zone), **Foundry** (a conveyor of half-built Wardlings on cradles; your
squad hops off and joins you), **Armory** (weapon racks and a glowing crystal/chip display
case with a workbench where the gun-socketing animation plays).

---

## 7. Weapon Art & the Visible Upgrade System

Visible weapon growth is the owner's top visual request (`/ideas`) and Pillar 4. Rules,
lines, prices and tiers are owned by `design/gdd/weapons-and-mods.md` (§3.6–3.8); this
section owns how they **look**. Every weapon uses the same four mounts, and mount meshes are
shared per line (placed by per-weapon scale/offset presets), so art cost is *lines × tiers*,
not *lines × tiers × weapons*.

### 7.1 Mount Layout (all 7 weapons)

| Socket (marker) | Position | Visible in FP view | Changes |
| --- | --- | --- | --- |
| **Core** (`socket_core`) | Top/heart of the receiver, just ahead of the sight | Always (centre-bottom of screen) | The gun's idle glow; muzzle flash takes the line's family hue |
| **Barrel** (`socket_barrel`) | Muzzle and barrel shroud | Yes, the leading tip | Lens rings (Crystal) or shroud/rail (Chip); ring count = tier; tracer length/shape |
| **Frame** (`socket_frame`) | Grip, stock and camera-facing side plates | Yes, left edge | Side crystals pulse during mana regen (pulse speed = regen rate) / stock LED counter = rounds left |
| **Chamber** (`socket_chamber`) | Mana conduit (Mana) / magazine window (Mech) | Yes | Conduit glow / tinted rounds = loaded **Ammo Type**; Ammo Mod adds a small rune/cap on the conduit or mag base |

Empty sockets are visible as open brass claws (Mana) or empty chip slots with a dark LED
(Mechanical), so players see what they *could* buy. Third-person mount meshes are scaled
1.3× relative to the viewmodel (a standard cheat so they survive distance).

### 7.2 Crystals (Mana guns: Halo Repeater, Threadcaster, Whisperfang, Glitchcaster)

- Physical, faceted, emissive meshes gripped by claw mounts, all using `spatial_fx_crystal`:
  interior parallax glow, fresnel rim, **core band in the line's family hue**, slow internal swirl.
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
  metallic "chk", a ring of light runs down the barrel, and the next shot plays a one-off
  brighter flash. The same animation drives the Armory turntable preview (HUD doc §10).
- Mana state is diegetic: crystal glow tracks the current pool %, and **Burnout** turns every
  crystal dark grey with a crackle of sparks until regen starts.

### 7.3 Chips (Mechanical guns: Breakline AR-7, Ironmaw, Tackhammer)

Chips are cartridge-like cards slotted into a **chip rack** with an LED strip; every line also adds
a physical module so the change is a silhouette, not just an LED.

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

### 7.4 Tiers and the FPS-Distance Read

Tier names per GDD: Crystals **Shard / Facet / Heart**, Chips **Mk I / Mk II / Mk III**. Tiers
read by **size, facet/fin count, glow and idle animation**, never by colour.

| Tier | Crystal | Chip | 3P read at 20–40 m |
| --- | --- | --- | --- |
| I | Thumb-size shard, low glow | Single card, 1 LED | Socket looks filled; no bloom |
| II | Twin facets + 1–2 orbiting motes, slow pulse | Card + heat-sink fins + LED strip | Visibly larger; faint bloom (Mana) |
| III | Large heart crystal with a floating halo ring and sparse particles | Full module, exposed core, moving parts | Halo/moving module adds ≥ 15 cm of silhouette, readable at 40 m |

- Core Tier III adds a **halo-ring muzzle flash every 5th shot** (every shot on Ironmaw and Tackhammer, per GDD).
- At > 25 m we only guarantee the read of *how many sockets are filled* and *which are Tier III*;
  finer detail comes from the scoreboard build icons and the death recap (HUD doc §8, §9).
- Acceptance (from GDD): QA can identify each socket's tier from 20 m in third person on a **greyscale** screenshot.
- Cosmetic VFX unlocks may recolour Core/Barrel/Frame family hues only; tier size/glow and
  ammo-type impact VFX are gameplay information and never recolourable.

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

| | **Mana** (Mana heroes, Wardlings, Uplink, crystals) | **Mechanical** (Mechanical heroes, chips, traps, Supply) |
| --- | --- | --- |
| Blend | Additive, emissive HDR > 1.0, blooms | Alpha-blended / opaque, HDR ≤ 1.0, never blooms |
| Shapes | Rounded ribbons, rings, hex glyphs, motes | Hard sparks, smoke puffs, shell casings, debris chunks |
| Motion | Swirl, ease-in-out, hovering | Ballistic, gravity, fast decay |
| Colour | White core + team rim (+ family core band) | Neutral brass/steel/smoke + team-coloured *decal or light* only |
| Audio pairing | Chimes, hums, choir pads | Clanks, gunshots, servos |

### 8.2 Team-Coloured Effects and Telegraphs

- **Every hostile area effect** has a team-coloured border with serrated outward ticks and a
  low-opacity fill (≤ 25%); allied areas have a smooth thin border and ≤ 12% fill; the
  player's own effects ≤ 8% fill. Damage zones add a white inner pulse every 0.5 s.
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

### 8.3 Budgets

Per effect: ≤ 64 particles, ≤ 2 overdraw layers at screen centre, ≤ 1 dynamic light (no
shadows) and ≤ 1.0 s lifetime for hit effects. Wardling effects use half budgets. Global
per-frame cap enforced by an effect-priority manager: enemy telegraphs > own feedback >
ally effects > ambient.

---

## 9. UI/HUD Visual Direction (summary; spec in `design/ux/hud.md`)

- **Screen-space HUD** with **diegetic echoes**: ammo/mana is also shown on the gun (the core
  crystal dims as mana drains; mechanical mag has a back-counter LED); hardpoint progress is in-world.
- **Typography:** display face *Chakra Petch* (OFL) for numbers and headers; body face *Noto
  Sans* (OFL, wide script coverage for localisation). Minimum 18 px at 1080p; numbers bold.
- **Iconography:** flat two-tone icons on a hexagon (mana) or rounded-square (mechanical) frame;
  team-coloured edges, white glyphs. Task icons match §6.3 exactly.
- **Animation feel:** snappy (≤ 150 ms in, ≤ 250 ms out), slight overshoot on gains, no motion on
  steady states. All motion respects the Reduced Motion setting.
- **Conflict decided:** art wanted translucent glassy panels over the world; UX readability
  won: panels are ≤ 65% opaque dark (`#0B0E18`) with a 1 px light keyline, and text never sits
  directly on the world.

---

## 10. Godot Technical Art Direction (Godot 4.7, Forward+)

> Engine reference in `docs/engine-reference/godot/` is verified for 4.6; 4.7 deltas are
> **unverified**. Items below marked ⚠ must be checked against the 4.7 docs before
> implementation.

### 10.1 Toon Shader

- One master spatial shader for characters/weapons/Wardlings (`spatial_char_toon.gdshader`)
  and one for environment (`spatial_env_toon.gdshader`), both using a custom `light()` function:
  - Diffuse: `NdotL × attenuation` (shadow included) sampled into a **shared 256×8 ramp texture**
    (8 rows = 8 material ramps: skin, cloth, metal, porcelain, iron, crystal, hair, environment), giving 2–3 hard bands with a tinted shadow colour.
  - Specular: thresholded Blinn highlight; anisotropic strip for hair and brushed metal (masked).
  - Rim: fresnel rim in the light colour on lit side; optional `team_tint` rim on characters at 0.15 strength.
  - Mask texture (RGBA): R = shadow bias (painted AO), G = spec mask, B = emissive mask, A = outline width.
- Emissive is the only route to bloom; artists must not push albedo above 0.9.
- Environment shader skips specular and uses 2 bands only (cheaper; calmer read, V1).
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
| Tonemap | Filmic, exposure tuned per lane | AgX (4.6 contrast/white-point controls) evaluated at VS; pick whichever keeps team colours saturated ⚠ |
| Colour grading | 3D LUT per match phase (Skirmish, Surge, Drought, Sudden Death), blended over 3 s | |
| Glow | On, HDR threshold 1.1, only emissives exceed it | Glow is processed before tonemapping since 4.6 — retune after any engine bump |
| SSAO | Off (painted AO in mask) | Saves ~1 ms |
| SSIL / SDFGI / VoxelGI | Off | Lighting is baked |
| GI | `LightmapGI` baked for static shards; few `ReflectionProbe`s for crystals | |
| Fog | Depth fog tinted `leyfall_violet` for distant shards; volumetric fog only on High and in HQ haze | |
| AA | SMAA 1x default; TAA optional (ghosts outlines) | SMAA available since 4.5 |
| Upscaling | FSR 2 option on low-end | ⚠ check 4.7 options |
| Motion blur / chromatic aberration / film grain | None in gameplay (readability); CA only in Hex glitch effects | |

### 10.4 LOD and Culling

- Mesh LODs auto-generated at import (Godot mesh LOD) for all props and characters; artists may supply hand LODs for heroes.
- Wardlings: two MeshInstances per Wardling (body + outline override) with
  `visibility_range_end` on the outline instance at 60 m; beyond 80 m the body swaps to a 300-tri
  proxy with the core still emissive (the core must always read).
- Third-person crystal/chip meshes: Tier I/II particles off beyond 25 m, Tier III halo kept to 60 m.
- `OccluderInstance3D` on shard architecture; lanes are designed with occluding walls between them.
- Shader Baker (4.5+) enabled for exports to avoid first-use hitches on ability VFX.

### 10.5 Budgets (target: 1080p, 144 fps on a recommended GPU, 60 fps on min spec)

| Category | Tris (LOD0) | Materials | Textures |
| --- | --- | --- | --- |
| Hero (3P) | 30k (max 40k) | ≤ 3 + outline | 2048 albedo, 1024 mask, shared ramp; normal map only for armour |
| Hero first-person arms | 15k | 1 | 2048 |
| Viewmodel weapon | 20k | 2 | 2048 albedo + 1024 mask |
| 3P weapon | 6k | 1 | 1024 |
| Crystal / chip / module | 300–1,000 | shared | 1024 atlas for all families |
| Wardling | 4k (Sentinel 6k) | 1 | 1024 atlas shared by all variants, faction swap via palette row |
| Uplink spire | 80k | ≤ 4 | trim sheets |
| Modular env piece | 200–5k | 1–2 | 2048 trim sheets per faction + neutral |
| VFX texture | — | — | ≤ 512, flipbooks ≤ 1024 atlas |

Scene-level: ≤ 2,000 draw calls and ≤ 3.5 M visible tris in the worst view (team fight
at a Mid with 10 heroes + 50 Wardlings, of which up to 8 Vanguards and 4 Sentinels; the
map-wide AI budget is ≤ 110 per Canon C1); texture memory ≤ 2.5 GB at High; VFX ≤ 1.5 ms GPU.
These are art-side proposals; `technical-preferences.md` still has budgets unconfigured, so
technical-director must ratify them.

### 10.6 glTF Pipeline

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
  material-name prefix (`M_toon_*`, `M_env_*`, `M_crystal_*`) and bakes smoothed normals for outlines.
- **Textures:** PNG sources, imported as VRAM Compressed (BPTC/S3TC), mipmaps on, sRGB for albedo, linear for masks.

### 10.7 Naming

Pattern (from art-director standard): `[category]_[name]_[variant]_[size].[ext]`, lower snake case.

| Category | Example |
| --- | --- |
| Character | `char_brannoc_body.glb`, `char_brannoc_fparms.glb` |
| Weapon | `wpn_ryker_rifle_fp.glb`, `wpn_ryker_rifle_tp.glb` |
| Upgrade | `upg_crystal_solar_t3.glb`, `upg_chip_overclock_t2.glb` |
| Wardling | `wdl_striker_t2.glb` |
| Environment | `env_concord_wall_straight_4m.glb`, `env_neutral_plaza_floor_8m.glb` |
| Prop | `prop_supply_cache_a.glb` |
| Texture | `tex_brannoc_body_albedo_2048.png` (`albedo`/`mask`/`normal`/`emit`) |
| VFX | `vfx_crystal_solar_muzzle_small.tscn` |
| Shader | `spatial_char_toon.gdshader`, `spatial_fx_crystal.gdshader`, `particles_fx_hit.gdshader` (per shader rules) |
| Placeholder | any of the above with suffix `_ph` (§13) |

---

## 11. Asset Standards Checklist (per incoming asset)

1. Passes the **shadow test** (recognisable as a black silhouette at gameplay distance).
2. Uses the master toon shader and shared ramp; no bespoke shaders without technical-artist sign-off.
3. Within §10.5 budget; LODs generated; collision named.
4. Team-coloured parts are driven by `team_tint` (never baked into textures).
5. Correct name, folder, and licence entry (placeholders in `assets/LICENSES.md`).
6. Five readability test screenshots (Mid team fight, Hold in North, Plant in South, Uplink Exposed, Sudden Death) still pass CVD simulation.

---

## 12. Vertical-Slice Asset List (M1)

M1 = the one-lane **Slice Map "Shardline Causeway"** (`match-flow-and-map.md` §3.7: 5
hardpoints using all 3 task types, staged within M1, both HQs, reduced Mid Plaza, one flank loop per half), **2 heroes
(Vesper Loom, Brannoc)**, levels with a reduced skill tree, Lumen shop with the minimal mount pipeline, Surge I, Vanguard waves,
Forward Beacon spawn. Garrisons, Barricades and Supply Caches (M3), Sudden Death (M3), Ryker and Liora (M3), Wardling
variants and the full crystal/chip set (Alpha) are later; the slice includes a minimal read-test of the socket system.

| # | Asset | Quantity | Fidelity in VS |
| --- | --- | --- | --- |
| 1 | Hero 3P models + FP arms: Vesper, Brannoc | 2 + 2 | Final-quality body, 1 faction trim swap |
| 2 | Hero weapons FP + TP (Threadcaster, Ironmaw) with four `socket_*` markers | 2 × 2 | Final |
| 3 | Hero animation sets (locomotion, fire, reload/vent, 4 skills, death, emote idle) | 2 | Final for FP, blockout-plus for TP |
| 4 | Slice mounts per `weapons-and-mods.md` §3.10: Ember Heart + Flux Coil crystals (Threadcaster), Overclock + Quickload chips (Ironmaw), Tiers I–III each; Piercing + Sunder tracers/impacts (no Barrel socket, no Ammo Mods) | 12 mounts + 2 ammo FX | Greybox primitives per GDD; final art for Ember Heart + Overclock as the Pillar 4 read-test |
| 5 | Wardling base form, both faction skins, Tiers I–III; owner sash + Vanguard pennant variants | 1 rig, 3 tier states, 2 class markings | Final |
| 5b | Command world markers: Hold ring, Attack reticle + threads, Go Capture ping column + path ribbon | 4 | Final |
| 6 | Slice Map: 1 lane × 5 hardpoints (Glasswork/Furnace Gate, Signal Market/Scrap Bazaar, Spindle kits), causeways, 2 flank loops, Barricade sockets | 5 nodes | Stylised neutral kit + 1 faction kit each side; full 15-node map is Alpha |
| 7 | Task objects: Holdstone, Charge Cradle + Mana Cell, Ward Generator (3 crack stages) | 3 + cell | Final |
| 7b | Barricade (Concord lattice / Syndicate blast gate), 3 damage states + rubble | 2 | Greybox in M1 (sockets only, inactive); final for M3 when Barricades go live |
| 8 | HQ ×2: Uplink spire (protected/exposed/3 crack stages/destroyed), Sanctum, Foundry, Armory | 2 | Uplink final; rooms stylised kit |
| 9 | Reduced Mid Plaza (r = 25 m); Leyfall ring wall for Sudden Death built in M3 | 1 | Final |
| 10 | Skybox: Leyfall sea, distant shards, per-phase LUTs (4) | 1 + 4 | Final |
| 11 | VFX: 2 heroes × (weapon fire, impact, 4 skills), Vesper Elite/Turned, Rally Beacon heal, Wardling hit/death, capture flip, Uplink damage, Surge transition | ~25 | Final for gameplay-critical, simple for ambient |
| 12 | Shaders: toon (char/env), outline, crystal, team-tint, telegraph decal, Leyfall, LUT grading | 7 | Final |
| 13 | UI kit (scope per HUD doc §19): icons for 2 heroes × 4 skills, task types, ownership patterns, squad command states (F/H/A/C), Vanguard flag, status effects, mount/ammo icons | ~60 icons | Final |

---

## 13. Placeholder-Art Strategy

Code must not wait for art. Placeholder art follows the same pipeline, naming (`_ph`), sockets and
`team_tint` uniform as final art, so swapping is a file replace.

1. **Greybox first (week 0):** CSG/`MeshInstance3D` blockouts with **Kenney Prototype Textures**
   (CC0) grids; hardpoint task objects as primitive stand-ins that already obey §6.3 skyline shapes
   (cylinder beam = Hold, Y-shape = Plant, sphere = Breach).
2. **Characters:** CC0 humanoids from **Quaternius** (e.g. Ultimate Modular Characters / Universal
   Animation Library) or **KayKit** character packs (CC0), recoloured via `team_tint`, plus a primitive
   "hook" bolted on (ring for Liora, slab for Brannoc, spindles for Vesper, pauldron for Ryker) to test
   silhouette rules immediately.
3. **Weapons:** **Kenney Blaster Kit** (CC0) guns with added `socket_*` markers; crystals as
   coloured `PrismMesh`/`SphereMesh` primitives in the right cut shapes.
4. **Wardlings:** capsule + sphere core with emissive team colour, sized per §5.3.
5. **Environment:** Kenney/Quaternius CC0 sci-fi kits for HQ dressing; **Poly Haven** / **ambientCG** (CC0)
   only for skies and reference, never for in-world PBR textures (style mismatch).
6. **Shaders from day one:** the real toon + outline shader runs on placeholders, so readability and
   performance are tested on the true render path from the prototype.
7. **Rules:** no Mixamo or other non-redistributable assets in the repository; every third-party file is
   listed in `assets/LICENSES.md` with source URL and licence; all placeholders live under
   `assets/placeholder/` and a pre-release check fails the build if any `_ph` asset is referenced.

---

## 14. Reference Direction (summary)

| Reference | Take | Avoid |
| --- | --- | --- |
| Overwatch | Silhouette discipline, telegraph conventions | PBR realism, its exact hero archetypes |
| Genshin Impact | Ramp shading, anime faces, elemental crystal colour coding | Low-contrast pastel playfields |
| Arcane | Hextech crystal-in-machine look for sockets, painterly surfaces | Grime and heavy texture noise |
| Valorant | Flat environment, enemy highlight options, low clutter | Muted character styling |
| Battlefield Breakthrough | Front line visible in the world (sector dressing) | Military realism |

---

## 15. Open Questions for the Owner

| # | Question | Decision taken (pending owner) |
| --- | --- | --- |
| A1 | Team colours absolute (Concord always blue) or relative (my team always blue)? | Absolute by default; Relative as an option |
| A2 | Damage numbers on by default? (UX decision mirrored here) | On, compact; can be turned off |
| A3 | ~~Ryker's rifle name collides with Vanguard waves~~ | Resolved in consistency pass 2026-10-02: renamed **Breakline AR-7** |
| A4 | Environment outlines (post edge-detect) | None in VS; Alpha experiment with a < 0.5 ms budget |
| A5 | Performance budgets in §10.5 | Proposed; technical-director to ratify in `technical-preferences.md` |
| A7 | ~~Elite (Rewrite) scale differs between GDDs~~ | Resolved in consistency pass 2026-10-02: ×1.3 everywhere |
| A6 | ~~Pillar 3's design test vs C15's 4 commands~~ | Resolved in consistency pass 2026-10-02: Pillar 3 now reads "more than four squad commands" |
