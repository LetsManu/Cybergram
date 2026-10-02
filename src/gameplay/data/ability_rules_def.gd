class_name AbilityRulesDef
extends Resource
## Shared skill rules (design/gdd/heroes.md §3.4, §3.6; tuning knobs §9).
## Defaults are the GDD values; no .tres needed unless tuned.

## §3.4: shared lockout between any two skill casts.
@export_range(0.0, 2.0, 0.01) var lockout_s: float = 0.25
## §3.4: external cooldown reduction cap.
@export_range(0.0, 1.0, 0.01) var cdr_cap: float = 0.25
## §3.4: minimum effective cooldown, basic / ultimate.
@export_range(0.0, 30.0, 0.5) var min_cooldown_basic_s: float = 3.0
@export_range(0.0, 200.0, 0.5) var min_cooldown_ult_s: float = 45.0
## §3.4: a cast cancelled by Stun/Silence goes on this fraction of its cooldown.
@export_range(0.0, 1.0, 0.05) var interrupt_cooldown_frac: float = 0.5
## §3.6: total move-speed reduction from all slows is capped.
@export_range(0.0, 1.0, 0.01) var slow_cap: float = 0.40
## §3.6: same-type hard CC diminishing returns window and duration factors.
@export_range(0.0, 20.0, 0.5) var cc_dr_window_s: float = 4.0
@export var cc_dr_factors: PackedFloat32Array = PackedFloat32Array([1.0, 0.5, 0.0])
## §3.3: SkillPower(L) = 1 + k × (L − 1).
@export_range(0.0, 0.1, 0.001) var skill_power_per_level: float = 0.02
