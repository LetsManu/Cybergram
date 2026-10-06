class_name SocialDmWindow
extends PanelContainer
## P2: the direct-message window with one friend (LoL-client style, docked
## beside the friends panel). Shows the thread from SocialModel, marks it read
## while open, sends through SocialModel.send_dm. Messages exist only in
## memory and only while both are online (PRIVACY.md).
##
## Example:
##   var w := SocialDmWindow.new()
##   w.social = social
##   w.friend_id = id
##   w.friend_name = "Nyx"
##   add_child(w)

var social: SocialModel
var friend_id: String = ""
var friend_name: String = ""

var _title: Label
var _box: SocialChatBox


func _ready() -> void:
	var t := UiKit.tokens()
	add_theme_stylebox_override("panel", UiKit.panel_box(t.panel, 12, t.line_strong))
	custom_minimum_size = Vector2(340, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = UiKit.label(friend_name, &"heading")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	head.add_child(UiKit.button(tr("HUD_MMS_CLOSE"), close, &"ghost", 28))
	_box = SocialChatBox.new()
	_box.send = func(text: String) -> void: social.send_dm(friend_id, text)
	col.add_child(_box)
	if social != null:
		social.open(friend_id)
		social.changed.connect(_refresh)
	_refresh()
	_box.focus_input.call_deferred()


func _refresh() -> void:
	if social == null or _box == null:
		return
	if social.open_thread == friend_id:
		social.unread.erase(friend_id)
	_box.set_lines((social.threads.get(friend_id, []) as Array).map(func(l: Dictionary) -> Dictionary:
		return {"mine": l.mine, "name": friend_name, "text": l.text}))


func close() -> void:
	if social != null:
		social.close_thread()
		if social.changed.is_connected(_refresh):
			social.changed.disconnect(_refresh)
	queue_free()
