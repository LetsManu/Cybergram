# Wardlings & Economy

*Created: 2026-10-02*
*Status: Draft. Authored autonomously by economy-designer and ai-programmer (modes.automation: autonomous).*
*Canon source: `design/gdd/game-concept.md` § Canon (C4, C5, C7, C10–C16). Where this doc gives a number that Canon marks as tunable, the Canon range still applies.*
*Sibling docs (written in parallel): `weapons-and-mods.md` (owns Crystals, Chips, ammo types and their prices), `heroes.md` (owns hero HP, speed, skills, including Vesper Loom's kit), `match-flow-and-map.md` (owns hardpoint tasks, Surges, Barricades, Beacons, the HUD minimap).*

---

## 1. Overview

This doc covers two linked systems.

- **Wardlings.** These are the player-carried mana-constructs: how a squad is picked up, what each variant does, how a squad is commanded and drawn, and the AI that drives them. It also covers the map-owned **Garrison Sentinels**.
- **Economy & Progression.** This covers **Resonance** (EXP, levels 1–15) and **Lumen** (the per-match currency): where each one comes from, what the Armory sells outside the weapon catalog, and the rules against snowballing and exploits.

The two systems share one link. Enemy Wardlings are the main source of both currencies (C13, C14), so every rule about how Wardlings live and die is also an economy rule.

## 2. Player Fantasy

*"I'm a small commander with shooter hands."* You leave the Foundry with three little constructs at your heels. They step into a sniper's line of fire for you, shoot back at whoever hurts you, and stand on the point when you tell them to hold it. You never micro them. One key says "stay here" and the same key held down says "with me". Across the match your squad gets visibly tougher (Tier pips, plating, variant silhouettes) and your Resonance glyph climbs toward 15. Your money comes from breaking the enemy's squads and taking ground, never from farming.

---

# PART 1 — WARDLINGS

## 3. Squad Pickup at the Foundry

| Rule | Value |
| ---- | ---- |
| Where | Foundry zone in your HQ (C6). It is a 6 m radius pad next to the Sanctum. |
| When | Spawning at the Sanctum mints a full squad automatically. Walking into the Foundry zone at any time **tops up** empty slots. |
| Mint time | 0.5 s per Wardling, staggered. A full squad of 5 appears in 2.5 s. The *Quick Mint* upgrade makes this 0.1 s. |
| Squad size | Base **3**. *Squad Expansion I/II* raises it to **4/5** (C15). Vesper Loom gets **+2** on top of that, for a base of 5 and a maximum of 7. |
| Slot contents | Each slot holds a **Picket** (the free default) or a **licensed variant** (§5). The Foundry fills slots in this order: licensed variants first (Shieldling, Mender, Striker, Sapper, Seeker), then Pickets. |
| Replacement | A dead Wardling's slot stays empty until you re-enter the Foundry (C15). There is no other way to replace one. |
| Spawning at a Forward Beacon | You get no squad (C5). Any squad you already had has dissolved (see §8.7). |
| Recall to HQ | Recalling dissolves your current squad at the moment you depart, the same as dying (Core Loop step 5). A fresh squad is minted at the Sanctum. |
| Cost | Pickets and re-mints are **free**. You pay Lumen only for licences and upgrades. Rationale: Pillar 3 says the squad is a resource you *spend*, and making each re-mint cost money would punish the HQ choice twice. |

## 4. Tier Stats

Tier follows the Surges (C15): **Tier I** from 0:00, **Tier II** from 15:00, **Tier III** from 30:00. At a Surge, every Wardling and Sentinel alive upgrades on the spot. It keeps its current HP percentage, plays a 0.6 s crystal-bloom VFX and grows one extra tier pip on its back fin (Pillar 4).

**Picket (the baseline every variant multiplies):**

| Stat | Tier I | Tier II | Tier III | Notes |
| ---- | ---- | ---- | ---- | ---- |
| HP | 150 | 200 | 260 | Assumes hero HP of about 250–600 (heroes.md). A Tier I Picket dies to about 1.5 s of focused rifle fire. |
| Damage per shot | 6 | 8 | 10 | Mana bolt, projectile at 60 m/s. |
| Fire interval | 0.5 s | 0.5 s | 0.5 s | 12 / 16 / 20 DPS at 100% hit rate. |
| Accuracy (cone) | 4° | 3.5° | 3° | Hits about 60% of shots on a strafing hero at 15 m. |
| Engage range | 20 m | 22 m | 24 m | |
| Move speed | 6.2 m/s | 6.2 m/s | 6.4 m/s | Catch-up sprint to 8.5 m/s when more than 10 m from its formation slot. |
| Damage vs. Uplink | ×0.5 | ×0.5 | ×0.5 | Canon C7. |
| Hold presence | 0.5 | 0.5 | 0.5 | Canon C4. |
| Collision radius | 0.45 m | 0.45 m | 0.5 m | |
| Bounty (Lumen / Resonance) | 60 / 45 | 75 / 60 | 90 / 75 | See §13 and §14. |

## 5. Variant Catalog

A **licence** is bought at the Armory (shown at the Foundry kiosk as well). It turns **one** squad slot into that variant for the rest of the match, and the Foundry re-mints it for free. Limits: at most **2 licences per variant** and **1 Mender**.

| Variant | Price (band) | HP × | DPS × | Range | Trait | Silhouette tell |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| **Picket** | free | 1.0 | 1.0 | 20 m | None. | Small biped with a single crystal eye. |
| **Shieldling** | 350 (Minor) | 1.6 | 0.4 | 15 m | **Aegis plate:** takes −40% damage from a 120° frontal arc. Gets top priority for the body-block slot (§8.3). | Large front shield and a hunched stance. |
| **Striker** | 400 (Minor) | 0.8 | 1.6 | 25 m | **Focus:** +25% damage to a target its owner hit in the last 2 s. It stays defensive (§8.4) and never starts fights against heroes. | Long barrel arm and a forward lean. |
| **Seeker** | 300 (Minor) | 0.8 | 0.6 | 20 m | **Sense:** reveals stealthed heroes and armed traps within **12 m** to its team for 1.5 s, re-checked every 0.5 s. This is the counter to Sable and Juniper (heroes.md owns the stealth rules). | Antenna crest and a sweeping scan light. |
| **Mender** | 700 (Standard) | 0.9 | 0.3 | 15 m | **Mend beam:** heals its owner by 8 / 11 / 14 HP/s (Tier I/II/III), or the most-damaged squadmate when the owner is full, soft-targeted within 10 m. Heal is halved for 2 s after the owner takes hero damage. | Floating halo and a green tether beam. |
| **Sapper** | 650 (Standard) | 1.0 | 0.8 | 18 m | **Breacher:** ×3 damage vs. Barricades and Ward Generators. No bonus vs. the Uplink (C7's ×0.5 still applies). | Backpack charge and drill arm. |

Rationale. Every variant except the Sapper is defensive or a support (Pillar 3, owner note "more on the defending side"). The Sapper is the one "specific variation" for offence, and it is gated behind the Standard band. A full licensed 5-squad costs between about 1,400 and 2,300 Lumen, which is 15–25% of the 30-minute budget.

## 6. Squad Upgrades

These are bought at the Armory, last for the match and apply to every Wardling in the owner's squad.

| Upgrade | Price (band) | Effect | Visible tell |
| ---- | ---- | ---- | ---- |
| **Squad Expansion I** | 800 (Standard) | Squad size +1, to 4. | Extra slot lit on the HUD strip. |
| **Squad Expansion II** | 1,500 (Major) | Squad size +1, to 5. Requires Expansion I. | Same as above. |
| **Reinforced Cores I** | 350 (Minor) | Wardling HP +20%. | Plating rim on the body. |
| **Reinforced Cores II** | 750 (Standard) | Wardling HP +40% in total. Requires I. | Full plating. |
| **Overclock Emitters** | 700 (Standard) | Wardling damage +20%. | Brighter muzzle glow. |
| **Harmonic Tether** | 300 (Minor) | Move speed +12%. Follow leash 30 → 40 m. | Owner-colour trail. |
| **Quick Mint** | 250 (Minor) | Foundry mint time 0.5 s → 0.1 s per Wardling. Wardlings get +25% damage resistance for 5 s after they are minted. | Mint VFX in gold. |
| **Bulwark Protocol** | 1,400 (Major) | Wardlings in **Hold** mode take −30% damage and get +25% body-block radius. Their Hold presence stays 0.5 (C4). | Wardlings in Hold plant a small ground shield. |

The squad sink capacity is about 6,050 Lumen of upgrades plus up to about 2,300 of licences. No player can buy all of it alongside a weapon build, so the choice of what to skip is real.

## 7. Commands, UX and Owner Visualization

**Two commands, one key** (Pillar 3). The default bind is `Z`, and it can be rebound.

| Input | Command | Behaviour |
| ---- | ---- | ---- |
| **Tap `Z`** | **Hold Here** | Sets a Hold point at the crosshair's ground hit (projected onto the navmesh, at most **25 m** away). If nothing valid is under the crosshair, the point is set at the owner's feet. Tapping again while already holding *moves* the Hold point. |
| **Press `Z` ≥ 0.35 s** | **Follow** (default state) | The squad comes back to the owner's formation. |

There is no per-unit selection, no split squads and no attack-move.

- **Feedback.** Each order plays an acknowledgement chirp (about 40 ms). A 0.4 s ground decal pulses at the Hold point. The squad strip flashes the new state.
- **Hold marker.** A thin owner-colour light pillar stands at the Hold point, visible to the owner at any range. Teammates see a dim version within 40 m, plus a minimap tick (a hook into match-flow-and-map.md's HUD).

**Squad strip (HUD, bottom-left, above the health bar).** It shows one icon per slot: the variant glyph, a small HP bar, 1–3 tier pips and a state badge (`F` for Follow, `H` for Hold, `!` for in combat, `↻` for returning). An empty slot shows a grey Foundry glyph. During the death-hold, the strip shows a 10 s ring timer.

**In the world:**
- The owner's own Wardlings get a 1 px owner-accent outline (the player's personal colour inside the team colour) and a 0.6 m ground ring. Other allies' Wardlings show only the team colour.
- When an owned Wardling is off-screen and either under fire or more than 20 m away, a screen-edge chevron points to it. Within 30 m it is visible through walls as a faint silhouette, for the owner only.
- **Line-of-fire courtesy.** Allied bullets pass through allied Wardlings. Wardlings also steer out of a 1.2 m-wide corridor along the owner's aim ray (§8.3), so they never visually block the owner's sights.

## 8. Behaviour Design

### 8.1 Architecture

Each Wardling runs a **behaviour tree whose combat branches are chosen by utility scores**. A **Squad Brain** (one per owner) computes the shared data: the formation frame, the current threat list, the Hold point and the slot assignment. Individual Wardlings read that data through blackboard keys and do not repeat the work.

- The server runs the BT at **10 Hz**, staggered across agents. Steering and avoidance run at **30 Hz**.
- Perception is read only through condition nodes (`HasThreat`, `OwnerAlive`, `InLeash`). Movement code never queries perception directly.

```
Root (Selector)
├─ [OwnerDead] → DeathHold          (§8.7)
├─ [Stranded]  → HoldAtCurrent       (§8.6)
├─ [OutOfLeash] → ReturnToLeash      (ignore targets, sprint, no firing)
├─ [Mode == Hold]
│   └─ Selector
│       ├─ [ThreatInHoldRadius] → UtilityCombat(HoldScoring)
│       └─ MoveTo(HoldSlot) → Idle(scan)
└─ [Mode == Follow]
    └─ Selector
        ├─ [OwnerUnderFire && Variant==Shieldling|best blocker] → BodyBlock
        ├─ [HasThreat] → UtilityCombat(FollowScoring)
        └─ MoveTo(FormationSlot) → MatchOwnerFacing
UtilityCombat: pick target = argmax Score(t); if Score < 0.25 → no target;
               strafe ±2 m around the slot; fire when LOS && inCone
```

### 8.2 Follow Formation

- The formation is a **loose wedge behind the owner**. Slots sit 3–6 m away, spread across a 140° arc behind the owner's movement direction. Slot 0 (the blocker) sits 2.5 m forward-left. The Mender's slot sits 3 m directly behind the owner.
- Slots are recomputed by the Squad Brain at 5 Hz, using the owner's **velocity** for the frame (or facing when standing still). Slots that fall off the navmesh snap to the nearest valid point within 2 m. If none is valid, the slot collapses toward the owner.
- When the owner sprints more than 10 m away, the Wardlings switch to catch-up speed (§4). If the owner moves 2 s faster than catch-up speed (with mobility skills), the Wardlings keep pathing and the leash rules apply.

### 8.3 Body-Block

- **Trigger.** The owner has taken hero damage in the last 2 s, from a known source.
- **Action.** The best blocker moves onto the line between the owner and that attacker, **2.0–3.0 m** from the owner. The best blocker is the Shieldling if there is one, otherwise the Wardling with the highest HP. If there are two attackers, the second-best blocker covers the second line.
- **Constraints.** It must stay outside the owner's 1.2 m aim corridor: if the blocking line and the aim ray overlap within 15°, it offsets 1 m to the side. Wardlings collide with **enemy** heroes and Wardlings (they can be shot and can physically block). They do not collide with allies.
- **Release.** The block ends 2 s after the last hit, after which the Wardling returns to its formation slot.

### 8.4 Retaliation Targeting (Utility)

```
Score(t) = 0.45·Threat(t) + 0.20·Proximity(t) + 0.15·Objective(t) + 0.10·Focus(t) + 0.10·Stickiness(t)
Threat     = clamp(damage t dealt to [owner ×1.0, this Wardling ×0.7, squadmates ×0.5] in last 3 s / 60, 0, 1)
Proximity  = 1 − clamp(dist(t, owner) / 25 m, 0, 1)
Objective  = 1 if t is inside the hardpoint zone the squad is in or holding, else 0
Focus      = 1 if owner hit t in last 2 s, else 0      (Striker weights this ×2)
Stickiness = 1 if t is current target, else 0          (prevents twitching)
Gate: an enemy HERO with Threat == 0 and Objective == 0 is scored 0 (never initiate on heroes).
Gate: enemy Wardlings / Sentinels within 10 m are always valid (mob-vs-mob fighting is allowed).
```

Example. An enemy hero who dealt 40 damage to the owner 1 s ago, standing 10 m from the owner, outside any zone, and not hit by the owner:
`0.45·0.667 + 0.20·0.6 + 0 + 0 + 0 = 0.42`, which is above the 0.25 threshold, so the Wardling engages.

### 8.5 Hold Mode and Hold-Zone Contribution

- **Hold radius** is **8 m** around the Hold point. Wardlings take slots in a ring around it, facing the nearest enemy-side lane direction. They engage enemies inside the hold radius plus 12 m, and never chase further than **12 m** from the Hold point.
- **Inside a Hold-task zone**, each Wardling counts **0.5 presence** (C4). Two extra rules apply (they extend C4; see Canon Concerns):
  - (a) Wardling presence **contests** a zone, stalling progress, but only **advances** capture while at least one allied hero is in the zone.
  - (b) Wardling plus Sentinel presence per team per zone is capped at **3.0** (tunable 2.0–4.0).
- In a Plant or Breach zone, held Wardlings defend the zone and damage Ward Generators (the Sapper deals ×3), but have no presence value.

### 8.6 Leash Distances

| Situation | Leash | On break |
| ---- | ---- | ---- |
| Follow mode | 30 m from the owner (40 m with Harmonic Tether) | `ReturnToLeash`: drop the target, sprint, hold fire until back within 20 m. |
| Hold mode | 12 m from the Hold point | Return to the Hold slot. |
| Owner unreachable (no path, or more than 60 m away for 20 s) | — | **Stranded.** The squad auto-switches to Hold at its current position, and the HUD shows "Squad stranded". It resumes Follow when the owner comes back within 30 m or issues Follow and a path exists. There are no teleports, so movement stays honest and readable. |

### 8.7 Pathing Around Barricades

- Barricades (C5) are navmesh obstacles. They are passable (via a nav layer bit) for the owning team and blocked for the enemy. Each squad's path is requested once by the Squad Brain to the formation centroid. Individual Wardlings use local steering.
- If the owner crosses an enemy Barricade (Sable phasing, a broken gap, or a jump), the squad re-paths around it through flank routes, but only when the detour is no more than **2.5×** the direct distance. Otherwise the squad waits at the Barricade, holding with a 6 m radius, until the owner is back on their side, or the Barricade breaks, or the stranded rule applies.
- When an allied Barricade is breached and destroyed, the nav layer is updated and squads re-path within 0.5 s.
- Hacked Barricades or gadgets (Hex) change their nav layer for as long as the hack lasts (heroes.md defines the duration).

### 8.8 Death of the Owner (Canon C15: 10 s hold)

1. When the owner dies, the squad enters **DeathHold**: Hold mode at the squad's centroid snapped to the navmesh, radius 8 m. It still contests zones and retaliates.
2. After 10 s, the squad **dissolves** with a 1 s fade. Dissolved Wardlings pay **no bounty** and drop **no Core**.
3. Wardlings killed by enemies **during** DeathHold pay normal bounties.
4. If the owner respawns before the 10 s are up (respawn at 0:00 is 6 s, C11), the old squad still dissolves on schedule. The respawned owner gets a fresh squad from the Foundry. There is no re-binding, because the rule must stay readable.

## 9. Garrison Sentinels (Canon C5)

| Rule | Value |
| ---- | ---- |
| Count | **2 per held hardpoint.** The maximum is 15 × 2 = **30**. At the start there are 24 (Mids begin neutral and have no Garrison). |
| Spawn | 15 s after a capture (the first spawn). After that, each Sentinel respawns **45 s** after it dies (C5), for as long as its team holds the hardpoint. When the hardpoint flips, the existing Sentinels dissolve (no bounty). |
| Stats (I / II / III) | HP 400 / 550 / 700. DPS 20 / 26 / 32. Range 25 m. Speed 4 m/s. Tiered by Surge. |
| Behaviour | Hold-mode BT anchored to the zone centre. Leash **15 m**. Targeting uses §8.4 with `Objective` weighted ×2 and with the hero-initiation gate **removed**: Sentinels shoot any enemy within range. |
| Presence | 0.5 in Hold zones (counted inside the 3.0 cap). |
| Bounty | ×1.5 the Picket bounty for that tier. There is a *Repeat decay* (§16): each Sentinel death at the same hardpoint within 180 s of the previous one pays 50%. |
| Exclusions | Not affected by owner commands, squad upgrades or the death-hold. **Hex** and **Vesper** can still affect them through the hooks in §12. |

## 10. Wardling Drops: the Wardling Core

When an enemy Wardling or Sentinel is killed by the other team, it drops a **Wardling Core**. This is a glowing pickup that lasts 10 s and has a 1.2 m auto-collect radius.

- **Lumen Mote.** 75% of the Lumen bounty is paid **instantly** to the share list (§13). The remaining **25%** sits in the Core. When any allied hero on the share list touches it, that 25% is paid to **everyone on the share list**. This rewards stepping forward onto the ground just won, without creating a last-hit race between allies.
- **Mechanical ammo.** A **Mechanical** hero who collects the Core regains **20%** of their weapon's maximum reserve (**35%** from a Sentinel Core). It is capped at the maximum, and weapons-and-mods.md owns the reserve sizes. Mana heroes get no ammo from it.
- **Denial.** An enemy hero (that is, the Wardling's own team) who touches the Core destroys it. The Mote and the ammo are both lost.

## 11. Performance and Network Budget

**Agent count.** At most 8 heroes × 5 + 2 Vesper × 7 = **54 squad Wardlings**, plus **30 Sentinels**, for **84 AI** in the worst case. A typical match has about 35–50. Sudden Death drops this to 0 (C10).

| Budget | Target |
| ---- | ---- |
| Server AI update (all 84 agents) | ≤ **2.0 ms** per frame on average, ≤ 3.0 ms at peak. BT at 10 Hz across 3 staggered buckets. Squad Brain at 5 Hz. |
| Path requests | ≤ **8 per server tick**, queued. One per squad (to the formation centroid), not one per Wardling. Re-paths happen only on a Barricade change or a slot jump of more than 5 m. |
| Perception | Shared per squad. Uses a spatial hash (8 m cells) with no per-agent raycasts. LOS raycasts are limited to the current target, at most 1 per agent per 0.2 s. |
| Client render | Animation LOD: full rate within 30 m, 15 fps from 30–60 m, and a pose-baked impostor beyond 60 m. Wardling total ≤ **1.5 ms** GPU at 1080p on the min-spec target. |
| Snapshot size | About **11 bytes per agent**: position quantised to 3×16 bits, yaw 8, HP% 8, state/variant/tier 8, target id 8, owner id 8. |

**Network relevance (interest management):**
- Your own squad is **always relevant** to you, at 20 Hz, and includes exact HP for the squad strip.
- Other agents within **60 m** or inside your view frustum up to 120 m are sent at 20 Hz.
- Agents between 60 and 120 m and out of view are sent at 5 Hz.
- Agents beyond 120 m are not sent, except as minimap dots (owned by match-flow-and-map.md) at 1 Hz in aggregated form.
- The worst-case downstream cost is about 84 × 11 B × 20 Hz ≈ 18.5 KB/s. With relevance applied the expected cost is about 6–9 KB/s per client.
- Damage from Wardlings is **server-authoritative** without lag compensation, because AI projectiles are simulated on the server. Hero shots *at* Wardlings use the same lag-compensated hit registration as shots at heroes.

## 12. Minionmancer (Vesper Loom) Hooks

heroes.md designs the kit. This system exposes the following hooks, all server-side and data-driven:

| Hook | Contract |
| ---- | ---- |
| `squad_capacity_bonus: int` | Per hero. Vesper = +2. Added after the Expansion upgrades. |
| `apply_squad_modifier(target_owner, stat, mult, duration)` | Stat buckets: `hp`, `damage`, `move_speed`, `damage_taken`, `heal_out`. Same-source modifiers do not stack; different sources multiply. Lets Vesper buff *allied* players' squads (C17: "empowers allies' squads"). |
| `rewrite_to_elite(wardling, duration)` | **Elite overlay:** tier +1 (Tier III becomes "Tier IV" = Tier III × 1.25 HP and damage), a gold outline and a scale of 1.15. The variant stays the same. Works on any allied Wardling within the radius heroes.md defines. |
| `subvert(enemy_wardling, new_owner, duration)` | Temporarily switches the team and owner. It joins the new owner's squad as an **overflow** unit that does not count against capacity and has no HUD slot; it appears only with a purple-ringed icon. While subverted it pays **no bounty** to anyone. When the effect ends it returns to its original team, and to Hold-at-current if its original owner is dead or out of leash. Sentinels **cannot** be subverted (they are only rewritten to elite). |
| `issue_command(owner, cmd)` | Lets a skill issue Follow or Hold on behalf of an owner. Used by Vesper's own kit only. |
| Signals | `wardling_minted(w)`, `wardling_died(w, killer, share_list)`, `squad_command_issued(owner, cmd, point)`, `squad_dissolved(owner, reason)`. |

Hex uses the same `subvert`-style status channel with `cmd = malfunction`: the target stops firing and wanders back toward its owner. heroes.md sets the durations.

---

# PART 2 — ECONOMY & PROGRESSION

## 13. Shared Concept: Share List and Share Factor

When an enemy Wardling, Sentinel or hero dies, the **share list** is every hero on the killing team who is:
- within **25 m** of the death position (C13), **or**
- dealt damage or healing that counted toward the kill in the last **5 s** (heroes) or **3 s** (Wardlings).

The killing blow gets no special treatment for Wardling bounties, by design: there is **no last-hitting** (Anti-Pillar).

```
S(n) = min(1, 1.2 / √n)        n = size of share list (1..5)
n:      1     2     3     4     5
S(n): 1.00  0.85  0.69  0.60  0.54     → team total grows 1.0 → 2.7× with n (grouping pays, leeching does not)
```

## 14. Resonance (EXP) — Levels 1–15 (Canon C12)

```
inc(L) = 140 + 50·L            for L = 1..5     (EXP from level L to L+1)
inc(L) = 500 + 60·(L − 6)      for L = 6..14
```

| Level | EXP to next | Cumulative to reach | Avg-player minute | Unlocks (C12) |
| ---- | ---- | ---- | ---- | ---- |
| 1 | 190 | 0 | 0:00 | 1 skill point |
| 2 | 240 | 190 | ~2 | |
| 3 | 290 | 430 | ~3 | |
| 4 | 340 | 720 | ~4 | |
| 5 | 390 | 1,060 | ~5.5 | |
| 6 | 500 | 1,450 | **~7** | Ultimate rank 1 |
| 7 | 560 | 1,950 | ~9 | |
| 8 | 620 | 2,510 | ~11 | |
| 9 | 680 | 3,130 | ~13 | Mastery nodes |
| 10 | 740 | 3,810 | **~16** | Ultimate rank 2 |
| 11 | 800 | 4,550 | ~18 | |
| 12 | 860 | 5,350 | ~21 | |
| 13 | 920 | 6,210 | ~24 | |
| 14 | 980 | 7,130 | ~27 | Ultimate rank 3 |
| 15 | — | **8,110** | **~31** | Cap (15 points) |

These meet the C12 targets: L6 at about 7 minutes (target 6–8) and L15 at about 31 minutes (target 30–35). Strong players hit L15 at about 22 minutes and weak players reach about L11–12 by 30:00 (§17). There is **no passive EXP**, because C13 lists the sources.

### 14.1 EXP Sources

| Source | Formula (per recipient) | Typical value |
| ---- | ---- | ---- |
| Enemy Wardling death | `R_T × S(n)`, with R_T = 45 / 60 / 75 by tier | 31–75 |
| Enemy Sentinel death | `1.5 × R_T × S(n) × RepeatDecay` | 47–112 |
| Enemy hero kill (killer) | `P = (200 + 20·Lv_victim) × C × D` | 240–700 |
| Assist / ally within 25 m | `0.5 × P` | 120–350 |
| Capture (whole team) | `100 × D` to every teammate, anywhere | 100–125 |
| Capture (participant bonus) | `+250 × D`. A participant is in the zone ≥ 10 s during the task, or carried/planted the Mana Cell, or damaged the Ward Generator | 250–312 |
| Defence (participant) | `150`, when attacker progress was ≥ 25% and is driven to 0 or the task fails | 150 |
| Individual catch-up | `×1.2` on all Resonance while `Lv ≤ team_avg_Lv − 2` | — |

**Catch-up kill bonus (C13):**
```
C = min(1.6, 1 + 0.15 × max(0, Lv_victim − Lv_killer))
```
Example: an L8 Ryker kills an L12 Brannoc, with one assister nearby and no team deficit (D = 1).
P = (200 + 240) × min(1.6, 1 + 0.6) = 440 × 1.6 = **704** to Ryker, and **352** to the assister.

**Team deficit multiplier** (applies to hero-kill and capture rewards only, never to Wardling rewards, so a team cannot farm it):
```
gap = (Res_leader − Res_team) / Res_leader      (team-total Resonance; 0 for the leading team)
D   = 1 + min(0.25, 0.5 × gap)
```
Example: the trailing team has 18,000 Resonance and the leader has 24,000. gap = 0.25, so D = 1.125.

## 15. Lumen Income Sources (Canon C14)

| Source | Formula (per recipient) | Avg 30-min total |
| ---- | ---- | ---- |
| **Starting purse** | 500 at 0:00 | 500 |
| **Passive trickle** | 60 / min from 1:00 | 1,740 |
| **Enemy Wardlings (primary)** | `L_T × S(n)`, L_T = 60 / 75 / 90. Paid 75% instantly and 25% through the Core Mote (§10) | 2,790 |
| **Enemy Sentinels** | `1.5 × L_T × S(n) × RepeatDecay`, same split | 670 |
| **Hero kill** | `K = (200 + Shutdown) × D`, with `Shutdown = min(300, 50 × max(0, streak_victim − 2))` | 990 |
| **Hero assist** | `0.5 × 200 × D` to every assister (Shutdown not shared) | 700 |
| **Capture** | Participant `200 × D × Recap`. Rest of team `75 × D`. `Recap = 1.25` when retaking a hardpoint your team started with | 1,250 |
| **Defence** | Participant `120` (same trigger as EXP) | 480 |
| **Total** | | **≈ 9,120** |

Enemy Wardlings and Sentinels together make up **38%** of income, the largest single source, which satisfies C14's "primary". Front-tied sources (Wardlings, captures and defences) make up **57%**, which meets Pillar 1's design test.

## 16. Repeat-Farm Guards

- **RepeatDecay (Sentinels).** A Sentinel death at hardpoint *h* within 180 s of the last Sentinel death at *h* pays ×0.5.
- **Capture cooldown.** A team capturing the same hardpoint again within **180 s** of its own previous capture of it gets ×0.25 Lumen and Resonance.
- **Defence cooldown.** Defence rewards at a given hardpoint pay at most once per 90 s.

## 17. 30-Minute Income Simulation

Model assumptions (scratch model, average player):
- 1.6 × (1 + 0.01·min) enemy Wardling deaths credited per minute, at a mean S(n) of 0.8 and 80% Mote collection.
- 0.3 Sentinel deaths per minute.
- 0.17 kills and 0.24 assists per minute.
- 4 captures participated in and 10 team captures over 30 minutes.

The strong profile multiplies activity ×1.4 (kills ×1.96). The weak profile multiplies it ×0.65. Purse and trickle are the same for everyone. Comeback multipliers are **excluded**, so the weak column is a floor.

| Minute | Weak — Lumen / EXP (Lv) | **Average — Lumen / EXP (Lv)** | Strong — Lumen / EXP (Lv) |
| ---- | ---- | ---- | ---- |
| 5 | 1,300 / 660 (3) | **1,600 / 1,010 (4)** | 1,970 / 1,470 (6) |
| 10 | 2,310 / 1,490 (6) | **2,980 / 2,290 (7)** | 3,830 / 3,330 (9) |
| 20 | 4,460 / 3,270 (9) | **5,940 / 5,020 (11)** | 7,820 / 7,310 (14) |
| 30 | 6,750 / 5,190 (11) | **9,120 / 7,970 (14)** | 12,120 / 11,580 (15) |

Reading the table:
- The strong-to-weak Lumen ratio at 30:00 is **1.8×**. That is enough to reward skill, but the weak player still affords about two full Major purchases.
- The trickle plus purse (2,240) is a guaranteed floor of about 25%, so a struggling player always reaches a Standard item every ~10 min.
- With the individual EXP catch-up (×1.2) and the D multiplier, the weak player's level at 30:00 rises to about 12.

**Sink check.** At 30:00 an average player has about 9,100 Lumen. The intended split is ~55% weapon (weapons-and-mods.md), ~30% squad, ~15% consumables and utility. The total catalog (weapon + squad about 8,350 + utility about 2,900) is well above 9,000, so the shop cannot be exhausted before about minute 45. After that, Med-Packs (an infinite consumable sink) absorb any surplus. Mana Drought and late matches are therefore not flooded with unspendable money.

## 18. Armory Catalog — Non-Weapon Items

Purchases happen at the HQ Armory only (C14). Prices follow the bands: Minor 250–400, Standard 600–900, Major 1,400–1,800. **Consumables** sit below the bands, anchored by the Med-Pack at 100. Wardling licences and upgrades are listed in §5–§6.

| Item | Type | Price | Effect | Limit |
| ---- | ---- | ---- | ---- | ---- |
| **Med-Pack** | Consumable | 100 | Use (key `4`): heal 40% of max HP over 3 s. The heal is cancelled if you fire your weapon. Liora's drones are separate (heroes.md). | Carry 3 |
| **Recall Shard** | Consumable | 150 | 6 s channel, then teleport to the Sanctum. Dissolves your squad on departure. Taking hero damage cancels it. | Carry 1 |
| **Scan Flare** | Consumable | 150 | Thrown. Reveals enemies, traps and stealth within 15 m for 3 s to your team. | Carry 2 |
| **Mana Cell Harness** | Utility | 300 (Minor) | +15% move speed while carrying a Plant-task Mana Cell. | Permanent |
| **Stride Rig** | Utility | 750 (Standard) | +8% move speed out of combat (no hero damage dealt or taken for 4 s). Visible as glowing calf rigs. | Permanent |
| **Barrier Lattice** | Utility | 800 (Standard) | +75 overshield that regenerates after 6 s out of combat. Shown as a hex shimmer on the body. | Permanent |
| **Uplink Breaker** | Utility | 1,600 (Major) | +15% weapon damage vs. Ward Generators and an **Exposed** Uplink. Shown as a red sigil on the gun. | Permanent |

Utility total is about 3,450, plus consumables. Every permanent item has a visible tell (Pillar 4).

## 19. Comeback and Anti-Snowball Mechanics

| # | Mechanic | Where it lives |
| ---- | ---- | ---- |
| 1 | **Catch-up kill EXP** `C` (≤ ×1.6) for killing a higher-level hero (C13). | §14.1 |
| 2 | **Shutdown bounty**: up to +300 Lumen for ending a streak. | §15 |
| 3 | **Team deficit multiplier** `D` (≤ ×1.25) on kill and capture rewards for the trailing team. | §14.1 / §15 |
| 4 | **Individual EXP catch-up** ×1.2 while 2+ levels below the team average. | §14.1 |
| 5 | **Recapture bonus** ×1.25 Lumen for retaking an original hardpoint. | §15 |
| 6 | **Floor income**: 500 purse plus 60/min trickle, independent of performance. | §15 |
| 7 | **Defender geometry**: Garrisons, Barricades and short walks to the Foundry near home. The losing team fights closer to its free squads. | §3, §9, C5 |
| 8 | **Sublinear sharing** `S(n)`: deathballing five heroes onto one squad yields 2.7×, not 5×, per kill. | §13 |
| 9 | **No Wardling-reward multipliers**: the leading team cannot amplify farming. | §14.1 |

## 20. Exploit Risks

| Exploit | Risk | Mitigation |
| ---- | ---- | ---- |
| Feeding your own squads to an ally on the enemy team (win-trading) | Medium in customs, high in ranked | No friendly fire on Wardlings. Bounties only from the opposing team. Ranked telemetry flags lopsided Core-denial and feed patterns. |
| Capture ping-pong (two teams trading a node to farm) | Medium | Capture cooldown ×0.25 within 180 s (§16). |
| Sentinel farming at an unattackable node | Medium | RepeatDecay ×0.5. Sentinels only respawn every 45 s. |
| Defence-reward farming by stopping attacks at 25% | Low | 90 s defence cooldown. Participation is required. |
| Leeching by standing in the 25 m radius | Low | S(n) is sublinear. The share list is open to anyone, but each share shrinks as it grows. |
| Wardling-only Hold capture while the owner farms elsewhere | High | Wardlings contest but do not advance capture without an allied hero in the zone, and presence is capped at 3.0 (§8.5). |
| Recall Shard / suicide to dodge kill bounty | Low | A death within 10 s of hero damage credits the last damager and its share list in full, including falls into the Leyfall. A Recall channel is cancelled by damage. |
| Mote sniping by enemies to deny income | Intended | Denial costs the 25% Mote only. Counterplay is to walk forward. |
| Subverted Wardlings fed for bounty | Medium | Subverted units pay no bounty (§12). |
| Bot backfill farming | Low | Bots follow the same rules. Bot slots are not exempt from the guards. |

## 21. Edge Cases

- **Squad at the moment of a Surge while in DeathHold.** It upgrades on the spot and still dissolves at 10 s.
- **Owner disconnects.** The bot takes over the hero and its squad keeps its state (C1). There is no dissolve.
- **Squad Expansion bought while away from HQ.** Not possible (HQ-only shop). The new slot is filled the next time you enter the Foundry.
- **Licence bought with a full squad of Pickets.** The next Foundry entry replaces a Picket with the variant: the Picket despawns and the variant mints.
- **Hold point set on an enemy-only nav layer** (behind an enemy Barricade). It is projected to the nearest point reachable by the squad. If none exists within 10 m, the command is rejected with an error chirp.
- **Sudden Death begins.** All Wardlings and Sentinels are removed (C10) with no bounty and no Cores. Lumen is kept but unspendable (the shop is disabled).
- **Hero killed by a Wardling with no hero damage in the last 10 s.** The kill is credited to the Wardling's owner, and the share list is built around the death position.
- **Tie in the utility score.** The closer target wins, then the lower entity id.
- **Mote collected after the share-list member dies.** Dead members still receive their Mote share. This is the rule because the share list is frozen at the moment of the kill.
- **Two Seekers revealing.** Reveals do not stack. A reveal refreshes its timer only.
- **Elite rewrite on a subverted Wardling.** Allowed. Both effects run independently and expire separately.

## 22. Dependencies

| System | This doc needs | That doc should reference |
| ---- | ---- | ---- |
| `heroes.md` | Hero HP and speed (for Wardling tuning), Vesper's kit (§12 hooks), Hex malfunction, Sable stealth (Seeker), Liora drones | Squad size +2, `apply_squad_modifier`, `rewrite_to_elite`, `subvert` |
| `weapons-and-mods.md` | Reserve sizes (Core ammo %), weapon price total (sink split) | Lumen budget ≈ 9,000 per 30 min. Core gives 20% / 35% reserve. |
| `match-flow-and-map.md` | Hardpoint zones, task presence rules, Barricade nav layers, Surge times, Foundry and Armory placement, minimap | 0.5 presence, the 3.0 cap and hero-required advance (§8.5). Capture and defence reward triggers. Sentinel spawn rules. |
| HUD / UX (future `design/ux/hud.md`) | — | Squad strip, Hold marker, edge chevrons, Lumen/Resonance readouts |
| Networking (future ADR) | Interest management, snapshot format | §11 budget |
| Bot AI (future) | — | Bots use the same `Z` command API and buy from the §18 priorities |

## 23. Tuning Knobs

| Knob | Default | Safe range | Affects |
| ---- | ---- | ---- | ---- |
| `wardling_bounty_lumen[T]` | 60 / 75 / 90 | ±25% | Share of income from Wardlings (keep ≥ 35%) |
| `wardling_bounty_res[T]` | 45 / 60 / 75 | ±25% | L6 and L15 timing |
| `sentinel_bounty_mult` | 1.5 | 1.0–2.0 | Attacking-node value |
| `share_k` in S(n) | 1.2 | 1.0–1.5 | Group vs. solo pay |
| `share_radius_m` | 25 | 20–30 (C13 says 25; changing it needs Canon) | — |
| `mote_fraction` | 0.25 | 0.0–0.4 | Reward for advancing |
| `trickle_per_min` | 60 | 40–90 | Floor income |
| `starting_purse` | 500 | 400–800 | Deploy-phase buys |
| `kill_lumen_base` / `assist_ratio` | 200 / 0.5 | 150–300 / 0.3–0.6 | Fight vs. objective pay |
| `catchup_per_level` / `cap` | 0.15 / 1.6 | 0.1–0.25 / 1.4–2.0 | Comeback strength |
| `deficit_D_cap` | 1.25 | 1.0–1.4 | Comeback strength |
| `xp_inc_early` (140 + 50L) | — | ±15% | L6 time (keep 6–8 min) |
| `xp_inc_late` (500 + 60·(L−6)) | — | ±15% | L15 time (keep 30–35 min) |
| `wardling_hp[T]`, `dps[T]` | §4 | ±30% | Wardling relevance vs. noise |
| `follow_leash_m` / `hold_leash_m` | 30 / 12 | 20–45 / 8–18 | Squad cohesion |
| `wardling_presence_cap` | 3.0 | 2.0–4.0 | Squad dominance in Hold |
| `death_hold_s` | 10 | Canon (fixed) | — |
| `sentinel_first_spawn_s` | 15 | 5–30 | Post-capture safety window |
| Item prices | §5, §6, §18 | Must stay inside their band | Build pacing |

## 24. Acceptance Criteria

1. **Income.** In 10 bot-filled full matches, the median player's earned Lumen at 30:00 is **8,000–10,000**. Wardling plus Sentinel bounties make up ≥ 35% of each player's income.
2. **Pacing.** In the same matches, the median player reaches L6 between 6:00 and 8:00 and L15 between 28:00 and 36:00.
3. **Spread.** The ratio of the top-quartile to bottom-quartile player's Lumen at 30:00 is ≤ 2.2×.
4. **Commands.** Tapping `Z` sets a Hold within 25 m and the squad arrives within 3 s on open ground. Holding `Z` for ≥ 0.35 s returns Follow. No third command exists.
5. **Death-hold.** After the owner dies, the squad holds for 10.0 ± 0.1 s and then dissolves. Dissolved units grant 0 Lumen and 0 Resonance (check the server log).
6. **Body-block.** With a Shieldling in the squad and the owner shot from a fixed turret, the Shieldling is on the attack line within 2.5 s and never inside the owner's aim corridor (debug draw).
7. **No hero initiation.** A squad in Follow next to an enemy hero who never deals damage, outside any objective zone, fires 0 shots at that hero over 30 s.
8. **Leash.** A Wardling never ends more than 30 m (Follow) or 12 m (Hold) from its anchor for longer than 3 s, except while stranded.
9. **Barricade.** With the owner on the far side of an enemy Barricade and no detour within 2.5×, the squad holds at the Barricade and the HUD shows "Squad stranded" within 20 s.
10. **Performance.** With 84 agents active in a load-test scene, the server AI frame cost is ≤ 2.0 ms on average and the downstream per client is ≤ 12 KB/s.
11. **Drops.** A Mechanical hero collecting a Picket Core regains exactly 20% of max reserve. An enemy touching a Core destroys it with no payout.
12. **Prices.** Every Armory item listed in §5, §6 and §18 is priced inside its band (or is a consumable at ≤ 200).

## 25. Vertical-Slice Subset (Scope Tier 1)

The Tier 1 scope puts Garrisons, Barricades, Beacons and Wardling variants in Alpha. The slice therefore ships:

- **In.**
  - Foundry pickup, Picket only, squad 3 → 5 (Expansion I/II).
  - Tier I/II/III via Surges.
  - Follow/Hold on `Z`, the squad strip and the Hold marker.
  - BT nodes: formation, body-block (best blocker = highest HP), retaliation utility, Hold presence with cap and hero gate, leash/stranded, death-hold.
  - Wardling Core (Mote and ammo).
  - Vesper hooks: `squad_capacity_bonus`, `apply_squad_modifier`, `rewrite_to_elite` (Vesper is in the slice). `subvert` is **in** only if Vesper's ult needs it in the slice.
  - The full Resonance table and every EXP source.
  - Lumen purse, trickle, Wardling, kill, assist, capture and defence income.
  - Med-Pack, Reinforced Cores I/II, Overclock Emitters.
  - The deficit multiplier, the catch-up bonus and the capture cooldown.
- **Out.** Variants, Sentinels, Barricade pathing, Bulwark Protocol, Harmonic Tether, Quick Mint, utility items other than the Med-Pack, Recall Shard and Scan Flare.
- **Slice re-tune.** With no Sentinels the average player loses about 670 Lumen, so **`trickle_per_min` is raised to 80** (+580) for the slice only. Check criteria 1–2 at the slice gate.

---

## Canon Concerns

These items are followed as written. Each row records a concern for the creative director.

| Canon | Concern | What this doc does |
| ---- | ---- | ---- |
| C1 (rationale "~60 AI") vs. C5/C15 | 30 Garrison Sentinels plus up to 54 squad Wardlings (two Vespers at 7) gives **84** AI in the worst case, not about 60. | Budgets for 84 (§11) and asks that the C1 rationale be updated to "≤ 84 AI (typically 35–50)". |
| C15 "base 3, upgradeable to 5 (Minionmancer +2 more)" | It is ambiguous whether Vesper's +2 is on top of the maximum of 5 (giving 7) or within it. | Reads it as base 5, maximum 7 (consistent with C17 "carries +2 Wardlings"). heroes.md should confirm. |
| C4 "Wardlings contribute to Hold presence at 0.5" | Taken alone, this allows capture by Wardlings only (an AFK exploit) and lets a Vesper squad (3.5 presence) dominate zones. | Keeps 0.5 per Wardling but adds the **hero-required-to-advance** gate and a **3.0 per-team cap** (§8.5). This needs a Canon footnote or the match-flow doc to accept it. |
| C14 "Lumen sources … small passive trickle" | At about 19% of income (1,740 of 9,120), the trickle is larger than "small" might suggest. It is needed to give weak players a floor without breaking the 9,000 target. | Keeps it at 60/min (tunable 40–90). Flagged for the owner. |
