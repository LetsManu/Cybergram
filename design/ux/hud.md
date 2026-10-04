# HUD Design: Cybergram

> **Status**: Draft — authored autonomously (`modes.automation: autonomous`) by ux-designer with art-director
> **Author**: ux-designer
> **Last Updated**: 2026-10-02
> **Game**: Cybergram (5v5 first-person objective MOBA shooter)
> **Platform Targets**: PC, keyboard + mouse (primary). Gamepad map defined now so every screen is gamepad-navigable (UI rule); gamepad *gameplay* is not a launch target per the concept doc.
> **Related GDDs**: `design/gdd/game-concept.md` (Canon C1–C18), `match-flow-and-map.md`, `wardlings-and-economy.md`, `weapons-and-mods.md`, `heroes.md`
> **Accessibility Tier**: Standard (target Comprehensive by Launch)
> **Style Reference**: `design/art-bible.md` §4 (colour), §6.3 (task icons), §9 (UI visual direction)
> **Path note**: this file is at `design/ux/hud.md`, the path `design/CLAUDE.md` names. Sibling GDDs that say "HUD / UX (future)" mean this file.
> **Consistency pass 2026-10-02**: squad command input unified with `wardlings-and-economy.md` §8 (Smart Command `Z`, Follow `X`); Ultimate moved to `G`; Ryker's rifle renamed Breakline AR-7; slice scope set to Vesper Loom + Brannoc.

Scope: everything shown while the player controls their hero, plus the in-match overlays that
replace the HUD (tactical map, scoreboard, Armory, skill tree, death/respawn, Sudden Death).
Out-of-match menus (lobby, settings pages) get separate `ux-spec` documents.

---

## 1. HUD Philosophy

Cybergram asks players to aim like a shooter and think like a MOBA commander. The HUD is
therefore split: **the centre belongs to the gun**, the edges belong to the war. The centre 40%
only ever shows the crosshair, hit feedback and short, critical telegraph warnings. The
corners show *me* (bottom-left: HP, level, squad), *my tools* (bottom: skills; bottom-right:
weapon) and *the war* (top: front line, Uplinks, clock; top-left: map; right: objective, kills).

- **Visibility principle: SHOW for state that changes decisions, CONTEXTUAL for everything else.**
  The front line, both Uplinks and the clock are always visible (Pillar 1: the front is the story).
- **Rule of Necessity:** *a HUD element earns its place when it changes where you go, who you
  shoot, or when you spend.* Anything that only reports history (stats, totals) lives on the scoreboard.
- **Pillar 4 echo:** every upgrade the player buys or learns appears on the HUD (mount icons,
  Fork tint, Mastery glyphs, tier pips) *and* on the model (art bible §5, §7).

---

## 2. Information Architecture

| Information | Always | Contextual | On demand | Diegetic echo | Reasoning |
| --- | :-: | :-: | :-: | :-: | --- |
| Crosshair, hit markers | ✓ | | | | Aim is primary (P2) |
| HP, shield, status effects | ✓ | | | | Survival |
| Mana pool / magazine + reserve | ✓ | | | ✓ crystal glow / mag LED | Weapon is the main damage source |
| 4 skills, cooldowns, skill-point badge | ✓ | | | Fork tint on VFX | Core loop |
| Level + Resonance progress, Mastery glyphs | ✓ | | | ✓ level ring over head | Growth (P4) |
| Lumen | ✓ (small) | grows in Armory | | | Spend decisions happen at HQ |
| Squad strip (per-follower HP, command state) | ✓ when squad > 0 | | | ✓ markers, outlines | P3 |
| Front-Line bar (3 lanes × 5 nodes) | ✓ | | | ✓ banners, rings | P1 |
| Uplink Integrity both teams + Exposed | ✓ | | | ✓ spire state | Win condition |
| Match timer + phase + next phase | ✓ | | | ✓ sky/LUT per phase | P5 |
| Vanguard wave timer | | ✓ (last 10 s, and on minimap) | Tactical map | ✓ gate horn | Timing pushes |
| Objective tracker | | ✓ in/near a task, or carrying a Cell | | ✓ task object progress | Local goal |
| Kill feed | | ✓ events, 6 s | Scoreboard | | Awareness |
| Minimap | ✓ | | Tactical map (M) | | Navigation |
| Enemy builds, Forks, K/D/A | | | Scoreboard | ✓ 3P weapon mounts | Reading threats |
| Damage numbers | | ✓ on hit (option) | | | Feedback |

---

## 3. Layout

### 3.1 Full HUD Mock (1920×1080, combat context, Concord player, Mana hero)

```
+------------------------------------------------------------------------------------------------------+
|+--------------+  CONCORD [Uplink 91% ||||||||||||||| ]  23:41 SURGE I  [|||||||||        62%] SYNDICATE |
||  MINIMAP     |          ^ protected              next SURGE II 6:19   EXPOSED (cracked shield)  ^     |
||  240x240     |   N  [#][#][#] | [/][/]      <- FRONT-LINE BAR (own side left)   Vesper ->> Hex    [K]|
||  ^ = you     |   C  [#][#] |(o)[/][/]       (o) = contested node, % ring          Ryker  ->> Picket(Sb)|
||  wave flags  |   S  [#][#][#][#] | [/]      | = front marker                     Sable  ->> Liora   [H]|
|+--------------+                                                                  (kill feed, max 5)  |
| Next wave 0:08 (N C S)                                                                              |
|                                                                        +---------------------------+|
|                                                                        | (o) HOLD  The Spindle     ||
|                                                                        | ##########------  64%     ||
|                                         .   |   .                      | CONTESTED  2 vs 1 (+3W)   ||
|                                             |                          +---------------------------+|
|                                      ------ + ------     crosshair                                  |
|                                             |                                                       |
|                                          .  |  .    hit marker / damage numbers float on target      |
|                                                                                                      |
|                                                                                                      |
| SQUAD  [1 Pk |||| F] [2 Sh |||. F] [3 Pk ||.. >ATK] [4 -- empty (Foundry)]                           |
| +----+ [Burn][Slow]                                                     +--------------------------+ |
| | L7 | HP ||||||||||||||||....  212 / 279  +75 shield                   | HALO REPEATER            | |
| |(ring)                                                                 | MANA ))))))))))))).. 86% | |
| +----+ LUMEN 1,240   RES 62%   [+1 SP]    [Q]  [E]  [C]  [G]   [4]    | [Core][Frame][Chamber]   | |
|                                           4s   --  12s  78%  Med x2   | Ember III  Flux I  Pierce| |
|                                                                         +--------------------------+ |
+------------------------------------------------------------------------------------------------------+
  [#] own team (solid + ring glyph)   [/] enemy (hatched + tooth glyph)   (o) neutral / contested
```

