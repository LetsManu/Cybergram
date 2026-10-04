class_name FriendsPanel
extends PanelContainer
## Compact social panel docked on the right of the main menu and the lobby
## (LoL-client style, design/ux/lobby-and-social.md §2.4/§6). Friends live on
## the server account: add by username (friend request), accept / decline
## incoming requests, cancel outgoing ones, remove, block / unblock; friends
## show online / in lobby / in match / offline (a shape per status, never
## colour alone) and JOIN when they are in a lobby or match. Display only:
## `request` sends AccountCodec ops; the owner feeds the FRIENDS answer back
## with apply_friends(). Guests and logged-out players see a hint instead.
##
## Example:
##   fp.request = func(op, f): online.request(op, f)
##   fp.join_requested.connect(_join_friend)

## The player pressed Join on a friend in a lobby or match.
signal join_requested(friend_id: String)
## The player pressed LOG IN (shown while logged out).
signal login_requested

const POLL_S := 10.0
const STATUS_KEYS := ["HUD_FRIENDS_OFFLINE", "HUD_FRIENDS_ONLINE", "HUD_FRIENDS_IN_LOBBY", "HUD_FRIENDS_IN_MATCH"]

## Callable(op: int, fields: Dictionary); invalid = logged out.
var request: Callable
## Logged in with an account (guests have no friends list).
var has_account: bool = false
## Show Join buttons (off inside the lobby).
var allow_join: bool = true
## Last FRIENDS entries ({id, status, relation, username, display_name, emblem, accent}).
var entries: Array = []

var _list: VBoxContainer
var _add: LineEdit
var _add_row: HBoxContainer
var _header: Label
var _hint: Label
var _poll_left: float = 0.3


func _ready() -> void:
	HudStrings.ensure_loaded()
	add_theme_stylebox_override("panel", MenuStyle.panel(HudPalette.PANEL_STRONG, 12))
	custom_minimum_size = Vector2(280, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_header = MenuStyle.label("", 16, HudPalette.TEXT)
	col.add_child(_header)
	_add_row = HBoxContainer.new()
	_add_row.add_theme_constant_override("separation", 6)
	_add = MenuStyle.line_edit(tr("HUD_FRIENDS_ADD_HINT"), PlayerProfile.NAME_MAX)
	_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add.text_submitted.connect(func(_t: String) -> void: _on_add())
	_add_row.add_child(_add)
	_add_row.add_child(MenuStyle.button(tr("HUD_FRIENDS_ADD"), _on_add, false, 36))
	col.add_child(_add_row)
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
	if not is_visible_in_tree() or not has_account or not request.is_valid():
		return
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = POLL_S
		poll_now()


func poll_now() -> void:
	if has_account and request.is_valid():
		request.call(AccountCodec.OP_FRIENDS, {})


## The server's FRIENDS list.
func apply_friends(list: Array) -> void:
	entries = list
	rebuild()


## Result of a friend op (shows a hint and refreshes the list).
func on_result(d: Dictionary) -> void:
	if int(d.op) == AccountCodec.OP_FRIENDS:
		if d.code == AccountCodec.OK:
			apply_friends(d.friends)
		return
	if int(d.op) == AccountCodec.OP_FRIEND_REQUEST:
		_say(tr("HUD_FRIENDS_REQUEST_SENT") if d.code == AccountCodec.OK else tr(LobbyClient.account_error_key(d.code)),
			d.code == AccountCodec.OK)
	poll_now()


func set_session(account: bool, request_: Callable) -> void:
	has_account = account
	request = request_
	if not account:
		entries = []
	rebuild()
	poll_now()


func rebuild() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_add_row.visible = has_account
	if not has_account:
		_header.text = tr("HUD_FRIENDS_TITLE_PLAIN")
		var l := MenuStyle.label(tr("HUD_FRIENDS_LOGIN_HINT") if not request.is_valid() else tr("HUD_FRIENDS_GUEST_HINT"),
			13, HudPalette.TEXT_OFF)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(l)
		if not request.is_valid():
			_list.add_child(MenuStyle.button(tr("HUD_FRIENDS_LOGIN"), func() -> void: login_requested.emit(), false, 32))
		return
	var friends := entries.filter(func(e: Dictionary) -> bool: return e.relation == AccountCodec.REL_FRIEND)
	friends.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.status != b.status:
			return a.status > b.status
		return str(a.display_name).to_lower() < str(b.display_name).to_lower())
	var online := friends.filter(func(e: Dictionary) -> bool: return e.status >= LobbyCodec.STATUS_ONLINE).size()
	_header.text = tr("HUD_FRIENDS_TITLE") % [online, friends.size()]
	for e: Dictionary in entries:
		if e.relation == AccountCodec.REL_INCOMING:
			_list.add_child(_row(e))
	for e: Dictionary in friends:
		_list.add_child(_row(e))
	for rel in [AccountCodec.REL_OUTGOING, AccountCodec.REL_BLOCKED]:
		for e: Dictionary in entries:
			if e.relation == rel:
				_list.add_child(_row(e))
	if entries.is_empty():
		var empty := MenuStyle.label(tr("HUD_FRIENDS_EMPTY"), 13, HudPalette.TEXT_OFF)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)


