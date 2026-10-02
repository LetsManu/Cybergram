# Cybergram Roadmap: M0 to Early Access

*Owner: producer · Created 2026-10-02 · Status: Draft (autonomous, `modes.rigor: minimal`)*
*Sources: `design/gdd/game-concept.md` (Canon C1–C18, Scope Tiers, Top Risks), `/ideas`, owner decisions of 2026-10-02.*

> **Owner decisions this roadmap encodes:** M0 is pre-production design docs. M1 is an **offline**
> vertical slice (1 lane, 2 heroes, bots, local authoritative server). M2 is **real networked PvP**.
> PvP is the core mode and bots fill empty slots. Co-op vs. bots comes later (M5).
>
> **Consistency pass 2026-10-02 (creative-director, producer-approved):** the M1 heroes are **Vesper Loom +
> Brannoc** (duplicates allowed per team in the slice only, Canon C1); the M1 map is the Slice Map
> **"Shardline Causeway"** (`match-flow-and-map.md` §3.7, Breach / Plant / Hold / Plant / Breach), which M1 may
> stage Hold-only first; M1 includes **levels with a reduced skill tree** (Unlock + Boost + ult ranks; no Forks or
> Mastery) and the **minimal mount shop** (`weapons-and-mods.md` §3.10). Ryker and Liora move to M3.
>
> **Mapping to the concept's Scope Tiers.** M1 is Tier 0 (offline vertical slice) plus HUD and bots. M2 adds
> networking that Tier 1 assumes. M3 completes Tier 1 (full match), M4 is Tier 2 (Alpha), and M5–M6 are Tier 3
> (Launch) cut down to an Early Access candidate. Networking moves *ahead* of the full match loop on purpose: the
> Top Risk "netcode for 10 heroes + ≤110 AI" is the one most likely to force a rewrite, so it is retired
> while the content is still small.

## Milestone Overview

| ID | Name | Type | Target (approx.) | One-line goal |
|----|------|------|------------------|---------------|
| M0 | Pre-Production Design | Design | 2026-10-16 (2 wk) | Every M1 system specified, architected and broken into stories |
| M1 | Offline Vertical Slice | Vertical Slice | 2026-12-14 (8 wk) | One lane, Vesper + Brannoc, Wardlings, levels, a small shop and bots: is the gun + squad + front loop fun? |
| M2 | Networked PvP | Tech Milestone | 2027-02-08 (8 wk) | The M1 slice played by real humans over the internet, server-authoritative |
| M3 | Full Match Loop | Vertical Slice (full) | 2027-04-19 (10 wk) | A full 3-lane 5v5 match lands in 25–35 min with 4 heroes (adds Ryker + Liora) |
| M4 | Alpha | Alpha | 2027-07-12 (12 wk) | All 7 heroes, all Canon systems, stylized map, dedicated servers |
| M5 | Beta / Platform | Beta | 2027-09-20 (10 wk) | Strangers can find a match, learn the game and play co-op vs. bots |
| M6 | Early Access Candidate | Gold (EA) | 2027-11-15 (8 wk) | A stable, performant, store-ready EA build |

Dates assume one owner reviewing PRs part-time and 1–3 parallel Claude sessions. The producer
re-baselines them at each `/milestone-review`.

## M0: Pre-Production Design (current)

**Goal.** Turn the concept into specs that agents can build from without guessing. These are the
GDDs for the M1–M3 systems, the art bible, the HUD spec and the architecture with its ADRs. The
milestone ends with M1 epics and stories on disk.

**Exit criteria**
- [ ] GDDs exist and pass `/design-review` (no MAJOR REVISION):
      `design/gdd/match-flow-and-map.md`, `design/gdd/heroes.md`, `design/gdd/weapons-and-mods.md`,
      `design/gdd/wardlings-and-economy.md`. *Paths are provisional. They are being written in
      parallel, so use whatever paths those agents deliver.*
