class_name MatchRulesDef
extends Resource
## Match rule coefficients (architecture.md §6 MatchRulesDef, abridged to what
## E4 uses). The formula lives in RespawnSystem; the numbers live here.

## design/gdd/match-flow-and-map.md F7 (Canon C11): R = min(cap, base + per_min * minutes).
@export_range(0.0, 60.0, 0.1) var respawn_base_s: float = 6.0
@export_range(0.0, 5.0, 0.01) var respawn_per_min_s: float = 0.4
@export_range(0.0, 120.0, 0.1) var respawn_cap_s: float = 30.0
## Slice tuning (E14, design/balance/slice-tuning.md): a team whose Uplink is
## Exposed when the hero dies respawns this much slower (1.0 = C11 as is).
@export_range(1.0, 4.0, 0.05) var exposed_respawn_mult: float = 1.0

## Heroes per team (Canon C1: 5v5). The M1 1-lane slice plays 3v3 so its lane
## density (heroes per lane) matches the full game's ~3.3 (game-concept.md C1,
## design/balance/slice-tuning.md). Read by GameSession and BotDirector.
@export_range(1, 5) var team_size: int = 5

## Safety net: a living hero whose position drops below this height (metres)
## has fallen out of the map and is killed so the normal respawn applies.
## Lanes sit at y ~ 0; the Leyfall void is far below.
@export_range(-500.0, 0.0, 1.0) var kill_plane_y: float = -25.0

## ---- Hardpoint capture (E7; match-flow-and-map.md §3.4, F1-F3, §8 knobs) ----
## C4: AI (Wardling) presence cap per team per hardpoint; heroes are uncapped.
@export_range(0.0, 10.0, 0.1) var ai_presence_cap: float = 3.0
## F2 advantage multiplier M(Δ) = min(m_max, m_intercept + m_slope × Δ).
@export_range(0.0, 2.0, 0.01) var capture_m_intercept: float = 0.4
@export_range(0.0, 1.0, 0.01) var capture_m_slope: float = 0.24
@export_range(0.5, 4.0, 0.05) var capture_m_max: float = 2.0
## K_hl: progress multiplier when no attacking hero is in the zone.
@export_range(0.0, 1.0, 0.05) var heroless_mult: float = 0.5
## Heroless progress cap on Inner hardpoints (§3.4).
@export_range(0.0, 1.0, 0.01) var heroless_inner_cap: float = 0.99
## Overtime window after the last attacker leaves: short, or long if P >= threshold.
@export_range(0.0, 30.0, 0.5) var overtime_short_s: float = 5.0
@export_range(0.0, 30.0, 0.5) var overtime_long_s: float = 10.0
@export_range(0.0, 1.0, 0.01) var overtime_long_threshold: float = 0.75
## F3 decay = mult / (T_base × D_s): no defender / defender in the zone.
@export_range(0.0, 4.0, 0.05) var decay_mult: float = 0.5
@export_range(0.0, 4.0, 0.05) var decay_mult_defended: float = 1.0
## Drain multiplier (× decay) on lost prerequisite and on a neutral Mid swap.
@export_range(0.0, 8.0, 0.1) var drain_mult: float = 2.0
## K_sev: Severed retake duration multiplier.
@export_range(0.1, 1.0, 0.01) var severed_mult: float = 0.75
## Hold T_base per HardpointDef.Tier (INNER, OUTER, MID) used while a Plant or
## Breach node is staged as Hold (M1 staging, §3.7; values from §3.3/§8).
@export var staged_hold_base_s: PackedFloat32Array = PackedFloat32Array([75.0, 65.0, 60.0])
## M1 staging: run every hardpoint as Hold until Plant/Breach ship (§3.7).
## The class default stays on (unit fixtures); the slice .tres turns it off (E14).
@export var stage_all_as_hold: bool = true

## ---- Plant (E14; match-flow-and-map.md §3.4 Plant, F3, §8 knobs) ----
## Cradle pickup: a 1 s interact within cell_interact_radius_m of the Cradle.
@export_range(0.0, 10.0, 0.1) var cell_pickup_s: float = 1.0
@export_range(0.5, 10.0, 0.1) var cell_interact_radius_m: float = 2.5
## A dropped Cell is taken by an attacker touching it, dispersed by a defender
## hero standing on it for cell_disperse_s.
@export_range(0.5, 10.0, 0.1) var cell_touch_radius_m: float = 1.5
@export_range(0.0, 10.0, 0.1) var cell_disperse_s: float = 2.0
## Carrier move speed multiplier (§3.3 table: 5.4 m/s at a 6.0 m/s run).
@export_range(0.5, 1.0, 0.01) var cell_carrier_speed_mult: float = 0.9
## A dropped Cell lies this long; the Cradle refills this long after a Cell is lost.
@export_range(0.0, 120.0, 0.5) var cell_drop_life_s: float = 15.0
@export_range(0.0, 120.0, 0.5) var cradle_respawn_s: float = 10.0
## Plant and defuse channels (interact held, inside the zone; not scaled by D_s).
@export_range(0.0, 30.0, 0.1) var plant_channel_s: float = 3.0
@export_range(0.0, 30.0, 0.1) var defuse_channel_s: float = 6.0
## F3: charge runs at this fraction while Pres(att) < Pres(def).
@export_range(0.0, 1.0, 0.05) var plant_outnumbered_mult: float = 0.5

