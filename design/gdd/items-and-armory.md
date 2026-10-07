# Items & Armory v2 (Recipes, Gun Sockets, Open Item Slots)

*Created: 2026-10-07*
*Status: **DRAFT for owner sign-off.** Not canon yet. Until the owner signs off and §9 "Canon changes required" is applied, `weapons-and-mods.md` §3.6–§3.8, `wardlings-and-economy.md` §18–§19, `game-concept.md` C14/C16/Pillar 4 and `design/registry/entities.yaml` stay the source of truth.*
*Brief: `docs/plans/armory-v2-recipes-gear.md` (owner decisions and answers of 2026-10-07).*
*Binding sources: `game-concept.md` Canon C6, C10, C14, C16 and Pillar 4; `weapons-and-mods.md` §3.3–§3.7 and §4 (damage, TTK targets, ammo); `wardlings-and-economy.md` §7 (squad upgrades) and §17–§18 (Lumen curve); `heroes.md` §3.1, §3.4, §5.1–§5.3 (HP, armor, CDR cap, EHP, skill-bonus clamp).*
*Release: one complete release, **protocol 22** (server and clients together).*

**How to read numbers.** Every new price, stat, cap and timing in this doc is a first guess and is marked **[TUNE]**, either on the number or on its table column header. Numbers taken from other GDDs carry their section reference instead and are not tuned here.

---

## 1. Overview

The Armory becomes a League-of-Legends-style shop with **recipes**. Small **Components** (250–400 Lumen) combine into **Assemblies** (800–1,000) and then into **Signatures** (2,400–2,600, one named unique passive each). When you buy an item, the parts you already own are used up and you pay only for the missing parts plus a **combine cost**. Each hero has two kinds of equipment space: the **gun sockets** (Core, Barrel, Frame, and a Chamber holding one Ammo Type and one Ammo Mod), which hold finished weapon parts, and **6 open item slots**, which hold anything else: loose components, and finished body gear for health, armor (vs weapon damage), resist (vs skill damage) and utility. Weapon parts take **Crystal** form on Mana guns and **Chip** form on Mechanical guns (C16). Everything a hero owns is visible: weapon parts on the gun, open-slot items on the hero's body (belt, chest, shoulders, back, head, legs), so you can read any build at a glance (Pillar 4). The shop has three tabs (Recommended, All Items, Item Sets). The release content is 10 Components, 10 Assemblies, 14 Signatures (8 weapon, 6 body gear), all 6 Ammo Types and all 5 Ammo Mods. Squad upgrades and consumables stay as they are and do not use open slots. Everything resets at match end.

## 2. Player Fantasy

*"Same start, my own finish."* At 0:00 two Rykers both buy an Ember Chip. By minute 12 one has an Overclock Core humming on the receiver; the other turned the same chip into a Breaker Bore on the muzzle and wears plated shoulders, because the enemy has a Brannoc and a Bastion Plate. Neither followed a fixed path. The enemy can see both choices from 20 m: the gun's silhouette tells them how it kills, the body tells them how it survives.

| Target aesthetic (MDA) | How this system serves it | Pillar |
| ---- | ---- | ---- |
| **Expression** (primary) | Branching recipes: one component feeds 2–8 finished items. Two Signature picks define your identity. | Pillar 4 |
| **Challenge** | Reading the enemy's gear and answering it (Piercing and Breaker Bore vs plate; Null Veil vs skill burst). | Pillar 2 (aim still decides fights: caps keep gear at ±25% TTK) |
| **Discovery** | The recipe tree and "builds into" lists teach the catalog through play. | — |
| **Sensation** | Each purchase changes the model at once: a part snaps onto the gun or the body. | Pillar 4 |

Self-Determination Theory check: **Autonomy** comes from branching and 2–3 Recommended choices per step, never one path. **Competence** comes from small, frequent steps (no saving gap over ~3.6 min for an average player, §4.7), each with a readable stat change. **Relatedness** comes from Item Sets you can share as a string and from reading teammates' builds.

---

## 3. Detailed Rules

### 3.1 Equipment space

| Space | Count | Holds | Shown on |
| ---- | ---- | ---- | ---- |
| **Core socket** | 1 | One finished Core part (Assembly or Signature) | Gun receiver (`socket_core`) |
| **Barrel socket** | 1 | One finished Barrel part | Muzzle / shroud (`socket_barrel`) |
| **Frame socket** | 1 | One finished Frame part | Grip, stock, side plates (`socket_frame`) |
| **Chamber** | 1 Ammo Type + 1 Ammo Mod | Ammo from `weapons-and-mods.md` §3.7 (all 6 types, all 5 mods) | Tracer colour, impact effect, magazine window / conduit glow |
| **Open item slots** | **6** | Components (weapon or gear), gear Assemblies, gear Signatures. Untyped: any of these fits any slot. | Body anchors (§3.8) |
| Consumable belt | separate, not a slot | Med-Packs (carry 3, `wardlings-and-economy.md` §19) | HUD only (used up) |
| Squad upgrades | separate, not a slot | `wardlings-and-economy.md` §7, unchanged | On the Wardlings |

**Recommendation (owner to confirm): squad upgrades and Med-Packs do not use open slots.** Reasons: (1) squad upgrades already have a visible tell on the Wardlings (Pillar 3/4), so putting them in a slot would show the same power twice; (2) Vesper's commander kit relies on squad upgrades, and a slot tax would make her pay twice for her identity; (3) LoL-style potion slots only matter with item actives, which this release does not have.

### 3.2 Item tiers

| Tier | Total price band [TUNE] | Recipe | Combine cost [TUNE] | Where it goes | Power share | Signature limit |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| **Component** | 250–450 (this release: 250–400) | none (bought whole) | — | Open slot (weapon and gear components alike) | ~30–40% of the line's max stat | — |
| **Assembly** | 800–1,100 (this release: 800–1,000) | 2 components + combine | 250–300 | Weapon: its socket. Gear: open slot. | ~60–75% | — |
| **Signature** | 2,400–3,200 (this release: 2,400–2,600) | 1 Assembly + 2 components + combine | 750–1,050 | Weapon: its socket. Gear: open slot. | 100% + one named passive | **2 per hero** [TUNE] |

Old tiers map one to one: Tier I (Shard / Mk I) = Component, Tier II (Facet / Mk II) = Assembly, Tier III (Heart / Mk III) = Signature.

**Signature limit (2) [TUNE].** A hero can own at most 2 Signatures, on the gun, on the body, or one of each. This bounds the full build (§4.7) and makes each Signature a real identity choice. Each Signature is also **unique**: you can own one copy at most.

### 3.3 One item, two forms (Crystal / Chip)

Every weapon item is one catalog entry with one stat block. On a Mana gun it shows and is named as a **Crystal**; on a Mechanical gun as a **Chip** (C16). Only Feed items have different stats per family (Mana: pool and regen; Mech: magazine and reload). This halves the content compared with separate Crystal and Chip lines and means that no weapon item is ever greyed out for a hero. Weapon-specific conversions (Hex beam, Ironmaw pellets, Liora projectiles) are written in the item rows.

### 3.4 Where weapon components live (the slot model)

**Rule: a weapon component waits in an open slot until its finished part is mounted on its socket.**

1. Buying a weapon **component** puts it in an open slot. It shows as a small clip-on crystal or chip on the hero's **belt rail**, in its line's hue.
2. A loose weapon component **gives its stat to the gun** at once (the harness feeds it through a cable to the gun). Early buys feel like power right away, as in LoL.
3. **Unique loose stats:** only one copy of each component id gives stats. A second copy of the same component is a **spare**: it is shown greyed in the inventory, gives nothing, and is only useful as recipe material. This rule applies to gear components too. It stops "six Ember Chips" rushes (§5).
4. Buying a weapon **Assembly or Signature** mounts it on its socket. Its parts are taken from the socket and from open slots, which frees those slots.
5. Weapon Assemblies and Signatures **never sit in an open slot**. A finished weapon part is either on its socket or sold.
6. Buying a finished weapon part for a socket that holds a part it does **not** build from **swaps** it: the old part is sold (§3.6, rule 4) after a confirm prompt that shows the sell value. If the old part is one of the new item's recipe parts, it is used up instead (upgrade in place).

