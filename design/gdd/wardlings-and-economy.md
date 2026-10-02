# Wardlings & Economy

*Created: 2026-10-02 · Revised 2026-10-02 for the owner's C15 decision (4 commands, middle-ground strength, Vanguard waves)*
*Status: Draft. Authored autonomously by economy-designer and ai-programmer (modes.automation: autonomous).*
*Canon source: `design/gdd/game-concept.md` § Canon (C3–C7, C10–C16). This doc obeys Canon; any disagreement is listed under "Canon Concerns" at the end.*
*Sibling docs:*
- *`weapons-and-mods.md` owns weapons, Crystals, Chips, ammo, Ammo Sparks and gun prices. Reference used here: Ryker's AR-7 at 260 body DPS.*
- *`match-flow-and-map.md` owns presence and capture formulas, capture and defence Lumen, the 500 purse and the 40/min trickle.*
- *`heroes.md` owns hero HP and armor and Vesper's kit.*
- *Values this doc borrows from a sibling are marked **[sibling]**.*

---

## 1. Overview

This doc covers two systems.

**Wardlings** are mana-constructs, and they come in three populations:
1. **Personal squads.** Each is bound to one player, picked up free at the Foundry, and takes 4 commands.
2. **Vanguard waves.** These are ownerless. Every 60 s, 4 Wardlings march into each lane and work that lane's front.
3. **Garrison Sentinels.** These are static defenders of held hardpoints.

**Economy & Progression** covers **Resonance** (EXP, levels 1–15) and **Lumen** (the per-match currency): their sources, the formulas behind them, the Armory's non-weapon items, and the rules against snowballing and exploits.

The two systems are coupled. Enemy Wardlings, with Vanguard waves the steadiest of them, are the main source of both currencies (C13, C14). That makes every Wardling life-and-death rule an economy rule as well.

## 2. Player Fantasy

*"I'm a small commander with shooter hands."* Three constructs leave the Foundry at your heels. They step into a sniper's line of fire for you and shoot back at whoever hurts you. Point at a wounded enemy and press a key, and they finish them off. Point at a hardpoint and they go and work it while you flank. They are not strong enough to win a duel for you. But as you invest Lumen, a squad of five with Strikers and Overclocked emitters becomes a threat the enemy has to answer. Meanwhile small Vanguard waves keep every lane moving, so there is always a fight at the front worth joining.

---

# PART 1 — WARDLINGS

## 3. Squad Pickup at the Foundry

| Rule | Value |
| ---- | ---- |
| Where | The Foundry zone (6 m radius) next to your HQ Sanctum (C6). |
| When | Spawning at the Sanctum mints a full squad automatically. Walking into the Foundry at any time **tops up** empty slots (C15). |
| Mint time | 0.5 s per Wardling, staggered (0.1 s with *Quick Mint*). |
| Squad size | Base **3**. *Squad Expansion I/II* (Lumen) raises it to **4/5**. Vesper Loom gets **+2** (see Canon Concerns). |
| Slot contents | Each slot holds a **Picket** (free) or a **licensed variant** (§6). Licensed variants fill first, then Pickets. |
| Replacement | A lost Wardling is replaced only at the Foundry (C15). |
| Forward Beacon spawn | No squad. Any squad you had has already dissolved. |
| Recall to HQ | Dissolves the squad on departure (Core Loop step 5). You get a fresh mint at the Sanctum. |
| Cost | Pickets and re-mints are **free** (C15). Lumen buys licences and upgrades only. |

## 4. Tier Stats (all Wardlings)

Tier follows the Surges: **Tier I** at 0:00, **Tier II** at 15:00, **Tier III** at 30:00 (C15). At a Surge, every living Wardling and Sentinel morphs in place over **3 s while invulnerable** [sibling: match-flow], keeps its HP fraction and grows one tier pip on its back fin (Pillar 4).

**Picket (the baseline every variant multiplies):**

| Stat | Tier I | Tier II | Tier III | Notes |
| ---- | ---- | ---- | ---- | ---- |
| HP | 180 | 235 | 300 | 0 armor. Ryker (260 DPS) kills a Tier I Picket in about 0.7 s of hits. |
| Damage per bolt | 9 | 11 | 13 | Mana bolt, **projectile at 55 m/s**: dodgeable, no hitscan. |
| Fire interval | 0.30 s | 0.30 s | 0.30 s | Nominal 30 / 37 / 43 DPS. |
| Accuracy vs. a strafing hero at 15 m | 87% focused / 70% retaliation | same | same | Spread cone of 2.5° focused and 4° otherwise. |
| Effective DPS vs. a hero | **26** / 21 | 32 / 26 | 38 / 30 | Focused / retaliation. |
| Range | 22 m | 24 m | 26 m | |
| Move speed | 6.5 m/s [sibling] | 6.5 | 6.7 | Catch-up sprint 8.5 m/s. |
| Structure damage | ×0.5 vs. Uplink (C7), Barricades and Ward Generators [sibling] | | | |
| Hold presence | 0.5 (C4) | 0.5 | 0.5 | |

**Tier scaling (×1.2 / ×1.4 damage, ×1.3 / ×1.65 HP)** is chosen to track hero growth: hero levels plus a Tier I–II gun build (+15–25% damage per weapons-and-mods). The ratio of squad to Soldier stays near 30%.

## 5. Squad Strength: The Middle Ground (C15)

**Target.** A **focused base squad of 3 ≈ 30% of a Soldier's DPS**. It can finish a wounded hero but cannot beat a healthy one alone. Lumen pushes it toward a genuine threat.

```
SquadDPS_focus = Σ_i ( eDPS_T × V_dps(i) ) × (1 + U_dmg)
Ratio          = SquadDPS_focus / DPS_soldier_ref           DPS_soldier_ref = 260 (Ryker AR-7 body, unmodded) [sibling]
```
- eDPS_T is the focused effective DPS per Picket (26 / 32 / 38).
- V_dps is the variant multiplier (§6).
- U_dmg is the sum of squad damage upgrades: Overclock +0.20, capped at +0.40 including Vesper.

**Duel check: 3 Tier I Pickets vs. a healthy Ryker** (300 HP, 10 armor, so ×0.909 [sibling]; Ryker hits 80%):
- Ryker needs about 1.0 s per Picket, including retargeting.
- The damage he takes is 0.909 × (78·1.0 + 52·1.0 + 26·1.0) = **142**.
- Ryker survives with about 158 HP. **The squad wins only if the hero starts below ~140 HP**, which makes it a finisher, as Canon intends.

