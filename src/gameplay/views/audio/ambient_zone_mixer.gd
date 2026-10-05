class_name AmbientZoneMixer
extends RefCounted
## W21-A1: per-zone ambient bed weights at a listener position (pure logic).
## Zones are XZ shapes: circles (base) and rectangles (jungle pockets, water
## AABBs). A zone's weight is 1 inside, fading linearly to 0 at crossfade_m
## outside its edge; lane = 1 - the strongest other zone (the default bed).

const ZONES: Array[StringName] = [&"base", &"lane", &"jungle", &"water"]

var crossfade_m: float = 6.0
var _circles: Array = []  # [zone, Vector2 centre, radius]
var _rects: Array = []  # [zone, Rect2]


func add_circle(zone: StringName, center: Vector3, radius: float) -> void:
	_circles.append([zone, Vector2(center.x, center.z), radius])


func add_rect(zone: StringName, rect: Rect2) -> void:
	_rects.append([zone, rect])


## Zones from a MapDef (null = only the lane bed).
static func from_map(md: MapDef, base_radius_m: float, fade_m: float) -> AmbientZoneMixer:
	var m := AmbientZoneMixer.new()
	m.crossfade_m = fade_m
	if md == null:
		return m
	for hq in md.hqs:
		m.add_circle(&"base", hq.sanctum, base_radius_m)
		m.add_circle(&"base", hq.armory, base_radius_m)
	for jp in md.jungle_pockets:
		m.add_rect(&"jungle", Rect2(jp.center.x - jp.size.x * 0.5, jp.center.z - jp.size.y * 0.5, jp.size.x, jp.size.y))
	for w in md.water_zones:
		m.add_rect(&"water", Rect2(w.bounds.position.x, w.bounds.position.z, w.bounds.size.x, w.bounds.size.z))
	return m


## Zone -> weight 0..1 at `pos`.
func weights(pos: Vector3) -> Dictionary:
	var p := Vector2(pos.x, pos.z)
	var w := {&"base": 0.0, &"jungle": 0.0, &"water": 0.0}
	for c in _circles:
		var d := maxf(p.distance_to(c[1]) - float(c[2]), 0.0)
		w[c[0]] = maxf(w[c[0]], _fade(d))
	for r in _rects:
		var rc: Rect2 = r[1]
		var q := Vector2(clampf(p.x, rc.position.x, rc.end.x), clampf(p.y, rc.position.y, rc.end.y))
		w[r[0]] = maxf(w[r[0]], _fade(p.distance_to(q)))
	var top := maxf(w[&"base"], maxf(w[&"jungle"], w[&"water"]))
	w[&"lane"] = clampf(1.0 - top, 0.0, 1.0)
	return w


func _fade(outside_m: float) -> float:
	if crossfade_m <= 0.0:
		return 1.0 if outside_m <= 0.0 else 0.0
	return clampf(1.0 - outside_m / crossfade_m, 0.0, 1.0)