Why this model: it keeps the owner's open-slot answer (Q1 (a), Q2) without "invisible" mid-build weapon power. Parts in waiting are seen on the belt, finished parts on the gun. A component is never stuck: you can always sell it or build it into something. Inventory pressure (6 slots shared between loose weapon parts and body gear) is the build tension: rushing a weapon recipe leaves slots free for gear sooner.

### 3.5 Content tables (release, protocol 22)

Columns: **Price** = list price if bought whole (components) or full recipe total (Assemblies, Signatures). **Comb.** = combine cost. Stats are additive within their stat (§4.3) and limited by the caps in §3.7. All values in columns marked [TUNE] are first guesses.

#### 3.5.1 Components (10)

| # | id | Name (Crystal / Chip) | Kind | Price [TUNE] | Stat [TUNE] | Builds into | Visual tell (belt rail unless stated) |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| CP-W1 | `ember_part` | Ember Shard / Ember Chip | Weapon | 400 | Weapon damage +5% | Ember Facet, Bore Ring, Ember Heart, Tempest Heart, Breaker Bore | Thumb-size amber crystal / amber card |
| CP-W2 | `tempo_part` | Tempo Shard / Tempo Chip | Weapon | 400 | Fire rate +4% (Hex: tick damage +4%; Ironmaw: pump cycle −4%) | Pulse Facet, Ember Heart, Tempest Heart, Flux Coil | Violet shard / violet card with clock-tick LED |
| CP-W3 | `lens_part` | Lens Shard / Lens Chip | Weapon | 300 | Falloff start and end +10% (Liora: projectile speed +15%; Hex: beam max range +1.5 m) | Ember Facet, Longsight Ring, Prism Eye, Longsight Lens, Breaker Bore, Anchor Frame | White ring shard / white optic card |
| CP-W4 | `steady_part` | Steady Shard / Steady Chip | Weapon | 250 | Spread −10%, recoil −10% (Hex: beam sway −10%) | Pulse Facet, Longsight Ring, Bore Ring, Wellframe, Prism Eye, Longsight Lens, Reservoir Frame, Anchor Frame | Teal-green flat shard / teal gyro card |
| CP-W5 | `feed_part` | Feed Shard / Feed Chip | Weapon | 350 | Mana: regen +10%. Mech: reload time −8% | Wellframe, Reservoir Frame, Flux Coil | Green vial shard / green cell clip |
| CP-G1 | `vital_cell` | Vital Cell | Gear: Health | 300 | Max HP +25 | Vital Core (×2), Plate Harness, Null Cowl, Bastion Plate, Null Veil, Vigil Core, Barrier Lattice, Breaker Sigil | Small glowing cell on the chest harness |
| CP-G2 | `plate_scale` | Plate Scale | Gear: Armor | 300 | Armor +8% (weapon damage only) | Plate Harness, Stride Rig, Bastion Plate, Vigil Core, Breaker Sigil | One scale plate on the left shoulder |
| CP-G3 | `null_thread` | Null Thread | Gear: Resist | 300 | Resist +9% (skill damage only) | Null Cowl, Cadence Circlet, Null Veil, Barrier Lattice, Cadence Crown | Pale-cyan thread spool on the upper back |
| CP-G4 | `cadence_bead` | Cadence Bead | Gear: Utility | 350 | Skill cooldowns −5% | Cadence Circlet, Cadence Crown | Bead earpiece, pulses when a skill comes off cooldown |
| CP-G5 | `stride_clip` | Stride Clip | Gear: Utility | 250 | Move speed +3%; +15% while carrying a Mana Cell (absorbs the old Cell Harness) | Stride Rig, Breaker Sigil | Clips on both calves |

#### 3.5.2 Assemblies (10)

| # | id | Name (Crystal / Chip) | Socket / slot | Recipe | Comb. [TUNE] | Price | Stats [TUNE] | Visual tell |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| AS-W1 | `ember_facet` | Ember Facet / Ember Board | Core | Ember + Lens | 300 | 1,000 | Damage +10%, falloff +5% | Twin amber facets with orbiting motes / card + heatsink fins |
| AS-W2 | `pulse_facet` | Pulse Facet / Pulse Board | Core | Tempo + Steady | 300 | 950 | Fire rate +8%, spread −5% | Violet facets that pulse per shot |
| AS-W3 | `longsight_ring` | Longsight Ring / Longsight Rail | Barrel | Lens + Steady | 300 | 850 | Falloff +18%, spread −8% (Liora: proj. speed +25%; Hex: beam +2.5 m) | Two white lens rings at the muzzle / twin rail shroud |
| AS-W4 | `bore_ring` | Bore Ring / Bore Rail | Barrel | Ember + Steady | 300 | 950 | Armor pen +15% (adds to Piercing, total cap 60%), damage +3% | Magenta ring with cutting teeth |
| AS-W5 | `wellframe` | Wellframe | Frame | Feed + Steady | 250 | 850 | Mana: pool +15%, regen +8%. Mech: magazine and reserve +15%, reload −6%. Both: recoil −8% | Green side crystals / LED stock counter |
| AS-G1 | `vital_core` | Vital Core | Open slot | Vital Cell + Vital Cell | 250 | 850 | Max HP +90 | Fist-size cell in a sternum cage |
| AS-G2 | `plate_harness` | Plate Harness | Open slot | Plate Scale + Vital Cell | 300 | 900 | Armor +13%, max HP +25 | Plates on both shoulders, strap across chest |
| AS-G3 | `null_cowl` | Null Cowl | Open slot | Null Thread + Vital Cell | 300 | 900 | Resist +15%, max HP +25 | Short shimmering cowl over the shoulders and back |
| AS-G4 | `cadence_circlet` | Cadence Circlet | Open slot | Cadence Bead + Null Thread | 300 | 950 | Skill cooldowns −10%, resist +6% | Thin circlet around the head |
| AS-G5 | `stride_rig` | Stride Rig | Open slot | Stride Clip + Plate Scale | 250 | 800 | Move speed +4%, +8% more after 4 s out of combat; armor +4%; Mana Cell +15% kept | Glowing calf rigs (old Stride Rig tell) |

#### 3.5.3 Signatures (14)

Weapon Signatures (8) mount on their socket; gear Signatures (6) sit in an open slot. Each has one named passive. Signatures are unique and count toward the limit of 2.

