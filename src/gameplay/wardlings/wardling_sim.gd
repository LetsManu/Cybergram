class_name WardlingSim
extends CharacterBody3D
## Server-side Wardling body (architecture.md §10, ADR-0005 §5). Holds HP and
## INTENTS only; brains in src/ai write intents through the set_* methods and
## WardlingWorld integrates movement, firing and damage every tick.
## Kinematic: positioned directly along navmesh paths (no move_and_slide), on a
## per-team collision layer so enemy heroes are body-blocked (§9.3) and allies
## pass through.

const LAYER_TEAM0: int = 4
const LAYER_TEAM1: int = 8

## Replicated display flags (squad strip badges).
const FLAG_COMBAT: int = 1
const FLAG_RETURNING: int = 2

var net_id: int = 0
var def: WardlingDef
var team: int = 0
## Owning hero (0 = ownerless Vanguard).
var owner_net_id: int = 0
var squad: Squad
var wave: VanguardWave
var health: HealthComponent
var dead: bool = false
## Net id of the killer (0 = dissolved / unknown).
var killer_id: int = 0
var spawned_tick: int = 0
## Surge tier I-III at mint time (WardlingWorld.tier; replicated for the model).
var tier: int = 1
var yaw: float = 0.0
## Presence seam (E7 PresenceSource duck typing: team, presence_weight,
## global_position, is_alive()). Registered by WardlingWorld while alive.
var presence_weight: float:
	get:
		return def.presence if def != null else 0.0

## --- Intents (written by brains) ---
var has_move_target: bool = false
var move_target: Vector3 = Vector3.ZERO
var move_speed: float = 0.0
var arrive_radius: float = 0.0
var attack_target_id: int = 0
var focused: bool = false
## The brain's latest LOS check to the target passed (no fire without LOS).
var fire_clear: bool = false
var display_flags: int = 0
## Brain state code (diagnostics only).
var brain_state: int = 0

## --- Movement internals (WardlingWorld) ---
var path: PackedVector3Array = PackedVector3Array()
var path_index: int = 0
var path_goal: Vector3 = Vector3.INF
var path_pending: bool = false
var desired_velocity: Vector3 = Vector3.ZERO
var safe_velocity: Vector3 = Vector3.ZERO
var safe_frame: int = -1
var agent: RID
var fire_cooldown: int = 0
var stuck_ticks: int = 0

## --- E10 Minionmancer hooks (wardlings-and-economy.md §13; MinionmancerHooks) ---
## Elite (Rewrite) until this tick, -1 = not Elite.
var elite_until_tick: int = -1
## Turned (subvert) until this tick, -1 = own allegiance.
var turned_until_tick: int = -1
var turned_from_team: int = -1
var turned_from_owner: int = 0
var turned_from_squad: Squad
var turned_from_wave: VanguardWave
## Overflow member of a squad (subverted: no slot, no capacity).
var overflow: bool = false
## Stalled / stunned until this tick (no move, no fire).
var stun_until_tick: int = -1
## apply_squad_modifier buckets: source id -> [bucket, mult, expires_tick].
var squad_mods: Dictionary = {}

## Damage memory (retaliation, LOD).
var last_attacker_id: int = 0
var last_hit_tick: int = -1000000
## E13 share list (§15.1): source net id -> last tick it damaged this Wardling.
var hit_by: Dictionary = {}


static func layer_for_team(t: int) -> int:
	return LAYER_TEAM0 if t == 0 else LAYER_TEAM1


func setup(d: WardlingDef, team_: int, pos: Vector3) -> void:
	def = d
	team = team_
	health = HealthComponent.new(d.max_hp, d.armor, team_)
	collision_layer = layer_for_team(team_)
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = d.radius
	capsule.height = maxf(d.height, d.radius * 2.0)
	shape.shape = capsule
	shape.position.y = capsule.height / 2.0
	add_child(shape)
	position = pos


## Walk (or sprint) to `pos` and stop within `arrive`.
func set_move_target(pos: Vector3, speed: float, arrive: float) -> void:
	has_move_target = true
	move_target = pos
	move_speed = speed
	arrive_radius = arrive


## Follow a precomputed (shared) path, e.g. a wave's march route.
func set_path(p: PackedVector3Array, speed: float, arrive: float) -> void:
	if p.is_empty():
		stop()
		return
	path = p
	path_index = 0
	path_goal = p[p.size() - 1]
	path_pending = false
	has_move_target = true
	move_target = path_goal
	move_speed = speed
	arrive_radius = arrive


func stop() -> void:
	has_move_target = false
	move_speed = 0.0


func set_attack_target(target_id: int, focus: bool, los_clear: bool) -> void:
	attack_target_id = target_id
	focused = focus
	fire_clear = los_clear


func clear_attack() -> void:
	attack_target_id = 0
	fire_clear = false


func set_display_flags(f: int) -> void:
	display_flags = f


func is_alive() -> bool:
	return not dead and is_instance_valid(self)


func chest() -> Vector3:
	return global_position + Vector3(0.0, def.chest_m, 0.0)


func _on_safe_velocity(v: Vector3) -> void:
	safe_velocity = v
	safe_frame = Engine.get_physics_frames()
