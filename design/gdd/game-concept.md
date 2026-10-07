# Game Concept: Cybergram

*Created: 2026-10-02*
*Status: Draft — authored autonomously by creative-director (modes.automation: autonomous). Decisions are recorded in "Open Questions for the Owner".*
*Source of intent: `/ideas` (owner notes). Where this doc and `/ideas` disagree, this doc reflects a deliberate decision listed below.*

---

## Elevator Pitch

> **Cybergram is a first-person team shooter played like a MOBA: two teams of five heroes fight across three war-front lanes, completing tasks at hardpoints to push the front toward the enemy HQ, each player leading a small squad of loyal AI constructs, until one team shuts down the other's Mana Uplink — the tower that lets their people wield magic at all.**

10-second version: *"Overwatch guns, Dota map, and you bring your own minions."*

---

## Core Identity

| Aspect | Detail |
| ---- | ---- |
| **Genre** | First-person hero shooter × lane MOBA (objective-front PvP) |
| **Platform** | PC first (keyboard + mouse). Controller/console is not a target before launch. |
| **Engine** | Godot 4.7, GDScript, Forward+, Jolt physics |
| **Player Count** | 5v5 online PvP; bots fill any empty slot. Later: co-op 5 humans vs. 5 bots. |
| **Session Length** | One match: target **25–35 min**, hard cap 60 min (+ ≤30 s capture overtime, + sudden death) |
| **Art** | 3D stylized anime/cartoon (cel-shaded), futuristic fantasy |
| **Monetization** | Undecided; anything sold is cosmetic only (see Anti-Pillars) |
| **Comparable Titles** | Paragon / Predecessor, Overwatch, Deadlock, Battlefield Conquest/Breakthrough |

---

## The World (fiction)

| Element | Canon |
| ---- | ---- |
| **World** | **Halcyra** — a sky-continent of floating city-shards over a sea of raw mana, the *Leyfall*. Neon arcologies grown around ancient crystal ruins. |
| **The Cybergram** | The encoded mana signal broadcast by an Uplink. Ordinary humans cannot touch mana; anyone *attuned* to a Cybergram can — to shoot it, shape it, and power their machines with it. The game is named after this signal. |
| **Mana Uplink** | A crystal-and-steel broadcast spire at the heart of each HQ that transmits its faction's Cybergram. If it is silenced, every fighter of that faction loses mana — their guns, gadgets and constructs die with it — and the faction loses the battle. Each Uplink draws from a finite **Mana Reserve**; in-fiction this is why a battle cannot last more than 60 minutes. |
| **Faction A** | **The Azure Concord** (blue/white/gold) — an alliance of spire-cities that treat mana as civic infrastructure. Clean lines, holo-glyphs, crystal lattices. |
| **Faction B** | **The Ember Syndicate** (red/orange/black) — salvage-guild federation of the lower shards that runs mana through rebuilt war-tech. Riveted plating, glowing furnace cores. |
| **Faction rule** | Factions are **cosmetic sides** (team colour, HQ dressing, VO). All heroes are available to both; gameplay is mirrored. |
| **Wardlings** | Small mana-constructs (the "mobs") minted at each HQ's **Foundry**. Bound to one fighter, they follow and protect them. |

---

## Core Fantasy

You are a gifted fighter of a world where magic is a broadcast — a gunslinger, a ninja, a puppeteer — dropping onto a living front line with a squad of little constructs at your heels. Every skirmish you win moves the war a few metres. Over thirty minutes you watch your gun sprout crystals, your squad grow teeth, and the front line on the map crawl toward the enemy's spire — until you are the one standing in their HQ as their Cybergram goes dark.

---

## Unique Hook

**"It's a lane MOBA in first person, AND ALSO every player carries their own minions."** The AI army is mostly what players bring — small objective-driven Vanguard waves keep empty lanes alive, but the squad at your heels is the star. Where you take your Wardlings, how you spend them (escort, garrison, sacrifice), and whether you respawn at HQ *with* them or at the front *without* them is the strategic layer — expressed through a first-person shooter's hands.

Secondary hook: hardpoints are **tasks** (hold, plant, breach), not just capture circles, and the front line is the score.

---

## Game Pillars

### Pillar 1 — The Front Is the Story
The state of the match is *where the front lines are*, and it is always visible on the map, the HUD and the world itself.
*Design test:* if a mechanic rewards kills without ever helping to move or hold a front, it loses to a mechanic that ties the reward to hardpoints.

