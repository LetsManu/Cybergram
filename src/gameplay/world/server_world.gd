class_name ServerWorld
extends Node3D
## Authoritative simulation (ADR-0002, architecture.md §8.3). One step() = one
## tick in a fixed order: poll transport -> per hero (input -> movement ->
## weapon -> hitscan -> damage) -> respawns -> snapshots -> events -> tick++.
## Lives in its own World3D (SubViewport.own_world_3d) when sharing a process
## with ClientWorld (verification-4.7.md item 2).
## E4/E5 scope: health, hitscan weapons, ammo feeds, death and respawn.

signal hero_died(victim_net_id: int, killer_net_id: int)
signal hero_respawned(net_id: int)
## E8: a hero lost HP (retaliation trigger for its squad).
signal hero_damaged(victim_net_id: int, attacker_net_id: int, amount: float)
## E7: a capture or defence outcome (Lumen / EXP hook; no economy yet).
signal objective_event(event: ObjectiveEvent)

const PLAYER_SPAWN := "PlayerSpawn"
## Optional per-team respawn markers in the map ("TeamSpawn0", "TeamSpawn1").
## Without one, a hero respawns at its first spawn point.
const TEAM_SPAWN := "TeamSpawn%d"
const TEAM_PLAYERS: int = 0
const TEAM_DUMMIES: int = 1

var net: NetConfig
var movement: MovementDef
var rules: MatchRulesDef
var player_hero: HeroDef
var session: ServerSession
var registry: EntityRegistry
var tick: int = 0
var dt: float

var _humans: Dictionary = {}  # peer id -> HeroBody
var _peer_of: Dictionary = {}  # hero net id -> peer id
var _dummies: Array = []      # [HeroBody, ScriptedInputSource]
var _map: Node3D
var _cmd := InputCommand.new()
var _tracer := HitscanTracer.new()
var _events: Dictionary = {}  # peer id -> Array[GameEvent] (flushed every tick)
## E7 presence seam: non-hero sources (Wardlings) counted by hardpoint zones.
var _presence_sources: Array = []
## E7 hardpoints (null on maps without a MapDef).
var objectives: ObjectiveSystem
var _hero_presence: Dictionary = {}  # hero net id -> PresenceSource
## Debug (--debug-capture): where joining clients spawn instead of PlayerSpawn.
var debug_player_spawn: Variant = null
## E8 Wardlings (squads, Vanguard, bolts); null on maps without a MapDef.
var wardlings: WardlingWorld


## Builds the map and session. Call after the node is in the tree.
## `hero_def` is the HeroDef for joining clients; `match_rules` the respawn rules.
func setup(net_config: NetConfig, movement_def: MovementDef, map_scene: PackedScene, transport: Transport,
		hero_def: HeroDef = null, match_rules: MatchRulesDef = null) -> void:
	net = net_config
	movement = movement_def
	player_hero = hero_def if hero_def != null else HeroDef.new()
	rules = match_rules if match_rules != null else MatchRulesDef.new()
	dt = net.tick_dt()
	registry = EntityRegistry.new(roundi(net.net_id_recycle_s * net.tick_rate_hz))
	session = ServerSession.new(transport, net)
	session.client_joined.connect(_on_client_joined)
	_map = map_scene.instantiate()
	add_child(_map)


## E7: builds the hardpoints from `map_def` (call after setup()).
func setup_objectives(map_def: MapDef) -> void:
	if map_def != null and not map_def.lanes.is_empty():
		objectives = ObjectiveSystem.new(map_def, rules)


## E8: enables Wardlings (squads + Vanguard) on a map with HQs. The AI is
## wired separately from a higher layer (WardlingDirector.attach(server)).
func enable_wardlings(map_def: MapDef, wardling_rules: WardlingRulesDef, picket: WardlingDef) -> WardlingWorld:
	if map_def == null or map_def.hqs.is_empty() or wardling_rules == null or picket == null:
		return null
	wardlings = WardlingWorld.new(self, map_def, wardling_rules, picket)
	return wardlings


## World-space position of a Marker3D in the map, or the origin.
func spawn_point(marker_name: String) -> Vector3:
	var m := _map.get_node_or_null(marker_name) as Node3D
	return m.global_position if m != null else Vector3.ZERO


