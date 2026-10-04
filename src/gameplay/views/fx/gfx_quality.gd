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


## Scales `env`, `sun` and the viewport AA to tier `lvl`. Any argument may be null.
static func apply(lvl: int, env: Environment, sun: DirectionalLight3D, vp: Viewport) -> void:
	lvl = clampi(lvl, LOW, ULTRA)
	if env != null:
		env.glow_enabled = lvl >= MEDIUM
		env.glow_intensity = [0.0, 0.5, 0.7, 0.85][lvl]
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
	if vp != null:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][lvl]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if lvl == MEDIUM or lvl == ULTRA else Viewport.SCREEN_SPACE_AA_DISABLED
