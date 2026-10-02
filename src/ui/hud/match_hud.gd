class_name MatchHud
extends CanvasLayer
## Match header and end banner (E9 / E12, design/ux/hud.md §4.8, §8 End):
## own Uplink bar on the left, enemy on the right (Integrity %, a darker "lost"
## region so the bar never seems to heal, EXPOSED marker with a pulsing border),
## the match clock + phase + next-phase countdown at top centre above the
## objective strip, and a VICTORY / DEFEAT / DRAW banner with the reason at End.
## Reads ClientWorld's replicated match state only.

const TOP: float = 8.0
const BAR: Vector2 = Vector2(260.0, 12.0)
const CENTER_W: float = 230.0
const LOST_COLOR := Color(0.32, 0.08, 0.08)
const EXPOSED_COLOR := Color(1.0, 0.25, 0.2)
const TEAM_NAMES := ["CONCORD", "SYNDICATE"]

## Set by AppRoot (the GameSession node).
var session: Node
var _client: ClientWorld
var _canvas: Control
var _font: Font
var _t: float = 0.0


func _ready() -> void:
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw)
	add_child(_canvas)
	_font = ThemeDB.fallback_font
	_client = session.get("client") as ClientWorld if session != null else null


func _process(delta: float) -> void:
	_t += delta
	_canvas.queue_redraw()


func _draw() -> void:
	if _client == null or _client.match_state == null:
		return
	var m := _client.match_state
	var team := _client.own_team()
	var cx := _canvas.size.x / 2.0
	_canvas.draw_rect(Rect2(cx - CENTER_W / 2.0 - BAR.x - 30.0, TOP - 4.0, CENTER_W + 2.0 * BAR.x + 60.0, 50.0),
		Color(0, 0, 0, 0.45))
	_draw_uplink(_client.uplink_state(team), team, cx - CENTER_W / 2.0 - BAR.x - 14.0, false)
	_draw_uplink(_client.uplink_state(1 - team), 1 - team, cx + CENTER_W / 2.0 + 14.0, true)
	var clock := MatchRules.format_clock(m.time_s)
	_canvas.draw_string(_font, Vector2(cx - CENTER_W / 2.0, TOP + 24.0), clock, HORIZONTAL_ALIGNMENT_CENTER,
		CENTER_W, 28, Color.WHITE)
	var phase_name: String = MatchRules.PHASE_NAMES[m.phase] if m.phase < MatchRules.PHASE_NAMES.size() else "?"
	_canvas.draw_string(_font, Vector2(cx - CENTER_W / 2.0, TOP + 42.0), "%s   %s" % [phase_name, _next_text(m)],
		HORIZONTAL_ALIGNMENT_CENTER, CENTER_W, 13, Color(0.85, 0.85, 0.95))
	if m.phase == MatchRules.Phase.END:
		_draw_banner(m, team)


func _next_text(m: SnapshotData.MatchState) -> String:
	if m.next_phase_s < 0.0 or m.phase == MatchRules.Phase.END:
		return ""
	var left := MatchRules.format_clock(ceilf(m.next_phase_s - m.time_s))
	match m.phase:
		MatchRules.Phase.DEPLOY:
			return "Mids unlock in %s" % left
		MatchRules.Phase.SKIRMISH:
			return "next %s" % left
	return "next %s" % left


func _draw_uplink(u: SnapshotData.UplinkState, team: int, x: float, right: bool) -> void:
	if u == null:
		return
	var frac := clampf(u.integrity / maxf(u.max_integrity, 1.0), 0.0, 1.0)
	var col := HardpointView.team_color(team)
	var title := "%s UPLINK  %d%%" % [TEAM_NAMES[team], ceili(frac * 100.0)]
	_canvas.draw_string(_font, Vector2(x, TOP + 14.0), title,
		HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT, BAR.x, 14, Color.WHITE)
	var r := Rect2(x, TOP + 22.0, BAR.x, BAR.y)
	_canvas.draw_rect(r, LOST_COLOR)
	# The own bar is anchored at its outer (left) edge, the enemy bar mirrors it.
	var w := BAR.x * frac
	var fill := Rect2(x + BAR.x - w if right else x, r.position.y, w, BAR.y)
	_canvas.draw_rect(fill, col)
	if u.exposed:
		var k := 0.5 + 0.5 * sin(_t * TAU * 1.5)
		var ec := Color(EXPOSED_COLOR, 0.55 + 0.45 * k)
		_canvas.draw_rect(r.grow(2.0), ec, false, 2.0)
		for i in range(0, int(BAR.x), 12):  # hatching
			var a := Vector2(x + i, r.end.y)
			_canvas.draw_line(a, a + Vector2(8.0, -BAR.y), Color(0, 0, 0, 0.35), 2.0)
		_canvas.draw_string(_font, Vector2(x, r.end.y + 13.0), "EXPOSED",
			HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT, BAR.x, 13, ec)
	elif u.integrity <= 0.0:
		_canvas.draw_string(_font, Vector2(x, r.end.y + 13.0), "DESTROYED",
			HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT, BAR.x, 13, Color(0.7, 0.7, 0.7))
	else:
		_canvas.draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)


func _draw_banner(m: SnapshotData.MatchState, team: int) -> void:
	var title := "DRAW"
	var col := Color(0.9, 0.9, 0.95)
	if m.winner == team:
		title = "VICTORY"
		col = HardpointView.team_color(team).lightened(0.25)
	elif m.winner == 1 - team:
		title = "DEFEAT"
		col = HardpointView.team_color(1 - team).lightened(0.15)
	var reason := ""
	match m.end_reason:
		MatchRules.EndReason.UPLINK_DESTROYED:
			reason = "%s Uplink destroyed" % TEAM_NAMES[1 - m.winner].capitalize()
		MatchRules.EndReason.INCURSION:
			reason = "Time-out: %s won on Incursion" % TEAM_NAMES[m.winner].capitalize()
		MatchRules.EndReason.UPLINK_DAMAGE:
			reason = "Time-out: Incursion tied, %s dealt more Uplink damage" % TEAM_NAMES[m.winner].capitalize()
		MatchRules.EndReason.DRAW:
			reason = "Time-out: Incursion and Uplink damage tied"
	var s := _canvas.size
	var y := s.y * 0.25
	_canvas.draw_rect(Rect2(0.0, y - 70.0, s.x, 120.0), Color(0, 0, 0, 0.6))
	_canvas.draw_string_outline(_font, Vector2(0.0, y), title, HORIZONTAL_ALIGNMENT_CENTER, s.x, 72, 10, Color.BLACK)
	_canvas.draw_string(_font, Vector2(0.0, y), title, HORIZONTAL_ALIGNMENT_CENTER, s.x, 72, col)
	_canvas.draw_string(_font, Vector2(0.0, y + 36.0), reason, HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, Color.WHITE)
