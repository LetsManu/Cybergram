# Weapons & Mods (Gun Systems, Mount System, Ammo Types)

*Created: 2026-10-02*
*Status: Draft — authored autonomously by systems-designer + economy-designer (modes.automation: autonomous, rigor: minimal). All 8 standard GDD sections are included even though `minimal` requires none, because this system defines damage, prices and caps that other docs will tune against.*
*Binding source: `design/gdd/game-concept.md` → **## Canon** (C1–C18). Owner intent: `/ideas` → "Weapons".*
*Sibling docs written in parallel: `heroes.md` (owns hero HP/armor, archetype intent, skills), `wardlings-and-economy.md` (owns Lumen income, Wardling drops and squad upgrades), art bible (owns palette and shape language). Where this doc assumes one of their values, it is marked **[assumed: owner doc]**.*

---

## 1. Overview

Every hero carries **one signature weapon** (no weapon swapping, no pickups) and it is their primary damage source (Anti-Pillar: guns are not decoration). Weapons are fed one of two ways (C16): **Mana guns** fire from a recharging pool; **Mechanical guns** fire from magazines backed by a finite reserve. During a match the player spends Lumen at the HQ Armory (C14) to **mount** upgrades physically onto the gun: **Crystals** on Mana guns, **Chips** on Mechanical guns, into fixed **sockets** (Core, Barrel, Frame) plus a **Chamber** that holds one **Ammo Type** and one **Ammo Mod**. Each mount comes in three tiers that map 1:1 to the Armory price bands (Minor / Standard / Major), and every tier changes the weapon's mesh, VFX and sound so an opponent can read your build from across a lane (Pillar 4). Everything resets at match end.

## 2. Player Fantasy

*"My gun is my story this match."* At minute 2 your rifle is bare steel; by minute 25 it hums with a fist-sized heart crystal, a lens ring at the muzzle and incendiary embers trailing every shot. Enemies see it coming, and you see theirs: a Brannoc whose scattergun has grown a glowing three-fin Overclock module is a different threat from one with a bare barrel. Mana players feel like casters who must breathe between volleys; Mechanical players feel like soldiers who count rounds and protect their supply lines.

---

## 3. Detailed Rules

### 3.1 Weapon architecture

