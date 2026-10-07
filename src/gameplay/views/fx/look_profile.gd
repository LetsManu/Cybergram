class_name LookProfile
extends Resource
## One complete world look as data (look-dev pass, docs/lookdev.md): sky, ambient,
## sun + fill, fog, grade, glow, AO, shadows, emissive multipliers, practical
## lights and the map panel material params. Client presentation only.
##
## Selection: `--look <id>` on the command line (ids in PROFILES); no flag =
## no profile, the map keeps its baked look (GfxQuality + AmbientMood).
## Applied by MapVisuals (environment, sun, fill, panels, practicals) and
## AmbientWorld (which then skips its per-mood sky / sun override and scales its
## neon / shafts by the profile's gains).
## Values are technical look-dev proposals; final colour is art-director's call.

## Launch ids -> profile files.
const PROFILES := {
	"a": "res://assets/data/look/look_a_neon_night.tres",
	"b": "res://assets/data/look/look_b_golden_hour.tres",
	"c": "res://assets/data/look/look_c_clean.tres",
}
const PANEL_SHADER := "res://assets/shaders/spatial_env_panel.gdshader"
const SKYLINE_SHADER := "res://assets/shaders/spatial_env_skyline.gdshader"

## Process-wide override (tests / tools); "" = read --look from the command line.
static var override_id: String = ""
static var _cache: Dictionary = {}

@export var id: String = ""
@export var display_name: String = ""

@export_group("Sky")
@export var sky_top: Color = Color(0.1, 0.18, 0.48)
@export var sky_horizon: Color = Color(0.78, 0.62, 0.86)
@export var ground_horizon: Color = Color(0.5, 0.36, 0.78)
@export var ground_bottom: Color = Color(0.2, 0.1, 0.42)
@export_range(0.01, 1.0) var sky_curve: float = 0.22
@export_range(0.0, 4.0) var sky_energy: float = 1.0
@export_range(0.0, 1.0) var sun_disc_curve: float = 0.2

@export_group("Ambient")
@export var ambient_color: Color = Color(0.52, 0.5, 0.82)
@export_range(0.0, 2.0) var ambient_energy: float = 0.6

@export_group("Tonemap and grade")
@export_range(0.2, 4.0) var exposure: float = 1.0
@export_range(1.0, 16.0) var tonemap_white: float = 6.0
@export_range(0.0, 2.0) var saturation: float = 1.18
@export_range(0.5, 2.0) var contrast: float = 1.08
@export_range(0.5, 1.5) var brightness: float = 1.0
## Grade LUT: shadows pulled toward grade_shadow, highlights toward grade_highlight.
@export var grade_shadow: Color = Color("#0B1015")
@export var grade_highlight: Color = Color("#ECE6D6")
@export_range(0.0, 1.0) var grade_shadow_amount: float = 0.12
@export_range(0.0, 1.0) var grade_highlight_amount: float = 0.08
## S-curve strength (0 = linear).
@export_range(0.0, 1.0) var grade_curve: float = 0.25

@export_group("Glow")
## Art bible §10.3: 1.1 (only Signal / Set-piece emissives bloom).
@export_range(0.8, 2.0) var glow_threshold: float = 1.1
@export_range(0.0, 2.0) var glow_intensity_scale: float = 1.0
@export_range(0.0, 0.5) var glow_bloom: float = 0.08

@export_group("SSAO / contact")
@export_range(0.0, 4.0) var ssao_intensity: float = 1.5
@export_range(0.1, 4.0) var ssao_radius: float = 1.6
@export_range(0.5, 4.0) var ssao_power: float = 1.5
@export_range(0.0, 1.0) var ssao_light_affect: float = 0.4
## Screen-space indirect light on Ultra only (art bible §10.3 lists SSIL off; look-dev option).
@export var ssil_ultra: bool = false
@export_range(0.0, 2.0) var ssil_intensity: float = 0.6

@export_group("Fog")
@export var fog_color: Color = Color(0.5, 0.4, 0.78)
@export_range(0.0, 0.05) var fog_density: float = 0.0028
@export_range(0.0, 1.0) var fog_sky_affect: float = 0.35
@export_range(0.0, 0.1) var fog_height_density: float = 0.035
@export var fog_height: float = -1.0
@export_range(0.0, 1.0) var fog_aerial: float = 0.0
## Volumetric fog density on High (0 = off) / Ultra.
@export_range(0.0, 0.05) var volumetric_density: float = 0.0
@export var volumetric_albedo: Color = Color(0.7, 0.62, 0.95)
@export_range(0.0, 4.0) var volumetric_anisotropy_gain: float = 0.6

