class_name WardlingWorld
extends RefCounted
## All server Wardlings (architecture.md §10, Canon C15): personal squads,
## Vanguard waves, movement on the navmesh, mana bolts and damage. Owned by
## ServerWorld and stepped once per tick (after hero input):
##   rules (Foundry minting, owner-death hold, Attack lifetime, Vanguard cadence)
##   -> think_hook (the WardlingDirector in src/ai, injected from a higher layer)
##   -> path queue -> movement -> firing -> projectiles -> despawn.
## Gameplay never names src/ai: brains write intents on WardlingSim / the Squad
## and VanguardWave blackboards; this class turns intents into motion and damage.

signal wardling_minted(w: WardlingSim)
## A Wardling left the world (killed: killer_id > 0; dissolved: 0).
signal wardling_removed(w: WardlingSim, killer_id: int)
signal squad_command_issued(owner_net_id: int, cmd: int)
signal squad_dissolved(owner_net_id: int)
## E10: a Wardling changed team / squad / wave (subvert, revert); brains rebuild.
signal wardling_allegiance_changed(w: WardlingSim)
signal vanguard_wave_spawned(team: int, lane: int, minted: int)

const KIND_WARDLING: int = EntityRegistry.KIND_WARDLING
## Personal squads keep this distance band when choosing a firing spot.
const VANGUARD_STATE: int = 5
const STATE_DISSOLVING_BIT: int = 1 << 5

var server: ServerWorld
var map_def: MapDef
var rules: WardlingRulesDef
var picket: WardlingDef
var tick_hz: int = 30
var dt: float = 1.0 / 30.0
## Debug clock: > 1 compresses the Vanguard cadence (--wave-clock).
var clock_scale: float = 1.0
var vanguard_enabled: bool = true
## E9 Surge hook: current Wardling tier (1-3), set by match flow. Tier II/III
## stats are not authored yet (PLACEHOLDER: no stat change).
var tier: int = 1
## Injected AI step: think_hook.call(tick). Set by WardlingDirector.attach().
var think_hook: Callable

var projectiles := ProjectileSystem.new()
var wardlings: Array[WardlingSim] = []
## Owner hero net id -> live Squad.
var squads: Dictionary = {}
## Squads whose owner died (DeathHold until they dissolve).
var orphan_squads: Array[Squad] = []
var waves: Array[VanguardWave] = []

## Perf counters (µs).
var last_step_usec: int = 0
var last_think_usec: int = 0
var think_usec_total: int = 0
var step_usec_total: int = 0
var steps: int = 0
var path_queries: int = 0

var _current_wave: Dictionary = {}  # Vector2i(team, lane) -> VanguardWave
var _known_heroes: Dictionary = {}
var _just_spawned: Dictionary = {}
var _grid: Dictionary = {}  # Vector2i -> Array[Node3D]
var _heroes: Array[HeroBody] = []
var _path_queue: Array[WardlingSim] = []
var _next_squad_id: int = 1
var _next_wave_id: int = 1
var _nav_map: RID
var _ray := PhysicsRayQueryParameters3D.new()
var _rng := RandomNumberGenerator.new()
var _frame: int = -1
## Navmesh surface height above the floor (measured once at a Sanctum).
var _nav_y_offset: float = NAN
var _ticks_this_frame: int = 0


func _init(world: ServerWorld, map: MapDef, rules_: WardlingRulesDef, picket_: WardlingDef) -> void:
	server = world
	map_def = map
	rules = rules_
	picket = picket_
	tick_hz = world.net.tick_rate_hz
	dt = world.dt
	_rng.seed = 0xC15
	_ray.collision_mask = HeroBody.LAYER_WORLD
	server.hero_died.connect(_on_hero_died)
	server.hero_respawned.connect(_on_hero_respawned)
	server.hero_damaged.connect(_on_hero_damaged)
	server.tree_exiting.connect(_free_agents)


func tick() -> int:
	return server.tick


