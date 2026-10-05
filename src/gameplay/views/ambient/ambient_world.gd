class_name AmbientWorld
extends Node3D
## W18-LIFE "living map", background life (client presentation only):
## skyline traffic with night light trails, cargo drones, a sky-train, holo
## billboards with fictional ads, flickering neon / market shop signs, light
## shafts, drifting fog banks, rain, dust motes, far birds, a per-match
## time-of-day mood and a low city hum.
##
## Rules it keeps (design: docs/architecture/ambient-world.md):
##  * never built on the dedicated server / headless, nor inside the offline
##    ServerWorld's copy of the map (should_build());
##  * no collision, no physics layer, nothing in navigation, nothing in the
##    playable box below TrafficPaths.CLEAR_Y except flush shop signs above head
##    height at the market lane edges;
##  * every mover rides a route baked into a float texture and is placed by the
##    vertex shader: one draw call per kind, no per-frame transform uploads;
##  * follows GameSettings: ambient_level (capped by graphics_quality),
##    ambient_rain, comfort_fx_intensity and reduce_motion (AmbientComfort);
##  * mood, weather and sky-train timing derive from the match seed and the
##    shared match clock (AmbientMood, SkyTrainSchedule).
## Anchors from the map (groups or the AmbientAnchors node) replace the
## fallback placements when present.

const MOVER_SHADER := "res://assets/shaders/spatial_env_ambient_mover.gdshader"
const TRAIL_SHADER := "res://assets/shaders/spatial_env_ambient_trail.gdshader"
const HOLO_SHADER := "res://assets/shaders/spatial_env_ambient_holo.gdshader"
const SHAFT_SHADER := "res://assets/shaders/spatial_env_ambient_shaft.gdshader"
const FOG_SHADER := "res://assets/shaders/spatial_env_ambient_fog.gdshader"
const NEON_SHADER := "res://assets/shaders/spatial_env_ambient_neon.gdshader"
const FONT_PATH := "res://assets/fonts/chakrapetch/ChakraPetch-SemiBold.ttf"

## Anchor groups / name prefixes (contract with the map builder).
const G_BILLBOARD := &"ambient_billboard"
const G_NEON := &"ambient_neon"
const G_SHOP_SIGN := &"ambient_shop_sign"
const G_TRAFFIC := &"ambient_traffic_path"
const G_DRONE := &"ambient_drone_path"
const G_TRAIN := &"ambient_skytrain"
const G_STEAM := &"ambient_steam_vent"
const ANCHOR_NODE := "AmbientAnchors"
const PREFIXES := {
	&"ambient_billboard": "Billboard", &"ambient_neon": "Neon", &"ambient_shop_sign": "ShopSign",
	&"ambient_traffic_path": "TrafficPath", &"ambient_drone_path": "DronePath", &"ambient_skytrain": "SkyTrain",
	&"ambient_steam_vent": "SteamVent",
}

## Fictional in-world ads: [name key, tagline key, motif, colour a, colour b].
const ADS := [
	["HUD_AMB_AD_LUMENFIZZ", "HUD_AMB_AD_LUMENFIZZ_TAG", 0, Color("#34D8C4"), Color("#8E5CFF")],
	["HUD_AMB_AD_SHARDSNAX", "HUD_AMB_AD_SHARDSNAX_TAG", 1, Color("#FF5A1F"), Color("#FFD447")],
	["HUD_AMB_AD_NEONOODLE", "HUD_AMB_AD_NEONOODLE_TAG", 2, Color("#FF4FD8"), Color("#FF8A3D")],
	["HUD_AMB_AD_LEYFALL_LINE", "HUD_AMB_AD_LEYFALL_LINE_TAG", 3, Color("#2E86FF"), Color("#34D8C4")],
	["HUD_AMB_AD_VOIDSURE", "HUD_AMB_AD_VOIDSURE_TAG", 4, Color("#8E5CFF"), Color("#2E86FF")],
	["HUD_AMB_AD_RESONA", "HUD_AMB_AD_RESONA_TAG", 5, Color("#4CE38A"), Color("#34D8C4")],
]
const SHOP_SIGNS := ["HUD_AMB_SHOP_NOODLES", "HUD_AMB_SHOP_MODS", "HUD_AMB_SHOP_LUMEN", "HUD_AMB_SHOP_REPAIR",
	"HUD_AMB_SHOP_TEA", "HUD_AMB_SHOP_SYNTH", "HUD_AMB_SHOP_DUMPLING", "HUD_AMB_SHOP_OPEN"]
const NEON_COLORS: Array[Color] = [Color("#FF4FD8"), Color("#34D8C4"), Color("#FFD447"), Color("#FF5A1F"),
	Color("#8E5CFF"), Color("#4CE38A"), Color("#2E86FF"), Color("#FF8A3D")]

