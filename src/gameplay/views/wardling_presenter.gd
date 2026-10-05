class_name WardlingPresenter
extends Node3D
## Client side of E8 (architecture.md §11: presentation only): interpolated
## WardlingViews, bolt tracers, the own squad list for the HUD strip, and the
## client-side crosshair resolution of squad orders (wardlings-and-economy.md §8):
##   Smart Command (Z tap): enemy under the crosshair (3° cone, <= 50 m, LOS)
##   -> Attack Target; else hardpoint zone / diamond -> Go Capture; else ground
##   (<= 25 m) -> Hold Here, or the own feet. The server re-validates all of it.
## Owned by ClientWorld (one child node), so ClientWorld only forwards snapshots,
## ticks and render calls.

## One entry of the own squad strip.
class SquadPip:
	var net_id: int
	var hp_frac: float
	## Squad.CMD_* of the squad.
	var command: int
	## WardlingSim.FLAG_* bits.
	var flags: int
	var dissolving: bool

## Height of a hardpoint's world-space HUD diamond above its zone centre.
const DIAMOND_UP_M: float = 6.0
const TRACER_LEN: float = 0.9
const TRACER_SPEED: float = 55.0
## Debug camera modes (--debug-camera): "" = first person.
const CAMERA_VANGUARD := "vanguard"

var client: ClientWorld
var rules: WardlingRulesDef = WardlingRulesDef.new()
var debug_camera: String = ""
## Own squad, ascending net id (HUD strip).
var own_squad: Array[SquadPip] = []
## Last resolution captured when the radial wheel opened.
var wheel_targets: Dictionary = {}
## Last order sent (HUD feedback / tests): [cmd, target, point].
var last_order: Array = []

var _views: Dictionary = {}  # net id -> WardlingView
var _buffers: Dictionary = {}  # net id -> InterpolationBuffer
var _states: Dictionary = {}  # net id -> SnapshotData.WardlingState
var _hero_teams: Dictionary = {}  # net id -> team
var _tracers: Array = []  # [MeshInstance3D, from, dir, length, travelled]
var _tracer_mat: Array[StandardMaterial3D] = []
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_ray.collision_mask = HeroBody.LAYER_WORLD
	for c in [WardlingView.COLOR_CONCORD, WardlingView.COLOR_SYNDICATE]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c.lightened(0.45)
		_tracer_mat.append(m)


func view(net_id: int) -> WardlingView:
	return _views.get(net_id)


func view_count() -> int:
	return _views.size()


func state(net_id: int) -> SnapshotData.WardlingState:
	return _states.get(net_id)


func apply_snapshot(s: SnapshotData) -> void:
	_hero_teams.clear()
	for e in s.entities:
		_hero_teams[e.net_id] = e.team
	var seen := {}
	own_squad.clear()
	for w in s.wardlings:
		seen[w.net_id] = true
		_states[w.net_id] = w
		var v: WardlingView = _views.get(w.net_id)
		if v == null:
			v = WardlingView.new()
			v.net_id = w.net_id
			v.tier = clampi(w.tier, 1, 3)  # before _ready: the model is built at this tier
			add_child(v)
			v.apply(w.position, w.yaw)
			_views[w.net_id] = v
			_buffers[w.net_id] = InterpolationBuffer.new(client.net.extrapolation_cap_ticks)
		if not w.stale:  # W16-NET: deferred Wardlings carry an older sample
			_buffers[w.net_id].push(s.tick, w.position, w.yaw, false)
		var kind := 0 if w.vanguard else (2 if w.owner_net_id == s.own_net_id and s.own_net_id != 0 else 1)
		v.set_state(w.team, w.hp_frac, kind)
		if clampi(w.tier, 1, 3) != v.tier:
			v.set_tier(w.tier)
		v.set_rewrite((w.state & (1 << 6)) != 0, (w.state & (1 << 7)) != 0)  # E10
		if kind == 2:
			var p := SquadPip.new()
			p.net_id = w.net_id
			p.hp_frac = w.hp_frac
			p.command = w.state & 7
			p.flags = (w.state >> 3) & 3
			p.dissolving = (w.state & WardlingWorld.STATE_DISSOLVING_BIT) != 0
			own_squad.append(p)
	for id in _views.keys():
		if not seen.has(id):
			_views[id].queue_free()
			_views.erase(id)
			_buffers.erase(id)
			_states.erase(id)
	for b in s.bolts:
		_spawn_tracer(b[0], b[1])


func render(render_tick: float, delta: float) -> void:
	for id in _views:
		var buf: InterpolationBuffer = _buffers[id]
		if buf.sample(render_tick):
			_views[id].apply(buf.position, buf.yaw)
	for i in range(_tracers.size() - 1, -1, -1):
		var t: Array = _tracers[i]
		t[4] += TRACER_SPEED * delta
		var mi: MeshInstance3D = t[0]
		if t[4] >= t[3]:
			mi.queue_free()
			_tracers.remove_at(i)
			continue
		mi.position = t[1] + t[2] * t[4]


## After the first-person rig is placed: debug camera overrides (--debug-camera).
func apply_debug_camera() -> void:
	if debug_camera == CAMERA_VANGUARD and client.rig != null:
		_vanguard_camera()


