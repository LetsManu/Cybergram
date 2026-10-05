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
## Eased on-screen cone radius (HUD units) of the dynamic crosshair.
var _shown_spread: float = -1.0
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
	if ctx.armory_prompt:
		caps_c(tr("HUD_ARMORY_PROMPT"), c + Vector2(0.0, 110.0), 20, HudPalette.BRASS_HI, 0.16)
	var input := ctx.client.player_input if ctx.client != null else null
	if input != null and input.wheel_open:
		_wheel(c, input)


func _crosshair(c: Vector2) -> void:
	var gs := GameSettings.shared()
	var sp := _spread_px(gs) if gs.crosshair_dynamic else -1.0
	SettingsCrosshair.draw(self, c + _recoil_offset(), gs.crosshair_style, GameSettings.CROSSHAIR_COLORS[gs.crosshair_color], sp)


## W16-COMFORT dynamic crosshair: screen radius of the real spread cone in HUD
## units, eased (instantly with Reduce motion). The cone is centred on the
## crosshair, which already carries the fair-recoil shift.
func _spread_px(gs: GameSettings) -> float:
	var client: Variant = ctx.client
	if client == null or client.rig == null or client.rig.camera == null:
		return -1.0
	var vp := get_viewport().get_visible_rect().size
	var px := SpreadModel.screen_radius_px(client.spread.spread_deg, client.rig.camera.fov, vp.y)
	var target: float = px / get_global_transform_with_canvas().get_scale().y
	if _shown_spread < 0.0 or gs.reduce_motion:
		_shown_spread = target
	else:
		_shown_spread = lerpf(_shown_spread, target, 1.0 - exp(-get_process_delta_time() * 30.0))
	return _shown_spread


## W16-COMFORT: the part of the recoil kick the camera does not show (camera
## recoil < 100%) moves the crosshair to where the shot will land. HUD units.
func _recoil_offset() -> Vector2:
	var client: Variant = ctx.client
	if client == null or client.player_input == null or client.rig == null or client.rig.camera == null:
		return Vector2.ZERO
	var kick: Vector2 = client.player_input.hidden_kick()
	if kick == Vector2.ZERO:
		return Vector2.ZERO
	var px := ComfortMath.kick_to_screen_px(kick, client.rig.camera.fov, get_viewport().get_visible_rect().size)
	return px / get_global_transform_with_canvas().get_scale()


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
	draw_circle(c, WHEEL_R, Color(HudPalette.INK, 0.45))
	draw_arc(c, WHEEL_R, 0.0, TAU, 48, Color(HudPalette.BRASS, 0.55), 1.0, true)
	for i in 4:
		var a := -PI / 2.0 + i * PI / 2.0
		var lit := sel == PlayerInputSource.WHEEL_SLICES[i]
		var pos := c + Vector2(cos(a), sin(a)) * WHEEL_R * 0.64
		caps_c(tr(WHEEL_KEYS[i]), pos, 16, HudPalette.BRASS_HI if lit else HudPalette.IVORY, 0.18)