**Upgrade curve** (Tier I focused DPS as a percentage of 260):

| Squad build | Approx. Lumen | Squad DPS | % of Soldier | Read |
| ---- | ---- | ---- | ---- | ---- |
| 3 Pickets (base) | 0 | 78 | **30%** | Finisher, body-blocker |
| 3 Pickets + Overclock | 700 | 94 | 36% | |
| 4 Pickets + Overclock (Exp I) | 1,500 | 125 | 48% | Punishes a hero who ignores it |
| 5 Pickets + Overclock (Exp II) | 3,000 | 156 | 60% | Duels a hero at half HP |
| 5 incl. 2 Strikers + Overclock | 3,800 | 193 | **74%** | **Genuine threat.** Beats a healthy Light hero who fights it alone |
| Same + Reinforced Cores II | 4,550 | 193 | 74% | Also survives about 1.6× longer |

**Design cap:** 80% from items alone (enforced by the 2-Striker licence limit and the U_dmg cap). Vesper buffs can exceed this briefly; heroes.md owns that.

## 6. Variant Catalog

A **licence** (bought at the Armory and mirrored at the Foundry kiosk) turns one slot into that variant for the rest of the match, and the Foundry re-mints it for free. Limits: **2 per variant**, and **1 Mender**.

| Variant | Price (band) | HP × | DPS × | Range | Trait | Silhouette |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| **Picket** | free | 1.0 | 1.0 | 22 m | None. | Small biped, one crystal eye |
| **Shieldling** | 350 (Minor) | 1.6 | 0.4 | 15 m | **Aegis plate:** −40% damage taken from a 120° frontal arc. First choice as blocker (§9.3). | Big front shield, hunched |
| **Striker** | 400 (Minor) | 0.8 | 1.6 | 26 m | **Focus:** +15% damage while executing Attack Target. | Long barrel arm |
| **Seeker** | 300 (Minor) | 0.8 | 0.6 | 22 m | **Sense:** reveals stealthed heroes and armed traps within 12 m to its team, for 1.5 s, re-checked every 0.5 s. Counters Sable and Juniper. | Antenna crest, scan light |
| **Mender** | 700 (Standard) | 0.9 | 0.3 | 15 m | **Mend beam:** heals its owner 8 / 11 / 14 HP/s, or the most-damaged squadmate when the owner is at full HP. Soft-target within 10 m (allowed by Pillar 2). Heal is halved for 2 s after the owner takes hero damage. | Halo, green tether |
| **Sapper** | 650 (Standard) | 1.0 | 0.8 | 18 m | **Breacher:** ×3 vs. Barricades and Ward Generators, applied *before* the ×0.5 structure rule. No bonus vs. the Uplink. | Backpack charge, drill arm |

## 7. Squad Upgrades (Armory, last for the match)

| Upgrade | Price (band) | Effect | Visible tell |
| ---- | ---- | ---- | ---- |
| **Squad Expansion I** | 800 (Standard) | Squad size 4. | New slot lit on the HUD |
| **Squad Expansion II** | 1,500 (Major) | Squad size 5. Requires I. | Same |
| **Reinforced Cores I / II** | 350 (Minor) / 750 (Standard) | Wardling HP +20% / +40% total. | Plating rim → full plating |
| **Overclock Emitters** | 700 (Standard) | Wardling damage +20%. | Brighter muzzle glow |
| **Harmonic Tether** | 300 (Minor) | Move speed +12%. Follow leash 30 → 40 m. | Owner-colour trail |
| **Quick Mint** | 250 (Minor) | Mint 0.1 s per Wardling, and +25% damage resistance for 5 s after minting. | Gold mint VFX |
| **Bulwark Protocol** | 1,400 (Major) | In Hold or Go Capture: −30% damage taken and +25% body-block radius. | Ground shield under each Wardling |

Squad sink capacity is **6,050** in upgrades plus up to **~2,300** in licences.

## 8. Commands and UX (C15: 4 commands, radial wheel + quick keys)

| Command | Quick key (default, rebindable) | Radial slot | Targeting |
| ---- | ---- | ---- | ---- |
| **Follow** | `X` tap | Up | Always valid. Recalls the squad to its formation. |
| **Hold Here** | `Z` tap on ground | Down | Crosshair ground hit within 25 m, projected to the navmesh. If none, the owner's feet. |
| **Attack Target** | `Z` tap on an enemy | Left | Enemy hero, Wardling, Sentinel, trap, turret, drone, Barricade, Ward Generator, or an Exposed Uplink. Must be under the crosshair (3° snap cone), within **50 m**, and in the owner's line of sight. |
| **Go Capture** | `Z` tap on a hardpoint | Right | Crosshair over a hardpoint's zone, or over its world-space HUD diamond (3° cone), at any distance. |

- **`Z` is context-sensitive.** The priority order is: enemy under crosshair, then hardpoint diamond or zone, then ground. The crosshair shows a **command preview glyph** (sword, flag or pin) while `Z` is held, so the result is never ambiguous.
- **Radial wheel.** Hold `Z` for ≥ 0.25 s, flick the mouse toward a slot and release. The target is resolved from the crosshair at the moment the wheel opened. Time does not slow. Releasing in the centre dead zone cancels. The wheel exists for players who want an explicit choice. The quick keys cover 95% of uses.
- **Feedback.** Each order plays a 40 ms acknowledgement chirp, a world decal (a pin for Hold, a red reticle ring on the target for Attack, a flag pulse on the hardpoint for Go Capture) and a state badge on the squad strip.
- **Rejected orders** play an error chirp and a one-word reason ("Out of range", "Locked", "No path"). Examples: Go Capture on a hardpoint your team cannot attack (C3), or an Attack Target beyond 50 m.
- **Teammates** see your Hold pin and Go Capture flag dimly, within 40 m and on the minimap. Your Attack reticle is visible only to you.