- [ ] `design/gdd/systems-index.md` lists every system with its milestone (M1/M3/M4).
- [ ] `/review-all-gdds` report exists (`design/gdd/gdd-cross-review-*.md`) with no Canon conflicts.
- [ ] `design/art-bible.md` and `design/ux/hud.md` exist.
- [ ] `docs/architecture/architecture.md` plus ≥3 ADRs (`docs/architecture/adr/ADR-*.md`). They must cover:
      server-authoritative tick model, transport abstraction (local ↔ ENet), entity/snapshot format,
      and the Wardling AI budget. `/architecture-review` is run and `docs/architecture/control-manifest.md` exists.
- [ ] **Launch and look:** the cloud container downloads Godot 4.7, opens an empty project and captures
      one frame with `--write-movie`. The frame is saved as `production/qa/evidence/m0/01-engine-probe.png`.
      This proves the screenshot evidence pipeline before M1 depends on it.
- [ ] `production/epics/*/EPIC.md` for every M1 epic and ≥3 `story-*.md` per epic.
      `production/milestones/M1-vertical-slice.md` is approved.
**Scope in:** design docs, architecture, ADRs, an engine probe and M1 story breakdown.
**Scope out:** game code beyond the engine probe, art assets, and GDD depth for M4+ systems
(their entries in the systems index are enough).
**Epics:** none (design milestone). Work items are the docs above.
**Risks retired:** spec ambiguity (agents inventing rules), Canon drift between parallel GDDs, and
"can a cloud session run Godot 4.7 and see a frame?"
**Driven by:** `/design-system`, `/design-review`, `/review-all-gdds`, `/consistency-check`,
`/art-bible`, `/ux-design hud`, `/create-architecture`, `/architecture-decision`,
`/architecture-review`, `/create-control-manifest`, `/create-epics`, `/create-stories`.
Agents: creative-director, game-designer, systems-designer, economy-designer, level-designer,
art-director, ux-designer, technical-director, network-programmer, producer.

## M1: Offline Vertical Slice (detailed in `M1-vertical-slice.md`)

**Goal.** Prove the core loop offline: a first-person fight over the 1-lane Slice Map **"Shardline
Causeway"** (5 hardpoints, Breach / Plant / Hold / Plant / Breach), with **Vesper Loom** (Mana, commander)
and **Brannoc** (Mechanical, tank), Wardling squads with all 4 commands, Vanguard waves, levels with a
reduced skill tree, a small Lumen shop, bots in every slot, and an Uplink that can fall. The match runs on a
**local authoritative server**. The simulation runs in-process and the client sees only snapshots through a
transport interface, so M2 swaps the transport and keeps the game code.

**Exit criteria:** these are the full list in `M1-vertical-slice.md`. In short, a 5v5 bot match is
played to an Uplink kill with a screenshot set in `production/qa/evidence/m1/`; 20 headless soak
matches run with 0 crashes; the client sees snapshots only (it still plays at 150 ms RTT); ≥60 FPS
with 10 heroes + 80 Wardlings (the slice worst case); and a `/playtest-report` go/pivot on fun.
**Scope in:** 1 lane (5 hardpoints, 2 HQs, Mid Forward Beacon), Hold first then Plant and Breach (staged within M1),
Vesper Loom + Brannoc (duplicates allowed), Mana and Mechanical ammo, Wardling squads with all 4 commands,
Vanguard waves, Uplink exposure, respawn C11, Surge I, levels 1–15 with a reduced skill tree (Unlock + Boost +
ult ranks), Lumen shop (squad upgrades, Med-Pack, minimal mount pipeline), bots, core HUD.
**Scope out:** networking, Forks/Mastery, Surge II/Drought, capture overtime, Sudden Death, 3 lanes, Garrisons,
Barricades, Supply Caches, Ryker/Liora/Sable/Juniper/Hex, Wardling variants, full mount catalog, art beyond
greybox and team colour.

**Epics and stories (build order).** `/create-stories <epic-slug>` turns each into story files under
`production/epics/<epic-slug>/`. Each visual story needs a screenshot in `production/qa/evidence/<story-slug>/`.