func nav_map() -> RID:
	if not _nav_map.is_valid():
		_nav_map = server.get_world_3d().navigation_map
	return _nav_map


func nav_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(nav_map()) > 0


## One server tick of every Wardling.
func step() -> void:
	var t0 := Time.get_ticks_usec()
	var t := server.tick
	var f := Engine.get_physics_frames()
	_ticks_this_frame = _ticks_this_frame + 1 if f == _frame else 1
	_frame = f
	projectiles.fired.clear()
	_collect_heroes()
	_squad_rules(t)
	MinionmancerHooks.step(self, t)  # E10: Elite / Turned expiry
	if vanguard_enabled and map_def != null:
		_vanguard_rules(t)
	if think_hook.is_valid():
		var a := Time.get_ticks_usec()
		think_hook.call(t)
		last_think_usec = Time.get_ticks_usec() - a
		think_usec_total += last_think_usec
	_service_paths()
	for w in wardlings:
		_move(w)
	for w in wardlings:
		_fire(w)
	_rebuild_grid()
	projectiles.step(dt, _candidates, _on_bolt_hit)
	_despawn_dead()
	last_step_usec = Time.get_ticks_usec() - t0
	step_usec_total += last_step_usec
	steps += 1


# --- Queries for brains (read-only) ---------------------------------------

func heroes() -> Array[HeroBody]:
	return _heroes


## Live entity (HeroBody or WardlingSim) by net id, or null when dead/gone.
func live_entity(net_id: int) -> Node3D:
	var n := server.registry.get_node_by_id(net_id)
	if n is HeroBody:
		return n if not (n as HeroBody).combat.dead else null
	if n is WardlingSim:
		return n if not (n as WardlingSim).dead else null
	if n is UplinkSim:  # E9: targetable while Exposed (Squad Attack, bolts)
		var u := n as UplinkSim
		return u if u.exposed and not u.is_destroyed() else null
	return null


static func team_of(n: Node3D) -> int:
	if n is HeroBody:
		return (n as HeroBody).combat.team
	if n is WardlingSim:
		return (n as WardlingSim).team
	if n is UplinkSim:
		return (n as UplinkSim).team
	return -1


static func feet_of(n: Node3D) -> Vector3:
	if n is HeroBody:
		return (n as HeroBody).state.position
	return n.global_position


func chest_of(n: Node3D) -> Vector3:
	if n is HeroBody:
		return (n as HeroBody).state.position + Vector3(0.0, rules.hero_aim_height_m, 0.0)
	if n is WardlingSim:
		return (n as WardlingSim).chest()
	if n is UplinkSim:
		return (n as UplinkSim).aim_point()
	return n.global_position


