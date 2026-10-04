class_name FriendsPanel
extends PanelContainer
## Compact social panel docked on the right of the main menu and the lobby
## (LoL-client style, design/ux/lobby-and-social.md §2.4): an add field
## ("Name" or "Name#TAG"), then one row per friend with a status dot
## (online / in lobby / in match / offline, each with its own shape),
## Join and Remove. Display only: presence comes from the server through
## `query` (set by the owner) and apply_presence().
##
## Example:
##   var fp := FriendsPanel.new()
##   fp.friends = FriendList.load_from(path)
##   fp.save_path = path
##   fp.query = func(ids, names): lobby.query_presence(ids, names)
##   fp.join_requested.connect(_join_friend)

## The player pressed Join on a friend in a lobby or match.
signal join_requested(friend_id: String)

## Seconds between presence queries while visible.
const POLL_S := 10.0
## Status presentation: tr key, colour.
const STATUS_KEYS := ["HUD_FRIENDS_OFFLINE", "HUD_FRIENDS_ONLINE", "HUD_FRIENDS_IN_LOBBY", "HUD_FRIENDS_IN_MATCH"]
const STATUS_UNKNOWN := -1

var friends: FriendList = FriendList.new()
## Where the list is saved after a change ("" = never).
var save_path: String = ""
## Callable(ids: PackedStringArray, names: PackedStringArray) that sends a
## presence query; the reply must come back through apply_presence().
var query: Callable
## Show Join buttons (off inside the lobby: you are already there).
var allow_join: bool = true
## friend id -> status (LobbyCodec.STATUS_*); missing = unknown.
var status: Dictionary = {}

var _list: VBoxContainer
var _add: LineEdit
var _header: Label
var _hint: Label
var _poll_left: float = 0.5