| # | id | Name (Crystal / Chip) | Socket / slot | Recipe | Comb. [TUNE] | Price | Stats [TUNE] | Unique passive [TUNE] | Visual tell |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| SG-W1 | `ember_heart` | Ember Heart / Overclock Core | Core | Ember Facet + Ember + Tempo | 800 | 2,600 | Damage +16%, fire rate +3% | **Kindle:** a hero kill or assist refills 30% of the magazine from nothing (Mech, no reserve used) or 30% of the pool (Mana). | Heart crystal with halo ring / three-fin module with exposed core; halo flash every 5th shot |
| SG-W2 | `tempest_heart` | Tempest Heart / Cyclic Governor | Core | Pulse Facet + Tempo + Ember | 750 | 2,500 | Fire rate +12%, damage +3%, spread −5% | **Overdrive Loop:** after 1.5 s of continuous fire (shots ≤ 0.9 s apart), spread bloom −40% (Ironmaw: pellet cone −10%; Hex: beam sway −50%). | Spinning violet ring / spinning governor drum |
| SG-W3 | `prism_eye` | Prism Eye / Ballistic Solver | Core | Ember Facet + Lens + Steady | 950 | 2,500 | Damage +6%, headshot mult +0.30 (Ironmaw +0.10; Hex: ramp time −30%) | **True Line:** a head hit on a hero refunds the shot (Mech: +1 round to the magazine, up to max; Mana: the shot's mana cost). Hex: the beam ramp is kept for 0.5 s after losing the target. | White eye crystal that tracks the aim / solver lens with a moving reticle |
| SG-W4 | `longsight_lens` | Longsight Lens / Longsight Rifling | Barrel | Longsight Ring + Lens + Steady | 1,000 | 2,400 | Falloff +30%, spread −15% (Liora: proj. speed +40%; Hex: beam +4 m) | **Long Reach:** body hits on a hero beyond the weapon's base `falloff_start` apply Slow 10% for 1 s (refresh, no stack; shared 40% slow cap). | Three white lens rings, longest barrel silhouette / long rifled shroud |
| SG-W5 | `breaker_bore` | Breaker Bore | Barrel | Bore Ring + Ember + Lens | 850 | 2,500 | Armor pen +25% (total cap 60%), damage +4%, falloff +5% | **Rend:** each body hit on a hero lowers its **gear** Armor by 2 points for 4 s (refresh), max −8 points. Base armor untouched. | Magenta drill-tooth muzzle, sparks on hit |
| SG-W6 | `reservoir_frame` | Reservoir Frame / Extended Frame | Frame | Wellframe + Feed + Steady | 950 | 2,400 | Mana: pool +45%. Mech: magazine and reserve +45% (round down, min +1) | **Deep Reserve:** Mana: emptying the pool never triggers Burnout. Mech: refills from Supply Caches and Ammo Sparks +50%. | Large green tank crystal / drum magazine housing |
| SG-W7 | `flux_coil` | Flux Coil / Quickload Coil | Frame | Wellframe + Feed + Tempo | 900 | 2,500 | Mana: regen +30%, regen delay −0.3 s. Mech: reload time −28% | **Cold Start:** after 3 s without firing, Mana regen is doubled until you fire; Mech: your next reload is instant. | Violet coil wrapped round the grip, rising chime |
| SG-W8 | `anchor_frame` | Anchor Frame / Gyro Frame | Frame | Wellframe + Steady + Lens | 1,000 | 2,400 | Recoil −35%, spread −15%, pool or magazine +15% | **Planted:** after 0.5 s without moving (or while crouched), recoil −25% more and Knockback / Pull distance on you −50% (Hex: beam sway 0). | Amber stock crystal / gyro stock with spinning ring |
| SG-G1 | `bastion_plate` | Bastion Plate | Open slot | Plate Harness + Plate Scale + Vital Cell | 1,000 | 2,500 | Armor +20%, max HP +60 | **Brace:** after losing ≥ 35% max HP to weapon damage within 2 s, gain 15% damage reduction vs weapon damage for 2.5 s (adds to DR, inside the 0.70 clamp); cooldown 20 s. | Full steel pauldrons and a raised collar |
| SG-G2 | `null_veil` | Null Veil | Open slot | Null Cowl + Null Thread + Vital Cell | 1,000 | 2,500 | Resist +22%, max HP +60 | **Grounding:** Root, Stun, Silence and Slow durations on you −25% (Knockback / Pull unchanged). | Pale-cyan veil fins along the spine |
| SG-G3 | `vigil_core` | Vigil Core | Open slot | Vital Core + Vital Cell + Plate Scale | 1,050 | 2,500 | Max HP +170, armor +4% | **Regrowth:** after 5 s without taking damage, regenerate 2% max HP per second until damaged (Scorched applies). | Large caged heart-cell on the chest, beats while regenerating |
| SG-G4 | `barrier_lattice` | Barrier Lattice | Open slot | Vital Core + Null Thread + Vital Cell | 1,050 | 2,500 | Max HP +60, resist +8% | **Lattice:** 80-point overshield, refills fully after 6 s without taking damage (absorbs after armor/resist). | Hex lattice projector on the hip; hex shimmer while the shield is up |
| SG-G5 | `cadence_crown` | Cadence Crown | Open slot | Cadence Circlet + Cadence Bead + Null Thread | 1,000 | 2,600 | Skill cooldowns −18%, resist +8% | **Resonant Cast:** casting your ultimate cuts the remaining cooldown of each basic skill by 25%. | Floating halo crown above the head |
| SG-G6 | `breaker_sigil` | Breaker Sigil | Open slot | Stride Rig + Plate Scale + Vital Cell | 1,050 | 2,450 | Max HP +60, armor +6%, move speed +4% | **Siegebreaker:** weapon damage vs Ward Generators and an Exposed Uplink +15% (target-class modifier, not an ammo effect, so the Uplink rule of `weapons-and-mods.md` §3.7.1 is untouched). Absorbs the old Uplink Breaker. | Red sigil gauntlet on the forearm + red gun sigil |

#### 3.5.4 Ammo Types and Ammo Mods (Chamber, all in this release)

Effects, compatibility and potency are **unchanged** from `weapons-and-mods.md` §3.7.1–§3.7.2. Prices are unchanged from §3.8 there. Ammo is not part of any recipe, is not tiered, and does not use open slots.

| id | Item | Kind | Price | Tracer / impact tell (owned by art; listed so it is not lost) |
| ---- | ---- | ---- | ---- | ---- |
| AM-0 | Standard | Ammo Type | free (default) | Plain tracer |
| AM-1 | Piercing | Ammo Type | 750 | Steel-blue thin tracer, spark puncture |
| AM-2 | Incendiary | Ammo Type | 800 | Ember trail, flame lick on impact |
| AM-3 | Shock | Ammo Type | 800 | Arc tracer, crackle ring |
| AM-4 | Siphon | Ammo Type | 850 | Green tracer, mote drawn back to the shooter |
| AM-5 | Cryo | Ammo Type | 750 | Pale frost tracer, frost bloom |
| AM-6 | Sunder | Ammo Type | 650 | Heavy orange tracer, chunk debris |
| MD-1 | Saturated | Ammo Mod | 350 | Thicker tracer |
| MD-2 | Lingering | Ammo Mod | 300 | Longer trail that hangs 0.3 s |
| MD-3 | Volatile | Ammo Mod | 400 | Small sparks off the tracer; burst ring on kill |
| MD-4 | Tracer | Ammo Mod | 300 | Pulsing tracer head |
| MD-5 | Overcharged | Ammo Mod | 350 | Crackling glow, brighter muzzle |

Content totals: **10 Components, 10 Assemblies, 14 Signatures (8 weapon + 6 body gear), 6 Ammo Types + Standard, 5 Ammo Mods = 45 sale items**, plus the unchanged Med-Pack and 8 squad upgrades.

**Interpretation note (owner to confirm):** the approved "6 body/gear items" are the **6 gear Signatures**. The four utility items of `wardlings-and-economy.md` §19 fold into the tree: Cell Harness → Stride Clip, Stride Rig → Assembly AS-G5, Barrier Lattice → Signature SG-G4, Uplink Breaker → Signature SG-G6. Bastion Weave and Null Weave leave the Frame socket and become the Plate and Null gear lines.

### 3.6 Buying, selling and undo

1. **Where and when.** Unchanged: only in your own HQ Armory zone, only while alive, never at Forward Beacons, never during Sudden Death (C6, C10, C14). Items persist through death; a bot replacing a disconnected player inherits items and Lumen; everything is deleted at match end.
2. **Recipe purchase.** Buying item X costs `RemainingCost(X)` (§4.1): the combine costs of every missing node in X's tree plus the list price of every missing component. Owned parts (in open slots, and in X's socket for weapon items) are used up. You never pay twice for a part you own.
3. **Slot check.** A purchase is refused with "Inventory full" if it would leave more than 6 items in open slots after used-up parts are removed (§4.2). Buying a weapon Assembly or Signature never needs a free slot (it goes to the socket) and frees the slots its parts used.
4. **Socket swap.** Buying a finished weapon part for an occupied socket whose part is not in its recipe sells the held part first (rule 7 values), after a confirm prompt. Same for Ammo Type and Ammo Mod (`weapons-and-mods.md` §3.6.4 rule 7 unchanged).
5. **Signature limit.** Buying a third Signature is refused ("Signature limit 2: sell one first"). The shop shows "Signatures 1/2".
6. **Unique Signature.** Buying a Signature you already own is refused.
7. **Sell value.** Selling an item gives `SellValue` (§4.4): **60%** of the item's full recipe total, rounded down to a multiple of 5. Selling a finished item never gives back its components. Selling a socketed part empties the socket.
8. **Undo (same visit, 100%).** Every purchase this visit is a transaction in a per-visit log (Lumen paid, parts used, parts sold by a swap). Undoing a transaction gives back the Lumen paid, restores the used-up parts and any part a swap sold, and removes the item. **An item that a later purchase used up cannot be undone on its own:** its undo button reads "Undo <later item> first". The **Undo last** button always works (strict last-in, first-out). The visit ends when you leave the zone or die. Squad upgrade and Med-Pack undo rules are unchanged (`weapons-and-mods.md` §3.6.4 rule 4, revision of 2026-10-07).
9. **No debt, no partial buy.** If Lumen is short, the buy button is disabled and shows the missing amount.
10. **Atomicity.** The server applies a purchase all at once: parts removed, item placed, Lumen charged, transaction logged. A refused request changes nothing.