## Respawn position for `team`: its TeamSpawn marker, else `fallback`.
func team_spawn(team: int, fallback: Vector3) -> Vector3:
	var m := _map.get_node_or_null(TEAM_SPAWN % team) as Node3D
	return m.global_position if m != null else fallback


## Adds a server-driven hero fed by a scripted input source. Returns its NetId.
func add_scripted_hero(source: ScriptedInputSource, spawn: Vector3, hero_def: HeroDef = null,
		team: int = TEAM_DUMMIES) -> int:
	var h := _spawn_hero(spawn, hero_def if hero_def != null else HeroDef.new(), team)
	_dummies.append([h, source])
	return h.net_id


## E7 presence seam (PresenceSource): registers a non-hero presence source
## (Wardling, weight 0.5, AI-capped per team per hardpoint). Idempotent.
## Heroes are counted automatically; do not register them here.
func register_presence_source(src: Object) -> void:
	if src != null and not _presence_sources.has(src):
		_presence_sources.append(src)


func unregister_presence_source(src: Object) -> void:
	_presence_sources.erase(src)


## Registered non-hero presence sources (read-only use).
func presence_sources() -> Array:
	return _presence_sources


func hero(net_id: int) -> HeroBody:
	return registry.get_node_by_id(net_id) as HeroBody


## Match time in seconds (server ticks since start).
func match_seconds() -> float:
	return tick * dt


## One server tick.
func step() -> void:
	session.poll()
	for peer in session.clients:
		var h: HeroBody = _humans.get(peer)
		if h == null:
			continue
		var buf: InputBuffer = session.clients[peer].inputs
		var n := 0
		while n < net.max_inputs_per_tick and buf.pop_next(_cmd):
			_step_hero(h, _cmd)
			n += 1
	for d in _dummies:
		d[1].sample(tick, _cmd)
		_step_hero(d[0], _cmd)
	if wardlings != null:
		wardlings.step()
	_respawn_due()
	_step_objectives()
	_send_snapshots()
	_flush_events()
	tick += 1


## Stage 9 (architecture.md §8.3): hardpoint presence, tasks and ownership.
func _step_objectives() -> void:
	if objectives == null:
		return
	var sources: Array = []
	for id in registry.ids():
		var h := registry.get_node_by_id(id) as HeroBody
		if h == null or h.combat == null:
			continue
		var src: PresenceSource = _hero_presence.get(id)
		if src == null or src.node != h:
			src = PresenceSource.for_node(h, h.combat.team, PresenceSource.HERO_WEIGHT, _alive_check(h))
			src.is_hero = true
			src.net_id = id
			_hero_presence[id] = src
		sources.append(src)
	sources.append_array(_presence_sources)
	objectives.step(dt, sources, tick)
	for ev in objectives.events:
		objective_event.emit(ev)


static func _alive_check(h: HeroBody) -> Callable:
	return func() -> bool: return is_instance_valid(h) and not h.combat.dead


func _step_hero(h: HeroBody, cmd: InputCommand) -> void:
	var c := h.combat
	c.local_tick += 1
	if c.dead:
		# Dead heroes stand still; the owning client zeroes the same fields so
		# prediction keeps matching (ClientWorld.tick()).
		cmd.move = Vector2.ZERO
		cmd.buttons = 0
	h.step(cmd, dt)
	if cmd.squad_cmd != InputCommand.SQUAD_NONE and wardlings != null and not c.dead:
		wardlings.issue_command(h, cmd)
	if c.dead or c.weapon == null:
		return
	# heroes.md §3.1: no firing while sprinting.
	var sprinting := cmd.has(InputCommand.BTN_SPRINT) and cmd.move.y > 0.0 and not h.state.crouching
	if c.weapon.step(cmd, c.local_tick, not sprinting):
		_fire(h, cmd)