@export_group("Sun (key)")
@export var sun_rotation_deg: Vector3 = Vector3(-48.0, -35.0, 0.0)
@export var sun_color: Color = Color(1.0, 0.95, 0.88)
@export_range(0.0, 4.0) var sun_energy: float = 1.0
@export_range(0.0, 1.0) var sun_shadow_opacity: float = 1.0
## Volumetric fog contribution of the sun (light shafts with volumetric fog).
@export_range(0.0, 8.0) var sun_volumetric_energy: float = 1.0

@export_group("Fill")
## Shadowless second directional light, opposite-ish to the key (fake bounce / sky fill).
@export var fill_rotation_deg: Vector3 = Vector3(-20.0, 145.0, 0.0)
@export var fill_color: Color = Color(0.45, 0.55, 1.0)
@export_range(0.0, 2.0) var fill_energy: float = 0.0

@export_group("Practical lights")
## Multiplier on every OmniLight / SpotLight baked into the map scene.
@export_range(0.0, 4.0) var practical_energy: float = 1.0
@export_range(0.5, 3.0) var practical_range: float = 1.0
## Extra warm practicals at the HQ spawn and Armory (above 4 m, HQ only: art bible §10.4).
@export var hq_practicals: bool = false
@export var hq_practical_color: Color = Color(1.0, 0.8, 0.68)
@export_range(0.0, 8.0) var hq_practical_energy: float = 2.0

@export_group("Emissive")
## Multiplier on the map's unshaded neon / trim materials (capped at emissive_cap, Set-piece tier).
@export_range(0.0, 3.0) var emissive_gain: float = 1.0
@export_range(1.0, 1.5) var emissive_cap: float = 1.5
## Ambient-world neon signs and light shafts.
@export_range(0.0, 3.0) var neon_gain: float = 1.0
@export_range(0.0, 3.0) var shaft_gain: float = 1.0
## Panel trim lines (spatial_env_panel trim_energy multiplier).
@export_range(0.0, 3.0) var trim_gain: float = 1.0

@export_group("Skyline")
@export var skyline_body: Color = Color(0.16, 0.14, 0.3)
@export var skyline_top: Color = Color(0.16, 0.14, 0.3)
@export_range(0.0, 3.0) var skyline_window_energy: float = 0.9
@export_range(0.0, 1.0) var skyline_window_density: float = 0.25

@export_group("Panels")
@export_range(0.0, 1.0) var shadow_value: float = 0.62
@export var shadow_tint: Color = Color(0.52, 0.52, 0.70)
@export_range(0.0, 1.0) var shadow_tint_mix: float = 0.35
@export_range(0.0, 1.0) var highlight_boost: float = 0.18
## Wall albedo: value scale and saturation (pale pastel walls -> deeper blocks).
@export_range(0.3, 1.5) var wall_value: float = 1.0
@export_range(0.0, 2.0) var wall_saturation: float = 1.0
@export_range(0.3, 1.5) var floor_value: float = 1.0
## Large-scale albedo breakup (0 = flat).
@export_range(0.0, 0.3) var albedo_noise: float = 0.0
## Light edge / wear line along mesh face borders (0 = off).
@export_range(0.0, 1.0) var edge_wear: float = 0.0
## Contact AO at the foot of walls: darkest value (1 = none) and grime tint mix.
@export_range(0.2, 1.0) var contact_ao_min: float = 0.72
@export_range(0.0, 1.0) var contact_grime: float = 0.0
## Cel specular band (thresholded Blinn): strength on walls / floors and the threshold.
@export_range(0.0, 2.0) var spec_wall: float = 0.0
@export_range(0.0, 2.0) var spec_floor: float = 0.0
@export_range(0.0, 1.0) var spec_threshold: float = 0.9
@export var spec_tint: Color = Color(1, 1, 1)
## Floor environment reflection (probes / sky) and its roughness (wet look < 0.4).
@export_range(0.0, 1.0) var floor_env_specular: float = 0.0
@export_range(0.0, 1.0) var floor_roughness: float = 0.8

@export_group("Reflection probes")
@export var reflection_probes: bool = false
@export_range(0.0, 2.0) var probe_intensity: float = 1.0


## The profile selected for this process (null = none: the baked look).
static func active() -> LookProfile:
	var key := override_id if override_id != "" else id_from_args(OS.get_cmdline_user_args())
	return load_id(key)


## The `--look <id>` value in `args` ("" when absent; also --look=<id>).
static func id_from_args(args: PackedStringArray) -> String:
	for i in args.size():
		var a := args[i]
		if a == "--look" and i + 1 < args.size():
			return args[i + 1].strip_edges().to_lower()
		if a.begins_with("--look="):
			return a.substr(7).strip_edges().to_lower()
	return ""