## Effective ambience level (AmbientComfort.LOW..HIGH), mood and weather.
var level: int = AmbientComfort.HIGH
var mood: int = AmbientMood.Mood.DUSK
var weather: int = AmbientMood.Weather.CLEAR
var match_seed: int = 1
## Debug overrides (parse_debug_args); -1 / NAN = none.
var debug: Dictionary = {}

var _map_root: Node
var _settings: GameSettings
var _anim_mats: Array[ShaderMaterial] = []
var _trail_mat: ShaderMaterial
var _train_mat: ShaderMaterial
var _train_node: MultiMeshInstance3D
var _shaft_mat: ShaderMaterial
var _shafts: MultiMeshInstance3D
var _holo_mats: Array[ShaderMaterial] = []
var _holo_labels: Array[Label3D] = []
var _signs: Array[Label3D] = []
var _sign_frames: MultiMesh
var _sign_colors: Array[Color] = []
## Label -> its hud.csv keys; re-translated until the HUD string table is loaded
## (the UI layer loads it, possibly after the map is built).
var _label_keys: Dictionary = {}
var _steam: GPUParticles3D
var _neon_mat: ShaderMaterial
var _rain: GPUParticles3D
var _motes: GPUParticles3D
var _schedule: SkyTrainSchedule
var _audio: AmbientAudio
var _local_t: float = 0.0
var _clock_offset: float = 0.0
var _flicker: float = 0.0
var _glow: float = 1.0
var _anim: float = 1.0
## Clock scale for movers (reduce motion: half speed).
var _move_k: float = 1.0
var _comfort_sig: String = ""
var _poll: int = 0
var _env: Environment
var _sun: DirectionalLight3D


## True when ambient life may be built under `node`: never headless, never in
## the offline ServerWorld's map copy, never with --ambient-off.
static func should_build(node: Node, headless: bool = GfxQuality.is_headless(),
		args: PackedStringArray = OS.get_cmdline_user_args()) -> bool:
	if headless or args.has("--ambient-off"):
		return false
	var p := node
	while p != null:
		if p is ServerWorld:
			return false
		p = p.get_parent()
	return true


## MapVisuals hook: builds and attaches the ambient layer under `host` (the
## MapVisuals node) for the map `map_root`. Returns null where it must not run.
static func create_for(host: Node, map_root: Node) -> AmbientWorld:
	if not should_build(host):
		return null
	var aw := AmbientWorld.new()
	aw.name = "AmbientWorld"
	aw._map_root = map_root
	host.add_child(aw)
	return aw


## Debug args (evidence captures): --ambient-time dusk|night|overcast,
## --ambient-weather clear|fog|rain, --ambient-level low|medium|high,
## --ambient-fx <0..1>, --ambient-reduce-motion, --ambient-seed <n>,
## --ambient-train-at <0..1> (train at that point of a pass right now).
static func parse_debug_args(args: PackedStringArray) -> Dictionary:
	var d := {}
	var levels := ["low", "medium", "high"]
	for i in args.size() - 1:
		var v := args[i + 1]
		match args[i]:
			"--ambient-time":
				d.mood = AmbientMood.mood_from_name(v)
			"--ambient-weather":
				d.weather = AmbientMood.weather_from_name(v)
			"--ambient-level":
				d.level = levels.find(v.to_lower())
			"--ambient-fx":
				d.fx = clampf(v.to_float(), 0.0, 1.0)
			"--ambient-seed":
				d.seed = v.to_int()
			"--ambient-train-at":
				d.train_at = clampf(v.to_float(), 0.0, 0.999)
	if args.has("--ambient-reduce-motion"):
		d.reduce_motion = true
	return d


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	if _map_root == null:
		_map_root = get_parent().get_parent() if get_parent() != null else null
	_settings = GameSettings.shared()
	debug = parse_debug_args(OS.get_cmdline_user_args())
	match_seed = _resolve_seed()
	_find_env()
	_rebuild()


## Re-reads settings, re-picks mood / weather and rebuilds every layer.
func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_anim_mats.clear()
	_holo_mats.clear()
	_holo_labels.clear()
	_signs.clear()
	_sign_colors.clear()
	_label_keys.clear()
	_trail_mat = null
	_train_mat = null
	_train_node = null
	_shaft_mat = null
	_shafts = null
	_sign_frames = null
	_rain = null
	_motes = null
	_steam = null
	_neon_mat = null
	if int(debug.get("level", -1)) >= 0:
		level = int(debug.level)
	else:
		level = AmbientComfort.level(_settings.ambient_level, _settings.graphics_quality)
	mood = int(debug.mood) if debug.get("mood", -1) >= 0 else AmbientMood.pick_mood(match_seed)
	weather = int(debug.weather) if debug.get("weather", -1) >= 0 \
		else AmbientMood.pick_weather(match_seed, _settings.ambient_rain)
	AmbientMood.apply(mood, weather, _env, _sun)
	_schedule = SkyTrainSchedule.new(match_seed)
	if debug.has("train_at"):
		_clock_offset = _schedule.current_start() + float(debug.train_at) * SkyTrainSchedule.PASS_S - _raw_clock()
	var b := AmbientComfort.budget(level)
	var lk := AmbientMood.look(mood)
	_build_traffic(b, lk)
	_build_drones(b)
	_build_train()
	_build_billboards(b)
	_build_signs(b)
	_build_neon(b)
	_build_steam(b)
	_build_shafts(b, lk)
	_build_fog(b)
	_build_particles(b)
	_build_birds(b)
	_audio = AmbientAudio.new()
	_audio.level = level
	add_child(_audio)
	_comfort_sig = ""
	_apply_comfort()


