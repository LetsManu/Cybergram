class_name ClientWorld
extends Node3D
## Client presentation world (architecture.md §2, §8.4): the client copy of the
## map, the predicted own hero (HeroBody + Predictor), interpolated remote
## HeroViews and the first-person rig. It never simulates authoritative state.
## Combat (E4/E5): the own hero's replicated health/feed (`combat`, read by the
## HUD), remote health on the views, and hit confirms / kills as signals.

## The server confirmed a hit by this client (hit marker, damage number).
signal hit_confirmed(event: GameEvent)
## Someone died (kill feed later; HUD uses it for the own death).
signal kill_received(event: GameEvent)
## E7: a replicated hardpoint changed owner (index into hardpoint_defs()).
signal hardpoint_owner_changed(index: int, old_team: int, new_team: int)
## E9: the match phase changed (MatchRules.Phase), from the reliable event.
signal match_phase_changed(phase: int)
## A shot was fired (any hero): drives bullet tracers.
signal shot_received(event: GameEvent)
## E9: the match ended (winner -1 = draw; reason = MatchRules.EndReason).
signal match_ended(winner: int, reason: int)
## E15: the own hero's level changed (HUD level-up flash).
signal level_changed(level: int)

var net: NetConfig
var movement: MovementDef
var hero_def: HeroDef
## Latest replicated combat state of the own hero (null until the first snapshot).
var combat: SnapshotData.OwnCombat
var session: ClientSession
var predictor: Predictor
var body: HeroBody
var rig: FirstPersonRig
## Object with sample(seq: int, out: InputCommand); PlayerInputSource or ScriptedInputSource.
var input_source: Object
var player_input: PlayerInputSource
var client_seq: int = 0
## Render-time estimate of the server tick (fractional).
var server_tick_estimate: float = 0.0

## E7: map layout (null = no objectives), replicated hardpoint states (lane-major,
## same order as hardpoint_defs()) and lane fronts ([concord, syndicate] per lane).
var map_def: MapDef
var hardpoints: Array[SnapshotData.HardpointState] = []
var fronts: PackedInt32Array = PackedInt32Array()
var _hp_defs: Array[HardpointDef] = []
var _hp_views: Array[HardpointView] = []

## E9: replicated match phase / clock / result / Uplinks (null until received).
var match_state: SnapshotData.MatchState
var _uplink_views: Array[UplinkView] = []

## E8: Wardling views, bolt tracers, own squad strip and squad-order resolution.
var wardlings: WardlingPresenter
## E10: skill FX / deployables (walls, beacons, telegraphs) and the own hero's
## replicated move-speed scale (fed to prediction).
var abilities: AbilityPresenter
var own_speed_scale: float = 1.0
## E13/E15: replicated own progression / wallet / mounts (null until received)
## and the Armory catalog (same data as the server: wire indices).
var progress: SnapshotData.ProgressState
var catalog: ArmoryCatalogDef
var _mote_views: Array[MeshInstance3D] = []
## Stable content indices (hero identity of remote views).
var content: ContentDB = ContentDB.shared()
var _hero_index: Dictionary = {}  # net id -> replicated hero index

var _views: Dictionary = {}  # net id -> HeroView
var tracers: TracerFx
var _buffers: Dictionary = {}  # net id -> InterpolationBuffer
var _prev_pos: Vector3
var _visual_offset: Vector3 = Vector3.ZERO
var _cmd := InputCommand.new()
var _look: LookSettings


func setup(net_config: NetConfig, movement_def: MovementDef, look: LookSettings,
		map_scene: PackedScene, transport: Transport, source: Object, hero: HeroDef = null) -> void:
	net = net_config
	movement = movement_def
	hero_def = hero if hero != null else HeroDef.new()
	_look = look
	input_source = source
	player_input = source as PlayerInputSource
	add_child(map_scene.instantiate())
	session = ClientSession.new(transport, net)
	if hero != null and hero.resource_path != "":
		session.hero_index = ContentDB.shared().index_of(ContentDB.HERO,
			StringName(hero.resource_path.get_file().get_basename()))
	session.snapshot_received.connect(_on_snapshot)
	session.event_received.connect(_on_event)
	wardlings = WardlingPresenter.new()
	wardlings.client = self
	add_child(wardlings)
	abilities = AbilityPresenter.new()
	abilities.client = self
	add_child(abilities)
	tracers = TracerFx.new()
	tracers.name = "Tracers"
	add_child(tracers)
	catalog = load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	session.connect_to_server()


## E7: builds the hardpoint views from `md` (null = none).
func setup_objectives(md: MapDef) -> void:
	map_def = md
	if md == null:
		return
	for lane in md.lanes:
		for d in lane.hardpoints:
			_hp_defs.append(d)
			var v := HardpointView.new()
			v.setup(d)
			add_child(v)
			_hp_views.append(v)
	for hq in md.hqs:
		var uv := UplinkView.new()
		uv.setup(hq)
		add_child(uv)
		_uplink_views.append(uv)


func hardpoint_defs() -> Array[HardpointDef]:
	return _hp_defs


## Team of the local player (offline: always the player team).
func own_team() -> int:
	return ServerWorld.TEAM_PLAYERS


