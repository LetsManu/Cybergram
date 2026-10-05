class_name TrafficPaths
extends RefCounted
## W18-LIFE: background traffic routes (flying cars, drones, birds, sky-train).
## A route is a PackedVector3Array of evenly spaced samples; closed routes loop.
## Routes come from the map's ambient anchors (Path3D) when present, else from
## the fallback generators below, which keep every point outside the playable
## bounds. The same samples are baked into a float texture that the mover
## shader reads, so sample() here mirrors the shader exactly.

## Samples per route (texture width).
const SAMPLES: int = 64
## Playable box of Shardline Front (x, z) plus margin: nothing may enter it
## below CLEAR_Y. Lanes span x -95..95 and L 0..420 (z = -L).
const PLAY_MIN := Vector2(-100.0, -430.0)
const PLAY_MAX := Vector2(100.0, 10.0)
const CLEAR_Y: float = 30.0


## Position at u (0..1) along `pts` with linear interpolation; closed routes wrap.
static func sample(pts: PackedVector3Array, u: float, closed: bool) -> Vector3:
	var n := pts.size()
	if n == 0:
		return Vector3.ZERO
	if n == 1:
		return pts[0]
	if closed:
		var f := fposmod(u, 1.0) * n
		var i0 := int(floor(f)) % n
		return pts[i0].lerp(pts[(i0 + 1) % n], f - floor(f))
	var g := clampf(u, 0.0, 1.0) * (n - 1)
	var j0 := mini(int(floor(g)), n - 2)
	return pts[j0].lerp(pts[j0 + 1], g - j0)


## Length of the route in metres.
static func length(pts: PackedVector3Array, closed: bool) -> float:
	var d := 0.0
	for i in pts.size() - 1:
		d += pts[i].distance_to(pts[i + 1])
	if closed and pts.size() > 1:
		d += pts[-1].distance_to(pts[0])
	return d


## Resamples any polyline (e.g. a baked Curve3D) to SAMPLES evenly spaced points.
static func resample(src: PackedVector3Array, closed: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	if src.is_empty():
		return out
	var total := length(src, closed)
	var seg := PackedFloat32Array()
	var count := src.size() if closed else src.size() - 1
	for i in count:
		seg.append(src[i].distance_to(src[(i + 1) % src.size()]))
	var steps := SAMPLES if closed else SAMPLES - 1
	var k := 0
	var acc := 0.0
	for s in SAMPLES:
		var want := total * s / float(steps)
		while k < count - 1 and acc + seg[k] < want:
			acc += seg[k]
			k += 1
		var a := 0.0 if seg[k] <= 0.0 else clampf((want - acc) / seg[k], 0.0, 1.0)
		out.append(src[k].lerp(src[(k + 1) % src.size()], a))
	return out


## Closed oval loop around the map centre: half extents `rx` (x) and `rz` (z),
## height `y` with a gentle `wave` (m) of altitude change.
static func oval(center: Vector3, rx: float, rz: float, y: float, wave: float, phase: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in SAMPLES:
		var a := TAU * i / float(SAMPLES)
		out.append(Vector3(center.x + cos(a) * rx, y + sin(a * 3.0 + phase) * wave, center.z + sin(a) * rz))
	return out


## Fallback skyline traffic lanes: `count` ovals at different radii and heights
## between the skyline towers, all outside the playable box and above CLEAR_Y.
static func fallback_traffic(count: int) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	var c := Vector3(0.0, 0.0, -210.0)
	for i in count:
		var k := i / maxf(1.0, count - 1.0)
		out.append(oval(c, lerpf(185.0, 330.0, k), lerpf(330.0, 470.0, k), lerpf(48.0, 120.0, fmod(k * 2.7, 1.0)), 6.0, i * 1.3))
	return out


## Fallback drone weave routes: long thin loops along the outside of the north
## and south lanes (|x| 112..150), weaving between building gaps, never over
## the playable box.
static func fallback_drones(count: int) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	for i in count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x0 := side * (122.0 + 8.0 * (i % 3))
		var pts := PackedVector3Array()
		for s in SAMPLES:
			var a := TAU * s / float(SAMPLES)
			var z := -210.0 + sin(a) * 180.0
			var x := x0 + side * (cos(a) * 9.0 + sin(a * 5.0 + i) * 4.0)
			pts.append(Vector3(x, 34.0 + 6.0 * sin(a * 2.0 + i) + i * 1.5, z))
		out.append(pts)
	return out


## Fallback sky-train track: an elevated line in the gap between the north lane
## and the skyline (x -125..-140, 62 m up, outside the playable box), running
## past both HQ ends.
static func fallback_train() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for s in SAMPLES:
		var k := s / float(SAMPLES - 1)
		pts.append(Vector3(-125.0 - 15.0 * sin(k * PI), 62.0, lerpf(260.0, -680.0, k)))
	return pts


## Far bird loops (well outside the skyline).
static func fallback_birds() -> Array[PackedVector3Array]:
	return [oval(Vector3(-260.0, 0.0, -150.0), 60.0, 40.0, 95.0, 4.0, 0.0),
		oval(Vector3(280.0, 0.0, -300.0), 50.0, 70.0, 85.0, 3.0, 1.0)]


## True when no point of `pts` lies inside the playable box below CLEAR_Y.
static func clear_of_play(pts: PackedVector3Array) -> bool:
	for p in pts:
		if p.y < CLEAR_Y and p.x > PLAY_MIN.x and p.x < PLAY_MAX.x and p.z > PLAY_MIN.y and p.z < PLAY_MAX.y:
			return false
	return true


## Never over the playable box at any height (drones: "near, never over").
static func never_over_play(pts: PackedVector3Array) -> bool:
	for p in pts:
		if p.x > PLAY_MIN.x and p.x < PLAY_MAX.x and p.z > PLAY_MIN.y and p.z < PLAY_MAX.y:
			return false
	return true


## Bakes routes into an RGBAF texture: one row per route, SAMPLES texels wide.
static func bake(routes: Array[PackedVector3Array]) -> ImageTexture:
	var img := Image.create(SAMPLES, maxi(1, routes.size()), false, Image.FORMAT_RGBAF)
	for r in routes.size():
		for s in SAMPLES:
			var p := routes[r][s] if s < routes[r].size() else routes[r][-1]
			img.set_pixel(s, r, Color(p.x, p.y, p.z, 1.0))
	return ImageTexture.create_from_image(img)
