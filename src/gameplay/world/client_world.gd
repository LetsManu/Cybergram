class_name ClientWorld
extends Node3D
## Client presentation world (architecture.md §2, §8.4): the client copy of the
## map, the predicted own hero (HeroBody + Predictor), interpolated remote
## HeroViews and the first-person rig. It never simulates authoritative state.

var net: NetConfig
var movement: MovementDef
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

var _views: Dictionary = {}  # net id -> HeroView
var _buffers: Dictionary = {}  # net id -> InterpolationBuffer
var _prev_pos: Vector3
var _visual_offset: Vector3 = Vector3.ZERO
var _cmd := InputCommand.new()
var _look: LookSettings


func setup(net_config: NetConfig, movement_def: MovementDef, look: LookSettings,
		map_scene: PackedScene, transport: Transport, source: Object) -> void:
	net = net_config
	movement = movement_def
	_look = look
	input_source = source
	player_input = source as PlayerInputSource
	add_child(map_scene.instantiate())
	session = ClientSession.new(transport, net)
	session.snapshot_received.connect(_on_snapshot)
	session.connect_to_server()


## One client tick: sample input, predict, send.
func tick() -> void:
	if body == null:
		return
	client_seq += 1
	_prev_pos = body.state.position
	input_source.sample(client_seq, _cmd)
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


## Number of remote entity views (tests/diagnostics).
func view_count() -> int:
	return _views.size()


func view(net_id: int) -> HeroView:
	return _views.get(net_id)


func _on_snapshot(s: SnapshotData) -> void:
	if server_tick_estimate < s.tick - 1:
		server_tick_estimate = s.tick
	if s.own_state != null:
		if body == null:
			_spawn_own(s.own_state)
		else:
			_visual_offset += predictor.reconcile(s.own_state, s.last_processed_seq)
	var seen := {}
	for e in s.entities:
		if e.net_id == s.own_net_id:
			continue
		seen[e.net_id] = true
		if not _views.has(e.net_id):
			var v := HeroView.new()
			add_child(v)
			_views[e.net_id] = v
			_buffers[e.net_id] = InterpolationBuffer.new(net.extrapolation_cap_ticks)
		_buffers[e.net_id].push(s.tick, e.position, e.yaw, e.crouching)
	for id in _views.keys():
		if not seen.has(id):
			_views[id].queue_free()
			_views.erase(id)
			_buffers.erase(id)


func _spawn_own(state: MotorState) -> void:
	body = HeroBody.new()
	body.setup(movement, state.position, false)
	add_child(body)
	body.state.copy_from(state)
	body.place()
	body.net_id = session.own_net_id
	_prev_pos = state.position
	predictor = Predictor.new(net, body)
	rig = FirstPersonRig.new()
	rig.setup(_look)
	add_child(rig)