**Owner visualization:**
- **Squad strip** (HUD, bottom-left, above health). One icon per slot: variant glyph, HP bar, tier pips and a state badge (`F` Follow, `H` Hold, `A` Attack, `C` Capture, `!` in combat, `↻` returning, `⚠` stranded). Empty slots show a grey Foundry glyph. During the death-hold, a 10 s ring.
- **In the world.** Your Wardlings get a 1 px personal-accent outline inside the team colour and a 0.6 m ground ring. They are visible through walls within 30 m as faint silhouettes, for you only.
- **Off-screen.** A screen-edge chevron points to any owned Wardling that is under fire or more than 20 m away. A **detached squad** (Hold, Go Capture) shows one grouped chevron with a count and its state badge, and a squad pip on the minimap.
- **Line-of-fire courtesy.** Allied bullets pass through allied Wardlings. Wardlings also steer out of a 1.2 m corridor along the owner's aim ray.

## 9. Behaviour Design (personal squads)

### 9.1 Architecture

- **Squad Brain** (one per owner, 5 Hz). It holds the command state, the formation frame, the threat list (shared perception), slot assignment and one path request to the squad's anchor.
- **Per-Wardling BT** (10 Hz, bucketed). It picks its combat target using **utility scoring** and reads the Brain's blackboard.
- **Steering and avoidance** run at 30 Hz.
- Perception is read only through condition nodes.

```
Root (Selector)
├─ [OwnerDead]   → DeathHold                                   (§9.8)
├─ [OutOfLeash]  → ReturnToAnchor (drop target, sprint, no fire)
├─ [Stranded]    → HoldAtCurrent                               (§9.6)
├─ [OwnerUnderFire && I am Blocker && Cmd ∈ {Follow, Attack}] → BodyBlock
├─ [Cmd == Attack]   → Sequence: ValidTarget? → MoveToFiringSpot(≤ range, LOS) → FocusFire
│                        └─ on invalid/timeout → revert to PrevCmd
├─ [Cmd == Capture]  → TaskWorker(hardpoint)                   (§9.5)
├─ [Cmd == Hold]     → Selector: [ThreatInHoldRadius] → UtilityCombat(Hold) | MoveTo(HoldSlot)
└─ [Cmd == Follow]   → Selector: [HasThreat] → UtilityCombat(Follow) | MoveTo(FormationSlot)
UtilityCombat: target = argmax Score(t); Score < 0.25 → none; strafe ±2 m; fire when LOS ∧ in cone
```

### 9.2 Follow Formation

- A loose wedge **3–6 m behind** the owner across a 140° rear arc, framed on the owner's velocity (or facing when standing).
- The blocker slot is 2.5 m forward-left. The Mender's slot is 3 m directly behind.
- Slots are recomputed at 5 Hz. Off-mesh slots snap within 2 m or collapse toward the owner.
- More than 10 m from its slot, a Wardling sprints at 8.5 m/s.

### 9.3 Body-Block

- **Trigger.** The owner has taken hero damage within 2 s.
- **Action.** The blocker moves onto the owner–attacker line, 2.0–3.0 m from the owner. The blocker is the Shieldling, otherwise the highest-HP Wardling. The second-best blocker covers a second attacker.
- **Constraint.** It never enters the owner's aim corridor: when the lines overlap within 15° it offsets 1 m. Wardlings collide with **enemy** units, so they block movement and soak bullets, but not with allies.
- **Release.** Two seconds after the last hit.

### 9.4 Retaliation and Target Scoring

```
Score(t) = 0.40·Threat + 0.20·Proximity + 0.15·Objective + 0.15·Command + 0.10·Stickiness
Threat     = clamp(dmg t dealt in last 3 s to [owner ×1.0, self ×0.7, squadmates ×0.5] / 60, 0, 1)
Proximity  = 1 − clamp(dist(t, anchor) / 25 m, 0, 1)        anchor = owner (Follow) or Hold/zone point
Objective  = 1 if t is inside the hardpoint zone the squad is working/holding
Command    = 1 if t is the Attack Target (forces top priority: a valid Attack target always wins)
Stickiness = 1 if t is the current target
Gate (Follow/Hold): an enemy HERO with Threat = 0 and Objective = 0 scores 0 → squads never start hero fights on their own;
                   the owner starts them with Attack Target.
Enemy Wardlings/Sentinels within 10 m are always valid.
```

Example. An enemy hero dealt 40 damage to the owner 1 s ago, 10 m away, outside any zone:
`0.40·0.667 + 0.20·0.6 = 0.39`, which is ≥ 0.25, so the squad retaliates (at retaliation accuracy).

### 9.5 Per-Command Behaviour

**Attack Target.**
- The whole squad focuses one target at **focused accuracy**. The blocker keeps body-blocking if the owner is under fire.
- Each Wardling moves to a firing spot within range and with LOS, but never further than the owner leash (30 m) from the owner. If the order was issued from Hold, the limit is **20 m** from the Hold point.
- The order **ends** when any of these happens: the target dies; the target is out of LOS for **4 s**; the target leaves leash range; **12 s** pass; or a new command is given. The squad then **reverts to its previous command**.
- Stealthed targets: Attack ends when stealth breaks LOS. A Seeker can keep it alive by revealing the target.

**Go Capture.**
- The squad **detaches**: the owner leash is suspended and it paths to the hardpoint by the lane route (flanks allowed when the detour ≤ 2.5×).
- On arrival it works the task, with a zone leash of **15 m**:
  - **Hold:** take ring slots inside the zone (0.5 presence each).
  - **Plant:** guard the socket and escort an allied Cell carrier within 15 m. Wardlings can **never carry** a Cell.
  - **Breach:** move inside the 12 m zone (the shield blocks fire from outside [sibling]), shoot the Generator, then hold.
  - **Own hardpoint:** act as defenders, the same as Hold Here at the zone centre.
- On **task completion** the squad converts to Hold Here at the zone centre.
- The order is **rejected** if the hardpoint is Locked for your team (C3).
- In Go Capture the gate in §9.4 is lifted inside the zone: the squad engages any enemy in the zone.

**Hold Here.**
- Ring slots around an 8 m radius, facing the enemy side of the lane.
- Engagement extends 12 m beyond the ring. There is no chase beyond 12 m from the point.

### 9.6 Leash and Stranding

| Mode | Leash | On break |
| ---- | ---- | ---- |
| Follow | 30 m from the owner (40 m with Tether) | Drop target, sprint back, hold fire until within 20 m |
| Attack (from Follow / Hold) | 30 m from the owner / 20 m from the Hold point | End the Attack and revert |
| Hold / Go Capture | 12 m from the Hold point / 15 m from the zone | Return to slot |
| Owner unreachable for 20 s (Follow only) | — | **Stranded.** The squad switches to Hold at its current position with a `⚠` badge. It resumes Follow when the owner comes within 30 m or presses Follow and a path exists. There are no teleports. |

