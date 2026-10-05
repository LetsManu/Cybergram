class_name DamageFeedbackModel
extends RefCounted
## Damage feedback state (W16-COMFORT): the direction indicator (arc segments on
## a ring around the screen centre, pointing at the attacker and following the
## view while they fade) and the red damage vignette. Pure logic, no nodes.
##
## Comfort: `fx` is the Screen effects intensity (0..1) and `reduce` the Reduce
## motion flag. Pulsing (extra brightness and width right after a hit) needs
## fx > 0 and not `reduce`. At fx = 0 the indicator stays (gameplay-critical)
## but static: a plain fade at `indicator_min_alpha`; the vignette becomes a thin
## static edge tint instead of a full-screen flash.
##
## Usage: model.hit(amount, max_hp, attacker_pos_or_null); model.step(dt);
## then per indicator: relative_angle(), indicator_alpha(), indicator_width_px().

var rules: ComfortRulesDef
## Active indicators: {has_dir: bool, pos: Vector3, age: float, strength: float}.
var indicators: Array[Dictionary] = []
const MAX_INDICATORS: int = 8
## Damage vignette: strength of the latest hit (0..1) and its age (seconds).
var vig_strength: float = 0.0
var vig_age: float = INF


func _init(r: ComfortRulesDef = null) -> void:
	rules = r if r != null else ComfortRulesDef.new()


## Strength 0..1 of a hit: `amount` HP of `max_hp`, big at `big_hit_hp_frac`.
func strength_of(amount: float, max_hp: float) -> float:
	var big := maxf(max_hp * rules.big_hit_hp_frac, 1.0)
	return clampf(amount / big, rules.indicator_min_strength, 1.0)


## Registers damage. `attacker` is the attacker's world position (Vector3), or
## null for environment / self / unattributed damage (a non-directional pulse).
func hit(amount: float, max_hp: float, attacker: Variant = null) -> void:
	if amount <= 0.0:
		return
	var st := strength_of(amount, max_hp)
	indicators.append({"has_dir": attacker is Vector3, "pos": attacker if attacker is Vector3 else Vector3.ZERO,
		"age": 0.0, "strength": st})
	while indicators.size() > MAX_INDICATORS:
		indicators.pop_front()
	if st >= vig_strength * vignette_fade() or vig_age == INF:
		vig_strength = st
		vig_age = 0.0


func step(dt: float) -> void:
	for i in range(indicators.size() - 1, -1, -1):
		indicators[i].age += dt
		if indicators[i].age >= rules.indicator_fade_s:
			indicators.remove_at(i)
	if vig_age != INF:
		vig_age += dt
		if vig_age >= rules.damage_vignette_fade_s:
			vig_age = INF
			vig_strength = 0.0


## Angle of the attacker on the screen ring: 0 = up (in front), +90 deg = right,
## 180 = behind, -90 = left (radians, -PI..PI), for a viewer at `own` looking
## along `yaw` (Godot yaw: forward = (-sin, 0, -cos)).
static func relative_angle(own: Vector3, yaw: float, attacker: Vector3) -> float:
	var dx := attacker.x - own.x
	var dz := attacker.z - own.z
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var d := Vector2(dx, dz)
	return atan2(d.dot(right), d.dot(fwd))


## World position `dist` m from `own` in the direction `rel` (see relative_angle).
static func world_pos_at(own: Vector3, yaw: float, rel: float, dist: float = 10.0) -> Vector3:
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var d := (fwd * cos(rel) + right * sin(rel)) * dist
	return Vector3(own.x + d.x, own.y, own.z + d.y)


## True when pulsing is allowed (effects above 0 and Reduce motion off).
static func pulsing(fx: float, reduce: bool) -> bool:
	return fx > 0.0 and not reduce


## 1 right after a hit, 0 after the pulse time; 0 whenever pulsing is off.
func punch(age: float, fx: float, reduce: bool) -> float:
	if not pulsing(fx, reduce):
		return 0.0
	return clampf(1.0 - age / rules.indicator_pulse_s, 0.0, 1.0) * fx


func indicator_alpha(ind: Dictionary, fx: float, reduce: bool) -> float:
	var fade := clampf(1.0 - float(ind.age) / rules.indicator_fade_s, 0.0, 1.0)
	var base := lerpf(rules.indicator_min_alpha, 1.0, clampf(fx, 0.0, 1.0)) * lerpf(0.6, 1.0, float(ind.strength))
	return clampf(base * fade * (1.0 + 0.5 * punch(ind.age, fx, reduce)), 0.0, 1.0)


func indicator_width_px(ind: Dictionary, fx: float, reduce: bool) -> float:
	var w := lerpf(rules.indicator_width_min_px, rules.indicator_width_max_px, float(ind.strength))
	return w * (1.0 + 0.5 * punch(ind.age, fx, reduce))


func indicator_half_arc_rad(ind: Dictionary) -> float:
	return deg_to_rad(lerpf(rules.indicator_arc_half_deg_min, rules.indicator_arc_half_deg_max, float(ind.strength)))


func vignette_fade() -> float:
	if vig_age == INF:
		return 0.0
	return clampf(1.0 - vig_age / rules.damage_vignette_fade_s, 0.0, 1.0)


## Edge alpha of the damage vignette. At 0% effects: a thin static tint.
func vignette_alpha(fx: float, reduce: bool) -> float:
	var fade := vignette_fade()
	if fade <= 0.0:
		return 0.0
	if fx <= 0.0:
		return rules.damage_static_alpha * vig_strength * fade
	return clampf(rules.damage_vignette_max_alpha * vig_strength * fx * fade \
		* (1.0 + 0.4 * punch(vig_age, fx, reduce)), 0.0, 1.0)


## Inner radius of the vignette (a high value = a thin edge band).
func vignette_inner(fx: float) -> float:
	return rules.damage_static_inner if fx <= 0.0 else rules.damage_vignette_inner
