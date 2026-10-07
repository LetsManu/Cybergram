extends Node3D
## Art showcase / evidence scene for the procedural models (art bible §12).
## Launch: godot --path . res://src/gameplay/views/models/model_showcase.tscn -- --showcase <mode>
## Modes: heroes (2-row lineup, both team tints), weapons (all 7 with Tier III
## mounts), wardlings (tiers, classes, Elite), uplink, perf (10 heroes + 50
## Wardlings animating; prints FPS). Extra: --walk (heroes walk in place),
## --turntable (slow spin), --silhouette (shadow test: flat black).

var mode: String = "heroes"
var _perf_heroes: Array[HeroModel] = []
var _perf_wardlings: Array = []
var _frames: int = 0
var _fps_t: float = 0.0
var _fps_frames: int = 0
var _fps_samples: Array[float] = []
var _turntable: bool = false
var _spin_nodes: Array[Node3D] = []
var _t: float = 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--showcase" and i + 1 < args.size():
			mode = args[i + 1]
		if args[i] == "--turntable":
			_turntable = true
	_env(mode != "perf")
	match mode:
		"weapons":
			_weapons()
		"wardlings":
			_wardlings()
		"uplink":
			_uplink()
		"perf":
			_perf()
		"hero":
			_hero_closeup(args)
		_:
			_heroes(args.has("--walk"), args.has("--silhouette"))


func _env(neutral: bool) -> void:
	var env := Environment.new()
	if neutral:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.36, 0.38, 0.45)
	else:
		var sky := Sky.new()
		var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color(0.2, 0.17, 0.38)
		sm.sky_horizon_color = Color(0.62, 0.55, 0.75)
		sky.sky_material = sm
		env.background_mode = Environment.BG_SKY
		env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.78)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Compatibility (GL, this container) has no HDR glow pipeline worth judging:
	# it washes the frame out, so bloom is only enabled on Forward+.
	env.glow_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility" \
		and not OS.get_cmdline_user_args().has("--no-glow")
	env.glow_hdr_threshold = 1.1
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 150.0, 0.0)
	fill.light_energy = 0.25
	fill.light_color = Color(0.7, 0.75, 1.0)
	add_child(fill)


func _floor(size: Vector2, y: float = 0.0, col: Color = Color(0.3, 0.31, 0.37)) -> void:
	var f := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	f.mesh = pm
	f.position.y = y
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	f.material_override = m
	add_child(f)


func _label(text: String, pos: Vector3, size: int = 48, col: Color = Color.WHITE) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 10
	l.pixel_size = 0.004
	l.modulate = col
	l.position = pos
	l.no_depth_test = true
	add_child(l)


func _camera(pos: Vector3, look: Vector3, ortho_size: float = 0.0, fov: float = 40.0) -> Camera3D:
	var c := Camera3D.new()
	if ortho_size > 0.0:
		c.projection = Camera3D.PROJECTION_ORTHOGONAL
		c.size = ortho_size
	else:
		c.fov = fov
	add_child(c)
	c.look_at_from_position(pos, look, Vector3.UP)
	c.current = true
	return c


func _yaw_arg(def: float) -> float:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--yaw")
	return args[i + 1].to_float() if i >= 0 and i + 1 < args.size() else def


# ------------------------------------------------------------------ heroes

func _heroes(walk: bool, silhouette: bool) -> void:
	var gap := 1.25
	var n := ModelCatalog.HERO_KEYS.size()
	_floor(Vector2(30, 12))
	var riser := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(gap * n + 0.6, 2.5, 1.6)
	riser.mesh = rb
	riser.position = Vector3(0, 1.25, -2.0)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.26, 0.27, 0.33)
	riser.material_override = rm
	add_child(riser)
	for row in 2:
		var team := ModelPalette.TEAM_CONCORD if row == 0 else ModelPalette.TEAM_SYNDICATE
		for i in n:
			var k := ModelCatalog.HERO_KEYS[i]
			var m := HeroModelLoader.build(k, team)
			add_child(m)
			m.position = Vector3((i - (n - 1) * 0.5) * gap, 0.0 if row == 0 else 2.5, 0.0 if row == 0 else -2.0)
			m.rotation_degrees.y = _yaw_arg(180.0 + 24.0)
			if walk:
				m.set_motion(m.global_basis * Vector3(0, 0, -4.0), false, 0.0)
			if silhouette:
				for mi in m.find_children("*", "MeshInstance3D", true, false):
					var b := StandardMaterial3D.new()
					b.albedo_color = Color.BLACK
					b.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					(mi as MeshInstance3D).material_override = b
			_spin_nodes.append(m)
			if row == 0:
				_label(ModelCatalog.HERO_NAMES[k], m.position + Vector3(0, 0.04, 0.75), 40)
	_label("CONCORD (light / porcelain)", Vector3(-(n * gap) * 0.5 + 1.2, 0.08, 1.2), 36, ModelPalette.AZURE_LIGHT)
	_label("SYNDICATE (dark / iron)", Vector3(-(n * gap) * 0.5 + 1.2, 2.55, -1.0), 36, Color("#FFB28F"))
	_camera(Vector3(0, 2.9, 10.6), Vector3(0, 2.0, -1.0), 0.0, 34.0)


