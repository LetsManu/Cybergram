# Heroes

*Created: 2026-10-02*
*Status: Draft. Authored autonomously by game-designer + systems-designer (modes.automation: autonomous, rigor: minimal).*
*Binding source: `design/gdd/game-concept.md` → **## Canon** (C1–C18). Owner intent: `/ideas` → "Legend/Heros".*
*Sibling docs (written in parallel): `weapons-and-mods.md` (guns, ammo types, Crystals/Chips), `wardlings-and-economy.md` (Wardling stats, Lumen, Med-Packs), `match-flow-and-map.md` (hardpoints, tasks, Barricades, Garrisons, structure HP).*

---

## 1. Overview

Cybergram has **7 heroes** (Canon C17), each with one weapon (the primary damage source), one optional passive, **3 basic skills and 1 ultimate**, all on **cooldowns** (C16). Each basic skill has a 4-node tree **Unlock → Boost → Fork (A or B) → Mastery** and the ultimate has 3 ranks at levels **6 / 10 / 14** (C12). This doc defines shared hero rules (stats, cooldowns, level scaling, status effects, the "gadget" definition used by the Hacker), every kit in full, the counter matrix, and the balance targets that other docs must hit. It follows Canon C15 as revised on 2026-10-02: every player commands a squad with 4 commands (Follow, Hold Here, Attack Target, Go Capture), squads are middle-ground strength, and ownerless **Vanguard waves** of 4 march every lane every 60 s. Only Vesper Loom can command waves; every other hero has an explicit wave interaction (§3.8, §4). It does **not** define guns beyond archetype and balance bands, the mod system, Wardling stat blocks, or hardpoint/Barricade HP; those belong to the sibling docs.

**Design goals**
| Goal | Pillar | Test |
| ---- | ---- | ---- |
| Every kit is gun-first: skills set up, protect or amplify shooting | P2 Shooter Hands | No hero's skills exceed 40% of its expected damage output in a teamfight |
| Every kit touches the front: Wardlings, Barricades or tasks | P1 Front, P3 Squad | Each hero has ≥2 explicit task/Wardling/Barricade interactions (§6) |
| Every node is visible | P4 Power You Can See | Each Fork has a distinct VFX tint on the skill; Mastery adds a glyph to the hero's level ring |
| Every effect has counterplay | Concept risk "Hacker/Infiltrator frustration" | Every skill lists counterplay; all hard CC ≤1.6 s |

---

## 2. Player Fantasy

| Hero | Fantasy in one sentence | Primary MDA aesthetic |
| ---- | ---- | ---- |
| Vesper Loom | "My army is bigger than yours, and with one gesture it becomes *better* than yours." | Fantasy, Expression |
| Sable | "They built a wall. I walked through it, and nobody saw me do it." | Challenge, Fantasy |
| Juniper Quill | "This hardpoint is a machine, and I built it to eat you." | Expression, Discovery |
| Ryker Vance | "Point, pull, win. I am the reason the front moves." | Sensation, Challenge |
| Brannoc | "Stand behind me. Nothing gets through." | Fellowship |
| Liora Vale | "Every fight we win, I kept someone alive to win it." | Fellowship |
| Hex | "Your traps, your walls, your little robots: mine now, or at least broken." | Discovery, Challenge |

---

## 3. Shared Hero Rules

### 3.1 Base stats by role (level 1)

| Hero | Role | Type (C16) | Base HP | Armor | Move speed | Difficulty (1–5) |
| ---- | ---- | ---- | ----: | ----: | ----: | :--: |
| Vesper Loom | Minionmancer / Commander | Mana | 250 | 0% | 6.0 m/s | 3 |
| Sable | Infiltrator | Mana | 225 | 0% | 6.6 m/s | 5 |
| Juniper Quill | Trapper | Mechanical | 250 | 0% | 6.0 m/s | 4 |
| Ryker Vance | Soldier (damage) | Mechanical | 250 | 0% | 6.2 m/s | 1 |
| Brannoc | Tank | Mechanical | 550 | 20% | 5.4 m/s | 2 |
| Liora Vale | Healer | Mana | 225 | 0% | 6.0 m/s | 3 |
| Hex | Hacker | Mana | 250 | 0% | 6.0 m/s | 4 |

- **Armor** is a flat percentage reduction of all incoming damage (weapon and skill). Brannoc's 550 HP at 20% = **687 effective HP**.
- Sprint = ×1.35 move speed, no firing while sprinting. Crouch = ×0.5. These are shared and owned by the movement system.
- All heroes have identical hitbox *rules* (head ×multiplier from `weapons-and-mods.md`). Brannoc's hitbox is 25% larger by volume (the cost of his HP).

### 3.2 Weapon balance bands (hero-specific numbers only)

The gun design, ammo types and Crystals/Chips belong to `weapons-and-mods.md`. This table is the **balance contract** heroes.md needs: unmodded, level 1, body shots, sustained fire excluding reload.

| Band | DPS | | Range band | Effective range (falloff starts) |
| ---- | ---- | ---- | ---- | ---- |
| Low | 90–120 | | Close | 0–12 m |
| Mid | 130–160 | | Mid | 12–30 m |
| High | 170–200 | | Long | 30–50 m |

| Hero | Weapon archetype | Resource | DPS band (target) | Range band | Hero-specific notes |
| ---- | ---- | ---- | ---- | ---- | ---- |
| Vesper | Mana pulse carbine | Mana pool | Low (115) | Mid | Low DPS is paid for by +2 Wardlings |
| Sable | Mana burst SMG | Mana pool (small) | High burst (190) for ≤3 s, then Low sustained | Close–Mid | Pool empties fast; built for 1 target, not a teamfight |
| Juniper | Mechanical lever-action marksman | Magazine + reserve | Mid (135) | Long | High headshot reward; trap kits do the close work |
| Ryker | Mechanical assault rifle | Magazine + reserve | High (180) | Mid–Long | Highest *sustained* DPS in roster |
| Brannoc | Mechanical heavy scattergun | Magazine (small) + reserve | High at ≤8 m (190), Low beyond 15 m | Close | Lethal only at Hold-zone distance |
| Liora | Mana lance (bolts + heal-beam alt-fire) | Mana pool shared by bolts **and** heal beam | Low (95) | Mid | Heal beam: 60 HP/s, 25 mana/s, 18 m |
| Hex | Mana glitch SMG | Mana pool | Mid (145) | Close–Mid | +50% vs gadgets (passive) |

### 3.3 Level scaling

Levels and EXP ("Resonance") are Canon C12/C13. Scaling per level:

```
MaxHP(L)     = BaseHP     × (1 + 0.04  × (L − 1))
WeaponDmg(L) = BaseWpnDmg × (1 + 0.025 × (L − 1))
SkillPower(L)= BaseSkill  × (1 + 0.02  × (L − 1))     # skill damage, heals, shields
```

| Symbol | Type | Range | Description |
| ---- | ---- | ---- | ---- |
| L | int | 1–15 | Hero level |
| BaseHP | int | 225–550 | §3.1 |
| BaseWpnDmg | float | per weapon | Damage per shot at L1, from `weapons-and-mods.md` |
| BaseSkill | float | per node | Damage/heal/shield number written in this doc |
| Output | float | ×1.00 → HP ×1.56, weapon ×1.35, skill ×1.28 at L15 | Clamped by L range |

**Worked example:** Ryker L15 vs Liora L15. Liora HP = 225 × 1.56 = 351. Ryker DPS = 180 × 1.35 = 243. TTK = 1.44 s (vs 1.25 s at L1). HP outgrows level-only damage on purpose: Crystals/Chips (Lumen) are expected to restore and slightly exceed L1 TTK, so **gear, not levels, decides late duels**, and a hero who falls behind in levels can still win fights with good aim (Pillar 2, anti-snowball).

Durations, cooldowns, ranges and radii **do not scale** with level; they only change through tree nodes.

### 3.4 Cooldown model

| Rule | Value |
| ---- | ---- |
| Resource for skills | Cooldowns only, for every hero (C16). Mana/ammo feed the weapon only. |
| When the cooldown starts | On cast for instant skills; **when the effect ends** for skills with a duration (stealth, stim, fields, walls). |
| Charges | Skills with charges recharge one charge at a time on the listed timer. |
| Skill lockout | 0.25 s shared lockout between any two skill casts (prevents frame-perfect combos). |
| External cooldown reduction (from mods, if `weapons-and-mods.md` adds any) | Capped at **25%** total. `EffectiveCD = NodeCD × (1 − min(0.25, CDR))`. Minimum effective CD 3 s (basic), 45 s (ultimate). |
| On death | Cooldowns keep ticking while dead. |
| On respawn at HQ Sanctum | **Basic** skill cooldowns reset (ultimate does not). Spawning at a Forward Beacon gives no reset. This adds one more reason to choose HQ (C6, C14). |
| Ultimate | Ready immediately when Rank 1 is learned; later ranks do not refresh it. |
| Cast interruption | Skills with a cast/channel time are cancelled by Stun or Silence. A cancelled skill goes on 50% of its cooldown. |

### 3.5 Skill tree structure (Canon C12)

