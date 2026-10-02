# M1 Soak Report: 20 headless bot matches (E14)

*Date: 2026-10-02 · Build: working tree on `main` (uncommitted E14 + E12 changes) · Godot 4.7-stable, headless.*
*Owner: qa-lead / gameplay-programmer (E14).*

## How it was run

```
godot --headless --fixed-fps 30 --path . -- --server --bots-only --seed <1..20> \
      --telemetry production/qa/telemetry/m1
```

- The matches ran as 10 normal-profile bots with mirror rosters (Vesper / Brannoc alternating), at the real match clock (`--match-clock 1`).
- The data is the final slice tuning in `design/balance/slice-tuning.md`.
- Three matches ran in parallel on a 4-core container. The E12 agent was also running tests on the same machine at times, so the timings below were taken under load.
- Each match wrote `production/qa/telemetry/m1/match_seed<N>.json`. The file holds the winner, length, flips, Uplink %, levels, task counters, tick time and bot cost.

## Results

| Metric | Result | Gate |
| ---- | ---- | ---- |
| Crashes / abnormal exits | **0 / 20** (all exit 0, all reached End) | 0, **PASS** |
| `SCRIPT ERROR` in logs | **0** | **PASS** |
| `ERROR` lines | 7 per run, all at exit (resource / RID leak report on quit). Identical in the E11 baseline log, so they predate E14 | follow-up (see below) |
| End by Uplink kill before 30:00 | **1 / 20** (seed 20, 25:13) | ≥ 15 / 20, **FAIL** |
| End reasons | 19 Time-out → Incursion, 1 Uplink destroyed. No draws | |
| Length | 19 × 30:00, 1 × 25:13. Mean 29.8 min | slice target 12–22 min, **FAIL** |
| Winners | Concord 12, Syndicate 8 | mirror teams: no side bias beyond noise |
| Uplink Exposed at least once | 14 / 20 matches. Max damage 100 % (seed 20), next 98.9 % (17) and 63.8 % (18) | |
| Server tick (`ServerWorld.step`) p50 / p95 | **2.86 / 4.86 ms** median across matches (worst p95 5.26 ms) | ≤ 25 % of the 33.3 ms tick = 8.3 ms, **PASS** |
| Tick max (spikes) | 15–116 ms, one or two ticks per match | follow-up |
| Bot cost per tick, all 10 bots (`BotCostMeter`) | **0.426 ms avg** (p95 0.74 ms) | 0.4 ms, **narrowly not met** |

### Per-match table

