class_name UplinkSim
extends Node3D
## One team's Mana Uplink, server-side (architecture.md §5.5; match-flow-and-map.md
## §3.6, Canon C7). Integrity is permanent: there is no regen and heal() is
## rejected. Damage counts only while `exposed` is true on the tick it lands
## (MatchRules recomputes exposure every tick after the hardpoints step).
## Wardling hits are scaled by MatchRulesDef.uplink_wardling_damage_scale (C7: 0.5).
## Ammo / status effects never apply: only the raw amount is used (C7).
##
## The node sits at the aim point (the core) so Wardling targeting helpers that
## read global_position work; `base` is the floor position from HqDef.uplink.

signal integrity_changed(value: float)
signal exposure_changed(exposed: bool)
signal destroyed()

const KIND_UPLINK: int = 3

## Team that owns (defends) this Uplink.
var team: int = 0
var max_integrity: float = 33000.0
var integrity: float = 33000.0
var exposed: bool = false
var net_id: int = 0
## Floor position (HqDef.uplink).
var base: Vector3 = Vector3.ZERO
var wardling_scale: float = 0.5
var hit_radius: float = 1.7
var hit_bottom: float = 1.5
var hit_top: float = 10.5
## Hits that landed while sealed (dropped server-side; ImmuneHit cue).
var immune_hits: int = 0


func setup(team_: int, base_pos: Vector3, rules: MatchRulesDef) -> void:
	team = team_
	base = base_pos
	max_integrity = rules.uplink_integrity
	integrity = max_integrity
	wardling_scale = rules.uplink_wardling_damage_scale
	hit_radius = rules.uplink_hit_radius_m
	hit_bottom = rules.uplink_hit_bottom_m
	hit_top = rules.uplink_hit_top_m
	position = aim_point()


func is_destroyed() -> bool:
	return integrity <= 0.0


## Applies a hit. Returns the Integrity removed (0 while sealed or destroyed).
func apply_damage(amount: float, from_wardling: bool = false) -> float:
	if is_destroyed() or amount <= 0.0:
		return 0.0
	if not exposed:
		immune_hits += 1
		return 0.0
	var a := minf(amount * (wardling_scale if from_wardling else 1.0), integrity)
	integrity -= a
	integrity_changed.emit(integrity)
	if integrity <= 0.0:
		integrity = 0.0
		destroyed.emit()
	return a


## Permanence (C7): heal effects are rejected. Always returns 0.
func heal(_amount: float) -> float:
	return 0.0


func set_exposed(v: bool) -> void:
	if v != exposed:
		exposed = v
		exposure_changed.emit(v)


## Damage dealt to this Uplink as a % of max Integrity (the C9 tie-break U).
func removed_pct() -> float:
	return 100.0 * (max_integrity - integrity) / maxf(max_integrity, 1.0)


## Where shooters aim (the core).
func aim_point() -> Vector3:
	return base + Vector3(0.0, (hit_bottom + hit_top) * 0.5, 0.0)


## Ray distance to the hit volume, or -1.
func ray_hit(origin: Vector3, dir: Vector3) -> float:
	return HitscanTracer.ray_vertical_capsule(origin, dir, base.y + hit_bottom + hit_radius,
		base.y + maxf(hit_top - hit_radius, hit_bottom + hit_radius), Vector2(base.x, base.z), hit_radius)


## Bolt candidate capsule [self, feet, radius, height] (ProjectileSystem format).
func bolt_capsule() -> Array:
	return [self, base + Vector3(0.0, hit_bottom, 0.0), hit_radius, hit_top - hit_bottom]
