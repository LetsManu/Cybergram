class_name GfxQuality
extends RefCounted
## Graphics quality tiers and the shared environment recipe (chunk G1, client
## presentation only). The tier comes from GameSettings `graphics_quality`
## (0 Low, 1 Medium, 2 High, 3 Ultra; 2 when the field is absent). Everything
## here degrades gracefully in the OpenGL compatibility renderer: features it
## lacks (SSAO, volumetric fog) are simply ignored by the engine there.
## The headless server never builds any of this: callers check is_headless().

const LOW: int = 0
const MEDIUM: int = 1
const HIGH: int = 2
const ULTRA: int = 3
const DEFAULT_LEVEL: int = HIGH

## Art bible §10.3: glow threshold 1.1 (only Signal / Set-piece emissives bloom).
const GLOW_THRESHOLD: float = 1.1


## True on the dedicated server / headless runs: no visual node may be created.
static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Current tier (0..3). Reads GameSettings.graphics_quality when the field exists.
static func level() -> int:
	var gs: Object = GameSettings.shared()
	var v: Variant = gs.get("graphics_quality")
	if v == null:
		return DEFAULT_LEVEL
	return clampi(int(v), LOW, ULTRA)


## Multiplier for particle counts and decoration density per tier.
static func particle_scale(lvl: int) -> float:
	match clampi(lvl, LOW, ULTRA):
		LOW:
			return 0.35
		MEDIUM:
			return 0.65
		HIGH:
			return 1.0
	return 1.5


## Number of muzzle-flash OmniLights pooled per tier (0 on Low: flash quad only).
static func muzzle_lights(lvl: int) -> int:
	return [0, 2, 4, 6][clampi(lvl, LOW, ULTRA)]


## Visual layer the characters (heroes, Wardlings) live on, alone: the rim light
## lights only this layer and floor decals skip it (no decal on boots).
const HERO_VISUAL_LAYER: int = 2


## Render-layer bits of a character mesh (pure).
static func character_layers() -> int:
	return 1 << (HERO_VISUAL_LAYER - 1)


## Cull mask for world decals: every layer except the characters' (pure).
static func decal_cull_mask() -> int:
	return 0xFFFFF & ~character_layers()
const INK_EDGE_SHADER := "res://assets/shaders/spatial_fx_ink_edges.gdshader"
## Premium-dark UI palette (design/ux/mockups/v0.9/README.md): ground ink for the
## shadow tint, ivory for the highlight tint. Art-director's values, used as given.
const GRADE_SHADOW := Color("#0B1015")
const GRADE_HIGHLIGHT := Color("#ECE6D6")
const LUT_SIZE: int = 16

## Per-tier glow intensity (Low off). Emissives are authored at 2.2x albedo, so a
## 1.1 HDR threshold lets visors / cables / team accents bloom while lit cel
## surfaces (<= 1.0) do not wash out.
const GLOW_INTENSITY := [0.0, 0.45, 0.6, 0.7]
const GLOW_STRENGTH := [1.0, 0.9, 0.95, 1.0]


static var _lut: Texture3D


## Rim-light tier gate: High and above.
static func rim_light_enabled(lvl: int) -> bool:
	return lvl >= HIGH


## Ink edge pass tier gate: High and Ultra only.
static func ink_edges_enabled(lvl: int) -> bool:
	return lvl >= HIGH


## Ink edge line width (px) per tier.
static func ink_edge_width(lvl: int) -> float:
	return 1.0 if lvl <= HIGH else 1.4