## Index of the hardpoint whose zone holds the predicted own hero, or -1.
func own_hardpoint_index() -> int:
	if body == null:
		return -1
	var p := body.state.position
	for i in _hp_defs.size():
		var d := _hp_defs[i]
		if p.y >= d.position.y - 1.0 and p.y <= d.position.y + d.zone_height \
				and Vector2(p.x - d.position.x, p.z - d.position.z).length() <= d.zone_radius:
			return i
	return -1


## One client tick: sample input, predict, send.
func tick() -> void:
	if body == null:
		return
	client_seq += 1
	_prev_pos = body.state.position
	input_source.sample(client_seq, _cmd)
	if player_input != null and player_input.wheel_capture:
		player_input.wheel_capture = false  # radial: targets fixed when the wheel opens
		wardlings.wheel_targets = wardlings.crosshair_targets(_cmd.yaw, _cmd.pitch)
	if is_dead():
		_cmd.move = Vector2.ZERO  # mirrors ServerWorld._step_hero for the dead
		_cmd.buttons = 0
		_cmd.squad_cmd = InputCommand.SQUAD_NONE
	if _cmd.squad_cmd != InputCommand.SQUAD_NONE:
		wardlings.resolve(_cmd)
		_cmd.quantize()
	body.state.speed_scale = own_speed_scale  # E10: slows / roots / stances
	predictor.predict(_cmd)
	session.send_input(_cmd)


## Per rendered frame: interpolate remote views and place the camera.
func render(delta: float) -> void:
	var latest := float(session.latest_snapshot_tick)
	server_tick_estimate = clampf(server_tick_estimate + delta * net.tick_rate_hz, latest - 1.0, latest + 1.0)
	var render_tick := server_tick_estimate - net.interp_delay_ticks
	for id in _views:
		var buf: InterpolationBuffer = _buffers[id]
		if buf.sample(render_tick):
			_views[id].apply(buf.position, buf.yaw, buf.crouching)
	wardlings.render(render_tick, delta)
	if body == null:
		return
	if net.error_smoothing_s > 0.0:
		_visual_offset = _visual_offset.lerp(Vector3.ZERO, clampf(delta / net.error_smoothing_s, 0.0, 1.0))
	else:
		_visual_offset = Vector3.ZERO
	var frac := Engine.get_physics_interpolation_fraction()
	var feet := _prev_pos.lerp(body.state.position, frac) + _visual_offset
	var yaw := player_input.live_yaw if player_input != null else _cmd.yaw
	var pitch := player_input.live_pitch if player_input != null else _cmd.pitch
	rig.follow(feet, body.eye_height(), yaw, pitch)
	wardlings.apply_debug_camera()


func is_dead() -> bool:
	return combat != null and combat.dead


## Seconds until the own hero respawns (0 when alive).
func respawn_seconds_left() -> float:
	if not is_dead():
		return 0.0
	return maxf(0.0, (combat.respawn_tick - server_tick_estimate) / net.tick_rate_hz)


## Number of remote entity views (tests/diagnostics).
func view_count() -> int:
	return _views.size()


## Remote hero views by net id (read-only use).
func remote_views() -> Dictionary:
	return _views


func view(net_id: int) -> HeroView:
	return _views.get(net_id)


func _on_snapshot(s: SnapshotData) -> void:
	if server_tick_estimate < s.tick - 1:
		server_tick_estimate = s.tick
	if s.own_combat != null:
		combat = s.own_combat
	if s.own_state != null:
		if body == null:
			_spawn_own(s.own_state)
		else:
			_visual_offset += predictor.reconcile(s.own_state, s.last_processed_seq)
	_apply_objectives(s)
	_apply_match(s)
	_apply_progress(s.progress)  # E13/E15
	wardlings.apply_snapshot(s)
	abilities.apply_snapshot(s)  # E10
	if s.own_state != null:
		own_speed_scale = s.own_state.speed_scale
	var seen := {}
	for e in s.entities:
		if e.net_id == s.own_net_id:
			continue
		seen[e.net_id] = true
		if not _views.has(e.net_id):
			var v := HeroView.new()
			v.team = e.team
			_apply_hero(v, e)  # before _ready: the right model is built once
			add_child(v)
			_views[e.net_id] = v
			_buffers[e.net_id] = InterpolationBuffer.new(net.extrapolation_cap_ticks)
		elif _hero_index.get(e.net_id, -1) != e.hero_index:
			_apply_hero(_views[e.net_id], e)
		_buffers[e.net_id].push(s.tick, e.position, e.yaw, e.crouching)
		_views[e.net_id].set_health(e.hp, e.max_hp, e.dead)
		_views[e.net_id].set_status(e.status)  # E10
	for id in _views.keys():
		if not seen.has(id):
			_views[id].queue_free()
			_views.erase(id)
			_buffers.erase(id)
			_hero_index.erase(id)


## Replicated hero identity -> the view's model (ContentDB index -> HeroDef id).
func _apply_hero(v: HeroView, e: SnapshotData.EntityState) -> void:
	_hero_index[e.net_id] = e.hero_index
	var id := content.id_at(ContentDB.HERO, e.hero_index)
	if id != &"":
		v.set_hero(id, e.team)