## Slice tuning (E14, design/balance/slice-tuning.md): multiplies every Plant
## T_base from the MapDef (1.0 = the map's §3.3 values).
@export_range(0.25, 2.0, 0.01) var plant_base_mult: float = 1.0

## ---- Breach (E14; match-flow-and-map.md §3.4 Breach, F4, §8 knobs) ----
## Slice tuning (E14): multiplies every Generator HP_base from the MapDef.
@export_range(0.25, 2.0, 0.01) var generator_hp_mult: float = 1.0
## Wardling hits on a Generator count this fraction (as on the Uplink, C7).
@export_range(0.0, 1.0, 0.05) var generator_wardling_damage_scale: float = 0.5
## Regeneration: after this long without attacker damage, this fraction of max HP per second.
@export_range(0.0, 60.0, 0.5) var generator_regen_delay_s: float = 8.0
@export_range(0.0, 1.0, 0.005) var generator_regen_frac_s: float = 0.04
## Phase 2 at P = 0 with no attacker for this long: the Generator respawns at full HP.
@export_range(0.0, 120.0, 0.5) var breach_reset_idle_s: float = 15.0
## Generator hit volume (greybox core): radius and height above the zone floor.
@export_range(0.1, 5.0, 0.1) var generator_hit_radius_m: float = 1.2
@export_range(0.5, 10.0, 0.1) var generator_hit_height_m: float = 2.4
## §3.5 rewards (emitted as ObjectiveEvents; no economy yet). A participant was
## in the zone during the last participant_window_s.
@export_range(0.0, 60.0, 0.5) var participant_window_s: float = 10.0
@export var lumen_capture_participant: int = 120
@export var lumen_capture_team: int = 40
@export var lumen_defence: int = 60
## A defence pays when P decays from >= this to 0.
@export_range(0.0, 1.0, 0.05) var defence_threshold: float = 0.5
## PLACEHOLDER: Resonance (EXP) amounts are owned by the progression GDD (C13).
@export var exp_capture_placeholder: int = 0
@export var exp_defence_placeholder: int = 0

## ---- Match flow and Uplink (E9; match-flow-and-map.md §3.1, §3.6, F5, F6, F8) ----
## Deploy ends (Mids unlock, Skirmish starts) at this match time.
@export_range(0.0, 600.0, 1.0) var deploy_end_s: float = 60.0
## Surge start times (Surge I, Surge II) and their task-duration multiplier D_s (F5).
## A Surge at or after time_cap_s never starts.
@export var surge_times_s: PackedFloat32Array = PackedFloat32Array([900.0, 1800.0])
@export var surge_task_scale: PackedFloat32Array = PackedFloat32Array([0.85, 0.70])
## Mana Drought: from here an enemy-held Outer also exposes an Uplink (F6, C7).
@export_range(0.0, 7200.0, 1.0) var drought_time_s: float = 2700.0
## Slice tuning (E14): from this match time an enemy-held Outer also exposes an
## Uplink without entering the Drought phase (< 0 = off: only Drought does).
@export_range(-1.0, 7200.0, 1.0) var outer_exposure_from_s: float = -1.0
## Hard cap -> Time-out (C8). Standard 60:00; the M1 slice overrides 30:00.
@export_range(60.0, 7200.0, 1.0) var time_cap_s: float = 3600.0
## C7: Uplink Integrity, and the Wardling damage scale against it.
@export var uplink_integrity: float = 33000.0
@export_range(0.0, 1.0, 0.05) var uplink_wardling_damage_scale: float = 0.5
## C9 tie-break: the higher Uplink damage % wins if the gap is at least this.
@export_range(0.0, 10.0, 0.1) var uplink_tiebreak_min_pct: float = 1.0
## C10 Sudden Death after a tied Incursion. Not built in M1 (slice: a tie is a draw).
@export var sudden_death_enabled: bool = false
## Uplink hit volume around HqDef.uplink (greybox spire + core, see the slice map):
## vertical capsule radius and its bottom / top heights above the Uplink floor.
@export_range(0.1, 10.0, 0.1) var uplink_hit_radius_m: float = 1.7
@export_range(0.0, 20.0, 0.1) var uplink_hit_bottom_m: float = 1.5
@export_range(0.0, 30.0, 0.1) var uplink_hit_top_m: float = 10.5
