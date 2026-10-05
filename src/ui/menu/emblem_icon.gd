class_name EmblemIcon
extends UiPortrait
## A player avatar (design/ux/lobby-and-social.md §2.1, v0.9 look): emblem
## `n` shows hero portrait n (HeroCatalog order, wrapping), inside a thin ring
## of the player's accent colour, so the colour is never the only cue.
##
## Example:
##   var e := EmblemIcon.make(3, 1, 40.0)
##   add_child(e)

var emblem: int = 0:
	set(v):
		emblem = v
		texture = EmblemIcon.portrait_of(v)
		var heroes := HeroCatalog.entries()
		face = UiKit.portrait_face(String(heroes[posmod(v, heroes.size())].stem)) if not heroes.is_empty() \
			else UiPortrait.FACE
var accent: int = 0:
	set(v):
		accent = v
		ring = PlayerProfile.accent_of(v)


static func make(emblem_: int, accent_: int, size_px: float) -> EmblemIcon:
	var e := EmblemIcon.new()
	e.ring_width = 1.5
	e.emblem = emblem_
	e.accent = accent_
	e.custom_minimum_size = Vector2(size_px, size_px)
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return e


## The portrait shown for emblem `n` (null when no hero has one).
static func portrait_of(n: int) -> Texture2D:
	var heroes := HeroCatalog.entries()
	if heroes.is_empty():
		return null
	return UiKit.portrait_texture(String(heroes[posmod(n, heroes.size())].stem))
