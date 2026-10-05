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

## Collapsed to the icon strip (design/ux/ui-kit.md §8.1).
var collapsed: bool = false

## Emitted when the sidebar collapses / expands (the owner re-docks it).
signal collapsed_changed(is_collapsed: bool)

var _list: VBoxContainer
var _add: LineEdit
var _add_row: HBoxContainer
var _header: Label
var _hint: Label
var _poll_left: float = 0.3
var _full: VBoxContainer
var _strip: VBoxContainer
var _strip_list: VBoxContainer
var _strip_count: Label
var _toggle: Button


func _ready() -> void:
	HudStrings.ensure_loaded()
	var t := UiKit.tokens()
	add_theme_stylebox_override("panel", UiKit.panel_box(t.panel, 0))
	custom_minimum_size = Vector2(t.sidebar_width, 0)
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	add_child(outer)
	# Expanded sidebar: header strip, add field, grouped list.
	_full = VBoxContainer.new()
	_full.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_full.add_theme_constant_override("separation", 0)
	outer.add_child(_full)
	var head := PanelContainer.new()
	var hb := StyleBoxFlat.new()
	hb.bg_color = t.panel_raised
	hb.border_color = t.line
	hb.border_width_bottom = 1
	hb.content_margin_left = t.space_m
	hb.content_margin_right = 4
	hb.content_margin_top = 4
	hb.content_margin_bottom = 4
	head.add_theme_stylebox_override("panel", hb)
	_full.add_child(head)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", t.space_s)
	head.add_child(hrow)
	hrow.add_child(UiIcon.make(&"friends", 18.0, t.gold))
	_header = UiKit.label("", &"heading")
	_header.add_theme_font_size_override("font_size", t.size_small + 1)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.clip_text = true
	hrow.add_child(_header)
	_toggle = UiKit.icon_button(&"right", func() -> void: set_collapsed(true), tr("HUD_FRIENDS_COLLAPSE"), 32)
	hrow.add_child(_toggle)
	var pad := MarginContainer.new()
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, t.space_m if side != "right" else t.space_s)
	_full.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", t.space_s)
	pad.add_child(col)
	_add_row = HBoxContainer.new()
	_add_row.add_theme_constant_override("separation", 6)
	_add = UiKit.line_edit(tr("HUD_FRIENDS_ADD_HINT"), PlayerProfile.NAME_MAX)
	_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add.text_submitted.connect(func(_t: String) -> void: _on_add())
	_add_row.add_child(_add)
	_add_row.add_child(UiKit.button(tr("HUD_FRIENDS_ADD"), _on_add, &"secondary", 38))
	col.add_child(_add_row)
	_hint = UiKit.label("", &"small", t.text_dim)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 120
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)
	# Collapsed icon strip: expand toggle, online count, online friends' emblems.
	_strip = VBoxContainer.new()
	_strip.custom_minimum_size.x = t.sidebar_collapsed
	_strip.add_theme_constant_override("separation", t.space_s)
	_strip.alignment = BoxContainer.ALIGNMENT_BEGIN
	outer.add_child(_strip)
	var open := UiKit.icon_button(&"left", func() -> void: set_collapsed(false), tr("HUD_FRIENDS_EXPAND"), 40)
	open.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_strip.add_child(UiKit.spacer(4))
	_strip.add_child(open)
	var fi := UiIcon.make(&"friends", 20.0, t.gold)
	fi.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_strip.add_child(fi)
	_strip_count = UiKit.label("", &"small", t.ok, HORIZONTAL_ALIGNMENT_CENTER)
	_strip.add_child(_strip_count)
	_strip_list = VBoxContainer.new()
	_strip_list.add_theme_constant_override("separation", 6)
	_strip.add_child(_strip_list)
	set_collapsed(collapsed)
	rebuild()


## Collapses to the icon strip (true) or expands the full sidebar.
func set_collapsed(on: bool) -> void:
	var changed := on != collapsed
	collapsed = on
	if _full == null:
		return
	_full.visible = not on
	_strip.visible = on
	custom_minimum_size.x = UiKit.tokens().sidebar_collapsed if on else UiKit.tokens().sidebar_width
	if changed:
		collapsed_changed.emit(on)
		UiKit.transition_in(_strip if on else _full, Vector2.ZERO, UiKit.tokens().motion_base)


## Width the owner should reserve for the sidebar.
func dock_width() -> int:
	return UiKit.tokens().sidebar_collapsed if collapsed else UiKit.tokens().sidebar_width


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
		_strip_count.text = ""
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
	_strip_count.text = str(online)
	for c in _strip_list.get_children():
		_strip_list.remove_child(c)
		c.queue_free()
	for e: Dictionary in friends:
		if e.status >= LobbyCodec.STATUS_ONLINE and _strip_list.get_child_count() < 8:
			var em := EmblemIcon.make(int(e.emblem), int(e.accent), 28.0)
			em.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			em.tooltip_text = str(e.display_name)
			_strip_list.add_child(em)
	var incoming := entries.filter(func(e: Dictionary) -> bool: return e.relation == AccountCodec.REL_INCOMING)
	if not incoming.is_empty():
		_list.add_child(_group_label("%s  %d" % [tr("HUD_FRIENDS_GROUP_REQUESTS"), incoming.size()]))
	for e: Dictionary in incoming:
		_list.add_child(_row(e))
	# Grouped like a MOBA client: Online / In lobby / In match / Offline.
	for g: Array in [[LobbyCodec.STATUS_ONLINE, "HUD_FRIENDS_GROUP_ONLINE"],
			[LobbyCodec.STATUS_IN_LOBBY, "HUD_FRIENDS_GROUP_LOBBY"],
			[LobbyCodec.STATUS_IN_MATCH, "HUD_FRIENDS_GROUP_MATCH"],
			[LobbyCodec.STATUS_OFFLINE, "HUD_FRIENDS_GROUP_OFFLINE"]]:
		var members := friends.filter(func(e: Dictionary) -> bool:
			return (e.status if e.status >= LobbyCodec.STATUS_ONLINE else LobbyCodec.STATUS_OFFLINE) == g[0])
		if members.is_empty():
			continue
		_list.add_child(_group_label("%s  %d" % [tr(g[1]), members.size()]))
		for e: Dictionary in members:
			_list.add_child(_row(e))
	var pending := entries.filter(func(e: Dictionary) -> bool:
		return e.relation == AccountCodec.REL_OUTGOING or e.relation == AccountCodec.REL_BLOCKED)
	if not pending.is_empty():
		_list.add_child(_group_label(tr("HUD_FRIENDS_GROUP_OTHER")))
	for rel in [AccountCodec.REL_OUTGOING, AccountCodec.REL_BLOCKED]:
		for e: Dictionary in entries:
			if e.relation == rel:
				_list.add_child(_row(e))
	if entries.is_empty():
		var empty := MenuStyle.label(tr("HUD_FRIENDS_EMPTY"), 13, HudPalette.TEXT_OFF)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)


## Small caption heading a status group.
func _group_label(text: String) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 2)
	m.add_child(UiKit.label(text, &"caption", UiKit.tokens().text_off))
	return m


func _row(e: Dictionary) -> Control:
	var rel: int = e.relation
	var st: int = e.status if rel == AccountCodec.REL_FRIEND else -1
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 36
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
	var b := UiKit.button(text, on_press, &"ghost", 26)
	b.add_theme_font_size_override("font_size", 11)
	var sb := b.get_theme_stylebox("normal") as UiBevelBox
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.border = UiKit.tokens().line
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