Mechanical variant of the weapon panel: `BREAKLINE AR-7   24 | 120   [Piercing]` with the magazine
number large (48 px), reserve small (24 px), and a 30-tick magazine strip under it.

### 3.2 Zone Table

| Zone | Position (% of 16:9 safe area) | Elements | Max simultaneous |
| --- | --- | --- | --- |
| Top-left | 0–14% W, 0–24% H | Minimap, wave timer | 2 |
| Top-centre | 30–70% W, 0–14% H | Uplinks, clock + phase, Front-Line bar | 3 |
| Top-right | 76–100% W, 0–20% H | Kill feed | 5 entries |
| Right-middle | 76–100% W, 26–42% H | Objective tracker, notification toasts | 2 |
| Centre (40% box) | 30–70% W, 30–70% H | Crosshair, hit markers, damage numbers, threat telegraph arrows, Fork card prompt (only while Alt held), command radial (only while held) | 3 |
| Bottom-left | 0–30% W, 76–100% H | Squad strip, status icons, portrait + level ring, HP, Lumen, Resonance | 6 |
| Bottom-centre | 36–64% W, 86–100% H | 4 skills, SP badge, consumable | 6 |
| Bottom-right | 72–100% W, 82–100% H | Weapon panel (feed, mounts, ammo type) | 3 |

Safe margin: 3% each edge on PC by default (adjustable 0–8%). Ultrawide: HUD clamps to a 16:9
centre region by default ("HUD aspect: 16:9 / native").

---

## 4. Element Specifications

| Element | Data source | Update | Min size @1080p | Colour-free alternative |
| --- | --- | --- | --- | --- |
| Crosshair | Weapon (`weapons-and-mods.md` spread) | Per frame | 24 px | Shape |
| HP / shield | Health system | Per change, 150 ms lerp | 300×14 px bar, 24 px digits | Numbers |
| Status icons | `heroes.md` §3.6 + ammo statuses | Per change | 28 px | Unique glyph + timer ring |
| Weapon panel | Weapon system | Per shot | 48 px digits | Numbers, tick strip |
| Skills | Hero/skill system | 10 Hz | 64 px icons | Radial sweep + seconds |
| Level / Resonance | Progression (C12/C13) | Per gain | 72 px portrait ring | Number |
| Lumen | Economy (C14) | Per gain | 20 px | Number |
| Squad strip | `wardlings-and-economy.md` §8 | 5 Hz | 56 px per slot | Letters F/H/A/C + glyphs |
| Front-Line bar | `match-flow-and-map.md` | Per flip/progress | 22 px node | Solid vs hatched pattern |
| Uplink bars | Match flow (C7) | Per damage, 5 Hz | 260×12 px | % number + EXPOSED text |
| Timer + phase | Match flow | 1 Hz | 28 px | Text |
| Objective tracker | Match flow | 10 Hz | 260 px panel | Task icon shape + % |
| Kill feed | Combat events | Per event | 20 px rows | Hero icons + text |
| Minimap | Match flow + vision | 10 Hz (Wardlings 1 Hz aggregated) | 240 px | Icon shapes |

### 4.1 Crosshair & Centre Feedback
- Hero-specific default (dot+lines for rifles, circle for Ironmaw cone, bracket for the Glitchcaster
  beam with a 15 m range tick). Spread bloom expands the lines. Fully customisable (shape, colour,
  outline, gap, thickness, opacity).
- Core Tier III halo-shot (every 5th shot) flashes a small ring around the crosshair.
- **Threat arrows:** a red-ring arc at the crosshair's edge points to an off-screen ult telegraph
  or a Sable Eclipse Step sting (`heroes.md` §4.2). Max 2 at once, 1.5 s each.

### 4.2 HP, Shield, Status
- Segmented bar (each segment = 50 HP) so big pools (Brannoc 550+) read as "more segments".
  Shield is a white-outlined overlay appended to the right; overheal (Vesper Elite style) is gold-outlined.
- States: Normal (white) → Caution ≤ 50% (bar edge pulses once) → Critical ≤ 25% (vignette at
  screen edges + heartbeat audio; bar flashes 2 Hz unless Reduced Motion) → 0.
- Status icons above the bar, newest left, with a draining ring: Slow, Root, Stun, Silence,
  Knockback, Blind, Reveal (eye — "you are revealed"), Scramble, plus ammo statuses Burn,
  Scorched, Charge (meter fill), Chill (meter fill), Brittle, Disrupted. Hard CC icons have a heavy frame.

