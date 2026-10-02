class_name HitscanTracer
extends RefCounted
## Server hitscan against simple hitboxes (architecture.md §8.7, abridged):
## static-world occlusion ray, then ray vs each target's body capsule and head
## sphere. Nearest hit before the wall wins; head beats body at equal distance.
##
## Lag-compensation seam: _pose() returns the CURRENT pose. The lag-compensation
## epic replaces it with a HitboxHistory lookup at (view_tick + view_alpha),
## clamped to NetConfig.max_rewind_ms; callers already pass both values.

## Result of one trace (target == null: no hero hit).
class Hit:
	var target: HeroBody = null
	var distance: float = 0.0
	var headshot: bool = false
	var point: Vector3 = Vector3.ZERO

## A hitbox pose: feet position and vertical scale (crouch).
class Pose:
	var feet: Vector3
	var y_scale: float = 1.0

## Static-world limit of the last trace (wall distance, or max_range).
var last_limit: float = 0.0
var _query := PhysicsRayQueryParameters3D.new()
var _pose_scratch := Pose.new()


func _init() -> void:
	_query.collision_mask = HeroBody.LAYER_WORLD
	_query.hit_from_inside = false


## Traces from `origin` along unit `dir` up to `max_range`. `targets` are the
## hurtable heroes (the caller filters out the shooter, allies and the dead).
func trace(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, max_range: float,
		targets: Array[HeroBody], view_tick: int, view_alpha: float) -> Hit:
	var hit := Hit.new()
	var limit := max_range
	if space != null:
		_query.from = origin
		_query.to = origin + dir * max_range
		var r := space.intersect_ray(_query)
		if not r.is_empty():
			limit = origin.distance_to(r.position)
	last_limit = limit
	for h in targets:
		var pose := _pose(h, view_tick, view_alpha)
		var d: HeroDef = h.combat.def
		var s := d.hitbox_scale
		var ys := pose.y_scale * s
		var feet := pose.feet
		var r_body := d.body_radius * s
		var head_c := feet + Vector3(0.0, d.head_center_m * ys, 0.0)
		var th := ray_sphere(origin, dir, head_c, d.head_radius * s)
		var tb := ray_vertical_capsule(origin, dir, feet.y + r_body,
			feet.y + maxf(d.body_top_m * ys - r_body, r_body), Vector2(feet.x, feet.z), r_body)
		var t := -1.0
		var head := false
		if th >= 0.0 and (tb < 0.0 or th <= tb):
			t = th
			head = true
		elif tb >= 0.0:
			t = tb
		if t >= 0.0 and t <= limit and (hit.target == null or t < hit.distance):
			hit.target = h
			hit.distance = t
			hit.headshot = head
			hit.point = origin + dir * t
	return hit


## Pose of `h` at the client's view time. See the class doc (lag-comp seam).
func _pose(h: HeroBody, _view_tick: int, _view_alpha: float) -> Pose:
	var p := _pose_scratch
	p.feet = h.state.position
	p.y_scale = 1.0
	if h.state.crouching:
		p.y_scale = h.movement_def().crouch_height / h.movement_def().stand_height
	return p


## Smallest t >= 0 where the ray hits the sphere, or -1.
static func ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var m := o - c
	var b := m.dot(d)
	var cc := m.dot(m) - r * r
	if cc > 0.0 and b > 0.0:
		return -1.0
	var disc := b * b - cc
	if disc < 0.0:
		return -1.0
	return maxf(0.0, -b - sqrt(disc))


## Ray vs a vertical capsule whose axis runs from y0 to y1 at `xz`, radius r.
static func ray_vertical_capsule(o: Vector3, d: Vector3, y0: float, y1: float, xz: Vector2, r: float) -> float:
	var best := -1.0
	# Infinite vertical cylinder in XZ, clipped to [y0, y1].
	var ox := o.x - xz.x
	var oz := o.z - xz.y
	var a := d.x * d.x + d.z * d.z
	if a > 1e-9:
		var b := ox * d.x + oz * d.z
		var c := ox * ox + oz * oz - r * r
		var disc := b * b - a * c
		if disc >= 0.0:
			var t := (-b - sqrt(disc)) / a
			if c <= 0.0:
				t = 0.0  # origin inside the cylinder
			var y := o.y + d.y * t
			if t >= 0.0 and y >= y0 and y <= y1:
				best = t
	for cy in [y0, y1]:
		var ts := ray_sphere(o, d, Vector3(xz.x, cy, xz.y), r)
		if ts >= 0.0 and (best < 0.0 or ts < best):
			best = ts
	return best