## Fills the squad fields of `cmd` (client-side resolution). SQUAD_SMART picks
## by priority; an explicit order from the radial uses the targets captured
## when the wheel opened. Unresolvable orders are dropped (SQUAD_NONE).
func resolve(cmd: InputCommand) -> void:
	if cmd.squad_cmd == InputCommand.SQUAD_NONE:
		return
	var t: Dictionary = wheel_targets if not wheel_targets.is_empty() else crosshair_targets(cmd.yaw, cmd.pitch)
	wheel_targets = {}
	var c := cmd.squad_cmd
	if c == InputCommand.SQUAD_SMART:
		if t.has("attack"):
			c = InputCommand.SQUAD_ATTACK
		elif t.has("capture"):
			c = InputCommand.SQUAD_CAPTURE
		else:
			c = InputCommand.SQUAD_HOLD
	cmd.squad_cmd = c
	match c:
		InputCommand.SQUAD_ATTACK:
			if not t.has("attack"):
				cmd.squad_cmd = InputCommand.SQUAD_NONE
				return
			cmd.squad_target = t["attack"]
		InputCommand.SQUAD_CAPTURE:
			if not t.has("capture"):
				cmd.squad_cmd = InputCommand.SQUAD_NONE
				return
			cmd.squad_target = t["capture"]
		InputCommand.SQUAD_HOLD:
			cmd.squad_point = t["hold"]
	last_order = [cmd.squad_cmd, cmd.squad_target, cmd.squad_point]


## Crosshair resolution for every command at once:
## {"attack": net id?, "capture": hardpoint index?, "hold": Vector3}.
func crosshair_targets(yaw: float, pitch: float) -> Dictionary:
	var out := {}
	var body := client.body
	if body == null:
		return out
	var feet := body.state.position
	var eye := feet + Vector3(0.0, body.eye_height(), 0.0)
	var fwd := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD
	var space := client.get_world_3d().direct_space_state
	var cone := deg_to_rad(rules.command_snap_cone_deg)
	var own_team := client.own_team()
	var best_ang := cone
	for id in client.remote_views():
		if _hero_teams.get(id, own_team) == own_team or not client.view(id).visible:
			continue
		var a := _aim_angle(space, eye, fwd, client.view(id).position + Vector3(0.0, 1.1, 0.0))
		if a <= best_ang:
			best_ang = a
			out["attack"] = id
	for id in _views:
		var st: SnapshotData.WardlingState = _states[id]
		if st.team == own_team:
			continue
		var a := _aim_angle(space, eye, fwd, _views[id].position + Vector3(0.0, 0.75, 0.0))
		if a <= best_ang:
			best_ang = a
			out["attack"] = id
	_ray.from = eye
	_ray.to = eye + fwd * 500.0
	var hit := space.intersect_ray(_ray)
	var ground: Variant = hit.get("position")
	if client.map_def != null and not client.map_def.lanes.is_empty():
		var hps: Array[HardpointDef] = []
		for lane in client.map_def.lanes:  # map-wide index order (W14: all lanes)
			hps.append_array(lane.hardpoints)
		for i in hps.size():
			var hp: HardpointDef = hps[i]
			var in_zone: bool = ground != null and WardlingWorld._flat(ground, hp.position) <= hp.zone_radius
			var diamond := fwd.angle_to(hp.position + Vector3(0.0, DIAMOND_UP_M, 0.0) - eye) <= cone
			if in_zone or diamond:
				out["capture"] = i
				break
	if ground != null and WardlingWorld._flat(ground, feet) <= rules.hold_ground_range_m:
		out["hold"] = ground
	else:
		out["hold"] = feet
	return out


## Angle between the aim and `target`, or INF when out of range or occluded.
func _aim_angle(space: PhysicsDirectSpaceState3D, eye: Vector3, fwd: Vector3, target: Vector3) -> float:
	var to := target - eye
	if to.length() > rules.command_range_m:
		return INF
	var a := fwd.angle_to(to)
	if a > deg_to_rad(rules.command_snap_cone_deg):
		return INF
	_ray.from = eye
	_ray.to = target
	return a if space.intersect_ray(_ray).is_empty() else INF


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var d := to - from
	var length := d.length()
	if length < 0.05:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.06, TRACER_LEN)
	mi.mesh = box
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var team := 0
	var best := INF
	for id in _views:  # tint by the nearest shooter's team
		var dd: float = _views[id].position.distance_squared_to(from)
		if dd < best:
			best = dd
			team = _states[id].team
	mi.material_override = _tracer_mat[clampi(team, 0, 1)]
	add_child(mi)
	mi.look_at_from_position(from, to, Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT)
	_tracers.append([mi, from, d / length, length, 0.0])


## Debug overview: a high third-person camera on the Concord Vanguard wave.
func _vanguard_camera() -> void:
	var c := Vector3.ZERO
	var n := 0
	for id in _views:
		var st: SnapshotData.WardlingState = _states[id]
		if st.vanguard and st.team == MapDef.TEAM_CONCORD:
			c += _views[id].position
			n += 1
	if n == 0:
		return
	c /= n
	var rig := client.rig
	rig.position = c + Vector3(7.0, 5.5, 7.0)
	rig.rotation = Vector3.ZERO
	rig.look_at(c + Vector3(0.0, 0.5, -4.0), Vector3.UP)
	rig.camera.rotation = Vector3.ZERO
	for child in rig.camera.get_children():
		(child as Node3D).visible = false  # no viewmodel in the overview
