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
## Armory advice: damage a hero took by DamageInfo.Type (WEAPON for gunfire).
signal hero_damage_taken(victim_net_id: int, amount: float, damage_type: int)
## E7: a capture or defence outcome (Lumen / EXP hook; no economy yet).
signal objective_event(event: ObjectiveEvent)
## Online slots: a joining human took over this scripted (bot) hero; whoever
## drove it must stop. Gameplay never names the AI; src/ai listens.
signal controller_taken(hero_net_id: int)
## A human left; this hero has no driver until someone attach_source()s one.
signal controller_released(hero_net_id: int)

const PLAYER_SPAWN := "PlayerSpawn"
## Optional per-team respawn markers in the map ("TeamSpawn0", "TeamSpawn1").
## Without one, a hero respawns at its first spawn point.
const TEAM_SPAWN := "TeamSpawn%d"
const MVP_FORMULA_PATH := "res://assets/data/match/mvp_formula.tres"
const TEAM_PLAYERS: int = 0
const TEAM_DUMMIES: int = 1
## Bullet tracers sent per shot (shotguns send an even subset of their pellets).
const TRACERS_PER_SHOT: int = 4

var net: NetConfig
var movement: MovementDef
var rules: MatchRulesDef
var player_hero: HeroDef
var session: ServerSession
var registry: EntityRegistry
var tick: int = 0
var dt: float

var _humans: Dictionary = {}  # peer id -> HeroBody
## Online lobby: token -> {team, hero_index} for players who start the match
## from the lobby (bots leave these slots free). Consumed on join.
var reserved_slots: Dictionary = {}
## W17B: slot token -> the hero it played (a reconnect with the same token
## takes its hero back from the bot that covered it).
var token_heroes: Dictionary = {}
var _peer_of: Dictionary = {}  # hero net id -> peer id
var _dummies: Array = []      # [HeroBody, ScriptedInputSource]
var _map: Node3D
var _cmd := InputCommand.new()
var _tracer := HitscanTracer.new()
## Hero weapon bolts in flight (Halo Repeater); see WeaponBolts.
var bolts := WeaponBolts.new()
var _no_targets: Array[HeroBody] = []
var _events: Dictionary = {}  # peer id -> Array[GameEvent] (flushed every tick)
## E7 presence seam: non-hero sources (Wardlings) counted by hardpoint zones.
var _presence_sources: Array = []
## E7 hardpoints (null on maps without a MapDef).
var objectives: ObjectiveSystem
var _hero_presence: Dictionary = {}  # hero net id -> PresenceSource
## E14 Breach: one targetable body per Ward Generator (Breach hardpoints).
var generators: Array[GeneratorTarget] = []
## E14 Plant: hero net id -> TaskActor, refreshed every tick (interact held, CC, dash).
var _task_actors: Dictionary = {}
## Debug (--debug-capture): where joining clients spawn instead of PlayerSpawn.
var debug_player_spawn: Variant = null
## E8 Wardlings (squads, Vanguard, bolts); null on maps without a MapDef.
var wardlings: WardlingWorld
## W16-SDWATER: the map's wading zones, handed to every hero's motor each tick.
var _water_zones: Array = []
## E9 match flow (phases, clock, Uplinks); null until setup_match().
var match_flow: MatchRules
## Map of the running match (Sudden Death plaza centre).
var _sd_map: MapDef
## E10 skills: deployables, skill projectiles, charges, leaps, skill FX.
var abilities: AbilityWorld
## C5 Supply Caches of held hardpoints; null without objectives.
var supply: SupplyCacheSystem
## E13/E15 Lumen, Armory, Resonance, levels, skill tree; null until enable_progression().
var progression: ProgressionSystem
## W10-W4 per-hero match statistics (post-match screen); sent at match end.
var stats: MatchStats = MatchStats.new()
var _stats_sent: bool = false
## Stable content indices for the wire (hero identity in snapshots).
var content: ContentDB = ContentDB.shared()
## Armory v2 ammo effects (weapons-and-mods.md §3.7): Burn, Shock, Siphon, Cryo,
## Brittle, mods. Hero states live in StatusComponent.ammo, Wardlings' here.
var ammo_fx: AmmoEffects
## Hero net id -> last tick it took or dealt damage (Stride Rig out-of-combat speed).
var _last_combat_tick: Dictionary = {}


## Builds the map and session. Call after the node is in the tree.
## `hero_def` is the HeroDef for joining clients; `match_rules` the respawn rules.
func setup(net_config: NetConfig, movement_def: MovementDef, map_scene: PackedScene, transport: Transport,
		hero_def: HeroDef = null, match_rules: MatchRulesDef = null) -> void:
	net = net_config
	_tracer.rewind_ticks = roundi(net.max_rewind_ms * net.tick_rate_hz / 1000.0)  # lag compensation window
	movement = movement_def
	player_hero = hero_def if hero_def != null else HeroDef.new()
	rules = match_rules if match_rules != null else MatchRulesDef.new()
	dt = net.tick_dt()
	registry = EntityRegistry.new(roundi(net.net_id_recycle_s * net.tick_rate_hz))
	session = ServerSession.new(transport, net)
	session.client_joined.connect(_on_client_joined)
	abilities = AbilityWorld.new(self)
	ammo_fx = AmmoEffects.new(DamageMath.rules(), net.tick_rate_hz)
	_setup_stats()
	_map = map_scene.instantiate()
	add_child(_map)


## W10-W4: counters fed by the damage / death signals (healing: _spawn_hero).
func _setup_stats() -> void:
	var f := load(MVP_FORMULA_PATH) as MvpFormulaDef
	if f != null:
		stats.assist_window_ticks = roundi(f.assist_window_s * net.tick_rate_hz)
	hero_damaged.connect(func(victim: int, attacker: int, amount: float) -> void:
		stats.record_damage(attacker, victim, amount, tick)
		_note_combat(victim)
		_note_combat(attacker))
	hero_died.connect(func(victim: int, killer: int) -> void:
		stats.record_death(victim, killer, tick, hero(killer) != null))


## Final per-hero rows (net id -> {MatchStats.Stat -> float}).
func match_summary() -> Dictionary:
	var identity := {}
	for h: HeroBody in _hero_bodies():
		var d := {"team": h.combat.team, "level": h.combat.level}
		if h.combat.def != null:
			d["hero"] = content.index_of(ContentDB.HERO, h.combat.def.id)
		if progression != null:
			var p: HeroProgress = progression.progress.get(h.net_id)
			if p != null:
				d["lumen"] = p.total_earned()
				d["level"] = p.level
		identity[h.net_id] = d
	return stats.summary(identity)


## E7: builds the hardpoints from `map_def` (call after setup()).
func setup_objectives(map_def: MapDef) -> void:
	_water_zones = map_def.water_zones if map_def != null else []
	if map_def != null and not map_def.lanes.is_empty():
		objectives = ObjectiveSystem.new(map_def, rules)
		supply = SupplyCacheSystem.new(objectives, rules)  # C5 Supply Caches
		SupplyCacheSystem.add_bodies(self, map_def)
		for h in objectives.all:
			if h.task == HardpointDef.TaskKind.BREACH:
				var g := GeneratorTarget.new()
				g.setup(h, rules)
				add_child(g)
				g.net_id = registry.register(g, GeneratorTarget.KIND_GENERATOR, tick)
				generators.append(g)