1. **E1 `project-scaffold`**: (1) Godot 4.7 project, folders and Jolt/Forward+ settings; (2) gdUnit4 and an example test;
   (3) GitHub Actions headless test workflow `.github/workflows/tests.yml`; (4) `tools/capture.sh` for
   `--write-movie` evidence capture with a `--scene` launch argument; (5) client/server boundary lint check.
2. **E2 `fps-controller`**: (1) input map and mouse look with sensitivity; (2) a pure, deterministic `move(state, input, dt)`
   step for walk, sprint, jump and crouch; (3) a CharacterBody3D wrapper that uses the step; (4) first-person camera
   and placeholder viewmodel; (5) a movement test course scene.
3. **E3 `local-server`**: (1) a `Transport` interface and `LocalTransport` with a latency/loss simulator; (2) a server
   `Simulation` with a fixed tick (rate per ADR) and an entity registry with network IDs; (3) client input
   commands → server; (4) server snapshots → client entity views with interpolation; (5) a `--headless`
   server-only mode for soak tests.
4. **E4 `combat-core`**: (1) Health/damage component, armor % and team filter; (2) server-side hitscan weapon with
   spread and falloff; (3) death, respawn timer (C11) and Sanctum spawn; (4) hit marker and damage feedback;
   (5) kill/assist events to a match event bus.
