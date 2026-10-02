class_name SquadStrip
extends CanvasLayer
## Squad strip and radial wheel (hud.md §4.6, §7; wardlings-and-economy.md §8).
## One slot per squad slot (3–5) above the HP bar: slot number, variant glyph,
## HP bar and the state badge (F Follow, H Hold, A Attack, C Capture, ! in
## combat, R returning, D death-hold). Empty slots show "--" (Foundry).
## Reads ClientWorld's WardlingPresenter only; writes nothing.

const SLOT_W: float = 64.0
const SLOT_H: float = 44.0
const GAP: float = 6.0
const MIN_SLOTS: int = 3
const COMMAND_LETTER := {0: "-", 1: "F", 2: "H", 3: "A", 4: "C"}
const WHEEL_R: float = 110.0
const WHEEL_LABELS := ["FOLLOW", "HOLD", "ATTACK", "CAPTURE"]
const COLOR_BG := Color(0.05, 0.07, 0.1, 0.72)
const COLOR_EDGE := Color(1.0, 0.86, 0.25)
const COLOR_EMPTY := Color(0.45, 0.47, 0.52)

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
	if _client == null or _client.wardlings == null:
		return
	var pips := _client.wardlings.own_squad
	var n := maxi(MIN_SLOTS, pips.size())
	var origin := Vector2(24.0, _canvas.size.y - 150.0)
	_canvas.draw_string(_font, origin + Vector2(0.0, -8.0), "SQUAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_EDGE)
	for i in n:
		var r := Rect2(origin + Vector2(i * (SLOT_W + GAP), 0.0), Vector2(SLOT_W, SLOT_H))
		_canvas.draw_rect(r, COLOR_BG)
		if i >= pips.size():
			_canvas.draw_rect(r, COLOR_EMPTY, false, 1.0)
			_canvas.draw_string(_font, r.position + Vector2(6.0, 18.0), "%d --" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1,
				15, COLOR_EMPTY)
			continue
		var p: WardlingPresenter.SquadPip = pips[i]
		_canvas.draw_rect(r, COLOR_EDGE, false, 1.5)
		_canvas.draw_string(_font, r.position + Vector2(6.0, 18.0), "%d Pk" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1,
			15, Color.WHITE)
		var badge := _badge(p)
		_canvas.draw_string(_font, r.position + Vector2(SLOT_W - 18.0, 18.0), badge, HORIZONTAL_ALIGNMENT_LEFT, -1,
			17, COLOR_EDGE if badge == COMMAND_LETTER.get(p.command, "-") else Color(1.0, 0.4, 0.3))
		var bar := Rect2(r.position + Vector2(6.0, SLOT_H - 14.0), Vector2(SLOT_W - 12.0, 7.0))
		_canvas.draw_rect(bar, Color(0.15, 0.15, 0.18))
		bar.size.x *= clampf(p.hp_frac, 0.0, 1.0)
		_canvas.draw_rect(bar, Color(1.0, 0.25, 0.2).lerp(Color(0.4, 1.0, 0.5), p.hp_frac))
	var input := _client.player_input
	if input != null and input.wheel_open:
		_draw_wheel(input)


static func _badge(p: WardlingPresenter.SquadPip) -> String:
	if p.dissolving:
		return "D"
	if (p.flags & WardlingSim.FLAG_RETURNING) != 0:
		return "R"
	if (p.flags & WardlingSim.FLAG_COMBAT) != 0 and p.command != 3:
		return "!"
	return COMMAND_LETTER.get(p.command, "-")


## Four 90° slices (Follow top, Hold right, Attack bottom, Capture left).
func _draw_wheel(input: PlayerInputSource) -> void:
	var c := _canvas.size / 2.0
	var sel := input.wheel_selection()
	_canvas.draw_circle(c, WHEEL_R, Color(0.05, 0.07, 0.1, 0.4))
	for i in 4:
		var a := -PI / 2.0 + i * PI / 2.0
		var lit := sel == PlayerInputSource.WHEEL_SLICES[i]
		var pos := c + Vector2(cos(a), sin(a)) * WHEEL_R * 0.66
		_canvas.draw_string(_font, pos - Vector2(36.0, -6.0), WHEEL_LABELS[i], HORIZONTAL_ALIGNMENT_CENTER, 72, 15,
			COLOR_EDGE if lit else Color.WHITE)
