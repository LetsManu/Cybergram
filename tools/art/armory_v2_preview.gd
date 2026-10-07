extends Node3D
## Armory v2 visual evidence (items-and-armory.md §3.8, weapons-and-mods.md
## §3.6.2-§3.6.3, §3.7.1). Not part of the game flow.
## Usage: tools/ci/capture_scene.sh res://tools/art/armory_v2_preview.tscn out.png 120 --av <guns|hero|hero_back|tracers>
##   guns:      a Mana gun and a Mechanical gun with Assembly and Signature parts, plus
##              the belt clip-on Components in both forms (Crystal / Chip).
##   hero:      Ryker and Liora in third person with gear, loose components and a spare.
##   hero_back: the same from behind (back gear, badge).
##   tracers:   one tracer + impact per Ammo Type (Standard ... Sunder).

const GUN_ASSEMBLY: Array[StringName] = [&"ember_facet", &"bore_ring", &"wellframe", &"ammo_shock", &""]
const GUN_SIGNATURE: Array[StringName] = [&"ember_heart", &"longsight_lens", &"flux_coil", &"ammo_incendiary", &"mod_saturated"]
const COMPONENTS: Array[StringName] = [&"ember_part", &"tempo_part", &"lens_part", &"steady_part", &"feed_part"]
const AMMO_ORDER: Array[int] = [0, 1, 3, 4, 5, 6, 2]  # Standard, Piercing, Incendiary, Shock, Siphon, Cryo, Sunder

var _cat: ArmoryCatalogDef
var _tracers: TracerFx
var _t: float = 0.0
var _mode: String = "guns"


func _ready() -> void:
	_cat = ArmoryVisualsData.catalog()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--av")
	_mode = args[i + 1] if i >= 0 and i + 1 < args.size() else "guns"
	_stage()
	match _mode:
		"guns":
			_guns()
		"hero", "hero_back":
			_heroes(_mode == "hero_back")
		"tracers":
			_tracer_stage()


func _stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#2A2838")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#9A98B8")
	e.ambient_light_energy = 0.7
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.2
	add_child(sun)


func _cam(pos: Vector3, look: Vector3, fov: float = 40.0) -> void:
	var c := Camera3D.new()
	c.fov = fov
	add_child(c)
	c.look_at_from_position(pos, look)
	c.current = true


func _label(text: String, pos: Vector3, size: int = 48) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0012
	l.outline_size = 8
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)


func _build(ids: Array) -> PackedInt32Array:
	var b := PackedInt32Array()
	for id in ids:
		b.append(_cat.index_of(id) if id != &"" else -1)
	while b.size() < SnapshotData.EntityState.BUILD_SIZE:
		b.append(-1)
	return b


func _guns() -> void:
	_cam(Vector3(0.0, 0.05, 2.1), Vector3(0.0, 0.05, 0.0))
	var cols := [[&"threadcaster", "Mana gun (Crystal form)", -0.5], [&"breakline", "Mechanical gun (Chip form)", 0.5]]
	for c in cols:
		var x: float = c[2]
		_label(String(c[1]), Vector3(x, 0.62, 0.0), 44)
		for r in 2:
			var w := WeaponModelBuilder.build(c[0], true, ModelPalette.TEAM_CONCORD)
			add_child(w)
			w.rotation_degrees = Vector3(0, 90, 0)
			w.position = Vector3(x + 0.16, 0.3 - r * 0.36, 0.0)
			w.scale = Vector3.ONE * 0.75
			w.set_build(_build(GUN_ASSEMBLY if r == 0 else GUN_SIGNATURE), _cat)
			_label("Assembly" if r == 0 else "Signature", Vector3(x, 0.45 - r * 0.36, 0.0), 30)
		# Belt clip-on Components (open slots) in this gun family's form.
		var mana: bool = c[0] == &"threadcaster"
		for k in COMPONENTS.size():
			var g := GearVisuals.build(_cat.find(COMPONENTS[k]), 1, mana, false, 2.4)
			g.position = Vector3(x - 0.24 + k * 0.12, -0.42, 0.0)
			add_child(g)
		_label("Components (belt clip-ons)", Vector3(x, -0.3, 0.0), 30)


func _heroes(back: bool) -> void:
	var z := -1.0 if back else 1.0
	_cam(Vector3(0.0, 1.3, 2.7 * z), Vector3(0.0, 1.1, 0.0), 40.0)
	var specs := [
		[&"ryker", -0.55, [&"ember_heart", &"bore_ring", &"wellframe", &"ammo_piercing", &"mod_tracer",
			&"tempo_part", &"tempo_part", &"vital_cell", &"bastion_plate", &"null_veil", &"stride_clip"]],
		[&"liora", 0.55, [&"pulse_facet", &"longsight_lens", &"", &"ammo_siphon", &"",
			&"lens_part", &"feed_part", &"vital_core", &"cadence_bead", &"cadence_circlet", &"cadence_crown"]],
	]
	for s in specs:
		var m := HeroModelLoader.build(s[0], ModelPalette.TEAM_CONCORD)
		add_child(m)
		m.position = Vector3(s[1], 0.0, 0.0)
		m.rotation_degrees.y = 180.0 + (12.0 if s[1] < 0.0 else -12.0)  # face the camera
		m.set_build(_build(s[2]), _cat)
	_label("Ryker: Tempo spare (unlit), Bastion Plate, Null Veil" if not back else "Back: Null Veil fins, overflow badge", Vector3(0, 2.02, 0), 30)


func _tracer_stage() -> void:
	_cam(Vector3(0.0, 1.6, 6.0), Vector3(0.0, 0.9, -2.0), 50.0)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(9, 4, 0.2)
	wall.mesh = bm
	wall.position = Vector3(0, 1.2, -4.0)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("#3B3A4A")  # dark wall: additive tracers read like in a lane
	wall.material_override = wm
	add_child(wall)
	_tracers = TracerFx.new()
	add_child(_tracers)
	for k in AMMO_ORDER.size():
		_label(String(ArmoryVisualsData.ammo_tell(AMMO_ORDER[k]).get("name", "")).capitalize(),
			Vector3(-3.3 + k * 1.1, 2.6, -3.8), 200)


func _process(delta: float) -> void:
	if _tracers == null:
		return
	_t += delta
	if _t < 0.05:
		return
	_t = 0.0
	for k in AMMO_ORDER.size():
		var x := -3.3 + k * 1.1
		_tracers.spawn(Vector3(x * 0.4, 0.6, 3.0), Vector3(x, 1.2, -3.85), Color("#FFF2D0"), false, AMMO_ORDER[k], 0)
