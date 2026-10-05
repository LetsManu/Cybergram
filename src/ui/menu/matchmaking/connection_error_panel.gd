class_name ConnectionErrorPanel
extends PanelContainer
## W21-U2: the player-facing "could not connect" card of the online menu:
## a headline, the reason and a Retry and a Back button. It sits in the
## screen's centre; the owner shows it when ConnectionWatch.failed fires and
## hides it on retry. Colours, sizes and buttons come from UiKit tokens.
##
## Example:
##   var p := ConnectionErrorPanel.new()
##   p.retry_requested.connect(retry)
##   p.back_requested.connect(leave)
##   add_child(p)
##   p.show_error(tr(key))

## The player pressed Retry: run the failed online action again.
signal retry_requested()
## The player pressed Back: leave the failed online action.
signal back_requested()

var _message: Label
var _retry: Button


func _ready() -> void:
	HudStrings.ensure_loaded()
	var t := UiKit.tokens()
	theme = UiKit.theme()
	name = "ConnectionError"
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(480, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := UiKit.panel_box(Color(t.bg_deep, 0.98), t.space_xl, t.accent_dim)
	add_theme_stylebox_override("panel", bg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", t.space_m)
	add_child(box)
	box.add_child(UiKit.label(tr("HUD_NET_ERR_TITLE"), &"title", t.text))
	_message = UiKit.label("", &"body", t.text_dim)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(430, 0)
	box.add_child(_message)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", t.space_m)
	box.add_child(row)
	_retry = UiKit.button(tr("HUD_NET_RETRY"), func() -> void: retry_requested.emit(), &"primary")
	row.add_child(_retry)
	row.add_child(UiKit.button(tr("HUD_NET_BACK"), func() -> void: back_requested.emit(), &"ghost"))
	visible = false


## Shows the card with an already translated `text`.
func show_error(text: String) -> void:
	_message.text = text
	visible = true
	_retry.grab_focus.call_deferred()


## The message currently shown ("" when hidden).
func message() -> String:
	return _message.text if visible and _message != null else ""