## Close-up of one hero (--key <hero>) from four angles, both teams.
func _hero_closeup(args: PackedStringArray) -> void:
	var i := args.find("--key")
	var k := StringName(args[i + 1]) if i >= 0 and i + 1 < args.size() else &"hex"
	_floor(Vector2(20, 10))
	for j in 4:
		var m := HeroModelLoader.build(k, j % 2)
		add_child(m)
		m.position = Vector3(-2.7 + j * 1.8, 0, 0)
		m.rotation_degrees.y = [180.0 + 25.0, 90.0, 0.0, 270.0][j]
		_spin_nodes.append(m)
	_camera(Vector3(0, 1.5, 6.2), Vector3(0, 1.05, 0), 0.0, 40.0)


# ----------------------------------------------------------------- weapons

func _weapons() -> void:
	var cat := load(ArmoryCatalogDef.active_path()) as ArmoryCatalogDef
	var by_id := {}
	for it in cat.items:
		by_id[(it as ArmoryItemDef).id] = it
	# Demo-only lines (not in the slice catalog) so every socket shows Tier III.
	var demo_barrel := ArmoryItemDef.new()
	demo_barrel.id = &"stillwater_ring"
	demo_barrel.kind = ArmoryItemDef.Kind.MOUNT
	demo_barrel.socket = ArmoryItemDef.Socket.BARREL
	demo_barrel.family = ArmoryItemDef.Family.CRYSTAL
	demo_barrel.hue = Color("#2FD3A0")
	var demo_barrel_chip := demo_barrel.duplicate() as ArmoryItemDef
	demo_barrel_chip.id = &"stabilizer"
	demo_barrel_chip.family = ArmoryItemDef.Family.CHIP
	for i in ModelCatalog.WEAPON_KEYS.size():
		var k := ModelCatalog.WEAPON_KEYS[i]
		var w := WeaponModelBuilder.build(k, false, ModelPalette.TEAM_CONCORD if i % 2 == 0 else ModelPalette.TEAM_SYNDICATE)
		add_child(w)
		var col := i % 2
		var row := i / 2
		w.position = Vector3(-0.62 + col * 1.24, 1.83 - row * 0.44, 0.0)
		w.rotation_degrees = Vector3(0, 104, 0)
		var items: Array
		if w.mana:
			items = [by_id.get(&"ember_heart"), demo_barrel, by_id.get(&"flux_coil"), by_id.get(&"ammo_sunder")]
		else:
			items = [by_id.get(&"overclock"), demo_barrel_chip, by_id.get(&"quickload"), by_id.get(&"ammo_piercing")]
		w.set_mounts(items, PackedInt32Array([3, 3, 3, 3]))
		_label(String(k).capitalize().replace("Breakline", "Breakline AR-7"), w.position + Vector3(0.05, -0.2, 0.1), 16)
	_label("Tier III mounts on Core / Barrel / Frame / Chamber  -  Concord left, Syndicate right", Vector3(0.0, 2.16, 0.0), 14)
	_camera(Vector3(0.0, 2.1, 3.1), Vector3(0.0, 1.2, 0.0), 0.0, 36.0)


# --------------------------------------------------------------- wardlings

