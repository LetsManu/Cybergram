class_name HeroBadge
extends UiPortrait
## A hero's circular portrait crop (v0.9: real portraits instead of the old
## initials hexagon). `hero_index` is the ContentDB HERO index (0 = no pick:
## an empty well).
##
## Example:
##   var b := HeroBadge.make(HeroCatalog.find_stem("brannoc").index, 36.0)

var hero_index: int = 0:
	set(v):
		hero_index = v
		var h := HeroCatalog.find_index(v)
		texture = UiKit.portrait_texture(String(h.stem)) if not h.is_empty() else null


static func make(hero_index_: int, size_px: float, ring_ := Color(0, 0, 0, 0)) -> HeroBadge:
	var b := HeroBadge.new()
	b.hero_index = hero_index_
	b.ring = ring_
	b.custom_minimum_size = Vector2(size_px, size_px)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b