### 4.3 Weapon Panel (Mana vs Mechanical)
- **Mana:** a segmented arc bar `))))))` with % number. During `regen_delay` the bar is dimmed and
  a thin clock ring runs; regen then fills it. **Burnout** (pool hit 0) shows the bar grey with a
  crackle icon and "BURNOUT" text until regen starts (`weapons-and-mods.md` §3.5).
- **Mechanical:** magazine large, reserve small, magazine tick strip. ≤ 25% magazine: digits turn
  amber + "R" reload prompt; 0 reserve: reserve shows "0" with a Supply/Armory icon hint.
- **Mount strip:** Core / Barrel / Frame / Chamber icons with tier pips (I–III) and the line's cut-shape
  or chip glyph (art bible §7.2–7.3); Chamber shows the Ammo Type icon and Mod rune. Empty sockets are
  outlined boxes. This is the HUD side of Pillar 4.

### 4.4 Skills, Skill Points, Level
- Four 64 px icons labelled with their current binds: S1 [Q], S2 [E], S3 [C], Ult [G]. Cooldown:
  dark radial sweep + seconds (≤ 3 s shows tenths). Ready: icon brightens, 150 ms pop. Locked
  (unlearned): greyed with a lock. Charges: pip row under the icon.
- Learned Fork tints the icon border (A cool / B warm, `heroes.md` §3.5) and adds a small "A"/"B" letter.
- **Skill-point badge:** `+1 SP` (violet, with count if > 1) next to the skills; every skill that can
  take a point shows a small `+` on its top-right corner. The Ultimate shows its rank pips (1–3)
  and its next level gate (6/10/14).
- **Portrait + level ring:** hero portrait with the level number; the ring fills with Resonance
  progress; Mastery glyphs sit on the ring (one per learned Mastery). Level-up: ring flash + chime.

### 4.5 Lumen & Resonance
`LUMEN 1,240` with a `+120` flyout on gains (captures, kills, Wardlings). The Lumen number pulses
once when the player can afford the next item on their **wish list** (pinned in the Armory).

### 4.6 Squad Strip (C15, `wardlings-and-economy.md` §8)
One 56 px slot per squad slot (3–5; Vesper up to 7), above the HP bar:

```
[1 Pk ||||  F]  [2 Sh |||.  H]  [3 St ||..  A]  [4 Mn |...  C]  [5 -- (Foundry glyph)]
 slot#  variant  HP     state badge                              empty slot
```
- **Variant glyph:** Pk Picket, Sh Shieldling, St Striker, Sk Seeker, Mn Mender, Sp Sapper (icons,
  with the letters as accessibility labels); tier pips 1–3 on the glyph's corner.
- **State badge** (letter + icon, never colour only): `F` Follow, `H` Hold Here, `A` Attack Target,
  `C` Go Capture, `!` in combat, `↻` returning, `S` stranded (same letters as `wardlings-and-economy.md` §8). The whole strip shares one command
  state; per-unit badges differ only for `!`/`↻`.
- Hit flash on a slot when that Wardling takes damage; death = slot greys, X, then the Foundry glyph.
- **Death hold:** when the owner dies, the strip shows a 10 s ring timer, then clears (C15).
- Vesper's **Turned** Wardlings appear as extra violet-ringed icons to the right (no slot, no HP bar);
  **Elite** overlay adds a gold frame to affected slots.
- Notices: "Squad stranded" (amber toast), "Squad dissolved" (on Beacon spawn or recall).

### 4.7 Front-Line Bar (top centre)
Three rows (N / C / S), each with five node chips in lane order, **own side on the left**:

```
N  [#][#][#] | [/][/]      own team holds Inner, Outer, Mid: front is at enemy Outer
C  [#][#] |(o)[/][/]       Mid contested (o) with a progress ring around the chip
S  [#][#][#][#] | [/]      own team holds enemy Outer: enemy Uplink is exposed only if an Inner falls
```
- Chip = task icon (circle Hold / square Plant / triangle Breach, art bible §6.3) on an ownership
  fill: **own = solid + ring glyph; enemy = diagonal hatch + tooth glyph; neutral = hollow.**
