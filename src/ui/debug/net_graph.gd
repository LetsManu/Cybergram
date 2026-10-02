class_name NetGraph
extends CanvasLayer
## Debug overlay: session tick, net-sim profile, prediction error, corrections.
## Hidden by default; F3 toggles it (or `--net-graph` / [hud] net_graph in
## user://settings.cfg shows it at start). It sits at the left middle of the
## screen, clear of the HUD zones (minimap / header / squad strip), in small
## monospace-free text. Reads the session; never writes gameplay state.
## Debug text is developer-only and intentionally not localised.

const _REFRESH_FRAMES: int = 10
const _KEY := KEY_F3

var session: Node
var _label: Label
var _frame: int = 0
var _was_down: bool = false


func _ready() -> void:
	layer = 20
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	visible = HudSettings.load_user(OS.get_cmdline_user_args()).net_graph
	get_viewport().size_changed.connect(_place)
	_place()


func _place() -> void:
	var vp := get_viewport().get_visible_rect().size
	_label.position = Vector2(12.0, vp.y * 0.28)
	_label.size = Vector2(vp.x * 0.24, 0.0)


func _process(_delta: float) -> void:
	var down := Input.is_physical_key_pressed(_KEY)
	if down and not _was_down:
		visible = not visible
	_was_down = down
	_frame += 1
	if not visible or session == null or _frame % _REFRESH_FRAMES != 0:
		return
	_label.text = "NET GRAPH [F3]\n%s\nGodot %s / %s" % [
		session.call("debug_text"), Engine.get_version_info().string,
		RenderingServer.get_current_rendering_method()]
