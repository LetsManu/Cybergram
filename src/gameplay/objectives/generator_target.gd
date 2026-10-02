class_name GeneratorTarget
extends Node3D
## Targetable body of one Breach hardpoint's Ward Generator, server-side
## (match-flow-and-map.md §3.4 Breach, F4). The rules live in HardpointSim;
## this node gives the Generator a NetId, a hit volume and a team so hero
## hitscan, Wardling bolts, squad Attack orders and bots can aim at it the way
## they aim at an Uplink. The node sits on the zone floor at the Generator.

const KIND_GENERATOR: int = 4

var hp_sim: HardpointSim
var net_id: int = 0
var hit_radius: float = 1.2
var hit_height: float = 2.4

## The defending team (the hardpoint owner).
var team: int:
	get:
		return hp_sim.owner if hp_sim != null else MapDef.TEAM_NEUTRAL


func setup(h: HardpointSim, rules: MatchRulesDef) -> void:
	hp_sim = h
	name = "Generator_%s" % h.def.id
	hit_radius = rules.generator_hit_radius_m
	hit_height = rules.generator_hit_height_m
	position = h.def.position


## Standing (phase 1, owned): shootable by the eligible attacker.
func is_up() -> bool:
	return hp_sim != null and hp_sim.owner != MapDef.TEAM_NEUTRAL and hp_sim.breach_phase == 1


func attackable_by(t: int) -> bool:
	return hp_sim != null and hp_sim.generator_attackable_by(t)


func aim_point() -> Vector3:
	return global_position + Vector3(0.0, hit_height * 0.5, 0.0)


## Ray distance to the hit volume, or -1.
func ray_hit(origin: Vector3, dir: Vector3) -> float:
	var p := global_position
	return HitscanTracer.ray_vertical_capsule(origin, dir, p.y + hit_radius,
		p.y + maxf(hit_height - hit_radius, hit_radius), Vector2(p.x, p.z), hit_radius)


## Bolt candidate capsule [self, feet, radius, height] (ProjectileSystem format).
func bolt_capsule() -> Array:
	return [self, global_position, hit_radius, hit_height]