- The **front marker** `|` is a bright vertical tick between the two owning teams' segments.
- **Contested** = chip outline animates and a progress ring fills (attacker's colour). **Overtime**
  = ring flashes with "OT" under the chip. **Locked** (C3 prerequisite unmet) = tiny padlock.
- A flip animates the chip (250 ms), moves the front marker and plays a team-specific sting.

### 4.8 Match Header (Uplinks, Timer, Phase)
- Own Uplink left, enemy right: bar + % (absolute value on the tactical map). Permanent damage
  leaves a darker "lost" region so the bar never appears to heal.
- **Exposed:** the bar border becomes hatched and pulses, a cracked-shield icon and the word
  `EXPOSED` appear, and a 1 s VO + sting plays on change (`match-flow-and-map.md` §3.6). From
  45:00 a `DROUGHT` tag sits under the clock to explain why Outer losses now expose.
- Clock `23:41` + phase name (`DEPLOY`, `SKIRMISH`, `SURGE I`, `SURGE II`, `DROUGHT`, `TIME-OUT`,
  `SUDDEN DEATH`) + next phase countdown. Deploy shows "Mids unlock in 0:42".

### 4.9 Objective Tracker (right)
Shows the task the player is in or nearest to (≤ 40 m), or their carried Mana Cell:
task icon + verb (`HOLD` / `PLANT` / `BREACH`), hardpoint name (e.g. "The Spindle", "Signal
Market"), progress bar + %, presence count `2 vs 1 (+3W)` (heroes vs heroes, Wardlings at 0.5),
and state text: `CAPTURING`, `CONTESTED`, `OVERTIME`, `DEFENDING`, `LOCKED`. Breach shows Generator
shield HP, then the 20 s hold. Plant shows "Carry a Mana Cell from <node>" until a Cell is carried;
the carrier sees "YOU ARE CARRYING THE CELL — no mobility skills".

### 4.10 Kill Feed (top right)
Max 5 rows, 6 s each, newest on top. `[killer icon] Name ->> [victim icon] Name`, with assist
pips. Own involvement rows get a light frame. Wardling kills are **not** shown, except the player's
own Elite/Turned events. Hardpoint flips, Exposed and Surges go to the toast lane (§13), not the feed.

---

## 5. Minimap (top-left, 240 px, north-up, own HQ on the left)

| Layer | Icon |
| --- | --- |
| Lanes, flank tunnels, Mid Plaza | Light outlines; flank tunnels dashed |
| Hardpoints | Task-shape icon with ownership fill/hatch; contested = pulsing ring + progress |
| **Front line** | A thick bright bar across each lane between the two teams' furthest nodes |
| Uplinks | Spire icon with Integrity ring; **Exposed = cracked ring + hatched pulse** |
| Self | Arrow with view cone |
| Allied heroes | Chevron with hero icon |
| Enemy heroes | Diamond; only when seen or revealed; last-known position fades over 3 s; Sable only when revealed (`heroes.md`) |
| Own squad | Small numbered dots 1–7 with the command marker (Hold ring tick / Attack line / Go Capture path) |
| Allied squads | Tiny dots (aggregated per owner) |
| **Vanguard waves** | One **pennant/flag icon per wave** with a count (`4`, `3`, …) moving along its lane; enemy waves only when in vision. Aggregated at 1 Hz (`wardlings-and-economy.md` networking) |
| Garrisons | Turret pips (0–2) on the hardpoint icon |
| Mana Cell carrier | Cell icon; enemy carriers pinged every 3 s (`match-flow-and-map.md` §3.4) |
| Forward Beacons | Banner icon; under attack = strobing |
| Pings | Ping-type icon, 4 s |

Vanguard (flag), personal squads (dots) and Garrisons (turret pips) use three different shapes so
ownerless AI never reads as a player's squad. Scramble (Hex) replaces the minimap with static
noise for its duration; it never touches HP, ammo or crosshair (`heroes.md` §3.6).

## 6. Tactical Map (full screen, hold/toggle `M`)

The world stays live behind a 75%-dark overlay; the player can still move (not shoot).
Everything from the minimap, larger, plus:
- **Lane panel** per lane: ownership of all 5 nodes, task types, current progress, Locked status,
  and **Incursion preview** (0–3) with the team total (C9) — "if time ran out now".
- **Uplink panel:** Integrity absolute (`30,412 / 33,000`), Exposed state and **why**: "EXPOSED —
  Syndicate holds Concord Atrium (C-AI)". From 45:00: "Drought: any Outer loss exposes".
- **Wave panel:** per lane, own wave status (`en route`, `at Signal Market`, `3 alive`) and next wave
  timer, or `waiting — previous wave alive` (C15 one-live-wave rule).
- Next Surge / Drought timer and what it does ("Wardlings → Tier II, tasks −15%").
- Legend (toggle with `L`), always accessible for colour-blind users.
- **No commands are issued from the map** (Pillar 3: no top-down control; decided in the consistency pass, R10). Go Capture is issued in
  first person (§7); the map only shows its target and path.

---

## 7. Squad Commands — Smart Command, Follow, Radial (C15, 4 commands)

The binding source for command input is `wardlings-and-economy.md` §8; this table mirrors it.

| Command | Effect (C15) | KB/M (default) | Gamepad |
| --- | --- | --- | --- |
| **Smart Command** | Context-sensitive, resolved from the crosshair: enemy → **Attack Target**; hardpoint zone or its diamond → **Go Capture**; ground → **Hold Here** (≤ 25 m, else own feet) | Tap `Z` | Tap D-pad ↓ |
| **Follow** (default) | Squad returns to formation | `X` | Double-tap D-pad ↓ |
| **Radial** (all four) | Explicit choice of any command | Hold `Z` ≥ 0.2 s | Hold D-pad ↓ ≥ 0.2 s |
| **Direct keys** (optional) | One action per command: Attack Target, Go Capture, Hold Here, Follow | Unbound by default (suggested: mouse thumb buttons) | Unbound by default |

While `Z` is down the crosshair shows the **command preview glyph** (sword = Attack, flag = Go Capture,
pin = Hold) so the Smart Command result is never ambiguous. On gamepad a D-pad ↓ tap is resolved
after the double-tap window (default 0.3 s) so it can be told apart from Follow; the target is
captured at the first press. **No command can be issued from the tactical map** (Pillar 3).

**Radial wheel:** four 90° slices (Follow top, Hold Here right, Attack Target bottom, Go Capture left), 220 px,
centred on the crosshair, 40% panel opacity so aim stays visible. The command's target is captured
**when the wheel opens** (the point/entity/hardpoint under the crosshair), and is previewed in the
world (ghost ring, target diamond, or hardpoint highlight). Select by mouse flick / right stick,
issue on release; releasing in the dead-zone cancels. Time does not slow; firing stays allowed
(the wheel does not block LMB). Invalid slices are greyed with a reason ("No target", "Locked
hardpoint") — Go Capture to a Locked node is rejected with a buzz.

**Feedback per order:** 40 ms acknowledgement chirp (one per command, distinct pitch); squad strip
badge flashes; world marker appears (art bible §5.5: Hold ring + anchor, Attack diamond + threads,
Go Capture ping column + path ribbon). Allies see the markers at 50% and a minimap tick.

---

## 8. Scoreboard (hold `Tab`)

Own team on top, enemy below; centre overlay, 85% dark background, HUD hidden except crosshair.

```
 CONCORD   Incursion now: 4    Uplink 91%                 23:41  SURGE I
 Hero        Lvl  Forks     K / D / A  Wardl  Caps  Build (Core/Barrel/Frame/Chamber)     Squad  Status
 Ryker       9 ** A B - -   7 / 3 / 5    22     3   [Ovc III][Rif I ][Gyro I][Pierce]       4/4   alive
 Liora       8 *  B A - -   1 / 2 / 11    9     2   [Well II][  --  ][Flux II][Siphon]      3/3   12s
 ...
 SYNDICATE Incursion now: 2    Uplink 62% EXPOSED
 Sable       9 *  A - B -   8 / 4 / 2    11     1   [Tmp II][Velo I][  --  ][Cryo]            -   alive
```
- `*` = Mastery glyphs; Forks show A/B per skill (`heroes.md` §3.5: scoreboard shows every hero's Forks).
- **Build icons for both teams** (`weapons-and-mods.md` §3.6.3). Enemy **Lumen is hidden**; own team's Lumen is shown.
- Bot-controlled slots show a bot icon (C1). Latency and mute buttons on the right.
- Right-hand side panel: **own skill tree** (§11) so points can be spent while checking the board.
- Gamepad: hold View; RB/LB cycle panels.

---

## 9. Death & Respawn Screen

```
+------------------------------------------------------------------------------------------+
| KILLED BY  [Sable]  Whisperfang  [Tmp II][Velo I][--][Cryo]   Sable HP left: 84 / 225    |
| Damage taken: Whisperfang 261 (9 hits, 2 heads, Eclipse bonus)  Picket 18                |
|                                                                                          |
|   RESPAWN IN 14s                                  +-----------------------------------+  |
|                                                   |  TACTICAL MAP (spawn select)      |  |
|   ( ) SANCTUM — squad of 4 + Armory               |   [Sanctum]   * N-MID Beacon       |  |
|        travel to front ~35 s                      |               x C-MID (under atk)  |  |
|   (*) BELFRY RUIN BEACON — no squad, no shop      |                                   |  |
|        travel to front ~11 s                      +-----------------------------------+  |
|                                                                                          |
|   Your squad holds position: (ring) 7s           [Skill tree  K]   [Spectate ally  Space] |
+------------------------------------------------------------------------------------------+
```
- **Death recap:** killer, their weapon **build icons** (teaching the Pillar 4 read), killer HP remaining,
  damage breakdown by source. Plays for ≥ 3 s; a 1.5 s killcam is optional (Alpha).
- **Respawn timer** per C11 (`min(30, 6 + 0.4 × minutes)`), large.
- **Spawn selection:** Sanctum is always available and shows what you get (squad size, Armory). Each
  held Forward Beacon is listed with travel estimate; "under attack" Beacons are greyed with a reason.
  Default = last choice. If the chosen Beacon becomes under attack during the countdown, the
  selection falls back to Sanctum with a notice; the timer is not reset (`match-flow-and-map.md` §6).
- Select by clicking the list or the map icon, or `1`/`2`/`3`; gamepad D-pad + A.
- Skill points may be spent here (C12: anytime). The Armory is **not** available (HQ only, C14).

---

## 10. Armory Shop UI (and Foundry kiosk)

Opened with `F` at the Armory counter (only inside your HQ Armory zone, while alive). The world
keeps running: the panel takes the left 60% of the screen, the right 40% stays live, and an alert
strip shows "Uplink under attack" / "Enemy in HQ" if relevant. Moving out of the zone closes it.

```
+-- ARMORY ----------------------------------------------- LUMEN 2,140 ---- [Wish list ★] --+
| [Core] [Barrel] [Frame] [Chamber] [Squad] [Consumables]                                    |
|  +----------------------------+   +-----------------------------------------------------+  |
|  | Ember Heart      I  400    |   |            3D TURNTABLE  (your Halo Repeater)       |  |
|  |  Damage +6/11/16%   II 900 |   |       [Frame]--o====[CORE: empty]====o--[Barrel]    |  |
|  |                    III1800 |   |   socket under the cursor glows; drag or press A    |  |
|  | Tempest Shard  ...         |   |   preview: crystal flies in, claws clamp, test shot |  |
|  | Prism Eye      ...         |   +-----------------------------------------------------+  |
|  | Wellspring     ...         |   DPS 95 -> 101 (+6%)   TTK vs 250 HP 2.63 -> 2.48 s        |
|  +----------------------------+   [BUY 400]  [Upgrade to II: 500]  [Sell 240]  [Undo]       |
+--------------------------------------------------------------------------------------------+
```
- **Tabs = sockets** (Core, Barrel, Frame, Chamber: Ammo Type + Mod), then Squad (licences shown
  for reference, upgrades: Expansion, Reinforced Cores, …) and Consumables (Med-Pack). Wrong-family
  or restricted lines are greyed with the reason (`weapons-and-mods.md` §3.6.4 rule 2).
- **Turntable:** a `SubViewport` showing the player's actual gun with all sockets labelled. Hovering an
  item highlights its socket and previews the mesh in place (ghosted); buying plays the art bible §7.2
  socketing animation and one test shot with the new muzzle flash. Gamepad: rotate with RS.
- **Prices:** buy shows list price; owning a lower tier shows **"Upgrade to III: 900"** (cost =
  `list(new) − list(held)`). Swapping lines shows the auto-sell amount first: "Replaces Flux Coil I
  (sells for 210)". **Undo** = 100% refund during the same visit; later sells show 60%.
- **Stat delta** for the hovered item, in plain numbers (DPS, TTK vs a 250 HP hero, pool/magazine).
- **Wish list:** star items anywhere (also from the death screen); the HUD Lumen pulses when the next
  one is affordable, and a one-click "Buy wish list" button appears on entry.
- **Foundry kiosk** (`F` at the Foundry): same shell, Squad tab only, showing slots, licences, and
  which slots the Foundry will re-mint.
- Keyboard: arrow keys/WASD navigate, Enter buy, Backspace sell, Ctrl+Z undo, Esc close.

---

## 11. Skill Tree & In-Match Fork Choice

Each basic skill is a vertical 4-node column: **Unlock → Boost (L3) → Fork A | B (L5) → Mastery (L9)**;
the Ultimate is a 3-rank column with gates 6 / 10 / 14 (C12, `heroes.md` §3.5).

**Quick spend (no screen, keeps aim):** hold `Alt` → a compact flyout appears above the skill bar
showing each skill's next node; press the skill key (`Q`/`E`/`C`/`G`) to buy it. When the next node
is a **Fork**, two cards pop up above that skill (`[1] Pounce — Wardlings leap…` / `[2] Puppet String — …`)
with a one-line effect and a 3-second animated preview; press `1` or `2` (or click). Releasing Alt
cancels. The choice is permanent for the match, so a Fork pick needs the explicit 1/2 press (no
accidental double-tap). Gamepad: hold View → RB/LB/Y/LB+RB select the skill → D-pad ←/→ + A for Forks.

**Full tree** (`K`, also on the scoreboard and death screen): all four columns, node text, level
gates, current numbers, and the Fork tint each choice will give.

**Options:** "Auto-spend skill points" (follows a recommended build, but always stops at Forks unless
"Auto-pick Forks" is also on); "Remind me" toast if a point stays unspent for 30 s outside combat.

---

## 12. Time-Out, Incursion and Sudden Death

| Moment | Presentation |
| --- | --- |
| **60:00 Capture Overtime** (≤ 30 s, C8) | Only if a task is in progress: banner `MANA RESERVES DEPLETED — CAPTURE OVERTIME`; the clock counts `OT 0:30` down; in-progress nodes pulse on the Front-Line bar, all other chips show a padlock. |
| **Time-out** (5 s freeze) | Screen desaturates 50%; banner `MANA RESERVES DEPLETED`; the clock shows `TIME-OUT`; all Uplink beams flicker out. |
| **Incursion reveal** (10 s) | Full-screen panel: each lane's score animates in (0–3) with its node strip, then team totals; if tied, Uplink damage % for both. Result: `CONCORD WINS ON INCURSION` or `TIED — SUDDEN DEATH`. |
| **SD-Freeze** (5 s) | Banner `SUDDEN DEATH — ROUND 1` + one-line rule ("No respawns. Last team standing wins."). Everyone at the Mid Plaza spawn pads. |
| **SD-Round HUD** | Front-Line bar, objective tracker, Lumen, squad strip and wave timer are **hidden**. Top centre shows **alive pips** per team `CONCORD ●●●●○  vs  ●●○○○ SYNDICATE` (filled = alive, hollow = dead; shape + count, not colour) and the **ring timer** `Ring 0:47 → 4 m`. Minimap zooms to the plaza with the Leyfall ring drawn. |
| **Ring** | Outside the ring: violet edge vignette + damage tick sound + "OUTSIDE RING −8%/s". After 90 s: `LEYFALL BLOOM` warning and a rising damage number under the ring timer. |
| **SD-Confirm** (1.0 s) | When a team's last fighter dies: centre text `CONFIRMING…` with a 1 s bar. |
| **Mutual kill** | `TRADE! — ROUND RESTARTS` banner, round counter +1, back to SD-Freeze. After the 3rd restart the banner reads `FINAL ROUND — HIGHER TEAM HP WINS AT RING CLOSE`, and the alive pips gain a summed-HP% number per team (C10). |
| **End** | `VICTORY` / `DEFEAT` (also spoken), the enemy Uplink goes dark on screen, then stats. |

---

## 13. Feedback & Notifications

### 13.1 Hit Markers
| Event | Marker | Sound |
| --- | --- | --- |
| Hero body hit | White X, 120 ms | Soft tick |
| Headshot | Larger yellow X with a notch at the top | Bright "crack" |
| Shield / Aegis Wall hit | Bracket marks `[ ]` | Glassy tink |
| Armour-heavy hit (> 30% reduced) | X with a small plate icon | Dull clank |
| Wardling / Sentinel hit | Small dim dot | Quiet tick (half volume) |
| Structure / Uplink hit | Hexagon outline | Low thud |
| Kill (hero) | X expands into a diamond burst | Kill chime (distinct for assist) |

### 13.2 Damage Numbers — **Yes**, default **Compact**
Options: Off / Compact / Full. Compact: one number per target that **merges** hits within 0.5 s and
floats 0.6 m above the target; white for body, yellow + `!` for headshots, grey for armour-reduced,
green `+` for heals (Liora/Mender). Full: per-hit numbers. Wardling damage numbers are off by default.
Rationale: MOBA build decisions (Armory stat deltas, Piercing vs armour) need visible numbers; Compact
keeps the centre clean.

### 13.3 Incoming-Damage and Threat Feedback
Directional damage arcs at screen edge (white core, attacker's team-colour rim, thickness = damage),
1.0 s. Low HP vignette and heartbeat. Being Revealed: eye icon + "REVEALED" for its duration.
Status-effect screen treatments follow `heroes.md` (Blind white-out clears from the centre first).

### 13.4 Audio Cues (owned by audio-director; these are HUD requirements)
| Cue | When |
| --- | --- |
| Hardpoint flip (own gain / own loss: different stings + VO) | Any flip; lane named in VO ("North Outer lost") |
| `Uplink Exposed` / `Uplink sealed` | Exposure change, both teams (1 s VO) |
| Uplink under fire (own) | Repeats every 10 s while taking damage |
| Vanguard horn | Own wave leaves the gates (every 60 s) |
| Surge / Drought | Phase transitions |
| Squad: order chirps ×4, Wardling lost blip, "Squad stranded" | Squad events |
| Level up, skill point ready, Lumen gain (soft) | Progression |
| Low ammo tick (shooter only), Burnout crackle (15 m) | Weapon (`weapons-and-mods.md`) |
| Ult wind-up stings, Eclipse Step whisper | Enemy abilities (`heroes.md`) |

Every VO callout also appears as a caption (subtitles ON by default) and every critical cue has a
HUD equivalent, so no information is audio-only.

### 13.5 Toast Lane (right side, under the objective tracker)
Max 3 toasts, 3 s each. Priority: **Critical** (Exposed, Uplink under fire, Sudden Death) bypasses the
queue → **High** (own-lane flips, Beacon fallback, squad stranded) → **Normal** (other flips, Surge,
level up) → **Low** (Lumen bonuses, tips; held while in combat). Same-type toasts within 500 ms merge.

---

## 14. HUD States by Context

| Context | Shown | Hidden / modified |
| --- | --- | --- |
| Deploy | All + "Mids unlock in" countdown | Objective tracker until near a task |
| Combat | All | Low toasts queued |
| Carrying Mana Cell | Tracker shows carrier text; mobility skill icons greyed | — |
| Command radial open | Radial + crosshair | Damage numbers dimmed |
| Armory / Foundry open | Shop panel, HP, Uplinks, clock, alerts | Skills, squad strip, kill feed |
| Tactical map / Scoreboard | Overlay | Gameplay HUD except HP and crosshair |
| Scrambled (Hex) | HP, ammo, crosshair, skills (icons only) | Minimap, enemy outlines, cooldown numbers (`heroes.md`) |
| Dead | Death & respawn screen | All gameplay HUD |
| Time-out / Incursion | Reveal panels | All gameplay HUD |
| Sudden Death | §12 SD HUD | Front-Line bar, Lumen, squad, tracker, wave timer |

---

## 15. Visual Budget

| Constraint | Limit |
| --- | --- |
| HUD area, non-combat / combat | ≤ 12% / ≤ 18% of screen |
| Centre 40% box occupancy | ≤ 5% (crosshair, markers, numbers) except while radial or Fork cards are held open |
| Text contrast | ≥ 4.5:1 against the brightest and darkest lane screenshots |
| Panel opacity | ≤ 65% (`#0B0E18`) |
| Min sizes @720p | 32 px icons, 16 px text; @1080p 40 px / 18 px |
| Simultaneous animated elements | ≤ 4 |

---

## 16. Accessibility

- **Colour:** team colour is never the only cue (art bible §4.4): ownership uses solid vs hatched +
  glyphs; enemies use diamonds, allies chevrons; tiers use pips; states use letters. Presets:
  Deuteranopia, Protanopia, Tritanopia; **Relative team colours** (ally blue / enemy red); **enemy
  highlight** Default / Yellow / Magenta; crosshair colour free.
- **Text & scale:** text scale 75–150% (all panels reflow; kill feed truncates names, never icons);
  HUD scale 80–120%; per-element opacity; safe margin 0–8%.
- **Motion:** Reduced Motion removes pulses, flashes (2 Hz HP flash → static red frame), screen
  shake, chip-flip animations and the Armory flight animation (snaps in). No element flashes > 3 Hz.
- **Audio:** subtitles + VO captions ON by default (speaker name + team glyph); optional **visual sound
  indicators** for footsteps, reloads and ult stings within 20 m.
- **Input:** full remapping (KB/M and gamepad separately), every hold action has a toggle option
  (ADS, crouch, sprint, scoreboard, map, radial = "tap to open, click to select"), adjustable
  double-tap window (150–500 ms, default 300) for gamepad Follow, and optional direct keys for each
  squad command (unbound by default).
- **Screen reader:** menus and the Armory expose names/values through Godot's AccessKit support (4.5+, verify for 4.7).
- **Cognitive:** tactical map legend always available; Auto-spend skill points; Armory "recommended" tag.

---

## 17. Input Map

| Action | KB/M (default) | Gamepad (Xbox / PS) |
| --- | --- | --- |
| Move / Look | WASD / Mouse | LS / RS |
| Jump / Crouch-slide / Sprint | Space / Ctrl / Shift | A ✕ / B ○ / L3 |
| Fire / ADS-alt fire | LMB / RMB | RT / LT |
| Reload (Mech) | R | X □ (tap) |
| Interact (Plant, pick up Cell, Armory, Foundry kiosk) | F | X □ (hold) |
| Melee | V | R3 |
| Skill 1 / 2 / 3 / Ultimate | Q / E / C / G | RB / LB / Y △ / LB+RB |
| Spend skill point | Alt + skill key; Forks: 1 / 2 | Hold View + skill button; D-pad ←/→ + A |
| Squad: Smart Command (Attack / Go Capture / Hold Here by context) | Z tap | D-pad ↓ tap |
| Squad: radial wheel (all four) | Z hold | D-pad ↓ hold |
| Squad: Follow | X | D-pad ↓ double-tap |
| Squad: direct Attack / Capture / Hold / Follow keys | unbound (optional) | unbound (optional) |
| Med-Pack | 4 | D-pad ← |
| Recall to HQ | B (channelled) | Ping wheel → Recall |
| Ping / ping wheel | MMB tap / MMB hold | D-pad ↑ tap / hold |
| Scoreboard / Tactical map / Skill tree | Tab (hold) / M / K | View hold / View tap / via scoreboard |
| Chat team / all | Enter / Shift+Enter | — (quick-chat via ping wheel) |
| Pause / settings | Esc | Menu |

Squad bindings follow `wardlings-and-economy.md` §8 (the binding source). Mouse thumb buttons are
suggested for the optional direct Attack Target / Go Capture keys in the onboarding prompt.

---

## 18. Tuning Knobs

| Parameter | Default | Range | Affects |
| --- | --- | --- | --- |
| Radial open delay | 0.2 s | 0.12–0.35 | Tap vs hold on Z |
| Double-tap window | 0.3 s | 0.15–0.5 (player) | Gamepad Follow vs Smart Command |
| Kill feed duration / rows | 6 s / 5 | 4–10 / 3–7 | Clutter |
| Damage number merge window | 0.5 s | 0.2–1.0 | Readability |
| Objective tracker range | 40 m | 20–80 | When it appears |
| Wave timer visibility | last 10 s | 0–60 | Push timing |
| Enemy last-known fade | 3 s | 1–6 | Map info |
| Low-HP threshold | 25% | 15–35 | Urgency |

---

## 19. Vertical-Slice HUD Subset (M1, Slice Map "Shardline Causeway", Vesper Loom + Brannoc)

**In:** crosshair + hit markers (body/head/kill/Wardling/structure); damage numbers Compact/Off;
HP + shield + status icons for the 2 slice heroes' effects (Vesper, Brannoc); weapon panel (mana arc with Burnout,
magazine + reserve); mount strip for Core / Frame / Chamber only; 4 skills + SP badge + Alt quick
spend (reduced tree: Unlock, Boost, ult ranks; no Fork cards or Mastery glyphs until M3); level ring + Resonance + Lumen; squad strip (Pickets only; badges F/H/A/C/!/↻/S);
**all 4 squad commands (Smart Command, Follow, radial)** and world markers; Vesper's Turned/Elite strip icons; Front-Line bar with **one lane**;
Uplink bars + Exposed; clock + phase; objective tracker for Hold/Plant/Breach; kill feed; minimap
(incl. Vanguard flags); simplified tactical map (one lane, Incursion 0–3); scoreboard (no build icons,
per `weapons-and-mods.md` §3.10); death screen with Sanctum/Beacon choice; Armory with turntable
(greybox mounts); 30:00 slice Time-out → Incursion (a tie is a draw; Capture Overtime and Sudden Death HUD arrive in M3); colour-blind presets, text scale,
full KB/M remapping, subtitles.

**Out (Alpha):** scoreboard build icons, killcam, wish list, visual sound indicators, Scramble HUD
treatment (Hex not in slice), variant glyphs, HUD layout editor, gamepad gameplay map (menus still navigable).

---

## 20. Acceptance Criteria

1. In a greyscale screenshot, a tester identifies ownership of every Front-Line chip and the front
   marker position for each lane (pattern + glyph only).
2. Issuing each of the 4 squad commands by Smart Command (`Z` tap on enemy / hardpoint / ground), Follow (`X`) and by radial updates the strip badge within
   100 ms, shows the correct world marker, and plays a distinct chirp; Go Capture on a Locked node is rejected with a reason.
3. Personal squads, Vanguard waves and Garrisons are distinguishable on the minimap by shape alone.
4. The Exposed state appears on the header, minimap and tactical map within 1 server tick of the
   change, with the reason on the tactical map.
5. Buying a mount in the Armory updates the turntable, the HUD mount strip and the FP weapon in the same frame.
6. A Fork can never be learned without an explicit 1/2 (or A) confirmation.
7. At 150% text scale and 1280×720, no HUD text overflows or overlaps.
8. Reduced Motion removes every animation listed in §16; no element flashes faster than 3 Hz.
9. Scramble hides the minimap, enemy outlines and cooldown numbers but never HP, ammo or crosshair.
10. The SD-Round HUD shows alive counts and ring timer, and hides the Front-Line bar, squad and Lumen.
11. All interactive screens (Armory, skill tree, spawn select, scoreboard) are fully usable with keyboard only and with gamepad only.

---

## 21. Open Questions

| # | Question | Decision taken (pending owner) |
| --- | --- | --- |
| U1 | Damage numbers default | Compact ON; Off available |
| U2 | Front-Line bar and minimap orientation | Own side on the left for both teams (option: absolute, Concord left) |
| U3 | ~~Command input differs between this doc and `wardlings-and-economy.md`~~ | Resolved in consistency pass 2026-10-02: unified scheme (Z tap Smart Command, Z hold radial, X Follow, optional direct keys); wardlings §8 is the binding source |
| U4 | ~~Should Go Capture also be issuable from the tactical map?~~ | Resolved in consistency pass 2026-10-02: no (Pillar 3) |
| U5 | ~~Ryker's rifle "Vanguard AR-7" collides with "Vanguard waves"~~ | Resolved in consistency pass 2026-10-02: renamed **Breakline AR-7**; UI uses "Vanguard" only for waves |
| U6 | ~~HUD file path~~ | Resolved: `design/ux/hud.md` matches `design/CLAUDE.md` |
| U7 | Ultimate key moved from `X` to `G` because `X` is now Follow | Default `G`; fully rebindable. Revisit at the M1 playtest |

**Slice implementation notes (P1):** the shop is a full-screen panel (tabs, search, cards, detail pane, recommended build from `assets/data/economy/recommended_builds_slice.tres`). Opens with F or `open_shop` (default B) on the pad; off the pad B shows "Return to your Armory pad to buy". Sell and undo are the same server action (ACTION_SELL by socket): 100% back for a line bought entirely this visit ("Undo", Ctrl+Z), 60% rounded down to 5 otherwise ("Sell"); Squad upgrades and Med-Packs cannot be sold (no GDD rule). No turntable, wish list or Barrel tab in the slice.