## Loads the profile for `key` (a PROFILES id or a res:// path); null when unknown.
static func load_id(key: String) -> LookProfile:
	if key == "" or key == "current" or key == "off":
		return null
	if _cache.has(key):
		return _cache[key]
	var path: String = PROFILES.get(key, key if key.begins_with("res://") else "")
	if path == "" or not ResourceLoader.exists(path):
		push_warning("[look] unknown look '%s'" % key)
		return null
	var p := load(path) as LookProfile
	_cache[key] = p
	return p


# ------------------------------------------------------------ environment

## Applies the profile over `env` for tier `lvl` (after GfxQuality.apply).
func apply_environment(env: Environment, lvl: int) -> void:
	if env == null:
		return
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial if env.sky != null else null
	if sky_mat != null:
		sky_mat.sky_top_color = sky_top
		sky_mat.sky_horizon_color = sky_horizon
		sky_mat.ground_horizon_color = ground_horizon
		sky_mat.ground_bottom_color = ground_bottom
		sky_mat.sky_curve = sky_curve
		sky_mat.sky_energy_multiplier = sky_energy
		sky_mat.sun_curve = sun_disc_curve
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = exposure
	env.tonemap_white = tonemap_white
	env.adjustment_saturation = saturation
	env.adjustment_contrast = contrast
	env.adjustment_brightness = brightness
	if lvl >= GfxQuality.HIGH:
		env.adjustment_color_correction = make_lut()
	env.glow_hdr_threshold = glow_threshold
	env.glow_intensity = GfxQuality.GLOW_INTENSITY[clampi(lvl, 0, 3)] * glow_intensity_scale
	env.glow_bloom = glow_bloom
	env.ssao_intensity = ssao_intensity
	env.ssao_radius = ssao_radius * (1.25 if lvl >= GfxQuality.ULTRA else 1.0)
	env.ssao_power = ssao_power
	env.ssao_light_affect = ssao_light_affect
	env.ssil_enabled = ssil_ultra and lvl >= GfxQuality.ULTRA
	env.ssil_intensity = ssil_intensity
	env.fog_light_color = fog_color
	env.fog_density = fog_density
	env.fog_sky_affect = fog_sky_affect
	env.fog_height = fog_height
	env.fog_height_density = fog_height_density * [0.0, 0.6, 1.0, 1.2][clampi(lvl, 0, 3)]
	env.fog_aerial_perspective = fog_aerial
	env.volumetric_fog_enabled = volumetric_density > 0.0 and lvl >= GfxQuality.HIGH
	env.volumetric_fog_density = volumetric_density * (1.0 if lvl >= GfxQuality.ULTRA else 0.7)
	env.volumetric_fog_albedo = volumetric_albedo
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.2


## Key light colour / energy / angle; shadow quality stays GfxQuality's (per tier).
func apply_sun(sun: DirectionalLight3D) -> void:
	if sun == null:
		return
	sun.rotation_degrees = sun_rotation_deg
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.shadow_opacity = sun_shadow_opacity
	sun.light_volumetric_fog_energy = sun_volumetric_energy * volumetric_anisotropy_gain


## The shadowless fill light (null when fill_energy is 0).
func make_fill() -> DirectionalLight3D:
	if fill_energy <= 0.0:
		return null
	var l := DirectionalLight3D.new()
	l.name = "LookFill"
	l.rotation_degrees = fill_rotation_deg
	l.light_color = fill_color
	l.light_energy = fill_energy
	l.shadow_enabled = false
	l.light_specular = 0.0
	l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	return l


## Grade LUT from the profile's tints (pure; GfxQuality.make_grade_lut's recipe).
func make_lut() -> Texture3D:
	var n := GfxQuality.LUT_SIZE
	var layers: Array[Image] = []
	for b in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for g in n:
			for r in n:
				img.set_pixel(r, g, grade(Color(r, g, b) / float(n - 1)))
		layers.append(img)
	var t := ImageTexture3D.new()
	t.create(Image.FORMAT_RGB8, n, n, n, false, layers)
	return t


## One graded colour (pure, testable): S-curve, then split toning by luminance.
func grade(c: Color) -> Color:
	var l := c.get_luminance()
	var s := Color(smoothstep(0.0, 1.0, c.r), smoothstep(0.0, 1.0, c.g), smoothstep(0.0, 1.0, c.b))
	var curve := c.lerp(s, grade_curve)
	var sh := curve.lerp(grade_shadow, (1.0 - smoothstep(0.0, 0.45, l)) * grade_shadow_amount)
	var hi := sh.lerp(grade_highlight, smoothstep(0.55, 1.0, l) * grade_highlight_amount)
	return Color(clampf(hi.r, 0.0, 1.0), clampf(hi.g, 0.0, 1.0), clampf(hi.b, 0.0, 1.0))


