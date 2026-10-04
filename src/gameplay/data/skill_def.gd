class_name SkillDef
extends Resource
## One hero skill (ADR-0004, architecture.md §7.2): targeting + effect list +
## base numbers. Base numbers are the Unlock (basic) / Rank 1 (ultimate) values
## of design/gdd/heroes.md §4; Boost/Fork/Mastery/Ult ranks are `nodes`
## (Modifiers on this skill's StatBlock), never new code.

enum TargetMode {
	SELF,           ## centred on the caster
	GROUND,         ## aimed point on the floor within `range`
	PROJECTILE,     ## aimed direction; an effect launches the projectile
	DIRECTION,      ## flat facing direction (dashes)
	ALLY_WARDLING,  ## an own / conducted Wardling under the crosshair within `range`
	GADGET,         ## W9-H2 Relay Hop: an allied gadget or a Malfunctioning enemy gadget under the crosshair
}

@export var id: StringName = &""
@export var display_name: String = ""
## 2-4 character HUD icon label (greybox icons).
@export var short_label: String = ""
@export var ultimate: bool = false
## heroes.md §3.5: basics 1, ultimate Rank 1 at 6.
@export_range(1, 15) var required_level: int = 1
@export var targeting: TargetMode = TargetMode.SELF
## StatCatalog.SKILL_PARAMS name -> base value (seconds, metres, HP, fractions).
@export var params: Dictionary = {}
## heroes.md §3.4: true = the cooldown starts when the effect ends (walls,
## stances); the active time is the `active_param` param unless an effect
## (a deployable) ends it first.
@export var cooldown_on_end: bool = false
@export var active_param: StringName = &"duration"
## Cast/channel cancelled by Stun (50% cooldown, heroes.md §3.4).
@export var interruptible: bool = false
## Run on the target set when the cast completes (EffectDef resources).
@export var effects: Array[Resource] = []
## Run on a second press while the skill's deployable lives (Rally Beacon
## double-tap). Costs no cooldown.
@export var recast_effects: Array[Resource] = []
## Boost / Fork / Mastery / Ult-rank nodes (data for E15).
@export var nodes: Array[SkillNodeDef] = []


func param(name: StringName) -> float:
	return float(params.get(name, 0.0))
