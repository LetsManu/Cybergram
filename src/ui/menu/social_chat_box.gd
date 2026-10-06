class_name SocialChatBox
extends VBoxContainer
## P2: a small chat view (DM thread or party chat): the last lines and an
## input; Enter or Send calls `send` with the text. Display only: lines come
## from SocialModel, the server filters and rate-limits. Long lines wrap.
##
## Example:
##   var box := SocialChatBox.new()
##   box.send = func(text): social.say_party(text)
##   box.set_lines([{"name": "Nyx", "text": "gl hf", "mine": false}])

## func(text: String)
var send: Callable
## Height of the line view.
var view_height: float = 140.0

var _log: RichTextLabel
var _edit: LineEdit


func _ready() -> void:
	var t := UiKit.tokens()
	add_theme_constant_override("separation", 6)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, view_height)
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.add_theme_color_override("default_color", t.text)
	_log.focus_mode = Control.FOCUS_NONE
	add_child(_log)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	_edit = UiKit.line_edit(tr("HUD_SOCIAL_TYPE"), 200)
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.text_submitted.connect(func(_s: String) -> void: _send())
	row.add_child(_edit)
	row.add_child(UiKit.button(tr("HUD_SOCIAL_SEND"), _send, &"secondary", 32))


## Lines: [{name?, text, mine?}] (oldest first). Text is escaped (no BBCode
## from other players).
func set_lines(lines: Array) -> void:
	if _log == null:
		return
	var t := UiKit.tokens()
	var parts := PackedStringArray()
	for l: Dictionary in lines:
		var who := tr("HUD_LOBBY_YOU") if bool(l.get("mine", false)) else str(l.get("name", ""))
		var col := (t.accent_hi if bool(l.get("mine", false)) else t.cyan).to_html(false)
		parts.append("[color=#%s]%s[/color]  %s" % [col, _esc(who), _esc(str(l.get("text", "")))])
	_log.text = "\n".join(parts)


func focus_input() -> void:
	if _edit != null:
		_edit.grab_focus()


func _send() -> void:
	var s := _edit.text.strip_edges()
	if s == "" or not send.is_valid():
		return
	send.call(s)
	_edit.text = ""


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")