func _row(e: Dictionary) -> Control:
	var rel: int = e.relation
	var st: int = e.status if rel == AccountCodec.REL_FRIEND else -1
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var dot := StatusDot.new()
	dot.status = st
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	row.add_child(EmblemIcon.make(int(e.emblem), int(e.accent), 26.0))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	var nm := MenuStyle.label(str(e.display_name), 14, HudPalette.TEXT if st >= LobbyCodec.STATUS_ONLINE else HudPalette.TEXT_DIM)
	nm.clip_text = true
	text.add_child(nm)
	var key: String = ["", "HUD_FRIENDS_INCOMING", "HUD_FRIENDS_OUTGOING", "HUD_FRIENDS_BLOCKED"][rel] \
		if rel != AccountCodec.REL_FRIEND else STATUS_KEYS[clampi(st, 0, 3)]
	text.add_child(MenuStyle.label(tr(key), 11, StatusDot.color_of(st) if rel == AccountCodec.REL_FRIEND else HudPalette.LUMEN))
	row.add_child(text)
	var id: String = e.id
	match rel:
		AccountCodec.REL_INCOMING:
			row.add_child(_small(tr("HUD_FRIENDS_ACCEPT"), func() -> void: _op(AccountCodec.OP_FRIEND_ACCEPT, id)))
			row.add_child(_small(tr("HUD_FRIENDS_REMOVE_X"), func() -> void: _op(AccountCodec.OP_FRIEND_DECLINE, id)))
		AccountCodec.REL_FRIEND:
			if allow_join and (st == LobbyCodec.STATUS_IN_LOBBY or st == LobbyCodec.STATUS_IN_MATCH):
				row.add_child(_small(tr("HUD_FRIENDS_JOIN"), func() -> void: join_requested.emit(id)))
			row.add_child(_small(tr("HUD_FRIENDS_BLOCK"), func() -> void: _op(AccountCodec.OP_BLOCK, id)))
			var rm := _small(tr("HUD_FRIENDS_REMOVE_X"), func() -> void: _op(AccountCodec.OP_FRIEND_REMOVE, id))
			rm.tooltip_text = tr("HUD_FRIENDS_REMOVE")
			row.add_child(rm)
		AccountCodec.REL_OUTGOING:
			row.add_child(_small(tr("HUD_FRIENDS_REMOVE_X"), func() -> void: _op(AccountCodec.OP_FRIEND_REMOVE, id)))
		AccountCodec.REL_BLOCKED:
			row.add_child(_small(tr("HUD_FRIENDS_UNBLOCK"), func() -> void: _op(AccountCodec.OP_UNBLOCK, id)))
	return row


func _small(text: String, on_press: Callable) -> Button:
	var b := MenuStyle.button(text, on_press, false, 28)
	b.add_theme_font_size_override("font_size", 11)
	b.custom_minimum_size.x = 28
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


func _op(op: int, id: String) -> void:
	if request.is_valid():
		request.call(op, {"id": id})


func _on_add() -> void:
	var u := _add.text.strip_edges()
	if u == "" or not request.is_valid():
		return
	if not AccountService.valid_username(u):
		_say(tr("HUD_ACCOUNT_ERR_6"), false)
		return
	request.call(AccountCodec.OP_FRIEND_REQUEST, {"username": u, "id": ""})
	_add.text = ""


func _say(text: String, ok: bool) -> void:
	_hint.text = text
	_hint.add_theme_color_override("font_color", HudPalette.TEXT_DIM if ok else HudPalette.WARN)


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
