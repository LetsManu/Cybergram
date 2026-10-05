class_name AmbientComfort
extends RefCounted
## W18-LIFE: how the "World ambience" setting, the graphics tier and the comfort
## options (effects intensity, reduce motion) scale the background life.
## Pure functions (unit-tested); AmbientWorld reads them at build and on change.

const LOW: int = 0
const MEDIUM: int = 1
const HIGH: int = 2
## Below this effects intensity neon / holograms stop flickering (steady light).
const FLICKER_MIN_FX: float = 0.5
## Deepest flicker dip at 100 % effects (subtle: never below 78 % brightness).
const FLICKER_MAX_DIP: float = 0.22
## Below this effects intensity the light shafts and rain streaks are skipped.
const SHAFT_MIN_FX: float = 0.25
const RAIN_MIN_FX: float = 0.25


## Effective ambience level: the player's choice capped by the graphics tier
## (Low quality -> Low, Medium -> at most Medium, High / Ultra -> as chosen).
static func level(ambient_setting: int, gfx_quality: int) -> int:
	var cap := clampi(gfx_quality, GfxQuality.LOW, GfxQuality.HIGH)
	return mini(clampi(ambient_setting, LOW, HIGH), cap)


## Per-level budgets. Counts are instances; draw calls stay one per kind.
static func budget(lvl: int) -> Dictionary:
	match clampi(lvl, LOW, HIGH):
		LOW:
			return {traffic_lanes = 3, cars_per_lane = 10, drones = 0, train = true, trails = false,
				billboards = 2, signs = 4, neon = 16, steam = 0, shafts = 0, fog_cards = 0, motes = 60, rain = 300, birds = 0}
		MEDIUM:
			return {traffic_lanes = 5, cars_per_lane = 16, drones = 6, train = true, trails = true,
				billboards = 4, signs = 8, neon = 32, steam = 64, shafts = 3, fog_cards = 6, motes = 140, rain = 800, birds = 0}
	return {traffic_lanes = 7, cars_per_lane = 22, drones = 12, train = true, trails = true,
		billboards = 8, signs = 12, neon = 64, steam = 128, shafts = 6, fog_cards = 10, motes = 260, rain = 1600, birds = 14}


## Flicker depth 0..FLICKER_MAX_DIP: 0 (steady) with reduce motion or at low
## effects intensity, rising linearly to the max at 100 %.
static func flicker_amount(fx_intensity: float, reduce_motion: bool) -> float:
	if reduce_motion or fx_intensity < FLICKER_MIN_FX:
		return 0.0
	return FLICKER_MAX_DIP * clampf((fx_intensity - FLICKER_MIN_FX) / (1.0 - FLICKER_MIN_FX), 0.0, 1.0)


## Speed multiplier for animated surfaces (hologram scroll, searchlight sweep,
## bird flapping): frozen with reduce motion. Traffic keeps moving (far away,
## slow) but at half speed, see traffic_speed().
static func anim_speed(reduce_motion: bool) -> float:
	return 0.0 if reduce_motion else 1.0


static func traffic_speed(reduce_motion: bool) -> float:
	return 0.5 if reduce_motion else 1.0


## Emissive gain for holograms / neon / trails at an effects intensity:
## 60 % brightness at 0 %, full at 100 %. Never flashes, only dims.
static func glow_gain(fx_intensity: float) -> float:
	return lerpf(0.6, 1.0, clampf(fx_intensity, 0.0, 1.0))


static func shafts_enabled(fx_intensity: float) -> bool:
	return fx_intensity >= SHAFT_MIN_FX


## Rain particle count after the rain setting and effects intensity.
static func rain_amount(lvl: int, fx_intensity: float, rain_on: bool) -> int:
	if not rain_on or fx_intensity < RAIN_MIN_FX:
		return 0
	return int(budget(lvl).rain * clampf(fx_intensity, 0.0, 1.0))


## Neon brightness factor at time `t` (s) for a sign with `phase`: 1.0 steady,
## dipping by up to `amount`. Mostly steady with rare short dips (a failing
## tube), never an on/off strobe.
static func flicker(t: float, phase: float, amount: float) -> float:
	if amount <= 0.0:
		return 1.0
	var slow := sin(t * 0.9 + phase * 7.0) * 0.5 + 0.5
	var fast := sin(t * 23.0 + phase * 13.0) * sin(t * 37.0 + phase * 3.0)
	var gate := clampf((slow - 0.82) / 0.18, 0.0, 1.0)  # dips only ~15 % of the time
	return 1.0 - amount * gate * (0.5 + 0.5 * absf(fast))