### 3.7 Stat caps (keep the §3.4 TTK cap)

| Stat | Cap | Source |
| ---- | ---- | ---- |
| Mod damage bonus `M_dmg` | +0.25 | `weapons-and-mods.md` §4.1 (unchanged) |
| Mod fire-rate bonus `M_rate` | **+0.15** [TUNE] | new |
| Weapon throughput `G = (1 + M_dmg) × (1 + M_rate)` | **≤ 1.333** (body TTK −25%) | new; keeps `weapons-and-mods.md` §3.4 rule (a) |
| Total weapon multiplier `S_skill × G` | **≤ 2.25** [TUNE] | new; keeps the old ceiling 1.80 × 1.25, so Sable's ult combo stays ≈ 0.6 s |
| Armor penetration (Piercing + Bore items) | 0.60 | `weapons-and-mods.md` §4.1 (unchanged) |
| Headshot bonus from items | +0.30 (one source: Prism Eye) | below the old +0.45 |
| Gear Armor `A_gear` | **0.25** [TUNE] | new |
| Gear Resist `R_gear` | **0.25** [TUNE] | new |
| Armor + resist + DR (any hit) | 0.70 | `heroes.md` §5.1 (unchanged) |
| Max HP from items | **+250** [TUNE] | new |
| Skill cooldown reduction | 0.25, min CD 3 s basic / 45 s ult | `heroes.md` §3.4 (unchanged) |
| Move speed from items | **+12%** [TUNE] | new |
| Falloff range bonus | **+40%** [TUNE] | new |
| Spread / recoil reduction | **−50%** each [TUNE] | new |
| Pool / magazine bonus | **+60%** [TUNE] | new |
| Mana regen bonus / reload reduction | **+45% / −35%** [TUNE] | new |

When a stat is over its cap, the extra is lost and the shop shows the stat as "capped". The data validator checks that **no single item** goes over a cap by itself.

### 3.8 Visibility (Pillar 4)

Every item has a **visual tell** in the tables above. Rules:

1. **Gun.** Socket parts use the existing `socket_core / socket_barrel / socket_frame / socket_chamber` markers and the tier channels of `weapons-and-mods.md` §3.6.2–§3.6.3 (size, facet/fin count, glow, idle animation; never colour alone). Component = small, Assembly = medium, Signature = large + idle animation + unique sound tail.
2. **Body.** Each open-slot item has a `body_anchor`. Every hero model gets these `Marker3D` anchors (first-person arms show only the forearm and belt):

| Anchor | Category | Sub-positions | Items |
| ---- | ---- | ---- | ---- |
| `body_belt` | Loose weapon components | 6 clips (left hip → right hip) | CP-W1…W5 |
| `body_chest` | Health | 2 | Vital Cell, Vital Core, Vigil Core |
| `body_shoulders` | Armor | 2 (left, right) | Plate Scale, Plate Harness, Bastion Plate |
| `body_back` | Resist / shields | 2 (upper, lower) | Null Thread, Null Cowl, Null Veil, Barrier Lattice (hip projector) |
| `body_head` | Cooldown | 1 + overflow on `body_back` | Cadence Bead, Circlet, Crown |
| `body_legs` / `body_forearm` | Speed / siege | 2 each | Stride Clip, Stride Rig, Breaker Sigil |

3. If an anchor is full (for example three armor items), the next item uses the anchor's overflow sub-position. A third copy that has no position left still shows as a small badge on the hero's back plate; nothing is ever invisible.
4. Spares (duplicate loose components, §3.4 rule 3) show **unlit** on the belt.
5. Item meshes are shared per item and placed by per-hero scale/offset presets, so the art cost is *items*, not *items × heroes*.
6. **Readability budget:** body tells use silhouette and size first; idle VFX on body gear are culled beyond 30 m (same rule as gun mounts, `weapons-and-mods.md` R9).
7. **HUD and scoreboard.** Your inventory strip shows the 4 sockets and 6 open slots. The Tab scoreboard shows every hero's sockets and slots as icons; the death card shows the killer's full build.

### 3.9 Shop UI requirements (three tabs)

Minimum layout at 1280×720 (all text readable at 720p; 1080p uses the same layout scaled). Gamepad and keyboard parity with today's bindings (`docs/armory.md` "Editing in the Armory").

**Always on screen (bottom strip):** Lumen; the 4 gun sockets (Core, Barrel, Frame, Chamber with type + mod); the 6 open slots; "Signatures n/2"; **Undo last**; Sell (on the focused owned item, showing the value).

| Tab | Layout | Must show |
| ---- | ---- | ---- |
| **Recommended** | Four sections top to bottom: **Starter** (at 0:00: affordable components + Med-Pack), **Core** (one row per build step, each with **2–3 choices** as cards), **Situational** (counter items with a reason chip, e.g. "Enemy has frontline", "Taking skill damage"), **Ammo** (one Ammo Type and one Mod suggestion with reason). | For every card: total price, "next part to buy" with its price, and the reason. No fixed path; the advisor re-scores on every change (§3.10). |
| **All Items** | Left: stat filters (Damage, Fire rate, Range, Handling, Feed, Health, Armor, Resist, Cooldown, Speed, Siege, Ammo, Squad, Consumable). Centre: grid in three rows, Components / Assemblies / Signatures (then Ammo, Squad, Consumables). Right: **recipe tree** of the focused item (item on top, parts below, owned parts ticked, "cost to complete") and **Builds into** list under it. | Socket or "open slot"; where it shows on the model ("Shows on: shoulders"); stats with "(capped)" when they would be wasted; the passive text; a greyed reason when it cannot be bought (Inventory full, Signature limit, already owned). |
| **Item Sets** | Today's My builds, renamed. List of the player's sets for this hero; using one replaces the Recommended Core section. | Copy / paste string (`CGB2:` + base64 JSON), new / duplicate / delete, the set's steps as finished items (components optional). Old `CGB1` strings are refused with "Made for the old Armory". |

### 3.10 BuildAdvisor and bots

1. **Guides become choice lists.** A hero guide lists steps; each step has 2–3 finished-item choices plus situational nodes. The guide names finished items; the advisor works out the parts.
2. **Next step = next part.** For the top-scored finished target, the advisor resolves the recipe tree against what the hero owns and offers, in order: (a) the combine, if every part is owned and Lumen is enough; else (b) the **cheapest missing component that gives stats now** (not a spare); else (c) the cheapest missing part. This keeps saving gaps short.
3. **Respect the rules.** The advisor never recommends a buy that would be refused (Inventory full, Signature limit, unique) and never recommends a swap that would sell a Signature unless the step is marked "replace". When slots are full, it recommends completing a recipe that frees slots before buying a new component.
4. **Situational rules stay** (`docs/armory.md` rule table). New mappings: `taking_weapon_damage` → Plate line / Bastion Plate; `taking_skill_damage` → Null line / Null Veil / Barrier Lattice; `enemy_cc` → Null Veil; `enemy_frontline` or **enemy gear Armor ≥ 0.15** (new server signal) → Piercing, Bore Ring / Breaker Bore; `enemy_sustain` → Incendiary; `enemy_squad` → Sunder / Shock; `objective_soon` → Breaker Sigil.
5. **Bots** use the same path (`ACTION_BUY`, `BuildAdvisor`). A bot picks the first choice of each Core step unless a situational rule outscores it (deterministic for tests). A bot sells only to make room: when slots are full and its next step needs a slot, it sells the loose spare or component of lowest value that is not in its plan.
6. **Balance report** (`tools/balance/armory_report.gd`) must report, per hero and for the weak / average / strong curves: time of first Signature, time of full build, unspent Lumen at 30:00, dead zones over 240 s, items never bought, and the share of Lumen spent on items / squad / consumables.

