# Match Flow & Map

*Created: 2026-10-02*
*Status: Draft. Authored autonomously by level-designer + systems-designer (modes.automation: autonomous).*
*Binding source: `design/gdd/game-concept.md` § Canon (C1–C18). This doc owns the details of C2–C11. It does not change any Canon value.*
*Economy constraint (producer): about 9,000 Lumen per player per 30 min. Armory bands: **Minor** 250–400, **Standard** 600–900, **Major** 1,400–1,800. Med-Pack 100.*

---

## 1. Overview

This doc defines how a Cybergram match runs from the first second to the result, and the one arena it runs on. It covers the match state machine (Deploy → Skirmish → Surges → Drought → Time-out → Incursion → Sudden Death → End), the 3-lane map with 15 task hardpoints, the exact capture, contest, decay and flip rules, Mana Uplink exposure and damage, and the formulas that set tempo: capture rate, respawn (C11), Surge modifiers and Incursion score. It also specifies a reduced **Slice Map** (1 lane, 5 hardpoints, both HQs) for the first playable vertical slice.

## 2. Player Fantasy

*"The front moved because we moved it."* At any moment a player can read the war at a glance: which nodes glow blue or red, where the barricades stand, which spire is exposed. Early on the map is a set of skirmishes over three Mid hardpoints a short run from home. By minute 20 the fronts are bent and one lane is cracking. By minute 30 a team wipe is worth 18 seconds of empty ground, and that is enough to reach a spire. Every hardpoint feels like a place with a job to do: hold the bridge, carry the cell through the market, crack the gatehouse generator. The match always ends.

---

## 3. Detailed Rules

### 3.1 Match state machine

The match clock `t` runs from 0:00. Every state listed below except Time-out, Incursion and End can also exit straight to **End** when an Uplink reaches Integrity 0 (§3.6).

```
 [Load] -> DEPLOY -> SKIRMISH -> SURGES(I -> II) -> DROUGHT -> TIME-OUT -> INCURSION --decisive--> END
   0:00     1:00      15:00     30:00   45:00      60:00                  \--tied--> SUDDEN DEATH -> END
           (any combat state: an Uplink at 0 -> END)                          (mutual kill: loops to SD freeze)
```

