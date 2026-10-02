class_name CenterFeedback
extends HudWidget
## Centre 40% box (design/ux/hud.md §4.1, §13.1, §7): crosshair (dot + lines
## with a dark outline), hit markers (body white X, headshot larger yellow X
## with a top notch, hero kill = X expanding into a diamond burst, Wardling /
## structure = small dim dot) and the squad radial wheel while Z is held.
## Anchored to the zone's centre, which is the screen centre.

const WHEEL_R: float = 110.0
const WHEEL_KEYS: Array[String] = ["HUD_CMD_FOLLOW", "HUD_CMD_HOLD", "HUD_CMD_ATTACK", "HUD_CMD_CAPTURE"]

var _marker_left: float = 0.0
var _marker_total: float = 0.1
var _marker_kind: int = 0  # 0 body, 1 head, 2 kill, 3 minor (Wardling / structure)


## Shows a hit marker for a confirmed hit (`hero` = target is a hero).
func on_hit(e: GameEvent, hero: bool) -> void:
	var kill := (e.flags & GameEvent.FLAG_KILL) != 0
	if not hero:
		_marker_kind = 3
	elif kill:
		_marker_kind = 2
	elif (e.flags & GameEvent.FLAG_HEADSHOT) != 0:
		_marker_kind = 1
	else:
		_marker_kind = 0
	_marker_total = ctx.tuning.kill_marker_seconds if _marker_kind == 2 else ctx.tuning.hit_marker_seconds
	_marker_left = _marker_total


func _process(delta: float) -> void:
	_marker_left = maxf(0.0, _marker_left - delta)
	super(delta)


func _draw() -> void:
	var c := size * 0.5
	_crosshair(c)
	if _marker_left > 0.0:
		_marker(c, 1.0 - _marker_left / _marker_total)
	var input := ctx.client.player_input if ctx.client != null else null
	if input != null and input.wheel_open:
		_wheel(c, input)


func _crosshair(c: Vector2) -> void:
	var col := Color(1, 1, 1, 0.95)
	var dark := Color(0, 0, 0, 0.7)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		draw_line(c + d * 6.0, c + d * 14.0, dark, 4.0)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		draw_line(c + d * 6.0, c + d * 14.0, col, 2.0)
	draw_circle(c, 2.2, dark)
	draw_circle(c, 1.4, col)


func _marker(c: Vector2, t: float) -> void:
	var a := 1.0 - t * 0.6
	match _marker_kind:
		3:
			draw_circle(c + Vector2(0.0, 22.0), 3.0, Color(1, 1, 1, 0.55 * a))
		2:
			var s := 10.0 + 14.0 * t
			diamond(c, s, Color(1.0, 0.3, 0.25, a), false)
			_x(c, 7.0, 16.0, Color(1.0, 0.3, 0.25, a), 3.0)
		1:
			_x(c, 8.0, 19.0, Color(HudPalette.CRIT, a), 3.5)
			draw_line(c + Vector2(0.0, -20.0), c + Vector2(0.0, -26.0), Color(HudPalette.CRIT, a), 3.0)
		_:
			_x(c, 7.0, 15.0, Color(1, 1, 1, a), 2.5)


func _x(c: Vector2, inner: float, outer: float, col: Color, w: float) -> void:
	for s in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		draw_line(c + s * inner * 0.7071, c + s * outer * 0.7071, Color(0, 0, 0, col.a * 0.6), w + 2.0, true)
		draw_line(c + s * inner * 0.7071, c + s * outer * 0.7071, col, w, true)


## Four 90° slices: Follow top, Hold right, Attack bottom, Capture left (§7).
func _wheel(c: Vector2, input: PlayerInputSource) -> void:
	var sel := input.wheel_selection()
	draw_circle(c, WHEEL_R, Color(HudPalette.PANEL, 0.4))
	draw_arc(c, WHEEL_R, 0.0, TAU, 48, HudPalette.KEYLINE, 1.5, true)
	for i in 4:
		var a := -PI / 2.0 + i * PI / 2.0
		var lit := sel == PlayerInputSource.WHEEL_SLICES[i]
		var pos := c + Vector2(cos(a), sin(a)) * WHEEL_R * 0.64
		text_c(tr(WHEEL_KEYS[i]), pos, 16, HudPalette.LUMEN if lit else HudPalette.TEXT, ctx.font_display)