### Pillar 2 — Shooter Hands, MOBA Head
Aiming, movement and gun feel are first-class and decide fights; MOBA depth (levels, skills, builds, roles) layers on top and never replaces aim.
*Design test:* damage abilities must be aimed or placed; no point-and-click lock-on damage. (Support effects such as heals may use soft-targeting.)
*Explicit exemption:* designating a target for your Wardlings with **Attack Target** is not hero lock-on damage, because Wardling shots are slow, dodgeable projectiles, need line of sight, and the order times out after 12 s (C15).

### Pillar 3 — Your Squad at Your Heels
Every player is a small commander. Wardlings are readable, defensive by nature, and a resource you choose how to spend. Commands stay at the "one key" level: one context-sensitive Smart Command key plus a Follow key (C15).
*Design test:* if a Wardling feature needs more than four squad commands or a top-down view, cut it.

### Pillar 4 — Power You Can See
In-match growth is visible: crystals and chips mounted on the gun, gear worn on the hero's body (six open item slots), Wardling tiers, hero level glyphs, hardpoint ownership on the map. *(Revised 2026-10-07, owner: Armory v2, `items-and-armory.md`.)*
*Design test:* an upgrade with no visible tell on the model or HUD either gets one or gets cut.

### Pillar 5 — Every Match Ends
Matches resolve decisively, typically in 25–35 min. Comebacks must exist; stalemates must not.
*Design test:* after minute 30, when defender advantage conflicts with tempo, choose tempo.

### Anti-Pillars (what Cybergram is NOT)

- **NOT pay-to-win or persistent power.** Everything bought with match currency resets each match; meta progression is cosmetic/unlock-only. Persistent power breaks PvP trust.
- **NOT a last-hit farming game.** No last-hitting minigame and no endless creep streams; Vanguard waves are small, capped, and go to objectives. Kill rewards are shared by proximity, so income comes from fighting over the front.
- **NOT an RTS.** No unit micro, no top-down control, no build orders for Wardlings.
- **NOT an ability-spam game with guns as decoration.** Weapons are the primary damage source for every hero.
- **NOT a battle royale, extraction or open-world game.** One authored arena, fixed teams, fixed objectives.
- **NOT a PvE campaign.** The `/ideas` heading "MAYBE PvE Shooter" is resolved: PvP first; co-op vs. bots is a later mode using the same rules.

---

## Target Audience

| Attribute | Detail |
| ---- | ---- |
| **Age** | 16–30 |
| **Experience** | Mid-core to core PC players |
| **Currently plays** | Overwatch 2, Valorant/Apex, League/Dota (or ex-MOBA players), Deadlock, Predecessor |
| **Looking for** | MOBA strategy and growth without top-down click play; a hero shooter with a longer arc than a 10-min payload round |
| **Time** | 30–40 min evening sessions (one match + queue) |
| **Turn-offs** | 60-min stomps with no way back, pay-to-win, unreadable visual noise, toxic dependence on one teammate |
| **Bartle** | Killers/competitors (primary), achievers (in-match growth), socializers (team roles) |

---

## Core Loop

### Moment-to-moment (≈30 s)
Move, shoot, manage ammo (mana recharge vs. magazines), use 4 skills on cooldown, position your Wardlings, contest a hardpoint task. Win the local fight → the task progresses.

### Per-life (≈2–4 min)
1. **Spawn** — choose: **HQ** (pick up your Wardling squad at the Foundry, shop at the Armory) or a **Forward Beacon** (held Mid hardpoint: faster to the front, no squad, no shop).
2. **Travel & push** — escort squad to a lane, join a hardpoint task (attack or defend).
3. **Earn** — Lumen and Resonance from enemy Wardlings, kills/assists, task completion.
4. **Spend** — skill point on level-up (anytime); Lumen only at HQ (crystals, chips, ammo types, squad upgrades).
5. **Die or recall** — lose your current squad; respawn timer; loop.

### Per-match (25–35 min typical)
Mid hardpoints contested → outer hardpoints swing → one lane breaks → an Inner hardpoint falls → enemy Uplink exposed → push on the Uplink, or defenders retake and reset the exposure. Time-based **Surges** escalate stakes so the front moves faster as the match ages.

