class_name HudScrims
extends HudWidget
## v0.12 readability scrims (design/ux/hud-v0.12.md §1 "No boxes"): a soft ink
## band at the top (225 design px, 62% fading to 0) and at the bottom (285
## design px, 0 to 66%) of the HUD canvas, under every widget. HudRoot toggles
## `top` / `bottom` per context (hud.md §14).

const TOP_H: float = 225.0
const BOTTOM_H: float = 285.0
const TOP_A: float = 0.62
const BOTTOM_A: float = 0.66

var top: bool = true
var bottom: bool = true


func _process(_delta: float) -> void:
	pass  # static: redrawn only when a flag or the size changes


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func set_flags(t: bool, b: bool) -> void:
	if t != top or b != bottom:
		top = t
		bottom = b
		queue_redraw()


func _draw() -> void:
	if top:
		scrim(Rect2(0.0, 0.0, size.x, TOP_H), TOP_A, 0.0)
	if bottom:
		scrim(Rect2(0.0, size.y - BOTTOM_H, size.x, BOTTOM_H), 0.0, BOTTOM_A)
