class_name LauncherPlayButton
extends Button
## The big PLAY button of the launcher (kit "play" look). While busy
## (updating, verifying, repairing) it is disabled and shows a progress fill
## drawn inside the button, a headline ("UPDATING 42%") and a small second
## line (size / speed). Otherwise it is a normal button with `text`.

var _busy: bool = false
var _headline: String = ""
var _sub: String = ""
var _frac: float = 0.0   ## < 0 = indeterminate
var _disabled_style: StyleBox
var _busy_style: UiBevelBox
var _sweep: float = 0.0


func _init() -> void:
	custom_minimum_size.y = 64
	UiKit.style_button(self, &"play")
	_disabled_style = get_theme_stylebox("disabled")
	var t: UiKitTokens = UiKit.tokens()
	_busy_style = UiBevelBox.new()
	_busy_style.fill = t.panel_sunken
	_busy_style.fill_hover = t.panel_sunken
	_busy_style.border = Color(t.gold, 0.75)
	_busy_style.border_hover = Color(t.gold, 0.75)
	_busy_style.bevel = t.bevel


## Switches to the busy look (progress fill + two text lines).
func show_busy(headline: String, sub: String, frac: float) -> void:
	_busy = true
	_headline = headline
	_sub = sub
	_frac = frac
	text = ""
	disabled = true
	add_theme_stylebox_override("disabled", _busy_style)
	set_process(frac < 0.0 and not UiKit.reduce_motion())
	queue_redraw()


## Back to a plain button showing `label`.
func show_idle(label: String, is_disabled: bool = false) -> void:
	_busy = false
	text = label
	disabled = is_disabled
	add_theme_stylebox_override("disabled", _disabled_style)
	set_process(false)
	queue_redraw()


func is_busy() -> bool:
	return _busy


func _process(delta: float) -> void:
	_sweep = fposmod(_sweep + delta * 0.8, 1.0)
	queue_redraw()


func _draw() -> void:
	if not _busy:
		return
	var t: UiKitTokens = UiKit.tokens()
	var r: Rect2 = Rect2(Vector2.ZERO, size).grow(-2.0)
	var fill: Rect2
	if _frac < 0.0:
		var w: float = r.size.x * 0.3
		var x: float = r.position.x + (r.size.x - w) * _sweep
		fill = Rect2(x, r.position.y, w, r.size.y)
	else:
		fill = Rect2(r.position, Vector2(r.size.x * clampf(_frac, 0.0, 1.0), r.size.y))
	if fill.size.x > 0.5:
		var shape: PackedVector2Array = UiBevelBox.outline(r, t.bevel)
		var clip: PackedVector2Array = PackedVector2Array([fill.position, Vector2(fill.end.x, fill.position.y),
			fill.end, Vector2(fill.position.x, fill.end.y)])
		for poly in Geometry2D.intersect_polygons(shape, clip):
			draw_colored_polygon(poly, Color(t.accent, 0.78))
	var big: Font = UiKit.display_font(800, 3)
	var small: Font = get_theme_default_font()
	var hs: Vector2 = big.get_string_size(_headline, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	var ss: Vector2 = small.get_string_size(_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12) if _sub != "" else Vector2.ZERO
	var total: float = hs.y + (ss.y + 2.0 if _sub != "" else 0.0)
	var y: float = (size.y - total) * 0.5
	draw_string(big, Vector2((size.x - hs.x) * 0.5, y + big.get_ascent(20)), _headline, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	if _sub != "":
		draw_string(small, Vector2((size.x - ss.x) * 0.5, y + hs.y + 2.0 + small.get_ascent(12)), _sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, t.text)
