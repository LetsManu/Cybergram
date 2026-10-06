extends SceneTree
## Standard camera presets for visual review (Phase 5, docs/visual-verification.md).
## Renders the map with the in-game objective views (the same HardpointView /
## UplinkView / ArmoryMarkerView the client spawns from the MapDef) and a hero
## for scale, from fixed presets, so before/after sets are comparable.
##
## Needs a display (render path 2, xvfb + Mesa):
##   xvfb-run -a -s "-screen 0 1600x900x24" $GODOT --path . --resolution 1600x900 \
##     -s res://tools/shot.gd -- --out production/qa/evidence/<set> [--only uplink,hold] [--list]
## --only takes name fragments (any preset whose name contains one is shot).
## --list prints the preset names and quits. Output: <out>/<preset>.png.
##
## Presets (all computed from map_front.tres, so they follow the layout):
##   fp-spawn-a / fp-spawn-b            first person at each HQ spawn, spawn yaw
##   fp-lane-<north|center|south>       first person at team A's Outer, towards Mid
##   topdown                            whole map from above
##   base-a / base-b                    HQ: Sanctum, Uplink, Foundry, Armory
##   <objective>-close|mid|far|approach Uplink A, one Hold, one Plant, one Breach
##                                      hardpoint, the Armory pad (6 / 15 / 35 m,
##                                      plus a first-person walk-up at 25 m)
##   hero-ref                           Vesper next to the Center Mid hardpoint (scale)
##   cradle-close / cradle-mid          a Concord Cell Cradle holding its Cell
##   wardlings                          Picket lineup: Concord tiers I-III (sash, own
##                                      sash), Syndicate Vanguard I-III, an Elite
## Objective state for the shots: the first Plant hardpoint has a Concord Cell
## planted (40 %), the other Plant hardpoints have their Concord Cell in its Cradle.

const MAP_DEF := "res://assets/data/match/map_front.tres"
const EYE := 1.7

var _out := "production/qa/evidence/shots"
var _only: PackedStringArray = []
var _cam: Camera3D
var _hero: Node3D
var _squad: Node3D
## The map's environment without fog (top-down only).
var _clear_env: Environment


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var list := false
	var i := 0
	while i < args.size():
		match args[i]:
			"--out":
				i += 1
				_out = args[i]
			"--only":
				i += 1
				_only = args[i].split(",", false)
			"--list":
				list = true
		i += 1
	var md := load(MAP_DEF) as MapDef
	var shots := presets(md)
	if list:
		for s in shots:
			print(s[0])
		quit()
		return
	DirAccess.make_dir_recursive_absolute(_out)
	if DisplayServer.get_name() == "headless":
		# Render path 1 gives no pixels (dummy renderer): fail loudly, never write blanks.
		push_error("[shot] NOT ASSESSED: --headless has no renderer; run under xvfb (docs/visual-verification.md)")
		quit(2)
		return
	# Watchdog: a hung render must not hang the caller (or CI).
	create_timer(float(OS.get_environment("SHOT_TIMEOUT_S")) if OS.get_environment("SHOT_TIMEOUT_S") != "" else 900.0) \
		.timeout.connect(func() -> void:
			push_error("[shot] NOT ASSESSED: watchdog timeout")
			quit(3))
	var map: Node3D = md.scene.instantiate()
	root.add_child(map)
	_add_views(md, map)
	_hero = _make_hero()
	map.add_child(_hero)
	_squad = _make_squad()
	map.add_child(_squad)
	_cam = Camera3D.new()
	_cam.fov = 75.0
	_cam.far = 2000.0
	map.add_child(_cam)
	_cam.current = true
	for n0 in map.find_children("*", "WorldEnvironment", true, false):
		if (n0 as WorldEnvironment).environment != null:
			_clear_env = (n0 as WorldEnvironment).environment.duplicate()
			_clear_env.fog_enabled = false
			_clear_env.volumetric_fog_enabled = false
	await _frames(20)
	var n := 0
	var bad := 0
	for s in shots:
		if not _wanted(s[0]):
			continue
		_hero.visible = String(s[0]) == "hero-ref"
		if _hero.visible:
			_hero.global_position = s[3]
			_hero.look_at(s[1] * Vector3(1, 0, 1) + Vector3(0, _hero.global_position.y, 0), Vector3.UP, true)
		_squad.visible = String(s[0]) == "wardlings"
		if _squad.visible:
			_squad.global_position = s[3]
			_squad.look_at(s[1] * Vector3(1, 0, 1) + Vector3(0, _squad.global_position.y, 0), Vector3.UP, true)
		_cam.global_position = s[1]
		_cam.look_at(s[2])
		_cam.environment = _clear_env if String(s[0]) == "topdown" else null
		await _frames(8)
		var img := root.get_texture().get_image()
		if img == null or img.is_empty() or _is_flat(img):
			push_error("[shot] NOT ASSESSED: %s rendered blank" % s[0])
			bad += 1
			continue
		img.save_png("%s/%s.png" % [_out, s[0]])
		n += 1
	print("[shot] %d presets -> %s, %d blank" % [n, _out, bad])
	quit(1 if bad > 0 or n == 0 else 0)