| Node | Requires | Min level | Effect type |
| ---- | ---- | :--: | ---- |
| **Unlock** | — | 1 | Learns the skill at base numbers |
| **Boost** | Unlock | 3 | Pure numeric upgrade |
| **Fork A *or* Fork B** | Boost | 5 | Modifier that changes *how* the skill plays. Choice is permanent for the match. Forks modify the existing skill; they never add a new button (scope risk mitigation in the concept). |
| **Mastery** | Fork | **9** (Canon) | Capstone; behaviour works with either Fork |
| **Ultimate Rank 1 / 2 / 3** | previous rank | **6 / 10 / 14** (Canon) | Rank = stronger numbers + one rider at Rank 3 |

- 1 point at L1, +1 per level, 15 points total; 3×4 + 3 = 15 (Canon). Points can be banked and spent any time, anywhere, including while dead.
- The Boost (L3) and Fork (L5) gates are a heroes.md rule that keeps early power spikes readable; they still allow every node to be bought by L15. Proof: by L8 the player can own 3 Unlocks + 3 Boosts + Ult R1 + 1 Fork = 8; levels 9–15 give 7 points = 2 Forks + 3 Masteries + Ult R2 + R3.
- **Visibility (Pillar 4):** a learned Fork tints that skill's VFX (Fork A = cool tint, Fork B = warm tint, per faction palette); each Mastery adds a glyph to the hero's level ring visible to everyone. The scoreboard shows every hero's Fork choices.

### 3.6 Status effects (shared glossary)

| Status | Effect | Hard CC? | Max duration in roster |
| ---- | ---- | :--: | ---- |
| Slow | −X% move speed | No | 2 s |
| Root | Cannot move; can aim, shoot, use non-movement skills | Yes | 1.5 s |
| Stun | Cannot move, shoot or use skills | Yes | 1.6 s |
| Silence | Cannot use skills; can move and shoot | Yes | 2.5 s |
| Knockback / Pull | Forced movement | Yes | 0.8 s |
| Blind | Screen bloom (white-out, 70% opacity, centre clears first) | No | 1.3 s |
| Reveal | Outline through walls for the revealing team | No | 6 s |
| Scramble | Target's HUD loses minimap, enemy outlines and cooldown numbers (icons stay). Never hides crosshair, own HP, ammo count. | No | 6 s |
| Malfunction | Applies to **gadgets only** (§3.7) | — | 10 s |

**Diminishing returns:** a second hard CC of the *same type* within 4 s of the first lasts 50%; a third lasts 0 (immune). Brannoc's Fortify and Wardling-only effects ignore this table.

### 3.7 What counts as a "gadget" (Hacker rule)

Hex makes enemy **gadgets** malfunction. A gadget is any enemy entity that is **not a hero** and was created by a hero skill, by a Wardling purchase, or by a held hardpoint. Exactly five categories:

| Category | Members (current roster) | What "Malfunction" does | Base Malfunction (Hex Spike) | Post-hack immunity |
| ---- | ---- | ---- | ----: | ----: |
| **Trap** | Juniper: Snare Coil, Tripwire Lattice, Pressure Mine, Killbox fence. Sable: Sabotage Charge | Inert and fully visible; cannot trigger | 6 s | 4 s |
| **Turret** | Vesper: Overwatch Node (Rally Beacon Fork B). Any future turret. | Stops firing | 4 s | 4 s |
| **Deployable** | Brannoc: Aegis Wall. Vesper: Rally Beacon. Liora: Med-Pack Drone. Hex: Static Field (vs enemy Hex). Juniper: Killbox emitter | Effect switches off (wall becomes non-blocking and passable, beacon stops healing, drone stops healing). HP is not reduced. | 3 s | 4 s |
| **Wardling** | All player-squad Wardlings, **Vanguard wave** Wardlings and Garrison Sentinels (C5, C15) | Ignores its command (squads) or stops marching (waves); stops firing and drifts back toward its owner / own Foundry side (wardlings doc §12 `malfunction` channel); takes +20% damage; **contributes 0 to Hold presence** | 3 s | 4 s |
| **Barricade** | Lane Barricades of held hardpoints (C5) | Opens a 3 m **Breach Gate** that Hex's team and Wardlings can pass through | 4 s | 8 s |

**Not gadgets** (Hex cannot hack them): heroes, the Mana Uplink, Ward Generators, Mana Cells, Foundry, Armory, Sanctum, Supply Caches, Forward Beacons. Rationale: hacking task objects or HQ structures would let one hero bypass the task layer (Pillar 1).

Post-hack immunity starts when a Malfunction ends; during it, Hex's basic skills cannot re-hack that gadget (the ultimate ignores immunity). This guarantees every gadget works at least 4 s out of every ~10 s even under a dedicated Hex.

### 3.8 Damage to structures and Wardlings

| Source | vs Wardlings | vs Barricades / Ward Generators | vs Mana Uplink (when Exposed) |
| ---- | ---- | ---- | ---- |
| Hero weapon | 100% | 100% | 100% |
| Hero skill damage | 100% unless a node says otherwise | 50% unless a node says otherwise | 50% |
| Wardlings | — | per `wardlings-and-economy.md` | 50% (Canon C7) |

"Wardlings" always includes **Vanguard waves** and Garrison Sentinels unless a rule says "squad". **Trigger rule:** Juniper's Snare Coil and Tripwire, and Sable's Sabotage Charge, are triggered by **heroes only** (a wave marching every 60 s would otherwise wipe every set-up); mines, Killbox fences and all explosions still damage Wardlings.

Structure HP values belong to `match-flow-and-map.md`; where a skill names a structure effect as "% of max integrity" it is written relative so it survives their tuning.

### 3.9 Role matrix

| Role function | Primary | Secondary |
| ---- | ---- | ---- |
| Sustained damage | Ryker | Hex, Juniper |
| Burst / pick | Sable | Ryker (ult) |
| Frontline / Hold anchor | Brannoc | Vesper (squad body-block) |
| Healing / sustain | Liora | Vesper (Rally Beacon) |
| Area denial / defence | Juniper | Brannoc |
| Wardling force multiplier / wave control | Vesper (only hero who commands Vanguard waves) | Liora (beam heals Wardlings), Juniper (Alarm Net), Brannoc (shelters waves) |
| Wave clear (enemy Vanguard + squads) | Ryker (grenades ×1.5), Juniper (mines ×1.5) | Hex (Malfunction), Vesper (Turn/convert) |
| Anti-gadget / anti-defence | Hex | Ryker (Breacher), Sable (Demolition) |
| Barricade bypass | Sable (phase), Hex (Breach Gate) | Brannoc (Bulldozer), Ryker (Breacher) |
| Attack a hardpoint | Ryker, Brannoc, Hex, Sable | Vesper |
| Defend a hardpoint | Juniper, Brannoc, Liora | Vesper |

A "standard" team of 5 = 1 frontline + 1 sustain + 2 damage/pick + 1 utility (Vesper, Juniper or Hex). Bots draft by role in this order (feeds the bot AI doc).

---

## 4. Hero Kits

Key slots are abstract: **S1 / S2 / S3 / Ult** (input bindings belong to UX). All numbers are level 1 base; skill numbers scale with SkillPower (§3.3).

---

### 4.1 Vesper Loom — Minionmancer / Commander

| Role | Type / weapon | Difficulty | Fantasy |
| ---- | ---- | :--: | ---- |
| Commander, Wardling force multiplier | Mana · pulse carbine · Low DPS (115) · Mid range | 3 | A puppeteer whose strings are mana threads. Her squad is her second barrel, the lane's Vanguard waves march to her tune, and her ultimate rewrites whole armies. |

Vesper is the only hero who can command **Vanguard waves** and take control of **enemy** Wardlings (Canon C15: waves are "uncommandable (Minionmancer excepted)"). Her kit uses the shared hooks in `wardlings-and-economy.md` §12 (`squad_capacity_bonus`, `apply_squad_modifier`, `rewrite_to_elite`, `subvert`, `issue_command`).

**Passive — Conductor.**
1. **Bigger squad.** Squad cap **+2** (base 5, max 7 with squad upgrades; C15). Her own Wardlings have +15% HP.
2. **Wave command.** Any **allied Vanguard wave** whose members are within **25 m** of Vesper obeys her squad's current command: Follow, Hold Here, Attack Target or Go Capture (the same 4 commands as C15, from the same radial wheel and quick keys; no new inputs). A conducted wave keeps the command while she stays within 25 m and for **8 s** after she leaves, then resumes its own march-to-front AI. Only one wave per lane can be conducted at a time.
3. **Command aura.** Allied Wardlings of any kind (squads, waves, Sentinels) within 15 m of her deal +10% damage.
4. **Readability.** Conducted waves and her own squad carry violet thread VFX that link them to her, so everyone can see who the commander is.

*Squad maths (balance contract with C15):* a focused base squad of 3 ≈ 30% of a Soldier's DPS (≈54 DPS against Ryker's 180). Vesper's 7 + aura ≈ 7/3 × 54 × 1.10 ≈ **139 DPS** of squad fire, plus a conducted 4-Wardling wave (≈ 72 more). Her own gun is Low band to pay for this.

