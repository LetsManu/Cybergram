class_name AmbientMood
extends RefCounted
## W18-LIFE: per-match time-of-day mood and weather (client presentation only).
## Both are pure functions of the match seed, so every client of one match picks
## the same look and evidence screenshots are reproducible. The colour values
## are first-pass technical defaults taken from the art bible palette (§2.3,
## §6.1); final grading is art-director's call.

enum Mood { DUSK, NIGHT, OVERCAST }
enum Weather { CLEAR, FOG, RAIN }

const MOOD_NAMES: Array[String] = ["dusk", "night", "overcast"]
const WEATHER_NAMES: Array[String] = ["clear", "fog", "rain"]
## Weighting: dusk is the house look, so it comes up most often.
const MOOD_WEIGHTS: Array[int] = [5, 3, 2]
const WEATHER_WEIGHTS: Array[int] = [5, 3, 2]


## Deterministic mood for `seed` (same seed -> same mood on every machine).
static func pick_mood(seed: int) -> int:
	return _weighted(_mix(seed, 0x6D6F6F64), MOOD_WEIGHTS)


## Deterministic weather for `seed`. Rain is only possible when `rain_allowed`
## (player setting); it then falls back to fog.
static func pick_weather(seed: int, rain_allowed: bool = true) -> int:
	var w := _weighted(_mix(seed, 0x77657468), WEATHER_WEIGHTS)
	if w == Weather.RAIN and not rain_allowed:
		return Weather.FOG
	return w


## Mood index for a name ("dusk" / "night" / "overcast"); -1 when unknown.
static func mood_from_name(n: String) -> int:
	return MOOD_NAMES.find(n.strip_edges().to_lower())


## Weather index for a name ("clear" / "fog" / "rain"); -1 when unknown.
static func weather_from_name(n: String) -> int:
	return WEATHER_NAMES.find(n.strip_edges().to_lower())


## Stable 31-bit integer hash of (seed, salt): integer maths only, so it does
## not depend on the platform's float or String hashing.
static func _mix(seed: int, salt: int) -> int:
	var h := (seed ^ salt) & 0x7FFFFFFF
	h = ((h >> 16) ^ h) * 0x45D9F3B & 0x7FFFFFFF
	h = ((h >> 16) ^ h) * 0x45D9F3B & 0x7FFFFFFF
	h = (h >> 16) ^ h
	return h & 0x7FFFFFFF


static func _weighted(h: int, weights: Array[int]) -> int:
	var total := 0
	for w in weights:
		total += w
	var r := h % total
	for i in weights.size():
		if r < weights[i]:
			return i
		r -= weights[i]
	return 0


## Look parameters per mood. Keys:
##  sky_top, sky_horizon, ground_horizon (Color), sun_color (Color), sun_energy,
##  ambient_color (Color), ambient_energy, fog_color (Color), fog_density,
##  neon_gain (emissive multiplier for signs / holograms), trail_gain (traffic
##  light trails; 0 = off), shaft_gain (light shafts).
## Readability floor: ambient_energy never drops below 0.5 and the sun below
## 0.45, so heroes read the same in every mood.
static func look(mood: int) -> Dictionary:
	match mood:
		Mood.NIGHT:
			return {
				sky_top = Color(0.03, 0.04, 0.12), sky_horizon = Color(0.22, 0.14, 0.36),
				ground_horizon = Color(0.2, 0.1, 0.38), sun_color = Color(0.7, 0.78, 1.0),
				sun_energy = 0.5, ambient_color = Color(0.42, 0.44, 0.78), ambient_energy = 0.62,
				fog_color = Color(0.22, 0.17, 0.42), fog_density = 0.0032,
				neon_gain = 1.5, trail_gain = 1.0, shaft_gain = 0.9,
			}
		Mood.OVERCAST:
			return {
				sky_top = Color(0.3, 0.32, 0.42), sky_horizon = Color(0.6, 0.58, 0.68),
				ground_horizon = Color(0.42, 0.36, 0.6), sun_color = Color(0.9, 0.92, 0.98),
				sun_energy = 0.7, ambient_color = Color(0.56, 0.56, 0.74), ambient_energy = 0.72,
				fog_color = Color(0.52, 0.5, 0.64), fog_density = 0.0042,
				neon_gain = 1.1, trail_gain = 0.0, shaft_gain = 0.5,
			}
	return {
		sky_top = Color(0.1, 0.16, 0.42), sky_horizon = Color(0.92, 0.6, 0.66),
		ground_horizon = Color(0.5, 0.34, 0.74), sun_color = Color(1.0, 0.86, 0.72),
		sun_energy = 0.9, ambient_color = Color(0.54, 0.48, 0.8), ambient_energy = 0.6,
		fog_color = Color(0.56, 0.4, 0.72), fog_density = 0.0028,
		neon_gain = 1.0, trail_gain = 0.35, shaft_gain = 1.0,
	}


## Applies `look(mood)` to the map's environment and sun (either may be null).
## Fog density is raised for the FOG weather.
static func apply(mood: int, weather: int, env: Environment, sun: DirectionalLight3D) -> void:
	var lk := look(mood)
	if env != null:
		var sky_mat := env.sky.sky_material as ProceduralSkyMaterial if env.sky != null else null
		if sky_mat != null:
			sky_mat.sky_top_color = lk.sky_top
			sky_mat.sky_horizon_color = lk.sky_horizon
			sky_mat.ground_horizon_color = lk.ground_horizon
		env.ambient_light_color = lk.ambient_color
		env.ambient_light_energy = lk.ambient_energy
		env.fog_light_color = lk.fog_color
		env.fog_density = float(lk.fog_density) * (1.8 if weather == Weather.FOG else (1.4 if weather == Weather.RAIN else 1.0))
	if sun != null:
		sun.light_color = lk.sun_color
		sun.light_energy = lk.sun_energy