func _process(delta: float) -> void:
	_local_t += delta
	var t := match_time()
	for m in _anim_mats:
		m.set_shader_parameter("anim_time", t * (_move_k if m.has_meta(&"mover") else 1.0))
	if _train_mat != null:
		var u := _schedule.progress(t)
		_train_node.visible = u >= 0.0
		# The head car runs 6 car lengths past 1.0 so the tail clears the rail.
		_train_mat.set_shader_parameter("train_u", u * 1.12)
	_update_signs(t)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var at := cam.global_position
		if _rain != null:
			_rain.global_position = at + Vector3(0.0, 14.0, 0.0)
		if _motes != null:
			_motes.global_position = at
	_poll += 1
	if _poll % 30 == 0:
		_poll_settings()
		if not _label_keys.is_empty():
			_retranslate()


## Shared match clock (s): the server tick estimate on clients, so every
## player sees the sky-train at the same moment; local time without a session.
func match_time() -> float:
	return _raw_clock() + _clock_offset


func _raw_clock() -> float:
	var cw := _client_world()
	if cw != null:
		var est: Variant = cw.get("server_tick_estimate")
		var net: Variant = cw.get("net")
		if est != null and net != null and float(est) > 0.0:
			return float(est) / float(maxi(1, int(net.get("tick_rate_hz"))))
	return _local_t


func _client_world() -> Node:
	var p := get_parent()
	while p != null:
		if p is ClientWorld:
			return p
		p = p.get_parent()
	return null


func _session() -> Node:
	var p := get_parent()
	while p != null:
		if p is GameSession:
			return p
		p = p.get_parent()
	return null


## Seed priority: --ambient-seed, else the server's Welcome `mood_seed`
## (ClientSession.mood_seed; the same for every client of a match, 0 = not
## sent / not yet welcomed), else the local launch seed (offline / local).
static func pick_seed(debug_seed: int, server_mood_seed: int, launch_seed: int) -> int:
	if debug_seed >= 0:
		return debug_seed
	if server_mood_seed != 0:
		return server_mood_seed
	return launch_seed


func _resolve_seed() -> int:
	var gs := _session() as GameSession
	var launch := gs.launch_config.match_seed if gs != null and gs.launch_config != null else 1
	return pick_seed(int(debug.get("seed", -1)), _server_mood_seed(), launch)


## The Welcome's mood seed from this client's session (0 when absent).
func _server_mood_seed() -> int:
	var cw := _client_world() as ClientWorld
	if cw == null or cw.session == null:
		return 0
	return cw.session.mood_seed


func _find_env() -> void:
	if _map_root == null:
		return
	var we := _map_root.get_node_or_null("Env") as WorldEnvironment
	if we != null and we.environment != null:
		# Own copy: the scene's Environment resource is shared with other instances.
		we.environment = we.environment.duplicate(true)
		_env = we.environment
	_sun = _map_root.get_node_or_null("Sun") as DirectionalLight3D


func _poll_settings() -> void:
	var seed_now := _resolve_seed()  # the Welcome may land after the map is built
	if seed_now != match_seed:
		match_seed = seed_now
		_rebuild()
		return
	var want := AmbientComfort.level(_settings.ambient_level, _settings.graphics_quality)
	if int(debug.get("level", -1)) < 0 and (want != level or _rain_setting_changed()):
		_rebuild()
		return
	_apply_comfort()


func _rain_setting_changed() -> bool:
	if debug.get("weather", -1) >= 0:
		return false
	return weather != AmbientMood.pick_weather(match_seed, _settings.ambient_rain)


