class_name HeroBadge
extends Control
## Code-drawn hero badge (stand-in portrait until hero art exists): a hexagon
## in the hero's signature colour, a secondary-colour rim and the hero's
## initials. `hero_index` is the ContentDB HERO index (0 = no pick: "?").
##
## Example:
##   var b := HeroBadge.make(HeroCatalog.find_stem("brannoc").index, 36.0)

var hero_index: int = 0:
	set(v):
		hero_index = v
		queue_redraw()
var dim: bool = false:
	set(v):
		dim = v
		queue_redraw()


static func make(hero_index_: int, size_px: float) -> HeroBadge:
	var b := HeroBadge.new()
	b.hero_index = hero_index_
	b.custom_minimum_size = Vector2(size_px, size_px)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _draw() -> void:
	var h := HeroCatalog.find_index(hero_index)
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var fill: Color = h.get("color", Color(0.16, 0.17, 0.22))
	var rim: Color = h.get("color2", HudPalette.TEXT_OFF)
	if dim:
		fill = fill.darkened(0.5)
		rim = rim.darkened(0.5)
	var hex := PackedVector2Array()
	for i in 6:
		var a := i * TAU / 6.0
		hex.append(c + Vector2(cos(a), sin(a)) * s * 0.48)
	draw_colored_polygon(hex, fill)
	hex.append(hex[0])
	draw_polyline(hex, rim, maxf(1.5, s * 0.06), true)
	var text: String = h.get("initials", "?")
	var font := get_theme_default_font()
	var fs := int(s * 0.36)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ink := Color.BLACK if fill.get_luminance() > 0.55 else HudPalette.TEXT
	draw_string_outline(font, Vector2(c.x - tw * 0.5, c.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		fs, 3, Color(0, 0, 0, 0.5) if ink != Color.BLACK else Color(1, 1, 1, 0.35))
	draw_string(font, Vector2(c.x - tw * 0.5, c.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