## Resolves the shot the weapon just fired: pellets -> hitscan -> damage.
func _fire(h: HeroBody, cmd: InputCommand) -> void:
	var c := h.combat
	var w := c.weapon
	var targets := _hurtable_enemies(c.team)
	var origin := h.state.position + Vector3(0.0, h.eye_height(), 0.0)
	var fwd := Basis(Vector3.UP, h.look_yaw) * Basis(Vector3.RIGHT, h.look_pitch) * Vector3.FORWARD
	var dirs := w.pellet_directions(fwd)
	if targets.is_empty() and (wardlings == null or wardlings.wardlings.is_empty()):
		return
	var space := h.get_world_3d().direct_space_state
	var per_target := {}  # net id -> [raw damage, flags, first point]
	var per_wardling := {}  # WardlingSim -> [raw damage, first point]
	for dir in dirs:
		var hit := _tracer.trace(space, origin, dir, w.def.range_m, targets, cmd.view_tick, cmd.view_alpha)
		if wardlings != null:
			var wl := wardlings.trace_wardlings(origin, dir, hit.distance if hit.target != null else _tracer.last_limit, c.team)
			if not wl.is_empty():
				if not per_wardling.has(wl[0]):
					per_wardling[wl[0]] = [0.0, origin + dir * float(wl[1])]
				per_wardling[wl[0]][0] += DamageMath.hit_damage(w.def, wl[1], false, c.level)
				continue
		if hit.target == null:
			continue
		var raw := DamageMath.hit_damage(w.def, hit.distance, hit.headshot, c.level)
		var id := hit.target.net_id
		if not per_target.has(id):
			per_target[id] = [0.0, 0, hit.point]
		per_target[id][0] += raw
		if hit.headshot:
			per_target[id][1] |= GameEvent.FLAG_HEADSHOT
	for id in per_target:
		var target := hero(id)
		var rec: Array = per_target[id]
		var dmg_flags: int = DamageInfo.FLAG_HEADSHOT if (rec[1] & GameEvent.FLAG_HEADSHOT) != 0 else 0
		var applied := target.combat.health.apply_damage(DamageInfo.make(rec[0], h.net_id, c.team, dmg_flags))
		if applied > 0.0:
			hero_damaged.emit(id, h.net_id, applied)
		var ev_flags: int = rec[1]
		if not target.combat.health.is_alive():
			ev_flags |= GameEvent.FLAG_KILL
			_kill(target, h.net_id)
		_queue_event(_peer_of.get(h.net_id, 0), GameEvent.hit_confirm(id, h.net_id, applied, ev_flags, rec[2]))
	for wd in per_wardling:
		var wrec: Array = per_wardling[wd]
		var wapplied := wardlings.damage_wardling(wd, DamageInfo.make(wrec[0], h.net_id, c.team))
		var wflags: int = GameEvent.FLAG_KILL if wd.dead else 0
		_queue_event(_peer_of.get(h.net_id, 0), GameEvent.hit_confirm(wd.net_id, h.net_id, wapplied, wflags, wrec[1]))


## E8: non-hitscan damage to a hero (Wardling bolts). Handles the kill.
func damage_hero(target: HeroBody, info: DamageInfo) -> float:
	if target.combat.dead:
		return 0.0
	var applied := target.combat.health.apply_damage(info)
	if applied > 0.0:
		hero_damaged.emit(target.net_id, info.source_net_id, applied)
	if not target.combat.health.is_alive():
		_kill(target, info.source_net_id)
	return applied


func _hurtable_enemies(team: int) -> Array[HeroBody]:
	var out: Array[HeroBody] = []
	for id in registry.ids():
		var t := registry.get_node_by_id(id) as HeroBody
		if t != null and t.combat != null and not t.combat.dead and t.combat.team != team:
			out.append(t)
	return out


func _kill(victim: HeroBody, killer_id: int) -> void:
	var c := victim.combat
	c.dead = true
	c.deaths += 1
	var killer := hero(killer_id)
	if killer != null:
		killer.combat.kills += 1
	c.respawn_tick = tick + RespawnSystem.respawn_ticks(rules, tick, net.tick_rate_hz)
	victim.collision_layer = 0  # corpses do not block
	var ev := GameEvent.kill(victim.net_id, killer_id, victim.state.position)
	for peer in session.clients:
		_queue_event(peer, ev)
	hero_died.emit(victim.net_id, killer_id)


func _respawn_due() -> void:
	for id in registry.ids():
		var h := registry.get_node_by_id(id) as HeroBody
		if h == null or not h.combat.dead or tick < h.combat.respawn_tick:
			continue
		var fresh := MotorState.new()
		fresh.position = h.combat.home_spawn if _respawns_at_home(h) else team_spawn(h.combat.team, h.combat.home_spawn)
		h.state.copy_from(fresh)
		h.collision_layer = HeroBody.LAYER_HEROES
		h.motor.restore(h.state)
		h.combat.reset_for_respawn()
		hero_respawned.emit(id)


