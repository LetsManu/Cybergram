class_name SettingsCrosshairPreview
extends Control
## Small dark swatch that shows the chosen crosshair.

var style: int = 0
var color: Color = Color.WHITE


func _init() -> void:
	custom_minimum_size = Vector2(64, 64)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.12, 0.9))
	draw_rect(Rect2(Vector2.ZERO, size), HudPalette.KEYLINE, false, 1.0)
	SettingsCrosshair.draw(self, size * 0.5, style, color)