5. **E5 `ammo-models`**: (1) a weapon data Resource schema; (2) a Mechanical magazine, reserve and reload (Brannoc's Ironmaw);
   (3) a Mana pool with regen delay and Burnout (Vesper's Threadcaster); (4) ammo refill at the Armory volume and from Ammo Sparks.
6. **E6 `slice-map`**: (1) Shardline Causeway lane blockout with 5 hardpoint sites and the two flank loops (Barricade sockets
   built but inactive); (2) two HQs (Sanctum, Foundry, Armory, Uplink spire); (3) navmesh baked for heroes and Wardlings;
   (4) team-colour dressing and readability pass; (5) launch scene `slice_match.tscn`.
7. **E7 `hardpoints`**: (1) hardpoint state and ownership with the C3 adjacency rule; (2) Hold task presence and contest
   with progress (out-number; AI presence 0.5 each, capped at 3.0 per team, C4); (3) flip to the capturing team, the
   lane-front state and the Mid Forward Beacon; (4) capture and defence events for telemetry; (5) **Plant** task (Cell
   Cradle, carry, plant, defuse) on S-AO/S-BO; (6) **Breach** task (Ward Generator, shield, phase-2 hold) on S-AI/S-BI.
   Stories 1–4 run all five nodes as Hold; 5–6 switch to the final layout.
8. **E8 `wardlings`**: (1) Foundry pickup of a squad of 3 (Vesper 5); (2) follow with formation and body-block; (3) defensive
   return fire at your attacker; (4) the 4 commands (Smart Command `Z`, Follow `X`, radial) and 0.5 Hold presence; (5) dissolve
   10 s after owner death; (6) Vanguard waves (60 s tick, ≤1-alive gate, lane-front targeting); (7) Surge I tier morph;
   (8) a server-side perf budget test with 80 Wardlings, plus the 120-agent stress scenario.
9. **E9 `uplink-match-flow`**: (1) Uplink Integrity (33,000), Exposure rule and permanent damage (C7); (2) match phases:
   Deploy (Mid locked 60 s) → Skirmish → Surge I → end; (3) a 30:00 slice cap with 1-lane Incursion and Uplink-% tie-break
   (a remaining tie is a draw); (4) victory/defeat screen and return to start.
10. **E10 `hero-kits`**: (1) a skill framework with cooldowns, aimed/placed casting and data Resources; (2) Vesper's passive
    (Conductor, wave command), 3 basics (Unlock/Boost) and Rewrite ranks 1–3; (3) Brannoc's passive (Anchor), 3 basics
    (Unlock/Boost) and Earthbreaker ranks 1–3; (4) a hero select with launch argument `--hero=`.
11. **E11 `hero-bots`**: (1) bot controller that drives the same input commands as a player; (2) lane decision
    (attack or defend the next eligible hardpoint, carry Cells); (3) combat (target select, aim error by difficulty, skill
    use); (4) squad pickup, squad commands and spawn choice; (5) fill empty slots at match start; (6) bot buying and skill points.
12. **E12 `core-hud`** (grows alongside other epics): (1) HP and ammo/mana meter; (2) skill cooldown bar; (3) squad strip
    and command glyphs; (4) lane front strip showing 5 hardpoints and capture progress; (5) Uplink Integrity for both teams
    and the match clock; (6) kill feed and respawn timer; (7) objective tracker for Hold/Plant/Breach.
13. **E13 `spawn-and-armory`**: (1) spawn choice between HQ and held Mid Beacon; (2) Lumen from enemy Wardlings, kills,
    captures and trickle (60/min in the slice); (3) Armory: Squad Expansion I/II, Reinforced Cores I/II, Amplifier
    Emitters, Med-Pack; (4) the minimal mount pipeline (Ember Heart, Flux Coil, Overclock, Quickload; Piercing, Sunder;
    greybox mounts; buy/upgrade/sell/undo); (5) HUD Lumen counter and Armory UI.
14. **E15 `progression-lite`**: (1) Resonance sources and levels 1–15 (`wardlings-and-economy.md` §16) with level scaling
    (`heroes.md` §3.3); (2) reduced skill tree (Unlock, Boost, ult ranks at 6/10/14) and skill-point spending (Alt quick
    spend); (3) HUD level ring and skill-point badge.
15. **E14 `slice-integration`**: (1) match telemetry log (length, winner, captures, K/D, Lumen, levels); (2) headless
    autoplay soak of 20 matches in nightly CI; (3) perf capture at 10 heroes + 80 Wardlings; (4) owner playtest ×3
    and `/playtest-report`; (5) `/milestone-review` and the go/pivot decision.

**Sprint plan:** S1 = E1–E3, E4.1–3 and E12.1. S2 = E4 rest, E5, E6, E7.1–4 (Hold-only), E8.1–4 and E12.2–4.
S3 = E8 rest, E9, E10, E15, E7.5 (Plant), E11.1–2 and the cel shader. S4 = E7.6 (Breach), E11 rest, E12 rest, E13
and E14. Keep a 20% buffer each sprint. The consistency pass added scope (Vanguard waves, all 4 commands, Plant/Breach,
levels, mount shop); the producer re-baselines at the end-of-S2 review.
**Risks retired:** "Is it fun?", Wardlings-as-noise (first read), the cost of the authoritative
architecture, the offline entity budget, bot feasibility and the agent build/evidence pipeline.
**Driven by:** `/create-stories`, `/story-readiness`, `/dev-story`, `/code-review`, `/story-done`,
`/smoke-check`, `/soak-test`, `/perf-profile`, `/playtest-report`, `/milestone-review`.
Teams: `/team-combat` (weapons, skills), `/team-level` (slice map), `/team-ui` (HUD).
Agents: gameplay-programmer, engine-programmer, ai-programmer, godot-gdscript-specialist,
ui-programmer, level-designer, qa-tester.

## M2: Networked PvP

**Goal.** The M1 slice played online by up to 10 humans, with bots filling the rest. It must feel
responsive at ≤100 ms RTT and stay authoritative and cheat-resistant at its core.

**Exit criteria**
- [ ] A listen server and a headless dedicated server (`--headless` export) both host the slice.
      Clients join by IP/code.
- [ ] Client-side prediction with reconciliation for movement and firing. Server-side lag
      compensation (rewind) for hitscan. Tested by the `/regression-suite` netcode cases.
- [ ] A load test with 10 clients (bots acting as clients) and up to 80 Wardlings (the slice worst case) at 150 ms RTT and 2%
      loss keeps bandwidth ≤ the ADR budget (e.g. ≤64 kbps down per client). Server tick stays stable.
- [ ] Disconnect → a bot takes over within 5 s, and rejoin returns the slot (C1).
- [ ] **Launch and look:** two clients in the cloud container, with captures from both POVs saved
      in `production/qa/evidence/m2/`. Owner plus ≥1 remote friend play 3 matches;
      `/playtest-report` is filed.
**Scope in:** ENet transport, prediction, lag compensation, interest management for Wardlings,
snapshot delta compression, join/leave/backfill, a basic lobby.
**Scope out:** matchmaking, accounts, NAT punch-through services (direct IP or relay only),
new content.
**Epics:** net-transport, client-prediction, lag-compensation, snapshot-compression,
interest-management, session-lobby, bot-backfill, dedicated-server-build, net-test-harness.
**Risks retired:** **Top Risk #1 (netcode at scale)**, plus hit-registration trust and server cost
per match (first estimate).
**Driven by:** `/architecture-decision` (netcode ADR updates), `/dev-story`, `/story-done`,
`/regression-suite`, `/soak-test`, `/perf-profile`, `/security-audit quick`, `/test-flakiness`.
Agents: network-programmer, engine-programmer, devops-engineer, security-engineer, qa-lead.

## M3: Full Match Loop

**Goal.** Grow to the Canon match: 3 lanes × 5 hardpoints with Mid Plaza and flanks; all three task
types on the full map; full skill trees (Forks and Mastery); held-hardpoint benefits; Surge II and Mana Drought;
time-out with capture overtime and Incursion; Sudden Death with its safety valve; 4 heroes (adds Ryker and Liora).
The point is to show that a full match lands in 25–35 min.

**Exit criteria**
- [ ] 50 headless 5v5 bot matches: median length is 25–35 min, <5% hit the 60:00 cap, and every
      match has a winner (C7–C10). Telemetry is in `production/qa/telemetry/m3/`.
- [ ] Each hero reaches L15 in ~30–35 min of bot play (C12). `/balance-check` is clean.
- [ ] Sudden Death restarts correctly on a mutual kill within 1.0 s, and after 3 restarts the final round is decided by summed HP% at ring close (automated scenario tests, C10).
- [ ] A capture in progress at 60:00 completes within the 30 s capture overtime and counts for Incursion (C8).
- [ ] **Launch and look:** screenshot set covering each task type, the shop, a skill tree, the Surge
      banner and the Sudden Death ring. 5 online playtests are filed.
**Scope in:** full map greybox (15 hardpoints, Mid Plaza, flank tunnels), Garrisons, Supply Caches (incl. the
Mana regen-delay benefit), Barricades (5,000 / 2,500 HQ-facing), Forward Beacons on all Mids, full skill trees
(Forks and Mastery for Vesper and Brannoc), Surge II, Mana Drought, capture overtime, Incursion, Sudden Death,
Ryker Vance (Breakline AR-7) and Liora Vale (Halo Repeater with heal beam), Canon C1 hero uniqueness per team.
**Scope out:** remaining 3 heroes, full Crystals/Chips catalog and visuals, Wardling variants, final art.
**Epics:** full-map, hardpoint-benefits, skill-trees-full, match-escalation, endgame-incursion-sudden-death,
hero-ryker, hero-liora, match-telemetry.
**Risks retired:** match length drift, the first snowball read and skill-tree scope (Fork/Mastery template proven).
**Driven by:** `/team-level`, `/team-combat` (per hero), `/team-ui`, `/balance-check`,
`/soak-test`, `/playtest-report`, `/consistency-check`, `/milestone-review`.

## M4: Alpha

**Goal.** Content and features complete for the core mode. That means all 7 heroes, the full Canon
system set with visible power (Pillar 4), and the stylized art pass on the map.

**Exit criteria**
- [ ] All 7 heroes are playable by humans and by bots (role-based bot behaviour).
- [ ] The full Crystals/Chips catalog appears on weapon models. All ammo types, Ammo Mods and Wardling variants (Shieldling,
      Striker, Seeker, Mender, Sapper) work.
- [ ] Map art pass matches `design/art-bible.md`. Team colours read at 50 m (screenshot review).
- [ ] Dedicated server soak: 24 h, 0 crashes, no memory growth over 5%.
- [ ] **Launch and look:** a hero gallery and per-hero skill captures, with `/team-polish`-lite visual review.
**Scope in:** Sable, Juniper, Hex; full Crystals/Chips catalog; all ammo types and Ammo Mods; Wardling variants; stylized map;
VO/SFX first pass; bot AI for all roles.
**Scope out:** accounts, matchmaking, cosmetics store, tutorial.
**Epics:** hero-sable, hero-juniper, hero-hex, weapon-mods-visible, ammo-types,
wardling-variants, bot-roles, map-art-pass, audio-pass, server-soak.
**Risks retired:** scope of 7 heroes, Hacker/Infiltrator frustration, bot quality, and readability
with full content.
**Driven by:** `/team-combat`, `/team-level`, `/team-audio`, `/asset-spec`, `/asset-audit`,
`/balance-check`, `/soak-test`, `/gate-check`. Agents: art-director, technical-artist,
godot-shader-specialist, sound-designer, ai-programmer.

## M5: Beta / Platform

**Goal.** Make it playable by strangers: matchmaking with bot backfill, a cosmetic-only account
layer, the co-op vs. bots mode, a tutorial, settings and accessibility.

**Exit criteria**
- [ ] A queue finds a match in under 90 s at 20 CCU. Missing slots fill with bots.
- [ ] The co-op 5 humans vs. 5 bots mode uses the same rules (Anti-Pillar: no PvE campaign).
- [ ] A new player finishes the tutorial and a bot match with no external help (3 fresh testers).
- [ ] `design/accessibility-requirements.md` tier is met. `/security-audit full` has no open HIGH.
- [ ] **Launch and look:** captures of the main menu, queue, tutorial, settings and post-match screens.
**Scope in:** accounts, matchmaking, co-op mode, cosmetic unlocks, tutorial, settings,
accessibility, crash reporting, anti-cheat basics.
**Scope out:** ranked, store/monetization, more maps.
**Epics:** accounts, matchmaking, coop-vs-bots, cosmetics-progression, tutorial, settings-a11y,
crash-reporting, anti-cheat-basics.
**Risks retired:** onboarding, queue health at low population (bots) and security.
**Driven by:** `/team-ui`, `/team-live-ops`, `/ux-design`, `/ux-review`, `/security-audit`,
`/team-qa`, `/playtest-report`.

## M6: Early Access Candidate

**Goal.** Polish, performance, balance and the release pipeline, ending in a build that could go on a store.

**Exit criteria**
- [ ] `/playtest-report` ×3 (new player, mid-game, late-game) is filed with no S1/S2 open.
- [ ] Perf budget is met on min spec. 7-day crash-free rate is ≥99.5% in a closed test.
- [ ] `/release-checklist` and `/launch-checklist` pass. `/changelog` and `/patch-notes` are drafted.
- [ ] **Launch and look:** a trailer-capture pass and store screenshots from a release build.
**Epics:** perf-pass, balance-pass, polish-pass, store-build-pipeline, closed-test-ops.
**Risks retired:** market readiness and live stability.
**Driven by:** `/team-polish`, `/perf-profile`, `/balance-check`, `/release-checklist`,
`/launch-checklist`, `/team-release`, `/day-one-patch`. Agents: release-manager, devops-engineer,
community-manager.

## Dependency Graph

```
 M0 Design ──► M1 Offline Slice ──► M2 Networked PvP ──► M3 Full Match ──► M4 Alpha ──► M5 Beta ──► M6 EA
   │  GDDs, ADRs        │                  │                   │                │            │
   │  art bible, HUD    │ transport iface  │ ENet + prediction │ 3 lanes,       │ 7 heroes   │ queue, co-op
   └─ engine probe      │ (local)          │ lag comp, interest│ full trees     │ all mods   │ accounts
                        ▼                  ▼                   ▼                ▼            ▼
                   go/pivot on fun   go/pivot on netcode   match length OK   content lock  stranger-ready

 M1 epic build order (critical path marked ═):
 E1 Scaffold/CI ═► E2 FPS Controller ═► E3 Local Server Tick ═► E4 Combat Core ═► E5 Ammo Models
                                              │                       │                 │
                                              ├─► E6 Slice Map ═══════╪═► E7 Hardpoints ═╪═► E9 Uplink & Match Flow
                                              │        │              │        │         │          │
                                              │        └─► E8 Wardlings ◄──────┘         │          │
                                              │                 │                        ▼          │
                                              └──► E12 HUD (grows with each epic)   E10 Hero Kits   │
                                                                │                        │          │
                          E13 Spawn & Armory, E15 Progression ◄─┴────────────────────────┤          │
                                                                                         ▼          ▼
                                                                         E11 Hero Bots ═══► E14 Integration
                                                                                              & Playtest
```

## How to Work with Claude on This Project

**Ground rules.**
1. Each cloud session does one story or one doc, and you get one PR per session.
2. Sessions run autonomous at `rigor: minimal`, so they write without asking. They do not commit
   unless the prompt says so. End every build prompt with *"commit on a branch and open a PR"*.
3. Canon (`design/gdd/game-concept.md`) is law. A session that wants to change it must say so
   in the PR title (`[CANON]`).

**Session prompts by phase**

| Phase | Paste into a new session |
|-------|--------------------------|
| M0 docs | `/design-system <system>` then `/design-review design/gdd/<file>.md`. After all are done: `/review-all-gdds`, then `/consistency-check` |
| M0 arch | `/create-architecture`, then `/architecture-decision <topic>` (×N), `/architecture-review`, `/create-control-manifest` |
| M0 → M1 | `/create-epics layer: foundation`, then `layer: core`. Next, `/create-stories <epic-slug>` per epic, and `/gate-check` (advisory) |
| Build a story | `/story-readiness production/epics/<epic>/story-NN-*.md`, then `/dev-story <same path>`, then `/code-review`, then `/story-done <same path>`, then "commit on a branch and open a PR" |
| Cross-domain feature | `/team-combat "Brannoc kit: Aegis Wall + Ironmaw"`, `/team-level "slice lane greybox"`, `/team-ui "core HUD"` |
| End of sprint (2 wk) | `/smoke-check sprint`, then `/sprint-status`, then `/retrospective`, then `/scope-check` |
| End of milestone | `/soak-test`, then `/perf-profile`, then `/playtest-report`, then `/milestone-review`, then a producer session that updates this roadmap |
| Something broke | `/bug-report "<symptom>"`, then `/bug-triage`, then `/hotfix` for an S1 |
| Lost? | `/help` or `/sprint-status` |

**Reviewing PRs (about 10 minutes each)**
1. **CI green.** The `.github/workflows/tests.yml` headless gdUnit4 run must pass. Don't merge red.
2. **Story file.** The `Status: Complete` and the AC table in the story map each criterion to a test
   or an evidence file.
3. **Look at the pictures.** Open `production/qa/evidence/<story>/*.png` in the PR diff. A visual
   story with no screenshot does not merge.
4. **Scope.** The diff touches only what the story names. Anything extra becomes a `/bug-report`
   or a new story, not a sneak-in.
5. **Play it** at the end of each epic. Pull the branch and run `godot --path . res://scenes/slice/slice_match.tscn`.
6. To request changes, comment on the PR and send the session "address PR comments". Use
   `/code-review <PR#> --comment` for a second opinion.

**Parallelism.** Run at most 3 build sessions at once, on epics that do not share files (see the
graph; for example, E6 map ∥ E5 ammo ∥ E12 HUD). Merge in graph order.