| Seed | End reason | Winner | Length | Incursion C-S | Ownership | Flips | Uplink % dealt C / S | Exposed s C / S | Cells planted / defused | Generators down | Kills | Tick p50 ms | Tick p95 ms | Tick max ms | Bot ms/tick |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| 1 | incursion | concord | 30:00 | 1-0 | CCCSS | 17 | 31.3 / 0.0 | 0 / 383 | 9 / 7 | 0 | 196 | 2.582 | 4.621 | 100.916 | 0.417 |
| 2 | incursion | syndicate | 30:00 | 0-1 | CCSSS | 20 | 0.0 / 0.0 | 0 / 0 | 5 / 5 | 0 | 184 | 2.908 | 4.849 | 92.107 | 0.418 |
| 3 | incursion | syndicate | 30:00 | 0-1 | CCSSS | 22 | 0.0 / 0.0 | 0 / 0 | 8 / 8 | 0 | 182 | 2.943 | 5.144 | 116.133 | 0.435 |
| 4 | incursion | syndicate | 30:00 | 0-1 | CCSSS | 18 | 0.0 / 0.0 | 72 / 0 | 9 / 7 | 0 | 185 | 2.854 | 4.968 | 15.529 | 0.425 |
| 5 | incursion | concord | 30:00 | 2-0 | CCCCS | 24 | 15.9 / 0.0 | 0 / 35 | 7 / 6 | 0 | 158 | 2.991 | 5.0 | 18.597 | 0.432 |
| 6 | incursion | syndicate | 30:00 | 0-1 | CCSSS | 20 | 36.1 / 0.0 | 0 / 102 | 6 / 4 | 0 | 187 | 2.845 | 4.782 | 30.581 | 0.417 |
| 7 | incursion | syndicate | 30:00 | 0-1 | CCSSS | 22 | 0.0 / 0.0 | 0 / 0 | 7 / 7 | 0 | 188 | 2.892 | 4.915 | 24.217 | 0.419 |
| 8 | incursion | syndicate | 30:00 | 0-1 | CCSSS | 14 | 0.0 / 0.0 | 0 / 0 | 10 / 9 | 0 | 193 | 2.806 | 4.682 | 36.71 | 0.416 |
| 9 | incursion | concord | 30:00 | 1-0 | CCCSS | 20 | 0.0 / 0.0 | 0 / 0 | 5 / 5 | 0 | 180 | 2.945 | 5.073 | 39.269 | 0.421 |
| 10 | incursion | concord | 30:00 | 1-0 | CCCSS | 14 | 0.0 / 8.2 | 117 / 0 | 9 / 7 | 0 | 197 | 2.585 | 4.697 | 42.156 | 0.414 |
| 11 | incursion | concord | 30:00 | 1-0 | CCCSS | 19 | 4.2 / 0.0 | 0 / 122 | 12 / 10 | 0 | 187 | 2.746 | 4.599 | 26.806 | 0.423 |
| 12 | incursion | syndicate | 30:00 | 0-1 | CCSSS | 18 | 0.8 / 0.3 | 67 / 121 | 11 / 5 | 0 | 191 | 2.752 | 4.647 | 63.958 | 0.416 |
| 13 | incursion | concord | 30:00 | 2-0 | CCCCS | 14 | 0.0 / 0.0 | 0 / 56 | 8 / 6 | 0 | 200 | 2.919 | 4.784 | 44.048 | 0.432 |
| 14 | incursion | concord | 30:00 | 1-0 | CCCSS | 17 | 0.0 / 0.0 | 0 / 69 | 8 / 6 | 0 | 185 | 2.866 | 4.911 | 40.894 | 0.424 |
| 15 | incursion | concord | 30:00 | 1-0 | CCCSS | 21 | 0.0 / 0.0 | 0 / 0 | 8 / 8 | 0 | 185 | 2.859 | 5.008 | 20.879 | 0.431 |
| 16 | incursion | concord | 30:00 | 1-0 | CCCSS | 19 | 0.0 / 0.0 | 0 / 68 | 11 / 7 | 0 | 200 | 2.867 | 4.88 | 32.871 | 0.427 |
| 17 | incursion | concord | 30:00 | 1-0 | CCCSS | 10 | 98.9 / 0.0 | 0 / 578 | 14 / 8 | 0 | 196 | 2.371 | 4.635 | 25.722 | 0.417 |
| 18 | incursion | concord | 30:00 | 1-0 | CCCSS | 11 | 63.8 / 0.0 | 0 / 638 | 14 / 6 | 0 | 192 | 2.408 | 4.235 | 33.922 | 0.42 |
| 19 | incursion | syndicate | 30:00 | 0-1 | CCSSS | 18 | 0.0 / 0.0 | 0 / 74 | 9 / 7 | 0 | 200 | 2.96 | 5.168 | 38.222 | 0.442 |
| 20 | uplink_destroyed | concord | 25:13 | 2-0 | CCCCS | 16 | 100.0 / 0.0 | 0 / 190 | 7 / 5 | 0 | 161 | 2.888 | 5.264 | 28.077 | 0.465 |

The ownership column lists S-AI, S-AO, S-MID, S-BO and S-BI in order (C = Concord, S = Syndicate). Flips counts the
ownership changes. Bot ms/tick is the average of `BotCostMeter`.

## Findings

1. **No crashes and no script errors over 20 × 30:00 (≈ 1.08 M server ticks).** No crash fix was needed. The only
   errors are the engine's exit-time leak report (resources, `JoltShape3D`, dummy meshes / materials). It appears
   unchanged in the pre-E14 baseline. It is not a crash, but it should be cleaned up so the soak's error grep is
   empty. Logged as a follow-up.