### 3.11 Migration (protocol 21 → 22)

The catalog is replaced. Catalog order is still the wire id and is append-only **from v22 on**. Proposed v22 order: 0 Med-Pack; 1–8 squad upgrades (Squad Expansion I, II, Reinforced Cores I, II, Amplifier Emitters, Harmonic Tether, Quick Mint, Bulwark Protocol; all below 32 for `owned_bits`); 9–18 Components; 19–28 Assemblies; 29–42 Signatures; 43–48 Ammo Types; 49–53 Ammo Mods. 54 items, all below 128.

| v21 item (id) | v22 replacement |
| ---- | ---- |
| Med-Pack (0), Squad Expansion I/II (1–2), Reinforced Cores I/II (3–4), Amplifier Emitters (5) | Same item, same id |
| Harmonic Tether (17), Quick Mint (18), Bulwark Protocol (19) | Same item, new ids 6–8 |
| Ember Heart (6) / Overclock (8), tiers I/II/III | Ember Shard/Chip → Ember Facet/Board → Ember Heart/Overclock Core |
| Flux Coil (7) / Quickload (9) | Feed part → Wellframe → Flux Coil / Quickload Coil |
| Focus Lens (12) / Rifling (13) | Lens part → Longsight Ring/Rail → Longsight Lens/Rifling |
| Penetrator (14) | Bore Ring/Rail → Breaker Bore |
| Bastion Weave (15, Frame) | Plate Scale → Plate Harness → Bastion Plate (open slot) |
| Null Weave (16, Frame) | Null Thread → Null Cowl → Null Veil (open slot) |
| Piercing (10), Sunder (11) | Same items, new ids 43–48 range |
| GDD-only lines not in v21 (Tempest, Prism, Wellspring, Stillwater, Velocity, Reservoir, Anchor, Feedback Loop, Stabilizer, Extended Mag, Gyro, Cyclic, Solver) | Tempest Heart, Prism Eye, Reservoir Frame, Anchor Frame; Wellspring + Feedback Loop → Ember Heart's Kindle; Stillwater/Stabilizer → Steady part; Velocity Facet → Lens/Longsight conversions for Liora and Hex |

Other migration needs: `ACTION_BUY`'s tier byte is no longer used (one price per item); `ProgressState` replicates 3 socket item ids, 2 Chamber ids and 6 open-slot item ids plus a spare flag per slot; `CustomBuildStore` file version 2; `ArmoryItemDef` gains `tier`, `recipe` (part ids), `combine_cost`, `slot_kind` (socket name or open), `body_anchor`, `unique`, `family_stats` (Feed). Clients on protocol 21 are refused at login by the existing protocol check.

---

## 4. Formulas

### 4.1 Recipe price

```
Total(X)         = combine(X) + Σ Total(p)                    for p in recipe(X); a component's Total = its list price
RemainingCost(X) = 0                                          if X is matched to an owned instance
                 = combine(X) + Σ RemainingCost(p)            otherwise
```

| Symbol | Range | Meaning |
| ---- | ---- | ---- |
| `combine(X)` | 0 (components), 250–300 (Assemblies), 750–1,050 (Signatures) [TUNE] | Extra Lumen to combine the parts |
| `recipe(X)` | 2 parts (Assembly), 3 parts (Signature) | Ordered list of part ids |
| `Total(X)` | 250–2,600 | Full price if nothing is owned |

**Matching:** owned instances are matched deepest first (an owned Assembly before its components), from X's socket first (weapon items), then from open slots, spares before active copies (so the player keeps the active stat as long as possible). Each owned instance is matched at most once.

**Example 1:** Ember Heart (combine 800; Ember Facet + Ember + Tempo). Ember Facet in Core, nothing loose: `800 + 0 + 400 + 400 = 1,600`. With an Ember Shard loose: `1,200`. Total = `800 + 1,000 + 400 + 400 = 2,600`.
**Example 2:** Bastion Plate from nothing: `1,000 + (300 + 300 + 300) + 300 + 300 = 2,500`.

### 4.2 Slot count after a purchase

```
Slots_after = Slots_now − Consumed_open + (X goes to an open slot ? 1 : 0)
Purchase allowed only if Slots_after ≤ 6
```
`Consumed_open` = matched instances taken from open slots. Example: 6 slots full with Plate Scale, Vital Cell and 4 others; buying Plate Harness: `6 − 2 + 1 = 5` → allowed.

### 4.3 Damage per hit (extends `weapons-and-mods.md` §4.1)

```
D_final = D_base × L(level) × F(d) × H × min(2.25, S_skill × G) × A_mult × V_mult × B_brittle
G       = min(1.333, (1 + min(0.25, M_dmg)) × (1 + min(0.15, M_rate)))
```
Fire rate from `M_rate` changes the shot interval, not `D_final`; it is in `G` only for the cap. In practice the server applies `M_dmg` per hit and `M_rate` to the cycle time, then scales `M_dmg` down if `G` would exceed 1.333 (so the cap always lands on damage, never on feel).

**Armor and resist (replaces the A_mult row of §4.1 for heroes).**

```
Weapon hit:  A_w = (A_base + max(0, min(0.25, A_gear) − Rend)) × (1 − min(0.60, P))
             A_mult = 1 − min(0.70, A_w + DR + DR_brace)
Skill hit:   A_s = A_base + min(0.25, R_gear)
             A_mult = 1 − min(0.70, A_s + DR)
TRUE damage: A_mult = 1
```

| Symbol | Range | Meaning |
| ---- | ---- | ---- |
| `A_base` | 0–0.20 | Hero armor, `heroes.md` §3.1, unchanged; still applies to **all** damage |
| `A_gear` | 0–0.25 | Sum of item Armor (Plate line, Stride Rig, Vigil Core, Breaker Sigil) |
| `R_gear` | 0–0.25 | Sum of item Resist (Null line, Cadence line, Barrier Lattice) |
| `Rend` | 0–0.08 | Breaker Bore stacks on the target |
| `P` | 0–0.60 | Piercing (+mod) + Bore Ring / Breaker Bore. **Penetration now also cuts gear armor.** |
| `DR`, `DR_brace` | 0–0.50, 0 or 0.15 | Active skill DR; Bastion Plate's Brace |

Damage types (assumption to check against `HealthComponent.apply_damage`): **weapon damage** = hero gunfire, ammo effects (Burn, Shock arcs), Wardling, Sentinel and turret shots; **skill damage** = hero skills, traps and deployables, ultimates. This replaces the multiplicative "after armor" rule of the old Bastion and Null Weaves: gear armor and resist now add to armor, so Piercing counters them.

**Worked example:** Ryker L10 (`D = 18 × 1.225 = 22.05` at ≤ 22 m) vs Liora L10 wearing Plate Harness (`A_gear = 0.13`): `A_mult = 0.87` → **19.2** per hit. With Piercing (`P = 0.40`): `A_w = 0.13 × 0.6 = 0.078` → **20.3**. With Piercing + Breaker Bore (`P = 0.60`) and 4 Rend stacks (−0.08): `A_w = 0.05 × 0.4 = 0.02` → **21.6**.

### 4.4 Sell value