## Pushes effects intensity / reduce motion into every layer (cheap; only
## when the values changed).
func _apply_comfort() -> void:
	var fx: float = float(debug.get("fx", _settings.comfort_fx_intensity))
	var rm: bool = bool(debug.get("reduce_motion", _settings.reduce_motion))
	var sig := "%.2f|%s" % [fx, rm]
	if sig == _comfort_sig:
		return
	_comfort_sig = sig
	_flicker = AmbientComfort.flicker_amount(fx, rm)
	_glow = AmbientComfort.glow_gain(fx)
	_anim = AmbientComfort.anim_speed(rm)
	var lk := AmbientMood.look(mood)
	for m in _holo_mats:
		m.set_shader_parameter("anim_speed", _anim)
	if _trail_mat != null:
		_trail_mat.set_shader_parameter("gain", float(lk.trail_gain) * _glow)
	for m in _anim_mats:
		if m.shader.resource_path == MOVER_SHADER:
			m.set_shader_parameter("flap_speed", maxf(_anim, 0.3))
			m.set_shader_parameter("blink", 1.0 if _anim > 0.0 else 0.0)
	_move_k = AmbientComfort.traffic_speed(rm)
	if _shafts != null:
		_shafts.visible = AmbientComfort.shafts_enabled(fx)
		_shaft_mat.set_shader_parameter("sweep", _anim if mood == AmbientMood.Mood.NIGHT else 0.0)
	if _rain != null:
		var n := AmbientComfort.rain_amount(level, fx, true)
		_rain.emitting = n > 0
		_rain.visible = n > 0
		if n > 0:
			_rain.amount = n
	if _neon_mat != null:
		_neon_mat.set_shader_parameter("flicker", _flicker)
		_neon_mat.set_shader_parameter("gain", float(lk.neon_gain) * _glow * 1.5)
	if _steam != null:
		_steam.speed_scale = 0.4 if rm else 1.0
	if _audio != null:
		_audio.set_level(level)


func _translate(label: Label3D) -> bool:
	var keys: Array = _label_keys.get(label, [])
	var parts: PackedStringArray = []
	var ok := true
	for k in keys:
		var t := tr(k)
		ok = ok and t != k
		parts.append(t)
	label.text = "\n".join(parts)
	if label.has_meta(&"fit"):
		label.pixel_size = fit_pixel_size(parts, label.font_size, label.get_meta(&"fit"))
	return ok


## Pixel size that fits `lines` (font size `font_px`) into `area` metres.
## Chakra Petch averages ~0.6 em per glyph; line height ~1.25 em.
static func fit_pixel_size(lines: PackedStringArray, font_px: int, area: Vector2) -> float:
	var longest := 1
	for l in lines:
		longest = maxi(longest, l.length())
	var by_w := area.x / (longest * 0.6 * font_px)
	var by_h := area.y / (maxi(1, lines.size()) * 1.25 * font_px)
	return minf(by_w, by_h)


## `n` indices spread evenly over `count` anchors (all of them when n >= count).
static func spread(count: int, n: int) -> Array[int]:
	var out: Array[int] = []
	if count <= 0 or n <= 0:
		return out
	if n >= count:
		for i in count:
			out.append(i)
		return out
	for i in n:
		out.append(int(floor(i * count / float(n))))
	return out


## Re-translates labels whose keys were not resolvable yet; stops once all are.
func _retranslate() -> void:
	var done := true
	for l in _label_keys:
		done = _translate(l) and done
	if done:
		_label_keys.clear()


# ------------------------------------------------------------- anchors

## Anchor nodes of one kind: members of `group` under the map, plus children of
## the map's AmbientAnchors node whose name starts with the kind's prefix.
func anchors(group: StringName) -> Array[Node]:
	var out: Array[Node] = []
	if _map_root == null:
		return out
	# Group members of THIS map only (offline, the server's map copy is in the tree too).
	if _map_root.is_inside_tree():
		for n in _map_root.get_tree().get_nodes_in_group(group):
			if n is Node3D and _map_root.is_ancestor_of(n):
				out.append(n)
	var holder := _map_root.get_node_or_null(ANCHOR_NODE)
	if holder != null:
		for n in holder.find_children(String(PREFIXES[group]) + "*", "Node3D", true, false):
			if not out.has(n):
				out.append(n)
	return out


func _routes_from(group: StringName, closed: bool) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	for n in anchors(group):
		var p := n as Path3D
		if p == null or p.curve == null or p.curve.point_count < 2:
			continue
		var pts := PackedVector3Array()
		for v in p.curve.get_baked_points():
			pts.append(p.global_transform * v)
		out.append(TrafficPaths.resample(pts, closed))
	return out


# ------------------------------------------------------------- builders

