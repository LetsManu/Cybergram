class_name SkillIcons
extends RefCounted
## v0.12 ability line icons (design/ux/hud-v0.12.md §2 "Ability bar": 45 px,
## 1.6 stroke, ivory; they replace the THRD / RLLY text). One icon per skill,
## keyed by SkillDef.short_label, authored in a 30×30 box as a tiny path
## language parsed once:
##   "M x y L x y …" polyline · "C cx cy r" circle · "A cx cy r a0 a1" arc (deg,
##   0 = +x, y down), separated by "|".
## Drawing uses draw_set_transform, so it allocates nothing per frame. Unknown
## labels return false and the caller falls back to the label text.

const BOX: float = 30.0
const STROKE: float = 1.6

const PATHS := {
	"THRD": "M5 25 L8 18 L11 13 L14 12 L17 15 L19 19 L22 15 L25 5|C25 5 2.2|C5 25 2.2",
	"RLLY": "M15 4 L15 18|M9 18 L21 18 L19 26 L11 26 L9 18|A15 13 9 215 325|A15 13 13 220 320",
	"STEP": "M5 10 L23 10|M19 6 L23 10 L19 14|M25 20 L7 20|M11 16 L7 20 L11 24",
	"RWRT": "M15 3 L25 9 L25 21 L15 27 L5 21 L5 9 L15 3|M11 15 L19 15|M15 11 L15 19",
	"OVRD": "M17 3 L8 17 L15 17 L12 27 L22 12 L15 12 L17 3",
	"WALL": "M4 8 L26 8 L26 24 L4 24 L4 8|M4 16 L26 16|M12 8 L12 16|M19 16 L19 24",
	"QUAKE": "M3 23 L27 23|M15 5 L12 12 L17 16 L13 23|M6 16 L9 12|M24 16 L21 12",
	"WARD": "M15 3 L25 15 L15 27 L5 15 L15 3|M5 15 L25 15|M15 3 L15 27",
	"FRAG": "C15 18 8|M12 10 L18 10|M15 10 L15 6 L20 6|M20 6 L24 3",
	"SBTG": "M7 11 L23 11 L23 25 L7 25 L7 11|M11 11 L11 6 L19 6 L19 11|M12 18 L18 18",
	"DRON": "C15 16 4|M6 10 L12 14|M24 10 L18 14|C6 8 3|C24 8 3|M15 20 L15 26|M12 26 L18 26",
	"ECLP": "A15 15 11 50 310|A20 15 8 110 250",
	"SPIK": "M15 3 L20 22 L10 22 L15 3|M5 26 L25 26",
	"FORT": "M15 3 L25 7 L25 15 L15 27 L5 15 L5 7 L15 3|M15 9 L15 21|M10 14 L20 14",
	"STIM": "M6 24 L18 12|M14 8 L22 16|M20 10 L25 5|M23 3 L27 7|M9 17 L13 21",
	"BLOM": "C15 15 3|M15 4 L15 9|M15 21 L15 26|M4 15 L9 15|M21 15 L26 15|M7 7 L11 11|M23 23 L19 19|M23 7 L19 11|M7 23 L11 19",
	"SNAR": "A15 15 11 0 300|A15 15 7 60 360|C15 15 2.5",
	"HOP": "M5 26 L5 21|M25 26 L25 21|A15 21 10 180 345|M21 9 L25 12 L27 7",
	"VEIL": "A15 23 13 225 315|A15 7 13 45 135|C15 15 3|M5 25 L25 5",
	"SLID": "M4 25 L26 25|M6 19 L14 19 L20 11|C22 7 3|M4 14 L11 14|M4 10 L9 10",
	"MINE": "A15 21 9 180 360|M6 21 L24 21|M15 12 L15 7|M10 7 L20 7",
	"BOX": "M5 5 L25 5 L25 25 L5 25 L5 5|M15 9 L15 21|M9 15 L21 15|C15 15 4",
	"PHSE": "C11 15 7|C19 15 7",
	"WIRE": "M4 8 L26 22|M4 22 L26 8|M4 15 L26 15|C4 15 2|C26 15 2",
	"AURA": "A15 23 12 200 340|A15 23 8 200 340|A15 23 4 200 340",
	"ZERO": "C15 15 10|M9 21 L21 9|M12 4 L18 4",
	"RAM": "M4 15 L18 15|M14 9 L22 15 L14 21|M4 9 L10 9|M4 21 L10 21|M24 7 L24 23",
	"FLD": "C15 15 11|M8 16 L12 11 L15 18 L18 11 L22 16",
	"MED": "M12 4 L18 4 L18 12 L26 12 L26 18 L18 18 L18 26 L12 26 L12 18 L4 18 L4 12 L12 12 L12 4",
}

## label -> Array of PackedVector2Array (polylines, 30-box coords).
static var _cache: Dictionary = {}


static func has(label: String) -> bool:
	return PATHS.has(label)


## Draws icon `label` centred at `c`, `size` px wide, in `col`. False if unknown.
static func draw(ci: CanvasItem, label: String, c: Vector2, size: float, col: Color) -> bool:
	if not PATHS.has(label):
		return false
	var lines: Array = _cache.get(label, [])
	if lines.is_empty():
		lines = parse(PATHS[label])
		_cache[label] = lines
	var k := size / BOX
	ci.draw_set_transform(c - Vector2(BOX, BOX) * 0.5 * k, 0.0, Vector2(k, k))
	for pl: PackedVector2Array in lines:
		ci.draw_polyline(pl, col, STROKE, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## Parses the path language into polylines (circles / arcs as 20-24 segments).
static func parse(src: String) -> Array:
	var out: Array = []
	for part in src.split("|"):
		var t := part.strip_edges().split(" ", false)
		if t.is_empty():
			continue
		match t[0].substr(0, 1):
			"C":
				out.append(_arc(Vector2(t[0].substr(1).to_float(), t[1].to_float()), t[2].to_float(), 0.0, 360.0))
			"A":
				out.append(_arc(Vector2(t[0].substr(1).to_float(), t[1].to_float()), t[2].to_float(),
					t[3].to_float(), t[4].to_float()))
			_:
				var pl := PackedVector2Array()
				var i := 0
				while i < t.size():
					var a := t[i]
					if a.begins_with("M") or a.begins_with("L"):
						a = a.substr(1)
					if i + 1 < t.size():
						pl.append(Vector2(a.to_float(), t[i + 1].to_float()))
					i += 2
				out.append(pl)
	return out


static func _arc(c: Vector2, r: float, a0: float, a1: float) -> PackedVector2Array:
	var n := maxi(6, ceili(absf(a1 - a0) / 15.0))
	var pl := PackedVector2Array()
	for k in n + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(k) / n))
		pl.append(c + Vector2(cos(a), sin(a)) * r)
	return pl
