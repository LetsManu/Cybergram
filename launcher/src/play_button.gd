class_name LauncherPlayButton
extends Button
## The big PLAY button of the launcher (brass chamfer, ink text). While busy
## (updating, verifying, repairing) it is disabled, turns hairline grey and
## fills with brass as the progress grows, with a headline ("UPDATING 42%");
## the size / speed line goes to the play bar. Otherwise a normal button.

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
	var t: UiKitTokens = UiKit.tokens()
	add_theme_font_override("font", UiKit.display_font(700, UiKit.track(22, 0.26)))
	add_theme_font_size_override("font_size", 22)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		(get_theme_stylebox(st) as UiBevelBox).bevel = 12
	_disabled_style = get_theme_stylebox("disabled")
	(_disabled_style as UiBevelBox).bevel = 12
	# Busy: hairline-grey chamfer that fills with brass (mockup btnBg #2A3238).
	_busy_style = UiBevelBox.new()
	_busy_style.fill = t.line_strong
	_busy_style.fill_hover = t.line_strong
	_busy_style.bevel = 12


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
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	var fill: Rect2
	if _frac < 0.0:
		var w: float = r.size.x * 0.3
		var x: float = r.position.x + (r.size.x - w) * _sweep
		fill = Rect2(x, r.position.y, w, r.size.y)
	else:
		fill = Rect2(r.position, Vector2(r.size.x * clampf(_frac, 0.0, 1.0), r.size.y))
	if fill.size.x > 0.5:
		var shape: PackedVector2Array = UiBevelBox.outline(r, 12.0)
		var clip: PackedVector2Array = PackedVector2Array([fill.position, Vector2(fill.end.x, fill.position.y),
			fill.end, Vector2(fill.position.x, fill.end.y)])
		for poly in Geometry2D.intersect_polygons(shape, clip):
			draw_colored_polygon(poly, t.accent)
	# The headline only ("42%", "VERIFYING"); the size / speed line is the
	# play bar's mono detail. Ink over the brass part, ivory over the grey.
	var size_px: int = 22 if _headline.length() <= 8 else 16
	var big: Font = UiKit.display_font(700, UiKit.track(size_px, 0.26 if size_px == 22 else 0.14))
	var hs: Vector2 = big.get_string_size(_headline, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	var pos: Vector2 = Vector2((size.x - hs.x) * 0.5, (size.y - hs.y) * 0.5 + big.get_ascent(size_px))
	var on_brass: bool = _frac >= 0.0 and fill.end.x >= size.x * 0.5 + hs.x * 0.5
	draw_string(big, pos, _headline, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, t.bg if on_brass else t.text)