## [name, eye, target, extra] for every preset, from the MapDef.
static func presets(md: MapDef) -> Array:
	var out: Array = []
	var a: HqDef = md.hqs[0]
	var b: HqDef = md.hqs[1]
	for hq: HqDef in [a, b]:
		var tag := "a" if hq.team == a.team else "b"
		var sp: Vector3 = hq.spawn_points[0] if not hq.spawn_points.is_empty() else hq.sanctum
		var fwd := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(hq.spawn_yaw_deg))
		out.append(["fp-spawn-" + tag, sp + Vector3(0, EYE, 0), sp + fwd * 20.0 + Vector3(0, EYE * 0.8, 0)])
		var to_lane := (hq.lane_gate - hq.uplink).normalized()
		out.append(["base-" + tag, hq.uplink - to_lane * 28.0 + Vector3(0, 14, 0) + to_lane.cross(Vector3.UP) * 18.0,
			hq.uplink.lerp(hq.lane_gate, 0.35)])
	for lane: LaneDef in md.lanes:
		var hp := lane.hardpoints
		if hp.size() < 3:
			continue
		var outer: Vector3 = hp[1].position
		var mid: Vector3 = hp[2].position
		# 14 m past the Outer towards Mid: off its zone column, on the lane.
		var e := outer + (mid - outer).normalized() * 14.0
		out.append(["fp-lane-" + String(lane.id), e + Vector3(0, EYE, 0), mid + Vector3(0, EYE * 0.6, 0)])
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for hq: HqDef in md.hqs:
		lo = lo.min(hq.uplink)
		hi = hi.max(hq.uplink)
	var c := (lo + hi) * 0.5
	out.append(["topdown", c + Vector3(0, 330, 1), c])
	# Objectives: one of each kind, viewed from its own team's side.
	# key -> [target, the point the player walks up from]
	var sp_a: Vector3 = a.spawn_points[0] if not a.spawn_points.is_empty() else a.sanctum
	var picks := {"uplink": [a.uplink + Vector3(0, 6, 0), a.lane_gate], "armory": [a.armory + Vector3(0, 1, 0), sp_a]}
	var center: LaneDef = md.lanes[mini(1, md.lanes.size() - 1)]
	picks["mid-hardpoint"] = [center.hardpoints[2].position + Vector3(0, 1, 0), center.hardpoints[1].position]
	for lane: LaneDef in md.lanes:
		for k in lane.hardpoints.size():
			var d: HardpointDef = lane.hardpoints[k]
			var key: String = ["hold", "plant", "breach"][int(d.task)]
			if not picks.has(key):
				var from: Vector3 = lane.hardpoints[k - 1].position if k > 0 else a.lane_gate
				picks[key] = [d.position + Vector3(0, 1, 0), from]
	for key: String in picks:
		var t: Vector3 = picks[key][0]
		var from: Vector3 = picks[key][1]
		var back := (from - t) * Vector3(1, 0, 1)
		back = back.normalized() if back.length() > 0.1 else Vector3.BACK
		var side := back.cross(Vector3.UP)
		out.append([key + "-close", t + back * 6.0 + side * 2.0 + Vector3(0, 2.5, 0), t])
		out.append([key + "-mid", t + back * 15.0 + side * 5.0 + Vector3(0, 6.0, 0), t])
		out.append([key + "-far", t + back * 35.0 + side * 10.0 + Vector3(0, 14.0, 0), t])
		# First-person walk-up along the path the player takes, at most 25 m.
		var g := Vector3(t.x, t.y - 1.0, t.z) if key != "uplink" else a.uplink
		var d := clampf(((from - t) * Vector3(1, 0, 1)).length() * 0.8, 18.0, 25.0)
		out.append([key + "-approach", Vector3(g.x, from.y, g.z) + back * d + Vector3(0, EYE, 0), t])
	var hp_mid: Vector3 = center.hardpoints[2].position
	var hb := (a.uplink - hp_mid) * Vector3(1, 0, 1)
	hb = hb.normalized() if hb.length() > 0.1 else Vector3.BACK
	out.append(["hero-ref", hp_mid + hb * 8.0 + hb.cross(Vector3.UP) * 1.5 + Vector3(0, 1.6, 0),
		hp_mid + hb * 4.0 + Vector3(0, 1.0, 0), hp_mid + hb * 4.0])
	# Wardling lineup on the plaza outside the Mid dais, seen at squad distance.
	var w0 := hp_mid + hb * 12.0
	out.append(["wardlings", w0 + hb * 3.4 + Vector3(0, 1.0, 0), w0 + Vector3(0, 0.55, 0), w0])
	var plants := plant_defs(md)
	if plants.size() > 1:
		var cr: Vector3 = plants[1].cradle_for(MapDef.TEAM_CONCORD)
		var cb := (plants[1].position - cr) * Vector3(1, 0, 1)
		cb = cb.normalized() if cb.length() > 0.1 else Vector3.BACK
		var cs := cb.cross(Vector3.UP)
		out.append(["cradle-close", cr + cb * 3.2 + cs * 1.2 + Vector3(0, 1.7, 0), cr + Vector3(0, 0.8, 0)])
		out.append(["cradle-mid", cr + cb * 9.0 + cs * 3.0 + Vector3(0, 3.5, 0), cr + Vector3(0, 0.6, 0)])
	return out