func _mover_mat(kind: int, tex: Texture2D, closed: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(MOVER_SHADER)
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("path_tex", tex)
	m.set_shader_parameter("path_samples", TrafficPaths.SAMPLES)
	m.set_shader_parameter("path_closed", closed)
	m.set_meta(&"mover", true)
	_anim_mats.append(m)
	return m


## One MultiMeshInstance3D whose instances carry INSTANCE_CUSTOM route data.
func _custom_mm(node_name: String, mesh: Mesh, mat: Material, custom: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = custom.size()
	for i in custom.size():
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, custom[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-900, -200, -1300), Vector3(1800, 600, 2200))
	add_child(mi)
	return mi


func _unit_box() -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	return b


func _build_traffic(b: Dictionary, lk: Dictionary) -> void:
	var routes := _routes_from(G_TRAFFIC, true)
	if routes.is_empty():
		routes = TrafficPaths.fallback_traffic(b.traffic_lanes)
	routes = routes.slice(0, maxi(1, int(b.traffic_lanes)))
	var tex := TrafficPaths.bake(routes)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var custom: Array[Color] = []
	for r in routes.size():
		var len_m := maxf(1.0, TrafficPaths.length(routes[r], true))
		for i in int(b.cars_per_lane):
			var dir := 1.0 if i % 2 == 0 else -1.0
			var v := rng.randf_range(28.0, 52.0) * (1.0 + 0.15 * r)
			custom.append(Color(r, rng.randf(), dir * v / len_m, dir * 4.0))
	var cars := _mover_mat(0, tex, true)
	cars.set_shader_parameter("size", Vector3(4.5, 1.8, 9.0))
	# Lights stay near 1.0 (barely over the bloom threshold): lamps, not muzzle flashes.
	cars.set_shader_parameter("light_gain", 1.0 + float(lk.neon_gain) * 0.1)
	_custom_mm("Traffic", _unit_box(), cars, custom)
	if b.trails and float(lk.trail_gain) > 0.0:
		_trail_mat = ShaderMaterial.new()
		_trail_mat.shader = load(TRAIL_SHADER)
		_trail_mat.set_shader_parameter("path_tex", tex)
		_trail_mat.set_shader_parameter("path_samples", TrafficPaths.SAMPLES)
		_trail_mat.set_shader_parameter("trail_size", Vector2(1.2, 0.35))
		_trail_mat.set_shader_parameter("trail_len", 10.0)
		_trail_mat.set_meta(&"mover", true)
		_anim_mats.append(_trail_mat)
		_custom_mm("TrafficTrails", _unit_box(), _trail_mat, custom)


func _build_drones(b: Dictionary) -> void:
	if int(b.drones) <= 0:
		return
	var routes := _routes_from(G_DRONE, true)
	if routes.is_empty():
		routes = TrafficPaths.fallback_drones(4)
	var tex := TrafficPaths.bake(routes)
	var custom: Array[Color] = []
	for i in int(b.drones):
		var r := i % routes.size()
		var len_m := maxf(1.0, TrafficPaths.length(routes[r], true))
		custom.append(Color(r, fposmod(i * 0.37, 1.0), (14.0 + 3.0 * (i % 3)) / len_m, 0.0))
	var m := _mover_mat(1, tex, true)
	m.set_shader_parameter("size", Vector3(2.4, 1.1, 2.4))
	m.set_shader_parameter("body_color", Color(0.12, 0.1, 0.14))
	_custom_mm("Drones", _unit_box(), m, custom)


func _build_train() -> void:
	var routes := _routes_from(G_TRAIN, false)
	if routes.is_empty():
		routes = [TrafficPaths.fallback_train()] as Array[PackedVector3Array]
	var rail := routes[0]
	var tex := TrafficPaths.bake([rail] as Array[PackedVector3Array])
	var len_m := maxf(1.0, TrafficPaths.length(rail, false))
	var custom: Array[Color] = []
	for i in 6:
		custom.append(Color(0.0, i * 17.0 / len_m, 0.0, 0.0))
	_train_mat = _mover_mat(3, tex, false)
	_train_mat.set_shader_parameter("size", Vector3(4.2, 3.6, 16.0))
	_train_mat.set_shader_parameter("body_color", Color(0.78, 0.76, 0.86))
	_train_mat.set_shader_parameter("light_front", Color(1.0, 0.9, 0.64))
	_train_node = _custom_mm("SkyTrain", _unit_box(), _train_mat, custom)
	# Static rail beam with pylons every 8th sample (one MultiMesh, no collision).
	var xf: Array[Transform3D] = []
	for i in rail.size() - 1:
		var a := rail[i]
		var c := rail[i + 1]
		var mid := (a + c) * 0.5 - Vector3(0.0, 2.4, 0.0)
		var basis := Basis.looking_at((c - a).normalized(), Vector3.UP).scaled(Vector3(2.6, 0.8, a.distance_to(c) + 0.2))
		xf.append(Transform3D(basis, mid))
		if i % 8 == 4:
			xf.append(Transform3D(Basis().scaled(Vector3(1.6, 100.0, 1.6)), a - Vector3(0.0, 52.0, 0.0)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _unit_box()
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = "SkyTrainTrack"
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.16, 0.14, 0.26)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _font() -> Font:
	return load(FONT_PATH) as Font if ResourceLoader.exists(FONT_PATH) else null


## Fallback billboard placements: holo panels between the skyline towers on
## both sides, facing the lanes.
func _fallback_billboards(n: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in n:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := -40.0 - (i * 340.0 / maxf(1.0, n - 1.0))
		var pos := Vector3(side * (132.0 + 10.0 * (i % 3)), 28.0 + 8.0 * (i % 2), z)
		# Angled 50 deg toward one lane end, so players looking down a lane see them.
		var face := Vector3(-side * 0.65, 0.0, 0.76 if i % 4 < 2 else -0.76).normalized()
		out.append(Transform3D(Basis.looking_at(-face, Vector3.UP), pos))
	return out


func _build_billboards(b: Dictionary) -> void:
	var n := int(b.billboards)
	if n <= 0:
		return
	var xfs: Array[Transform3D] = []
	var sizes: Array[Vector2] = []
	var found := anchors(G_BILLBOARD)
	for k in spread(found.size(), n):
		xfs.append((found[k] as Node3D).global_transform)
		sizes.append(found[k].get_meta("size", Vector2(32.0, 12.0)))
	if xfs.is_empty():
		xfs = _fallback_billboards(n)
		for i in xfs.size():
			sizes.append(Vector2(32.0, 12.0))
	var font := _font()
	var lk := AmbientMood.look(mood)
	for i in mini(n, xfs.size()):
		var ad: Array = ADS[(i + match_seed) % ADS.size()]
		var q := QuadMesh.new()
		q.size = sizes[i]
		var m := ShaderMaterial.new()
		m.shader = load(HOLO_SHADER)
		m.set_shader_parameter("color_a", ad[3])
		m.set_shader_parameter("color_b", ad[4])
		m.set_shader_parameter("motif", ad[2])
		m.set_shader_parameter("gain", float(lk.neon_gain))
		m.set_shader_parameter("alpha", 0.85)
		_anim_mats.append(m)
		_holo_mats.append(m)
		var panel := MeshInstance3D.new()
		panel.name = "Billboard%d" % i
		panel.mesh = q
		panel.material_override = m
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		panel.transform = xfs[i]
		add_child(panel)
		var label := Label3D.new()
		_label_keys[label] = [ad[0], ad[1]]
		if font != null:
			label.font = font
		label.font_size = 96
		label.outline_size = 0
		label.modulate = Color(1.0, 1.0, 1.0)
		# Glyph on the left 36 %, text fitted into the rest.
		label.position = Vector3(sizes[i].x * 0.18, 0.0, 0.06)
		label.set_meta(&"fit", Vector2(sizes[i].x * 0.58, sizes[i].y * 0.75))
		label.render_priority = 1
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		panel.add_child(label)
		_translate(label)
		_holo_labels.append(label)


## Fallback shop sign slots: flush at the centre (market) lane edges, above
## head height on the 3 m decks (6.5 m), facing into the lane.
func _fallback_signs(n: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in n:
		var side := -1.0 if i % 2 == 0 else 1.0
		var l := 90.0 + i * 240.0 / maxf(1.0, n - 1.0)
		var face := Vector3(-side, 0.0, 0.0)
		out.append(Transform3D(Basis.looking_at(-face, Vector3.UP), Vector3(side * 9.6, 6.5, -l)))
	return out


func _build_signs(b: Dictionary) -> void:
	var n := int(b.signs)
	if n <= 0:
		return
	var xfs: Array[Transform3D] = []
	var sizes: Array[Vector2] = []
	var found := anchors(G_SHOP_SIGN)
	for k in spread(found.size(), n):
		xfs.append((found[k] as Node3D).global_transform)
		sizes.append(found[k].get_meta("size", Vector2(6.0, 1.4)))
	if xfs.is_empty():
		xfs = _fallback_signs(n)
		for i in xfs.size():
			sizes.append(Vector2(4.0, 1.0))
	var font := _font()
	var frames: Array[Transform3D] = []
	for i in mini(n, xfs.size()):
		var c := NEON_COLORS[(i * 3 + match_seed) % NEON_COLORS.size()]
		var label := Label3D.new()
		label.name = "ShopSign%d" % i
		_label_keys[label] = [SHOP_SIGNS[(i + match_seed) % SHOP_SIGNS.size()]]
		if font != null:
			label.font = font
		label.font_size = 64
		label.outline_size = 0
		label.set_meta(&"fit", Vector2(sizes[i].x * 0.9, sizes[i].y * 0.62))
		_translate(label)
		# Text 6 cm off the wall so it never z-fights the facade.
		label.transform = xfs[i] * Transform3D(Basis(), Vector3(0.0, 0.0, 0.06))
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(label)
		_signs.append(label)
		_sign_colors.append(c)
		# Neon tube frame: top and bottom bars around the text.
		var w := sizes[i].x * 0.96
		for y in [0.45, -0.45]:
			frames.append(xfs[i] * Transform3D(Basis().scaled(Vector3(w, 0.06, 0.06)), Vector3(0.0, y * sizes[i].y, 0.05)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _unit_box()
	mm.instance_count = frames.size()
	for i in frames.size():
		mm.set_instance_transform(i, frames[i])
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	var mi := MultiMeshInstance3D.new()
	mi.name = "NeonFrames"
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_sign_frames = mm
	_update_signs(0.0)


## Neon brightness: mood gain x comfort glow x subtle flicker (steady when off).
func _update_signs(t: float) -> void:
	var gain := float(AmbientMood.look(mood).neon_gain) * _glow
	for i in _signs.size():
		var f := AmbientComfort.flicker(t, i * 0.618, _flicker)
		var c := _sign_colors[i] * (gain * f * 1.6)
		c.a = 1.0
		_signs[i].modulate = c
		if _sign_frames != null and i * 2 + 1 < _sign_frames.instance_count:
			_sign_frames.set_instance_color(i * 2, c)
			_sign_frames.set_instance_color(i * 2 + 1, c)
	for i in _holo_mats.size():
		var f := AmbientComfort.flicker(t, 0.31 + i * 0.47, _flicker * 0.6)
		_holo_mats[i].set_shader_parameter("gain", float(AmbientMood.look(mood).neon_gain) * _glow * f)
		if i < _holo_labels.size():
			var lc := Color(1.0, 1.0, 1.0) * (_glow * f * 1.3)
			lc.a = 1.0
			_holo_labels[i].modulate = lc


func _build_shafts(b: Dictionary, lk: Dictionary) -> void:
	var n := int(b.shafts)
	if n <= 0:
		return
	var cone := CylinderMesh.new()
	cone.top_radius = 0.08
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 12
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	_shaft_mat = ShaderMaterial.new()
	_shaft_mat.shader = load(SHAFT_SHADER)
	var night := mood == AmbientMood.Mood.NIGHT
	_shaft_mat.set_shader_parameter("color", Color(0.7, 0.82, 1.0) if night else Color(1.0, 0.84, 0.66))
	_shaft_mat.set_shader_parameter("gain", 0.16 * float(lk.shaft_gain))
	_anim_mats.append(_shaft_mat)
	var custom: Array[Color] = []
	var xf: Array[Transform3D] = []
	for i in n:
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := Vector3(side * (140.0 + 25.0 * (i % 3)), 40.0, -30.0 - i * 360.0 / maxf(1.0, n - 1.0))
		var tilt := Basis(Vector3.FORWARD, side * 0.25)
		xf.append(Transform3D(tilt.scaled(Vector3(40.0, 160.0, 40.0)), pos))
		custom.append(Color(i * 0.173, 0.0, 0.0, 0.0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = cone
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_custom_data(i, custom[i])
	_shafts = MultiMeshInstance3D.new()
	_shafts.name = "LightShafts"
	_shafts.multimesh = mm
	_shafts.material_override = _shaft_mat
	_shafts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shafts)


func _build_fog(b: Dictionary) -> void:
	var n := int(b.fog_cards)
	if weather == AmbientMood.Weather.FOG:
		n = maxi(n, 4) * 2
	if n <= 0:
		return
	var m := ShaderMaterial.new()
	m.shader = load(FOG_SHADER)
	m.set_shader_parameter("color", AmbientMood.look(mood).fog_color)
	m.set_shader_parameter("density", 0.55 if weather == AmbientMood.Weather.FOG else 0.3)
	_anim_mats.append(m)
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var xf: Array[Transform3D] = []
	for i in n:
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := Vector3(side * (125.0 + 30.0 * (i % 3)), 2.0 + 10.0 * (i % 4), -20.0 - (i * 397 % 400))
		var basis := Basis(Vector3.UP, side * PI * 0.5 + 0.2 * sin(i)).scaled(Vector3(170.0, 46.0, 1.0))
		xf.append(Transform3D(basis, pos))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, xf[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = "FogBanks"
	mi.multimesh = mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _particle_quad(c: Color, size: Vector2, fixed_y: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if fixed_y else BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	return q


func _build_particles(b: Dictionary) -> void:
	# Dust / crystal motes: tiny, dim, slow (never pickup-sized: Lumen Motes are gameplay).
	if int(b.motes) > 0:
		_motes = GPUParticles3D.new()
		_motes.name = "DustMotes"
		_motes.amount = int(b.motes)
		_motes.lifetime = 9.0
		_motes.preprocess = 9.0
		_motes.local_coords = false
		_motes.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(30.0, 10.0, 30.0)
		pm.gravity = Vector3(0.0, 0.05, 0.0)
		pm.direction = Vector3(1.0, 0.2, 0.3)
		pm.spread = 180.0
		pm.initial_velocity_min = 0.05
		pm.initial_velocity_max = 0.35
		pm.scale_min = 0.6
		pm.scale_max = 1.4
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 0))
		fade.set_color(1, Color(1, 1, 1, 0))
		fade.add_point(0.3, Color(1, 1, 1, 1))
		fade.add_point(0.7, Color(1, 1, 1, 1))
		var ramp := GradientTexture1D.new()
		ramp.gradient = fade
		pm.color_ramp = ramp
		_motes.process_material = pm
		_motes.draw_pass_1 = _particle_quad(Color(0.86, 0.8, 1.0, 0.35), Vector2(0.05, 0.05), false)
		_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_motes)
	if weather == AmbientMood.Weather.RAIN:
		_rain = GPUParticles3D.new()
		_rain.name = "Rain"
		_rain.amount = maxi(1, int(b.rain))
		_rain.lifetime = 1.1
		_rain.preprocess = 1.1
		_rain.local_coords = false
		_rain.visibility_aabb = AABB(Vector3(-30, -40, -30), Vector3(60, 60, 60))
		var rp := ParticleProcessMaterial.new()
		rp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		rp.emission_box_extents = Vector3(26.0, 2.0, 26.0)
		rp.direction = Vector3(0.12, -1.0, 0.05)
		rp.spread = 2.0
		rp.initial_velocity_min = 26.0
		rp.initial_velocity_max = 32.0
		rp.gravity = Vector3(0.0, -6.0, 0.0)
		_rain.process_material = rp
		_rain.draw_pass_1 = _particle_quad(Color(0.78, 0.82, 1.0, 0.22), Vector2(0.025, 0.7), true)
		_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_rain)


## Neon sign mounts (ambient_neon anchors): glowing tube outlines in one
## MultiMesh; the flicker runs in the shader (same curve as
## AmbientComfort.flicker), steady when the comfort settings say so.
func _build_neon(b: Dictionary) -> void:
	var found := anchors(G_NEON)
	var pick := spread(found.size(), int(b.neon))
	if pick.is_empty():
		return
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var custom: Array[Color] = []
	for j in pick.size():
		var a := found[pick[j]] as Node3D
		var size: Vector2 = a.get_meta("size", Vector2(3.0, 1.0))
		var c := NEON_COLORS[(pick[j] * 5 + match_seed) % NEON_COLORS.size()]
		var t := 0.07
		# Outline (4 tubes) plus one inner "lettering" tube at 60 % width.
		var bars := [[Vector3(0, size.y * 0.5, 0), Vector3(size.x, t, t)], [Vector3(0, -size.y * 0.5, 0), Vector3(size.x, t, t)],
			[Vector3(size.x * 0.5, 0, 0), Vector3(t, size.y, t)], [Vector3(-size.x * 0.5, 0, 0), Vector3(t, size.y, t)],
			[Vector3(-size.x * 0.1, 0, 0), Vector3(size.x * 0.6, t * 1.4, t)]]
		for bar in bars:
			xf.append(a.global_transform * Transform3D(Basis().scaled(bar[1]), bar[0] + Vector3(0, 0, 0.06)))
			cols.append(c)
			custom.append(Color(fposmod(pick[j] * 0.618, 1.0), 0, 0, 0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _unit_box()
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
		mm.set_instance_custom_data(i, custom[i])
	_neon_mat = ShaderMaterial.new()
	_neon_mat.shader = load(NEON_SHADER)
	_anim_mats.append(_neon_mat)
	var mi := MultiMeshInstance3D.new()
	mi.name = "NeonMounts"
	mi.multimesh = mm
	mi.material_override = _neon_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Steam vents (ambient_steam_vent anchors, jungle alley floors): one
## GPUParticles3D emitting from every vent point. Low, faint plumes (about
## 2.5 m, alpha <= 0.12) so they never hide a player; slower with reduce motion.
func _build_steam(b: Dictionary) -> void:
	var found := anchors(G_STEAM)
	if found.is_empty() or int(b.steam) <= 0:
		return
	var img := Image.create(found.size(), 1, false, Image.FORMAT_RGBF)
	for i in found.size():
		var p := (found[i] as Node3D).global_position
		img.set_pixel(i, 0, Color(p.x, p.y, p.z))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = ImageTexture.create_from_image(img)
	pm.emission_point_count = found.size()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 14.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0.15, 0.1, 0.0)
	pm.damping_min = 0.2
	pm.damping_max = 0.4
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	pm.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.25, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	_steam = GPUParticles3D.new()
	_steam.name = "SteamVents"
	_steam.amount = int(b.steam)
	_steam.lifetime = 2.4
	_steam.preprocess = 2.4
	_steam.local_coords = false
	_steam.process_material = pm
	_steam.visibility_aabb = AABB(Vector3(-80, -10, -360), Vector3(160, 30, 300))
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.86, 0.86, 0.94, 0.12)
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	var pg := Gradient.new()
	pg.set_color(0, Color(1, 1, 1, 1))
	pg.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = pg
	puff.width = 32
	puff.height = 32
	m.albedo_texture = puff
	q.material = m
	_steam.draw_pass_1 = q
	_steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_steam)


func _build_birds(b: Dictionary) -> void:
	if int(b.birds) <= 0:
		return
	var routes := TrafficPaths.fallback_birds()
	var tex := TrafficPaths.bake(routes)
	var custom: Array[Color] = []
	for i in int(b.birds):
		var r := i % routes.size()
		var len_m := maxf(1.0, TrafficPaths.length(routes[r], true))
		custom.append(Color(r, fposmod(i * 0.071, 1.0) + (0.0 if i % 2 == 0 else 0.02), 9.0 / len_m, (i % 3) * 2.5 - 2.5))
	var m := _mover_mat(2, tex, true)
	m.set_shader_parameter("size", Vector3(2.2, 0.15, 0.7))
	m.set_shader_parameter("body_color", Color(0.1, 0.08, 0.16))
	_custom_mm("Birds", _unit_box(), m, custom)
