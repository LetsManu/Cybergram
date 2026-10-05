class_name NetGraph
extends CanvasLayer
## Debug overlay (W16-NET): ping, loss, jitter, snapshot kB/s in and input
## kB/s out, snapshot size with a size history against the byte budget, the
## current interpolation delay, then the session's debug text (tick, net-sim,
## prediction error). UI kit style: ink panel, brass eyebrow, IBM Plex Mono
## values, teal for healthy figures and amber when a figure is poor.
## Hidden by default; F3 toggles it (or `--net-graph` / [hud] net_graph in
## user://settings.cfg shows it at start). It sits at the left middle of the
## screen, clear of the HUD zones (minimap / header / squad strip). Reads the
## session (GameSession.net_stats() / debug_text()); never writes gameplay state.
## Debug text is developer-only and intentionally not localised.

const _REFRESH_FRAMES: int = 10
const _KEY := KEY_F3
## Rows: [stat key, label]. Values come from GameSession.net_stats().
const ROWS: Array = [
	["ping", "PING"], ["loss", "LOSS"], ["jitter", "JITTER"], ["interp", "INTERP"],
	["kbps_in", "SNAP IN"], ["kbps_out", "OUT"], ["snap", "SNAP SIZE"], ["mode", "LINK"]]
## Thresholds above which a figure turns amber.
const WARN_PING_MS: float = 120.0
const WARN_LOSS_PCT: float = 2.0
const WARN_JITTER_MS: float = 34.0

var session: Node
var _panel: PanelContainer
var _values: Dictionary = {}  # key -> Label
var _spark: _Spark
var _footer: Label
var _frame: int = 0
var _was_down: bool = false


## Bar history of snapshot sizes with the budget as a hairline.
class _Spark:
	extends Control
	var sizes: PackedInt32Array = PackedInt32Array()
	var budget: int = 1100
	var bar := Color("#4FB8B0")
	var over := Color("#D0904E")
	var line := Color("#C2A267")
	var grid := Color("#1E272D")

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, grid, false, 1.0)
		var top := float(maxi(budget * 5 / 4, 1))
		var y_budget := size.y * (1.0 - budget / top)
		if sizes.is_empty():
			draw_line(Vector2(0, y_budget), Vector2(size.x, y_budget), line, 1.0)
			return
		var n := sizes.size()
		var w := size.x / float(maxi(n, 1))
		for i in n:
			var h := minf(sizes[i] / top, 1.0) * size.y
			draw_rect(Rect2(i * w, size.y - h, maxf(w - 1.0, 1.0), h), over if sizes[i] > budget else bar)
		draw_line(Vector2(0, y_budget), Vector2(size.x, y_budget), line, 1.0)


func _ready() -> void:
	layer = 20
	var t := UiKit.tokens()
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := t.panel
	bg.a = 0.88
	_panel.add_theme_stylebox_override("panel", UiKit.panel_box(bg, 10, t.line_strong))
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := UiKit.eyebrow("Net graph", t.accent, 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiKit.key_chip("F3", 24))
	col.add_child(head)
	col.add_child(UiKit.hairline(true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	for row: Array in ROWS:
		var k := UiKit.label(row[1], &"caption", t.text_dim)
		k.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(11, 0.16)))
		grid.add_child(k)
		var v := Label.new()
		v.add_theme_font_override("font", UiKit.mono_font())
		v.add_theme_font_size_override("font_size", 14)
		v.add_theme_color_override("font_color", t.text)
		v.text = "-"
		grid.add_child(v)
		_values[row[0]] = v
	col.add_child(grid)
	var cap := UiKit.label("SNAPSHOT BYTES / BUDGET", &"caption", t.text_off)
	col.add_child(cap)
	_spark = _Spark.new()
	_spark.custom_minimum_size = Vector2(0, 28)
	_spark.bar = t.cyan
	_spark.over = t.warn
	_spark.line = t.accent
	_spark.grid = t.line
	col.add_child(_spark)
	col.add_child(UiKit.hairline())
	_footer = UiKit.label("", &"caption", t.text_dim)
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_footer)
	visible = HudSettings.load_user(OS.get_cmdline_user_args()).net_graph
	get_viewport().size_changed.connect(_place)
	_place()


func _place() -> void:
	var vp := get_viewport().get_visible_rect().size
	_panel.position = Vector2(12.0, vp.y * 0.225)  # below the minimap, above the item strip
	_panel.custom_minimum_size = Vector2(clampf(vp.x * 0.2, 260.0, 340.0), 0.0)
	_panel.size = Vector2(_panel.custom_minimum_size.x, 0.0)


func _process(_delta: float) -> void:
	var down := InputBindings.is_down(&"net_graph", _KEY)
	if down and not _was_down:
		visible = not visible
	_was_down = down
	_frame += 1
	if not visible or session == null or _frame % _REFRESH_FRAMES != 0:
		return
	refresh()


## Pulls the session's figures into the panel (also used by evidence captures).
func refresh() -> void:
	var s: Dictionary = session.call("net_stats") if session.has_method("net_stats") else {}
	apply_stats(s)
	var dbg: String = session.call("debug_text") if session.has_method("debug_text") else ""
	_footer.text = "%s | Godot %s / %s" % [dbg, Engine.get_version_info().string,
		RenderingServer.get_current_rendering_method()]


## Shows `s` (GameSession.net_stats() keys; missing keys show "-").
func apply_stats(s: Dictionary) -> void:
	var t := UiKit.tokens()
	_set_row("ping", "%d ms" % s.ping_ms if s.get("ping_ms", -1) >= 0 else "-",
		s.get("ping_ms", 0) > WARN_PING_MS)
	_set_row("loss", "%.1f %%" % s.loss_pct if s.has("loss_pct") else "-", s.get("loss_pct", 0.0) > WARN_LOSS_PCT)
	_set_row("jitter", "%.0f ms  p95 %.0f" % [s.jitter_ms, s.jitter_p95_ms] if s.has("jitter_ms") else "-",
		s.get("jitter_p95_ms", 0.0) > WARN_JITTER_MS)
	_set_row("interp", "%.0f ms  (%.1f t)" % [s.interp_ms, s.interp_ticks] if s.has("interp_ms") else "-", false)
	_set_row("kbps_in", "%.1f kB/s  all %.1f" % [s.kbps_snap, s.kbps_in] if s.has("kbps_snap") else "-", false)
	_set_row("kbps_out", "%.1f kB/s" % s.kbps_out if s.has("kbps_out") else "-", false)
	_set_row("snap", "%d B  max %d" % [roundi(s.snap_avg), s.snap_max] if s.has("snap_avg") else "-",
		s.get("snap_max", 0) > s.get("budget", 1 << 30))
	_set_row("mode", str(s.get("mode", "-")), false)
	_spark.sizes = s.get("sizes", PackedInt32Array())
	_spark.budget = s.get("budget", 1100)
	_spark.queue_redraw()
	_values["mode"].add_theme_color_override("font_color", t.text_dim)


## Text of a value row (tests / evidence).
func value_text(key: String) -> String:
	return _values[key].text if _values.has(key) else ""


func _set_row(key: String, text: String, bad: bool) -> void:
	var l: Label = _values[key]
	l.text = text
	var t := UiKit.tokens()
	l.add_theme_color_override("font_color", t.warn if bad else (t.cyan if text != "-" else t.text_off))