## E14: the Generator body of Breach hardpoint `h`, or null.
func generator_of(h: HardpointSim) -> GeneratorTarget:
	for g in generators:
		if g.hp_sim == h:
			return g
	return null


## E14 Breach: a hit on a Generator from `team`, fired from `source_pos`
## (Wardling bolts are scaled by generator_wardling_damage_scale). Counts only
## while the match is live. Returns the HP removed.
func damage_generator(g: GeneratorTarget, amount: float, team: int, source_pos: Vector3, from_wardling: bool) -> float:
	if objectives == null or g == null or (match_flow != null and not match_flow.is_live()):
		return 0.0
	var a := amount * (rules.generator_wardling_damage_scale if from_wardling else 1.0)
	return objectives.damage_generator(g.hp_sim, a, team, source_pos)


## E9: match state machine and one UplinkSim per HQ (call after
## setup_objectives()). `clock_scale` > 1 compresses the timeline (debug).
func setup_match(map_def: MapDef, clock_scale: float = 1.0) -> MatchRules:
	match_flow = MatchRules.new(rules, objectives)
	match_flow.clock_scale = clock_scale
	for u in match_flow.build_uplinks(map_def):
		add_child(u)
		u.net_id = registry.register(u, UplinkSim.KIND_UPLINK, tick)
		u.destroyed.connect(match_flow.on_uplink_destroyed.bind(u.team))
	match_flow.surge_started.connect(_on_surge_started)
	match_flow.sudden_death_started.connect(_on_sudden_death_started.bind(map_def))
	_sd_map = map_def
	return match_flow


## E8: enables Wardlings (squads + Vanguard) on a map with HQs. The AI is
## wired separately from a higher layer (WardlingDirector.attach(server)).
func enable_wardlings(map_def: MapDef, wardling_rules: WardlingRulesDef, picket: WardlingDef) -> WardlingWorld:
	if map_def == null or map_def.hqs.is_empty() or wardling_rules == null or picket == null:
		return null
	wardlings = WardlingWorld.new(self, map_def, wardling_rules, picket)
	return wardlings


## E13/E15: Lumen, Armory, Resonance and the skill tree for every hero (call
## after setup_objectives() / enable_wardlings(); `map_def` gives the Armory pads).
func enable_progression(economy: EconomyRulesDef, catalog: ArmoryCatalogDef, map_def: MapDef = null) -> ProgressionSystem:
	progression = ProgressionSystem.new(self, economy, catalog, map_def)
	return progression


# --- E13/E15 bot-facing API (results are HeroProgress.Result; OK = 0) ---------------

## Spends a skill point on `slot` (0..2 basics, 3 ultimate): the next node
## (Unlock -> Boost; Ult rank 1 -> 3), or `node_kind` (SkillNodeDef.Kind) if given.
func learn_skill(h: HeroBody, slot: int, node_kind: int = -1) -> int:
	return progression.learn(h, slot, node_kind) if progression != null else HeroProgress.Result.DISABLED


## Buys `item_id` (ArmoryItemDef.id) at `tier` (0 = next tier). Only on the own HQ Armory pad.
func buy(h: HeroBody, item_id: StringName, tier: int = 0) -> int:
	return progression.buy(h, item_id, tier) if progression != null else HeroProgress.Result.DISABLED


## Sells the mount in `socket` (ArmoryItemDef.Socket): 100% this visit, else 60%.
func sell_mount(h: HeroBody, socket: int) -> int:
	return progression.sell(h, socket) if progression != null else HeroProgress.Result.DISABLED


func use_medpack(h: HeroBody) -> int:
	return progression.use_medpack(h) if progression != null else HeroProgress.Result.DISABLED


## Weapon damage of one body hit at `distance` m against `target_class`
## (DamageMath.TARGET_*), before the target's armor: level, items (G_hit with the
## 2.25 clamp, items-and-armory.md §4.3), headshot bonus and ammo.
func weapon_hit_damage(h: HeroBody, distance: float, headshot: bool = false,
		target_class: int = DamageMath.TARGET_HERO) -> float:
	var c := h.combat
	if c.weapon == null:
		return 0.0
	var wdef := c.weapon.def
	var fr: float = DamageMath.range_conversion(wdef, c.stats.get_value(StatCatalog.FALLOFF_RANGE))[0]
	var pot := ammo_fx.potency(c.ammo_type, c.ammo_mod)
	return DamageMath.hit_damage(wdef, distance, headshot, 1, fr, c.stats.get_value(StatCatalog.HEADSHOT_BONUS)) \
		* c.stats.get_value(StatCatalog.WEAPON_DAMAGE) \
		* DamageMath.weapon_hit_mult(c.stats.get_value(StatCatalog.MOD_DAMAGE), c.stats.get_value(StatCatalog.FIRE_RATE_BONUS),
			c.stats.get_value(StatCatalog.DAMAGE_DEALT), 1.0, 0.0, DamageMath.rules().is_beam(wdef)) \
		* DamageMath.ammo_mult(c.ammo_type, target_class, false, pot)


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


## Match time in seconds: the E9 match clock, or server ticks without one.
func match_seconds() -> float:
	return match_flow.time_s if match_flow != null else tick * dt


## E14 soak telemetry: wall-clock µs of each step() (measurement only).
var tick_usec: PackedInt32Array = PackedInt32Array()


