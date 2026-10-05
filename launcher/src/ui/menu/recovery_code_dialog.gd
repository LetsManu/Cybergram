class_name RecoveryCodeDialog
extends CanvasLayer
## Shows a new account recovery code exactly once (W21-N1): after CREATE
## ACCOUNT, after "Forgot password?" and after NEW RECOVERY CODE in the
## profile. The player must tick "I wrote it down" before DONE closes it;
## COPY puts the code on the clipboard. Nothing is stored: closing clears the
## text. Display only, built from the UI kit alone, so the launcher uses the
## same file (launcher/tools/shared_tree_files.txt). Texts come from the
## game's string table (HUD_RECOVERY_*) and fall back to English where there
## is none (the launcher).
##
## Example:
##   RecoveryCodeDialog.show_if_issued(self, account_result)  # no-op without a code

## The player confirmed and closed the dialog.
signal acknowledged

const LAYER := 120
const FALLBACK := {
	"HUD_RECOVERY_TITLE": "YOUR RECOVERY CODE",
	"HUD_RECOVERY_BODY": "Write this code down or store it in a password manager. It is the only way to set a new password if you forget yours: there is no e-mail. It is shown only now and works once; you then get a new one.",
	"HUD_RECOVERY_COPY": "COPY",
	"HUD_RECOVERY_COPIED": "Copied to the clipboard.",
	"HUD_RECOVERY_ACK": "I wrote the code down or saved it",
	"HUD_RECOVERY_DONE": "DONE",
}

static var _open: RecoveryCodeDialog

## The code shown (cleared on close).
var code: String = ""
var _ack: CheckBox
var _done: Button
var _code_label: Label
var _note: Label


## Opens the dialog over everything when `result` (an ACCOUNT_RESULT) is OK
## and carries a `recovery_code`. Returns the dialog, or null when there is
## nothing to show (or this code is already on screen).
static func show_if_issued(parent: Node, result: Dictionary) -> RecoveryCodeDialog:
	var c := str(result.get("recovery_code", ""))
	if int(result.get("code", -1)) != 0 or c == "" or parent == null or not parent.is_inside_tree():
		return null
	if is_instance_valid(_open) and _open.code == c:
		return null
	if is_instance_valid(_open):
		_open._close()  # a newer code replaces the old one at once
	var d := RecoveryCodeDialog.new()
	d.code = c
	parent.get_tree().root.add_child.call_deferred(d)
	_open = d
	return d


## True while a dialog is open (tests, the menu).
static func is_open() -> bool:
	return is_instance_valid(_open)


func _ready() -> void:
	layer = LAYER
	var t := UiKit.tokens()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = UiKit.theme()  # a CanvasLayer does not inherit the menu's theme
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(t.bg_deep, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var card := UiKit.card(_t("HUD_RECOVERY_TITLE"), 20)
	card.custom_minimum_size.x = 520
	center.add_child(card)
	var body := card.body
	body.add_theme_constant_override("separation", 12)
	var info := UiKit.label(_t("HUD_RECOVERY_BODY"), &"small", t.text_dim)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(info)
	_code_label = UiKit.label(code, &"display", t.accent, HORIZONTAL_ALIGNMENT_CENTER)
	_code_label.add_theme_font_override("font", UiKit.mono_font(2))
	_code_label.add_theme_font_size_override("font_size", 30)
	body.add_child(_code_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var copy := UiKit.button(_t("HUD_RECOVERY_COPY"), _copy, &"secondary", 36)
	row.add_child(copy)
	_note = UiKit.label("", &"small", t.ok)
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_note)
	body.add_child(row)
	_ack = CheckBox.new()
	_ack.text = _t("HUD_RECOVERY_ACK")
	_ack.toggled.connect(func(on: bool) -> void: _done.disabled = not on)
	body.add_child(_ack)
	_done = UiKit.button(_t("HUD_RECOVERY_DONE"), acknowledge, &"primary", 44)
	_done.disabled = true
	body.add_child(_done)
	UiKit.transition_in(card, Vector2.ZERO)
	_ack.grab_focus.call_deferred()


## Ticks the box (tests / automation; the player clicks it).
func confirm_written_down() -> void:
	_ack.button_pressed = true


## Closes the dialog once the box is ticked (DONE); clears the code.
func acknowledge() -> void:
	if _ack != null and not _ack.button_pressed and is_inside_tree():
		return
	_close()


func _close() -> void:
	code = ""
	if _code_label != null:
		_code_label.text = ""
	if _open == self:
		_open = null
	acknowledged.emit()
	queue_free()


func _copy() -> void:
	DisplayServer.clipboard_set(code)
	_note.text = _t("HUD_RECOVERY_COPIED")


func _unhandled_input(event: InputEvent) -> void:
	# Escape does not dismiss it: only DONE after the box is ticked.
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()


func _t(key: String) -> String:
	var s := tr(key)
	return str(FALLBACK.get(key, key)) if s == key else s