### Long-term (across matches)
Hero mastery, account level and cosmetic unlocks (skins, Wardling skins, crystal VFX colours). No stat progression. Ranked play is a launch-tier feature.

---

## Match Structure Overview

```
 Concord HQ                                                Syndicate HQ
 [Uplink]  A-Inner — A-Outer — MID — B-Outer — B-Inner  [Uplink]   ← Lane 1 (North)
 [Foundry] A-Inner — A-Outer — MID — B-Outer — B-Inner  [Foundry]  ← Lane 2 (Center)
 [Armory]  A-Inner — A-Outer — MID — B-Outer — B-Inner  [Armory]   ← Lane 3 (South)
           flank paths connect lanes between Outer and Mid rows
```

| Phase | Time | What changes |
| ---- | ---- | ---- |
| **Deploy** | 0:00–1:00 | Teams spawn, buy, pick up squads. Mid hardpoints locked (countdown). |
| **Skirmish** | 1:00–15:00 | Mid hardpoints unlock; Tier I Wardlings. |
| **Surge I** | 15:00 | Wardlings & garrisons → Tier II; task durations −15%. |
| **Surge II** | 30:00 | Wardlings & garrisons → Tier III; task durations −30% (total); respawn grows (formula). |
| **Mana Drought** | 45:00 | Uplinks also become **Exposed** while the enemy holds *any* of your Outer hardpoints (not just Inner). |
| **Time-out** | 60:00 | Both Mana Reserves run dry. Captures already in progress get up to 30 s of capture overtime (C8), then the Incursion tie-break (see Canon). |
| **Sudden Death** | after the time-out if tied | No respawns; last team standing wins; a mutual kill restarts the round at Mid (after 3 restarts, remaining HP decides, C10). |

**How the design pulls matches toward 25–35 min:** Uplink damage is permanent (no regen); Surges shorten tasks and strengthen attackers' Wardlings; respawn time rises with match time, so late team-wipes open real windows; Mana Drought widens Uplink exposure; Forward Beacons cut travel for the side that holds Mid.

---

## Canon

**Every other design doc must obey these values.** Changing one requires updating this table and `design/registry/entities.yaml`. Numbers marked *(tunable)* may be tuned within the stated range by the owning GDD without a concept change; structure may not.

