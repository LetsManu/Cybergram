class_name MatchRulesDef
extends Resource
## Match rule coefficients (architecture.md §6 MatchRulesDef, abridged to what
## E4 uses). The formula lives in RespawnSystem; the numbers live here.

## design/gdd/match-flow-and-map.md F7 (Canon C11): R = min(cap, base + per_min * minutes).
@export_range(0.0, 60.0, 0.1) var respawn_base_s: float = 6.0
@export_range(0.0, 5.0, 0.01) var respawn_per_min_s: float = 0.4
@export_range(0.0, 120.0, 0.1) var respawn_cap_s: float = 30.0

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
@export var stage_all_as_hold: bool = true
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