## Live enemies of `team` within `radius` (flat) of `pos`, heroes and Wardlings.
func enemies_near(pos: Vector3, radius: float, team: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var r := ceili(radius / rules.spatial_cell_m)
	var c := _cell(pos)
	var r2 := radius * radius
	for x in range(c.x - r, c.x + r + 1):
		for z in range(c.y - r, c.y + r + 1):
			var list: Array = _grid.get(Vector2i(x, z), [])
			for n in list:
				# The grid is rebuilt after despawns: a Wardling freed since then is skipped.
				if not is_instance_valid(n) or team_of(n) == team:
					continue
				var p := feet_of(n)
				if (p.x - pos.x) * (p.x - pos.x) + (p.z - pos.z) * (p.z - pos.z) <= r2 and live_entity(n.get("net_id")) != null:
					out.append(n)
	return out


## Static-world line of sight between two points (one ray).
func has_los(from: Vector3, to: Vector3) -> bool:
	var space := server.get_world_3d().direct_space_state
	_ray.from = from
	_ray.to = to
	return space.intersect_ray(_ray).is_empty()


## Closest navmesh point, on the floor (identity until the navigation map is synced).
func snap(p: Vector3) -> Vector3:
	if not nav_ready():
		return p
	return NavigationServer3D.map_get_closest_point(nav_map(), p) - Vector3(0.0, _nav_offset(), 0.0)


func _nav_offset() -> float:
	if is_nan(_nav_y_offset):
		var ref := map_def.hq(MapDef.TEAM_CONCORD).sanctum if map_def != null else Vector3.ZERO
		_nav_y_offset = clampf(NavigationServer3D.map_get_closest_point(nav_map(), ref).y - ref.y, 0.0, 1.0)
	return _nav_y_offset


## One navmesh path query (counted). Brains use it for shared wave paths.
func query_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	path_queries += 1
	return NavigationServer3D.map_get_path(nav_map(), from, to, true)


## Hardpoint owner (E7 ObjectiveSystem when present, else the MapDef initial owner).
func hardpoint_owner(lane: int, index: int) -> int:
	if server.objectives != null:
		return (server.objectives.lanes[lane][index] as HardpointSim).owner
	return map_def.lanes[lane].hardpoints[index].initial_owner


## Front hardpoint index of `team` in `lane` (Canon C15): E7's LaneFrontResolver;
## on maps without an ObjectiveSystem the same rule on the initial owners (no
## progress, so step 1 never fires).
func front_index(team: int, lane: int) -> int:
	if server.objectives != null:
		return server.objectives.front.front_for(team, lane)
	var hps := map_def.lanes[lane].hardpoints
	var order := range(hps.size())
	if team == MapDef.TEAM_SYNDICATE:
		order.reverse()
	var held := -1
	var prev_held := true  # the HQ side counts as held
	for i in order:
		var o := hps[i].initial_owner
		if o == team:
			held = i
			prev_held = true
			continue
		if hps[i].tier == HardpointDef.Tier.MID or prev_held:
			return i
		prev_held = false
	return held


func squad_of(owner_net_id: int) -> Squad:
	return squads.get(owner_net_id)


func vanguard_count(team: int) -> int:
	var n := 0
	for w in waves:
		if w.team == team:
			n += w.alive_count()
	return n


# --- Commands ---------------------------------------------------------------

## Validates and applies a squad command carried by `cmd` (server side; never
## trusts the client). Returns true if the squad took the order.
func issue_command(h: HeroBody, cmd: InputCommand) -> bool:
	var sq: Squad = squads.get(h.net_id)
	if sq == null or h.combat.dead:
		return false
	var feet := h.state.position
	match cmd.squad_cmd:
		Squad.CMD_FOLLOW:
			sq.issue(Squad.CMD_FOLLOW, server.tick)
		Squad.CMD_HOLD:
			var p := cmd.squad_point
			if Vector2(p.x - feet.x, p.z - feet.z).length() > rules.hold_ground_range_m + 1.0:
				p = feet
			sq.issue(Squad.CMD_HOLD, server.tick, snap(p))
		Squad.CMD_ATTACK:
			var target := live_entity(cmd.squad_target)
			if target == null or team_of(target) == sq.team:
				return false
			var eye := feet + Vector3(0.0, h.eye_height(), 0.0)
			var aim := chest_of(target)
			if eye.distance_to(aim) > rules.command_range_m or not has_los(eye, aim):
				return false
			sq.issue(Squad.CMD_ATTACK, server.tick, Vector3.ZERO, cmd.squad_target)
		Squad.CMD_CAPTURE:
			if map_def == null or map_def.lanes.is_empty():
				return false
			var hps := map_def.lanes[0].hardpoints
			if cmd.squad_target < 0 or cmd.squad_target >= hps.size():
				return false
			if server.objectives != null and hardpoint_owner(0, cmd.squad_target) != sq.team \
					and not server.objectives.eligible(0, cmd.squad_target, sq.team):
				return false  # Locked (C3); own hardpoints are defended instead
			var hp: HardpointDef = hps[cmd.squad_target]
			sq.issue(Squad.CMD_CAPTURE, server.tick, hp.position, 0, cmd.squad_target)
			sq.capture_radius = hp.zone_radius
		_:
			return false
	squad_command_issued.emit(h.net_id, cmd.squad_cmd)
	return true


# --- Damage -----------------------------------------------------------------

## Applies damage to a Wardling; returns the HP removed.
func damage_wardling(w: WardlingSim, info: DamageInfo) -> float:
	if w.dead:
		return 0.0
	var taken := MinionmancerHooks.damage_taken_mult(w, server.tick)  # E10: Rally Beacon DR
	if not is_equal_approx(taken, 1.0):
		info = DamageInfo.make(info.amount * taken, info.source_net_id, info.instigator_team, info.flags, info.type)
	var applied := w.health.apply_damage(info)
	if applied > 0.0:
		w.last_attacker_id = info.source_net_id
		w.last_hit_tick = server.tick
		w.hit_by[info.source_net_id] = server.tick  # E13 share list
	if not w.health.is_alive():
		w.dead = true
		w.killer_id = info.source_net_id
	return applied


## Nearest Wardling of another team hit by a ray within `limit` (hero hitscan).
## Returns [WardlingSim, distance] or [] .
func trace_wardlings(origin: Vector3, dir: Vector3, limit: float, shooter_team: int) -> Array:
	var best: WardlingSim = null
	var best_t := limit
	for w in wardlings:
		if w.dead or w.team == shooter_team:
			continue
		var p := w.global_position
		var t := HitscanTracer.ray_vertical_capsule(origin, dir, p.y + w.def.radius,
			p.y + maxf(w.def.height - w.def.radius, w.def.radius), Vector2(p.x, p.z), w.def.radius)
		if t >= 0.0 and t <= best_t:
			best_t = t
			best = w
	return [best, best_t] if best != null else []


# --- Debug ------------------------------------------------------------------

## Spawns `n` ownerless Wardlings as extra Vanguard-style waves of 4, both teams
## alternating, staggered along each lane gate (perf scenario, --spawn-wardlings).
func debug_spawn(n: int) -> void:
	if map_def == null:
		return
	var made := 0
	var k := 0
	while made < n:
		var team := k % 2
		var hq := map_def.hq(team)
		var wave := VanguardWave.new(_next_wave_id, team, 0, server.tick)
		_next_wave_id += 1
		var ahead := -1.0 if team == MapDef.TEAM_CONCORD else 1.0
		var base := hq.lane_gate + Vector3(0.0, 0.0, ahead * (6.0 + float(k >> 1) * 5.0))
		for i in mini(4, n - made):
			if _mint(picket, team, base + _block_offset(i, ahead), 0, null, wave) == null:
				return
			made += 1
		waves.append(wave)
		k += 1


## Debug / tests (E9): gives `owner` a full squad minted around it now (normally
## squads mint only at the owner's Sanctum / Foundry). Returns the Squad.
func debug_squad_at(owner: HeroBody) -> Squad:
	var sq: Squad = squads.get(owner.net_id)
	if sq == null:
		sq = Squad.new(_next_squad_id, owner.net_id, owner.combat.team, rules.squad_size)
		_next_squad_id += 1
		squads[owner.net_id] = sq
		_known_heroes[owner.net_id] = true
	sq.anchor = owner.state.position
	while sq.alive_count() < sq.size:
		if _mint(picket, sq.team, owner.state.position + _ring_offset(sq.alive_count(), rules.mint_ring_m), owner.net_id, sq) == null:
			break
	return sq


# --- Rules ------------------------------------------------------------------

func _collect_heroes() -> void:
	_heroes.clear()
	for id in server.registry.ids():
		var h := server.registry.get_node_by_id(id) as HeroBody
		if h != null and h.combat != null:
			_heroes.append(h)


func _squad_rules(t: int) -> void:
	if map_def != null:
		for h in _heroes:
			if h.combat.dead:
				continue
			if not _known_heroes.has(h.net_id):
				_known_heroes[h.net_id] = true
				_just_spawned[h.net_id] = true
			var hq := map_def.hq(h.combat.team)
			if hq == null:
				continue
			var pos := h.state.position
			var spawned := _just_spawned.has(h.net_id) and _flat(pos, hq.sanctum) <= hq.sanctum_radius
			var at_foundry := _flat(pos, hq.foundry) <= rules.foundry_radius_m
			if not spawned and not at_foundry:
				continue
			var sq: Squad = squads.get(h.net_id)
			if sq == null:
				sq = Squad.new(_next_squad_id, h.net_id, h.combat.team, rules.squad_size)
				_next_squad_id += 1
				sq.anchor = pos
				squads[h.net_id] = sq
			sq.size = rules.squad_size + MinionmancerHooks.capacity_bonus(h)  # E10: Vesper +2
			var n := Squad.mint_count(sq.alive_count(), sq.pending_mints, sq.size, at_foundry, spawned)
			if n > 0:
				if sq.pending_mints == 0:
					sq.next_mint_tick = t
				sq.pending_mints += n
	_just_spawned.clear()
	var interval := maxi(roundi(rules.mint_interval_s * tick_hz), 1)
	for owner_id in squads:
		var sq: Squad = squads[owner_id]
		while sq.pending_mints > 0 and t >= sq.next_mint_tick:
			var hq := map_def.hq(sq.team)
			_mint(picket, sq.team, snap(hq.foundry + _ring_offset(sq.alive_count(), rules.mint_ring_m)), owner_id, sq)
			sq.pending_mints -= 1
			sq.next_mint_tick += interval
		if sq.command == Squad.CMD_ATTACK:
			var target := live_entity(sq.attack_target_id)
			var owner := server.hero(owner_id)
			var from := sq.hold_point if sq.prev_command == Squad.CMD_HOLD else (owner.state.position if owner != null else sq.anchor)
			var in_leash := target != null and _flat(feet_of(target), from) <= rules.command_range_m
			sq.update_attack(t, tick_hz, rules, target != null, in_leash)
	for i in range(orphan_squads.size() - 1, -1, -1):
		var sq := orphan_squads[i]
		if sq.members.is_empty() or sq.dissolve_due(t, tick_hz, rules):
			for m in sq.members.duplicate():
				_despawn(m, 0)
			orphan_squads.remove_at(i)
			squad_dissolved.emit(sq.owner_net_id)


func _vanguard_rules(t: int) -> void:
	if not VanguardSpawner.is_wave_tick(t, rules, tick_hz, clock_scale):
		return
	for team in [MapDef.TEAM_CONCORD, MapDef.TEAM_SYNDICATE]:
		var hq := map_def.hq(team)
		if hq == null:
			continue
		for lane in map_def.lanes.size():
			var key := Vector2i(team, lane)
			var old: VanguardWave = _current_wave.get(key)
			var alive := old.alive_count() if old != null else 0
			var n := VanguardSpawner.mint_count(alive, rules)
			if n == 0:
				continue
			var wave := VanguardWave.new(_next_wave_id, team, lane, t)
			_next_wave_id += 1
			if old != null:
				for m in old.members:  # survivors merge (keep HP, no reward)
					m.wave = wave
					wave.members.append(m)
				old.members.clear()
				waves.erase(old)
			var ahead := -1.0 if team == MapDef.TEAM_CONCORD else 1.0
			for i in n:
				_mint(picket, team, hq.lane_gate + _block_offset(i + alive, ahead), 0, null, wave)
			waves.append(wave)
			_current_wave[key] = wave
			vanguard_wave_spawned.emit(team, lane, n)


# --- Bodies -----------------------------------------------------------------

func _mint(def: WardlingDef, team: int, pos: Vector3, owner_id: int, squad: Squad = null,
		wave: VanguardWave = null) -> WardlingSim:
	var w := WardlingSim.new()
	w.setup(def, team, snap(pos))
	server.add_child(w)
	w.net_id = server.registry.register(w, KIND_WARDLING, server.tick)
	if w.net_id == 0:
		w.queue_free()
		return null
	w.name = "Wardling%d" % w.net_id
	w.owner_net_id = owner_id
	w.squad = squad
	w.wave = wave
	if squad != null:
		squad.members.append(w)
	if wave != null:
		wave.members.append(w)
	w.spawned_tick = server.tick
	w.yaw = 0.0 if team == MapDef.TEAM_CONCORD else PI
	var a := NavigationServer3D.agent_create()
	NavigationServer3D.agent_set_map(a, nav_map())
	NavigationServer3D.agent_set_radius(a, def.radius + 0.1)
	NavigationServer3D.agent_set_max_speed(a, def.sprint_speed)
	NavigationServer3D.agent_set_neighbor_distance(a, rules.avoidance_neighbor_m)
	NavigationServer3D.agent_set_max_neighbors(a, 8)
	NavigationServer3D.agent_set_time_horizon_agents(a, rules.avoidance_horizon_s)
	NavigationServer3D.agent_set_position(a, w.global_position)
	NavigationServer3D.agent_set_avoidance_callback(a, w._on_safe_velocity)
	NavigationServer3D.agent_set_avoidance_enabled(a, true)
	w.agent = a
	wardlings.append(w)
	server.register_presence_source(w)  # E7 seam: 0.5 presence (C4)
	MinionmancerHooks.on_minted(self, w)  # E10: owner's Wardling HP bonus
	wardling_minted.emit(w)
	return w


func _despawn(w: WardlingSim, killer_id: int) -> void:
	if not wardlings.has(w):
		return
	w.dead = true
	wardlings.erase(w)
	server.unregister_presence_source(w)
	_path_queue.erase(w)
	if w.squad != null:
		w.squad.members.erase(w)
	if w.wave != null:
		w.wave.members.erase(w)
		if w.wave.members.is_empty():
			waves.erase(w.wave)
	if w.agent.is_valid():
		NavigationServer3D.free_rid(w.agent)
		w.agent = RID()
	server.registry.release(w.net_id, server.tick)
	wardling_removed.emit(w, killer_id)
	w.queue_free()


func _free_agents() -> void:
	for w in wardlings:
		if w.agent.is_valid():
			NavigationServer3D.free_rid(w.agent)
			w.agent = RID()


func _despawn_dead() -> void:
	for i in range(wardlings.size() - 1, -1, -1):
		var w := wardlings[i]
		if w.dead:
			_despawn(w, w.killer_id)


func _service_paths() -> void:
	if not nav_ready():
		return
	var n := 0
	while n < rules.max_path_requests_per_tick and not _path_queue.is_empty():
		var w: WardlingSim = _path_queue.pop_front()
		w.path_pending = false
		if w.dead or not w.has_move_target:
			continue
		w.path = query_path(w.global_position, w.move_target)
		w.path_index = 1 if w.path.size() > 1 else 0
		w.path_goal = w.move_target
		n += 1


func _move(w: WardlingSim) -> void:
	if w.dead:
		return
	if MinionmancerHooks.is_stunned(w, server.tick):  # E10: stalled
		w.desired_velocity = Vector3.ZERO
		return
	var pos := w.global_position
	var desired := Vector3.ZERO
	if w.has_move_target:
		var goal := w.move_target
		var to_goal := Vector3(goal.x - pos.x, 0.0, goal.z - pos.z)
		var dist := to_goal.length()
		if dist > w.arrive_radius:
			if dist < rules.direct_steer_m:
				w.path = PackedVector3Array()
			elif (w.path.is_empty() or _flat(goal, w.path_goal) > rules.repath_m) and not w.path_pending:
				w.path_pending = true
				_path_queue.append(w)
			var steer := goal
			if not w.path.is_empty():
				while w.path_index < w.path.size() - 1 and _passed(pos, w.path, w.path_index, rules.waypoint_m):
					w.path_index += 1
				if not (w.path_index == w.path.size() - 1 and _flat(pos, w.path[w.path_index]) < rules.waypoint_m):
					steer = w.path[w.path_index]
			var d := Vector3(steer.x - pos.x, 0.0, steer.z - pos.z)
			if d.length_squared() > 1e-6:
				desired = d.normalized() * minf(w.move_speed, dist / dt)
	w.desired_velocity = desired
	var v := desired
	var fresh := _ticks_this_frame == 1 and Engine.get_physics_frames() - w.safe_frame <= 1
	if fresh and desired != Vector3.ZERO:
		v = w.safe_velocity
		v.y = 0.0
		if v.length() > desired.length():
			v = v.normalized() * desired.length()
	if w.agent.is_valid():
		NavigationServer3D.agent_set_position(w.agent, pos)
		NavigationServer3D.agent_set_velocity(w.agent, desired)
	if v == Vector3.ZERO:
		w.stuck_ticks = 0
		return
	var np := pos + v * dt
	if nav_ready():
		var s := snap(np)
		if absf(s.y - np.y) < 2.0:
			np = s
	# Stuck (pinned against the mesh edge): re-path from here.
	if _flat(np, pos) < v.length() * dt * 0.2:
		w.stuck_ticks += 1
		if w.stuck_ticks > rules.stuck_ticks and not w.path_pending:
			w.stuck_ticks = 0
			w.path = PackedVector3Array()
			w.path_pending = true
			_path_queue.append(w)
	else:
		w.stuck_ticks = 0
	w.global_position = np
	w.yaw = atan2(-v.x, -v.z)


func _fire(w: WardlingSim) -> void:
	if w.fire_cooldown > 0:
		w.fire_cooldown -= 1
	if w.dead or w.attack_target_id == 0 or not w.fire_clear or w.fire_cooldown > 0:
		return
	if MinionmancerHooks.is_stunned(w, server.tick):
		return
	var target := live_entity(w.attack_target_id)
	if target == null or team_of(target) == w.team:
		w.clear_attack()
		return
	var origin := w.chest()
	var aim := chest_of(target)
	var dist := origin.distance_to(aim)
	if dist > w.def.range_m or dist < 0.01:
		return
	var dir := (aim - origin) / dist
	w.yaw = atan2(-dir.x, -dir.z)
	var cone := deg_to_rad(w.def.spread_focused_deg if w.focused else w.def.spread_retaliation_deg) * 0.5
	dir = _spread(dir, cone)
	var limit := w.def.range_m * rules.bolt_range_frac
	var space := server.get_world_3d().direct_space_state
	_ray.from = origin
	_ray.to = origin + dir * limit
	var r := space.intersect_ray(_ray)
	if not r.is_empty():
		limit = origin.distance_to(r.position)
	projectiles.spawn(origin, dir, w.def.projectile_speed, limit,
		w.def.bolt_damage * MinionmancerHooks.damage_mult(self, w, server.tick), w.team, w.net_id,
		origin + dir * minf(limit, dist + 0.3))
	w.fire_cooldown = maxi(roundi(w.def.fire_interval_s * tick_hz), 1)


## Uniform direction inside a cone of half-angle `half` around `dir`.
func _spread(dir: Vector3, half: float) -> Vector3:
	if half <= 0.0:
		return dir
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(dir).normalized()
	var a := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * tan(half)
	return (dir + (side * cos(a) + up * sin(a)) * r).normalized()


func _rebuild_grid() -> void:
	_grid.clear()
	for h in _heroes:
		if not h.combat.dead:
			_grid_add(h, h.state.position)
	for w in wardlings:
		if not w.dead:
			_grid_add(w, w.global_position)


func _grid_add(n: Node3D, p: Vector3) -> void:
	var c := _cell(p)
	if not _grid.has(c):
		_grid[c] = []
	_grid[c].append(n)


func _candidates(pos: Vector3, team: int) -> Array:
	var out := []
	var c := _cell(pos)
	for x in range(c.x - 1, c.x + 2):
		for z in range(c.y - 1, c.y + 2):
			for n in _grid.get(Vector2i(x, z), []):
				if n is HeroBody:
					var h := n as HeroBody
					if h.combat.team != team and not h.combat.dead:
						var s := h.combat.def.hitbox_scale
						out.append([h, h.state.position, h.combat.def.body_radius * s, rules.hero_hit_height_m * s])
				else:
					var w := n as WardlingSim
					if w.team != team and not w.dead:
						out.append([w, w.global_position, w.def.radius, w.def.height])
	if server.match_flow != null:  # E9: enemy Uplinks near the bolt
		var reach := rules.spatial_cell_m * 1.5
		for u in server.match_flow.uplinks:
			if u.team != team and not u.is_destroyed() \
					and Vector2(u.base.x - pos.x, u.base.z - pos.z).length() <= reach + u.hit_radius:
				out.append(u.bolt_capsule())
	return out


func _on_bolt_hit(target: Object, b: ProjectileSystem.Bolt) -> void:
	var info := DamageInfo.make(b.damage, b.source_id, b.team)
	if target is HeroBody:
		server.damage_hero(target as HeroBody, info)
	elif target is WardlingSim:
		damage_wardling(target as WardlingSim, info)
	elif target is UplinkSim:
		server.damage_uplink(target as UplinkSim, b.damage, true)  # C7: Wardlings deal 50%


func _on_hero_died(victim_id: int, _killer_id: int) -> void:
	var sq: Squad = squads.get(victim_id)
	if sq == null:
		return
	squads.erase(victim_id)
	sq.on_owner_died(server.tick, sq.centroid())
	orphan_squads.append(sq)


func _on_hero_respawned(net_id: int) -> void:
	_just_spawned[net_id] = true


func _on_hero_damaged(victim_id: int, attacker_id: int, _amount: float) -> void:
	var sq: Squad = squads.get(victim_id)
	if sq != null:
		sq.note_owner_hit(attacker_id, server.tick)


# --- Snapshot ---------------------------------------------------------------

## Appends the Wardling and bolt blocks to `s` (compact; see SnapshotCodec).
func write_snapshot(s: SnapshotData) -> void:
	for w in wardlings:
		var e := SnapshotData.WardlingState.new()
		e.net_id = w.net_id
		e.position = w.global_position
		e.yaw = w.yaw
		e.hp_frac = w.health.hp / w.health.max_hp
		e.team = w.team
		e.vanguard = w.wave != null
		e.owner_net_id = w.owner_net_id
		var st := VANGUARD_STATE if w.wave != null else (w.squad.command if w.squad != null else 0)
		st |= (w.display_flags & 3) << 3
		st |= MinionmancerHooks.state_bits(w, server.tick)  # E10: Elite / Turned
		if w.squad != null and w.squad.is_dissolving():
			st |= STATE_DISSOLVING_BIT
		e.state = st
		s.wardlings.append(e)
	for f in projectiles.fired:
		s.bolts.append(f)


# --- Helpers ----------------------------------------------------------------

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Waypoint i is reached when close, or when `pos` is past the plane through it
## perpendicular to the next segment (robust to waypoints offset off the mesh).
static func _passed(pos: Vector3, path: PackedVector3Array, i: int, reach_m: float) -> bool:
	var wp := path[i]
	if _flat(pos, wp) < reach_m:
		return true
	var nxt := path[i + 1]
	var seg := Vector2(nxt.x - wp.x, nxt.z - wp.z)
	return seg.dot(Vector2(pos.x - wp.x, pos.z - wp.z)) > 0.0


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / rules.spatial_cell_m), floori(p.z / rules.spatial_cell_m))


static func _ring_offset(i: int, r: float) -> Vector3:
	var a := i * TAU / 5.0
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


## 2 x 2 march block slot `i` (ahead = -1 marches toward -Z).
func _block_offset(i: int, ahead: float) -> Vector3:
	var s := rules.wave_spacing_m
	return Vector3((float(i % 2) - 0.5) * s, 0.0, -ahead * float((i >> 1) % 2) * s)