**S1 — Marionette Thread** (aimed projectile, 60 m/s). A mana thread. On hit it deals damage and works as an instant **Attack Target** on that target for her squad **and** any wave she is conducting.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 40 dmg, range 30 m. Squad + conducted wave focus the target for 4 s. CD 10 s. |
| Boost | 3 | 60 dmg; CD 8 s. |
| Fork A — Pounce | 5 | Her Wardlings *leap* to the target (arrive in 0.5 s) and deal +25% damage during the 4 s focus. |
| Fork B — Puppet String | 5 | Hitting an **enemy Wardling** (squad or Vanguard, not Sentinel) **subverts** it for 6 s: it joins her squad as an overflow unit (no capacity, no bounty). Hitting a hero slows it 30% for 2 s. |
| Mastery | 9 | The thread chains once to a second enemy within 8 m. Allied squads (other owners) within 15 m of Vesper also focus. |
*Counterplay:* dodge the visible thread; break line of sight; Juniper mines and Ryker grenades punish the clumped squad that arrives; kill a subverted Wardling (it pays no bounty, but it stops).

**S2 — Rally Beacon** (placed deployable, 20 m). A beacon (200 HP, 30 s). Allied Wardlings within 10 m heal 15 HP/s and take 20% less damage. Double-tap orders her squad *and* a conducted wave to **Hold Here** at the beacon. Placing it inside a hardpoint zone issues **Go Capture** to them instead.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 15 HP/s, 20% DR, radius 10 m, 200 HP, 30 s. CD 18 s. |
| Boost | 3 | 22 HP/s; beacon 300 HP. |
| Fork A — Bastion | 5 | Also heals allied **heroes** 10 HP/s in radius. |
| Fork B — Muster Point | 5 | Any allied Vanguard wave whose path passes within 30 m **diverts to the beacon** and is conducted by Vesper for as long as the beacon lives (even if she is far away). |
| Mastery | 9 | Two beacons can exist at once. |
*Counterplay:* shoot the beacon (marked through walls for 1 s when placed); Hex disables it (deployable); fight outside the radius.

**S3 — Threadstep** (aimed at an allied Wardling). Swap positions with one of her Wardlings, or with any Wardling of a wave she is conducting, within range.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | Range 30 m, instant swap (0.15 s VFX). CD 14 s. |
| Boost | 3 | Range 40 m; CD 11 s. |
| Fork A — Decoy | 5 | The swapped Wardling detonates 1.5 s later: 80 dmg in 4 m (placed damage; it does not die). |
| Fork B — Cloak of Strings | 5 | Vesper gains a 150 shield for 3 s after swapping. |
| Mastery | 9 | 2 charges. |
*Counterplay:* kill her nearby Wardlings and she has no escape; the swap leaves a 1 s thread trail pointing to where she went.

**Ult — Rewrite** (centred on Vesper, 0.8 s cast, loud ring telegraph, interruptible). Rewrites every Wardling within the radius:
- **Allied** Wardlings (her squad, allies' squads, allied Vanguard waves, allied Garrison Sentinels) become **Elite** (`rewrite_to_elite`: tier +1, gold outline, ×1.15 scale; numbers owned by `wardlings-and-economy.md`).
- **Enemy squad and Vanguard** Wardlings are **Turned** (`subvert` to Vesper): they fight for her team, count toward *her* team's Hold presence (inside the Wardling presence cap), and pay no bounty.
- **Enemy Garrison Sentinels** cannot be subverted (wardlings doc §12); instead they are **Stalled**: they stop firing and give 0 presence for the Turned duration.

| Rank | Lv | Radius | Elite duration | Turned / Stalled duration | Rider | CD |
| ---- | :--: | ---- | ---- | ---- | ---- | ---- |
| 1 | 6 | 18 m | 12 s | 6 s | — | 120 s |
| 2 | 10 | 20 m | 15 s | 8 s | Turned Wardlings are also Elite | 105 s |
| 3 | 14 | 22 m | 18 s | 10 s | **Enemy Vanguard Wardlings are converted permanently**: they become an allied Vanguard wave (Elite for 18 s) that marches on the enemy's front for the rest of its life. Enemy *squad* Wardlings still return to their owner. | 90 s |

Turned squad Wardlings are leashed to 20 m from where they were turned; when the effect ends they return to their owner (or Hold-at-current if the owner is dead). A converted Vanguard group counts as a live wave for Vesper's team in that lane, so it delays that lane's next allied wave (C15: max 1 live wave per lane per team).
*Counterplay:* interrupt the cast (stun/silence); spread your squad with **Hold Here** away from the fight; kill your own Vanguard wave before she reaches it at R3 (it pays no bounty to you, but denies her a wave); Hex's Zero Day Malfunctions Elite/Turned Wardlings; kill Vesper and her own squad dissolves after 10 s (C15).

| Strengths | Weaknesses |
| ---- | ---- |
| Largest army in the game: squad of 7 + a conducted wave | Lowest personal DPS; loses most 1v1 duels |
| Rewrite swings a contested Hold task outright; R3 steals waves | Squad is rebuilt only at the Foundry: Forward Beacon spawns hurt her most |
| Makes every ally's squad and wave better: rewards grouping | Clumped army is food for grenades, mines and Hex |

**Front interactions**
| Wardlings / waves | Barricades | Hold | Plant | Breach |
| ---- | ---- | ---- | ---- | ---- |
| Core of kit. Only hero who commands Vanguard waves and changes Wardling allegiance | Her army cannot pass enemy Barricades unless Sable/Hex/Brannoc open them; Turned Wardlings follow the Barricade rules of their *current* team | Best in roster (presence up to the cap + Rewrite swing + Go Capture on waves) | Thread + army escort the Mana Cell carrier; Muster Point holds the plant site | Army DPS on the Ward Generator; Rally Beacon sustains the hold-after-breach |

---

### 4.2 Sable — Infiltrator

| Role | Type / weapon | Difficulty | Fantasy |
| ---- | ---- | :--: | ---- |
| Infiltrator, picks, sabotage | Mana · burst SMG · High burst (190) / Low sustained · Close–Mid | 5 | A ninja who slips through the front, leaves charges behind it, and makes one enemy disappear. |

**Passive — Shadowgraph.** Sable's weapon deals +20% damage to targets facing away from her (angle between target's aim and Sable > 90°). Her footsteps are 50% quieter. She shows on enemy minimaps only when revealed.

**S1 — Veilwalk** (self). Stealth: invisible beyond 8 m, a heat-shimmer within 8 m, fully visible within 3 m. +15% move speed. Firing, using a skill, or taking damage ends it.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 6 s, shimmer radius 8 m. CD 16 s (starts when stealth ends). |
| Boost | 3 | 8 s; CD 13 s. |
| Fork A — Ambush | 5 | First 1.5 s after leaving stealth: weapon +40% damage (stacks additively with Shadowgraph). |
| Fork B — Ghost Lane | 5 | Enemy Wardlings and Sentinels do not detect her while stealthed and for 2 s after; shimmer radius 5 m. |
| Mastery | 9 | Taking damage no longer breaks stealth; each hit flashes her silhouette for 0.5 s instead. |
*Counterplay:* listen (stealth has a faint hum); shimmer at 8 m; Seeker Wardlings reveal within 12 m; Juniper tripwires and snares reveal; Hex's passive sees her charges; area damage breaks it.

**S2 — Phase Shift** (directional dash). An 8 m dash, intangible for 0.4 s, that passes through **enemy Barricades, Aegis Walls, Killbox fences and other deployables**. Never through level geometry.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 8 m, 0.4 s intangible. CD 14 s. |
| Boost | 3 | 10 m; CD 11 s. |
| Fork A — Echo | 5 | Re-press within 3 s to snap back to the start point (in or out of enemy lines). |
| Fork B — Slipstream | 5 | Leaves a rift for 2 s that **one** ally (hero or Wardling) can pass through the same way. |
| Mastery | 9 | 2 charges. |
*Counterplay:* a phase through a Barricade makes a loud crackle and a 2 s ping at the Barricade for its owners; guard the backline side of Barricades; Brannoc and Ryker burst her on arrival.

**S3 — Sabotage Charge** (placed trap, 3 m plant reach, 1.0 s plant). Sticky charge on any surface. Arms after 1.5 s; visible to enemies only within 6 m. Triggers on an enemy **hero** within 3 m or on re-press (remote; the remote blast hits Wardlings too). 120 dmg in 4 m. Vs Barricades and Ward Generators: deals **25% of max integrity** (overrides §3.8).
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 120 dmg, radius 4 m, max 2 placed. CD 12 s. |
| Boost | 3 | 150 dmg; max 3 placed. |
| Fork A — Demolition | 5 | Structure damage 25% → 40% of max integrity; also destroys any enemy deployable or trap in radius. |
| Fork B — Snare Charge | 5 | Heroes hit are rooted 1.2 s and revealed 4 s. |
| Mastery | 9 | Cascade: detonating one charge detonates all of hers within 20 m; enemies hit are revealed to her team for 4 s. |
*Counterplay:* charges glint within 6 m and are shootable (40 HP); Hex sees them through walls; check behind your Barricades.

**Ult — Eclipse Step** (aimed projectile). Throws a shadow dart (40 m, 80 m/s). On hitting an enemy hero: after 0.5 s Sable teleports behind them; the target is **Silenced** and her weapon deals bonus damage to them. On hitting terrain: she teleports there (mobility use). The target hears a whisper sting at the moment of hit (0.5 s to react).
| Rank | Lv | Silence | Weapon bonus vs target | Window | CD |
| ---- | :--: | ---- | ---- | ---- | ---- |
| 1 | 6 | 2.0 s | +40% | 2 s | 100 s |
| 2 | 10 | 2.25 s | +50% | 2.5 s | 90 s |
| 3 | 14 | 2.5 s | +50% | 3 s | 80 s |
Rank 3 rider: a kill within the window instantly re-enters Veilwalk (free cast) and refunds 30% of the ult cooldown.
*Counterplay:* react to the sting (turn, jump, dash); stay near Wardlings, which auto-return fire; a Silenced target can still shoot; Liora's Cleanse Fork removes Silence.