| # | Topic | Canon decision | Rationale |
| ---- | ---- | ---- | ---- |
| C1 | **Team size** | **5v5.** Bots fill every empty slot and replace disconnected players. Each hero is unique *within* a team; mirror picks across teams allowed. **Exception, M1 vertical slice only:** the 1-lane slice plays **3v3** (`MatchRulesDef.team_size` = 3 in the slice rules; owner decision 2026-10-02), so its lane density (~3 heroes per lane) matches the full game's 10 heroes on 3 lanes (~3.3 per lane) instead of tripling it; duplicate heroes on a team are allowed, because the slice ships 2 heroes (each team is a Vesper Loom / Brannoc mix). The full game stays 5v5. | Standard MOBA shape; 7 heroes > 5 slots leaves draft choice. AI budget: 10 heroes + **≤110 AI agents** on the full map (squads ≤54 incl. 2 Vespers, Garrisons ≤30, Vanguard ≤24). *Consistency pass 2026-10-02: budget re-baselined from "~60 AI" to ≤110; slice duplicate exception added (R4, R5).* |
| C2 | **Map topology** | One symmetric map, **3 lanes** (North/Center/South). Each lane = **5 hardpoints**: A-Inner, A-Outer, **Mid** (starts neutral), B-Outer, B-Inner → **15 total**. Flank paths link lanes between Outer and Mid rows. Central **Mid Plaza** connects the three Mid hardpoints (also the Sudden Death arena). | Short lanes suit first-person travel; 5 nodes give a readable front with room to swing. |
| C3 | **Hardpoint ownership** | Each team starts owning its own Outer + Inner per lane. A hardpoint can be attacked only if the attacker holds the **adjacent hardpoint toward its own HQ** in that lane (Mid needs no prerequisite). Hardpoints flip directly to the capturing team (no neutral state after first capture). Defenders can retake. | Enforces a contiguous front per lane = "push the opponent back". |
| C4 | **Hardpoints are tasks** | Each hardpoint has one fixed task type set by the map: **Hold** (stand in zone, out-number to progress), **Plant** (carry a Mana Cell from the previous held node, plant it, defend it while it charges), **Breach** (destroy a shielded Ward Generator, then hold briefly). Base task duration 60–90 s *(tunable)*, scaled by Surges. **Presence:** heroes count 1.0 each, uncapped; AI presence (Wardlings of any kind: squads, Vanguard waves, Garrison Sentinels) counts 0.5 each, **capped at 3.0 per team per hardpoint**. | Owner: "tasks to be done at hardpoints". Variety per lane without per-node bespoke rules. The AI cap keeps heroes deciding Holds (Pillar 2) even with Vesper's squad and a wave in the zone. *Consistency pass 2026-10-02: AI presence cap 3.0 added (R3).* |
| C5 | **Held hardpoint benefits** | Owner gets: a static **Garrison** (2 Sentinel Wardlings, respawn 45 s), a **Supply Cache** (refills Mechanical reserve ammo; for **Mana** heroes, touching it gives −50% mana regen delay for 10 s, 8 s per-hero cooldown), and a **Barricade** across the lane's main path toward the enemy (owning team passes; enemies must breach it or flank). Barricade Integrity **5,000**; a Barricade on an **Inner** hardpoint that faces the defender's own HQ (i.e. an attacker-held Inner blocking the defender's HQ gate) has **2,500**. Held **Mid** hardpoints are also **Forward Beacons** (spawn points, no Foundry/Armory). | Gives every node a reason to be held, for both resource types; Barricades support the Infiltrator role from `/ideas`; the weaker HQ-facing Barricade stops a captured Inner from sealing the defender inside its HQ. *Consistency pass 2026-10-02: Mana Supply Cache benefit (R8) and Barricade Integrity values (R7) added.* |
| C6 | **HQ contents** | Each HQ: **Mana Uplink** (win objective), **Sanctum** (spawn), **Foundry** (Wardling pickup), **Armory** (shop + full ammo). HQ Sanctum zone heals and blocks enemy entry for the first 10 m (anti-spawn-camp). | Spawn = squad + shopping, per owner. |
| C7 | **Mana Uplink** | **Integrity 33,000** *(tunable 20k–40k)*. **Invulnerable** unless **Exposed**. Exposed while the enemy holds ≥1 of your **Inner** hardpoints (from 45:00, also ≥1 Outer). Damage is **permanent** (no regen, cannot be healed). Wardlings deal 50% to it. Target: ~60 s of uncontested full-team fire to destroy (reference: 5 heroes × 80 + 15 Tier I Wardlings × 21 × 0.5 ≈ 558 DPS → 59 s). Integrity 0 → that team loses immediately. | Two-step siege (break a lane, then hit the spire) prevents cheese; permanence guarantees progress. *Consistency pass 2026-10-02: 30,000 → 33,000 after the Wardling DPS retune (R2).* |
| C8 | **Match timer** | Hard cap **60:00** (owner). **Target typical length 25–35 min.** Escalation at 15:00 / 30:00 (Surges) and 45:00 (Mana Drought) per Match Structure. **Capture overtime:** a capture already in progress at 60:00 may run up to **30 s** past 60:00 (no new tasks start); the Incursion snapshot is taken when the last one completes or fails, or at 60:30. | Owner cap kept; escalation pulls the median down; a 99% capture at 60:00 should not count for nothing. *Consistency pass 2026-10-02: 30 s capture overtime added (R6).* |
| C9 | **Time-out tie-break ("Incursion")** | At 60:00 each team scores **Incursion** per lane: 0 = holds nothing past own Outer; 1 = holds Mid; 2 = holds enemy Outer; 3 = holds enemy Inner. Team Incursion = sum of 3 lanes (0–9). Higher wins. If equal → team that removed the larger **% of enemy Uplink Integrity** wins (needs ≥1 percentage point difference). Still equal → Sudden Death. | Literal reading of "team further into the opponent's HQ wins"; Uplink damage is the deepest possible incursion. |
| C10 | **Sudden Death** | 5 s freeze, then every player (dead or alive) respawns at full HP/ammo on their side of the **Mid Plaza**. Levels, skills and gear kept; all Wardlings and garrisons removed; no respawns; shop disabled. **Last team with a living fighter wins.** If the final fighters of both teams die within **1.0 s** of each other (mutual kill / trade), everyone respawns at Mid Plaza and Sudden Death restarts. A shrinking **Leyfall ring** closes the plaza over 90 s each round to prevent hiding. **Safety valve:** after **3** restarts, the next round is final: if it is still undecided when its ring finishes closing (90 s), the team with the higher **summed remaining HP%** of its living fighters at that moment wins (exact tie → more Sudden Death damage dealt). *(Pending owner confirmation, see `design/open-questions.md`.)* | The owner's mutual-kill rule is kept; the ring makes each round end and the valve makes the match end. *Consistency pass 2026-10-02: 3-restart safety valve added (R6).* |
| C11 | **Respawn** | `Respawn(s) = min(30, 6 + 0.4 × match_minutes)` → 6 s at 0:00, 18 s at 30:00, 30 s at 60:00 *(tunable coefficients)*. Choose spawn: HQ Sanctum or any held Forward Beacon not under attack. | Short early (learning, skirmish), long late (wipes matter → Pillar 5). |
| C12 | **Level & skill points** | **Level cap 15.** 1 skill point at level 1, +1 per level → **15 points**. 4 skills per hero: 3 basic + 1 ultimate. Basic skill tree = 4 nodes: **Unlock → Boost → Fork (pick A *or* B) → Mastery** (Mastery needs level 9+). Ultimate = 3 ranks, available at levels **6 / 10 / 14**. 3×4 + 3 = 15 = everything at cap. Typical player reaches L6 ≈ 6–8 min, L15 ≈ 30–35 min. | Owner: "minimal skill tree per skill, 4 fixed skills, points through EXP". Hitting cap ≈ target match length. |
| C13 | **EXP — "Resonance"** | Earned from: enemy Wardling kills, enemy hero kills/assists, hardpoint captures/defences (owner list). Kills/Wardlings share to allies within 25 m; captures grant EXP to the whole team (participants bonus). Kills of higher-level heroes pay a bonus (catch-up). | In-fiction: attunement to the Cybergram grows. |
| C14 | **Money — "Lumen"** | Per-match currency (resets each match). Sources: **enemy Wardlings (primary)**, hero kills/assists, captures, small passive trickle. Spent **only at HQ Armory** on: weapon parts built from recipes (Components → Assemblies → Signatures; Crystal form on Mana guns, Chip form on Mechanical guns), **body gear in six open item slots** (health, armor vs weapons, resist vs skills, utility), ammo types and ammo mods, consumables (Med-Packs), Wardling squad upgrades. Rules and catalog: `items-and-armory.md`. | Owner: "money given through the mobs"; HQ-only shopping makes the HQ-vs-Beacon spawn choice matter. *Revised 2026-10-07 (owner): Armory v2 recipes and body gear.* |
| C15 | **Wardlings (player mobs)** | **Personal squad:** picked up free at your HQ **Foundry** when you spawn there or walk in: base squad **3**, upgradeable (Lumen) to **5** (Minionmancer +2 more). Variants bought at Foundry (e.g. Shieldling, Striker, Mender); squad upgrades bought at the Armory. Lost squad members are only replaced at the Foundry. On owner's death, squad holds position 10 s then dissolves. **Commands (4):** **Follow** (default), **Hold Here** (garrison a spot), **Attack Target** (aim + press: focus a hero/Wardling/gadget), **Go Capture** (send squad to a hardpoint to work its task). Input: **Smart Command** key (tap: enemy under crosshair → Attack Target, hardpoint → Go Capture, ground → Hold Here), hold the same key for a 4-slice radial wheel, a separate **Follow** key; no commands from the map. **Strength: middle ground** — a base squad is a real but modest threat (focused fire from a base squad of 3 ≈ 30% of a Soldier's DPS: ≈54 DPS against Ryker's 180, i.e. ≈18 per Picket; can finish a wounded hero, cannot beat a healthy one alone); Lumen upgrades/variants (e.g. Striker) push it toward a genuine threat. They still body-block, retaliate against whoever damages their owner, and count for Hold. **Vanguard waves:** every **60 s** each team's Foundry sends a wave of **4** Tier-matched Wardlings into **each lane**, which marches to that lane's **front** (the nearest hardpoint being contested; else the next enemy hardpoint it may attack per C3, else its own front-most hardpoint) and works/defends it. Max **1 live wave per lane per team** (a new wave spawns only when the previous has ≤1 alive). Waves are ownerless and uncommandable (Minionmancer excepted). Tier I/II/III by Surge for all Wardlings. **Garrisons** (C5) and **Vanguard waves** are the only Wardlings without an owner. | Owner notes + owner decision 2026-10-02: picked up at spawn, follow players, buyable, money source; owner chose bodyguard squad + small waves, 4 commands, middle-ground strength. *Consistency pass 2026-10-02: strength anchored to Ryker's 180 DPS (R2); input unified (R10).* |
| C16 | **Hero resource types** | **Mana** heroes: weapon fires from a recharging mana pool (regen after short delay, no reloads, no reserve). **Mechanical** heroes: magazines + finite reserve; refill at Armory, Supply Caches, and from enemy Wardling drops. Skills use **cooldowns** for all heroes (resource type affects the weapon only). Mana guns upgrade with socketed **Crystals**, Mechanical guns with slotted **Chips**: the same weapon items, shown and named in the gun's family form, built from recipes and mounted in the Core, Barrel and Frame sockets — all visible on the weapon model. | Owner's two types; cooldown-only skills keep one readable skill model across heroes. *Revised 2026-10-07 (owner): one item, two forms (`items-and-armory.md` §3.3).* |
| C17 | **Hero roster (7)** | See table below. | Owner's 7 roles, kept. |
| C18 | **Names** | World **Halcyra**; signal **the Cybergram**; teams **Azure Concord** (blue) vs **Ember Syndicate** (red); mobs **Wardlings**; EXP **Resonance**; money **Lumen**; Uplink HP **Integrity**; spawn **Sanctum**; mob pickup **Foundry**; shop **Armory**. | Single vocabulary for UI, VO, docs. |

### Hero Roster (Canon C17)

| # | Hero | Role (from `/ideas`) | Type | Identity in one line |
| ---- | ---- | ---- | ---- | ---- |
| 1 | **Vesper Loom** | Minionmancer / Commander | Mana | Puppeteer who carries +2 Wardlings, empowers allies' squads, and whose ultimate *rewrites* nearby Wardlings into elite forms (or briefly turns enemy ones). |
| 2 | **Sable** | Infiltrator (Stealth / Ninja / Assassin) | Mana | Phases through enemy Barricades, flanks behind the front, plants sabotage charges and picks off isolated targets. |
| 3 | **Juniper Quill** | Trapper | Mechanical | Engineer of layered, chainable traps (snares, tripwires, mines) that lock down hardpoints and chokepoints. |
| 4 | **Ryker Vance** | Soldier (damage dealer) | Mechanical | Assault rifle and grenades, highest sustained DPS, minimal defensive tools. |
| 5 | **Brannoc** | Tank | Mechanical | Huge HP, deployable shield wall, short-range heavy weapon; anchors Hold tasks. |
| 6 | **Liora Vale** | Healer | Mana | Defensive mana weapon; heals with a mana beam and throwable Med-Pack drones. |
| 7 | **Hex** | Hacker | Mana | Hacks enemy gadgets, traps, Barricades and Wardlings into malfunction; scrambles enemy HUDs. |

Type split: 4 Mana / 3 Mechanical.

---

## Comparable Games and How Cybergram Differs

| Game | What we take | What we do differently |
| ---- | ---- | ---- |
| **Paragon / Predecessor** | 3D lane MOBA with heroes, levels, items | First-person, gun-first; no last-hitting, small objective-driven waves; front line is the score |
| **Deadlock** | Shooter-MOBA hybrid, souls economy | Players *carry* their minions; hardpoint tasks instead of tower trades; lower complexity, readable anime look |
| **Overwatch 2** | Hero roles, ability identity, readability | Long arc (levelling, builds, 30-min front war) vs. short rounds |
| **Battlefield (Breakthrough)** | Sector-by-sector push, front lines | Symmetric two-way front with comebacks; heroes and MOBA growth |
| **Dota 2 / LoL** | Lanes, roles, skill points, ultimate at L6 | Shooter execution; 4-node "minimal" skill trees |

**Unique selling points**
1. **Bring-your-own army** — every player leads a commandable Wardling squad; small Vanguard waves keep the front alive.
2. **Hardpoints are tasks** — hold, plant, breach — and the front line is visible everywhere.
3. **Spawn choice with teeth** — HQ (squad + shop) vs. Forward Beacon (speed).
4. **Visible weapon growth** — crystals and chips physically socketed into your gun.
5. **A siege that ends** — permanent Uplink damage, Surges, and a sudden-death rule that guarantees a winner.

---

## Scope Tiers

| Tier | Content | Features | Answers |
| ---- | ---- | ---- | ---- |
| **0 — Offline Vertical Slice (M1)** | 1-lane Slice Map "Shardline Causeway" (Breach / Plant / Hold / Plant / Breach), greybox, 2 heroes (**Vesper Loom, Brannoc**; duplicates allowed per team, C1), local authoritative server, bots | Movement/gunplay, Mana vs. Mechanical ammo, Hold first then Plant and Breach (staged within M1), Wardling squads with all 4 commands, Vanguard waves, Uplink + exposure, Surge I, levels + **reduced skill tree** (Unlock + Boost, ult ranks), Lumen shop incl. the minimal mount pipeline (`weapons-and-mods.md` §3.10), Forward Beacon spawn choice | Is the gun + squad + front loop fun? |
| **1 — Full Match (M2–M3)** | 3-lane map greybox→stylized, 4 heroes (+ Ryker, Liora) | Online PvP (listen + dedicated server, M2); full skill trees (Forks, Mastery), Garrisons, Supply Caches, Barricades, Surge II, Drought, time-out + capture overtime, Sudden Death, 5v5 with bots | Does a full match land in 25–35 min? |
| **2 — Alpha** | All 7 heroes, final map art pass | Full Crystals/Chips catalog visible on guns and body gear visible on heroes (Armory v2, protocol 22, `items-and-armory.md`), all ammo types and Ammo Mods, Wardling variants, bot AI for all roles | Is the role mix balanced and readable? |
| **3 — Launch** | 7 heroes, 1 map, cosmetics | Matchmaking, backfill bots, co-op vs. bots mode, account progression (cosmetic), tutorial | Can strangers enjoy it? |
| **Post-launch** | More heroes/maps | Ranked, new Wardling variants, events | — |

**Explicitly cut until post-launch:** neutral jungle camps, more than one map, controller support, PvE campaign, voice-chat tech beyond pings.

---

## Top Risks

| Risk | Type | Why it matters | Mitigation |
| ---- | ---- | ---- | ---- |
| **Netcode for 10 heroes + ≤110 AI** (squads ≤54 incl. 2 Vespers, Garrisons ≤30, Vanguard ≤24; C1) in Godot 4.7 | Technical | Wardlings multiply replicated entities; FPS needs lag compensation | Server-authoritative from Tier 0; Wardling state compressed/interest-managed; cap squads (C15); 120-agent perf scenario from M1; 5v5 + full squads load test in M2 |
| **Wardlings as noise** | Design | Up to ~110 constructs map-wide (50+ in one big fight) may bury readability and feel like clutter | Pillar 3 & 4: strong team colour, simple silhouettes, defensive behaviour, squad cap, audio tells |
| **Match length drift** | Design | 60-min stalemates kill the genre fit | Canon C7/C8/C11 levers; telemetry on match length from M1 (slice) and M3 (full map) bot playtests |
| **Snowballing** | Design | Front + levels + money compound | Forward Beacons only at Mid; catch-up EXP bounty; defender advantage pre-30 min; Uplink exposure reversible by retaking |
| **Bot quality** | Technical/Design | Bots fill slots in PvP *and* power the later co-op mode | Bot AI is a first-class system from M1 (Tier 0); behaviour per role, not per hero, first |
| **Hacker/Infiltrator frustration** | Design | Losing control of gadgets/flanks feels unfair in FPS | Short, telegraphed effects; clear counterplay in each hero GDD |
| **Scope (7 heroes × 4 skills × trees)** | Production | 28 skills, 56 forks, + ammo/mod content | Tiered hero delivery; shared skill-node templates; Forks are modifiers, not new skills |
| **Market crowding** | Market | Deadlock/Predecessor occupy the space | Lean into USP #1 and the anime look; shorter, readable matches |

---

## Open Questions for the Owner

**Consolidated on 2026-10-02 into `design/open-questions.md`** (the single list for every doc, with current defaults, alternatives and where each lives, plus the Decision Log of the consistency pass). The items previously listed here (team size, map shape, Uplink exposure, tie-break order, Sudden Death details, cooldown-only skills, names) are carried there. Wardlings (C15) were decided by the owner on 2026-10-02.
