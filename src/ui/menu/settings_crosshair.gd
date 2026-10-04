class_name SettingsCrosshair
extends RefCounted
## Crosshair drawing shared by the HUD (CenterFeedback) and the settings
## preview, so both always look the same.


## Draws the crosshair `style` (GameSettings.Crosshair) in `color` at `c`.
static func draw(ci: CanvasItem, c: Vector2, style: int, color: Color) -> void:
	var col := Color(color, 0.95)
	var dark := Color(0, 0, 0, 0.7)
	if style == GameSettings.Crosshair.CROSS_DOT or style == GameSettings.Crosshair.CROSS:
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			ci.draw_line(c + d * 6.0, c + d * 14.0, dark, 4.0)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			ci.draw_line(c + d * 6.0, c + d * 14.0, col, 2.0)
	if style == GameSettings.Crosshair.CIRCLE:
		ci.draw_arc(c, 10.0, 0.0, TAU, 32, dark, 4.0, true)
		ci.draw_arc(c, 10.0, 0.0, TAU, 32, col, 2.0, true)
	if style != GameSettings.Crosshair.CROSS:
		var r := 2.8 if style == GameSettings.Crosshair.DOT else 2.2
		ci.draw_circle(c, r, dark)
		ci.draw_circle(c, r - 0.8, col)