| Strengths | Weaknesses |
| ---- | ---- |
| Only hero who ignores the Barricade layer alone | Lowest HP; dies to any focused response |
| Deletes isolated healers, Hexes and Junipers | Weak in open teamfights and against grouped squads |
| Sabotage Charges let her contribute to Breach tasks from behind | Highest skill floor; poor at Hold tasks |

**Front interactions**
| Wardlings | Barricades | Hold | Plant | Breach |
| ---- | ---- | ---- | ---- | ---- |
| Enemy Wardlings, waves and Seeker variants detect her (unless Ghost Lane; Seekers still reveal her at 12 m). Enemy Vanguard waves do not trigger her charges; she remote-detonates them on a passing wave for Lumen. Her own squad waits at the Barricade she phased through (wardlings doc §7) | Phase Shift passes them; Demolition charges damage them | Counts toward presence while stealthed, but every 3 s she is pinged to enemies inside the zone | **Cannot** Veilwalk or Phase through Barricades while carrying a Mana Cell (prevents uncontestable plants) | Charges on Ward Generators (25%/40% of integrity) |

---

### 4.3 Juniper Quill — Trapper

| Role | Type / weapon | Difficulty | Fantasy |
| ---- | ---- | :--: | ---- |
| Area denial, hardpoint lock-down | Mechanical · lever-action marksman · Mid (135) · Long | 4 | A tinkerer who turns a chokepoint into a Rube Goldberg machine. |

**Passive — Linkwork.** Juniper's traps within 6 m of each other link with a visible wire. When one triggers, every linked trap triggers 0.3 s later (chains). **Trap budget:** max **6** trap entities in total across all her skills (oldest removed). Her traps persist 30 s after her death, then decay. All her traps: 60 HP, shootable, glint to enemies within 8 m (mines within 4 m). **Snares and Tripwires are triggered by enemy heroes only**; Pressure Mines are triggered by heroes *and* Wardlings (incl. Vanguard waves), so she chooses where to spend mines on wave clear.

**S1 — Snare Coil** (thrown, arc, 20 m). Arms after 1.0 s. An enemy within 2 m is rooted and damaged.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | Root 1.25 s, 30 dmg. 2 charges, recharge 10 s. |
| Boost | 3 | Root 1.5 s; 3 charges. |
| Fork A — Barbed | 5 | Also 40 dmg bleed over 3 s and −30% healing received for 3 s. |
| Fork B — Spring | 5 | Replaces root with a 6 m knockback away from the coil (pushes enemies off a Hold zone). |
| Mastery | 9 | Snared enemies are revealed to her team for 5 s and her team's Wardlings prioritise them. |
*Counterplay:* shoot coils before stepping in; Hex disables; Liora's Cleanse.

**S2 — Tripwire Lattice** (two-point placement). First press places anchor A, second press places anchor B within 10 m: a laser wire. Crossing it triggers damage, slow and reveal. Lasts 90 s or until triggered.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 70 dmg, 40% slow 2 s, reveal 3 s; length 10 m. CD 12 s. |
| Boost | 3 | 90 dmg; length 14 m. |
| Fork A — Razor | 5 | Wire survives 3 triggers. |
| Fork B — Alarm Net | 5 | Trigger reveals the enemy to the whole team for 6 s and pings Juniper; her Wardlings deal +30% damage to marked enemies. |
| Mastery | 9 | Two wires can exist (each counts toward the trap budget as 1). |
*Counterplay:* the wire is visible at 8 m; shoot an anchor; Sable phases through it; Hex disables it.

**S3 — Pressure Mine** (placed, buried). Arms after 2.0 s; invisible beyond 4 m. Explodes on an enemy within 2 m: damage in 5 m with falloff to 40% at the edge. ×1.5 vs Wardlings.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 140 dmg, radius 5 m, max 2 mines. CD 15 s. |
| Boost | 3 | 170 dmg; arm time 1.2 s. |
| Fork A — Cluster | 5 | Splits into 3 bomblets (60 dmg each, 3 m) scattered 4 m apart: area denial. |
| Fork B — Gravity Mine | 5 | Pulls enemies within 6 m toward its centre for 0.8 s, then explodes for 110. Combos with Snare Coil. |
| Mastery | 9 | Mines re-arm once after triggering (2 detonations each). |
*Counterplay:* move slowly to see the glint; Hex's passive reveals mines through walls; Brannoc's Fortify tanks them.

**Ult — Killbox** (thrown emitter, 25 m). Deploys a 12 m radius electrified fence dome. Enemies crossing the fence in either direction take damage and are stunned. Inside, all Juniper's traps re-arm instantly and deal +30% damage. The emitter is a deployable with 400 HP.
| Rank | Lv | Duration | Fence crossing | CD |
| ---- | :--: | ---- | ---- | ---- |
| 1 | 6 | 8 s | 80 dmg + 1.0 s stun | 120 s |
| 2 | 10 | 10 s | 100 dmg + 1.0 s stun | 110 s |
| 3 | 14 | 12 s | 120 dmg + 1.2 s stun | 100 s |
Rank 3 rider: enemies inside are revealed and slowed 20%.
*Counterplay:* destroy the emitter (marked); Hex disables the fence (Trap category); Sable phases through; wait it out from outside.

| Strengths | Weaknesses |
| ---- | ---- |
| Best hardpoint defender; Killbox wins defensive Holds | Weak on the attack; traps need set-up time |
| Long-range weapon pairs with traps that cover her flank | Hard-countered by Hex |
| Mines shred clumped Wardling squads | Low mobility, no escape skill |

**Front interactions**
| Wardlings | Barricades | Hold | Plant | Breach |
| ---- | ---- | ---- | ---- | ---- |
| Mines (×1.5) on a wave's march path farm enemy Vanguard waves every 60 s; snares/wires ignore Wardlings so waves can't burn her set-up; Alarm Net buffs her own squad | She cannot pass enemy Barricades; behind her own Barricade she layers traps to catch Sables | Best defensive Hold: Spring knocks attackers off the zone | Mines on the plant site; Killbox over a charging Mana Cell | Defending: traps around the Ward Generator |

---

### 4.4 Ryker Vance — Soldier

| Role | Type / weapon | Difficulty | Fantasy |
| ---- | ---- | :--: | ---- |
| Sustained damage dealer, no big defence | Mechanical · assault rifle · High (180) · Mid–Long | 1 | The professional. A rifle, grenades, and nothing to hide behind. |

**Passive — Battle Rhythm.** A kill or assist refills 50% of his current magazine and grants +15% move speed for 3 s.

**S1 — Frag Grenade** (thrown, bounces). 1.2 s fuse. Damage in 5 m, falloff to 40%. ×1.5 vs Wardlings.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 110 dmg. 2 charges, recharge 9 s. |
| Boost | 3 | 130 dmg; recharge 7.5 s. |
| Fork A — Cluster | 5 | Splits on detonation into 3 sub-munitions (40 dmg, 3 m each). |
| Fork B — Breacher | 5 | Detonates on impact; 100% (not 50%) skill damage vs Barricades, Ward Generators and enemy deployables. |
| Mastery | 9 | 3 charges. |
*Counterplay:* audible pin and a visible arc; spread out; Wardlings absorb it.

**S2 — Combat Stim** (self). +25% fire rate and +15% move speed. Costs 20 HP (cannot drop him below 1 HP).
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 5 s. CD 16 s. |
| Boost | 3 | 6 s; CD 14 s. |
| Fork A — Adrenal | 5 | No HP cost; heals 60 HP over the duration (his only real sustain). |
| Fork B — Overdrive | 5 | Instant full reload on cast, +20% reload speed; HP cost rises to 40. |
| Mastery | 9 | Each kill during Stim extends it 2 s (max +6 s). |
*Counterplay:* the glowing stim is visible; disengage for 6 s; CC him.

**S3 — Tactical Slide** (directional). A 7 m slide that reloads 30% of his magazine.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 7 m. CD 8 s. |
| Boost | 3 | CD 6.5 s. |
| Fork A — Momentum | 5 | Next 8 bullets after the slide deal +20% damage. |
| Fork B — Rebound | 5 | Can re-cast within 2 s for a second slide. |
| Mastery | 9 | 30% damage reduction while sliding (0.5 s). This is the most defence his kit ever gets. |
*Counterplay:* the slide is short and committal; hold angles; roots and snares stop it.

**Ult — Overdrive Protocol** (self). Bottomless magazine (no reload, no reserve drain), weapon damage up, recoil −50%.
| Rank | Lv | Duration | Weapon damage | CD |
| ---- | :--: | ---- | ---- | ---- |
| 1 | 6 | 8 s | +30% | 100 s |
| 2 | 10 | 10 s | +35% | 90 s |
| 3 | 14 | 12 s | +40% | 80 s |
Rank 3 rider: each kill during the ult extends it 2 s (max +6 s).
*Counterplay:* he glows and his rifle hums (team-wide audio); break line of sight; Brannoc's Aegis Wall; Silence does **not** end it, so stun or kill him.

