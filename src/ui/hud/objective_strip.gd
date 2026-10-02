class_name ObjectiveStrip
extends CanvasLayer
## Minimal HUD objective strip (E7 / E12.4, design/ux/hud.md lane front strip):
## the lane's hardpoints as owner-coloured pips in lane order (own HQ on the
## left), a front marker under the own team's front hardpoint, and the capture
## progress of the hardpoint the player stands in. Reads ClientWorld only.

const PIP: Vector2 = Vector2(46.0, 22.0)
const GAP: float = 10.0
## Below the E9 match header (Uplinks, clock, phase).
const TOP: float = 66.0
const BAR_W: float = 320.0
const LOCKED_COLOR := Color(0.25, 0.25, 0.3)

## Set by AppRoot (the GameSession node).
var session: Node
var _client: ClientWorld
var _canvas: Control
var _font: Font


func _ready() -> void:
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw)
	add_child(_canvas)
	_font = ThemeDB.fallback_font
	_client = session.get("client") as ClientWorld if session != null else null


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


func _draw() -> void:
	if _client == null or _client.hardpoints.is_empty():
		return
	var defs := _client.hardpoint_defs()
	var states := _client.hardpoints
	var team := _client.own_team()
	var n := states.size()
	var total := n * PIP.x + (n - 1) * GAP
	var x0 := (_canvas.size.x - total) / 2.0
	var front := _client.fronts[team] if _client.fronts.size() > team else -1
	_canvas.draw_rect(Rect2(x0 - 10.0, TOP - 8.0, total + 20.0, PIP.y + 30.0), Color(0, 0, 0, 0.45))
	for k in n:
		# Own HQ on the left: Syndicate reads the lane reversed.
		var i := k if team == MapDef.TEAM_CONCORD else n - 1 - k
		var st := states[i]
		var r := Rect2(x0 + k * (PIP.x + GAP), TOP, PIP.x, PIP.y)
		_canvas.draw_rect(r, HardpointView.team_color(st.owner))
		if st.progress > 0.0:
			var pr := Rect2(r.position + Vector2(0.0, PIP.y - 5.0), Vector2(PIP.x * st.progress, 5.0))
			_canvas.draw_rect(pr, HardpointView.team_color(st.capturing_team).lightened(0.3))
		if st.locked[team]:
			_canvas.draw_rect(r, LOCKED_COLOR, false, 2.0)
		if st.contested:
			_canvas.draw_rect(r.grow(2.0), Color.WHITE, false, 2.0)
		var tag := defs[i].id.trim_prefix("s_").to_upper() if i < defs.size() else str(i)
		_canvas.draw_string(_font, r.position + Vector2(0.0, PIP.y - 6.0), tag, HORIZONTAL_ALIGNMENT_CENTER,
			PIP.x, 13, Color(0, 0, 0, 0.85))
		if i == front:
			var c := Vector2(r.get_center().x, TOP + PIP.y + 4.0)
			_canvas.draw_colored_polygon(PackedVector2Array([c, c + Vector2(-7, 10), c + Vector2(7, 10)]), Color.WHITE)
	var here := _client.own_hardpoint_index()
	if here < 0 or here >= states.size():
		return
	var st := states[here]
	var title := defs[here].display_name.to_upper()
	var state := ""
	if st.locked[team]:
		state = "LOCKED"
	elif st.contested:
		state = "CONTESTED"
	elif st.overtime:
		state = "OVERTIME"
	elif st.progress > 0.0:
		state = ("CAPTURING" if st.capturing_team == team else "ENEMY CAPTURING") + " %d%%" % floori(st.progress * 100.0)
	elif st.owner == team:
		state = "HELD"
	var bx := (_canvas.size.x - BAR_W) / 2.0
	var by := TOP + PIP.y + 26.0
	_canvas.draw_rect(Rect2(bx - 10.0, by - 4.0, BAR_W + 20.0, 42.0), Color(0, 0, 0, 0.55))
	_canvas.draw_string(_font, Vector2(bx, by + 14.0), "%s   %s" % [title, state], HORIZONTAL_ALIGNMENT_CENTER,
		BAR_W, 16, Color.WHITE)
	_canvas.draw_rect(Rect2(bx, by + 22.0, BAR_W, 10.0), Color(0, 0, 0, 0.6))
	_canvas.draw_rect(Rect2(bx, by + 22.0, BAR_W * st.progress, 10.0), HardpointView.team_color(st.capturing_team))