```
SellValue(X) = Paid_this_transaction + restored parts        if undone in the same visit (100%)
             = floor(0.60 × Total(X) / 5) × 5                 otherwise
```
Example: Ember Heart sold later: `floor(0.6 × 2,600 / 5) × 5 = 1,560`. Ember Shard: `240`. Selling never pays more than was spent, so no buy–sell loop gains Lumen.

### 4.5 TTK limits

```
TTK_ideal = EHP / (DPS_base × L × G)        (heroes.md §5.1)
TTK reduction from items = 1 − 1/G  ≤ 1 − 1/1.333 = 25%
EHP_weapon = (MaxHP(L) + HP_items) / (1 − min(0.70, A_w + DR))
```

| Check | Value | Target | Pass |
| ---- | ---- | ---- | ---- |
| Fastest unmodded body TTK vs 250 HP (Ryker 1.39 s, Whisperfang burst 1.33 s, Ironmaw ≤ 8 m 1.33 s) × 0.75 | 1.00–1.04 s | ≥ 0.80 s floor (§3.4 rule b) | yes |
| Max throughput of any item build (damage and fire rate can now stack, which the old one-line Core prevented) | G capped at 1.333 | ≤ 25% TTK cut (§3.4 rule a) | yes, by construction |
| Sable full combo with items: `188 × min(2.25, 1.80 × 1.333 = 2.40) = 188 × 2.25 = 423 DPS` vs 250 HP | 0.59 s | ≈ 0.6 s ult floor (`heroes.md` §5.2) | same as today |
| Max defense, squishy L15: `(390 + 250) / (1 − 0.25)` | EHP 853 vs weapons (×2.19 of 390) | must leave an armor-less damage build; telemetry R2 | watch |
| Brannoc L15 full plate: `(858 + 250) / (1 − 0.45)` | EHP 2,015 vs weapons; with P = 0.60: `1,108 / 0.82 = 1,351` | Piercing must matter | yes |

Example build ceiling: Ember Heart (+16% dmg, +3% rate) + Breaker Bore (+4%) + loose Ember (+5%) + loose Tempo (+4%) → `M_dmg 0.25, M_rate 0.07` → `1.25 × 1.07 = 1.3375` → capped **1.333**: Ryker L1 DPS 180 → 240, TTK vs 250 HP 1.39 → **1.04 s** (−25%).

### 4.6 Item value (for the balance report)

```
EHP_gain(item, L) = EHP_with / EHP_without − 1,      at L10 vs the item's damage type
Value_per_1k      = EHP_gain / (Total / 1,000)
```
At L10 (MaxHP 340): Vital Cell +25 HP = +7.4% vs all (24.5% per 1k); Plate Scale +8% armor = +8.7% vs weapons (29% per 1k); Null Thread +9% resist = +9.9% vs skills (33% per 1k). Specialised defense is a bit stronger per Lumen than health because it covers one damage type only. Same reasoning as the old Null Weave: skill damage comes in fewer, larger hits.

### 4.7 Spending check against the §18 curve

```
FullBuild = Σ socket parts (3) + Chamber (type + mod) + Σ open slots (6)
          with at most 2 Signatures (§3.2)
```

**Reference full build (Ryker "Line Breaker v2"):**

| Space | Item | Lumen |
| ---- | ---- | ----: |
| Core | Ember Heart / Overclock Core (Signature 1) | 2,600 |
| Barrel | Bore Rail | 950 |
| Frame | Wellframe | 850 |
| Chamber | Piercing + Saturated | 1,100 |
| Open 1 | Bastion Plate (Signature 2) | 2,500 |
| Open 2–6 | Null Cowl 900, Vital Core 850, Stride Rig 800, Cadence Circlet 950, Plate Harness 900 | 4,400 |
| **Total** | | **12,400** |

**Range** with 2 Signatures and 7 different Assemblies (duplicating the cheapest Assembly can go a little lower, but gives capped, wasted stats): cheapest `2,400 + 2,400 + (800 + 850 × 3 + 900 × 3) + 950 = 11,800`; dearest `2,600 + 2,600 + (1,000 + 950 × 4 + 900 × 2) + 1,250 = 13,050`. **Full build = 11,800–13,050, centre ≈ 12,400.**

| Profile (`wardlings-and-economy.md` §18) | Lumen at 30:00 | Share of a 12,400 full build |
| ---- | ----: | ----: |
| Weak | 6,320 | 51% |
| **Average** | **8,970** | **72%** |
| **Strong** | **12,280** | **99%** |

So only a strong player who spends nothing on the squad finishes the build around 30 min; an average player has about 72% of it, before any squad spend. The old rule "no player completes a full build and a maxed squad before 30:00" holds easily: `12,400 + 6,050 = 18,450 > 12,280`.

**Average player, gun-first timeline (Lumen earned approx. linear between §18 points: 210/min to 5:00, 266/min to 10:00, 291/min to 20:00, 318/min to 30:00):**

| Time | Earned | Buy | Spent total | Holds |
| ---- | ----: | ---- | ----: | ---- |
| 0:00 | 500 | Ember Chip 400 | 400 | +5% dmg |
| ~2:30 | 1,025 | Lens Chip 300 | 700 | +5% dmg, +10% falloff |
| ~3:30 | 1,235 | Combine → Ember Board (Core) 300 | 1,000 | +10% dmg; 2 slots freed |
| ~6:00 | 1,815 | Piercing 750 | 1,750 | |
| ~8:30 | 2,480 | Ember Chip 400, Tempo Chip 400 | 2,550 | loose +5% dmg, +4% rate |
| ~11:45 | 3,400 | Combine → Overclock Core 800 (Signature 1) | 3,350 | +16% dmg +3% rate; first Signature ~11–12 min |
| ~14:45 | 4,270 | Plate Harness 900 (in steps of 300) | 4,250 | |
| ~17:45 | 5,140 | Wellframe 850 | 5,100 | |
| ~21:00 | 6,110 | Bore Rail 950 | 6,050 | G ≈ 1.25 → TTK −20% |
| 21:00–30:00 | 8,970 | ~2,900 left: squad (Amplifier 700, Expansion I 800), Saturated 350, Vital Core 850, Med-Packs | ~8,900 | |

Largest single saving step = biggest Signature combine (1,050) = **3.6 min** at 291 Lumen/min, under the report's 240 s dead-zone line. Strong player: first Signature ≈ 8–9 min. Weak player: first Signature ≈ 15–16 min.

**Spend split (replaces `wardlings-and-economy.md` §18 "~60% gun, ~30% squad, ~10% consumables"):** about **65–70% items** (gun + body), **20–25% squad**, **~10% consumables** [TUNE]. The squad sink (6,050 + licences) and Med-Packs remain the open-ended sinks after a full build.

---

## 5. Edge Cases