| Strengths | Weaknesses |
| ---- | ---- |
| Highest sustained DPS; best Uplink damage when it's Exposed | No shield, no heal (unless Adrenal), no escape beyond a slide |
| Easiest kit: the onboarding hero | Countered by walls, traps and dive |
| Grenades clear Wardling squads and (Breacher) Barricades | Ammo-hungry; depends on Supply Caches and Armory |

**Front interactions**
| Wardlings | Barricades | Hold | Plant | Breach |
| ---- | ---- | ---- | ---- | ---- |
| Grenades ×1.5 vs Wardlings: best clearer of enemy Vanguard waves and squads, best Lumen farmer; uses his squad's **Attack Target** to finish wounded heroes (≈30% of his DPS on top) | Breacher Fork damages Barricades at full skill rate | Clears the zone; does not anchor it | Escorts or carries the Cell; dies fast if focused | Best Ward Generator DPS (rifle + Breacher) |

---

### 4.5 Brannoc — Tank

| Role | Type / weapon | Difficulty | Fantasy |
| ---- | ---- | :--: | ---- |
| Frontline, Hold anchor | Mechanical · heavy scattergun · High ≤8 m (190), Low beyond 15 m · Close | 2 | A walking fortress of riveted plate; the front moves when he steps forward. |

**Passive — Anchor.** While inside a hardpoint zone with an active task, Brannoc takes 15% less damage (stacks additively with armor: 35% total) and is immune to knockback and pull.

**S1 — Aegis Wall** (aimed placement, 20 m). A 6 m × 3 m shield wall. Blocks enemy projectiles and hitscan; allies shoot through it. 10 s.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 1,200 HP, 10 s. CD 18 s (starts when the wall ends). |
| Boost | 3 | 1,500 HP; 12 s. |
| Fork A — Rampart | 5 | Wall also blocks enemy *movement* (heroes and Wardlings): a temporary chokepoint. |
| Fork B — Mirror | 5 | Damage absorbed charges his next shot: +1% per 20 absorbed, max +50%. |
| Mastery | 9 | On expiry or destruction, restores 100 HP to allies (heroes and Wardlings) within 6 m. |
*Counterplay:* flank it; Sable phases through; Hex disables it (it becomes passable); Breacher grenades and Demolition charges.

**S2 — Ram Charge** (directional). Charges 12 m in 0.8 s. Enemies in his path are knocked aside; the first hero hit is carried and takes damage; if carried into a wall, they are stunned.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 60 dmg; +60 dmg and 1.0 s stun if pinned. CD 14 s. |
| Boost | 3 | 80 dmg (+80 pinned); CD 12 s. |
| Fork A — Bulldozer | 5 | Hitting an enemy Barricade deals 15% of its max integrity; Wardlings hit are stunned 1.5 s. |
| Fork B — Interceptor | 5 | Can target an ally: charges to them, granting both a 150 shield for 3 s. |
| Mastery | 9 | Pinning a hero refunds 50% of the cooldown. |
*Counterplay:* sidestep (0.2 s wind-up roar); stand away from walls; Juniper snares stop him.

**S3 — Fortify** (self). Damage reduction and CC immunity; he is slowed 25% for the duration.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 40% DR, CC immune, 3 s. CD 20 s. |
| Boost | 3 | 50% DR. |
| Fork A — Challenge | 5 | Enemy heroes within 8 m deal 30% less damage to anyone except Brannoc; enemy Wardlings (squads, waves, Sentinels) within 8 m must target him. |
| Fork B — Lifeblood | 5 | After it ends, heals 20% of the damage absorbed during it. |
| Mastery | 9 | Allies within 6 m gain 25% DR for the duration. |
*Counterplay:* it is short: wait 3 s, or turn to his backline; Liora-less Brannocs run out of HP eventually.

**Ult — Earthbreaker** (aimed leap, 25 m). Leaps to the target point and slams: damage and stun in 8 m, then leaves a **Bastion zone** where allies take 25% less damage.
| Rank | Lv | Damage | Stun | Bastion zone | CD |
| ---- | :--: | ---- | ---- | ---- | ---- |
| 1 | 6 | 120 | 1.2 s | 6 s | 110 s |
| 2 | 10 | 150 | 1.4 s | 7 s | 100 s |
| 3 | 14 | 180 | 1.6 s | 8 s | 90 s |
Rank 3 rider: an enemy Barricade inside the radius loses 25% of its max integrity.
*Counterplay:* the 0.6 s landing marker on the ground is visible to enemies; dash or slide out; Hex's ult cannot stop it (not a gadget), so spread.

| Strengths | Weaknesses |
| ---- | ---- |
| 687 effective HP; anchors any Hold | Low damage outside 12 m; kited by Juniper and Ryker |
| Aegis Wall erases enemy DPS windows (and the Uplink defence) | Wall is a gadget: Hex makes it useless for 3 s |
| Ult starts fights and opens Barricades | Largest hitbox; burst by focused teams |

**Front interactions**
| Wardlings | Barricades | Hold | Plant | Breach |
| ---- | ---- | ---- | ---- | ---- |
| Challenge pulls enemy Wardlings and Vanguard waves off allies; Aegis Wall shelters his squad and the allied wave as it marches into a Hold; Bulldozer stuns Wardlings 1.5 s | Bulldozer Ram and Rank 3 slam damage Barricades | Best anchor (Anchor passive) | Walls the Cell carrier; Interceptor shields them | Walls the team while it shoots the Ward Generator |

---

### 4.6 Liora Vale — Healer

| Role | Type / weapon | Difficulty | Fantasy |
| ---- | ---- | :--: | ---- |
| Healer, sustain | Mana · lance (bolts + heal beam) · Low (95) · Mid | 3 | A field medic who heals with the same mana she fights with, and a satchel of Med-Pack drones. |

**Heals with mana (weapon).** Her alt-fire is a soft-targeted **heal beam** (18 m, 60 HP/s to heroes, 30 HP/s to any allied Wardling, including Vanguard waves) that drains her weapon's mana pool at 25 mana/s. Bolts and beam share one pool, so every second spent healing is a second not shooting. This satisfies C16: skills stay on cooldowns; mana feeds only the weapon.