### 9.7 Pathing Around Barricades

- Barricades are nav obstacles on a per-team layer: passable for the owner team, blocked for the enemy (C5). One path request goes out per squad, and Wardlings use local steering.
- If the owner crosses an enemy Barricade (Sable phase, a gap, a jump), the squad re-paths by flank if the detour is ≤ 2.5×. Otherwise it waits at the Barricade, and the stranding rule applies.
- Under **Attack Target** on a Barricade, the squad shoots it (×0.5, or ×1.5 for a Sapper).
- Nav layers update within 0.5 s of a Barricade breaking, rebuilding or being hacked by Hex.

### 9.8 Death of the Owner (C15)

1. When the owner dies, whatever the command, the squad enters **DeathHold**: Hold at its current centroid (or keeps its zone, if it was on Go Capture). It still retaliates and still counts for presence.
2. After **10 s** the squad dissolves (1 s fade). **Dissolved units pay no bounty and drop no Core.**
3. Units killed during DeathHold pay normally.
4. Respawning within those 10 s (respawn is 6 s at 0:00, C11) does not re-bind the squad. The fresh mint comes from the Foundry.

## 10. Vanguard Waves (C15)

| Rule | Value |
| ---- | ---- |
| Cadence | Each team, each lane, has its own **60 s** timer, starting at **1:00** (Veil drop [sibling]). |
| Size and makeup | **4 Pickets** at the current tier. From Surge II, 1 of the 4 is a **Shieldling** (a visible escalation). They have no upgrades. |
| Gate | A wave spawns only when the previous wave of that lane and team has **≤ 1 alive**. If the timer expires while the gate is closed, the wave waits and spawns the instant the gate opens. The timer restarts at the spawn. A **survivor merges** into the new wave, and only `4 − survivors` are minted, so a lane never holds more than 4 per team. |
| Cap | 3 lanes × 4 × 2 teams = **24** (C15 budget). |
| Spawn point | The Foundry's lane gate for that lane. |
| Target (re-evaluated every 2 s and on any hardpoint state change) | 1. the **nearest contested hardpoint** in the lane, counted from its own HQ. A hardpoint is contested when progress P > 0 for either team, or an enemy hero or Wardling is in its zone. 2. Otherwise, the **next enemy hardpoint it may attack** under C3. 3. Otherwise, its own **front-most** held hardpoint. |
| Behaviour | A **Wave Brain** (1 per wave, 2 Hz) drives a column march along the lane spline at 6.5 m/s. On arrival it runs the same `TaskWorker` as Go Capture (§9.5). Vanguard Wardlings never take flank tunnels. An enemy Barricade on the route is **attacked**, which makes waves natural siege fodder. They deviate at most 12 m off the spline. They engage enemy Wardlings within 15 m and any enemy that damages them. In their target zone they engage any enemy. Outside it, the hero gate of §9.4 applies (Threat only). |
| Commands | **None.** They are ownerless, and only Vesper can redirect them (§13). |
| Rewards | Bounty per §15 and §17. No owner, so there is no owner-death dissolve. They dissolve only at Sudden Death (C10). |

*Why the gate matters.* A lane where nobody fights gets one wave at a time that works the front slowly. A contested lane recycles its waves quickly, because they die quickly. The supply of mobs (and income) follows the fighting, not the clock (Pillar 1).

## 11. Garrison Sentinels (C5)

| Rule | Value |
| ---- | ---- |
| Count | **2 per held hardpoint**, for a maximum of **30**. At the start there are 24: the Mids are neutral and have none. |
| Spawn | **10 s** after a capture [sibling], then a **45 s** respawn per Sentinel while the hardpoint is held (C5). When the hardpoint flips, they dissolve over 2 s and pay no bounty. |
| Stats (I / II / III) | HP 450 / 590 / 740. Effective DPS vs. heroes 30 / 37 / 44. Range 26 m. They never leave the zone [sibling]. |
| Behaviour | A Hold BT anchored at the zone centre. `Objective` is weighted ×2 and the hero gate is removed: Sentinels shoot any eligible enemy in range. |
| Presence | 0.5 each (C4, [sibling]). |
| Bounty | 1.5 × the squad-Wardling bounty, with RepeatDecay (§17). |

## 12. Wardling Drops: the Wardling Core

When a Wardling is killed by the opposing team, it drops a **Core**: a pickup that lasts 10 s with a 1.2 m auto-collect radius.

- **Lumen Mote.** 75% of the Lumen bounty is paid **instantly** to the share list (§15.1). The remaining **25%** sits in the Core and is paid to **the whole share list** when any one of them touches it. This rewards stepping onto the ground just won, without a last-hit race.
- **Ammo Sparks** for Mechanical heroes only: **+1 magazine of reserve** each, capped at the maximum [sibling: weapons-and-mods]. The collector gets them.

| Killed unit | Sparks in Core | Spark drop rate |
| ---- | ---- | ---- |
| Squad Wardling | 1 | 100% |
| Vanguard Wardling | 1 | 50% |
| Sentinel | 2 | 100% |

- **Denial.** An enemy of the collector's team (that is, a hero from the Wardling's own side) touching the Core destroys it, Mote and Sparks included.
- **Unwitnessed kills.** If the share list is empty (the kill was made only by AI, with no allied hero within 25 m and no hero contribution), the instant 75% is **not paid**. The Core still drops. If an allied hero touches it within 10 s, that hero gets the 25% Mote. This ties income to presence at the front (Pillar 1).

## 13. Minionmancer (Vesper Loom) Hooks

heroes.md designs the kit. This system exposes the following hooks, all server-side and data-driven:

