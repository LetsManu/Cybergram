class_name WaterZoneDef
extends Resource
## A wading zone as map data (W16-SDWATER; Shardline Front map spec: dock water
## slows movement 15%). An axis-aligned box in world space plus a speed factor.
## The movement simulation (HeroMotor, shared by server and client prediction)
## and Wardling movement read it; the map builder writes it from the dock
## water meshes. Presentation (splash, wading loop) reads it too.

## World-space box: x/z footprint, y range counted as "standing in the water"
## (feet below the top of the range; a jump clear of it leaves the water).
@export var bounds: AABB = AABB()
## Move-speed multiplier inside (0.85 = 15% slower).
@export_range(0.1, 1.0, 0.01) var speed_factor: float = 0.85


func contains(pos: Vector3) -> bool:
	return bounds.has_point(pos)


## Strongest (lowest) speed factor of every zone containing `pos`; 1.0 outside
## all zones. Overlapping zones never multiply.
static func factor_at(zones: Array, pos: Vector3) -> float:
	var f := 1.0
	for z in zones:
		if (z as WaterZoneDef).contains(pos):
			f = minf(f, (z as WaterZoneDef).speed_factor)
	return f


## Combines a StatBlock/status move-speed scale with the water factor. Slows are
## NEVER multiplied: the strongest slow wins (a 30% ability slow in 15% water is
## 0.70, not 0.595). Haste (> 1) still applies on top of the winning slow;
## a root (0) stays 0.
static func combine(speed_scale: float, water_factor: float) -> float:
	var slow := minf(minf(speed_scale, 1.0), water_factor)
	var haste := maxf(speed_scale, 1.0)
	return slow * haste
