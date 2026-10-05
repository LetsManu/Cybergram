class_name ConnectionErrorPanel
extends PanelContainer
## W21-U2: the player-facing "could not connect" card of the online menu:
## a headline, the reason and a Retry and a Back button. It covers the
## screen's centre; the owner shows it when ConnectionWatch.failed fires and
## hides it on retry.
##
## Example:
##   var p := ConnectionErrorPanel.new()
##   p.retry_requested.connect(retry)
##   p.back_requested.connect(leave)
##   p.show_error(tr(key))

signal retry_requested()
signal back_requested()

var _message: Label
var _retry: Button
var _back: Button


func _ready() -> void:
	HudStrings.ensure_loaded()
	theme = UiKit.theme()
	name = "ConnectionError"
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(480, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.09, 0.98)
	bg.border_color = Color(0.78, 0.65, 0.4, 0.8)
	bg.set_border_width_all(1)
	add_theme_stylebox_override("panel", bg)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var title := Label.new()
	title.text = tr("HUD_NET_ERR_TITLE")
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(430, 0)
	box.add_child(_message)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_retry = Button.new()
	_retry.text = tr("HUD_NET_RETRY")
	_retry.pressed.connect(func() -> void: retry_requested.emit())
	row.add_child(_retry)
	_back = Button.new()
	_back.text = tr("HUD_NET_BACK")
	_back.pressed.connect(func() -> void: back_requested.emit())
	row.add_child(_back)
	visible = false


## Shows the card with an already translated `text`.
func show_error(text: String) -> void:
	_message.text = text
	visible = true
	_retry.grab_focus.call_deferred()


## The message currently shown ("" when hidden).
func message() -> String:
	return _message.text if visible and _message != null else ""