## {p50_ms, p95_ms, max_ms, ticks} of step() wall time so far.
func tick_time_summary() -> Dictionary:
	if tick_usec.is_empty():
		return {"p50_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0, "ticks": 0}
	var s := tick_usec.duplicate()
	s.sort()
	return {
		"p50_ms": snappedf(s[s.size() / 2] / 1000.0, 0.001),
		"p95_ms": snappedf(s[mini(s.size() - 1, int(s.size() * 0.95))] / 1000.0, 0.001),
		"max_ms": snappedf(s[s.size() - 1] / 1000.0, 0.001),
		"ticks": s.size(),
	}


## One server tick.
func step() -> void:
	var t0 := Time.get_ticks_usec()
	bolts.launched.clear()
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
	_step_bolts()
	_step_ammo()  # Armory v2: Burn ticks, Chill / Scorched, meter decay
	if wardlings != null:
		wardlings.step()
	abilities.step()
	_respawn_due()
	_step_objectives()
	_step_match()
	if progression != null:
		progression.step()  # E13/E15 income, Armory visits, Motes, Med-Packs
	_tracer.record(tick, _hero_bodies())  # lag compensation: pose history per tick
	_send_snapshots()
	_flush_events()
	session.log_stats(tick)  # W16-NET: [net] line per client every 10 s (dedicated only)
	tick += 1
	tick_usec.append(Time.get_ticks_usec() - t0)


## E14 Plant: what this hero does for the tasks this tick (interact, CC, dash).
func _note_actor(h: HeroBody, cmd: InputCommand) -> void:
	var a: TaskActor = _task_actors.get(h.net_id)
	if a == null:
		a = TaskActor.new()
		a.net_id = h.net_id
		_task_actors[h.net_id] = a
	var c := h.combat
	a.team = c.team
	a.alive = not c.dead
	a.interact = not c.dead and cmd.has(InputCommand.BTN_INTERACT)
	a.can_channel = not (c.status.is_stunned() or c.status.is_immobile())
	a.mobility = c.abilities.is_dashing()


## Stage 9 (architecture.md §8.3): hardpoint presence, tasks and ownership.
func _step_objectives() -> void:
	if objectives == null:
		return
	var actors: Array = []
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
		var a: TaskActor = _task_actors.get(id)
		if a != null:
			a.position = h.state.position
			a.alive = not h.combat.dead
			actors.append(a)
	sources.append_array(_presence_sources)
	objectives.step(dt, sources, tick, actors)
	for ev in objectives.events:
		objective_event.emit(ev)
	if supply != null:
		supply.step(dt, match_seconds(), tick, net.tick_rate_hz, _hero_bodies())


## E9: match clock, phases, Uplink exposure; phase changes go out as events.
func _step_match() -> void:
	if match_flow == null:
		return
	match_flow.step(dt)
	for p in match_flow.phase_events:
		var ev := GameEvent.match_phase(p, match_flow.winner, match_flow.end_reason, match_flow.time_s)
		for peer in session.clients:
			_queue_event(peer, ev)
	match_flow.phase_events.clear()
	if match_flow.is_over() and not _stats_sent:
		_stats_sent = true
		var evs := MatchStats.to_events(match_summary())
		for peer in session.clients:
			for ev in evs:
				_queue_event(peer, ev)
	if match_flow.phase == MatchRules.Phase.SUDDEN_DEATH:
		_step_sudden_death()
	if match_flow.is_over() and wardlings != null:
		wardlings.vanguard_enabled = false


## C10 Sudden Death start: every hero, alive or dead, is revived at full health
## on its team's plaza pad (MapDef.sudden_death_spawns); waves stop.
func _on_sudden_death_started(map_def: MapDef) -> void:
	if wardlings != null:
		wardlings.vanguard_enabled = false
	var k := [0, 0]
	for id in registry.ids():
		var h := registry.get_node_by_id(id) as HeroBody
		if h == null or h.combat == null:
			continue
		var team := h.combat.team
		var pad := team_spawn(team, h.combat.home_spawn)
		if map_def != null and team >= 0 and team < map_def.sudden_death_spawns.size():
			pad = map_def.sudden_death_spawns[team]
		var n: int = k[clampi(team, 0, 1)]
		k[clampi(team, 0, 1)] = n + 1
		var fresh := MotorState.new()
		fresh.position = pad + Vector3((float(n) - 2.0) * 2.5, 0.0, 0.0)
		h.state.copy_from(fresh)
		h.collision_layer = HeroBody.LAYER_HEROES
		h.motor.restore(h.state)
		h.combat.reset_for_respawn(false)
		hero_respawned.emit(id)


## C10 each tick: ring + Leyfall Bloom damage, then last-team-standing.
func _step_sudden_death() -> void:
	var centre := _sd_map.mid_plaza_center if _sd_map != null else Vector3.ZERO
	var r := match_flow.sudden_death_radius()
	var alive := [0, 0]
	for id in registry.ids():
		var h := registry.get_node_by_id(id) as HeroBody
		if h == null or h.combat == null or h.combat.dead:
			continue
		var outside := MatchRules.outside_ring(centre, r, h.state.position)
		var frac := match_flow.sudden_death_damage_frac_s(outside)
		if frac > 0.0:
			damage_hero(h, DamageInfo.make(h.combat.health.max_hp * frac * dt * match_flow.clock_scale, 0, -1, 0, DamageInfo.Type.TRUE))
		if not h.combat.dead and h.combat.team >= 0 and h.combat.team <= 1:
			alive[h.combat.team] += 1
	match_flow.resolve_sudden_death(alive[0], alive[1])


func _on_surge_started(_index: int, _task_scale: float) -> void:
	if wardlings != null:
		wardlings.tier = match_flow.wardling_tier  # Wardling tier hook (stats: PLACEHOLDER)


## E9: a hit on an Uplink (hero hitscan 100%, Wardling bolt 50%). Counts only
## while it is Exposed this tick and the match is live. Returns Integrity removed.
func damage_uplink(u: UplinkSim, amount: float, from_wardling: bool) -> float:
	if match_flow == null or not match_flow.is_live():
		return 0.0
	return u.apply_damage(amount, from_wardling)


## Enemy Uplinks a pellet from `team` can hit (none once the match is over).
func _enemy_uplinks(team: int) -> Array[UplinkSim]:
	var out: Array[UplinkSim] = []
	if match_flow != null and match_flow.is_live():
		for u in match_flow.uplinks:
			if u.team != team and not u.is_destroyed():
				out.append(u)
	return out


static func _alive_check(h: HeroBody) -> Callable:
	return func() -> bool: return is_instance_valid(h) and not h.combat.dead


func _step_hero(h: HeroBody, cmd: InputCommand) -> void:
	var c := h.combat
	c.local_tick += 1
	if cmd.action != InputCommand.ACTION_NONE and progression != null:
		progression.handle_action(h, cmd)  # E13/E15 (also while dead)
	if c.dead:
		# Dead heroes stand still; the owning client zeroes the same fields so
		# prediction keeps matching (ClientWorld.tick()).
		cmd.move = Vector2.ZERO
		cmd.buttons = 0
	abilities.pre_move(h)  # E10: stat/status expiry, move-speed scale
	if objectives != null:
		h.state.speed_scale *= objectives.move_speed_mult(h.net_id)  # E14: Cell carrier 90%
		_note_actor(h, cmd)
	h.state.speed_scale *= _item_move_mult(h)  # Armory v2 move-speed items
	h.motor.water_zones = _water_zones  # W16-SDWATER: shared wading slow
	h.step(cmd, dt)
	if not c.dead and h.global_position.y < rules.kill_plane_y:
		# Fell through the map: kill so respawn and Cell drop logic run.
		damage_hero(h, DamageInfo.make(c.health.max_hp * 10.0, 0, -1, 0, DamageInfo.Type.TRUE))
		return
	var casts_before := _cast_counts(h)
	abilities.post_move(h, cmd)  # E10: charge contact, skill casts
	_broadcast_casts(h, casts_before)
	if cmd.squad_cmd != InputCommand.SQUAD_NONE and wardlings != null and not c.dead:
		wardlings.issue_command(h, cmd)
	if c.dead or c.weapon == null:
		return
	# heroes.md §3.1: no firing while sprinting.
	var sprinting := cmd.has(InputCommand.BTN_SPRINT) and cmd.move.y > 0.0 and not h.state.crouching
	_apply_weapon_items(c)
	if c.weapon.step(cmd, c.local_tick, not sprinting and c.can_shoot()):
		_fire(h, cmd)


## Resolves the shot the weapon just fired: pellets -> hitscan -> damage, or
## (projectile weapons) launches one bolt per pellet into `bolts`.
func _fire(h: HeroBody, cmd: InputCommand) -> void:
	var c := h.combat
	var w := c.weapon
	var origin := h.state.position + Vector3(0.0, h.eye_height(), 0.0)
	var fwd := Basis(Vector3.UP, h.look_yaw) * Basis(Vector3.RIGHT, h.look_pitch) * Vector3.FORWARD
	var dirs := w.pellet_directions(fwd)
	# items-and-armory.md §3.5: Liora converts falloff items to projectile speed, Hex to beam range.
	var conv := DamageMath.range_conversion(w.def, c.stats.get_value(StatCatalog.FALLOFF_RANGE))
	if w.def.projectile_speed > 0.0:
		var space := h.get_world_3d().direct_space_state
		for dir in dirs:
			bolts.spawn(h.net_id, w.def, origin, dir, cmd.view_tick, cmd.view_alpha, conv[1])
			# Client visual: the bolt's flight line up to the first wall.
			_tracer.trace(space, origin, dir, w.def.range_m, _no_targets, 0, 0.0)
			bolts.launched.append([origin, origin + dir * _tracer.last_limit])
		return
	_resolve_pellets(h, w.def, origin, dirs, w.def.range_m + conv[2], cmd.view_tick, cmd.view_alpha, 0.0, true)


## One tick of hero bolts (WeaponBolts documents the lag-compensation choice).
func _step_bolts() -> void:
	if bolts.bolts.is_empty():
		return
	bolts.step(1.0 / net.tick_rate_hz, _resolve_bolt, func(id: int) -> bool: return hero(id) != null)


## Sweeps one bolt segment; true when the bolt stopped. Poses are rewound to the
## shooter's view time advanced by the bolt's age (0 = current poses).
func _resolve_bolt(b: WeaponBolts.Bolt, seg: float) -> bool:
	var h := hero(b.owner_id)
	var vt := b.view_tick + b.age if b.view_tick > 0 else 0
	return _resolve_pellets(h, b.def, b.pos, [b.dir] as Array[Vector3], seg, vt, b.view_alpha, b.traveled, false)


## Traces `dirs` from `origin` for up to `max_range` with poses at the given view
## time and applies the damage. `dist_off` is the distance already flown (bolt
## falloff). Returns true if any pellet was stopped (hero, Wardling, structure, wall).
func _resolve_pellets(h: HeroBody, wdef: WeaponDef, origin: Vector3, dirs: Array[Vector3], max_range: float,
		view_tick: int, view_alpha: float, dist_off: float, tracers: bool) -> bool:
	var c := h.combat
	var stopped := false
	var targets := _hurtable_enemies(c.team)
	var space := h.get_world_3d().direct_space_state
	var ends: Array[Vector3] = []  # where each pellet stopped, for client tracers
	var per_target := {}  # net id -> [raw damage, flags, first point]
	var per_wardling := {}  # WardlingSim -> [raw damage, first point]
	var per_uplink := {}  # E9: UplinkSim -> [raw damage, first point]
	var uplinks := _enemy_uplinks(c.team)
	var gens := _enemy_generators(c.team)  # E14 Breach
	var per_gen := {}  # GeneratorTarget -> [raw damage, first point]
	var dealt := c.stats.get_value(StatCatalog.DAMAGE_DEALT)  # E10
	# items-and-armory.md §4.3: L × min(2.25, S_skill × G_hit) / (1 + M_rate), per target.
	var lvl := c.stats.get_value(StatCatalog.WEAPON_DAMAGE)  # E15 level L
	var m_dmg := c.stats.get_value(StatCatalog.MOD_DAMAGE)
	var m_rate := c.stats.get_value(StatCatalog.FIRE_RATE_BONUS)
	var beam := DamageMath.rules().is_beam(wdef)
	var wm := lvl * DamageMath.weapon_hit_mult(m_dmg, m_rate, 1.0, 1.0, 0.0, beam)  # structures: no S_skill
	var ammo := c.ammo_type  # E13 Chamber
	var pot := ammo_fx.potency(ammo, c.ammo_mod)
	var fr: float = DamageMath.range_conversion(wdef, c.stats.get_value(StatCatalog.FALLOFF_RANGE))[0]
	var hs_bonus := c.stats.get_value(StatCatalog.HEADSHOT_BONUS)
	for dir in dirs:
		var clip := abilities.clip_shot(origin, dir, max_range, c.team)  # E10: enemy shield walls
		var hit := _tracer.trace(space, origin, dir, clip[0], targets, view_tick, view_alpha)
		var end_d := hit.distance if hit.target != null else minf(_tracer.last_limit, clip[0])
		if wardlings != null:
			var wl := wardlings.trace_wardlings(origin, dir, hit.distance if hit.target != null else _tracer.last_limit, c.team)
			if not wl.is_empty():
				end_d = float(wl[1])
				stopped = true
				ends.append(origin + dir * end_d)
				if not per_wardling.has(wl[0]):
					per_wardling[wl[0]] = [0.0, origin + dir * float(wl[1])]
				# heroes.md §3.7: Wardlings are gadgets (Hex Signal Sight +50 %).
				per_wardling[wl[0]][0] += DamageMath.hit_damage(wdef, wl[1] + dist_off, false, 1, fr) \
					* DamageMath.ammo_mult(ammo, DamageMath.TARGET_CONSTRUCT, false, pot) * c.def.gadget_damage_mult
				continue
		ends.append(origin + dir * end_d)
		if hit.target != null or end_d < max_range - 1e-3:
			stopped = true
		if not uplinks.is_empty() and _pellet_hits_uplink(uplinks, origin, dir, hit, per_uplink, wdef, wm, dist_off):
			stopped = true
			continue
		if not gens.is_empty() and _pellet_hits_generator(gens, origin, dir, hit, per_gen, wdef,
				wm * DamageMath.ammo_mult(ammo, DamageMath.TARGET_STRUCTURE, false, pot), dist_off):
			stopped = true
			continue
		if hit.target == null:
			if clip[1] != null and _tracer.last_limit >= clip[0] - 1e-3:
				abilities.damage_deployable(clip[1], DamageMath.hit_damage(wdef, clip[0] + dist_off, false, 1, fr) * wm * dealt
					* DamageMath.ammo_mult(ammo, DamageMath.TARGET_CONSTRUCT, true, pot))
				abilities.blocked_shots += 1
			continue
		var raw := DamageMath.hit_damage(wdef, hit.distance + dist_off, hit.headshot, 1, fr, hs_bonus) \
			* DamageMath.ammo_mult(ammo, DamageMath.TARGET_HERO, false, pot)
		var id := hit.target.net_id
		if not per_target.has(id):
			per_target[id] = [0.0, 0, hit.point]
		per_target[id][0] += raw
		if hit.headshot:
			per_target[id][1] |= GameEvent.FLAG_HEADSHOT
	if tracers:
		_broadcast_tracers(h.net_id, ends)
	for id in per_target:
		var target := hero(id)
		var rec: Array = per_target[id]
		var dmg_flags: int = DamageInfo.FLAG_HEADSHOT if (rec[1] & GameEvent.FLAG_HEADSHOT) != 0 else 0
		var tst := target.combat.status.ammo
		var s_skill := abilities.extras.shot_mult(h, target) * dealt
		var mult := lvl * DamageMath.weapon_hit_mult(m_dmg, m_rate, s_skill, ammo_fx.brittle(tst, tick),
			ammo_fx.burn_share(ammo, c.ammo_mod, DamageMath.TARGET_HERO), beam)
		var info := DamageInfo.make(rec[0] * mult, h.net_id, c.team, dmg_flags)
		info.armor_pen = DamageMath.ammo_armor_pen(ammo, pot) + c.stats.get_value(StatCatalog.ARMOR_PEN_BONUS)  # Piercing + Bore items
		var applied := target.combat.health.apply_damage(info)
		if applied > 0.0:
			hero_damaged.emit(id, h.net_id, applied)
			hero_damage_taken.emit(id, applied, DamageInfo.Type.WEAPON)
		var final := applied + target.combat.health.last_absorbed
		if final > 0.0:
			_apply_ammo_hit(h, tst, DamageMath.TARGET_HERO, final, target, target.state.position)
		var ev_flags: int = rec[1]
		if not target.combat.health.is_alive() and not target.combat.dead:
			ev_flags |= GameEvent.FLAG_KILL
			var vpos := target.state.position
			_kill(target, h.net_id)
			_volatile(h, tst, vpos)
		elif not target.combat.health.is_alive():
			ev_flags |= GameEvent.FLAG_KILL
		_queue_event(_peer_of.get(h.net_id, 0), GameEvent.hit_confirm(id, h.net_id, applied, ev_flags, rec[2]))
	for wd in per_wardling:
		var wrec: Array = per_wardling[wd]
		var wst := ammo_fx.state_for(wd)
		var wmult := lvl * DamageMath.weapon_hit_mult(m_dmg, m_rate, dealt, ammo_fx.brittle(wst, tick),
			ammo_fx.burn_share(ammo, c.ammo_mod, DamageMath.TARGET_CONSTRUCT), beam)
		var wapplied := wardlings.damage_wardling(wd, DamageInfo.make(wrec[0] * wmult, h.net_id, c.team))
		if wapplied > 0.0:
			_note_combat(h.net_id)
			_apply_ammo_hit(h, wst, DamageMath.TARGET_CONSTRUCT, wapplied + wd.health.last_absorbed, null, wd.global_position)
			if wd.dead:
				_volatile(h, wst, wd.global_position)
		var wflags: int = GameEvent.FLAG_KILL if wd.dead else 0
		_queue_event(_peer_of.get(h.net_id, 0), GameEvent.hit_confirm(wd.net_id, h.net_id, wapplied, wflags, wrec[1]))
	for g in per_gen:
		var grec: Array = per_gen[g]
		var gapplied := damage_generator(g, grec[0], c.team, h.state.position, false)
		stats.record_objective(h.net_id, gapplied)
		_queue_event(_peer_of.get(h.net_id, 0), GameEvent.hit_confirm(g.net_id, h.net_id, gapplied,
			0 if gapplied > 0.0 else GameEvent.FLAG_IMMUNE, grec[1]))
	for u in per_uplink:
		var urec: Array = per_uplink[u]
		var uapplied := damage_uplink(u, urec[0], false)
		stats.record_objective(h.net_id, uapplied)
		var uflags: int = 0 if u.exposed else GameEvent.FLAG_IMMUNE
		_queue_event(_peer_of.get(h.net_id, 0), GameEvent.hit_confirm(u.net_id, h.net_id, uapplied, uflags, urec[1]))
	return stopped


## E9: nearest Uplink in front of the hero hit and the static wall; accumulates
## the raw weapon damage (no headshot, no ammo effects: C7). True if it took the pellet.
func _pellet_hits_uplink(uplinks: Array[UplinkSim], origin: Vector3, dir: Vector3, hit: HitscanTracer.Hit,
		acc: Dictionary, wdef: WeaponDef, mult: float, dist_off: float = 0.0) -> bool:
	var limit := hit.distance if hit.target != null else _tracer.last_limit + 0.5
	for u in uplinks:
		var t := u.ray_hit(origin, dir)
		if t >= 0.0 and t <= limit:
			if not acc.has(u):
				acc[u] = [0.0, origin + dir * t]
			acc[u][0] += DamageMath.hit_damage(wdef, t + dist_off, false) * mult  # no ammo effects (C7)
			return true
	return false


## E14: enemy Generators standing (phase 1) that a pellet from `team` can hit.
func _enemy_generators(team: int) -> Array[GeneratorTarget]:
	var out: Array[GeneratorTarget] = []
	if match_flow == null or match_flow.is_live():
		for g in generators:
			if g.is_up() and g.team != team:
				out.append(g)
	return out


## E14: like _pellet_hits_uplink, for Ward Generators (weapon damage, no ammo effects).
func _pellet_hits_generator(gens: Array[GeneratorTarget], origin: Vector3, dir: Vector3, hit: HitscanTracer.Hit,
		acc: Dictionary, wdef: WeaponDef, mult: float, dist_off: float = 0.0) -> bool:
	var limit := hit.distance if hit.target != null else _tracer.last_limit + 0.5
	for g in gens:
		var t := g.ray_hit(origin, dir)
		if t >= 0.0 and t <= limit:
			if not acc.has(g):
				acc[g] = [0.0, origin + dir * t]
			acc[g][0] += DamageMath.hit_damage(wdef, t + dist_off, false) * mult
			return true
	return false


## E8: non-hitscan damage to a hero (Wardling bolts). Handles the kill.
func damage_hero(target: HeroBody, info: DamageInfo) -> float:
	if target.combat.dead:
		return 0.0
	var applied := target.combat.health.apply_damage(info)
	if applied > 0.0:
		hero_damaged.emit(target.net_id, info.source_net_id, applied)
		hero_damage_taken.emit(target.net_id, applied, info.type)
	if not target.combat.health.is_alive():
		_kill(target, info.source_net_id)
	return applied


## E10: hit marker / damage number for skill damage, to the caster's client.
func skill_hit_feedback(caster: HeroBody, target_id: int, applied: float, killed: bool, pos: Vector3) -> void:
	if applied <= 0.0 and not killed:
		return
	_queue_event(_peer_of.get(caster.net_id, 0),
		GameEvent.hit_confirm(target_id, caster.net_id, applied, GameEvent.FLAG_KILL if killed else 0, pos))


# --- Armory v2: items on the weapon and the body, ammo effects ----------------------

## Item stats on the weapon each tick (fire rate, spread; Overcharged costs),
## combined with skill buffs by WeaponSim (items-and-armory.md §3.5, §4.3).
func _apply_weapon_items(c: HeroCombat) -> void:
	c.weapon.apply_item_stats(c.stats)
	var costs := ammo_fx.feed_costs(c.ammo_type, c.ammo_mod)
	c.weapon.feed.cost_mult = costs[0]
	c.weapon.feed.reload_mult = costs[1]


## Move-speed items (items-and-armory.md §3.5): +item speed, +Cell carry while
## carrying a Mana Cell, +out-of-combat after AmmoRulesDef.out_of_combat_s
## without taking or dealing damage. 1.0 with no items.
func _item_move_mult(h: HeroBody) -> float:
	var s := h.combat.stats
	var bonus := s.get_value(StatCatalog.ITEM_MOVE_SPEED)
	if objectives != null and objectives.carriers.has(h.net_id):
		bonus += s.get_value(StatCatalog.CELL_CARRY_SPEED)
	var ooc := s.get_value(StatCatalog.OOC_MOVE_SPEED)
	if ooc > 0.0 and is_out_of_combat(h.net_id):
		bonus += ooc
	return 1.0 + bonus


## True if hero `net_id` has neither taken nor dealt damage for out_of_combat_s.
func is_out_of_combat(net_id: int) -> bool:
	var last: int = _last_combat_tick.get(net_id, -1000000)
	return tick - last >= roundi(ammo_fx.rules.out_of_combat_s * net.tick_rate_hz)


func _note_combat(net_id: int) -> void:
	if net_id > 0:
		_last_combat_tick[net_id] = tick


## Ammo state of an enemy object (HeroBody or WardlingSim).
func _ammo_state_of(o: Object) -> AmmoTargetState:
	if o is HeroBody:
		return (o as HeroBody).combat.status.ammo
	return ammo_fx.state_for(o)


## Alive enemies of `team` (heroes and Wardlings) within `radius` of `pos`,
## nearest first, without `exclude`.
func _enemies_near(pos: Vector3, team: int, radius: float, exclude: Object = null) -> Array:
	var found: Array = []
	var r2 := radius * radius
	for t in _hurtable_enemies(team):
		if t != exclude and t.state.position.distance_squared_to(pos) <= r2:
			found.append([t.state.position.distance_squared_to(pos), t])
	if wardlings != null:
		for w in wardlings.wardlings:
			if w != exclude and not w.dead and w.team != team and w.global_position.distance_squared_to(pos) <= r2:
				found.append([w.global_position.distance_squared_to(pos), w])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array = []
	for f in found:
		out.append(f[1])
	return out


## Ammo effect damage (Burn, arcs, Volatile) from `shooter_id` to a hero or Wardling.
func _ammo_damage(target: Object, shooter_id: int, team: int, amount: float, premitigated: bool) -> float:
	var flags := DamageInfo.FLAG_AMMO_EFFECT | (DamageInfo.FLAG_PREMITIGATED if premitigated else 0)
	var info := DamageInfo.make(amount, shooter_id, team, flags, DamageInfo.Type.WEAPON)
	if target is HeroBody:
		return damage_hero(target as HeroBody, info)
	if target is WardlingSim and wardlings != null:
		return wardlings.damage_wardling(target as WardlingSim, info)
	return 0.0


## Applies the shooter's ammo effects for one target's final damage.
func _apply_ammo_hit(h: HeroBody, st: AmmoTargetState, target_class: int, final: float,
		target_hero: HeroBody, pos: Vector3) -> void:
	var c := h.combat
	if c.ammo_type == DamageMath.AMMO_STANDARD or c.weapon == null:
		return
	var hit := AmmoEffects.Hit.new()
	hit.shooter_id = h.net_id
	hit.team = c.team
	hit.ammo = c.ammo_type
	hit.mod = c.ammo_mod
	hit.target_class = target_class
	hit.damage = final
	hit.tick = tick
	hit.mana_gun = c.weapon.def.feed_kind == WeaponDef.FeedKind.MANA
	var out := ammo_fx.apply_hit(st, hit)
	if out.heal > 0.0:
		c.health.heal(out.heal, h.net_id)
	if out.mana > 0.0 and c.weapon.feed is ManaPoolFeed:
		(c.weapon.feed as ManaPoolFeed).add_mana(out.mana)
	if out.overload:
		_ammo_arcs(h, pos, out, target_hero)
	if out.disrupt_s > 0.0 and target_hero != null and target_hero.combat.weapon != null:
		var f := target_hero.combat.weapon.feed
		f.disrupt(target_hero.combat.local_tick, f.ticks(out.disrupt_s), f.ticks(out.reload_penalty_s))
	if out.mark_s > 0.0 and target_hero != null:
		abilities.reveals.reveal(target_hero.net_id, c.team, roundi(out.mark_s * net.tick_rate_hz), tick)


## Shock Overload arcs: `out.arc_damage` to up to `out.arc_targets` other enemies.
func _ammo_arcs(h: HeroBody, pos: Vector3, out: AmmoEffects.Outcome, exclude: Object) -> void:
	var n := 0
	for e in _enemies_near(pos, h.combat.team, out.arc_radius, exclude):
		if n >= out.arc_targets:
			break
		_ammo_damage(e, h.net_id, h.combat.team, out.arc_damage, false)
		n += 1


## §3.7.2 Volatile on a kill by `h`'s weapon hit. Not recursive: burst damage is
## ammo-effect damage and never reaches this function.
func _volatile(h: HeroBody, victim: AmmoTargetState, pos: Vector3) -> void:
	var c := h.combat
	var out := ammo_fx.volatile_burst(victim, h.net_id, c.ammo_type, c.ammo_mod)
	if out.burst_radius <= 0.0:
		return
	if out.overload:
		_ammo_arcs(h, pos, out, null)
	if out.burst_heal > 0.0:
		var r2 := out.burst_heal_radius * out.burst_heal_radius
		for a in _hero_bodies():
			var ab := a as HeroBody
			if ab.combat.team == c.team and not ab.combat.dead and ab.state.position.distance_squared_to(h.state.position) <= r2:
				ab.combat.health.heal(out.burst_heal, h.net_id)
	if out.burst_burn <= 0.0 and out.burst_chill <= 0.0 and out.burst_construct_damage <= 0.0:
		return
	var dur := ammo_fx.duration(c.ammo_type, c.ammo_mod)
	for e in _enemies_near(pos, c.team, out.burst_radius):
		if out.burst_burn > 0.0:
			ammo_fx.add_burn(_ammo_state_of(e), h.net_id, c.team, out.burst_burn, dur)
		if out.burst_chill > 0.0:
			ammo_fx.add_chill(_ammo_state_of(e), out.burst_chill, tick, dur)
		if out.burst_construct_damage > 0.0 and e is WardlingSim:
			_ammo_damage(e, h.net_id, c.team, out.burst_construct_damage, false)


## Per tick: Burn damage, Chill slow and Scorched on heroes; Burn on Wardlings.
func _step_ammo() -> void:
	var cut := ammo_fx.rules.scorched_heal_cut
	for o in _hero_bodies():
		var hb := o as HeroBody
		var hc := hb.combat
		if hc == null or hc.dead:
			continue
		var st := hc.status.ammo
		for d in ammo_fx.step_target(st, tick):
			_ammo_damage(hb, d[0], d[1], d[2], true)
		if hc.dead:
			continue
		hc.status.set_chill_slow(ammo_fx.chill_slow(st), tick)
		hc.status.set_scorched(cut if st.is_burning() else 0.0, tick)
	if ammo_fx.others.is_empty():
		return
	ammo_fx.prune(func(k: Object) -> bool: return is_instance_valid(k) and not (k as WardlingSim).dead)
	for w in ammo_fx.others.keys():
		for d in ammo_fx.step_target(ammo_fx.others[w], tick):
			_ammo_damage(w, d[0], d[1], d[2], true)


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
	if match_flow != null:  # C11 on the real match clock (E9)
		var own := match_flow.uplink_of(c.team)
		c.respawn_tick = tick + RespawnSystem.respawn_ticks_at_minutes(rules, match_flow.minutes(), net.tick_rate_hz,
			own != null and own.exposed)  # E14 slice: Exposed teams respawn slower
	else:
		c.respawn_tick = tick + RespawnSystem.respawn_ticks(rules, tick, net.tick_rate_hz)
	victim.collision_layer = 0  # corpses do not block
	c.status.ammo.clear()  # Burn / Charge / Chill end with the hero
	var ev := GameEvent.kill(victim.net_id, killer_id, victim.state.position)
	for peer in session.clients:
		_queue_event(peer, ev)
	hero_died.emit(victim.net_id, killer_id)


func _respawn_due() -> void:
	if match_flow != null and match_flow.phase == MatchRules.Phase.SUDDEN_DEATH:
		return  # C10: no respawns in Sudden Death
	for id in registry.ids():
		var h := registry.get_node_by_id(id) as HeroBody
		if h == null or not h.combat.dead or tick < h.combat.respawn_tick:
			continue
		var fresh := MotorState.new()
		fresh.position = h.combat.home_spawn if _respawns_at_home(h) else team_spawn(h.combat.team, h.combat.home_spawn)
		var beacon: Variant = progression.respawn_point(h) if progression != null else null  # E13 Mid Beacon
		if beacon != null:
			fresh.position = beacon
		h.state.copy_from(fresh)
		h.collision_layer = HeroBody.LAYER_HEROES
		h.motor.restore(h.state)
		h.combat.reset_for_respawn(beacon == null)
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
	var hid := h.net_id
	h.combat.health.healed.connect(func(amount: float, src: int) -> void:
		stats.record_heal(src if src > 0 else hid, amount))
	return h


## The hero a joining peer picked in Hello, or the server default.
func _hero_for_peer(peer_id: int) -> HeroDef:
	var idx: int = session.hello_hero.get(peer_id, ContentDB.NONE)
	var id := ContentDB.shared().id_at(ContentDB.HERO, idx)
	if id != &"":
		var path := "%s/%s.tres" % [ContentDB.SOURCES[ContentDB.HERO][0], id]
		var def := load(path) as HeroDef if ResourceLoader.exists(path) else null
		if def != null:
			return def
	return player_hero


func _on_client_joined(peer_id: int) -> void:
	var def := _hero_for_peer(peer_id)
	var h: HeroBody = null
	var token: int = session.hello_token.get(peer_id, 0)
	var back: HeroBody = token_heroes.get(token) if token != 0 else null
	if back != null and is_instance_valid(back) and not _humans.values().has(back):
		h = back
		controller_taken.emit(h.net_id)
	elif token != 0 and reserved_slots.has(token):
		var slot: Dictionary = reserved_slots[token]
		reserved_slots.erase(token)
		h = _spawn_hero(team_spawn(slot.team, spawn_point(PLAYER_SPAWN)), def, slot.team)
	elif not _humans.is_empty() or not reserved_slots.is_empty() or token != 0:
		# Later players fill the team with fewer humans by taking over a bot.
		h = _take_over_scripted(_team_with_fewer_humans(), def)
	if h == null:
		var at: Vector3 = debug_player_spawn if debug_player_spawn != null else spawn_point(PLAYER_SPAWN)
		h = _spawn_hero(at, def, TEAM_PLAYERS)
	_humans[peer_id] = h
	_peer_of[h.net_id] = peer_id
	if token != 0:
		token_heroes[token] = h
	session.accept(peer_id, h.net_id, tick)


## A remote player disconnected: forget the peer and release its hero so a
## bot can drive it (controller_released).
func on_peer_left(peer_id: int) -> void:
	session.drop(peer_id)
	var h: HeroBody = _humans.get(peer_id)
	_humans.erase(peer_id)
	if h == null:
		return
	_peer_of.erase(h.net_id)
	controller_released.emit(h.net_id)


## Gives `hero_net_id` a scripted driver (e.g. a bot taking over a left player).
func attach_source(hero_net_id: int, source: Object) -> void:
	var h := hero(hero_net_id)
	if h != null:
		_dummies.append([h, source])


func _team_with_fewer_humans() -> int:
	var n := [0, 0]
	for p in _humans:
		var t: int = (_humans[p] as HeroBody).combat.team
		if t >= 0 and t <= 1:
			n[t] += 1
	return 0 if n[0] <= n[1] else 1


## Detaches a scripted hero of `team` (same hero as `def` if possible, else
## none: the joining client predicts with its own pick) and returns it.
func _take_over_scripted(team: int, def: HeroDef) -> HeroBody:
	for i in _dummies.size():
		var h: HeroBody = _dummies[i][0]
		if h.combat.team == team and h.combat.def != null and def != null \
				and h.combat.def.resource_path == def.resource_path:
			_dummies.remove_at(i)
			controller_taken.emit(h.net_id)
			return h
	return null


## Sends up to TRACERS_PER_SHOT pellet end points of one shot to every client
## (evenly picked for shotguns) so they can draw bullet tracers.
func _broadcast_tracers(shooter: int, ends: Array[Vector3]) -> void:
	if session.clients.is_empty() or ends.is_empty():
		return
	var step := maxi(1, ceili(float(ends.size()) / TRACERS_PER_SHOT))
	for i in range(0, ends.size(), step):
		var ev := GameEvent.shot(shooter, ends[i])
		for peer in session.clients:
			_queue_event(peer, ev)


## W11-V1: Fork / Mastery of the 3 basic skills as SnapshotData.EntityState.fork_bits.
func _fork_bits(h: HeroBody) -> int:
	var bits := 0
	for slot in 3:
		var sk := h.combat.abilities.skill(slot)
		if sk != null:
			bits = SnapshotData.EntityState.with_slot(bits, slot, sk.fork(), sk.has_mastery())
	return bits


func _cast_counts(h: HeroBody) -> PackedInt32Array:
	var out := PackedInt32Array([0, 0, 0, 0])
	for slot in 4:
		var sk := h.combat.abilities.skill(slot)
		if sk != null:
			out[slot] = sk.casts
	return out


## W11-V1: one SKILL_CAST event to every client per skill cast this tick (the caster's own
## client ignores it: it plays own casts from its cooldowns).
func _broadcast_casts(h: HeroBody, before: PackedInt32Array) -> void:
	if session.clients.is_empty():
		return
	for slot in 4:
		var sk := h.combat.abilities.skill(slot)
		if sk == null or sk.casts <= before[slot]:
			continue
		var fk := 0 if sk.def.ultimate else sk.fork()
		var ev := GameEvent.skill_cast(h.net_id, slot, fk, not sk.def.ultimate and sk.has_mastery(), h.state.position)
		for peer in session.clients:
			_queue_event(peer, ev)


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
		e.max_hp = ceili(h.combat.health.max_hp)  # E15 level scaling
		e.status = abilities.status_bits(h)  # E10
		if h.combat.def != null:
			e.hero_index = content.index_of(ContentDB.HERO, h.combat.def.id)  # M1 remote hero models
		e.fork_bits = _fork_bits(h)  # W11-V1 Pillar 4: everyone sees Fork / Mastery
		entities.append(e)
	# W16-NET: blocks every client gets alike are built once per tick (shared
	# objects also let the session encode each record once).
	var shared := SnapshotData.new()
	_fill_objectives(shared)
	_fill_match(shared)
	abilities.write_snapshot(shared)  # E10 skill FX
	if wardlings != null:
		wardlings.write_snapshot(shared)
	shared.bolts.append_array(bolts.launched)  # hero bolts reuse the Wardling bolt block
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
			abilities.fill_own(s.own_combat, own.combat)  # E10 skill bar
		s.entities = _entities_for(entities, c, own)
		if own != null and progression != null:
			progression.fill_own(s, own)  # E13/E15 own progress + learnable slots
		s.hardpoints = shared.hardpoints
		s.fronts = shared.fronts
		s.match_state = shared.match_state
		s.fx = shared.fx
		s.wardlings = shared.wardlings
		s.bolts = shared.bolts
		session.send_snapshot(peer, s)


## W11-M1: the shared entity list, with SkillStatusBits.REVEALED set (on copies)
## for the heroes revealed to this recipient's team. Other teams never see it.
func _entities_for(entities: Array[SnapshotData.EntityState], c: ServerSession.ClientConnection, own: HeroBody) -> Array[SnapshotData.EntityState]:
	if own == null or own.combat == null:
		return entities
	var ids := abilities.reveals.revealed_ids(own.combat.team, tick)
	if ids.is_empty():
		return entities
	var out: Array[SnapshotData.EntityState] = []
	for e in entities:
		if ids.has(e.net_id) and e.team != own.combat.team:
			var n := SnapshotData.EntityState.new()
			for p in ["net_id", "kind", "position", "velocity", "yaw", "pitch", "crouching", "grounded", "dead", "team", "hp", "max_hp", "hero_index", "fork_bits"]:
				n.set(p, e.get(p))
			n.status = e.status | SkillStatusBits.REVEALED
			out.append(n)
		else:
			out.append(e)
	return out


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
		st.task = h.task  # E14 Plant / Breach
		if progression != null and h.def.tier == HardpointDef.Tier.MID:  # Forward Beacon (§3.5)
			st.beacon = progression.beacon_state(h)
			st.beacon_attune = progression.beacon_attune(h) if st.beacon != ProgressionSystem.Beacon.NONE else 0.0
		if h.task == HardpointDef.TaskKind.BREACH:
			st.breach_phase2 = h.breach_phase == 2
			st.gen_frac = h.gen_frac if h.breach_phase == 1 else 0.0
			st.shielded = h.gen_shielded and h.breach_phase == 1
		elif h.task == HardpointDef.TaskKind.PLANT:
			st.cell_state = h.cell_state
			st.cell_team = h.cell_team
			st.cell_pos = h.cell_pos
			st.carrier_id = h.carrier_id
			st.channel = h.channel
			var need := 0.0
			match h.channel:
				HardpointSim.Channel.PICKUP:
					need = rules.cell_pickup_s
				HardpointSim.Channel.PLANT:
					need = rules.plant_channel_s
				HardpointSim.Channel.DEFUSE:
					need = rules.defuse_channel_s
				HardpointSim.Channel.DISPERSE:
					need = rules.cell_disperse_s
			st.channel_frac = clampf(h.channel_t / need, 0.0, 1.0) if need > 0.0 else 0.0
		s.hardpoints.append(st)
	for lane in objectives.lanes.size():
		for team in 2:
			s.fronts.append(objectives.front.front_for(team, lane))


## E9: match phase, clock, result and both Uplinks.
func _fill_match(s: SnapshotData) -> void:
	if match_flow == null:
		return
	var m := SnapshotData.MatchState.new()
	m.phase = match_flow.phase
	m.time_s = match_flow.time_s
	m.next_phase_s = match_flow.next_phase_time()
	m.winner = match_flow.winner
	m.end_reason = match_flow.end_reason
	for u in match_flow.uplinks:
		var us := SnapshotData.UplinkState.new()
		us.team = u.team
		us.integrity = u.integrity
		us.max_integrity = u.max_integrity
		us.exposed = u.exposed
		m.uplinks.append(us)
	s.match_state = m


static func _own_combat(c: HeroCombat) -> SnapshotData.OwnCombat:
	var o := SnapshotData.OwnCombat.new()
	o.hp = ceili(c.health.hp)
	o.max_hp = ceili(c.health.max_hp)
	o.dead = c.dead
	o.respawn_tick = c.respawn_tick
	if c.weapon != null:
		var f := c.weapon.feed
		o.feed_kind = c.weapon.def.feed_kind
		o.ammo = f.current()
		o.ammo_capacity = f.capacity()
		o.reserve = f.reserve_count()
		o.ammo_flags = f.flags()
		# Armory v2 prediction parity: filled once OwnCombat carries these fields
		# (snippet in the C2 report); until then the client predicts v1 values.
		if "weapon_rate_mult" in o:
			o.set("weapon_rate_mult", c.weapon.total_rate_mult())
			o.set("weapon_spread_mult", c.weapon.spread_mult)
			o.set("weapon_recoil_mult", c.weapon.recoil_mult)
			o.set("weapon_kick_mult", c.stats.get_value(StatCatalog.RECOIL_MULT))
	return o


func _hero_bodies() -> Array:
	var out: Array = []
	for id in registry.ids():
		var h := registry.get_node_by_id(id) as HeroBody
		if h != null:
			out.append(h)
	return out


## Online lobby: how many reserved human slots each team has (bots skip them).
func reserved_per_team() -> Array[int]:
	var n: Array[int] = [0, 0]
	for t in reserved_slots:
		var team: int = reserved_slots[t].team
		if team >= 0 and team <= 1:
			n[team] += 1
	return n
