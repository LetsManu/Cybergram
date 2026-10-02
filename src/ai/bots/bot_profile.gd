class_name BotProfile
extends Resource
## One bot difficulty tier (architecture.md §6 BotProfile, ADR-0005 §2-3):
## decision rate, perception, humanised aim and goal weights. Loaded from
## assets/data/ai/bot_profile_<difficulty>.tres. Every number here is a
## PLACEHOLDER tuning value (no GDD table yet); heroes.md §5.1 assumes bot
## accuracy ~0.40, which the normal tier aims for.

@export var id: StringName = &"normal"

@export_group("Decisions")
## Brain decisions per second (aim and movement are emitted every tick).
@export_range(1.0, 30.0, 0.5) var decision_hz: float = 10.0

@export_group("Perception")
@export_range(5.0, 200.0, 1.0) var sight_range_m: float = 70.0
## Full field of view (degrees) for spotting heroes.
@export_range(30.0, 360.0, 1.0) var fov_deg: float = 120.0
## Enemies this close are noticed in any direction (hearing).
@export_range(0.0, 40.0, 0.5) var awareness_m: float = 12.0
## A seen enemy is remembered (last known position) this long.
@export_range(0.0, 20.0, 0.5) var memory_s: float = 3.0

@export_group("Aim (AimHumanizer)")
## Delay between first seeing a target and the first shot.
@export_range(0.0, 2.0, 0.01) var reaction_s: float = 0.35
## Random +- fraction applied to reaction_s per acquisition.
@export_range(0.0, 1.0, 0.05) var reaction_jitter: float = 0.25
## Standard deviation of the steady tracking error (degrees).
@export_range(0.0, 15.0, 0.1) var tracking_error_deg: float = 2.0
## Hard bound on the tracking error (degrees).
@export_range(0.0, 30.0, 0.1) var max_error_deg: float = 5.0
## Extra error on a fresh target, decaying over flick_settle_s (overshoot).
@export_range(0.0, 30.0, 0.1) var flick_error_deg: float = 6.0
@export_range(0.01, 2.0, 0.01) var flick_settle_s: float = 0.35
## Turn rate limit (degrees per second).
@export_range(30.0, 2000.0, 10.0) var turn_rate_deg_s: float = 420.0
## Chance per acquisition (re-rolled every second) to aim at the head.
@export_range(0.0, 1.0, 0.01) var headshot_rate: float = 0.15
## Fire only when the aim is within the target's angular radius times this.
@export_range(0.5, 5.0, 0.1) var fire_tolerance_mult: float = 1.6

@export_group("Combat")
## Engage enemy heroes within this range.
@export_range(5.0, 150.0, 1.0) var engage_range_m: float = 45.0
## Retreat below this HP fraction while threatened; recover above return_hp_frac.
@export_range(0.0, 1.0, 0.01) var retreat_hp_frac: float = 0.3
@export_range(0.0, 1.0, 0.01) var return_hp_frac: float = 0.6
## Seconds without a threat after which a retreat ends even without healing.
@export_range(0.0, 30.0, 0.5) var retreat_calm_s: float = 4.0
## After a retreat that ended still hurt, no new retreat for this long.
@export_range(0.0, 120.0, 1.0) var retreat_cooldown_s: float = 25.0
## Mana: stop firing below this fraction, resume above mana_resume_frac.
@export_range(0.0, 1.0, 0.01) var mana_stop_frac: float = 0.1
@export_range(0.0, 1.0, 0.01) var mana_resume_frac: float = 0.6
## Strafe direction changes every strafe_min_s..strafe_max_s while fighting.
@export_range(0.1, 5.0, 0.05) var strafe_min_s: float = 0.5
@export_range(0.1, 5.0, 0.05) var strafe_max_s: float = 1.2
## Chance per decision to use a skill whose rule is satisfied.
@export_range(0.0, 1.0, 0.01) var skill_use_chance: float = 0.5

@export_group("Goal weights (utility)")
@export_range(0.0, 2.0, 0.01) var w_push: float = 0.5
@export_range(0.0, 2.0, 0.01) var w_defend: float = 0.75
@export_range(0.0, 2.0, 0.01) var w_fight: float = 0.7
@export_range(0.0, 2.0, 0.01) var w_retreat: float = 0.95
@export_range(0.0, 2.0, 0.01) var w_siege: float = 0.85
## E14 Plant: carry / plant / defuse / disperse a Mana Cell.
@export_range(0.0, 2.0, 0.01) var w_cell: float = 1.0
## Added to the current goal's score (hysteresis against flip-flopping).
@export_range(0.0, 1.0, 0.01) var stickiness: float = 0.08

@export_group("Squad")
## Minimum seconds between two squad orders.
@export_range(0.5, 30.0, 0.5) var squad_order_interval_s: float = 2.5