## Plant hardpoints in preset order (the first is the `plant-*` one).
static func plant_defs(md: MapDef) -> Array[HardpointDef]:
	var out: Array[HardpointDef] = []
	for lane: LaneDef in md.lanes:
		for d: HardpointDef in lane.hardpoints:
			if d.task == HardpointDef.TaskKind.PLANT:
				out.append(d)
	return out


## True when a sampled grid of pixels is all one colour (nothing rendered).
static func _is_flat(img: Image) -> bool:
	var c0 := img.get_pixel(0, 0)
	for y in range(0, img.get_height(), maxi(1, img.get_height() / 16)):
		for x in range(0, img.get_width(), maxi(1, img.get_width() / 16)):
			if not img.get_pixel(x, y).is_equal_approx(c0):
				return false
	return true


func _wanted(name: String) -> bool:
	if _only.is_empty():
		return true
	for f in _only:
		if name.contains(f):
			return true
	return false


## The client's objective views (ClientWorld.setup_objectives), without a ClientWorld.
func _add_views(md: MapDef, map: Node3D) -> void:
	var first_plant: HardpointDef = plant_defs(md)[0] if not plant_defs(md).is_empty() else null
	for lane: LaneDef in md.lanes:
		for d: HardpointDef in lane.hardpoints:
			var v := HardpointView.new()
			v.setup(d)
			map.add_child(v)
			if d.task == HardpointDef.TaskKind.PLANT:
				var st := SnapshotData.HardpointState.new()
				st.task = d.task
				st.owner = d.initial_owner
				st.cell_team = MapDef.TEAM_CONCORD
				if d == first_plant:
					st.cell_state = HardpointSim.CellState.PLANTED
					st.cell_pos = d.position
					st.progress = 0.4
					st.capturing_team = MapDef.TEAM_CONCORD
				else:
					st.cell_state = HardpointSim.CellState.CRADLE
					st.cell_pos = d.cradle_for(MapDef.TEAM_CONCORD)
				v.apply(st)
	for hq: HqDef in md.hqs:
		var uv := UplinkView.new()
		uv.setup(hq)
		map.add_child(uv)
		var am := ArmoryMarkerView.new()
		am.setup(hq, null)
		map.add_child(am)


## Vesper as the game builds her (HeroModelLoader, idle) plus a Tier II Picket
## Wardling beside her: both sit in the frame of `hero-ref` for scale.
func _make_hero() -> Node3D:
	var group := Node3D.new()
	var m := HeroModelLoader.build(&"vesper", ModelPalette.TEAM_CONCORD)
	group.add_child(m)
	if m.has_method("set_motion"):
		m.call("set_motion", Vector3.ZERO, false, 0.0)
	var w := WardlingModelBuilder.build(&"picket", 2, ModelPalette.TEAM_CONCORD)
	w.position = Vector3(1.4, 0, 0.6)
	group.add_child(w)
	return group


## The `wardlings` lineup: Concord squad tiers I-III (sash, own sash on III),
## Syndicate Vanguard tiers I-III (pennant), and a Concord Elite, 1 m apart.
func _make_squad() -> Node3D:
	var group := Node3D.new()
	var rows := [[ModelPalette.TEAM_CONCORD, 1, 1, false], [ModelPalette.TEAM_CONCORD, 2, 1, false],
		[ModelPalette.TEAM_CONCORD, 3, 2, false], [ModelPalette.TEAM_CONCORD, 2, 1, true],
		[ModelPalette.TEAM_SYNDICATE, 1, 0, false], [ModelPalette.TEAM_SYNDICATE, 2, 0, false],
		[ModelPalette.TEAM_SYNDICATE, 3, 0, false]]
	for i in rows.size():
		var r: Array = rows[i]
		var w := WardlingModelBuilder.build(&"picket", r[1], r[0])
		w.set_owner_kind(r[2])
		w.set_elite(r[3])
		w.position = Vector3((i - (rows.size() - 1) * 0.5) * 1.0, 0.0, 0.0)
		w.rotation.y = PI  # the group faces the camera with +Z; Wardlings face -Z
		group.add_child(w)
	group.visible = false
	return group


func _frames(n: int) -> void:
	for k in n:
		await process_frame