| State | Entry condition | What is true during it | Exit condition → next |
| ---- | ---- | ---- | ---- |
| **Load** (pre-state) | Match created | Clients load. Bots are assigned to empty slots (C1). | All 10 slots ready, or 60 s load timeout (missing humans become bots) → Deploy |
| **Deploy** | Load complete; `t = 0:00` | Everyone spawns at their Sanctum with **500 Lumen** (enough for one **Minor** item at 250–400 plus one Med-Pack at 100). Foundry gives each player a squad of 3 Tier I Wardlings. Mid hardpoints are **Locked** and show a countdown. A **Leyfall Veil** blocks the map midline (x = 210 m): no movement or damage crosses it. All Outer and Inner hardpoints are attackable only through the C3 chain, so nothing is capturable yet. | `t = 1:00` → Skirmish |
| **Skirmish** | `t = 1:00` | The Veil drops and Mid hardpoints unlock as neutral. Wardlings and Garrisons are Tier I. Duration multiplier `D_s = 1.00`. | `t = 15:00` → Surges (I); an Uplink reaches 0 → End |
| **Surges / Surge I** | `t = 15:00` | Every living Wardling and Garrison Sentinel transforms in place to Tier II over 3 s (an invulnerable morph). `D_s = 0.85`. In-progress tasks keep their progress *fraction* and continue at the new rate. | `t = 30:00` → Surge II |
| **Surges / Surge II** | `t = 30:00` | Tier III, the same morph. `D_s = 0.70`. Respawn continues to grow per C11. | `t = 45:00` → Drought |
| **Drought** (Mana Drought) | `t = 45:00` | The exposure rule widens: an Uplink is Exposed if the enemy holds ≥1 of its team's Inner **or Outer** hardpoints (C7). `D_s` stays 0.70. | `t = 60:00` → Time-out |
| **Time-out** | `t = 60:00` (hard cap, C8) | Both Mana Reserves run dry. On the 60:00 server tick the game takes a **snapshot** of hardpoint ownership and Uplink Integrity. Then a 5 s freeze: inputs are locked except the camera, everyone is invulnerable, and Wardlings, tasks, projectiles and respawn timers are suspended. In-progress captures **do not complete** (see Canon Concern 1). | After 5 s → Incursion |
| **Incursion** | Time-out ends | Incursion score is computed from the snapshot (F7). There is a 10 s reveal: lane-by-lane bars, then totals, then Uplink damage % if the totals are tied. | Higher Incursion wins → End. Tied, and Uplink damage % differs by ≥1.0 point → End. Still tied → Sudden Death |
| **Sudden Death** | Incursion tied | Per C10. Sub-states: **SD-Freeze** (5 s: every player respawns at full HP and ammo on their own half of the Mid Plaza; Wardlings and Garrisons are removed, the shop is disabled, levels and gear are kept). **SD-Round** (no respawns; the Leyfall ring closes over 90 s). **SD-Confirm** (a 1.0 s window that opens when a team's last fighter dies). | One team eliminated and the other still has a fighter alive when SD-Confirm ends → End. Both teams' last fighters died within 1.0 s → SD-Freeze (new round) |
| **End** | Uplink at 0, or a decisive Incursion, or a decisive SD | Result banner, then 20 s of stats. Lumen, levels and purchases are discarded (Anti-Pillar). | → post-match flow (out of scope) |

**Sudden Death ring.** The ring starts at radius 45 m centred on the Spindle (C-Mid), which covers the plaza and the first 15 m of each spoke. It shrinks linearly to 4 m at 90 s. Outside the ring a fighter takes 8% of max HP per second. After 90 s, **Leyfall Bloom** begins: every fighter takes 2% of max HP per second, and the rate rises by 2% every 10 s. This guarantees that each round ends.

### 3.2 Map layout: "Shardline Front"

Reference **hero move speed = 6.0 m/s** (base run, used for all run-times here). The movement GDD owns the real value; times scale linearly. Wardlings follow at 6.5 m/s. A Mana Cell carrier moves at 5.4 m/s. Axis: x runs west to east (Concord HQ at x = 0, Syndicate HQ at x = 420); lane centrelines are at y = +80 (North), 0 (Center) and −80 (South). Between lanes is open Leyfall sky, which is impassable except through flank tunnels, the Mid spokes and HQ interiors.

```
 x(m) ->  0  25 40      85          145           210           275          335      380 395 420
                                                  (not to scale; see distance table)
 NORTH y+80     .---[N-AI]=========[N-AO]======[N-MID]======[N-BO]=========[N-BI]---.
                /     Br              Ho  \      /  Pl  \      /  Ho            Br     \
               /                     (Fx-AN)  X    ||    X  (Fx-BN)                     \
 +---------+  /                           /    \   ||   /    \                           \  +---------+
 | Sanctum |-'  |B|                      /      \ .||. /      \                     |B|   '-| Sanctum |
 | Foundry |------[C-AI]=========[C-AO]===|B|===( C-MID )===|B|===[C-BO]=========[C-BI]------| Foundry |
 | UPLINK  |-.  |B|       Ho         Pl  \      (MID PLAZA)      /  Pl         Ho   |B|   .-| UPLINK  |
 | Armory  |  \                           \    / '||' \    /                           /  | Armory  |
 +---------+   \                     (Fx-AS)  X    ||    X  (Fx-BS)                     /  +---------+
 CONCORD HQ     \     Pl              Br  /      \  Br  /      \  Br            Pl     /    SYNDICATE HQ
 SOUTH y-80      '---[S-AI]=========[S-AO]======[S-MID]======[S-BO]=========[S-BI]---'
  ===  lane main path (12-20 m wide)    ||  Mid spoke    X  flank tunnel crossing (Undercroft)
  |B|  Barricade socket (example)       Ho/Pl/Br  task type    AI/AO = Concord Inner/Outer, BO/BI = Syndicate
```

**Geometry rules**
- **HQ** (40 × 60 m walled compound): the Sanctum is at x = 5 with a 10 m no-entry and heal zone (C6). The Uplink stands in an open courtyard at x = 30, 25 m from the Sanctum. The Foundry and Armory sit beside the Sanctum. Three lane gates open at x = 40; the North and South gates climb ramp roads to their lanes. The courtyard walls are 12 m high, so the Uplink core can only be hit from inside the HQ walls or from its three gates.
- **Hardpoint zones** are 6 m tall cylinders: Hold r = 12 m, Breach r = 12 m (centred on the Generator), Plant r = 10 m (centred on the Socket).
- **Barricade sockets:** each hardpoint has two, placed 15 m outside its zone edge on the main path, one on each side. Only the socket that faces the owner's enemy is active (C5).
- **Flank tunnels (Undercroft):** four X-shaped tunnel pairs, one per team half per lane pair (Fx-AN, Fx-AS, Fx-BN, Fx-BS). Each X links the **Outer side door** of one lane to the **Mid side door** of the adjacent lane, and the two diagonals cross in a 15 m junction room. Side doors open *inside* hardpoint zones, so flanks bypass all Barricades by design (C2, C5). They run only between the Outer and Mid rows (C2).
- **Mid Plaza:** a circle of r = 30 m at (210, 0). The Spindle (C-Mid) sits at its centre. Two 50 m spokes link the plaza to N-Mid and S-Mid. The plaza is also the Sudden Death arena, with spawn pads at x = 185 (Concord) and x = 235 (Syndicate).
- **Sightlines:** lane sightlines are capped at 70 m by blockers. The one exception is Lattice/Rivet Bridge, at 90 m, which gives the North lane its long-range identity.

**Distances and run-times (path length, 6.0 m/s)**

| Route | Metres | Seconds |
| ---- | ---- | ---- |
| Sanctum → own Uplink | 25 | 4 |
| Sanctum → C-Inner / N- or S-Inner (ramp road) | 85 / 130 | 14 / 22 |
| Inner → Outer (any lane) | 60 | 10 |
| Outer → Mid (main path) | 65 | 11 |
| Sanctum → own C-Mid / N- or S-Mid | 210 / 255 | 35 / 43 |
| Mid ↔ adjacent Mid (spoke via plaza) | 80 | 13 |
| Outer side door ↔ adjacent lane's Mid side door (flank) | 110 | 18 |
| Forward Beacon (Mid) → enemy Outer / enemy Inner | 65 / 125 | 11 / 21 |
| Forward Beacon (C-Mid) → enemy Uplink | 210 | 35 |
| Sanctum → Sanctum (Center lane) | 410 | 68 |
| Mana Cell: Outer Cradle → Mid Socket (carrier speed) | 65 | 12 |

A Beacon spawn saves 24–32 s of running to the enemy Outer compared with an HQ spawn. In return the player arrives without a squad or a shop visit (C5, C11).

### 3.3 The 15 hardpoints

Every lane is mirror-symmetric (A and B halves are geometric mirrors with faction dressing), so both teams face identical tasks. Each task type appears exactly 5 times. **Base duration** is the time for the *reference push*, which is 1 hero plus 3 Wardlings, uncontested, at `D_s = 1.00` (see F2–F4).

| Hardpoint | Name (Concord / Syndicate side) | Task | Base duration | Terrain identity |
| ---- | ---- | ---- | ---- | ---- |
| N-AI / N-BI | Glasswork Gate / Furnace Gate | Breach | Generator 6,000 + Hold 20 s (≈80 s) | A gatehouse with the Generator under an arch, flanked by two balconies that overlook the approach. |
| N-AO / N-BO | Lattice Bridge / Rivet Span | Hold | 65 s | A 20 m wide bridge over the Leyfall with no centre cover and pylons at each end; the 90 m sightline lane. |
| N-MID | Belfry Ruin | Plant | 70 s | A ruined crystal bell tower; the Socket is on the top floor, reached by 3 stairwells. |
| C-AI / C-BI | Concord Atrium / Boiler Hall | Hold | 75 s | An indoor atrium with pillars and a mezzanine ring, so close range dominates. |
| C-AO / C-BO | Signal Market / Scrap Bazaar | Plant | 75 s | Market stalls and awnings with five entrances; the Socket sits under the central canopy. |
| C-MID | The Spindle | Hold | 60 s | A raised dais at the centre of Mid Plaza, exposed from 360°. |
| S-AO / S-BO | Halo Dock / Cinder Dock | Breach | Generator 5,000 + Hold 20 s (≈70 s) | A docked skiff carries the Generator; shallow mana-water slows movement by 15%. |
| S-MID | Leyfall Pumpworks | Breach | Generator 4,500 + Hold 20 s (≈65 s) | A two-level pump room with the Generator on the lower floor and grated catwalks above. |
| S-AI / S-BI | Prism Locks / Slag Locks | Plant | 80 s | Canal lock gates; the Socket is on the lock floor, under catwalks the defenders control. |

Inner tasks are the longest (75–80 s), which gives the defender an advantage before minute 30. Mids are the shortest (60–70 s), so early fights resolve quickly. All values fall within C4's 60–90 s range.

### 3.4 Capture rules

**Roles.** For an owned hardpoint, the owner is the **defender**. The other team is the **attacker** only if it is *eligible* under C3, meaning it holds the adjacent hardpoint toward its own HQ in that lane. A team's own Inner is always eligible for that team, because the adjacent node is its HQ. An ineligible team's presence counts as zero, its Plant socket rejects Cells, and Generator damage from it is ignored. The HUD shows **Locked** for that team. A neutral Mid (before its first capture) is attackable by both teams.

**Presence.** `Pres(team)` = heroes alive in the zone (1.0 each; stealthed heroes count) + 0.5 × that team's Wardlings in the zone. Garrison Sentinels count as Wardlings for their owner (C4). Dead heroes and dissolving squads count 0. `Δ = Pres(attacker) − Pres(defender)`.

**Hold.** Progress `P ∈ [0, 1]` belongs to the attacker.
- `Δ > 0` → P rises at the rate given by F2.
- An attacker is present and `Δ ≤ 0` → **Contested**: P is frozen.
- No attacker present → **Overtime window**, then **decay** (below).
- Neutral Mid: the team with higher presence is the attacker. If the other team holds progress, that progress first drains at 2× the decay rate before the new team builds its own. Equal presence freezes P.

**Plant.**
1. The attacker takes a Mana Cell from the **Cell Cradle** at its eligible adjacent hardpoint (for a team's own Inner, the Cradle is at its HQ lane gate). Pickup is a 1 s interact. Only one active Cell per team per hardpoint at a time.
2. The carrier moves at 90% speed, can fire their weapon, and cannot use mobility skills; phasing or teleporting drops the Cell. The carrier is pinged on the enemy minimap every 3 s.
3. A dropped Cell lies for 15 s. Any attacker can pick it up by touching it. A defender hero standing on it for 2 s **disperses** it. When it expires or is dispersed, the Cradle produces a new Cell after 10 s.
4. **Plant:** a 3 s channel inside the Socket zone. **Defuse:** a 6 s channel by a defender *hero*. Both are broken by crowd control or by leaving the zone. Damage alone does not break them.
5. While a Cell is planted, charge P rises at the rate in F3: full speed when `Pres(att) ≥ Pres(def)`, half speed otherwise. A defused Cell is destroyed, and P then follows the Overtime/decay rule.

**Breach.**
1. **Phase 1, Generator:** HP = base × `D_s` (F4). Its shield blocks all damage that originates outside the 12 m zone, and blocks *all* damage while `Pres(def) > Pres(att)`. Wardlings and hero deployables deal 50% to it (the same as for the Uplink, C7). If the Generator takes no attacker damage for 8 s, it regenerates 4% of max HP per second.
2. **Phase 2, Hold:** when the Generator is destroyed, a 20 s × `D_s` Hold runs under the Hold rules. If phase-2 progress sits at 0 with no attacker present for 15 s, the Generator respawns at full HP.
3. Neutral S-MID: the team with higher presence in the zone when the Generator dies gets phase 2. Equal presence goes to the team that dealt more Generator damage.

**Overtime window.** When the last attacker leaves the zone or dies (or a Cell is defused), P is frozen for **5 s**, or **10 s if P ≥ 0.75**. The HUD shows "OVERTIME". If an attacker re-enters during the window, nothing is lost.

**Decay.** After the window, P falls at half the base rate (F3), or at the full base rate if a defender is in the zone. Decay stops at 0.

**Severed hardpoints.** A hardpoint that is cut off from its owner's chain (the owner no longer holds the adjacent node toward its own HQ) is **Severed**. Its retake duration is ×0.75 (`K_sev`). All C5 benefits stay in place.

**Prerequisite lost mid-task.** If the attacker loses eligibility while a task is running, its active Cell dissolves and P drains at 2× the decay rate. No Overtime window applies.

### 3.5 When a hardpoint flips

A flip is instant and goes straight to the capturing team (C3).

| Element | On flip |
| ---- | ---- |
| **Garrison** (C5) | The old owner's Sentinels dissolve over 2 s. After a 10 s settling delay the new owner gets 2 Sentinels at the current Surge tier. Each Sentinel respawns 45 s after it dies. Sentinels never leave the zone. |
| **Barricade** (C5) | The old owner's socket collapses. The new owner's socket (on the side facing *its* enemy) raises over 15 s and becomes solid at the end. Players standing in the socket volume are pushed out toward their own side. Integrity is 5,000 (2,500 for a socket that faces an HQ gate, see Canon Concern 4). Wardlings deal 50% to it. A destroyed Barricade rebuilds 60 s later if the hardpoint is still held. The owning team passes through freely. |
| **Supply Cache** (C5) | Changes owner after 10 s. Refills Mechanical reserve ammo to full; per-player cooldown 20 s. |
| **Forward Beacon** (Mid only) | Becomes a spawn point for the new owner after a 15 s attunement. It is "under attack", and so not selectable, while enemy progress P > 0 or an enemy hero is within 25 m of the zone centre. |
| **Rewards** | Each participant (a hero who was in the zone during the last 10 s) gets **120 Lumen**, and every teammate gets 40 Lumen. A defence (P decays from ≥0.5 to 0, or a Cell is defused) pays 60 Lumen to each defender hero in the zone. Resonance amounts are owned by the progression GDD (C13). |

**Lumen budget from match flow** (per player, typical 30 min): starting 500 + passive trickle 40/min × 29 = 1,160 + captures about 5 × 120 + 10 × 40 = 1,000 + defences about 5 × 60 = 300. That totals **≈2,960, or about 33% of the 9,000 target**. The remaining ≈6,000 comes from enemy Wardlings (the primary source, C14) and kills, as specified in the economy GDD. 9,000 Lumen buys roughly one **Major** (1,400–1,800), four or five **Standard** (600–900), three **Minor** (250–400) and Med-Packs (100).

### 3.6 Mana Uplink: exposure and damage

- **Integrity 30,000** (C7). It is invulnerable unless **Exposed**.
- **Exposed** while the enemy holds ≥1 of this team's Inner hardpoints, and from 45:00 also ≥1 Outer (F6). Exposure is re-evaluated every server tick, with no lingering. On a change, a 1 s VO and HUD sting plays and the spire's shell opens or seals.
- **Damage sources:** hero weapons and damaging skills 100%; enemy Wardlings 50%; hero deployables (traps, turrets, drones) 50%; Garrisons cannot attack it. A hit counts only if the Uplink is Exposed on the server tick when it lands.
- **Permanence:** no regen, no healing, no shields (C7). Each team's cumulative damage is tracked as a % of 30,000 for the tie-break (C9).
- **Target time to kill:** 30,000 / ≈500 DPS (5 heroes × 80 structure DPS + 15 Wardlings × 7 effective) ≈ **60 s** uncontested at mid-match gear (F8).
- **Integrity 0:** End on that tick, and the attacking team wins. If both Uplinks reach 0 on the same tick, see §5.

### 3.7 Slice Map (vertical slice): "Shardline Causeway"

One lane (the Center lane geometry, 410 m Sanctum to Sanctum), 5 hardpoints, both full HQs and a reduced Mid Plaza. Task assignment differs from the full Center lane so that the slice exercises all three task types:

```
 +---------+                                (MID PLAZA r=25m)                                +---------+
 | CONCORD |--[S-AI]=========[S-AO]========|B|==( S-MID )==|B|========[S-BO]=========[S-BI]--| EMBER   |
 |   HQ    |    Breach   60m    Plant  \     65m   Hold   65m     /  Plant    60m   Breach   |   HQ    |
 +---------+  (85m from Sanctum)        '--- flank loop 90m ---'  '--- flank loop 90m ---'   +---------+
                                       (Outer side door <-> Mid side door, one per half)
```

| Slice hardpoint | Task | Base duration | Identity (reuses full-map kit) |
| ---- | ---- | ---- | ---- |
| S-AI / S-BI | Breach | Generator 6,000 + 20 s | Glasswork / Furnace Gate kit |
| S-AO / S-BO | Plant | 75 s | Signal Market / Scrap Bazaar kit |
| S-MID | Hold | 60 s | Spindle dais in a reduced plaza (r = 25 m); also the Sudden Death arena |

Slice rules are identical to the full map, with these differences: Incursion ranges 0–3 (one lane); each half has one flank loop (90 m, 15 s; the main path is 65 m) so that Barricades and flanking can be tested; the full state machine runs, and a debug `clock_scale` (default 1.0; QA uses 0.25) compresses the timeline for testing. With one lane, a slice match is expected to run **12–22 min**. Match length is therefore validated only on the full map.

---

## 4. Formulas

**F1. Presence.** `Pres = H + 0.5 × W`

| Symbol | Type | Range | Description |
| ---- | ---- | ---- | ---- |
| H | int | 0–5 | Living heroes of the team in the zone |
| W | int | 0–27 | Team Wardlings in the zone (squads 3–5 each, up to 7 for Vesper, plus 2 Sentinels) |
| Pres | float | 0–18.5 | Output. Unclamped (Wardling cap knob, §7) |

Example: 2 heroes + 6 Wardlings = 5.0.

**F2. Hold capture rate.** `dP/dt = M(Δ) / (T_base × D_s × K_sev)`, where `M(Δ) = min(M_max, 0.4 + 0.24 × Δ)` for Δ > 0. If Δ ≤ 0 the rate is 0 (Contested or no attackers).

| Symbol | Type | Range | Description |
| ---- | ---- | ---- | ---- |
| Δ | float | 0.5–18.5 | Pres(att) − Pres(def) |
| M | float | 0.52–2.0 | Advantage multiplier; 1.0 at Δ = 2.5 (the reference push) |
| M_max | float | 2.0 | Cap |
| T_base | float | 20–80 s | §3.3 (20 s for Breach phase 2) |
| D_s | float | 0.70–1.00 | Surge duration multiplier (F5) |
| K_sev | float | 0.75 or 1.0 | Severed retake multiplier |
| dP/dt | float/s | 0.0069–0.0635 | Output |

Output range: the slowest case is Δ = 0.5 at T = 75, `D_s` = 1, giving 0.52/75 = 0.0069/s (144 s). The fastest is M = 2.0 at T = 60, `D_s` = 0.70, `K_sev` = 0.75, giving 2/31.5 = 0.0635/s (15.8 s). Neither is zero nor negative, so no division risk (T_base ≥ 20). Example: the Spindle at 18:00 (`D_s` = 0.85), attackers 2H + 6W = 5.0 against defenders 1H + 2 Sentinels = 2.0, so Δ = 3.0 and M = 1.12. dP/dt = 1.12/51 = 0.0220/s, and the capture takes **45.5 s**.

**F3. Plant charge and decay.** `charge = 1/(T_base × D_s × K_sev)` per second when Pres(att) ≥ Pres(def), and ×0.5 otherwise. `decay = 0.5/(T_base × D_s)` per second, or `1.0/(T_base × D_s)` if a defender is in the zone, after the Overtime window. Example: Signal Market at 20:00, P = 0.60 after a defuse. Overtime is 5 s (P < 0.75), then decay with a defender present is 1/63.75 = 0.0157/s, so the progress is gone in 38 s.

**F4. Breach Generator.** `HP_gen = HP_base × D_s`. `DPS_eff = Σ hero_structure_DPS + 0.5 × Σ wardling_DPS`. `t_breach = HP_gen / DPS_eff + 20 × D_s / M(Δ)`.

| Symbol | Type | Range | Description |
| ---- | ---- | ---- | ---- |
| HP_base | int | 4,500–6,000 | §3.3 |
| hero_structure_DPS | float | 60–140 | Reference 80 at mid-match gear (owned by the weapons GDD) |
| wardling_DPS | float | 10–25 | Raw; reference 14 at Tier I |
| t_breach | float | ≈25–110 s | Output |

Example: Halo Dock at 21:00 has HP 5,000 × 0.85 = 4,250. Attackers are 2 heroes + 6 Wardlings, so DPS_eff = 160 + 42 = 202, and Phase 1 takes 21 s. Phase 2 has Δ = 5.0 against an empty zone, so M = 1.6 and it takes 17/1.6 = 10.6 s. Total ≈ **31.6 s**.

**F5. Surge modifiers.** `D_s(t) = 1.00 if t < 15:00; 0.85 if 15:00 ≤ t < 30:00; 0.70 if t ≥ 30:00`. `Tier(t) = I / II / III` on the same breakpoints. `D_s` scales T_base for Hold, Plant charge, Breach phase 2 and Generator HP. It does not affect Cell plant or defuse channels, the Overtime window, or Barricades.

**F6. Exposure.** `Exposed(X) = (enemy holds ≥1 Inner of X) OR (t ≥ 45:00 AND enemy holds ≥1 Outer of X)`.

**F7. Respawn (C11).** `R(s) = min(R_max, R_0 + k × m)`, where m = match minutes at the time of death (float).

| Symbol | Default | Range | Description |
| ---- | ---- | ---- | ---- |
| R_0 | 6 | 4–10 | Base seconds |
| k | 0.4 | 0.3–0.5 | Seconds added per minute |
| R_max | 30 | 25–35 | Cap (reached at m = 60) |

Values: 0:00 → 6 s; 12:00 → 10.8 s; 30:00 → 18 s; 45:00 → 24 s; 60:00 → 30 s. The same timer applies to HQ and Beacon spawns (the trade-off is squad and shop access, not time).

**F8. Incursion score (C9).** `lane_score = max over held hardpoints h in the lane of depth(h)`, with depth: own Inner or Outer = 0, Mid = 1, enemy Outer = 2, enemy Inner = 3. `Incursion = Σ over 3 lanes` (0–9; 0–3 on the Slice Map). Tie-break: `U = 100 × damage_dealt_to_enemy_uplink / 30,000`, and the team with the higher U wins if `|U_A − U_B| ≥ 1.0`; otherwise Sudden Death. Example: Concord holds N-MID, C-BO and nothing past its own S-AO, giving 1 + 2 + 0 = 3. Syndicate holds S-AO (Concord's), S-MID and nothing else, giving 2 + 0 + 0 = 2. **Concord wins.**

**F9. Uplink time to kill.** `TTK = 30,000 / (Σ hero_structure_DPS + 0.5 × Σ wardling_DPS)`. The reference full team is 400 + 105 = 505, giving TTK 59.4 s (the C7 target). 3 heroes with 7 Wardlings give 240 + 49 = 289, or 104 s.

---

## 5. Worked Example: a 31-minute match

| Clock | Event | Numbers |
| ---- | ---- | ---- |
| 0:00 | Deploy. Each player buys a Minor (300) and a Med-Pack (100) and picks up 3 Wardlings. | Lumen 500 → 100 |
| 1:00 | Skirmish: the Veil drops. Concord sends 2/2/1 heroes to N/C/S; Syndicate sends 1/2/2. | Sanctum → C-Mid 35 s |
| 1:35–2:50 | Spindle (Hold 60 s): Concord 2H+6W against Syndicate 1H+3W, Δ = 2.5, M = 1.0. Syndicate's second hero arrives at 2:05 with P = 0.5, which makes it Contested. Concord trades a kill and finishes at 2:50. | Respawn at 2:20 = 6.9 s |
| 3:05 | The Spindle becomes a Concord Forward Beacon (15 s attunement). | |
| 4:40 | Syndicate breaches S-MID: 4,500 / 202 DPS = 22 s, plus a 20 s / 1.6 = 12.5 s hold. | |
| 6:10 | Concord carries a Cell from Lattice Bridge (12 s) and plants at Belfry Ruin. The charge runs 70 s and completes at 7:23. | |
| 10:10 | Concord's Plant at Scrap Bazaar (C-BO) is defused at P = 0.55. The 5 s Overtime runs out, then the progress decays to 0 by 10:50. | |
| 15:00 | Surge I: Tier II, `D_s` 0.85. | Spindle Hold now 51 s |
| 18:20 | Syndicate retakes the Spindle (Δ 3.0 → 45.5 s, F2). Concord's Beacon is lost. | |
| 21:00 | Syndicate breaches Halo Dock (Concord's S-AO) in 31.6 s (F4). | |
| 24:30 | Syndicate charges a Plant at Prism Locks (S-AI): 80 × 0.85 = 68 s. **Concord Uplink Exposed.** | |
| 24:40–26:10 | Syndicate deals 9,000 damage (30%) before Concord retakes Prism Locks from its HQ-gate Cradle (Severed? No: Syndicate still holds S-AO). The Uplink seals. | U_Synd = 30.0 |
| 29:50 | Syndicate retakes Prism Locks. Exposed again. | |
| 30:00 | Surge II: Tier III, `D_s` 0.70. | Respawn 18 s |
| 30:20 | Syndicate wipes 4 Concord heroes at the HQ gate. The remaining 21,000 Integrity takes 4H × 80 + 9W × 7 = 383 DPS. | TTK 55 s |
| 30:38 | The first Concord respawns (died 30:20, R = 18.1 s), 4 s from the Uplink. That is too few, too late. | |
| 31:15 | Concord Uplink reaches 0, Syndicate wins. Typical length confirmed (target 25–35). | |

---

## 6. Edge Cases

| Case | Resolution |
| ---- | ---- |
| **Player disconnects** | After a 10 s grace the slot is taken over by a bot (C1) with the same hero, level, gear, Lumen and squad. A player who reconnects takes control back at their next death, or immediately if the bot is within the Sanctum zone. A disconnected Cell carrier drops the Cell (normal drop rules). |
| **Disconnect during Sudden Death** | The bot takes over immediately (no grace) and counts as a fighter. |
| **Whole team disconnected** | The match continues with 5 bots. No forfeit at Tier 1 (surrender is out of scope). |
| **Stalled match** (no flips) | **Stagnation:** after 15:00, if no hardpoint has flipped anywhere for 5:00, all task durations are ×0.85 on top of `D_s` until the next flip. This does not stack. Combined with Surges and Drought, the Time-out still guarantees resolution at 60:00. |
| **Capture in progress at 60:00** | It does not count. The snapshot uses ownership at the 60:00 tick (C8 hard cap). See Canon Concern 1. |
| **Respawn timer running at 60:00** | Irrelevant to Incursion. In Sudden Death everyone respawns. |
| **Incursion tie, Uplink % within 1.0 point** | Example: Concord dealt 12.4% and Syndicate 11.6% (a 0.8 difference), so the match goes to Sudden Death. |
| **Both Uplinks reach 0 on the same tick** | Compare Incursion at that tick. If still tied, compare U. If still tied, Sudden Death. |
| **Mutual kill in Sudden Death** | The last fighters of both teams die within 1.0 s (from weapons, ring or Bloom). Everyone respawns in SD-Freeze and the ring resets. There is no limit on restarts (C10; see Canon Concern 2). |
| **Last fighter dies, opponent dies 1.2 s later** | The first team to be eliminated loses. SD-Confirm closed at +1.0 s while the opponent was still alive. |
| **Attacker loses eligibility on the flip tick** | Server order: flips resolve first in hardpoint-ID order, then eligibility is re-evaluated. A flip that lands on the same tick stands. |
| **Beacon becomes under attack during the respawn countdown** | The spawn falls back to the Sanctum without resetting the timer, and a HUD notice is shown. |
| **Barricade raises on top of players** | Players are pushed out toward their own side over 0.5 s, and collision applies after the push. |
| **Uplink exposure ends mid-flight** | Projectiles that land on a sealed tick deal 0. |
| **Neutral Mid with equal presence** | Frozen. If neither team is present, progress decays as normal. |
| **Wardling squad owner dies inside a zone** | The squad holds for 10 s and keeps counting (C15), then dissolves and counts 0. |

---

## 7. Dependencies

| System (GDD, planned) | Direction | Interface |
| ---- | ---- | ---- |
| Hero movement | This doc depends on it | Run speed (6.0 m/s reference), mobility skills that drop Cells |
| Weapons & combat | Depends on | Structure DPS reference (80) for F4 and F9; damage on hit |
| Wardlings | Both directions | Presence 0.5, Tier by Surge, Garrison Sentinels, 50% structure damage, 10 s dissolve |
| Economy & Armory | Both directions | Starting 500, capture/defence payouts, trickle 40/min; the bands above |
| Progression (Resonance) | Depends on | Capture and defence EXP, shared team-wide (C13) |
| Heroes (Sable, Hex, Juniper, Brannoc) | Both directions | Barricade phasing and hacking, deployables at 50%, Hold anchoring |
| HUD & minimap | Is depended on by | Front-line ownership, Contested/Overtime/Locked, Exposed alerts, Incursion reveal |
| Bot AI | Is depended on by | Lane assignment, task behaviours, disconnect takeover |
| Networking | Is depended on by | Server-authoritative ticks, snapshot at 60:00, same-tick ordering |

Each of those GDDs must list this doc back when it is written.

---

## 8. Tuning Knobs

| Knob | Default | Safe range | Affects |
| ---- | ---- | ---- | ---- |
| Hold T_base (Inner/Outer/Mid) | 75/65/60 s | 60–90 (C4) | Front speed; defender advantage |
| Plant T_base (Inner/Outer/Mid) | 80/75/70 s | 60–90 | Same |
| Generator HP (Inner/Outer/Mid) | 6,000/5,000/4,500 | 3,500–8,000 | Breach length; burst-hero value |
| Breach phase 2 hold | 20 s | 10–30 | Breach defender comeback window |
| M(Δ) intercept / slope / cap | 0.4 / 0.24 / 2.0 | 0.2–0.6 / 0.15–0.35 / 1.5–3.0 | How much numbers matter |
| Wardling presence weight | 0.5 | Canon C4 (fixed) | n/a |
| Wardling presence cap per team | none | none–4.0 | Stacking (Vesper) |
| `D_s` Surge I / II | 0.85 / 0.70 | Canon (fixed) | n/a |
| Overtime window (P<0.75 / ≥0.75) | 5 / 10 s | 3–8 / 6–15 | Clutch moments |
| Decay rate (×base) | 0.5 / 1.0 with defender | 0.25–1.0 / 0.5–2.0 | Progress stickiness |
| Severed retake K_sev | 0.75 | 0.6–1.0 | Anti-snowball |
| Stagnation trigger / multiplier | 5:00 / 0.85 | 3–8 min / 0.75–0.95 | Anti-stall |
| Uplink Integrity | 30,000 | 20,000–40,000 (C7) | Siege length |
| Respawn R_0 / k / R_max | 6 / 0.4 / 30 | 4–10 / 0.3–0.5 / 25–35 | Late-game wipe value |
| Barricade Integrity (lane / HQ-facing) | 5,000 / 2,500 | 3,000–8,000 / 1,500–5,000 | Flank value, HQ lock-in |
| Beacon attunement / under-attack radius | 15 s / 25 m | 5–30 s / 15–40 m | Spawn tempo |
| Cell carrier speed | 90% | 80–100% | Plant difficulty |
| Defuse channel | 6 s | 4–8 | Plant defence |
| Capture Lumen (participant / team / defence) | 120 / 40 / 60 | 80–200 / 20–80 / 30–120 | Share of the 9,000 target |
| Starting Lumen | 500 | 400–700 | First buy (Minor + Med-Pack) |
| SD ring start / end radius, Bloom | 45 → 4 m over 90 s, 2%/s +2%/10 s | Over-time fixed (C10); radii 30–60 / 2–8 | Round length |

---

## 9. Acceptance Criteria (vertical slice, Slice Map)

1. Clock-driven transitions fire at 1:00 / 15:00 / 30:00 / 45:00 / 60:00 within ±1 server tick (verified in a log with `clock_scale` 0.25).
2. During Deploy, no player, projectile or damage crosses x = 210, and the Mid zone reports Locked.
3. 1 hero + 3 Wardlings alone on a neutral Mid Hold (60 s) captures in 60 ± 1 s. 2H + 6W captures in 37.5 ± 1 s (M = 1.6).
4. With equal presence, progress stays exactly frozen for 30 s.
5. After the last attacker leaves at P = 0.5, P holds for 5 s, then decays to 0 in 120 s with no defender present (60 s with one).
6. An ineligible team in a zone (no prerequisite held) produces 0 progress, a rejected plant and 0 Generator damage.
7. A Cell carrier moves at 5.4 m/s ±2%, drops the Cell on death, and the Cell returns to the Cradle 15 s later (plus a 10 s Cradle delay after dispersal).
8. A Generator takes no damage from outside its 12 m zone or while defenders out-number attackers in the zone, and regenerates after 8 s idle.
9. On a flip: the new Garrison appears at 10 s, the Barricade becomes solid at 15 s, the Supply Cache switches at 10 s, and a Mid Beacon becomes selectable at 15 s.
10. The Uplink takes 0 damage while not Exposed. It becomes Exposed on the tick an enemy Inner capture completes (and an Outer capture at ≥45:00), and seals on the retake tick.
11. Wardling hits on the Uplink deal 50% of the damage they deal to a hero-equivalent target.
12. Respawn equals F7 to within 0.1 s at deaths sampled at 0, 12, 30 and 60 minutes.
13. A scripted 60:00 snapshot yields the expected Incursion (0–3) and U values, and routes correctly to End or Sudden Death in 3 test fixtures (decisive, U-decided, SD).
14. In Sudden Death: everyone spawns on their own half of the plaza, there are no Wardlings or shop, the ring reaches 4 m at 90 s, and a forced mutual kill within 1.0 s restarts the round.
15. Pulling a client's network mid-match hands its slot to a bot within 10 s with the same hero, level and gear.
16. 20 bot-vs-bot slice matches all reach End, and none exceeds 60:00 plus Sudden Death.

---

## Canon Concerns

| # | Canon item | Concern | What this doc does / recommendation |
| ---- | ---- | ---- | ---- |
| 1 | C8 hard cap 60:00 | A capture at 99% at 60:00 counts for nothing, which feels arbitrary in the most important moment. | Follows Canon: snapshot at 60:00, no overtime. Recommend a match overtime of ≤30 s for tasks already in progress at 60:00. |
| 2 | C10 mutual-kill restart | Unlimited restarts. Two healers can trade indefinitely, and Leyfall Bloom raises the chance of a near-simultaneous death. | Follows Canon. Recommend that after 3 restarts the tie is broken by total remaining team HP %. |
| 3 | Concept § Scope Tiers (Tier 1 = 3-lane map) | The producer asked for a 1-lane Slice Map, which matches Tier 0 rather than Tier 1. This is not a Canon-table item. | Uses the 1-lane Slice Map. The "full match lands in 25–35 min" question can only be answered on the full map, so it moves to Alpha. |
| 4 | C5 Barricade "toward the enemy" | When an enemy holds your Inner, its Barricade blocks your own HQ gate in that lane, and no flank exists near Inners. That is a strong lock-in, against "defender advantage pre-30". | Follows Canon. HQ-gate-facing sockets get half Integrity (2,500) as a tunable value. Recommend Canon state that HQ-facing Barricades are weaker or absent. |
| 5 | C4 Wardlings at 0.5 presence, uncapped | Vesper (7 Wardlings = 3.5) plus a Garrison can make a single hero out-present 3 enemy heroes. | Follows Canon. A cap knob (default none) is exposed in §8 for playtest. |
