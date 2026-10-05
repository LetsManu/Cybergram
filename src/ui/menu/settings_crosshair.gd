class_name SettingsCrosshair
extends RefCounted
## Crosshair drawing shared by the HUD (CenterFeedback) and the settings
## preview, so both always look the same.


## Draws the crosshair `style` (GameSettings.Crosshair) in `color` at `c`.
## `spread_px` >= 0 opens the gap / circle to the real spread cone (dynamic
## crosshair, radius in the canvas item's units); -1 = the static look.
static func draw(ci: CanvasItem, c: Vector2, style: int, color: Color, spread_px: float = -1.0) -> void:
	var gap := 6.0 if spread_px < 0.0 else maxf(spread_px, 2.0)
	var ring := 10.0 if spread_px < 0.0 else maxf(spread_px, 4.0)
	var col := Color(color, 0.95)
	var dark := Color(0, 0, 0, 0.7)
	if style == GameSettings.Crosshair.CROSS_DOT or style == GameSettings.Crosshair.CROSS:
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			ci.draw_line(c + d * gap, c + d * (gap + 8.0), dark, 4.0)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			ci.draw_line(c + d * gap, c + d * (gap + 8.0), col, 2.0)
	if style == GameSettings.Crosshair.CIRCLE:
		ci.draw_arc(c, ring, 0.0, TAU, 32, dark, 4.0, true)
		ci.draw_arc(c, ring, 0.0, TAU, 32, col, 2.0, true)
	if style != GameSettings.Crosshair.CROSS:
		var r := 2.8 if style == GameSettings.Crosshair.DOT else 2.2
		ci.draw_circle(c, r, dark)
		ci.draw_circle(c, r - 0.8, col)