func _wardlings() -> void:
	_floor(Vector2(30, 14))
	var x := -4.4
	for team in [ModelPalette.TEAM_CONCORD, ModelPalette.TEAM_SYNDICATE]:
		for tier in [1, 2, 3]:
			var w := WardlingModelBuilder.build(&"picket", tier, team)
			add_child(w)
			w.position = Vector3(x, 0, 0)
			w.rotation_degrees.y = 180.0 + 20.0
			w.set_owner_kind(1)
			_label("Tier %s" % ["I", "II", "III"][tier - 1], Vector3(x, 0.05, 0.75), 30)
			x += 1.35
		x += 0.7
	_label("Personal squad (sash), Tier I / II / III  -  Concord | Syndicate", Vector3(0, 0.05, 1.5), 30)
	var specs := [[ModelPalette.TEAM_CONCORD, 0, false, false, "Vanguard (pennant)"],
		[ModelPalette.TEAM_SYNDICATE, 0, false, false, "Vanguard"],
		[ModelPalette.TEAM_CONCORD, 2, false, false, "Own squad"],
		[ModelPalette.TEAM_CONCORD, 1, true, false, "Elite (Vesper)"],
		[ModelPalette.TEAM_SYNDICATE, 1, false, true, "Turned"]]
	x = -4.6
	for s in specs:
		var w := WardlingModelBuilder.build(&"picket", 2, s[0])
		add_child(w)
		w.position = Vector3(x, 0.0, -3.4)
		w.rotation_degrees.y = 180.0 + 35.0
		w.set_owner_kind(s[1])
		w.set_elite(s[2])
		w.set_turned(s[3])
		_label(s[4], Vector3(x, 1.95, -3.4), 46)
		x += 2.3
	_camera(Vector3(0, 3.0, 6.9), Vector3(0, 0.75, -1.5), 0.0, 42.0)


# ------------------------------------------------------------------ uplink

func _uplink() -> void:
	_floor(Vector2(120, 120))
	var hq := HqDef.new()
	for t in 2:
		hq.team = t
		hq.uplink = Vector3(-14 + 28 * t, 0, 0)
		var u := UplinkView.new()
		add_child(u)
		u.setup(hq)
		var st := SnapshotData.UplinkState.new()
		st.team = t
		st.max_integrity = 100.0
		st.integrity = 100.0 if t == 0 else 60.0
		st.exposed = t == 1
		u.apply(st)
	_camera(Vector3(0, 12, 62), Vector3(0, 20, 0), 0.0, 50.0)


# -------------------------------------------------------------------- perf

func _perf() -> void:
	_floor(Vector2(120, 120))
	for i in 10:
		var k := ModelCatalog.HERO_KEYS[i % ModelCatalog.HERO_KEYS.size()]
		var m := HeroModelLoader.build(k, i % 2)
		add_child(m)
		m.position = Vector3(-8 + (i % 5) * 4.0, 0, -6.0 - (i / 5) * 6.0)
		_perf_heroes.append(m)
	for i in 50:
		var w := WardlingModelBuilder.build(&"picket", 1 + i % 3, i % 2)
		add_child(w)
		w.position = Vector3(-12 + (i % 10) * 2.6, 0, -2.0 - (i / 10) * 3.0)
		w.set_owner_kind(i % 3)
		_perf_wardlings.append(w)
	_camera(Vector3(0, 4.0, 10.0), Vector3(0, 1.0, -8.0), 0.0, 75.0)


func _process(delta: float) -> void:
	_t += delta
	if _turntable:
		for n in _spin_nodes:
			n.rotation.y += delta * 0.6
	if mode != "perf":
		return
	for i in _perf_heroes.size():
		var m := _perf_heroes[i]
		var v := Vector3(sin(_t * 0.7 + i), 0, cos(_t * 0.7 + i)) * 5.0
		m.position += v * delta * 0.3
		m.rotation.y = atan2(-v.x, -v.z)
		m.set_motion(v, fmod(_t + i, 6.0) > 5.0, sin(_t + i) * 0.4)
		if fmod(_t * 2.0 + i, 3.0) < delta * 2.0:
			m.flinch()
	for i in _perf_wardlings.size():
		var w = _perf_wardlings[i]
		w.position.x += sin(_t + i) * delta
		w.set_moving(true)
	_frames += 1
	if _frames > 30:
		_fps_t += delta
		_fps_frames += 1
		if _fps_t >= 1.0:
			_fps_samples.append(_fps_frames / _fps_t)
			print("PERF fps=%.1f draw_calls=%d prims=%d objects=%d" % [_fps_frames / _fps_t,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
			_fps_t = 0.0
			_fps_frames = 0