1. Each hero has exactly one weapon, bound to the hero. There are no weapon drops, pickups or swaps. Alt-fire behaviour (if any) is part of the hero kit and owned by `heroes.md`; this doc owns the primary fire stat model only.
2. Hitscan is the default. Projectiles are used only where noted (Liora). No weapon has lock-on or aim magnetism (Pillar 2). Bots use the same weapons with handicapped aim, not altered stats.
3. Hit zones: **Head** (multiplied by the weapon's headshot multiplier) and **Body** (×1.0). No limb zone. Wardlings, Sentinels and structures have no head zone.
4. Weapons scale with hero level by a single shared damage multiplier (§4.2), so equal-level TTK stays stable across the match. Fire rate, falloff, feed and spread do **not** scale with level; only mounts change them.
5. There is no friendly fire. Ammo effects never apply to allies.

### 3.2 Stat model

Every weapon is defined by the same record. Mana guns use the pool fields; Mechanical guns use the magazine fields.

| Stat | Unit | Meaning |
| ---- | ---- | ---- |
| `damage` | HP per hit (per pellet / per tick) | Base damage at level 1, before falloff/armor |
| `fire_rate` | shots/s | Cycle rate; bursts list burst size + cycle |
| `headshot_mult` | × | Applied on head hits |
| `falloff_start` / `falloff_end` / `falloff_min` | m, m, × | Full damage up to start, linear down to `falloff_min` at end, flat beyond |
| `spread_base` / `spread_bloom` / `spread_max` | degrees (cone half-angle) | First-shot cone, growth per shot, cap; recovers at 6°/s after 0.15 s without firing |
| `recoil_v` / `recoil_h` | degrees per shot | Vertical kick, horizontal random ±; camera recovers 80% within 0.3 s of stopping |
| **Mana:** `pool`, `cost`, `regen`, `regen_delay` | mana, mana/shot, mana/s, s | Regen starts `regen_delay` after the last shot |
| **Mechanical:** `magazine`, `reserve`, `reload`, `reload_empty` | rounds, rounds, s, s | Reload moves rounds from reserve to magazine |

### 3.3 Signature weapon table (level 1, unmodded)

Range bands: **CQ** ≤ 12 m, **Mid** 12–30 m, **Long** 30 m+. `heroes.md` owns each hero's archetype intent and range band; if it differs from a row below, `heroes.md` wins on archetype and band, and this table must be re-tuned to the TTK targets in §3.4.

| Weapon | Hero | Feed | Archetype / band | Dmg | Rate | HS× | Falloff (m → min) | Spread base/bloom/max | Recoil V/H | Feed values | Body DPS |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| **Vanguard AR-7** | Ryker Vance | Mech | Full-auto rifle, hitscan / Mid | 26 | 10/s | 2.0 | 22–40 → 0.60 | 0.4 / 0.12 / 2.2 | 0.35 / 0.15 | Mag 30, reserve 150, reload 1.6 s (empty 1.9 s) | 260 |
| **Ironmaw** | Brannoc | Mech | Pump scattergun, 10 pellets / CQ | 11 ×10 | 1.43/s (0.7 s) | 1.25 | 6–14 → 0.30 | fixed 5.5° cone | 4.0 / 1.0 | Mag 6, reserve 30, reload 0.45 s per shell (interruptible) | 157 |
| **Tackhammer** | Juniper Quill | Mech | Semi-auto rail-tack rifle / Long | 58 | 3/s cap | 2.0 | 30–55 → 0.70 | 0.1 / 0.6 / 2.0 | 1.6 / 0.3 | Mag 10, reserve 50, reload 2.0 s (empty 2.4 s) | 174 |
| **Halo Repeater** | Liora Vale | Mana | Full-auto projectile (90 m/s) / Mid | 32 | 5/s | 1.5 | 20–35 → 0.60 | 0.6 / 0.15 / 2.0 | 0.25 / 0.10 | Pool 100, 4/shot, regen 40/s, delay 0.8 s | 160 |
| **Threadcaster** | Vesper Loom | Mana | Semi-auto hitscan carbine / Mid | 40 | 4.5/s cap | 1.75 | 25–45 → 0.60 | 0.2 / 0.4 / 2.0 | 0.9 / 0.2 | Pool 100, 6/shot, regen 35/s, delay 1.0 s | 180 |
| **Whisperfang** | Sable | Mana | 3-round burst SMG, hitscan / CQ–Mid | 22 | 3-burst @15/s, 0.35 s cycle (8.57/s) | 2.25 | 12–25 → 0.50 | 0.5 / 0.2 / 2.5 | 0.5 / 0.25 | Pool 100, 3/bolt, regen 45/s, delay 0.6 s | 188 |
| **Glitchcaster** | Hex | Mana | Continuous beam, hitscan, 15 m hard max / CQ | 6→12 per tick, 20 ticks/s, ramps over 1.2 s | — | 1.0 (no HS) | 10–15 → 0.75 | n/a (beam sway 0.3°) | n/a | Pool 100, drain 22/s, regen 30/s, delay 1.2 s | 120→240 |

Ryker keeps the highest sustained body DPS and the highest headshot DPS (Canon C17: "highest sustained DPS").

### 3.4 Time-to-kill targets

Reference targets **[assumed: heroes.md]** at level 1: **Light** 250 HP / 0 armor (Sable, Hex); **Medium** 300 HP / 10 armor (Ryker, Juniper, Liora, Vesper); **Heavy** 550 HP / 30 armor (Brannoc). TTK = body shots only, optimal range, equal level, every shot hits, unmodded (formula §4.4).

| Weapon | vs Light | vs Medium | vs Heavy | All-headshot vs Medium | Target band vs Medium (body) |
| ---- | ---- | ---- | ---- | ---- | ---- |
| Vanguard AR-7 | 0.90 s | 1.20 s | 2.70 s | 0.60 s | **DPS: 1.0–1.3 s** |
| Whisperfang | 1.18 s | 1.53 s | 3.16 s | 0.70 s | Assassin: 1.4–1.7 s (relies on headshots / kit) |
| Ironmaw (all pellets) | 1.40 s | 1.40 s | 2.80 s | 1.40 s | **Tank CQ: 1.2–1.6 s** |
| Tackhammer | 1.33 s | 1.67 s | 3.33 s | 0.67 s | Marksman: 1.5–1.8 s, ≤ 0.7 s headshots |
| Threadcaster | 1.33 s | 1.78 s | 3.78 s | 0.89 s | Flex: 1.5–1.9 s |
| Glitchcaster | 1.35 s | 1.70 s | 2.95 s | — | Flex CQ: 1.5–1.9 s |
| Halo Repeater | 1.60 s | 2.00 s | 4.40 s | 1.20 s | **Support: 1.8–2.2 s** |

Global rules: (a) a **fully built** weapon (Tier III Core + matching Barrel/Frame + ammo type) may cut body TTK by **15–25%**, never more; (b) **no weapon may kill a Medium target with body shots in under 0.70 s** at any build or level parity; (c) Heavy TTK must stay ≥ 2× Medium TTK for every non-tank weapon.

### 3.5 Mana guns vs. Mechanical guns

| Aspect | Mana gun | Mechanical gun |
| ---- | ---- | ---- |
| Rhythm | Volley → breathe. Fire until the pool runs low, step back during `regen_delay`, re-engage. | Magazine → reload. Burst a full magazine harder than any pool, then a committed reload. |
| Downtime | Soft: can fire any time there is mana; no reload animation. | Hard: reload locks fire for 1.6–2.4 s. |
| Sustain over a life | Infinite (pool always regenerates). | Finite: `magazine + reserve` rounds. Refill at Armory (full), **Supply Cache** (C5: +25% of max reserve per second while inside 3 m, i.e. 4 s to full), and **Ammo Sparks** dropped by enemy Wardlings (+1 magazine of reserve each **[drop rate owned by wardlings-and-economy.md]**). |
| Burst per load | Lower (pool damage 640–800). | Higher (Ryker magazine = 780, Ironmaw 6 shells = 660, Tackhammer 580 with headshot ceiling 1,160). |
| **Burnout** | Emptying the pool to 0 triggers **Burnout**: `regen_delay` ×1.5 and the weapon's crystals go dark. | — |
| **Dry** | — | Magazine and reserve both 0: trigger plays a dry click; the hero cannot fire until a refill source. |
| Readable tell (for enemies) | Crystal glow on the gun = current pool %; Burnout plays a crackle audible within 15 m. | Reload animation + magazine-drop sound audible within 15 m; last 20% of magazine plays a higher-pitched "low ammo" tick audible to the shooter only. |
| Counterplay against | Bait the volley, punish the regen delay, hit them with **Shock** (resets regen delay) or **Siphon**-pressure; force fights longer than one pool. | Punish reloads, fight away from their held Supply Caches, kill Wardlings before they drop Sparks, **Shock** lengthens reloads. |
| Fiction | Shots are shaped Cybergram signal. | Mana-powered war-tech firing physical rounds. |

### 3.6 The Mount System

**Principle:** every purchase is a physical object mounted on the gun. No invisible stat item exists (Pillar 4 design test).

#### 3.6.1 Sockets (identical layout on all 7 weapons)

| Socket | Count | Holds | Changes | Mount point on model |
| ---- | ---- | ---- | ---- | ---- |
| **Core** | 1 | Core Crystal / Core Chip | Damage profile: damage, fire rate, headshot, on-kill sustain | Receiver top / heart of the gun, visible in first-person view |
| **Barrel** | 1 | Barrel Crystal / Chip | Range: falloff, spread, projectile speed / beam range, armor penetration | Muzzle and barrel shroud |
| **Frame** | 1 | Frame Crystal / Chip | Feed & handling: pool, regen, magazine, reload, recoil | Grip, stock and side plates |
| **Chamber** | 1 Ammo Type + 1 Ammo Mod | Ammo Type, Ammo Mod (§3.7) | On-hit effects | Mana: the mana conduit / pool glow; Mech: magazine window and tracer |

Every weapon is authored with four attach markers (`socket_core`, `socket_barrel`, `socket_frame`, `socket_chamber`) as `Marker3D` nodes in first- and third-person rigs. Mount meshes are shared per family and placed via per-weapon scale/offset presets, so the art cost is *families × tiers*, not *families × tiers × weapons*.

#### 3.6.2 Tiers (rarity) and price bands

Each Crystal/Chip is a **line** with three tiers. Tier = rarity = price band. A socket holds one tier of one line.

| Tier | Rarity name (Crystal / Chip) | Price band | Power share | Visual signal |
| ---- | ---- | ---- | ---- | ---- |
| I | **Shard** / **Mk I** | Minor 250–400 | ~40% of the line's max effect | Small: thumb-size crystal / single circuit card. Low glow. |
| II | **Facet** / **Mk II** | Standard 600–900 | ~70% | Medium: twin facets with orbiting motes / card + heatsink fins + LED strip. Medium glow, slow pulse. |
| III | **Heart** / **Mk III** | Major 1,400–1,800 | 100% | Large: heart crystal with halo ring / full module with exposed core and moving parts. Strong glow, idle animation, unique sound tail. |

- **Upgrading in place:** buying a higher tier of the line already in that socket costs `list(new) − list(held)` (§4.6). Total cost of a Tier III line = its Tier III list price. Tiers can be skipped (buy III directly at list price).
- Tier readability uses **size, facet/fin count, glow intensity and idle animation**, never colour alone (accessibility). Each line has a family hue (§3.8) that the art bible must keep out of the team blue and team red hue ranges.

#### 3.6.3 How mounts change model, VFX and sound

| Socket | Model | VFX | Sound |
| ---- | ---- | ---- | ---- |
| Core | Crystal / chip module grows with tier on the receiver. | Muzzle flash takes the line's family hue; Tier III adds a halo ring flash every 5th shot (Ironmaw and Tackhammer: every shot). | Adds a tonal layer to the shot (I: faint harmonic, II: clear harmonic, III: harmonic + unique tail per line). |
| Barrel | Lens rings (Crystal) or shroud/rail (Chip) at the muzzle; count = tier. | Tracer length and shape (Focus/Rifling: longer, thinner tracer; Stillwater/Stabilizer: tighter muzzle cone; Velocity: speed streaks). | Changes the shot's tail and reverb envelope. |
| Frame | Side crystals / plate chips on grip and stock. | Mana: crystals pulse during regen (pulse speed = regen rate). Mech: animated LED counter on the stock = rounds left. | Reload / regen foley layer (Quickload: snappier mag seat; Flux: rising chime during regen). |
| Chamber | Mana: conduit glow takes the infusion hue. Mech: magazine window shows tinted rounds. | **Projectile/tracer colour and impact effect = ammo type** (the strongest channel for the target). | Distinct impact sound per ammo type, audible to the victim. |

Enemy build readability: the third-person model shows every mount; the scoreboard (Tab) lists each enemy's mounts as icons; the death card shows the killer's full build. Cosmetic VFX unlocks (concept: "crystal VFX colours") may recolour **Core/Barrel/Frame family hues only**; tier size/glow channels and **ammo-type impact VFX are not recolourable** (gameplay information).

#### 3.6.4 Buying, swapping and selling rules

1. Mounts are bought, swapped and sold **only inside your own HQ Armory zone** while alive (C6, C14). Not at Forward Beacons. Shop disabled during Sudden Death (C10); mounts are kept into Sudden Death.
2. **Socket limit:** one mount per socket; one Ammo Type and one Ammo Mod in the Chamber. Crystals only fit Mana guns; Chips only fit Mechanical guns. Lines marked with a weapon restriction (catalog §3.8) are greyed out for other weapons.
3. **Swap:** buying a different line for an occupied socket automatically sells the held mount (rule 4), then buys the new one. Same rule for Ammo Type and Ammo Mod.
4. **Sell value:** 100% of Lumen paid if sold during the **same Armory visit** it was bought in (undo; the visit ends when the player leaves the Armory zone or dies). Otherwise **60%** of total Lumen paid for that mount's line (all tiers), rounded down to a multiple of 5.
5. Mounts persist through death and respawn for the rest of the match. A bot that replaces a disconnected player (C1) inherits that player's mounts and Lumen; a reconnecting player gets them back.
6. **No persistent power:** all mounts, ammo types and Lumen are deleted at match end (Anti-Pillar). Account progression may unlock cosmetic recolours only.
7. An Ammo Mod requires an Ammo Type in the Chamber. Selling the Ammo Type also sells the Ammo Mod. Swapping the Ammo Type keeps the Mod only if it is compatible with the new type (§3.7.2); otherwise the Mod is sold.

### 3.7 Ammo Types (Chamber)

Mana guns call them **Infusions**; Mechanical guns call them **Rounds**. Same six effects for both families, same prices. The default is **Standard** (free, no effect). Every effect scales with **final damage dealt**, so it works fairly on a 10/s rifle, a 10-pellet shotgun and a 20-tick beam (§4.5).

#### 3.7.1 Ammo Type catalog

| Ammo Type | Effect (base numbers) | Best on | Counters |
| ---- | ---- | ---- | ---- |
| **Piercing** | Ignores **40%** of target armor. +25% damage vs hero-deployed shields (Brannoc's shield wall). | Ryker, Juniper vs Brannoc / armored builds | Bring raw HP rather than armor; outrange it (does nothing to falloff). Useless vs 0-armor Light heroes. |
| **Incendiary** | Each hit adds **12%** of its final damage to the target's **Burn pool**; the pool deals itself out over **3 s** (refreshed on hit, max **35 burn DPS**). Burning targets are **Scorched**: −30% healing received. | Ryker, Hex, Whisperfang vs Liora-supported teams | Disengage 3 s; Liora's cleanse **[assumed: heroes.md]**; heal through it (only −30%); Mender Wardlings. |
| **Shock** | Each hit adds **0.6 × final damage** to the target's Charge; at 100 → **Overload**: 30 damage arcs to up to 2 other enemies within 6 m (Wardlings count), and the target's weapon is **Disrupted 1.0 s** (Mana: regen paused and `regen_delay` restarted; Mech: current or next reload +0.5 s). Charge decays 25/s after 1 s without hits; Overload once per 3 s per target. | Vesper, Juniper vs grouped squads and Mana heroes | Spread out from your squad; fight at full pool / full mag so Disrupted hurts less; break line of sight before Charge fills. |
| **Siphon** | Heals the shooter for **8%** of final damage dealt to heroes (4% vs Wardlings, 0% vs structures). Mana guns also restore mana equal to **6%** of final damage. No overheal. | Liora, Sable, Brannoc for sustain | Incendiary (Scorched cuts Siphon healing by 30%); burst them instead of trading; deny targets (Siphon from nothing is nothing). |
| **Cryo** | Each hit adds **0.5 × final damage** to the target's Chill meter (0–100). Slow = **25% × meter/100**. Meter decays 30/s after 0.75 s without hits. At 100 → **Brittle** 2 s: target takes **+8%** damage, then meter resets and Brittle cannot re-trigger on that target for 4 s. | Halo Repeater, Threadcaster vs divers (Sable) | Movement skills; break line of sight for 0.75 s; slow cap is 25% and never roots or stuns. |
| **Sunder** | **+35%** damage vs constructs (Wardlings, Garrison Sentinels, traps, deployables, drones), **+20%** vs Barricades and Ward Generators, **−10%** vs heroes, **+0%** vs Mana Uplink. | Anyone pushing hardpoints; Brannoc on Breach tasks | Take the hero fight: Sunder users lose 10% damage to heroes. |

Global ammo rules: the Mana Uplink is **immune to all ammo effects** (only base damage applies; protects Canon C7's ~60 s siege target). Structures (Barricades, Ward Generators) take Sunder/Piercing damage modifiers but no status effects. Wardlings and Sentinels take every effect. Effects from different shooters stack independently (separate Burn pools, Charge meters); Chill uses one shared meter per target.

#### 3.7.2 Ammo Mods (owner: "ammo can also be modded in specific ways")

One Ammo Mod slot per Chamber. A Mod changes **how the loaded Ammo Type behaves**; it does nothing on Standard ammo. Potency = the Ammo Type's headline number (Piercing %, Burn %, Charge/Chill multiplier, Siphon %, Sunder bonus).

| Ammo Mod | Effect | Piercing | Incendiary | Shock | Siphon | Cryo | Sunder |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| **Saturated** | Potency ×1.3 | ✓ 52% | ✓ 15.6% | ✓ 0.78 | ✓ 10.4% / 7.8% | ✓ 0.65 | ✓ +45.5% (penalty unchanged) |
| **Lingering** | Effect duration ×1.5 | — | ✓ burn over 4.5 s (cap unchanged) | ✓ Disrupted 1.5 s | — | ✓ Brittle 3 s, decay delay 1.1 s | — |
| **Volatile** | On kill, the effect bursts to enemies within 4 m (not recursive) | — | ✓ adds 40% of victim's remaining Burn pool to each | ✓ free Overload arc (30 dmg, ≤2 targets) | ✓ heals you and allies within 8 m for 40 HP | ✓ +50 Chill to each | ✓ 30 dmg to each construct (Wardling kills too) |
| **Tracer** | Hits that apply the effect mark the target for your team (outline through walls) for 1.5 s; refreshes on hit | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (marks only heroes) |
| **Overcharged** | Potency ×1.5, but mana `cost` +20% (Mana) / `reload` +15% (Mech) | ✓ 60% (cap) | ✓ 18% | ✓ 0.9 | ✓ 12% / 9% | ✓ 0.75 | ✓ +52.5% |

"—" = incompatible; the Armory greys the mod out and rule 3.6.4-7 applies on ammo swap.

### 3.8 Full catalog with prices

All prices are list prices; every tier sits inside its band (Tier I Minor 250–400, Tier II Standard 600–900, Tier III Major 1,400–1,800). Effects listed I / II / III. Hue = family colour for art (must avoid team blue/red hue ranges).

#### Crystals (Mana guns: Liora, Vesper, Sable, Hex)

| ID | Line | Socket | Effect (I / II / III) | Restriction | Price I / II / III | Hue |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| CR-1 | **Ember Heart** | Core | Damage +6% / +11% / +16% | — | 400 / 900 / 1,800 | amber |
| CR-2 | **Tempest Shard** | Core | Fire rate +5% / +10% / +14% (Hex: tick damage +5/10/14%) | — | 400 / 900 / 1,800 | violet |
| CR-3 | **Prism Eye** | Core | Headshot mult +0.15 / +0.30 / +0.45 (Hex: ramp time −15/−25/−35%) | — | 350 / 850 / 1,700 | white |
| CR-4 | **Wellspring** | Core | On kill/assist restore 25% / 40% / 60% pool; III also: next 2 s regen ignores delay | — | 350 / 800 / 1,600 | green |
| CR-5 | **Focus Lens** | Barrel | Falloff start & end +12% / +20% / +30% | Not Hex | 300 / 700 / 1,500 | white |
| CR-6 | **Stillwater Ring** | Barrel | Spread base, bloom and max −15% / −25% / −35% | Not Hex | 250 / 650 / 1,400 | teal-green |
| CR-7 | **Velocity Facet** | Barrel | Projectile speed +20/35/50% (Liora); beam max range +2/+3.5/+5 m (Hex) | Liora, Hex only | 250 / 600 / 1,400 | magenta |
| CR-8 | **Reservoir** | Frame | Pool +20% / +35% / +50% | — | 300 / 700 / 1,500 | green |
| CR-9 | **Flux Coil** | Frame | Regen +15/25/35% and regen delay −0.1/−0.2/−0.3 s | — | 350 / 800 / 1,600 | violet |
| CR-10 | **Anchor Crystal** | Frame | Recoil −15% / −25% / −35% (Hex: beam sway −) | — | 250 / 650 / 1,400 | amber |

#### Chips (Mechanical guns: Ryker, Brannoc, Juniper)

| ID | Line | Socket | Effect (I / II / III) | Restriction | Price I / II / III | Hue |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| CH-1 | **Overclock** | Core | Damage +6% / +11% / +16% | — | 400 / 900 / 1,800 | amber |
| CH-2 | **Cyclic Governor** | Core | Fire rate +5% / +10% / +14% (Ironmaw: pump cycle −) | — | 400 / 900 / 1,800 | violet |
| CH-3 | **Ballistic Solver** | Core | Headshot mult +0.15 / +0.30 / +0.45 (Ironmaw: +0.05/0.10/0.15) | — | 350 / 850 / 1,700 | white |
| CH-4 | **Feedback Loop** | Core | On kill/assist refill 30% / 50% / 75% of magazine from nothing (no reload, does not use reserve) | — | 350 / 800 / 1,600 | green |
| CH-5 | **Rifling** | Barrel | Falloff start & end +12% / +20% / +30% | — | 300 / 700 / 1,500 | white |
| CH-6 | **Stabilizer** | Barrel | Spread −15/25/35% (Ironmaw: pellet cone −10/18/25%) | — | 250 / 650 / 1,400 | teal-green |
| CH-7 | **Penetrator** | Barrel | Armor penetration +10% / +18% / +25% (adds to Piercing, total cap 60%) | — | 300 / 700 / 1,500 | magenta |
| CH-8 | **Extended Mag** | Frame | Magazine and reserve +20% / +35% / +50% (round down, min +1) | — | 300 / 700 / 1,500 | green |
| CH-9 | **Quickload** | Frame | Reload time −12% / −22% / −30% | — | 350 / 800 / 1,600 | violet |
| CH-10 | **Gyro** | Frame | Recoil −15% / −25% / −35% | — | 250 / 650 / 1,400 | amber |

#### Ammo Types and Ammo Mods (both families; not tiered)

| ID | Item | Kind | Band | Price |
| ---- | ---- | ---- | ---- | ---- |
| AM-0 | Standard | Ammo Type | — | free (default) |
| AM-1 | Piercing | Ammo Type | Standard | 750 |
| AM-2 | Incendiary | Ammo Type | Standard | 800 |
| AM-3 | Shock | Ammo Type | Standard | 800 |
| AM-4 | Siphon | Ammo Type | Standard | 850 |
| AM-5 | Cryo | Ammo Type | Standard | 750 |
| AM-6 | Sunder | Ammo Type | Standard | 650 |
| MD-1 | Saturated | Ammo Mod | Minor | 350 |
| MD-2 | Lingering | Ammo Mod | Minor | 300 |
| MD-3 | Volatile | Ammo Mod | Minor | 400 |
| MD-4 | Tracer | Ammo Mod | Minor | 300 |
| MD-5 | Overcharged | Ammo Mod | Minor | 350 |
| — | Med-Pack (consumable, reference) | Consumable | fixed | 100 |

Catalog size: 10 Crystal lines + 10 Chip lines (60 tier entries), 6 Ammo Types, 5 Ammo Mods.

#### Spending budget (economy check)

A full weapon build costs `Core III + Barrel III + Frame III + Ammo Type + Ammo Mod` = **5,250–6,200 Lumen**, i.e. **58–69%** of the ~9,000 Lumen a player earns in 30 minutes. The remaining ~2,800–3,750 goes to Wardling squad upgrades/variants and Med-Packs (owned by `wardlings-and-economy.md`). The design intent: a player who spends only on the gun is fully built around minute 20–22; a balanced spender completes the gun at ~28–32 min. Target: **no player completes both a full gun and a maxed squad before 30:00** in median telemetry. The shop is an exhaustible sink (~6,200 max on the gun), so Lumen earned after a full build only has squad and Med-Pack sinks; this is acceptable because it coincides with Surge II and the end of a typical match.

### 3.9 Build examples

Lumen timeline **[assumed: wardlings-and-economy.md]**: ~600 starting Lumen, ~1,500 by 6:00, ~4,000 by 15:00, ~6,500 by 22:00, ~9,000 by 30:00. Purchases happen on HQ visits.

**Ryker Vance — "Line Breaker" (anti-tank DPS, ~5,450 gun)**
1. 0:00: Overclock I (400). 2. ~5:00: Rifling I (300) + Piercing (750). 3. ~11:00: Overclock II (+500). 4. ~16:00: Gyro II (650). 5. ~21:00: Overclock III (+900). 6. ~27:00: Rifling III (+1,200), Saturated (350) → Piercing at 52% pen.
Result vs Brannoc (30 armor) at 20 m, level 12: per body hit 33.6 vs 25.5 unmodded (×1.32) → ~24% shorter TTK, just inside the 25% cap (§3.4). At 30 m Rifling also removes most falloff, so the gap is larger there; that is range extension, not optimal-range lethality. Visual: amber three-fin module on the receiver, double rail shroud, steel-blue Piercing tracers.

**Liora Vale — "Lifeline" (sustain support, ~5,550 gun)**
1. 0:00: Flux Coil I (350). 2. ~6:00: Siphon (850). 3. ~12:00: Velocity Facet II (600). 4. ~18:00: Flux Coil III (+1,250). 5. ~24:00: Wellspring III (1,600). 6. ~29:00: Volatile (400) → kills heal her and nearby allies 40 HP.
Plays as: longer Halo volleys, faster refill, heals herself on hits, and turns every kill into a small team heal. Visual: green heart crystal, violet pulsing side crystals, magenta lens, siphon-green bolts.

**Brannoc — "Breach Anchor" (objective tank, ~5,250 gun)**
1. 0:00: Sunder (650). 2. ~7:00: Stabilizer I (250) + Extended Mag I (300). 3. ~13:00: Extended Mag II (+400). 4. ~19:00: Feedback Loop III (1,600). 5. ~26:00: Stabilizer III (+1,150), Volatile (400).
Plays as: deletes Ward Generators, traps and enemy squads on Breach/Hold tasks; Feedback Loop refills shells on hero kills/assists (not Wardling kills, §5); Volatile turns each Wardling kill into splash on the rest of the squad. Weak vs heroes (−10%), which his team covers.

### 3.10 Vertical slice subset (Tier 1)

The concept's Scope Tiers put "Crystals/Chips visible upgrades, ammo types" at Alpha, but the Tier 1 slice already includes a Lumen shop and must answer "does a full match land in 25–35 min?", which depends on spend pacing. The slice therefore ships the **pipeline with minimal content** (see Canon Concerns):

| In slice | Content |
| ---- | ---- |
| Weapons | 4: Vanguard AR-7, Halo Repeater, Threadcaster, Ironmaw (slice heroes) |
| Sockets | Core + Frame + Chamber (no Barrel socket in slice) |
| Lines | Crystals: Ember Heart, Flux Coil. Chips: Overclock, Quickload. All 3 tiers each. |
| Ammo | Piercing, Sunder. No Ammo Mods. |
| Visuals | Greybox mounts: one primitive mesh per line, scaled by tier, emissive per tier; ammo tracer colour. No unique sounds; one generic "mount" pitch layer per tier. |
| Rules | Full buy / upgrade-in-place / sell / undo rules; death persistence; reset at match end. |
| Out of slice | Barrel socket, Ammo Mods, Incendiary/Shock/Siphon/Cryo, remaining lines, final mount art and audio, scoreboard build icons. |

---

## 4. Formulas

### 4.1 Final damage per hit

`D_final = D_base × L(level) × F(d) × H × (1 + M_dmg) × A_mult × V_mult × B_brittle`

| Symbol | Type | Range | Description |
| ---- | ---- | ---- | ---- |
| D_base | float | 6–58 | Weapon `damage` per hit / pellet / tick (§3.3) |
| L | float | 1.00–1.35 | Level multiplier (§4.2) |
| F(d) | float | 0.30–1.00 | Falloff multiplier at distance d (§4.3) |
| H | float | 1.0 or 1.0–2.70 | 1.0 body; `headshot_mult` (+Prism/Solver up to +0.45) head |
| M_dmg | float | 0–0.25 | Sum of additive damage mods (Core +0.16 max, hero skills **[heroes.md]**); **capped at +0.25** |
| A_mult | float | 0.625–1.0 | `100 / (100 + A_eff)` |
| A_eff | float | 0–60 | `A × (1 − min(0.60, P))`, A = target armor 0–60 **[heroes.md]**, P = Piercing + Penetrator |
| V_mult | float | 0.90–1.35 | Target-class modifier (Sunder: 1.35 constructs, 1.20 structures, 0.90 heroes; else 1.0) |
| B_brittle | float | 1.0 or 1.08 | Cryo Brittle |
| D_final | float | ≥ 0.9 (clamped ≥ 1 for display) | Damage applied |

Output range: min ≈ 6 × 1.0 × 0.75 × 1.0 × 1 × 0.625 × 0.9 ≈ 2.5 (Hex first tick at range vs 60 armor with Sunder); max ≈ 58 × 1.35 × 1 × 2.45 × 1.25 × 1.0 × 1.0 × 1.08 ≈ 259 (Tackhammer headshot, L15, Ballistic Solver III, Brittle). No division by zero (denominator ≥ 100). Never negative.

**Worked example:** Ryker, level 10, Overclock III, Piercing, 30 m, body, vs Brannoc (A = 30).
L = 1 + 0.025 × 9 = 1.225; F(30) = 1 − 0.4 × (8/18) = 0.822; A_eff = 30 × 0.6 = 18 → A_mult = 0.847.
D = 26 × 1.225 × 0.822 × 1.0 × 1.16 × 0.847 = **25.7** (without Piercing: 23.4).

### 4.2 Level multiplier

`L(level) = 1 + k_lvl × (level − 1)`, k_lvl = 0.025, level 1–15 (C12) → 1.00–1.35. Assumes `heroes.md` grows hero HP at a similar ~2.5%/level so equal-level TTK holds; a 5-level gap gives the higher hero ~12% more damage.

### 4.3 Falloff

`F(d) = 1` if d ≤ r0; `F(d) = 1 − (1 − f_min) × (d − r0)/(r1 − r0)` if r0 < d < r1; `F(d) = f_min` if d ≥ r1. r0, r1 in metres (×(1 + Focus/Rifling bonus)); f_min 0.30–0.75. Example: Halo Repeater at 30 m: 1 − 0.4 × 10/15 = 0.733.

### 4.4 Time to kill

`N = ceil(HP_eff / D_final)`; `TTK = (N − 1) / fire_rate + R_extra`
R_extra = reload time × number of reloads needed if N > magazine (Mech), or Burnout wait if N × cost > pool (Mana); bursts use cycle timing (Whisperfang: shot k at `floor((k−1)/3) × 0.35 + ((k−1) mod 3) × 0.067` s).
Example: Ryker vs Medium (300 HP, 10 armor): D = 26 × 0.909 = 23.6 → N = 13 → TTK = 12/10 = **1.20 s**. Hex uses the integral of the ramp: damage in the first 1.2 s = 24 ticks × 9 avg = 216 raw.

### 4.5 Ammo effect accumulation

`Meter += k_type × D_final × Pot` per hit; Burn pool `+= 0.12 × D_final × Pot`; Siphon heal `= s × D_final × Pot`.
| Symbol | Range | Description |
| ---- | ---- | ---- |
| k_type | Shock 0.6, Cryo 0.5 | Meter gain per damage |
| Pot | 1.0, 1.3 (Saturated), 1.5 (Overcharged) | Ammo Mod potency |
| s | 0.08 heroes / 0.04 Wardlings | Siphon fraction |
Because accumulation is proportional to damage, proc rate ∝ DPS regardless of fire rate. Example: Ryker (23.6 vs Medium) builds Shock Charge 14.2/hit → Overload on hit 8 (0.7 s); Ironmaw full hit (100) → Overload on the 2nd shot.

### 4.6 Mana duty cycle

`T_fire = pool / (cost × fire_rate)`; `T_refill = regen_delay + pool / regen`; `Uptime = T_fire / (T_fire + T_refill)`.
Threadcaster: T_fire = 100/27 = 3.70 s; T_refill = 1.0 + 2.86 = 3.86 s; uptime 49%. With Flux Coil III: regen 47.25, delay 0.7 → T_refill 2.82 s, uptime 57%. Burnout multiplies regen_delay by 1.5.

### 4.7 Shop math

`UpgradeCost = list(tier_new) − list(tier_held)` (held tier of the same line; 0 if empty).
`SellValue = 100% × paid` (same Armory visit) else `floor(0.6 × paid_line_total / 5) × 5`.
Example: Overclock I (400) → II pays 500 → III pays 900; total paid 1,800; sell later = 1,080.

---

## 5. Edge Cases

| Situation | Resolution |
| ---- | ---- |
| Selling Reservoir / Extended Mag while the pool or magazine is above the new max | Current value clamps to the new max; excess is lost (Mech: excess rounds return to reserve up to its max). |
| Buying Extended Mag mid-magazine | Max rises; current rounds unchanged until next reload or refill. |
| Swapping Ammo Type (Mech) with rounds loaded | All loaded and reserve rounds convert to the new type instantly; no ammo is lost or refunded. |
| Death while Burnout or reloading | Pool and magazine are full on respawn; mounts kept. |
| Feedback Loop / Wellspring on Wardling kills | Trigger only on hero kills/assists, not Wardlings (prevents squad-farming loops). |
| Volatile kill burst kills another target | No second burst (not recursive). |
| Two Shock users on one target | Separate Charge meters; Overload ICD (3 s) is per shooter per target. |
| Siphon healing at full HP | No overheal, no shield; wasted. Siphon gains nothing from structures or the Uplink. |
| Ammo effects on the Mana Uplink | Immune; base damage only. Sunder gives +0%. |
| Ammo effects on Barricades / Ward Generators | Damage modifiers apply (Sunder +20%, Piercing pen); no Burn/Chill/Charge. |
| Cryo slow stacking with skill slows | Total move-speed reduction from all sources capped at 40% **[heroes.md must honour]**. |
| Hex beam and headshot mods | Prism Eye converts to ramp-time reduction; beam never crits. |
| Ironmaw pellets and ammo meters | Each pellet is a hit; meters accumulate by damage, so 10 pellets = one 110-damage hit. |
| Player leaves Armory with an un-undone purchase then returns | New visit; sell value is 60%. |
| Lumen insufficient for an upgrade | Purchase button disabled; no debt, no partial purchase. |
| Sudden Death (C10) | Everyone respawns full pool / full magazine + full reserve; mounts kept; shop disabled. |
| Bot takes over a disconnected slot | Inherits mounts, Chamber and Lumen; bot buy logic follows the build examples' order for its hero. |
| Mechanical hero Dry far from refills | Cannot fire; must use skills, return to a held Supply Cache, Armory, or collect Ammo Sparks. Intended counterplay, not a bug. |
| Tracer on Sable while stealthed **[heroes.md]** | Outline shows; reveals for 1.5 s. Sable's kit must state whether her stealth breaks on damage (Balance risk R5). |

---

## 6. Dependencies

| System / Doc | Direction | Contract |
| ---- | ---- | ---- |
| `game-concept.md` Canon C5, C6, C7, C10, C14, C16, C17 | This doc obeys | Supply Cache refill, Armory-only shopping, Uplink immune to effects, Sudden Death gear rules, Lumen sink, Crystals/Chips split. |
| `heroes.md` | Both | heroes.md supplies HP, armor, HP-per-level, archetype & range band, cleanse/stealth/slow rules; it must reference this doc's weapon table, TTK bands and the 40% slow cap. |
| `wardlings-and-economy.md` | Both | It supplies the Lumen income curve and Ammo Spark drop rate; it must reference this doc's gun spend (5,250–6,200 per full build) when sizing squad-upgrade prices, and Sunder/Shock/Volatile as Wardling counters. |
| Art bible | Both | It owns family hues (must avoid team blue/red), tier silhouettes and mount meshes; it must implement the 4 attach markers and the tier channels in §3.6.2–3.6.3. |
| Hardpoints / match flow (future GDD) | This → | Barricade and Ward Generator interaction with Sunder/Piercing. |
| HUD / UX (future) | This → | Pool / magazine / reserve display, Burnout state, status icons (Burn, Charge, Chill, Brittle, Scorched, Disrupted), scoreboard mount icons, death card. |
| Audio (future) | This → | Per-tier shot layers, ammo impact sounds, Burnout crackle and reload tells audible at 15 m. |
| Netcode | This → | Hitscan uses server-side lag compensation; meters and Burn pools are server-authoritative; mounts replicate as small IDs (line + tier per socket). |
| Bot AI | This → | Bot buy order per hero; bot aim handicap, not stat change. |

---

## 7. Tuning Knobs

| Knob | Default | Safe range | Affects |
| ---- | ---- | ---- | ---- |
| Weapon `damage` per weapon | §3.3 | ±20% | TTK; must stay in §3.4 bands |
| `k_lvl` | 0.025 | 0.015–0.035 | How much level gaps matter |
| `M_dmg` cap | +0.25 | 0.15–0.35 | Ceiling of damage stacking |
| Total armor pen cap | 60% | 40–75% | Tank viability |
| Full-build TTK reduction | 15–25% | 10–30% | How much Lumen leads snowball |
| Body TTK floor (Medium) | 0.70 s | 0.6–0.9 s | Lethality ceiling |
| Burnout delay multiplier | 1.5 | 1.25–2.0 | Mana overcommit punishment |
| Supply Cache refill rate | 25%/s | 10–50%/s | Mechanical sustain near held nodes |
| Tier power share | 40 / 70 / 100% | ±10 pts each | Value of early vs late buys |
| Sell rate | 60% | 50–75% | Cost of experimenting / adapting |
| Ammo potency (Burn 12%, Shock 0.6, Siphon 8%, Cryo 0.5, Sunder 35%, Pierce 40%) | §3.7.1 | ±30% each | Ammo strength |
| Shock Overload ICD | 3 s | 2–5 s | Teamfight chain spam |
| Cryo slow max | 25% | 15–30% | Kiting frustration |
| Uplink ammo immunity | on | on/off | Siege length (keep on; Canon C7) |
| Price per tier | §3.8 | Inside band only | Build pacing |

---

## 8. Acceptance Criteria

1. In a test range, each weapon's unmodded body TTK vs a 300 HP / 10 armor dummy at optimal range is within its §3.4 band (±0.05 s, automated test).
2. With any combination of mounts, ammo and Ammo Mod, the Medium body TTK is never below 0.70 s (automated sweep over all valid builds).
3. Every catalog entry's price sits inside its band; Tier I/II/III map to Minor/Standard/Major; Ammo Types are Standard, Ammo Mods Minor (data validation test).
4. Buying any Crystal/Chip tier changes the first-person and third-person weapon model within 1 frame of purchase; QA can identify each socket's tier from 20 m in third person by size/glow alone (screenshot review, greyscale pass).
5. Crystals cannot be bought for a Mechanical gun and vice versa; restricted lines are greyed for other weapons.
6. Purchases are impossible outside the own HQ Armory zone, at Forward Beacons, and during Sudden Death.
7. Selling within the same Armory visit refunds 100%; after leaving and re-entering, 60% rounded down to 5.
8. Upgrading Overclock I → III charges 400 + 500 + 900 = 1,800 total.
9. Emptying a Mana pool triggers Burnout (regen delay ×1.5) and the crystals visibly go dark; the crackle is audible at 15 m and not at 20 m.
10. Standing in a held Supply Cache refills a Mechanical reserve from 0 to full in 4 s ±0.1 s; Mana heroes gain nothing.
11. The Mana Uplink takes base damage only from any ammo type (no Burn, no Sunder bonus).
12. Shock Overload cannot proc on the same target from the same shooter more than once per 3 s.
13. Cryo never reduces a target's move speed by more than 25% from Cryo alone.
14. At match end all mounts, ammo types and Lumen are cleared; the next match starts every weapon unmodded.
15. Median telemetry from 20+ bot matches: full gun build completes at 24–32 min; no player completes a full gun + max squad before 30:00.

---

## Balance Risks

| # | Risk | Mitigation |
| ---- | ---- | ---- |
| R1 | **Damage Core dominance**: Ember Heart / Overclock is the default pick and builds homogenise. | Core alternatives offer non-linear value (Feedback/Wellspring sustain, Prism for headshot heroes); telemetry on Core pick rate; target no line > 50% pick rate per hero. |
| R2 | **Lumen snowball**: the leading team is better armed and wins more fights. | TTK reduction capped at 25%; tier power front-loaded (Tier I = 40% for Minor price) so trailing players get efficient early tiers; catch-up EXP (C13). |
| R3 | **Siphon + Liora/Brannoc sustain** makes fights unwinnable. | Siphon 8% hero-only; Incendiary's Scorched as a hard counter; no overheal. |
| R4 | **Shock chains in squad fights** (60 constructs = many arc targets). | 2 arc targets, 30 damage, 3 s ICD; Sunder/Shock tuned against squad clustering. |
| R5 | **Tracer hard-counters Sable**. | 1.5 s only; heroes.md decides stealth interaction; watch Sable win rate vs Tracer users. |
| R6 | **Sunder trivialises Wardlings and Breach tasks**. | −10% vs heroes; 0% vs Uplink; Ward Generator HP tuned with Sunder in mind. |
| R7 | **Mechanical starvation** when a team holds no Supply Caches. | Ammo Sparks from Wardlings, Feedback Loop, Extended Mag; reserve 5 magazines. Monitor "time spent Dry". |
| R8 | **Cryo kiting frustration** in an FPS. | 25% cap, no root/stun, global 40% slow cap. |
| R9 | **Readability overload**: 10 players × 4 mounts + 60 Wardlings. | Tier read via silhouette size; ammo impact VFX dominant only on the victim's screen; mount idle VFX culled beyond 30 m. |
| R10 | **Hex beam + Incendiary** ramps too hard in CQ. | Beam capped at 15 m; Burn DPS cap 35. |

---

## Canon Concerns

Canon was followed in full. Concerns raised for the creative-director:

| # | Canon / concept item | Concern | What this doc did |
| ---- | ---- | ---- | ---- |
| CC1 | Scope Tiers (concept, not a C-row): Crystals/Chips and ammo types are listed under **Alpha**, but the **Vertical Slice** includes a Lumen shop and must validate match length. | A shop with only squad upgrades and Med-Packs cannot test spend pacing or Pillar 4 ("Power You Can See", a USP). | Proposed a minimal mount pipeline in the slice (§3.10): 4 lines, 2 ammo types, greybox meshes. Full catalog stays at Alpha. Needs CD sign-off. |
| CC2 | C16: Mechanical heroes refill from enemy Wardling drops; Mana heroes get no node or drop benefit. | Held Supply Caches (C5) are worth nothing to 4 of 7 heroes, which weakens the "every node matters" rule for Mana-heavy teams. | Followed. Suggest a future change: Supply Caches also cut Mana `regen_delay` by 50% for 10 s. Not implemented here. |