| Hook | Contract |
| ---- | ---- |
| `squad_capacity_bonus` | Vesper +2, added after the Expansions. |
| `apply_squad_modifier(owner\|wave, stat, mult, dur)` | Buckets: `hp`, `damage`, `move_speed`, `damage_taken`, `heal_out`. The same source refreshes; different sources multiply. Works on allies' squads and own-team Vanguard. Note the U_dmg cap in §5. |
| `rewrite_to_elite(w, dur)` | Tier +1. Tier III goes to "IV" = Tier III ×1.25 HP and damage. Adds a gold outline and ×1.15 scale. Valid on any allied Wardling, Vanguard or Sentinel. |
| `subvert(enemy_w, new_owner, dur)` | A temporary team and owner swap. The unit joins as an overflow unit (no slot, purple icon). It pays **no bounty** while subverted. When it reverts, it returns to its wave or squad, or to Hold-at-current if its original owner is dead or out of leash. **Sentinels cannot be subverted.** |
| `command_vanguard(wave, cmd, target, dur)` | The only way to command a Vanguard wave. Vesper may issue Hold Here, Attack Target or Go Capture to an own-team wave within the radius heroes.md sets, for `dur`. After that the Wave Brain resumes the §10 target rule. |
| `issue_command(owner, cmd, target)` | Skill-driven commands on a player squad. |
| Signals | `wardling_minted`, `wardling_died(w, killer, share_list)`, `squad_command_issued(owner, cmd, target)`, `squad_dissolved(owner, reason)`, `vanguard_wave_spawned(team, lane, n)`. |

Hex uses the same status channel with `malfunction`: the target ceases fire and wanders back toward its anchor. heroes.md sets the duration.

## 14. Performance and Network Budget

**Agent counts (worst case):**

| Population | Count |
| ---- | ---- |
| Squads | ≤ 50 (C15 budget), or 54 with two Vespers at maximum (see Canon Concerns) |
| Garrisons | ≤ 30 |
| Vanguard | ≤ 24 |
| **Total** | **≤ 104–108** |

Typical is about 60–75.

| Budget | Target |
| ---- | ---- |
| Server AI (all agents) | ≤ **2.0 ms** per frame average, ≤ 3.0 ms peak. BT at 10 Hz in 3 buckets. Squad Brains at 5 Hz. 6 Wave Brains at 2 Hz. |
| Path requests | ≤ 8 per tick, queued. One per squad or wave, not per agent. Re-path only on a nav-layer change, a command change, or an anchor jump of more than 5 m. |
| Perception | Shared per squad or wave via a spatial hash (8 m cells). LOS raycasts only for the current target, ≤ 1 per agent per 0.2 s. |
| Client render | Animation LOD: full rate within 30 m, 15 fps from 30–60 m, pose-baked impostor beyond 60 m. Wardlings ≤ **1.5 ms** GPU at 1080p on min-spec. |
| Snapshot size | About **11 B per agent**: position 3×16 bits, yaw 8, HP% 8, state/variant/tier 8, target id 8, owner id 8. |

**Relevance (interest management):**
- Your own squad is always relevant at 20 Hz, with exact HP.
- Other agents within 60 m, or in the view frustum up to 120 m, at 20 Hz.
- Agents from 60–120 m that are out of view, at 5 Hz.
- Beyond 120 m: not sent. They appear only as aggregated minimap pips at 1 Hz (one pip per wave or squad).
- Worst-case downstream is 108 × 11 B × 20 Hz ≈ **23.8 KB/s**. With relevance applied, about 8–12 KB/s per client.
- AI projectiles are simulated on the server. Hero shots *at* Wardlings use the same lag-compensated hit registration as shots at heroes.

---

# PART 2 — ECONOMY & PROGRESSION

## 15. Shared Rule: Share List and Share Factor

### 15.1 Share List

When an enemy unit dies, the **share list** is every hero on the killing team who is:
- within **25 m** of the death (C13), or
- dealt damage or healing that contributed to the kill within the last 5 s (for a hero victim) or 3 s (for a Wardling victim).

**There is no killing-blow privilege for mob bounties** (Anti-Pillar: no last-hitting).

```
S(n) = min(1, 1.2 / √n)      n = share-list size
n:     1     2     3     4     5
S:   1.00  0.85  0.69  0.60  0.54      team total = n·S(n): 1.0, 1.7, 2.1, 2.4, 2.7
```

## 16. Resonance (EXP): Levels 1–15 (C12)

```
inc(L) = 140 + 50·L            L = 1..5      (EXP needed from L to L+1)
inc(L) = 520 + 60·(L − 6)      L = 6..14
```

| Lv | To next | Cumulative | Avg-player minute | Unlock (C12) |
| ---- | ---- | ---- | ---- | ---- |
| 1 | 190 | 0 | 0:00 | 1 point |
| 2 | 240 | 190 | ~2 | |
| 3 | 290 | 430 | ~3 | |
| 4 | 340 | 720 | ~4 | |
| 5 | 390 | 1,060 | ~5 | |
| 6 | 520 | 1,450 | **~7** | Ult rank 1 |
| 7 | 580 | 1,970 | ~8.5 | |
| 8 | 640 | 2,550 | ~10.5 | |
| 9 | 700 | 3,190 | ~12.5 | Mastery |
| 10 | 760 | 3,890 | **~16** | Ult rank 2 |
| 11 | 820 | 4,650 | ~18 | |
| 12 | 880 | 5,470 | ~21 | |
| 13 | 940 | 6,350 | ~24 | |
| 14 | 1,000 | 7,290 | ~27 | Ult rank 3 |
| 15 | — | **8,290** | **~30** | Cap |

These meet C12: L6 in 6–8 minutes and L15 in 30–35 minutes for the average player. The strong profile caps at about 22 minutes. The weak profile is about L11–12 at 30:00 (§18). There is **no passive EXP** (C13 lists the sources).

### 16.1 EXP Sources

| Source | Formula (per recipient) | Range |
| ---- | ---- | ---- |
| Enemy **Vanguard** Wardling | `RV_T × S(n)`, RV_T = 20 / 30 / 40 | 11–40 |
| Enemy **squad** Wardling | `RS_T × S(n)`, RS_T = 45 / 60 / 75 | 24–75 |
| Enemy **Sentinel** | `1.5 × RS_T × S(n) × RepeatDecay` | 18–112 |
| Hero kill: the killer | `P = (200 + 20·Lv_victim) × C × D` | 220–720 |
| Hero kill: assisters and allies within 25 m | `0.5 × P` | 110–360 |
| Capture: every teammate | `100 × D` | 100–125 |
| Capture: participant bonus | `+250 × D` (in the zone within the last 10 s [sibling], or planted the Cell, or damaged the Generator) | 250–312 |
| Defence: each defender in the zone [sibling trigger] | `150` | 150 |
| Individual catch-up | All Resonance **×1.2** while `Lv ≤ team_avg_Lv − 2` | — |