2. **The M1 end-by-Uplink target is not met (1 / 20).** The front see-saws at the Mid: 10–24 flips per match,
   mostly at S-MID. Outers flip 0–4 times, and **no Inner Generator was destroyed in 20 matches**. Exposure
   came only from the slice's early Outer exposure, from 5:00. Two matches came close: seed 17 at 98.9 %
   after 578 s Exposed, and seed 18 at 63.8 % after 638 s. The siege works when the attackers keep their Outer, but
   they rarely do. Root-cause analysis and the iteration log are in `design/balance/slice-tuning.md` (F1, F2).
3. **The tick budget has headroom.** p95 ≈ 4.9 ms is about 15 % of the tick at 10 heroes + 30–50 Wardlings.
   Occasional single-tick spikes up to 116 ms show up, usually early in a match. Navmesh sync and GC are the
   suspects. They are not frame-visible on a dedicated server, but they should be profiled.
4. **Bot cost is 0.43 ms against 0.4 ms.** This was measured with three matches sharing four cores, so it reads
   high. E11 measured 0.75 ms on the same meter. The changes: 5 Hz decisions (normal profile), cached skill-point
   dry runs, arithmetic `InputCommand.quantize()` with no byte buffer (tested bit-identical to the wire), half-rate
   steering for calm bots, and fewer `Basis` builds in aim. The remaining cost is about 55 % per-tick action and
   45 % decisions; the sensor's ray casts dominate the decisions.
5. **Economy pacing is off the GDD in bot play:** L15 by 10:00, and about 7,800 Lumen at 10:00 against the GDD's
   2,880. This is the E13/E15 finding again, with tasks live. A slice-only rescale that matched the GDD curve
   within 20 % was tried (i3), did not change outcomes, and was reverted. The decision is open (slice-tuning F3).

## Update 2026-10-02 (late): 3v3 slice, short check only

*The owner's budget was nearly spent, so the 20-match soak was **not** re-run at 3v3. The table above is still the
5v5 E14 soak.*

- **Format:** the slice now plays **3v3** through data (`match_rules_slice.tres` `team_size = 3`; Canon C1 slice
  exception). Slice tuning values are unchanged from E14 (Integrity 12,000, respawn 10 + 1.0/min, ×1.5 while
  Exposed, Outer exposes from 5:00, Plant ×0.8, Generator ×0.6). The walk back toward Canon was not done.
- **Short check** (seeds 1–3, `--match-clock 4`, headless): **0 / 3 Uplink kills**. All three ended on Time-out →
  Incursion (Concord 2, Syndicate 1), 4–7 flips each, no Uplink damage. Tick p50 ≈ 2.1 ms, p95 5.5–6.8 ms.
  The match clock ×4 also shortens respawns, so this check says nothing about tempo; it shows the 3v3 build plays to
  End without errors.
- **3v3 at real clock** (6 matches, seeds 201–206, E14 values): **0 / 6 Uplink kills**, all Time-out. The Mid still
  flips 15–22 times per match. Lumen per hero is still far above the GDD curve: ≈3,200 at 5:00, ≈6,050 at 10:00,
  ≈11,200 at 20:00, ≈16,300 at 30:00 (GDD 1,550 / 2,880 / 5,790 / 8,970). Level ≈9 at 5:00 and 15 by ~10:00.
  Lane density alone did not fix the end-by-Uplink target.
- **New finding (S2): heroes fall through the map.** In a diagnostic of 3 real-clock 3v3 matches, 4 bots fell below
  the floor at about z = −104 and z = −237…−254, roughly x = 11–17 and x = −11 (next to the Outer plazas), and kept
  falling with no kill plane. They stay "alive" for the rest of the match: a 3v3 team plays a hero short, and a
  fallen Cell carrier keeps the Cell (it reads "carried" forever). One fallen defender sat on a Defuse job and never
  defused because the zone height check fails. This probably explains part of the stall in both the 5v5 and 3v3
  soaks. Needed: a fix to the map collision gap, and a kill plane (`y < map floor − N` → death and respawn).

## Evidence

- Telemetry: `production/qa/telemetry/m1/match_seed1.json` … `match_seed20.json`
- Task captures: `production/qa/evidence/e14/plant.png`, `production/qa/evidence/e14/breach.png`
