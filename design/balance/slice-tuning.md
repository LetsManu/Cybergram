# M1 Slice Tuning (Shardline Causeway)

*Created 2026-10-02 by E14 (gameplay-programmer with systems-designer / qa-lead).*
*Scope: the M1 slice only. Every value here lives in a slice `.tres`. Canon and the full-game
defaults (`MatchRulesDef` / `EconomyRulesDef` class defaults, `design/gdd/*`) are unchanged, and
the tests check them separately (`MatchRulesDef.new()` = Canon C7 / C11).*

## Why the slice deviates

Shardline Causeway is one lane. All 10 heroes and both Vanguard waves meet on it, so every
fight is 5v5 at the same choke. In bot-vs-bot play with mirror profiles, the Canon tempo
values gave 8 of 8 time-outs in E11 and 0 of 3 Uplink kills once Plant/Breach went live (v1
below). The deviations in this doc aim at three things:

1. A won fight converts into ground: a longer respawn, and a slower one for a team whose
   Uplink is Exposed.
2. Tasks short enough to finish inside that window: Plant and Generator HP.
3. The siege can end the match: lower Integrity, and an Outer also exposes the Uplink from 5:00.

Bot profiles stay mirrored (fair teams). There is no profile asymmetry.

## Final slice values (`assets/data/match/match_rules_slice.tres`)

| Knob | Canon / map value | Slice value | GDD safe range | Reason |
| ---- | ---- | ---- | ---- | ---- |
| `stage_all_as_hold` | (M1 staging) on | **off** | — | E14: Breach / Plant / Hold / Plant / Breach goes live (M1 exit layout) |
| `respawn_base_s` (R_0) | 6 | **10** | 4–10 | A wipe must open a window: 10 s at 0:00 |
| `respawn_per_min_s` (k) | 0.4 | **1.0** | 0.3–0.5 (**outside**) | The slice is capped at 30:00, so k = 1.0 reaches the 30 s cap at 20:00. The full game reaches it at 60:00 |
| `respawn_cap_s` | 30 | 30 | 25–35 | unchanged |
| `exposed_respawn_mult` *(new, slice-only rule)* | 1.0 | **1.5** | — | Defenders respawn 25 m behind their Uplink. A slower respawn while Exposed is the "defender respawn distance" lever as a timer |
| `uplink_integrity` | 33,000 (C7) | **12,000** | 20,000–40,000 (**outside**) | Measured bot siege DPS while Exposed is ≈40 DPS (i5: 48 % of 20,000 in 229 s), not the F9 557 DPS |
| `outer_exposure_from_s` *(new)* | off (Drought 45:00) | **300 s** | — | Compresses the full game's Drought (Outer exposes) into the 30:00 slice. Without it, 0 of 9 matches had any exposure |
| `plant_base_mult` *(new)* | 1.0 (Outer Plant 75 s) | **0.8** (60 s) | 60–90 | Lowest C4 value. The Plant must finish inside a respawn window |
| `generator_hp_mult` *(new)* | 1.0 (6,000) | **0.6** (3,600) | 3,500–8,000 | i2 seed 202: 10.5 k Generator damage landed over the match, but regen restored it each time |

**Economy:** unchanged in the slice (`economy_rules_slice.tres`: GDD values plus the §26 trickle of 60).
See finding F3.

**Bot data** (`assets/data/ai/bot_profile_*.tres`, `BotProfile` defaults; AI tuning, not game rules):
- `decision_hz` is easy 4, normal 5, hard 6 (it was 10 for all; ADR-0005 default is 5).
- `w_siege` 0.85 → 1.15, above Defend's 1.125 ceiling.
- New: `w_cell` 1.0, `w_push_commit` 0.4 within 35 m, `defend_falloff_m` 120 (it was 200 m with a 0.3 floor),
  `defend_carrier_radius_m` 40, `objective_focus_m` 12, `siege_range_m` 14 (the siege spot was ≈48 m away),
  `beacon_spawn` on, and siege regroup (3 allies, 50 m stage, 30 m commit).

## Iteration log

Seeds 201–203 unless noted. All matches use real clock scale 1.0 (`--match-clock` would shorten
respawns and invalidate the tempo).