## E13/E15: own progress, the FP gun's mounts and the Lumen Motes.
func _apply_progress(p: SnapshotData.ProgressState) -> void:
	if p == null:
		return
	var old := progress.level if progress != null else 1
	progress = p
	if p.level != old:
		level_changed.emit(p.level)
	if rig != null:
		rig.set_mounts(mount_items(), p.mount_tier)
	while _mote_views.size() < p.motes.size():
		var m := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.18
		sph.height = 0.36
		m.mesh = sph
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.3)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.8, 0.2)
		mat.emission_energy_multiplier = 2.0
		m.material_override = mat
		add_child(m)
		_mote_views.append(m)
	for i in _mote_views.size():
		_mote_views[i].visible = i < p.motes.size()
		if i < p.motes.size():
			_mote_views[i].position = p.motes[i] + Vector3(0.0, 0.6, 0.0)


## Mounted catalog items per ProgressState.MOUNT_SOCKETS slot (null = empty).
func mount_items() -> Array:
	var out := []
	for i in SnapshotData.ProgressState.MOUNT_SOCKETS.size():
		out.append(catalog.at(progress.mount_item[i]) if progress != null and catalog != null else null)
	return out


func _apply_objectives(s: SnapshotData) -> void:
	if s.hardpoints.is_empty():
		return
	fronts = s.fronts
	for i in s.hardpoints.size():
		var st := s.hardpoints[i]
		if i < hardpoints.size() and hardpoints[i].owner != st.owner:
			hardpoint_owner_changed.emit(i, hardpoints[i].owner, st.owner)
		if i < _hp_views.size():
			_hp_views[i].apply(st)
	hardpoints = s.hardpoints
	_mark_objectives()


## The own team's lane fronts (C15, replicated `fronts`) are the current
## objectives: their world labels stay up at any range (clutter fix).
func _mark_objectives() -> void:
	if map_def == null:
		return
	var base := 0
	var team := own_team()
	for lane in map_def.lanes.size():
		var n := map_def.lanes[lane].hardpoints.size()
		var front := fronts[lane * 2 + team] if lane * 2 + team < fronts.size() else -1
		for k in n:
			if base + k < _hp_views.size():
				_hp_views[base + k].set_objective(k == front)
		base += n


func _apply_match(s: SnapshotData) -> void:
	if s.match_state == null:
		return
	var was_over := match_state != null and match_state.phase == MatchRules.Phase.END
	match_state = s.match_state
	for u in match_state.uplinks:
		for v in _uplink_views:
			if v.team == u.team:
				v.apply(u)
	if not was_over and match_state.phase == MatchRules.Phase.END:
		match_ended.emit(match_state.winner, match_state.end_reason)


## E9: replicated Uplink state of `team`, or null.
func uplink_state(team: int) -> SnapshotData.UplinkState:
	if match_state == null:
		return null
	for u in match_state.uplinks:
		if u.team == team:
			return u
	return null


func uplink_views() -> Array[UplinkView]:
	return _uplink_views


func _spawn_own(state: MotorState) -> void:
	body = HeroBody.new()
	body.setup(hero_def.movement_for(movement), state.position, false)
	add_child(body)
	body.state.copy_from(state)
	body.place()
	body.net_id = session.own_net_id
	_prev_pos = state.position
	predictor = Predictor.new(net, body)
	rig = FirstPersonRig.new()
	rig.setup(_look)
	add_child(rig)


func _on_event(e: GameEvent, _server_tick: int) -> void:
	match e.kind:
		GameEvent.HIT_CONFIRM:
			hit_confirmed.emit(e)
		GameEvent.KILL:
			kill_received.emit(e)
		GameEvent.MATCH_PHASE:
			match_phase_changed.emit(e.target_net_id)
		GameEvent.SHOT:
			_draw_tracer(e)
			shot_received.emit(e)


## Tracer colours (saturated so they read on both the pale floor and dark sky):
## own shots yellow, allies azure, enemies ember red.
const TRACER_OWN := Color(1.0, 0.82, 0.1, 0.95)
const TRACER_ALLY := Color(0.25, 0.6, 1.0, 0.9)
const TRACER_ENEMY := Color(1.0, 0.25, 0.1, 0.95)
const REMOTE_MUZZLE_H := 1.45


func _draw_tracer(e: GameEvent) -> void:
	if tracers == null:
		return
	if e.source_net_id == session.own_net_id:
		var from := rig.camera.global_position if rig != null and rig.camera != null else e.position
		if rig != null and rig.weapon_model != null:
			var m := rig.weapon_model.socket(&"fx_muzzle")
			if m != null:
				from = m.global_position
		tracers.spawn(from, e.position, TRACER_OWN, true)
		return
	var v: HeroView = _views.get(e.source_net_id)
	if v == null:
		return
	var c := TRACER_ALLY if v.team == own_team() else TRACER_ENEMY
	tracers.spawn(v.global_position + Vector3(0.0, REMOTE_MUZZLE_H, 0.0), e.position, c)
