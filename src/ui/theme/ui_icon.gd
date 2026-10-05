class_name UiIcon
extends Control
## Small vector glyphs drawn in code (no icon font needed): gear, close,
## minus, chevrons, friends, play, check. Used by UiKit.icon_button() for
## the top bar quick buttons, sidebar toggles and showcase arrows.
##
## Example:
##   add_child(UiIcon.make(&"gear", 18.0, UiKit.tokens().text_dim))

const KINDS: Array[StringName] = [&"gear", &"close", &"minus", &"left", &"right", &"up", &"down",
	&"friends", &"play", &"check", &"ring", &"target", &"diamond", &"add_friend", &"search"]

@export var kind: StringName = &"gear":
	set(v):
		kind = v
		queue_redraw()
@export var color := Color.WHITE:
	set(v):
		color = v
		queue_redraw()


static func make(kind_: StringName, size_px: float, color_: Color) -> UiIcon:
	var i := UiIcon.new()
	i.kind = kind_
	i.color = color_
	i.custom_minimum_size = Vector2(size_px, size_px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.5
	var w := maxf(1.3, s / 15.0)  # the mockup's 1.6 px stroke on a 24 px glyph
	match kind:
		&"gear":
			draw_arc(c, r * 0.27, 0.0, TAU, 24, color, w, true)
			for k in 8:
				var d := Vector2.from_angle(TAU * k / 8.0)
				draw_line(c + d * r * 0.62, c + d * r * 0.95, color, w, true)
		&"diamond":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r),
				c + Vector2(-r, 0)]), color)
		&"add_friend":
			draw_arc(c + Vector2(-r * 0.17, -r * 0.33), r * 0.29, 0.0, TAU, 20, color, w, true)
			draw_arc(c + Vector2(-r * 0.17, r * 0.75), r * 0.55, PI * 1.12, PI * 1.88, 16, color, w, true)
			draw_line(c + Vector2(r * 0.58, -r * 0.33), c + Vector2(r * 0.58, r * 0.17), color, w, true)
			draw_line(c + Vector2(r * 0.33, -r * 0.08), c + Vector2(r * 0.83, -r * 0.08), color, w, true)
		&"search":
			draw_arc(c + Vector2(-r * 0.08, -r * 0.08), r * 0.5, 0.0, TAU, 24, color, w, true)
			draw_line(c + Vector2(r * 0.3, r * 0.3), c + Vector2(r * 0.67, r * 0.67), color, w, true)
		&"close":
			draw_line(c + Vector2(-r, -r) * 0.6, c + Vector2(r, r) * 0.6, color, w, true)
			draw_line(c + Vector2(r, -r) * 0.6, c + Vector2(-r, r) * 0.6, color, w, true)
		&"minus":
			draw_line(c + Vector2(-r * 0.6, 0), c + Vector2(r * 0.6, 0), color, w, true)
		&"left", &"right", &"up", &"down":
			var dir := {&"left": Vector2.LEFT, &"right": Vector2.RIGHT, &"up": Vector2.UP, &"down": Vector2.DOWN}[kind] as Vector2
			var tip := c + dir * r * 0.35
			var back := c - dir * r * 0.25
			var side := Vector2(-dir.y, dir.x) * r * 0.55
			draw_polyline(PackedVector2Array([back + side, tip, back - side]), color, w * 1.2, true)
		&"friends":
			draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.26, color)
			draw_arc(c + Vector2(-r * 0.25, r * 0.55), r * 0.5, PI, TAU, 16, color, w * 1.3, true)
			draw_circle(c + Vector2(r * 0.4, -r * 0.2), r * 0.2, Color(color, 0.7))
			draw_arc(c + Vector2(r * 0.4, r * 0.55), r * 0.38, PI, TAU, 12, Color(color, 0.7), w, true)
		&"play":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.4, -r * 0.6), c + Vector2(r * 0.6, 0),
				c + Vector2(-r * 0.4, r * 0.6)]), color)
		&"target":
			draw_arc(c, r * 0.8, 0.0, TAU, 32, color, w, true)
			draw_arc(c, r * 0.4, 0.0, TAU, 24, color, w, true)
			draw_circle(c, r * 0.1, color)
		&"ring":
			draw_arc(c, r - w, 0.0, TAU, 40, color, w * 1.2, true)
		&"check":
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.6, 0), c + Vector2(-r * 0.15, r * 0.45),
				c + Vector2(r * 0.6, -r * 0.45)]), color, w * 1.2, true)