## Colour grade 3D LUT: identity with a subtle pull of shadows toward ground ink
## and highlights toward ivory, plus a gentle S-curve. `amount` 0 = identity.
static func make_grade_lut(amount: float = 1.0) -> Texture3D:
	if amount == 1.0 and _lut != null:
		return _lut
	var layers: Array[Image] = []
	for b in LUT_SIZE:
		var img := Image.create(LUT_SIZE, LUT_SIZE, false, Image.FORMAT_RGB8)
		for g in LUT_SIZE:
			for r in LUT_SIZE:
				var c := Color(r, g, b) / float(LUT_SIZE - 1)
				var l := c.get_luminance()
				var curve := c.lerp(Color(smoothstep(0.0, 1.0, c.r), smoothstep(0.0, 1.0, c.g), smoothstep(0.0, 1.0, c.b)), 0.25 * amount)
				var sh := curve.lerp(GRADE_SHADOW.lightened(0.15), (1.0 - smoothstep(0.0, 0.45, l)) * 0.12 * amount)
				var hi := sh.lerp(GRADE_HIGHLIGHT, smoothstep(0.65, 1.0, l) * 0.08 * amount)
				img.set_pixel(r, g, Color(hi.r, hi.g, hi.b))
		layers.append(img)
	var t := ImageTexture3D.new()
	t.create(Image.FORMAT_RGB8, LUT_SIZE, LUT_SIZE, LUT_SIZE, false, layers)
	if amount == 1.0:
		_lut = t
	return t


## Cool, shadowless, hero-only back light that follows the camera (toon rim).
static func make_rim_light() -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = "RimLight"
	l.light_color = Color(0.78, 0.86, 1.0)
	l.light_energy = 0.55
	l.shadow_enabled = false
	l.light_cull_mask = 1 << (HERO_VISUAL_LAYER - 1)
	l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	return l


## Full-screen ink edge quad (clip-space vertex shader; add under any 3D node).
static func make_ink_edges(lvl: int) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	var mi := MeshInstance3D.new()
	mi.name = "InkEdges"
	mi.mesh = q
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = load(INK_EDGE_SHADER)
	m.set_shader_parameter("width_px", ink_edge_width(lvl))
	m.set_shader_parameter("compat_depth", RenderingServer.get_current_rendering_method() == "gl_compatibility")
	mi.material_override = m
	return mi


## Builds the Shardline environment at High quality. Stored in the map scene by
## the builder; apply() scales it for the player's tier at runtime.
static func make_environment() -> Environment:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	# Late-afternoon Halcyra: deep blue zenith, pale violet-peach horizon,
	# Leyfall violet below (art bible §2.3, §6.1).
	sky_mat.sky_top_color = Color(0.1, 0.18, 0.48)
	sky_mat.sky_horizon_color = Color(0.78, 0.62, 0.86)
	sky_mat.sky_curve = 0.22
	sky_mat.ground_horizon_color = Color(0.5, 0.36, 0.78)
	sky_mat.ground_bottom_color = Color(0.2, 0.1, 0.42)
	sky_mat.ground_curve = 0.1
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.2
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Tinted ambient so shadows stay blue-violet, never grey (art bible §4.5).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.5, 0.82)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.08
	env.glow_enabled = true
	env.glow_hdr_threshold = GLOW_THRESHOLD
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_strength = 1.0
	env.set_glow_level(1, 0.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.4)
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.5
	env.ssao_light_affect = 0.4
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.5, 0.4, 0.78)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.35
	# Leyfall void: thicker violet haze below the causeway.
	env.fog_height = -1.0
	env.fog_height_density = 0.035
	env.volumetric_fog_enabled = false
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.7, 0.62, 0.95)
	return env


## Builds the sun: cool 6500 K-ish key light with tinted shadows.
static func make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 200.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	return sun


## Sun cascade splits as fractions of the max distance, tuned for a first-person
## view: the first cascade covers ~10 m (boots, cover lips), the second ~30 m.
const SUN_SPLITS := [0.05, 0.15, 0.4]
## Directional shadow atlas (px) and soft filter per tier.
const SUN_ATLAS := [2048, 4096, 4096, 8192]
const SUN_NORMAL_BIAS := [2.0, 1.6, 1.2, 1.0]
## Shadowed local (omni / spot) lights per tier, the positional atlas size and its
## quadrant subdivisions (lights per quadrant: 1, 4, 4, 16).
const LOCAL_SHADOWS := [0, 2, 4, 8]
const LOCAL_ATLAS := [0, 2048, 4096, 4096]


