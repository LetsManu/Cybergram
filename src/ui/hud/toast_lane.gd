class_name ToastLane
extends HudWidget
## Toast lane, right side under the objective tracker (design/ux/hud.md §13.5,
## reduced): max 3 toasts, 3 s each, newest on top; a toast with the same text
## within 0.5 s merges. Used for settings feedback (F6-F9) for now; gameplay
## toasts (flips, Exposed, Surge) are a follow-up.

const MAX: int = 3
const LIFE: float = 3.0
const ROW_H: float = 42.0

var _items: Array = []  # [text, age]


func push(t: String) -> void:
	for it in _items:
		if it[0] == t and float(it[1]) < 0.5:
			it[1] = 0.0
			return
	_items.push_front([t, 0.0])
	while _items.size() > MAX:
		_items.pop_back()


func _process(delta: float) -> void:
	for i in range(_items.size() - 1, -1, -1):
		_items[i][1] += delta
		if _items[i][1] >= LIFE:
			_items.remove_at(i)
	super(delta)


func _draw() -> void:
	var y := 0.0
	for it in _items:
		var t: String = it[0]
		var a := clampf((LIFE - float(it[1])) / 0.4, 0.0, 1.0)
		var w := text_width(t, 18) + 33.0
		var r := Rect2(size.x - w, y, w, ROW_H - 6.0)
		# v0.12: ink gradient (clear on the left) + 3 px teal right rule (status).
		scrim_h(Rect2(r.position, Vector2(w * 0.25, r.size.y)), 0.0, 0.6 * a)
		draw_rect(Rect2(r.position + Vector2(w * 0.25, 0.0), Vector2(w * 0.75, r.size.y)), Color(HudPalette.INK_DEEP, 0.6 * a))
		draw_rect(Rect2(r.end.x - 3.0, r.position.y, 3.0, r.size.y), Color(HudPalette.TEAL, a))
		text(t, Vector2(r.position.x + 15.0, r.position.y + r.size.y * 0.5 + ts(18) * 0.36), 18, Color(HudPalette.IVORY, a))
		y += ROW_H
