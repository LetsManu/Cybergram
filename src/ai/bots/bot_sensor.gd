class_name BotSensor
extends RefCounted
## LOS/FOV-gated perception for one bot (architecture.md §9 BotSensor,
## ADR-0005: no omniscience). An enemy hero is seen if it is within sight
## range, inside the field of view (or within the awareness radius, or it just
## hit the bot) and a ray to its chest is clear of map geometry. Enemy
## Wardlings within WARDLING_RANGE_M and an Exposed enemy Uplink in range are
## checked the same way. Picks the fight target: heroes, then the Uplink while
## it is Exposed, then the enemy Ward Generator (E14), then Wardlings. While
## sieging (or standing in the Breach zone) the Uplink / Generator outranks
## heroes farther than BotProfile.objective_focus_m while the bot is not under
## fire (E14). Ray count per scan is bounded (MAX_RAYS).

const CHEST_Y: float = 1.1
const HEAD_Y: float = 1.6
const WARDLING_RANGE_M: float = 30.0
const UPLINK_RANGE_M: float = 75.0
const MAX_RAYS: int = 8

var server: ServerWorld
var profile: BotProfile
var rays_last_scan: int = 0
## net id -> [last seen position, tick] (memory_s).
var memory: Dictionary = {}
## Target picked by the last scan, its kind, aim point and visibility.
var target: Node3D = null
var target_visible: bool = false

var _ray := PhysicsRayQueryParameters3D.new()
var _rays_left: int = 0


func _init(s: ServerWorld, p: BotProfile) -> void:
	server = s
	profile = p
	_ray.collision_mask = HeroBody.LAYER_WORLD


## Scans from hero `h` looking along `look_yaw`; fills `bb` target fields.
func scan(h: HeroBody, look_yaw: float, bb: BotBlackboard, prefer_uplink: bool) -> void:
	_rays_left = MAX_RAYS
	var team := h.combat.team
	var eye := h.state.position + Vector3(0.0, h.eye_height(), 0.0)
	var fwd := Vector2(-sin(look_yaw), -cos(look_yaw))
	var half_fov := deg_to_rad(profile.fov_deg * 0.5)
	var best: Node3D = null
	var best_score := INF
	var best_d := INF
	var seen := 0
	# Heroes (<= 5 enemies: no sorting needed). WardlingWorld's hero list is
	# collected once per tick in registry order (deterministic, no allocation).
	var list: Array = server.wardlings.heroes() if server.wardlings != null else _all_heroes()
	for item in list:
		var e := item as HeroBody
		if e.combat.dead or e.combat.team == team:
			continue
		var d := eye.distance_to(e.state.position)
		if d > profile.sight_range_m:
			continue
		var flat := Vector2(e.state.position.x - eye.x, e.state.position.z - eye.z)
		var in_fov := flat.length() < 0.01 or absf(fwd.angle_to(flat.normalized())) <= half_fov
		var hit_me := e.net_id == bb.last_attacker_id and bb.seconds_since(bb.last_damaged_tick) < 1.0
		if not (in_fov or d <= profile.awareness_m or hit_me):
			continue
		if not _los(eye, e.state.position + Vector3(0.0, CHEST_Y, 0.0)):
			continue
		seen += 1
		memory[e.net_id] = [e.state.position, bb.tick]
		bb.last_seen_enemy_tick = bb.tick
		var s := d + 20.0 * e.combat.health.hp / maxf(e.combat.def.max_hp, 1.0) - (15.0 if hit_me else 0.0)
		if s < best_score:
			best_score = s
			best = e
			best_d = d
	bb.enemy_heroes_seen = seen
	var visible := best != null
	# E14 objective focus: during a siege (or inside a Breach zone) the Uplink /
	# Generator beats heroes farther than profile.objective_focus_m.
	# A bot under fire fights back first (it would otherwise die to defenders at range).
	var focus := best == null or (best_d > profile.objective_focus_m and bb.seconds_since(bb.last_damaged_tick) > 1.0)
	# Exposed enemy Uplink.
	if focus and bb.enemy_uplink_exposed and (best == null or prefer_uplink):
		var u := server.registry.get_node_by_id(bb.enemy_uplink_id) as UplinkSim
		if u != null and (prefer_uplink or eye.distance_to(u.aim_point()) <= UPLINK_RANGE_M * 0.6) \
				and eye.distance_to(u.aim_point()) <= UPLINK_RANGE_M and _los_uplink(eye, u):
			best = u
			visible = true
	# E14 Breach: the enemy Generator, from inside its zone (the shield blocks the rest).
	if focus and not (best is UplinkSim) and bb.generator_id != 0 \
			and BotBlackboard.flat_dist(h.state.position, bb.generator_pos) <= bb.generator_zone_radius - 0.5:
		var g := server.registry.get_node_by_id(bb.generator_id) as GeneratorTarget
		if g != null and g.is_up() and _los_near(eye, g.aim_point(), g.global_position, g.hit_radius):
			best = g
			visible = true
	# Enemy Wardlings (nearest with LOS, at most 2 rays).
	bb.enemy_wardlings_seen = 0
	if best == null and server.wardlings != null:
		var near := server.wardlings.enemies_near(h.state.position, WARDLING_RANGE_M, team)
		var first: WardlingSim = null
		var second: WardlingSim = null
		var d1 := INF
		var d2 := INF
		for n in near:
			if not (n is WardlingSim):
				continue
			bb.enemy_wardlings_seen += 1
			var dd := eye.distance_squared_to(n.global_position)
			if dd < d1:
				second = first
				d2 = d1
				first = n
				d1 = dd
			elif dd < d2:
				second = n
				d2 = dd
		for w in [first, second]:
			if w != null and _los(eye, (w as WardlingSim).chest()):
				best = w
				visible = true
				break
	# Remembered hero (last known position, not shootable).
	if best == null:
		_forget(bb.tick)
		var near_d := INF
		for id in memory:
			var e := server.hero(id)
			if e == null or e.combat.dead:
				continue
			var p: Vector3 = memory[id][0]
			var d := eye.distance_to(p)
			if d < near_d:
				near_d = d
				best = e
		visible = false
	target = best
	target_visible = visible
	rays_last_scan = MAX_RAYS - _rays_left
	_fill(bb, eye)


