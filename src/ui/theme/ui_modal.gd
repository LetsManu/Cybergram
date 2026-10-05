class_name UiModal
extends Control
## Kit modal dialog (UiKit.modal()): full-rect dim that blocks input, a card
## with a header strip, body text and OK / Cancel. Esc / B cancel (when there
## is a cancel button); focus starts on OK.

signal closed(confirmed: bool)

var card: UiCard
var ok_button: Button
var cancel_button: Button
var _on_ok: Callable
var _on_cancel: Callable


## Fills the dialog (call before adding it to the tree).
func build(title: String, body: String, ok_text: String, on_ok: Callable, cancel_text: String,
		on_cancel: Callable, danger := false) -> void:
	var t := UiKit.tokens()
	_on_ok = on_ok
	_on_cancel = on_cancel
	name = "UiModal"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(t.bg_deep, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	card = UiKit.card(title, 20)
	card.custom_minimum_size.x = 460
	center.add_child(card)
	var l := UiKit.label(body, &"body", t.text_dim)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.body.add_child(l)
	card.body.add_child(UiKit.spacer(t.space_s))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", t.space_s)
	card.body.add_child(row)
	if cancel_text != "":
		cancel_button = UiKit.button(cancel_text, func() -> void: close(false), &"ghost", 40)
		row.add_child(cancel_button)
	ok_button = UiKit.button(ok_text, func() -> void: close(true), &"danger" if danger else &"primary", 40)
	ok_button.custom_minimum_size.x = 140
	row.add_child(ok_button)


func open() -> void:
	UiKit.transition_in(card, Vector2.ZERO)
	ok_button.grab_focus.call_deferred()


## Closes and runs the matching callback.
func close(confirmed: bool) -> void:
	if is_queued_for_deletion():
		return
	closed.emit(confirmed)
	var cb := _on_ok if confirmed else _on_cancel
	queue_free()
	if cb.is_valid():
		cb.call()


func _unhandled_input(event: InputEvent) -> void:
	if cancel_button != null and (event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton
			and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B)):
		get_viewport().set_input_as_handled()
		close(false)