| Iter | Change | Uplink kills | Exposed (s, per match) | Generators destroyed | Notes |
| ---- | ---- | ---- | ---- | ---- | ---- |
| base | E11 baseline (Hold-only, 10 Hz), seed 101 | 0/1 | 0 | — | Mid flipped 15×. L15 by 10:00. Lumen 8,964 at 10:00 (GDD 2,880) |
| v1 | Plant/Breach live, Canon data (seeds 101–103) | 0/3 | 0 / 0 / 0 | 0 | 5–8 Cells planted per match, about 75 % defused |
| i1 | R 10 + 0.5 m, Integrity 20 k, siege spot 14 m, bots 5 Hz | 0/3 | 0 | 0 | Bot cost 0.81 → 0.58 ms |
| i2 | k 1.0, bots spawn at the Mid Beacon when pushing | 0/3 | 0 | 0 | 202: 10.5 k Generator damage, never destroyed (regen) |
| i3 | Plant ×0.8, Generator ×0.6, Outer exposes from 10:00, economy ×0.25 (kills) / ×0.4 (Wardlings) | 0/3 | 0 / 100 / 0 | 0 | Economy back on the GDD curve (F3). 100 s Exposed, 0 damage |
| i4 | Bot objective focus 12 m | 0/3 | 0 / 106 / 325 | 0 | Best: 9.6 % Uplink damage |
| i5 | `w_siege` 1.15, Defend fall-off, carrier radius | 0/3 | 81 / 229 / 88 | 0 | 202: **48 %** of 20 k in 229 s |
| probe | 5 bots sieging an Exposed Uplink with 5 defenders home | — | — | — | Attackers lose 15:1 to 15:4 at the gate (choke, defender squads); Integrity −1.2 to −2 k |
| i6 | Integrity 12 k, Outer from 5:00, ×1.5 Exposed respawn, regroup, focus off, economy reverted | 0/3 | 0 / 159 / 67 | 0 | Focus off: 2 % damage; restored to 12 m |
| **soak** | **final values above (seeds 1–20)** | **1/20** (seed 20, 25:13) | Exposed in 14/20; max 578 / 638 s | 0 | Seed 17 reached 98.9 %. Tick p95 4.9 ms. See `production/qa/m1-soak-report.md` |

## Findings

- **F1. The Mid ping-pong is the stall.** In every iteration the Mid flips 15–25 times per match.
  Outers flip 0–4 times, and the Inner Generator fell in 0 of 30+ matches. With mirror bots each
  fight is a coin flip, and the defender of any node beyond the Mid fights next to its
  Sanctum and squads. A won Mid fight rarely chains into Outer → Inner → Uplink.
- **F2. Sieges are lost at the gate.** Attackers enter the enemy HQ through one 16 m gate into
  five defenders who respawn 25 m away with fresh squads. They lose those fights about 4:1. A
  siege damages the Uplink only in the gaps between defender respawns.
- **F3. Economy pacing (slice).** Bots run kill + assist income about 7× and Wardling bounty income about 2.6×
  the GDD §18 per-player model. All 10 heroes are in one lane, so heroes reach L15 at about 10:00.
  i3 scaled the slice bounties (kills / assists ×0.25, Wardlings ×0.4). The result was 3,432 Lumen / L8.6 at
  10:00 and 6,106 / L12.8 at 20:00 (GDD 2,880 / L7 and 5,790 / L11), with no effect on the end reasons.
  It was reverted for two reasons: it did not move the target, and `economy_curve_test` asserts that the slice
  data stays on the GDD curve under the GDD's activity model. **Open for the systems-designer:** decide
  whether the slice economy is tuned to bot activity (the i3 values above) or stays on the GDD model.
- **F4. Not tried (they need design approval):** asymmetric bot profiles (excluded by brief), Sudden Death /
  Stagnation in the slice (the Stagnation ×0.85 rule is not implemented), and a second spawn exit
  or HQ geometry change.

## 3v3 tuning attempt (2026-10-04, after the M1 3v3 switch)

Four bot matches per variant (seeds 1-4, real clock, `--match-rules` overrides). Nothing was adopted.
The slice values above are unchanged.

| Variant | Change vs slice | Uplink kills | Cells planted / defused | Outer flips | Max Uplink dmg |
| ---- | ---- | ---- | ---- | ---- | ---- |
| base | current slice values, 3v3 | 0/4 | 27 / 25 | 2 | 0 % |
| C2 | Plant ×0.5, defuse 9 s, Integrity 7,200, Generator regen 1.5 %/s after 12 s, Exposed respawn ×2.0, Wardling Uplink dmg ×1.0 | 0/4 | 34 / 22 | 12 | 58.7 % |
| C3 | C2 + Integrity 4,000, Exposed respawn ×2.5 | 0/4 | 32 / 14 | 18 | 52.8 % |
| final | C2 without the Integrity / Wardling changes | 0/4 | 26 / 22 | 4 | 0 % |

- **F5. At 3v3 the front never passes the Mid.** The Mid flips 14-21 times per match. Almost every
  planted Cell is defused (25 of 27 at base), so the Outers do not fall and the Uplink is never Exposed.
- **F6. Bots do not siege.** The Siege goal share is about 0 % even while an Uplink is Exposed. C2/C3
  exposed an Uplink in most matches, but the damage stayed at 0-59 % and an Outer is retaken in about
  1 minute.
- **F7. Four seeds per variant is too noisy.** "final" differs from C2 only in Uplink knobs that cannot
  affect Plants, yet its Plant numbers fell back to the baseline. The C2/C3 gains are within the noise.
  A real comparison needs about 12-20 seeds per variant (about 15-25 min of CPU on 4 cores per variant).
- **Not adopted, and why:** a low Integrity only helps bots. A human team (about 150 DPS per hero)
  would kill a 4,000-HP Uplink in seconds. The bot-only goal needs AI work instead: siege commitment
  while Exposed, and defuse contesting. That is the recommended next step, not more rule tuning.