## Debug: scripted dummies flagged respawn_at_home come back where they started.
func _respawns_at_home(h: HeroBody) -> bool:
	for d in _dummies:
		if d[0] == h:
			return (d[1] as ScriptedInputSource).respawn_at_home
	return false


func _spawn_hero(spawn: Vector3, def: HeroDef, team: int) -> HeroBody:
	var h := HeroBody.new()
	h.setup(def.movement_for(movement), spawn, true)
	h.collision_mask |= WardlingSim.layer_for_team(1 - team)  # E8: enemy Wardlings body-block
	add_child(h)
	h.place()
	h.net_id = registry.register(h, EntityRegistry.KIND_HERO, tick)
	h.combat = HeroCombat.new(def, team, net.tick_rate_hz, h.net_id)
	h.combat.home_spawn = spawn
	return h


func _on_client_joined(peer_id: int) -> void:
	var at: Vector3 = debug_player_spawn if debug_player_spawn != null else spawn_point(PLAYER_SPAWN)
	var h := _spawn_hero(at, player_hero, TEAM_PLAYERS)
	_humans[peer_id] = h
	_peer_of[h.net_id] = peer_id
	session.accept(peer_id, h.net_id, tick)


func _queue_event(peer: int, ev: GameEvent) -> void:
	if peer == 0 or not session.clients.has(peer):
		return
	if not _events.has(peer):
		var list: Array[GameEvent] = []
		_events[peer] = list
	_events[peer].append(ev)


func _flush_events() -> void:
	for peer in _events:
		session.send_events(peer, tick, _events[peer])
	_events.clear()


func _send_snapshots() -> void:
	if session.clients.is_empty():
		return
	var entities: Array[SnapshotData.EntityState] = []
	for id in registry.ids():
		var h := registry.get_node_by_id(id) as HeroBody
		if h == null:
			continue  # Wardlings go in their own compact block
		var e := SnapshotData.EntityState.new()
		e.net_id = id
		e.kind = registry.kind_of(id)
		e.position = h.state.position
		e.velocity = h.state.velocity
		e.yaw = h.look_yaw
		e.pitch = h.look_pitch
		e.crouching = h.state.crouching
		e.grounded = h.state.grounded
		e.dead = h.combat.dead
		e.team = h.combat.team
		e.hp = ceili(h.combat.health.hp)
		e.max_hp = h.combat.def.max_hp
		entities.append(e)
	for peer in session.clients:
		var c: ServerSession.ClientConnection = session.clients[peer]
		var s := SnapshotData.new()
		s.tick = tick
		s.last_processed_seq = c.inputs.last_processed_seq
		s.own_net_id = c.own_net_id
		var own := registry.get_node_by_id(c.own_net_id) as HeroBody
		if own != null:
			s.own_state = own.state
			s.own_combat = _own_combat(own.combat)
		s.entities = entities
		_fill_objectives(s)
		if wardlings != null:
			wardlings.write_snapshot(s)
		session.send_snapshot(peer, s)


func _fill_objectives(s: SnapshotData) -> void:
	if objectives == null:
		return
	for h in objectives.all:
		var st := SnapshotData.HardpointState.new()
		st.owner = h.owner
		st.progress = h.progress
		st.capturing_team = h.capturing_team
		st.contested = h.contested
		st.overtime = h.overtime_left > 0.0
		st.severed = h.severed
		st.locked = [h.locked_for(0), h.locked_for(1)]
		s.hardpoints.append(st)
	for lane in objectives.lanes.size():
		for team in 2:
			s.fronts.append(objectives.front.front_for(team, lane))


static func _own_combat(c: HeroCombat) -> SnapshotData.OwnCombat:
	var o := SnapshotData.OwnCombat.new()
	o.hp = ceili(c.health.hp)
	o.max_hp = c.def.max_hp
	o.dead = c.dead
	o.respawn_tick = c.respawn_tick
	if c.weapon != null:
		var f := c.weapon.feed
		o.feed_kind = c.weapon.def.feed_kind
		o.ammo = f.current()
		o.ammo_capacity = f.capacity()
		o.reserve = f.reserve_count()
		o.ammo_flags = f.flags()
	return o