## Sun / local shadow quality for tier `lvl` (renderer-wide settings plus the sun
## and the viewport's positional atlas). Any argument may be null.
static func apply_shadows(lvl: int, sun: DirectionalLight3D, vp: Viewport) -> void:
	lvl = clampi(lvl, LOW, ULTRA)
	if sun != null:
		sun.directional_shadow_split_1 = SUN_SPLITS[0]
		sun.directional_shadow_split_2 = SUN_SPLITS[1]
		sun.directional_shadow_split_3 = SUN_SPLITS[2]
		sun.directional_shadow_blend_splits = lvl >= HIGH
		sun.directional_shadow_fade_start = 0.85
		sun.shadow_bias = 0.03
		sun.shadow_normal_bias = SUN_NORMAL_BIAS[lvl]
	if is_headless():
		return
	RenderingServer.directional_shadow_atlas_set_size(SUN_ATLAS[lvl], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([
		RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][lvl])
	RenderingServer.positional_soft_shadow_filter_set_quality([
		RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][lvl])
	if vp != null:
		vp.positional_shadow_atlas_size = LOCAL_ATLAS[lvl]
		vp.positional_shadow_atlas_16_bits = true
		var sub := Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4 if lvl < ULTRA else Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16
		vp.set_positional_shadow_atlas_quadrant_subdiv(0, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1)
		for q in [1, 2, 3]:
			vp.set_positional_shadow_atlas_quadrant_subdiv(q, sub)


## Small world props (below the tall-prop cut) cast sun shadows from this tier.
static func small_prop_shadows(lvl: int) -> bool:
	return lvl >= HIGH


## Scales `env`, `sun` and the viewport AA to tier `lvl`. Any argument may be null.
static func apply(lvl: int, env: Environment, sun: DirectionalLight3D, vp: Viewport) -> void:
	lvl = clampi(lvl, LOW, ULTRA)
	if env != null:
		env.glow_enabled = lvl >= MEDIUM
		env.glow_intensity = GLOW_INTENSITY[lvl]
		env.glow_strength = GLOW_STRENGTH[lvl]
		env.glow_hdr_scale = 1.4
		env.glow_hdr_luminance_cap = 10.0
		env.adjustment_color_correction = make_grade_lut() if lvl >= HIGH else null
		env.ssao_enabled = lvl >= HIGH
		env.ssao_radius = 1.6 if lvl == HIGH else 2.0
		env.fog_enabled = true
		env.fog_height_density = [0.0, 0.02, 0.035, 0.045][lvl]
		env.volumetric_fog_enabled = lvl >= ULTRA
		env.adjustment_enabled = lvl >= MEDIUM
	if sun != null:
		sun.shadow_enabled = lvl >= MEDIUM
		sun.directional_shadow_mode = [
			DirectionalLight3D.SHADOW_ORTHOGONAL, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
			DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS][lvl]
		sun.directional_shadow_max_distance = [80.0, 120.0, 200.0, 300.0][lvl]
		sun.shadow_blur = [1.0, 1.0, 1.4, 2.0][lvl]
	apply_shadows(lvl, sun, vp)
	if vp != null:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][lvl]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if lvl == MEDIUM or lvl == ULTRA else Viewport.SCREEN_SPACE_AA_DISABLED


static var _blob_mat: StandardMaterial3D


## Blob contact shadows under heroes and Wardlings on this tier only (Low: no
## sun shadows, so characters would float).
static func blob_shadows_enabled(lvl: int) -> bool:
	return lvl <= LOW


## Soft dark disc on the floor under a character (unshaded, alpha, one shared
## material and gradient texture). Parent it to the model root (at the feet).
static func make_blob_shadow(radius: float) -> MeshInstance3D:
	if _blob_mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.05, 0.04, 0.12, 0.55))
		g.set_color(1, Color(0.05, 0.04, 0.12, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_blob_mat = StandardMaterial3D.new()
		_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blob_mat.albedo_texture = tex
		_blob_mat.render_priority = -1
	var q := PlaneMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	var mi := MeshInstance3D.new()
	mi.name = "BlobShadow"
	mi.mesh = q
	mi.material_override = _blob_mat
	mi.position.y = 0.03
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
