class_name NetGraph
extends CanvasLayer
## Debug overlay: session tick, net-sim profile, prediction error, corrections,
## plus a crosshair. Reads the session; never writes gameplay state.

const _REFRESH_FRAMES: int = 10

var session: Node
var _label: Label
var _frame: int = 0


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(12.0, 8.0)
	_label.add_theme_font_size_override("font_size", 16)
	add_child(_label)
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 28)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(cross)


func _process(_delta: float) -> void:
	_frame += 1
	if session == null or _frame % _REFRESH_FRAMES != 0:
		return
	_label.text = "CYBERGRAM M1 - offline session (local server + loopback)\n%s\nGodot %s / %s" % [
		session.call("debug_text"), Engine.get_version_info().string,
		RenderingServer.get_current_rendering_method()]