**Catch-up (C13):**
```
C = min(1.6, 1 + 0.15 × max(0, Lv_victim − Lv_killer))
```

**Team deficit** (applies to kills and captures only, never to mobs):
```
gap = (Res_leader − Res_team) / Res_leader        (0 for the leader)
D   = 1 + min(0.25, 0.5 × gap)
```

Worked example. An L8 Ryker kills an L12 Brannoc. His team trails 18k to 24k Resonance, so gap = 0.25 and D = 1.125.
P = (200 + 240) × 1.6 × 1.125 = **792** to Ryker, and **396** to an assister.

## 17. Lumen Income (C14)

| Source | Formula (per recipient) | Avg 30-min total |
| ---- | ---- | ---- |
| Starting purse | 500 [sibling] | 500 |
| Passive trickle | 40 / min from 1:00 [sibling] | 1,160 |
| **Vanguard Wardlings** | `LV_T × S(n)`, LV_T = **35 / 45 / 55**. 75% instant, 25% as Mote | **2,900** |
| **Squad Wardlings** | `LS_T × S(n)`, LS_T = **60 / 75 / 90**, same split | 1,045 |
| **Sentinels** | `1.5 × LS_T × S(n) × RepeatDecay` | 560 |
| Hero kill | `K = (200 + Shutdown) × D`, with `Shutdown = min(300, 50 × max(0, streak − 2))` | 985 |
| Hero assist | `100 × D` each | 695 |
| Capture | Participant `120 × D × Recap`, plus every teammate `40 × D` [sibling base]. Recap ×1.25 for retaking one of your starting hardpoints | 880 |
| Defence | `60` per defender [sibling] | 240 |
| **Total** | | **≈ 8,965** |

- **Mob kills make up 50%** (4,505), and Vanguard alone is 32%, the largest single source. This satisfies C14 ("primary") and C15 ("main steady source").
- **Front-tied income** (mobs, captures and defences) is **63%** (Pillar 1).
- Squad Wardlings pay more than Vanguard because they are rarer and carry their owner's investment. Killing an upgraded squad is a worthwhile target.

**Repeat-farm guards:**
- **RepeatDecay.** A Sentinel death at hardpoint *h* within 180 s of the previous Sentinel death at *h* pays ×0.5.
- **Capture cooldown.** A team recapturing the same hardpoint within 180 s of its own previous capture of it gets ×0.25 (Lumen and EXP).
- **Defence cooldown.** At most one defence payout per hardpoint per 90 s.

## 18. 30-Minute Simulation

Model (a scratch per-minute model; average player):
- 2.8 × (1 + 0.01·min) enemy Vanguard deaths credited per minute.
- 0.7 squad-Wardling and 0.25 Sentinel deaths credited per minute.
- Mean S(n) of 0.8, and 80% of Motes collected.
- 0.17 kills and 0.24 assists per minute.
- 4 captures participated in, 10 team captures and 4 defences over 30 minutes.

The strong profile is ×1.4 activity (kills ×1.96). The weak profile is ×0.65. Comeback multipliers are excluded, so the weak column is a floor.

| Minute | Weak: Lumen / EXP (Lv) | **Average: Lumen / EXP (Lv)** | Strong: Lumen / EXP (Lv) |
| ---- | ---- | ---- | ---- |
| 5 | 1,230 / 680 (3) | **1,550 / 1,050 (4)** | 1,960 / 1,530 (6) |
| 10 | 2,150 / 1,540 (6) | **2,880 / 2,370 (7)** | 3,810 / 3,450 (9) |
| 20 | 4,150 / 3,410 (9) | **5,790 / 5,230 (11)** | 7,850 / 7,610 (14) |
| 30 | 6,320 / 5,450 (11) | **8,970 / 8,360 (15)** | 12,280 / 12,130 (15) |

**Health checks:**
- Strong-to-weak Lumen at 30:00 is **1.9×**.
- Purse plus trickle (1,660) is a floor of about 18%.
- With the catch-up multipliers, the weak player reaches about L12 by 30:00.
- **Sink check.** At 30:00 the average player holds about 9,000. weapons-and-mods plans a gun of 5,250–6,200, and the squad sink is about 8,350, so the shop cannot be exhausted before about minute 45. Med-Packs are an unlimited sink beyond that.
- **Intended spend split:** ~60% gun, ~30% squad, ~10% consumables and utility.

## 19. Armory: Non-Weapon Items

Purchases are at the HQ Armory only (C14). Bands: Minor 250–400, Standard 600–900, Major 1,400–1,800. **Consumables** sit below the bands and are anchored by the Med-Pack at 100. Squad items are in §6–§7.

| Item | Type | Price | Effect | Limit |
| ---- | ---- | ---- | ---- | ---- |
| **Med-Pack** | Consumable | 100 | Heal 40% of max HP over 3 s. Cancelled by firing. | Carry 3 |
| **Recall Shard** | Consumable | 150 | 6 s channel to the Sanctum, cancelled by hero damage. Dissolves the squad. | Carry 1 |
| **Scan Flare** | Consumable | 150 | Thrown. Reveals enemies, traps and stealth within 15 m for 3 s. | Carry 2 |
| **Cell Harness** | Utility | 300 (Minor) | +15% move speed while carrying a Mana Cell. | Permanent |
| **Stride Rig** | Utility | 750 (Standard) | +8% move speed after 4 s out of combat. Glowing calf rigs. | Permanent |
| **Barrier Lattice** | Utility | 800 (Standard) | +75 overshield, regenerating after 6 s out of combat. Hex shimmer. | Permanent |
| **Uplink Breaker** | Utility | 1,600 (Major) | +15% weapon damage vs. Ward Generators and an Exposed Uplink. Red gun sigil. Not an ammo effect, so the Uplink rule [sibling] is untouched. | Permanent |

## 20. Comeback and Anti-Snowball

| # | Mechanic | Ref |
| ---- | ---- | ---- |
| 1 | Catch-up kill EXP `C`, up to ×1.6 (C13) | §16.1 |
| 2 | Shutdown bounty, up to +300 Lumen | §17 |
| 3 | Team deficit `D`, up to ×1.25, on kills and captures | §16.1 |
| 4 | Individual EXP ×1.2 while 2+ levels below the team average | §16.1 |
| 5 | Recapture ×1.25 Lumen | §17 |
| 6 | Floor income (purse plus trickle) | §17 |
| 7 | **Vanguard self-balance.** A losing team's front sits closer to its Foundry, so its waves arrive sooner and work defended ground (Garrisons, Barricades). The winner's waves walk further into Sentinels. | §10 |
| 8 | Sublinear sharing S(n): deathballing pays 2.7×, not 5× | §15.1 |
| 9 | No leader-side multipliers on mob income | §16.1 |