| Situation | Resolution |
| ---- | ---- |
| Buying a weapon component with 6 open slots full | Refused: "Inventory full". Advisor suggests a combine that frees slots or a sell. |
| Buying a recipe item with slots full | Allowed if `Slots_after ≤ 6` (§4.2); weapon Assemblies and Signatures always allowed (they go to the socket). |
| Buying a second copy of a component | Allowed. It is a **spare**: unlit, no stats, used first by recipes. |
| "Six Ember Chips" rush at 8 min | Prevented: only one Ember Chip gives stats. Max loose weapon stats = +5% dmg, +4% rate, etc. |
| Six Vital Cores (+540 HP) | Allowed to buy; item HP capped at +250; shop shows "capped". Assemblies may be duplicated; Signatures may not. |
| Two armor items over the cap (Bastion 20 + Harness 13) | `A_gear` = 0.25; extra lost, shown "capped". |
| Third Signature | Refused: "Signature limit 2". |
| Buying Ember Board while Core holds Overclock Core (a downgrade) | Confirm prompt "This sells Overclock Core for 1,560". Never recommended by the advisor. |
| Buying Ember Heart while Core holds Pulse Facet (another line) | Pulse Facet is sold (60%, or 100% if bought this visit) after a confirm; then normal recipe pricing. |
| Undo an Ember Board that a later Overclock Core used up | Its undo is blocked: "Undo Overclock Core first". Undo last undoes the Core, which restores Ember Board + Ember + Tempo and refunds 800. |
| Undo a swap purchase | Restores the sold part to its socket and takes back the Lumen the sale gave. |
| Leave the zone, come back, sell | New visit: 60% of the recipe total. |
| Sell a component that a spare copy duplicates | The spare becomes active (lights up). |
| Hex buys Barrel items | Converted: beam max range (Lens, Longsight). No Barrel item is greyed for Hex (fixes review F2). |
| Ironmaw and Prism Eye | Headshot +0.10 only (pellet weapon). |
| Liora heal beam | Unchanged rule: damage stats never change healing. Longsight items extend lock range the same way Focus Lens did (+10% / +18% / +30%); Reservoir and Flux change the shared pool; Ammo never applies. |
| Rend on a target with no gear armor | No effect; gear armor floors at 0; base armor untouched. |
| Kindle (Ember Heart) on Wardling kills | Hero kills and assists only (same anti-farm rule as old Feedback Loop / Wellspring). |
| Deep Reserve and Burnout | Pool can reach 0 with no Burnout; regen delay still applies. |
| Cold Start on Ironmaw (per-shell reload) | "Instant reload" fills the magazine from reserve at once. |
| True Line at full magazine | No refund (cannot exceed max). |
| Brace and Fortify together | Both are DR; the 0.70 clamp applies. |
| Barrier Lattice vs Scorched | Overshield refill is not healing; Scorched does not reduce it. Vigil Core regen is healing and is reduced 30%. |
| Breaker Sigil on Barricades | No bonus (Ward Generators and Exposed Uplink only, as the old Uplink Breaker). |
| Grounding vs Knockback / Pull | Not reduced (Anchor Frame's Planted covers those). Both together: −50% distance from Planted only. |
| Selling an item while its stat is over cap | Stats recompute; current HP keeps its ratio to max HP (selling HP never kills). Pool / magazine clamp as in `weapons-and-mods.md` §5. |
| Bot replaces a disconnected player | Inherits sockets, slots, spares, Lumen; its advisor plans from that state. Reconnecting player gets the state back. |
| Item Set names an item the hero cannot use | Impossible for weapon items (all fit, §3.3); warnings kept for unknown ids (`CustomBuildStore`). |
| Old `CGB1` build string pasted | Refused: "Made for the old Armory". |
| Sudden Death | Items kept; shop disabled (C10). |
| Pre-existing: Brannoc's 2.5× rule (`weapons-and-mods.md` §3.4 rule c) | With P = 0.60 Brannoc's EHP at L1 is `550 / 0.92 = 598` = 2.39× of 250. This was already true with Penetrator III + Piercing in v21. Open question Q9. |

**Degenerate strategies watched (Sirlin):** (1) component rush, handled by unique loose stats; (2) full-defense squishy, bounded by HP / armor / resist caps and by giving up all damage items; telemetry R2; (3) double weapon Signature + naked body, allowed (glass cannon, readable at a glance); (4) sell-loop, impossible (§4.4).

---

## 6. Dependencies

| System / doc | Direction | Contract |
| ---- | ---- | ---- |
| `game-concept.md` C6, C10, C14, C16, Pillar 4 | This obeys; needs text changes (§9) | HQ-only shop, Sudden Death, Lumen sinks, Crystal/Chip forms, visible power. |
| `weapons-and-mods.md` | Both | Supplies weapon stats (§3.3), TTK targets and caps (§3.4), ammo (§3.7), damage formula (§4.1). This doc replaces its §3.6, §3.8 catalog and §4.7 shop math, and extends §4.1 (§4.3 here). |
| `heroes.md` | Both | Supplies HP / armor (§3.1), CDR cap (§3.4), EHP and skill clamp (§5.1–§5.3), slow cap (§3.6). Needs a note that gear armor is weapon-only and gear resist skill-only. |
| `wardlings-and-economy.md` | Both | Supplies the Lumen curve (§17–§18) and squad upgrades (§7, unchanged). §18 spend split and sink check, and §19 utility items, change (§9). |
| `match-flow-and-map.md` | This → | Siegebreaker uses Ward Generator / Exposed Uplink rules; Stride Clip uses Mana Cell carry. |
| Art bible | This → | Body anchors (§3.8) on 7 hero models; part meshes per item; tier size/glow channels; ammo tracers and impacts. |
| UX / HUD (`design/ux/hud.md`) | This → | Shop tabs (§3.9), inventory strip, scoreboard icons, death card. |
| BuildAdvisor / bots / balance report | This → | Recipe resolution, slot and Signature limits, new signal "enemy gear armor" (§3.10). |
| Server / netcode | This → | Protocol 22, new catalog order and replicated slot state (§3.11), atomic purchases, per-visit transaction log. |
| `design/registry/entities.yaml` | This → | New and changed entries (§9). |

---

## 7. Tuning Knobs

| Knob | Default | Safe range | Category | Affects |
| ---- | ---- | ---- | ---- | ---- |
| Open item slots | 6 | 5–7 | Gate | Build breadth; slot pressure |
| Signature limit | 2 [TUNE] | 2–3 (3 raises the full build to ~14,500) | Gate | Full-build cost and identity |
| Component price | 250–400 [TUNE] | 250–450 | Curve | Early spikes |
| Assembly combine | 250–300 [TUNE] | 200–400 (total 800–1,100) | Curve | Mid-game pacing |
| Signature combine | 750–1,050 [TUNE] | 600–1,200 (total 2,400–3,200; keep ≤ 4 min of average income) | Curve | Dead zones; first-Signature time |
| Sell rate | 60% | 50–75% | Curve | Cost of adapting |
| `M_rate` cap | 0.15 [TUNE] | 0.10–0.20 | Curve | Fire-rate stacking |
| Throughput cap `G` | 1.333 | 1.25–1.40 | Curve | Build TTK cut (§3.4 rule a) |
| Total weapon multiplier cap | 2.25 [TUNE] | 2.1–2.4 | Curve | Ult combo floor |
| Gear armor / resist caps | 0.25 / 0.25 [TUNE] | 0.15–0.35 | Curve | Tankiness of squishies |
| Item HP cap | +250 [TUNE] | 150–350 | Curve | EHP ceiling |
| Item move-speed cap | +12% [TUNE] | 8–15% | Feel | Chase / kite balance |
| Component power share | ~30–40% | 25–45% | Curve | Value of early buys |
| Unique loose stats | on | on / off | Gate | Component rush |
| Passive values (Kindle 30%, Rend 2/8 pts, Brace 15% / 20 s, Lattice 80, Regrowth 2%/s, Grounding 25%, Resonant 25%, Siegebreaker 15%, Long Reach 10% / 1 s) | §3.5.3 [TUNE] | ±40% each | Feel / Curve | Signature identity |
| Advisor: saving-gap target | ≤ 240 s | 180–300 s | Gate | Recommendation order |

All knobs live in `assets/data/economy/` (catalog, advice rules), never in code.

---

## 8. Acceptance Criteria

**Functional (automated, `tests/unit/economy/` unless stated):**
1. Data validator: every Component total is in 250–450, Assembly 800–1,100, Signature 2,400–3,200; `Total = combine + Σ parts` for every item; every component feeds ≥ 2 finished items; every item has a `body_anchor` or socket and a visual-tell key; no single item exceeds any §3.7 cap.
2. Recipe pricing: with Ember Facet in Core and nothing loose, Ember Heart costs 1,600; with an Ember Shard loose, 1,200; from nothing, 2,600 (§4.1 examples).
3. Buying a weapon Assembly whose two components are loose frees 2 open slots and fills the socket in one server step.
4. With 6 slots full, buying a component is refused ("Inventory full"); buying Plate Harness when a Plate Scale and a Vital Cell are among the 6 succeeds and leaves 5.
5. A third Signature and a duplicate Signature are refused with their messages.
6. A second copy of a component adds no stats; selling the first copy activates the second.
7. Undo: a full visit of N purchases undone with Undo last returns exactly the Lumen and inventory held on entering the zone. Undo of a used-up item is blocked with "Undo <item> first".
8. Selling after the visit pays `floor(0.6 × Total / 5) × 5` (Ember Heart 1,560).
9. Throughput sweep over every valid build (all sockets, loose stats, ammo, mods): `G ≤ 1.333` and body TTK_ideal vs a level-matched 250 HP, 0-armor target ≥ 0.80 s without an ultimate (extends `weapons-and-mods.md` AC 2).
10. Armor / resist: a weapon hit on a target with `A_gear 0.13` deals 87% (no pen); with Piercing 92.2%; a skill hit on `R_gear 0.15` deals 85%; TRUE damage is unchanged.
11. Caps: HP from items never exceeds +250, gear armor and resist never exceed 0.25, CDR never exceeds 0.25.
12. Protocol 22: catalog order is pinned by a test; a protocol 21 client is refused at login.
13. Bots: in a 20-bot-match integration run, every bot buys through `ACTION_BUY`, never sends a refused request twice, and never exceeds 6 slots or 2 Signatures (`tests/integration/bots/`).

**Balance (balance report on the §18 curves):**
14. Average curve: first Signature at 10–14 min for gun-first guides; no dead zone over 240 s before 30:00; unspent Lumen at 30:00 ≤ 15% for every hero.
15. Strong curve: full build (2 Signatures + 7 Assemblies + Chamber) reached at 28–33 min with no squad spend; average curve reaches 65–80% of it by 30:00.
16. Spend split on the average curve: items 60–75%, squad 15–30%, consumables 5–15%.

**Visual / experiential (screenshots in `production/qa/evidence/`, playtest):**
17. Every purchase changes the third-person model within 1 frame; QA can name each hero's two Signatures and its armor/resist category from 20 m in a greyscale screenshot.
18. Shop at 720p and 1080p: all three tabs, the recipe tree with ticked parts, "Signatures n/2", Undo last and the inventory strip are readable (screenshot per tab).
19. Playtest (5+ testers): at least 4 of 5 can explain why the Recommended tab offered each Situational item, and no tester reports a "forced path" in the Core section.
20. Telemetry (20+ bot matches, later human matches): no single Signature above 50% pick rate per hero; at least 3 different Core Signatures used per Mana and per Mech hero.

---

## 9. Canon changes required (after owner sign-off; not applied by this draft)

**`game-concept.md`**
- **Pillar 4**, first line → "In-match growth is visible: crystals and chips mounted on the gun, **gear worn on the hero's body (six open item slots)**, Wardling tiers, hero level glyphs, hardpoint ownership on the map." Design test unchanged.
- **C14**, "Spent only at HQ Armory on:" list → "weapon parts built from recipes (Components → Assemblies → Signatures; Crystal form on Mana guns, Chip form on Mechanical guns), **body gear in six open item slots** (health, armor vs weapons, resist vs skills, utility), ammo types and ammo mods, consumables (Med-Packs), Wardling squad upgrades."
- **C16**, last sentence → "Mana guns upgrade with socketed **Crystals**, Mechanical guns with slotted **Chips**: the same weapon items, shown and named in the gun's family form, built from recipes and mounted in Core, Barrel and Frame sockets — all visible on the weapon model."

**`weapons-and-mods.md`**
- §1 Overview: replace "three tiers that map 1:1 to the Armory price bands (Minor / Standard / Major)" with the recipe tiers and point to this doc.
- §3.3.1 heal-beam table: Focus Lens → Lens / Longsight items; Reservoir → Reservoir Frame / Wellframe; Flux Coil → Flux Coil / Feed; Wellspring → Ember Heart's Kindle (counts heal assists).
- §3.4 rule (a): "a fully built weapon" → "a hero's full item build; enforced by the throughput cap G ≤ 1.333 (items-and-armory §3.7)".
- §3.6: replace §3.6.2 (tiers / bands / upgrade-in-place) and §3.6.4 rules 2–4 with a pointer to items-and-armory §3.2–§3.6; keep §3.6.1 sockets (Core / Barrel / Frame hold finished parts only) and §3.6.3 visual channels.
- §3.7: unchanged content; add "all 6 Ammo Types and 5 Ammo Mods ship in protocol 22".
- §3.8: replace the Crystal, Chip and Weave tables and the spending budget with a pointer to items-and-armory §3.5 and §4.7. Remove the Weaves from the Frame socket.
- §3.9 build examples: rewrite with recipe steps (or point to §4.7 here). §3.10 slice: note superseded by the v22 release.
- §4.1: add `M_rate`, `G`, the 2.25 total clamp and the weapon / skill `A_mult` split (items-and-armory §4.3). §4.7 shop math → items-and-armory §4.1, §4.4.
- §7 knobs "Tier power share" and "Price per tier" → items-and-armory §7. §8 AC 3 and AC 8 → items-and-armory AC 1–2.

**`wardlings-and-economy.md`**
- §18 sink check and spend split: full build 11,800–13,050; split ~65–70% items / 20–25% squad / ~10% consumables.
- §19: remove Cell Harness, Stride Rig, Barrier Lattice and Uplink Breaker (now in items-and-armory §3.5); keep Med-Pack, Recall Shard, Scan Flare; bands line adds Component / Assembly / Signature bands.

**`heroes.md`**
- §3.1 note: base Armor applies to all damage; item Armor applies to weapon damage only, item Resist to skill damage only.
- §3.4: external CDR now exists (Cadence items), still capped at 25%.

**`design/registry/entities.yaml`**
- `lumen.price_bands`: add `component: [250, 450]`, `assembly: [800, 1100]`, `signature: [2400, 3200]` (keep the old bands for squad and ammo).
- `bastion_weave`, `null_weave`: `status: replaced` → new entries `bastion_plate`, `null_veil` (values §3.5.3).
- `full_weapon_build` → rename `full_item_build`, `value_lumen: [11800, 13050]`, `revised: <sign-off date>`.
- New constants: `open_item_slots: 6`, `signature_limit: 2`, `cap_m_rate: 0.15`, `cap_throughput: 1.333`, `cap_total_weapon_mult: 2.25`, `cap_gear_armor: 0.25`, `cap_gear_resist: 0.25`, `cap_item_hp: 250`, `cap_item_move_speed: 0.12`, `armory_protocol: 22`, `spend_split: {items: 0.675, squad: 0.225, consumables: 0.10}`.
- Register every v22 catalog item with price and `source: design/gdd/items-and-armory.md` (closes the review's "12 unregistered items" gap).

**Other docs:** `docs/armory.md` ("There is no generic six-slot inventory" and the wire contract), `design/gdd/systems-index.md` (add this GDD), `docs/plans/armory-v2-recipes-gear.md` (mark step 1 done).

---

## Open questions for the owner

1. **Signature limit:** 2 per hero (recommended; full build ≈ 12,400 = strong player at 30 min), 3 (≈ 14,500, nobody finishes), or none?
2. **Loose weapon components give stats** at once (recommended), or are they inert until mounted?
3. **Unique loose stats** (one active copy per component): OK?
4. **"6 body/gear items" = the 6 gear Signatures**, with §19's Cell Harness, Stride Rig, Barrier Lattice and Uplink Breaker folded into the tree: is that the intended reading?
5. **One item, two forms** (Crystal / Chip share one stat block): OK, or keep separate Crystal and Chip catalogs?
6. **Penetration cuts gear armor** (Piercing gains value vs every hero): OK?
7. **Damage types:** do Wardling, Sentinel and turret shots count as weapon damage (armor) as assumed here?
8. **Undo:** per-item undo with "undo the later item first", plus Undo last (recommended), or Undo last only?
9. **Brannoc 2.5× rule** is already broken at 60% pen (2.39×). Lower the pen cap to 0.55, or relax the rule to 2.3×?
10. **Spend split** 65–70% items / 20–25% squad / ~10% consumables: accept?
11. **Squad upgrades and Med-Packs outside open slots** (recommended): confirm.