# ------------------------------------------------------------ map materials

## Pushes the panel / skyline / emissive params onto every material under `root`
## (each shared material once; original values kept in metadata, so re-applying
## is idempotent).
func apply_materials(root: Node) -> void:
	var seen := {}
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		var mats: Array[Material] = []
		if gi.material_override != null:
			mats.append(gi.material_override)
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			var mesh := (gi as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var m := mesh.surface_get_material(s)
				if m != null:
					mats.append(m)
		for m in mats:
			if seen.has(m):
				continue
			seen[m] = true
			if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
				var path := (m as ShaderMaterial).shader.resource_path
				if path == PANEL_SHADER:
					_panel(m as ShaderMaterial)
				elif path == SKYLINE_SHADER:
					_skyline(m as ShaderMaterial)
			elif m is StandardMaterial3D:
				_emissive(m as StandardMaterial3D)


func _orig(m: Material, key: StringName, v: Variant) -> Variant:
	if not m.has_meta(key):
		m.set_meta(key, v)
	return m.get_meta(key)


func _panel(m: ShaderMaterial) -> void:
	var base: Color = _orig(m, &"look_base", m.get_shader_parameter("base_color"))
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("wall_value", wall_value)
	m.set_shader_parameter("wall_saturation", wall_saturation)
	m.set_shader_parameter("floor_value", floor_value)
	m.set_shader_parameter("shadow_value", shadow_value)
	m.set_shader_parameter("shadow_tint", Vector3(shadow_tint.r, shadow_tint.g, shadow_tint.b))
	m.set_shader_parameter("shadow_tint_mix", shadow_tint_mix)
	m.set_shader_parameter("highlight_boost", highlight_boost)
	m.set_shader_parameter("albedo_noise", albedo_noise)
	m.set_shader_parameter("edge_wear", edge_wear)
	m.set_shader_parameter("contact_ao_min", contact_ao_min)
	m.set_shader_parameter("contact_grime", contact_grime)
	m.set_shader_parameter("spec_wall", spec_wall)
	m.set_shader_parameter("spec_floor", spec_floor)
	m.set_shader_parameter("spec_threshold", spec_threshold)
	m.set_shader_parameter("spec_tint", Vector3(spec_tint.r, spec_tint.g, spec_tint.b))
	m.set_shader_parameter("floor_env_specular", floor_env_specular)
	m.set_shader_parameter("floor_roughness", floor_roughness)
	var te: Variant = m.get_shader_parameter("trim_energy")
	var trim0: float = _orig(m, &"look_trim", float(te) if te != null else 0.9)
	m.set_shader_parameter("trim_energy", trim0 * trim_gain)


func _skyline(m: ShaderMaterial) -> void:
	m.set_shader_parameter("body_color", Vector3(skyline_body.r, skyline_body.g, skyline_body.b))
	m.set_shader_parameter("top_color", Vector3(skyline_top.r, skyline_top.g, skyline_top.b))
	m.set_shader_parameter("window_energy", skyline_window_energy)
	m.set_shader_parameter("window_density", skyline_window_density)


## Unshaded opaque map colours are the neon / trim class: scaled, capped (Set-piece tier).
func _emissive(m: StandardMaterial3D) -> void:
	if m.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return
	var c: Color = _orig(m, &"look_albedo", m.albedo_color)
	var k := emissive_gain
	var peak := maxf(c.r, maxf(c.g, c.b)) * k
	if peak > emissive_cap:
		k *= emissive_cap / peak
	m.albedo_color = Color(c.r * k, c.g * k, c.b * k, c.a)


# ------------------------------------------------------------ validation

## Range problems ("" = none). Readability floors: art bible §2.3 exposure floor
## (key + fill + ambient never below 70 % of the current Skirmish look's 1.6) and
## glow threshold no lower than the §10.3 1.1.
func validate() -> PackedStringArray:
	var out: PackedStringArray = []
	var light := sun_energy + fill_energy + ambient_energy
	if light < 1.6 * 0.7:
		out.append("exposure floor: key + fill + ambient %.2f < 1.12" % light)
	if glow_threshold < 1.1:
		out.append("glow threshold %.2f below 1.1" % glow_threshold)
	if emissive_cap > 1.5:
		out.append("emissive cap above the Set-piece tier 1.5")
	if shadow_value < 0.2:
		out.append("shadow value %.2f: shadows read black" % shadow_value)
	for c in [sky_top, sky_horizon, ambient_color, fog_color, sun_color, fill_color]:
		if c.r < 0.0 or c.g < 0.0 or c.b < 0.0:
			out.append("negative colour")
	return out