## 21. Exploit Risks

| Exploit | Risk | Mitigation |
| ---- | ---- | ---- |
| Win-trading by feeding squads to the other team | Medium (ranked) | Bounties only from the opposing team. Telemetry flags feed and denial anomalies. |
| Capture ping-pong | Medium | 180 s capture cooldown at ×0.25. |
| Sentinel farming at a node you will not take | Medium | RepeatDecay ×0.5. 45 s respawn. |
| Parking at the Vanguard spawn lane to farm waves | Medium | Waves spawn inside the Sanctum's 10 m anti-entry zone (C6) and lane gates are covered by Garrisons. Spawn rate is gated by the ≤1-alive rule, so farming faster than one wave per ~15 s is impossible. |
| AFK income from detached squads (Go Capture while away) | Low | Squad kills with no hero on the share list pay only the Mote (§12). Presence still helps the team, which is intended play. |
| Stacking AI presence on Hold (Vesper squad + Vanguard + Go Capture) | Medium | Recommend that match-flow's "Wardling presence cap per team" knob default to **3.0** at the first playtest (see Dependencies). |
| Attack Target as an aimbot | Medium | Bolts are slow, dodgeable projectiles. A base squad is only 30% of Soldier DPS. LOS and 50 m required. Ends after 12 s. |
| Suicide or Recall to dodge a bounty | Low | A death within 10 s of hero damage credits the last damager's share list. Damage cancels the Recall channel. |
| Subverted Wardlings fed for bounty | Medium | Subverted units pay nothing. |
| Leeching in the 25 m radius | Low | S(n) is sublinear. |

## 22. Edge Cases

- **Owner dies during Go Capture.** The squad keeps the zone for 10 s, then dissolves (C15).
- **Attack Target on a unit that becomes subverted, malfunctions or goes stealthed.** The order ends immediately and the squad reverts. The squad never shoots a unit that is now on its own team.
- **Go Capture on a hardpoint that becomes Locked en route** (the prerequisite is lost). The squad converts to Hold at its current position, and the HUD shows "Locked".
- **Vanguard target flips mid-march.** The 2 s re-evaluation picks a new target. There is no backtracking past the wave's own front-most held hardpoint.
- **Wave survivor merge across a Surge.** The survivor morphs with the Surge. The new mints are at the new tier.
- **Expansion bought away from HQ.** Impossible (HQ-only shop). The slot is filled on the next Foundry entry.
- **Licence bought with a full squad of Pickets.** On the next Foundry entry, a Picket despawns and the variant mints.
- **Sudden Death.** All Wardlings are removed (C10) with no bounty and no Cores. The Vanguard timer stops. The shop is disabled.
- **Hero killed only by Wardlings.** It credits the Wardling's owner (squad) or, for Vanguard, the allied heroes within 25 m. If neither applies, no hero bounty is paid, but the death still counts for streaks.
- **Mote collected after a share-list member dies.** The member is still paid, because the share list is frozen at the kill.
- **Utility score tie.** The closer target wins, then the lower entity id.
- **Two Seekers.** Reveals do not stack. They only refresh.

## 23. Dependencies

| System | This doc needs | That doc must reflect |
| ---- | ---- | ---- |
| `match-flow-and-map.md` | Presence F1, capture rates F2–F4, capture and defence Lumen (120 / 40 / 60), purse 500, trickle 40, Garrison 10 s delay, 3 s Surge morph, lane splines, Foundry lane gates | **Wardling raw DPS** rises from the reference 14 to **30 at Tier I** (C15 middle ground). F4 and F9 Uplink time-to-kill drop to about 50 s for the reference team, so their Uplink Integrity or reference team needs a retune. Also: Vanguard waves (24 agents, §10), the D and Recap multipliers on capture Lumen, a presence-cap default of 3.0, and Go Capture as a presence source. |
| `weapons-and-mods.md` | Soldier reference DPS 260, armor formula, Ammo Spark size, gun price total | Spark drop rates (§12). The Lumen curve: 1,550 at 5:00, 2,880 at 10:00, 5,790 at 20:00, 8,970 at 30:00. |
| `heroes.md` | Hero HP and armor, Vesper's kit (§13 hooks), Hex malfunction, Sable stealth (Seeker) | Squad +2 for Vesper. `command_vanguard`, `rewrite_to_elite`, `subvert`, the U_dmg cap. |
| HUD / UX (future) | — | Squad strip, radial wheel, command preview glyph, detached-squad chevron |
| Bot AI (future) | — | Bots issue commands via the same API. Buy priorities follow the §18 spend split and the §19 catalog. |

## 24. Tuning Knobs

| Knob | Default | Safe range | Affects |
| ---- | ---- | ---- | ---- |
| `picket_dmg_per_bolt[T]` | 9 / 11 / 13 | ±20% | Keep the base-squad ratio in 25–35% |
| `picket_hp[T]` | 180 / 235 / 300 | ±25% | Squad survivability |
| `focus_accuracy` / `retaliate_accuracy` | 0.87 / 0.70 | 0.7–0.95 / 0.5–0.8 | Attack Target value |
| `attack_timeout_s` / `attack_los_loss_s` | 12 / 4 | 8–20 / 2–6 | Command persistence |
| `vanguard_interval_s` | 60 | Canon (fixed) | — |
| `vanguard_size` | 4 | Canon (fixed) | — |
| `vanguard_bounty_lumen[T]` | 35 / 45 / 55 | ±25% | Main steady income |
| `vanguard_bounty_res[T]` | 20 / 30 / 40 | ±25% | L15 timing |
| `squad_bounty_lumen[T]` / `_res[T]` | 60/75/90 · 45/60/75 | ±25% | Value of hunting squads |
| `sentinel_bounty_mult` | 1.5 | 1.0–2.0 | Value of attacking nodes |
| `share_k` | 1.2 | 1.0–1.5 | Group vs. solo pay |
| `mote_fraction` | 0.25 | 0–0.4 | Reward for advancing |
| `kill_lumen_base` / `assist_lumen` | 200 / 100 | 150–300 / 60–150 | Fight vs. objective pay |
| `catchup_per_level` / `catchup_cap` | 0.15 / 1.6 | 0.10–0.25 / 1.4–2.0 | Comeback |
| `deficit_D_cap` | 1.25 | 1.0–1.4 | Comeback |
| `xp_inc_early` / `xp_inc_late` | 140 + 50L / 520 + 60(L−6) | ±15% | L6 time (6–8 min) / L15 time (30–35 min) |
| `follow_leash_m` / `hold_leash_m` / `zone_leash_m` | 30 / 12 / 15 | 20–45 / 8–18 / 12–20 | Cohesion |
| `squad_dmg_cap` (U_dmg) | 0.40 | 0.3–0.6 | Ceiling on squad threat |
| Prices | §6, §7, §19 | Within their band | Build pacing |