func _ready() -> void:
	HudStrings.ensure_loaded()
	add_theme_stylebox_override("panel", MenuStyle.panel(HudPalette.PANEL_STRONG, 12))
	custom_minimum_size = Vector2(280, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_header = MenuStyle.label("", 16, HudPalette.TEXT)
	col.add_child(_header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_add = MenuStyle.line_edit(tr("HUD_FRIENDS_ADD_HINT"), PlayerProfile.NAME_MAX + 5)
	_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add.text_submitted.connect(func(_t: String) -> void: _on_add())
	row.add_child(_add)
	var add_btn := MenuStyle.button(tr("HUD_FRIENDS_ADD"), _on_add, false, 36)
	row.add_child(add_btn)
	col.add_child(row)
	_hint = MenuStyle.label("", 12, HudPalette.TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 120
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	rebuild()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or not query.is_valid():
		return
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = POLL_S
		poll_now()


## Sends a presence query for every friend right away.
func poll_now() -> void:
	if not query.is_valid():
		return
	var names := PackedStringArray()
	for f in friends.unresolved():
		names.append(f.label())
	query.call(friends.ids(), names)


## Presence reply (Array of {id, status, name}): resolves friends added by
## name, updates statuses and redraws.
func apply_presence(entries: Array) -> void:
	var changed := false
	for e: Dictionary in entries:
		if str(e.name) != "" and friends.resolve(str(e.id), str(e.name)):
			changed = true
		status[str(e.id)] = int(e.status)
	if changed:
		_save()
	rebuild()


## Adds a friend whose id is known (e.g. from a lobby row). True if added.
func add_known(id: String, name: String) -> bool:
	var f := friends.add_known(id, name)
	if f == null:
		return false
	_save()
	rebuild()
	poll_now()
	return true


## Status of friend `f` (STATUS_UNKNOWN before the first answer).
func status_of(f: FriendList.Friend) -> int:
	return int(status.get(f.id, STATUS_UNKNOWN)) if f.id != "" else STATUS_UNKNOWN


func rebuild() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var online := 0
	var order: Array = friends.friends.duplicate()
	order.sort_custom(func(a: FriendList.Friend, b: FriendList.Friend) -> bool:
		var sa := status_of(a)
		var sb := status_of(b)
		if sa != sb:
			return sa > sb
		return a.name.to_lower() < b.name.to_lower())
	for f: FriendList.Friend in order:
		if status_of(f) >= LobbyCodec.STATUS_ONLINE:
			online += 1
		_list.add_child(_row(f))
	_header.text = tr("HUD_FRIENDS_TITLE") % [online, friends.friends.size()]
	if friends.friends.is_empty():
		var empty := MenuStyle.label(tr("HUD_FRIENDS_EMPTY"), 13, HudPalette.TEXT_OFF)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)


func _row(f: FriendList.Friend) -> Control:
	var st := status_of(f)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var dot := StatusDot.new()
	dot.status = st
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	var nm := MenuStyle.label(f.label(), 14, HudPalette.TEXT if st >= LobbyCodec.STATUS_ONLINE else HudPalette.TEXT_DIM)
	nm.clip_text = true
	text.add_child(nm)
	var key: String = "HUD_FRIENDS_PENDING" if f.id == "" else ("HUD_FRIENDS_UNKNOWN" if st < 0 else STATUS_KEYS[st])
	text.add_child(MenuStyle.label(tr(key), 11, StatusDot.color_of(st)))
	row.add_child(text)
	if allow_join and (st == LobbyCodec.STATUS_IN_LOBBY or st == LobbyCodec.STATUS_IN_MATCH):
		var join := MenuStyle.button(tr("HUD_FRIENDS_JOIN"), func() -> void: join_requested.emit(f.id), false, 28)
		join.add_theme_font_size_override("font_size", 12)
		row.add_child(join)
	var rm := MenuStyle.button(tr("HUD_FRIENDS_REMOVE_X"), func() -> void:
		friends.remove(f)
		_save()
		rebuild(), false, 28)
	rm.tooltip_text = tr("HUD_FRIENDS_REMOVE")
	rm.custom_minimum_size.x = 28
	row.add_child(rm)
	return row


func _on_add() -> void:
	var text := _add.text.strip_edges()
	if text == "":
		return
	var f := friends.add(text)
	if f == null:
		_hint.text = tr("HUD_FRIENDS_ADD_BAD") if FriendList.parse(text).is_empty() else tr("HUD_FRIENDS_ADD_DUP")
		_hint.add_theme_color_override("font_color", HudPalette.WARN)
		return
	_add.text = ""
	_hint.text = tr("HUD_FRIENDS_ADDED") % f.label()
	_hint.add_theme_color_override("font_color", HudPalette.TEXT_DIM)
	_save()
	rebuild()
	poll_now()


func _save() -> void:
	if save_path != "":
		friends.save(save_path)


## Status marker: a shape per status (never colour alone): filled circle =
## online, diamond = in lobby, square = in match, hollow ring = offline.
class StatusDot:
	extends Control
	var status: int = -1

	static func color_of(st: int) -> Color:
		match st:
			LobbyCodec.STATUS_ONLINE:
				return HudPalette.HEAL
			LobbyCodec.STATUS_IN_LOBBY:
				return Color("#4FB3FF")
			LobbyCodec.STATUS_IN_MATCH:
				return HudPalette.LUMEN
		return HudPalette.TEXT_OFF

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.4
		var col := color_of(status)
		match status:
			LobbyCodec.STATUS_ONLINE:
				draw_circle(c, r, col)
			LobbyCodec.STATUS_IN_LOBBY:
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.2), c + Vector2(r * 1.2, 0),
					c + Vector2(0, r * 1.2), c + Vector2(-r * 1.2, 0)]), col)
			LobbyCodec.STATUS_IN_MATCH:
				draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), col)
			_:
				draw_arc(c, r * 0.85, 0.0, TAU, 20, col, 1.5, true)
