# Hero Art Bible — Toon Rigged Heroes (W13 pilot)

Status: PILOT (Ryker Vance, Vesper Loom). Owner reviews before the other 5 heroes.
Parent docs: `design/art-bible.md` (§3.3 role shapes, §4.7 signature colours, §5.2
silhouettes), `design/gdd/heroes.md`, `design/ux/mockups/v0.9/README.md` (UI palette).
This document replaces the "box model" look of `HeroModelBuilder` for heroes that have a
rigged `.glb`; it does not change any gameplay rule.

## 1. Style rules (toon / cel)

| Rule | Value | Why |
|---|---|---|
| Cel bands | 3 tones: shadow (x0.55), mid (x0.85), lit (x1.0); hard steps, 0.04 smoothing | Comic read, no muddy gradients at range |
| Specular | none on cloth/skin; one hard 2-tone glint band on chrome only (vertex channel) | Chrome is the one "shiny" read (art-bible §3.1) |
| Rim light | view-space fresnel, power 3, 0.35 strength, tinted by team colour | Separates the hero from dark ground ink `#0B1015` |
| Outline | inverted hull (`next_pass`), 1.4 mm world grow + small distance term, colour `#14161C` | Works on skinned meshes; no post-process cost; per-hero toggle |
| Team colour | ONE accent stripe system per hero (vertex channel `team`), replaced at runtime by `team_color` shader param; emissive variant for visor/thread glow | 15-25% coverage rule (art-bible §4.3) without per-team assets |
| Palette | <= 5 flat colours per hero + skin + team: signature (<= 30%), secondary, two neutrals, one chrome | Limited palette = comic read; repeats art-bible §4.7 |
| Value contrast | lit body mean value 0.35-0.65; never darker than the UI rail `#0D1318` + 0.15 | Heroes must read on the premium-dark UI and on night lanes |
| Readability at 30 m | silhouette hook visible as >= 6 px at 1080p / 90 deg FOV; team stripe >= 4 px | The 30 m check is done in the turntable "far" shot |

UI fit (v0.9 premium-dark): ground ink `#0B1015`, brass accent `#C2A267`, text ivory
`#ECE6D6`. Hero portraits sit on ink, so every hero needs one light value block (bone, gold,
chrome) in the upper third and the rim light; no hero uses ink-black as a large area.

## 2. Proportions

- ~7.5 heads, slightly heroic: shoulders 2.1 heads wide (male) / 1.8 (female), hands and
  feet +10%, head -5% from the base, legs = half the height.
- Heights follow the art bible (Sable 1.70 m smallest, Brannoc 2.2 m tallest); Ryker 1.85 m,
  Vesper 1.88 m (tall, slender).
- Pose language: upright V for soldiers, lifted chin and open chest for commanders.

## 3. Budgets

| Budget | Value | Source |
|---|---|---|
| Hero tris in view (LOD0, incl. 3P weapon) | 8k-15k (hard cap 30k, `ModelCatalog.HERO_TRI_BUDGET`) | this brief / art-bible §10.6 |
| Skeleton | <= 32 bones (fingers merged to the hand, face merged to the head) | skinning cost x 6-12 heroes |
| Surfaces per hero | 1 (one toon material + outline pass) | draw calls: 2 per hero |
| Textures | none: flat vertex colours + a per-vertex channel id in UV0 | no photo textures; zero texture memory |
| glb size | <= 3 MB each | repo size |
| Frame time | 6 rigged heroes must stay within +1 ms of the box models | measured in the pilot report |

### Vertex channel convention (UV0.x)
`channel = floor(UV.x * 8)`: 0 flat cel, 1 team accent (cel), 2 emissive (vertex colour),
3 team emissive (visor, threads), 4 skin (softer shadow band), 5 chrome (cel + glint).
UV0.y is unused (0.5). Colour lives in `COLOR_0`.

## 4. Pilot heroes

### Ryker Vance — Soldier (baseline)
- **Silhouette:** upright V-taper; the one oversized LEFT pauldron with a rising antenna fin
  is the hook (asymmetric read from front and side); closed helmet with a horizontal visor bar.
- **Palette:** field olive `#4E5A45` (signature, armour), bone `#E3DCC8` (secondary, pauldron
  face, helmet top), gunmetal `#2F333B` (suit), rubber `#232428` (boots/gloves), chrome
  `#C9D4E2` (right forearm stim port). Team: visor bar (emissive) + chest/pauldron stripe.
- **Gear:** diagonal grenade bandolier, chest plate, belt pouches, knee pads, chrome right forearm.
- **Weapon:** Breakline AR-7 — bulky full-auto rifle, top rail, big receiver, straight mag.
- **Body language:** compact, weight forward, rifle at low-ready in idle.

### Vesper Loom — Commander / Minionmancer
- **Silhouette:** inverted triangle (high wide collar, narrow waist), long legs, long
  asymmetric coat split into ribbon tails at the back; the hook is the **Loom halo**: four
  chrome spindle arms behind the shoulders in a semicircle with violet crystal tips, linked by
  glowing threads to her fingertips.
- **Palette:** plum `#5B2A6E` (signature, coat), spool gold `#D9A441` (secondary: braid wrap,
  coat trim, spindles), ink-plum `#2A1E33` (bodysuit), chrome `#C9D4E2` (thimbles, spine rig),
  violet mana `#B07CFF` (crystals, emissive). Team: collar lining + thread glow.
- **Hair:** sharp bob with one long gold-wrapped braid.
- **Weapon:** Threadcaster — long-barrel semi-auto mana carbine, chrome receiver, spindle drum.
- **Body language:** tall, chin up, off hand free and open (conductor gesture) in idle and casts.

## 5. Animation set

`idle, walk, run, strafe_l, strafe_r, run_back, crouch, jump, fall, aim (upper), shoot (upper
one-shot), reload (upper one-shot), cast_0..cast_3 (one-shot per skill slot), hit, death`.
Driven by `RiggedHeroModel` through an `AnimationTree` (see §6): locomotion blend by
replicated speed / direction, airborne from `grounded`, upper-body aim always on (pitch
additive via spine bones), shoot from `shot_received`, cast from `skill_cast_received`,
death from `dead`.

## 6. Pipeline (rebuild)

See §7 for commands. The base and its licence are recorded in
`assets/models/heroes/LICENSES.md`.