## 25. Acceptance Criteria

1. **Income.** Across 10 bot-filled matches, the median player's Lumen at 30:00 is 8,000–10,000. Mob bounties make up ≥ 40% of it, and Vanguard is the largest single source.
2. **Pacing.** The median player reaches L6 in 6:00–8:00 and L15 in 28:00–36:00.
3. **Spread.** Top-quartile to bottom-quartile Lumen at 30:00 is ≤ 2.2×.
4. **Strength.** In a test range, 3 Tier I Pickets on Attack Target against a strafing dummy deal 70–86 DPS (27–33% of 260). A healthy, unmodded Ryker (80% accuracy) beats them with ≥ 100 HP left. A Ryker starting at 120 HP loses.
5. **Upgrade curve.** 5 Wardlings including 2 Strikers with Overclock deal 180–205 DPS under the same test.
6. **Commands.** `Z` on an enemy, a hardpoint and the ground issues Attack, Go Capture and Hold respectively. `X` issues Follow. The radial wheel issues all four. A Locked hardpoint is rejected with "Locked".
7. **Attack.** The order ends and the squad reverts within 0.2 s after the target dies, after 4 s out of LOS, or after 12 s.
8. **Go Capture.** A squad of 3 sent to a free neutral Mid Hold reaches it and holds 1.5 presence. On completion it switches to Hold at the zone centre.
9. **Vanguard.** Each lane and team never has more than 4 Vanguard units. A new wave spawns only when the previous wave has ≤ 1 alive. With no players, waves alternate target selection exactly per the §10 rule (checked on the debug overlay).
10. **Death-hold.** After the owner dies, the squad holds for 10.0 ± 0.1 s, dissolves, and pays 0 Lumen and 0 Resonance.
11. **No hero initiation.** A Follow squad beside a passive enemy hero, outside any zone, fires 0 shots over 30 s.
12. **Performance.** 108 agents in a load scene: server AI ≤ 2.0 ms average, downstream ≤ 12 KB/s per client.
13. **Drops.** A Mechanical hero collecting a squad Core gains exactly 1 magazine of reserve. An enemy touching a Core destroys it with no payout.
14. **Prices.** Every item in §6, §7 and §19 is inside its band, or is a consumable at ≤ 200.

## 26. Vertical-Slice Subset (Scope Tier 1)

The slice ships Vesper and a 3-lane map. Variants, Garrisons and Barricades are Alpha (Tier 2).

- **In.**
  - Foundry pickup with Pickets, squad 3 → 5.
  - Tiers via Surges.
  - **All 4 commands** (quick keys and the radial wheel), the squad strip and the chevrons.
  - Full BT: formation, body-block (highest-HP blocker), scoring, Attack, Go Capture TaskWorker, leash and stranding, death-hold.
  - **Vanguard waves** (in the slice, because they carry 32% of income and keep bot lanes alive).
  - The Core with Mote and Sparks.
  - Vesper hooks: capacity, modifier, elite, `command_vanguard`. `subvert` only if his slice ult uses it.
  - The full Resonance table and sources.
  - All Lumen sources except Sentinels.
  - Med-Pack, Squad Expansion I/II, Reinforced Cores I/II, Overclock Emitters.
  - D, C, Shutdown and the capture cooldown.
- **Out.** Variants (including the Surge II Vanguard Shieldling, which is replaced by a Picket), Sentinels, Barricade pathing, Harmonic Tether, Quick Mint, Bulwark, utility items other than the Med-Pack.
- **Slice re-tune.** With no Sentinels the average player loses about 560 Lumen, so `trickle_per_min` is raised to **60** for the slice. The model gives about 8,990 Lumen and L14–15 at 30:00. Check criteria 1–2 at the slice gate.

---

## Canon Concerns

These items are followed as written. Each row is a note for the creative director.

| Canon | Concern | What this doc does |
| ---- | ---- | ---- |
| Pillar 3 design test ("more than two commands … cut it") vs. C15 (4 commands) | The pillar text predates the owner's decision, and the two now contradict each other. | Follows C15 (4 commands). Keeps the "one key" spirit through the context-sensitive `Z` plus `X`. Asks that the Pillar 3 test be updated to "more than four commands". |
| Pillar 2 ("no point-and-click lock-on damage") vs. C15 Attack Target | Attack Target is a point-to-designate damage command. | Mitigates by making all Wardling fire slow, dodgeable projectiles at 30% of Soldier DPS, with LOS required and a 12 s timeout. Asks that Pillar 2 exempt AI-unit designation explicitly. |
| C15 "upgradeable to 5 (Minionmancer +2 more)" vs. the "squads ≤ 50" budget | Two Vespers (one per team) at 7 gives 54 squad agents, which exceeds 50. | Budgets 108 in total (§14). Asks the owner either to accept "≤ 54 squad" or to count Vesper's +2 inside the 5 cap (base 5, max 5). |
| C15 middle-ground strength vs. the match-flow / C7 Uplink target (~60 s) | Wardling raw DPS rises from about 14 to about 30, which shortens the reference Uplink time-to-kill to about 50 s. | Keeps C15's strength. Flags the issue for match-flow to retune the reference team or Integrity (C7 is tunable 20k–40k; about 35k restores 60 s). |
| C4 presence 0.5, uncapped | Go Capture plus Vanguard plus Vesper can stack AI presence well beyond what heroes provide. | Follows C4. Recommends match-flow's cap knob default to 3.0 AI presence per team per zone. |