## Aim point of the target (head or chest for heroes).
func aim_point(head: bool) -> Vector3:
	if target is HeroBody:
		var h := target as HeroBody
		var crouch := h.eye_height() / 1.62
		return h.state.position + Vector3(0.0, (HEAD_Y if head else CHEST_Y) * crouch, 0.0)
	if target is WardlingSim:
		return (target as WardlingSim).chest()
	if target is UplinkSim:
		return (target as UplinkSim).aim_point()
	if target is GeneratorTarget:
		return (target as GeneratorTarget).aim_point()
	return target.global_position if target != null else Vector3.ZERO


## Angular radius used for the fire check (metres at the target).
func target_radius() -> float:
	if target is HeroBody:
		return 0.35
	if target is WardlingSim:
		return 0.3
	if target is UplinkSim:
		return 1.4
	if target is GeneratorTarget:
		return (target as GeneratorTarget).hit_radius
	return 0.3


## Target still alive and valid (between scans).
func target_alive() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target is HeroBody:
		return not (target as HeroBody).combat.dead
	if target is WardlingSim:
		return not (target as WardlingSim).dead
	if target is UplinkSim:
		var u := target as UplinkSim
		return u.exposed and not u.is_destroyed()
	if target is GeneratorTarget:
		return (target as GeneratorTarget).is_up()
	return false


func _fill(bb: BotBlackboard, eye: Vector3) -> void:
	if target == null:
		bb.target_id = 0
		bb.target_is_hero = false
		bb.target_dist = INF
		return
	bb.target_id = int(target.get("net_id"))
	bb.target_is_hero = target is HeroBody
	bb.target_hp_frac = 1.0
	if target is HeroBody:
		var th := target as HeroBody
		bb.target_hp_frac = th.combat.health.hp / maxf(th.combat.def.max_hp, 1.0)
	bb.target_pos = memory[bb.target_id][0] if (not target_visible and memory.has(bb.target_id)) \
		else WardlingWorld.feet_of(target) if not (target is UplinkSim) else (target as UplinkSim).base
	bb.target_dist = eye.distance_to(bb.target_pos)


func _all_heroes() -> Array:
	var out: Array = []
	for id in server.registry.ids():
		var e := server.registry.get_node_by_id(id) as HeroBody
		if e != null and e.combat != null:
			out.append(e)
	return out


func _forget(tick: int) -> void:
	var limit := roundi(profile.memory_s * server.net.tick_rate_hz)
	for id in memory.keys():
		if tick - int(memory[id][1]) > limit:
			memory.erase(id)


## The Uplink has its own static collision: a ray that stops on its surface
## (within the hit radius of the core axis, plus slack) counts as a clear shot.
func _los_uplink(from: Vector3, u: UplinkSim) -> bool:
	if _rays_left <= 0:
		return false
	_rays_left -= 1
	_ray.from = from
	_ray.to = u.aim_point()
	var r := server.get_world_3d().direct_space_state.intersect_ray(_ray)
	if r.is_empty():
		return true
	var p: Vector3 = r.position
	return Vector2(p.x - u.base.x, p.z - u.base.z).length() <= u.hit_radius + 1.5


## A static body with collision (the Generator core): a ray stopping within
## `radius` (+ slack) of its axis counts as a clear shot.
func _los_near(from: Vector3, to: Vector3, axis: Vector3, radius: float) -> bool:
	if _rays_left <= 0:
		return false
	_rays_left -= 1
	_ray.from = from
	_ray.to = to
	var r := server.get_world_3d().direct_space_state.intersect_ray(_ray)
	if r.is_empty():
		return true
	var p: Vector3 = r.position
	return Vector2(p.x - axis.x, p.z - axis.z).length() <= radius + 1.5


func _los(from: Vector3, to: Vector3) -> bool:
	if _rays_left <= 0:
		return false
	_rays_left -= 1
	_ray.from = from
	_ray.to = to
	return server.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()