**Passive — Triage Kit (heals with Med-Packs).** Liora regenerates 1 free Med-Pack every 30 s (free ones hold max 2; together with Armory-bought Med-Packs, 100 Lumen, she obeys the shared carry cap of 3 in `wardlings-and-economy.md`). A Med-Pack heals 40% of max HP over 3 s (economy doc). She can **throw** any Med-Pack to an ally within 15 m (soft target); thrown Med-Packs heal **+50%** (60% of the recipient's max HP) and are **not** cancelled by the recipient firing.

**S1 — Med-Pack Drone** (thrown deployable, 25 m). A drone flies to the most injured ally within 8 m of where it lands (soft target allowed for heals) and heals them over 2 s.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 120 heal over 2 s. 2 charges, recharge 12 s. |
| Boost | 3 | 150 heal; recharge 10 s. |
| Fork A — Swarm | 5 | Splits into 2 drones (90 each) that pick different allies. |
| Fork B — Cleanse | 5 | Also removes Root, Slow, Silence and Scramble from the healed ally. |
| Mastery | 9 | After healing, the drone hovers 4 s pulsing 15 HP/s to allies and Wardlings within 5 m. |
*Counterplay:* shoot drones (50 HP); Hex disables them; Barbed snares cut healing 30%.

**S2 — Prism Ward** (soft target ally or self, 20 m). Shield on one ally.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | 150 shield, 4 s. CD 14 s. |
| Boost | 3 | 200 shield. |
| Fork A — Haste | 5 | Shielded ally gains +25% move speed for 3 s. |
| Fork B — Overcharge | 5 | Shielded ally's weapon deals +15% damage while the shield holds. |
| Mastery | 9 | 2 charges. |
*Counterplay:* burst through it; wait 4 s; Eclipse Step Silence on Liora prevents it.

**S3 — Flash Bloom** (thrown, 15 m). Bursts after 0.3 s: enemies within 10 m facing it are Blinded and knocked back 3 m. Her self-defence tool.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | Blind 1.0 s, knockback 3 m. CD 15 s. |
| Boost | 3 | Blind 1.3 s; CD 13 s. |
| Fork A — Sanctuary | 5 | Also heals allies within 10 m for 60. |
| Fork B — Bloom Jump | 5 | If thrown at her own feet, launches her 5 m upward and she glides for 2 s (escape). |
| Mastery | 9 | Blinded enemies' Wardlings lose their target and stop attacking for 2 s. |
*Counterplay:* look away from the bloom (audible 0.3 s chime); attack from behind.

**Ult — Aurora** (centred on Liora). A 12 m dome of light: allies inside heal per second, and for the first 2 s cannot drop below 1 HP.
| Rank | Lv | Heal | Duration | CD |
| ---- | :--: | ---- | ---- | ---- |
| 1 | 6 | 80 HP/s | 6 s | 130 s |
| 2 | 10 | 100 HP/s | 7 s | 115 s |
| 3 | 14 | 120 HP/s | 8 s | 100 s |
Wardlings inside heal at 50%. Rank 3 rider: allies inside also gain 20% damage reduction.
*Counterplay:* pull or knock enemies out of the dome (Spring, Ram); burst after the 2 s floor ends; Barbed −30% healing; stun Liora (the dome stays, but she can't follow).

| Strengths | Weaknesses |
| ---- | ---- |
| Only true healer; doubles team uptime on a Hold | Lowest duel strength; prime Sable target |
| Heals Wardlings: keeps squads alive between Foundry trips | Healing costs her own DPS (shared pool) |
| Cleanse fork counters Juniper, Sable and Hex | Ult can be out-burst by Ryker Overdrive + grenade |

**Front interactions**
| Wardlings | Barricades | Hold | Plant | Breach |
| ---- | ---- | ---- | ---- | ---- |
| Beam and drones heal squads and Vanguard waves at 50%: keeping the allied wave alive on a Hold is half her front value | None (needs Sable/Hex/Brannoc to get through) | Aurora wins the last 8 s of a contested Hold | Keeps the Cell carrier alive | Sustains the hold-after-breach |

---

### 4.7 Hex — Hacker

| Role | Type / weapon | Difficulty | Fantasy |
| ---- | ---- | :--: | ---- |
| Anti-gadget, disruption | Mana · glitch SMG · Mid (145) · Close–Mid | 4 | A hacker who turns the enemy's machines against their logic; their defences go dark when Hex walks in. |

"Gadget" is defined in §3.7: **traps, turrets, deployables, Wardlings, Barricades**. Never heroes, Uplink, Ward Generators, Mana Cells or HQ buildings.

**Passive — Signal Sight.** Hex sees enemy gadgets (including buried mines and Sabotage Charges) through walls within 25 m, and her weapon deals +50% damage to gadgets. A stealthed Sable within 12 m (not 8) shows her shimmer to Hex only.

**S1 — Breach Spike** (aimed projectile, 35 m). A hacking dart. On a gadget: Malfunction for the category duration in §3.7. On an enemy hero: 40 damage and **Scramble** for 3 s.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | §3.7 durations; hero 40 dmg + 3 s Scramble. CD 10 s. |
| Boost | 3 | Malfunction durations +25%; CD 8 s. |
| Fork A — Turncoat | 5 | Traps and turrets are **Hijacked** instead of disabled: they trigger/fire against their owner's team for the duration. (Wardlings and Barricades are never hijacked: Vesper owns allegiance-swapping.) |
| Fork B — Worm | 5 | The hack spreads to up to 2 more gadgets within 8 m at 50% duration. |
| Mastery | 9 | 2 charges. |
*Counterplay:* dodge the dart; post-hack immunity (4 s) means re-deployed gadgets work; kill Hex, the main source of hacks.

**S2 — Static Field** (placed, 20 m). A 6 m zone for 6 s. Enemy gadgets inside Malfunction continuously (plus 1 s on leaving); enemy heroes inside cannot *place* new deployables or traps.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | Radius 6 m, 6 s. CD 18 s. |
| Boost | 3 | Radius 8 m. |
| Fork A — Blackout | 5 | Enemy heroes inside are Scrambled. |
| Fork B — Firewall | 5 | Allied gadgets and Wardlings inside are immune to enemy hacks and take 20% less damage. |
| Mastery | 9 | The field attaches to Hex and moves with her. |
*Counterplay:* it is a deployable (Hex vs Hex can hack it); fight outside it; it is short.

**S3 — Relay Hop** (aimed at a gadget, 30 m, 0.5 s channel). Hex teleports to any **allied** gadget (her own Wardlings and allied Vanguard wave Wardlings count) or any **currently Malfunctioning** enemy gadget.
| Node | Lv | Effect |
| ---- | :--: | ---- |
| Unlock | 1 | Range 30 m, channel 0.5 s. CD 15 s. |
| Boost | 3 | Range 40 m; channel 0.3 s. |
| Fork A — Firmware Bomb | 5 | Leaves a decoy at the origin that explodes after 1.5 s: 70 dmg in 4 m (placed damage). |
| Fork B — Encrypted | 5 | Arrives with a 100 shield for 3 s. |
| Mastery | 9 | Hopping to a Malfunctioning enemy gadget extends its Malfunction 3 s. |
*Counterplay:* the channel shows a beam at the destination for its duration; camp the destination; stun cancels it.

**Ult — Zero Day** (aimed point, 40 m, 1.0 s telegraph glitch-dome). A pulse in a 20 m radius that **ignores post-hack immunity**: all enemy gadgets Malfunction, and enemy heroes are Scrambled and their *ready* basic skills are put on a short cooldown ("Lag").
| Rank | Lv | Gadget Malfunction | Hero Scramble | Lag on ready skills | CD |
| ---- | :--: | ---- | ---- | ---- | ---- |
| 1 | 6 | 6 s | 4 s | 3 s | 120 s |
| 2 | 10 | 8 s | 5 s | 4 s | 110 s |
| 3 | 14 | 10 s | 6 s | 5 s | 100 s |
Rank 3 rider: enemy Barricades in the radius open a Breach Gate for the full 10 s.
*Counterplay:* the dome telegraphs for 1.0 s; leave or pre-cast skills; gadget-light teams lose little; it never affects heroes' guns.

| Strengths | Weaknesses |
| ---- | ---- |
| Hard-counters Juniper and turtle defences | Value depends on enemy comp (weak vs Ryker/Sable/Liora-heavy teams) |
| Opens Barricades for the whole team (Breach Gate) | Mid HP, short range; dies to Sable |
| Zero Day breaks a defended Hold in one cast | High cognitive load (category rules, immunity timers) |

**Front interactions**
| Wardlings | Barricades | Hold | Plant | Breach |
| ---- | ---- | ---- | ---- | ---- |
| Malfunctioning Wardlings stop defending; a Spike + Worm (or Static Field) on an **enemy Vanguard wave** freezes its march and zeroes its Hold presence, which makes Hex the fastest way to break a wave-held zone. She never takes control of Wardlings (that is Vesper's) | Spike/Zero Day open Breach Gates for her team | Static Field + Zero Day strip enemy Wardling presence and traps | Clears traps from the plant site | Cannot hack the Ward Generator (not a gadget); strips its Garrison Sentinels and traps |

---

## 5. Formulas

### 5.1 Effective HP and time-to-kill

```
EHP      = MaxHP(L) / (1 − Armor − DR_active)
TTK_ideal= EHP / DPS_attacker(L, gear)
TTK_real = TTK_ideal / accuracy        # accuracy assumed 0.55 (bots 0.40, good players 0.65)
```
| Symbol | Type | Range | Description |
| ---- | ---- | ---- | ---- |
| Armor | float | 0–0.20 | §3.1 |
| DR_active | float | 0–0.50 | Fortify, Anchor, Bastion, etc. Sum of Armor + DR clamped to **0.70** |
| DPS_attacker | float | 90–270 | Band × WeaponDmg(L) × gear multiplier |
| accuracy | float | 0.3–0.8 | Body-shot hit ratio |
| TTK | float (s) | ~0.9–12 | Clamp prevents infinite EHP (max ×3.33) |

**Worked example:** Ryker (L1, 180 DPS) vs Brannoc in Fortify (Armor 0.20 + 0.50 DR = 0.70 clamp): EHP = 550 / 0.30 = 1,833; TTK_ideal = 10.2 s (for 3 s), which is why Fortify is short.

### 5.2 Time-to-kill targets (level-matched, unmodded)

| Matchup | TTK_ideal target | Current (L1) | TTK_real at 0.55 accuracy |
| ---- | ---- | ---- | ---- |
| High DPS vs 225–250 HP | 1.2–1.6 s | Ryker vs Hex: 1.39 s | 2.5 s |
| Mid DPS vs 225–250 HP | 1.6–2.0 s | Hex vs Vesper: 1.72 s | 3.1 s |
| Low DPS vs 225–250 HP | 2.0–2.6 s | Liora vs Sable: 2.37 s | 4.3 s |
| High DPS vs Brannoc | 3.5–4.5 s | Ryker vs Brannoc: 3.82 s | 6.9 s |
| Sable full combo (Eclipse +50%, Shadowgraph +20%, Ambush +40%) vs 250 HP | ≥0.8 s (floor) | 190 × 2.1 = 399 DPS → 0.63 s ⚠ | see §7.3 |
| Any hero vs Tier I Wardling (150 HP, `wardlings-and-economy.md` §4) | ≤1.2 s | Mid: 1.0 s | 1.9 s |
| Focused base squad of 3 (≈54 DPS, C15) vs healthy 250 HP hero | ≥4.5 s ("cannot beat a healthy hero alone") | 4.6 s | ~7 s |
| Vesper's 7 + aura (≈139 DPS) vs 250 HP hero | ≥1.8 s | 1.8 s | ~3 s |

Rule: no single hero may reach TTK_ideal < 0.8 s on a full-HP, level-matched 250 HP target without an ultimate; with ultimate, the floor is 0.6 s. Sable is capped by a damage-bonus rule in §7.3.

### 5.3 Damage-bonus stacking

```
WeaponMult = 1 + Σ(additive bonuses)      # Shadowgraph, Ambush, Eclipse, Overdrive, Momentum, Overcharge
           clamped to ≤ 1.80
```
All hero-skill weapon bonuses are **additive** with each other and clamped at +80%; mod multipliers from `weapons-and-mods.md` apply after this clamp.

### 5.4 Hack duration

```
Malfunction = CategoryBase × (1 + 0.25·Boost) × (Worm ? 0.5 : 1)   # basic skills only
```
| Category | Base | With Boost | Worm spread |
| ---- | ---- | ---- | ---- |
| Trap | 6 s | 7.5 s | 3.75 s |
| Turret | 4 s | 5 s | 2.5 s |
| Deployable | 3 s | 3.75 s | 1.9 s |
| Wardling | 3 s | 3.75 s | 1.9 s |
| Barricade gate | 4 s | 5 s | 2.5 s |
Ult durations are fixed per rank (§4.7). Post-hack immunity: 4 s (8 s Barricades).

---

## 6. Balance Notes

### 6.1 Counter matrix

Row hero's outlook against column hero. `++` hard counter, `+` favoured, `0` even, `−` unfavoured, `−−` hard countered.

| vs → | Vesper | Sable | Juniper | Ryker | Brannoc | Liora | Hex |
| ---- | :--: | :--: | :--: | :--: | :--: | :--: | :--: |
| **Vesper** | · | + | − | − | + | 0 | − |
| **Sable** | − | · | 0 | + | − | + | + |
| **Juniper** | + | 0 | · | + | 0 | 0 | −− |
| **Ryker** | + | − | − | · | − | + | 0 |
| **Brannoc** | − | + | 0 | + | · | 0 | − |
| **Liora** | 0 | − | 0 | − | 0 | · | 0 |
| **Hex** | + | − | ++ | 0 | + | 0 | · |

| Hero | Counters (why) | Countered by (why) |
| ---- | ---- | ---- |
| Vesper | Sable (squad returns fire, reveals), Brannoc (Wardling swarm DPS ignores his range) | Juniper (mines ×1.5), Ryker (grenades ×1.5), Hex (Malfunction + Zero Day) |
| Sable | Liora, Hex, Ryker (isolated squishies, no escape) | Vesper (bodyguard squad), Brannoc (survives burst, Ram punishes) |
| Juniper | Ryker (no defence vs traps), Vesper (clumped squads) | Hex (hard: everything she has is a gadget) |
| Ryker | Vesper, Liora (raw DPS outpaces heals and squads) | Brannoc (wall), Juniper (denial), Sable (dive) |
| Brannoc | Ryker, Sable | Hex (wall disabled), Vesper (swarm) |
| Liora | Nobody in a duel; she counters *attrition* and CC (Cleanse) | Sable, Ryker |
| Hex | Juniper, Brannoc, Vesper | Sable (dies to dive) |

Liora's net-negative row is intended: healers are judged by team impact, not duels. Hex's net-positive row is a **watch item**: Hex's power is conditional on enemy gadgets, and her row overstates her value against gadget-light comps (§6.3).

### 6.2 Power curve by phase

| Hero | Early (L1–5) | Mid (L6–10) | Late (L11–15) | Notes |
| ---- | ---- | ---- | ---- | ---- |
| Vesper | Medium | **High** | High | Rewrite at L6 is the roster's biggest mid-game swing; Surges (Tier II/III Wardlings) scale her up |
| Sable | Low | High | High | Needs Eclipse Step |
| Juniper | Medium | High | Medium | Strongest while the front is static |
| Ryker | **High** | Medium | High | Onboarding hero; ult scales with Chips |
| Brannoc | High | High | Medium | Late burst eats him |
| Liora | Medium | Medium | High | Aurora R3 dominates last-stand Holds |
| Hex | Low | Medium | High | Value grows as enemies buy Wardling variants and Juniper/Brannoc level up |

### 6.3 Riskiest kits (playtest first)

| Rank | Kit | Risk | Mitigation already in kit | Telemetry trigger |
| ---- | ---- | ---- | ---- | ---- |
| 1 | **Hex** | Frustration (gadgets "stop working"); value swings wildly with enemy comp | Post-hack immunity; never affects guns; Scramble keeps crosshair/HP/ammo; Wardlings never stolen | Win rate vs Juniper >65%, or "my gadgets didn't work" survey >30% |
| 2 | **Sable** | Stealth + teleport + Silence in FPS = invisible death | Shimmer 8 m, hum, whisper sting 0.5 s, Barricade crackle, +80% bonus clamp, Silence leaves guns active | Deaths to Sable with <0.6 s TTK >10% of her kills |
| 3 | **Vesper** | Readability (7 Wardlings + a conducted wave + Elites + Turned); netcode load; Rewrite R3 permanently converting a Vanguard wave can snowball a lane; her squad maths (≈139 DPS) rivals a High-band gun | 0.8 s interruptible cast, ring telegraph, 20 m leash, Turned only 6–10 s, one conducted wave per lane, Wardling presence cap (wardlings doc), Hex/Ryker/Juniper counters | Hold flips within 5 s of Rewrite >50%; converted waves capture a hardpoint in >25% of R3 casts; Vesper damage share from Wardlings >60% |
| 4 | **Juniper** | Trap clutter; defence stalls matches (Pillar 5) | Budget of 6, glint, traps shootable, Hex counter, Surges shorten tasks | Median match length +3 min when Juniper is present |
| 5 | Brannoc | Wall + Anchor makes Holds unbreakable without Hex | Wall is a gadget; Fortify short; DR clamp 0.70 | Defensive Hold success >70% with Brannoc in zone |

### 6.4 Interaction checks resolved in this doc

| Pair | Ruling |
| ---- | ---- |
| Vesper Rewrite vs Hex Malfunction on the same Wardling | Malfunction wins while active (Wardling is inert); Turned/Elite timers keep running underneath |
| Vesper conducting a wave vs Hex Malfunction on it | Malfunctioned members ignore her command until it ends, then rejoin the conducted wave |
| Two Vespers (mirror) contest one Vanguard wave | A wave obeys only its own team's Vesper; an enemy Vesper can only Turn it (Rewrite / Puppet String) |
| Juniper snare vs a Vanguard wave | Waves walk over snares and wires without triggering them; mines trigger |
| Hex vs Sable stealth | Hex cannot hack heroes; Signal Sight only widens shimmer visibility to 12 m for Hex |
| Sable Phase vs Rampart wall / Killbox fence | Phase passes both (they are deployables/traps) |
| Brannoc Fortify vs Juniper Snare | CC immune: snare deals damage, no root |
| Liora Cleanse vs Scramble/Silence | Removed |
| Juniper Turncoat-hijacked traps (Hex) | Trigger on Juniper's team; links (Linkwork) are severed while hijacked |
| Killbox stun vs Brannoc Anchor | Anchor stops knockback only; stun still applies unless Fortify is up |

---

## 7. Edge Cases

1. **Vesper dies during Rewrite.** Elites keep Elite status until their duration ends or the squad dissolves (10 s after death, C15), whichever is first. Turned Wardlings return to their owner immediately.
2. **Turned Wardling's owner dies.** The Turned Wardling dissolves on schedule (C15: 10 s), even if still Turned. Turned **Vanguard** Wardlings have no owner and simply return to their team when the effect ends (R1–R2) or stay converted (R3).
2a. **Vesper dies while conducting a wave.** The wave keeps her last command for the 8 s grace, then resumes its own march AI. A Muster Point wave stays until the beacon dies.
2b. **Rewrite R3 converts a wave while Vesper's team already has a live wave in that lane.** The converted group merges into the existing live wave (max 8 members; extras dissolve with no bounty). The next wave still waits for the C15 "≤1 alive" rule.
2c. **Puppet String on the last member of an enemy wave.** Allowed; while subverted it does not count as alive for the enemy's wave-spawn rule, so their next wave can spawn (counterplay: they get a fresh wave).
3. **Sable plants a Sabotage Charge on a Barricade, then the Barricade changes owner** (hardpoint flips). The charge is removed and 50% of the cooldown refunded.
4. **Sable is inside an enemy Barricade's footprint when Phase ends** (e.g. latency). She is pushed to the nearest valid side along her dash direction.
5. **Juniper exceeds the trap budget mid-Killbox.** Killbox re-arm does not create new traps; the oldest trap is removed only when she places a new one.
6. **Ryker's Stim at ≤20 HP.** HP drops to 1, never to 0.
7. **Brannoc's Rampart wall placed on an enemy Hold zone.** Allowed; enemies inside can still shoot through gaps and walk around it (max width 6 m; Hold zones are larger per map doc).
8. **Liora heal beam on a full-HP target.** No mana drained.
9. **Hex Relay Hop target is destroyed during the channel.** Hop cancels, 50% cooldown refund.
10. **Zero Day on a Barricade the enemy is behind.** Gate opens both ways for 10 s (R3); defenders can also come out.
11. **Sudden Death (C10).** All Wardlings, Vanguard waves and garrisons are removed: Vesper's Passive, Rally Beacon heals and Rewrite have nothing to affect except deployables. Accepted: Vesper is weakest in Sudden Death, her ultimate becomes a mobility-free dud. Rewrite in Sudden Death instead grants Vesper and allies within radius a 100 shield for 5 s (fallback).
12. **Respawn at HQ resets basic cooldowns** but not if the player spawned at a Forward Beacon and later walks into the Sanctum (reset only on spawn).
13. **Same-type CC chain** (Juniper Snare root → Sable Snare Charge root within 4 s): second root lasts 50%.

---

## 8. Dependencies

| Doc | This doc needs from it | This doc provides to it |
| ---- | ---- | ---- |
| `game-concept.md` (Canon) | C1, C4, C5, C7, C10–C17 | — |
| `weapons-and-mods.md` | Per-hero gun stats inside the bands of §3.2; head multiplier; any CDR mods (capped 25%) | Archetype, resource, DPS/range bands per hero; additive skill-bonus clamp (+80%) |
| `wardlings-and-economy.md` | Wardling HP/damage per tier (Picket 150 HP T1); the 4 commands and Vanguard wave AI (C15); hooks `squad_capacity_bonus`, `apply_squad_modifier`, `rewrite_to_elite`, `subvert`, `issue_command`; Med-Pack (40% over 3 s, carry 3); Seeker reveal; Wardling presence cap | Vesper +2 squad; **wave command** (Conductor), Muster Point diversion, Puppet String and Rewrite (Elite / Turned / Stalled / R3 permanent wave conversion); Malfunction durations for squads, waves and Sentinels; Liora's free and thrown Med-Packs; ×1.5 Wardling multiplier on grenades/mines; hero-only trigger rule for snares/wires/charges. **Consistency check:** C15 says a base squad of 3 ≈ 30% of a Soldier's DPS (≈54 vs Ryker's 180); the Picket's 12 DPS × 3 = 36 (20%) at 100% hit rate, so one of the two needs tuning |
| `match-flow-and-map.md` | Barricade and Ward Generator integrity; Hold presence formula; Mana Cell carry rules; Hold zone sizes | Breach Gate (Hex); Phase Shift (Sable); %-integrity effects (Sabotage, Bulldozer, Earthbreaker R3); skill damage ×0.5 vs structures; stealth-in-Hold ping; Mana Cell carrier restrictions (Sable) |
| Bot AI (future) | — | Role order for drafting (§3.9) |
| UX / HUD (future) | — | Status glossary (§3.6), Scramble spec, Fork tint and Mastery glyph visibility rules |

---

## 9. Tuning Knobs

| Knob | Default | Safe range | Category | Affects |
| ---- | ---- | ---- | ---- | ---- |
| HP per level | 4% | 3–5% | Curve | Late-game TTK |
| Weapon dmg per level | 2.5% | 1.5–3.5% | Curve | Late-game TTK vs gear weight |
| Skill power per level | 2% | 1–3% | Curve | Skill share of damage |
| Boost / Fork min level | 3 / 5 | 2–4 / 4–6 | Gate | Early spikes |
| External CDR cap | 25% | 15–35% | Gate | Skill spam |
| DR clamp | 0.70 | 0.60–0.75 | Feel | Tank invulnerability |
| Skill weapon-bonus clamp | +80% | +60–100% | Feel | Sable/Ryker burst |
| HQ respawn cooldown reset | on | on/off | Gate | HQ vs Beacon spawn choice |
| Post-hack immunity | 4 s / 8 s | 2–6 s / 6–12 s | Feel | Hex frustration |
| Juniper trap budget | 6 | 4–8 | Gate | Clutter, defence stall |
| Vesper squad bonus | +2 | +1–+2 | Gate | Net load, Hold power |
| Conductor wave radius / grace | 25 m / 8 s | 15–35 m / 4–12 s | Feel | How far Vesper must lead waves |
| Rewrite R3 permanent wave conversion | on | on / off (fallback: Turned 10 s) | Gate | Lane snowball |
| Rewrite Turned duration | 6/8/10 s | 4–10 s | Feel | Hold swing |
| Stealth shimmer radius | 8 m | 6–10 m | Feel | Sable fairness |
| Same-type CC DR window | 4 s | 3–6 s | Feel | CC chains |

All per-node numbers live in `assets/data/heroes/<hero>.tres` (one resource per hero), never in code.

---

## 10. Acceptance Criteria

1. With 15 points, a player can own all 3×4 basic nodes and 3 ult ranks; the UI refuses Boost before L3, Fork before L5, Mastery before L9, ult ranks before L6/10/14, and a second Fork on the same skill.
2. Every Fork choice is visible to all players (VFX tint + scoreboard); every Mastery adds a level-ring glyph.
3. In a bot test, level-matched unmodded TTK_ideal for every pair in §5.2 is within its target band ±10%, except Sable's combo which must be ≥0.8 s after the +80% clamp.
4. Hex's basic skills cannot re-hack a gadget during its post-hack immunity; Zero Day can.
5. Hex skills have no effect on heroes' guns, the Uplink, Ward Generators, Mana Cells or HQ buildings.
6. Sable cannot Veilwalk or Phase through a Barricade while carrying a Mana Cell.
7. No hard CC in the roster exceeds 1.6 s (Silence 2.5 s); a third same-type hard CC within 4 s has 0 duration.
8. Respawning at HQ Sanctum resets basic cooldowns; respawning at a Forward Beacon does not.
9. Playtest (Tier 1): ≥70% of testers can name what killed them when killed by Sable or Juniper (readability check).
10. An allied Vanguard wave within 25 m of Vesper executes her current squad command (Follow / Hold Here / Attack Target / Go Capture) within 0.5 s, and resumes its march AI 8 s after she leaves; no other hero can command a wave.
11. Rewrite R3 leaves enemy Vanguard Wardlings in its radius permanently on Vesper's team; enemy squad Wardlings return to their owners; enemy Sentinels are Stalled, never subverted.
12. A Vanguard wave walking across Juniper's Snare Coil or Tripwire does not trigger it; a Pressure Mine does trigger.

---

## 11. Vertical Slice Recommendation

Canon's Scope Tiers fix the prototype pair (**Ryker + Liora**) and add **Vesper Loom + Brannoc** at the Vertical Slice. **Recommendation: keep Vesper Loom and Brannoc as the 2 heroes added for the slice.**

| Hero | Why it belongs in the slice | What it proves |
| ---- | ---- | ---- |
| **Vesper Loom** | She *is* the Unique Hook ("every player carries their own minions") turned up to maximum: +2 squad, conducting Vanguard waves, Puppet String, Rewrite. If Vesper is fun and readable, Wardlings work; if she is noise, the concept's top design risk shows early. | Pillar 3; all 4 squad commands plus the Vanguard wave AI (she drives both); Wardling netcode at worst case (7 per Vesper + overflow); Hold presence cap; Surge tier scaling |
| **Brannoc** | The slice must test all 3 task types; Hold and Breach need a frontline anchor, and he is the simplest new kit (difficulty 2) using only shared systems (deployable wall, dash, self-buff). | Pillar 1 (Hold anchoring), deployables pipeline (reused later by Juniper/Hex), Mechanical ammo vs Supply Caches |

Together with Ryker (damage) and Liora (healer), the slice covers damage / sustain / frontline / commander, and both resource types twice (2 Mana, 2 Mechanical). Sable, Juniper and Hex all depend on systems that arrive in Alpha (Barricades, Garrisons, gadget categories), so building them earlier would mean designing against placeholder systems.

---

## Canon Concerns

| # | Canon item | Concern | What this doc did | Suggested fix |
| ---- | ---- | ---- | ---- | ---- |
| 1 | C1 (each hero unique within a team) + Scope Tier 1 (4 heroes, 5v5 with bots) | A 5-player team cannot be filled with 4 unique heroes. The Vertical Slice as written cannot run 5v5. | Followed Canon: recommended Vesper + Brannoc for the slice (§11). | Either add a 5th hero to the slice (Juniper is next-cheapest: her traps reuse the deployable pipeline), or allow duplicates within a team in Tier 1 only. |
| 2 | C15 (Minionmancer +2) + Top Risks netcode row (squads ≤50) | With 2 Vespers, squads reach 8 × 5 + 2 × 7 = **54**, above the ≤50 in the risk table; Vesper's subverted overflow units and a conducted wave add more. Total worst case ≈ 54 + 30 Sentinels + 24 Vanguard = **108** AI vs "~100". | Implemented +2 (base 5, max 7) as Canon. Subverted units are temporary overflow; Rewrite R3 merges converted waves into an existing wave (max 8) rather than adding a new one. | Re-baseline the netcode budget to ~110 AI, or cap Vesper at +1 when both teams pick her. |
| 3 | C16 (skills use cooldowns only) vs owner's "Healer heals with mana" | Read literally, Liora's healing cannot spend mana via a skill. | Routed mana healing through her **weapon alt-fire** (heal beam drains the weapon pool); skills stay on cooldowns. Fully Canon-compliant. | None needed; flagged so the weapons doc models a dual-mode weapon. |
| 4 | C4 (Wardlings = 0.5 Hold presence) | Vesper's 7 Wardlings + a conducted wave of 4 = 5.5 players of presence before Rewrite turns more. | Kept 0.5 untouched; relied on the wardlings doc's 3.0 per-team Wardling presence cap (an extension of C4 they flagged) plus short Turned timers and Hex's 0-presence Malfunction. | Promote the 3.0 Wardling presence cap into Canon C4 so every doc obeys it. |
| 5 | Pillar 3 design test ("more than two commands → cut") vs C15 (4 commands, owner decision 2026-10-02) | The concept now contradicts itself: C15 grants 4 commands, but Pillar 3's test still cuts any feature that needs more than two. | Followed C15: Vesper uses the same 4 commands and adds **no** new inputs (waves obey her current squad command). | Update Pillar 3's test to "more than the 4 standard commands or a top-down view". |
