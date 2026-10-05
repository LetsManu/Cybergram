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
var _add_btn: Button
var _add_rule: ColorRect
var _footer: Button
## The offline group is folded into the footer until it is clicked.
var _show_offline: bool = false


func _ready() -> void:
	HudStrings.ensure_loaded()
	var t := UiKit.tokens()
	var psb := StyleBoxFlat.new()
	psb.bg_color = t.panel
	psb.border_color = t.line
	psb.border_width_left = 1
	psb.content_margin_top = 20
	add_theme_stylebox_override("panel", psb)
	custom_minimum_size = Vector2(t.sidebar_width, 0)
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	add_child(outer)
	# Expanded rail: header, search / add field, grouped list, offline footer.
	_full = VBoxContainer.new()
	_full.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_full.add_theme_constant_override("separation", 0)
	outer.add_child(_full)
	var hpad := MarginContainer.new()
	hpad.add_theme_constant_override("margin_left", 20)
	hpad.add_theme_constant_override("margin_right", 12)
	_full.add_child(hpad)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	hpad.add_child(hrow)
	var title := Label.new()
	title.text = tr("HUD_FRIENDS_TITLE_PLAIN")
	title.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(13, 0.24)))
	title.add_theme_font_size_override("font_size", 13)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(title)
	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 12)
	_header.add_theme_color_override("font_color", t.text_dim)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header.clip_text = true
	hrow.add_child(_header)
	_add_btn = UiKit.icon_button(&"add_friend", _on_add_pressed, tr("HUD_FRIENDS_ADD"), 32)
	hrow.add_child(_add_btn)
	_toggle = UiKit.icon_button(&"right", func() -> void: set_collapsed(true), tr("HUD_FRIENDS_COLLAPSE"), 32)
	hrow.add_child(_toggle)
	var fpad := MarginContainer.new()
	fpad.add_theme_constant_override("margin_left", 20)
	fpad.add_theme_constant_override("margin_right", 20)
	fpad.add_theme_constant_override("margin_top", 14)
	fpad.add_theme_constant_override("margin_bottom", 6)
	_full.add_child(fpad)
	var col := VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	fpad.add_child(col)
	_add_row = HBoxContainer.new()
	_add_row.add_theme_constant_override("separation", 8)
	var glass := UiIcon.make(&"search", 15.0, t.text_off)
	glass.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_add_row.add_child(glass)
	_add = UiKit.line_edit(tr("HUD_FRIENDS_SEARCH_HINT"), PlayerProfile.NAME_MAX)
	_add.add_theme_font_size_override("font_size", 13)
	var none := StyleBoxEmpty.new()
	_add.add_theme_stylebox_override("normal", none)
	_add.add_theme_stylebox_override("focus", none)
	_add.custom_minimum_size.y = 26
	_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add.text_submitted.connect(func(_t: String) -> void: _on_add())
	_add.text_changed.connect(func(_t: String) -> void: rebuild())
	_add_row.add_child(_add)
	var under := VBoxContainer.new()
	under.add_theme_constant_override("separation", 8)
	under.add_child(_add_row)
	_add_rule = UiKit.hairline(true)
	under.add_child(_add_rule)
	_add.focus_entered.connect(func() -> void: _add_rule.color = t.accent)
	_add.focus_exited.connect(func() -> void: _add_rule.color = t.line_strong)
	col.add_child(under)
	_hint = UiKit.label("", &"small", t.text_dim)
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 120
	_full.add_child(scroll)
	_footer = Button.new()
	_footer.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_footer.add_theme_font_size_override("font_size", 12)
	_footer.add_theme_color_override("font_color", t.text_off)
	_footer.add_theme_color_override("font_hover_color", t.text)
	_footer.add_theme_color_override("font_focus_color", t.text)
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0, 0, 0, 0)
	fsb.border_color = t.line
	fsb.border_width_top = 1
	fsb.content_margin_top = 12
	fsb.content_margin_bottom = 18
	fsb.expand_margin_left = 0
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		_footer.add_theme_stylebox_override(st, fsb)
	_footer.add_theme_stylebox_override("focus", UiKit.focus_box())
	_footer.pressed.connect(func() -> void:
		_show_offline = not _show_offline
		rebuild())
	var foot_pad := MarginContainer.new()
	foot_pad.add_theme_constant_override("margin_left", 20)
	foot_pad.add_theme_constant_override("margin_right", 20)
	foot_pad.add_child(_footer)
	_full.add_child(foot_pad)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
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
	var fi := UiIcon.make(&"friends", 20.0, t.text_dim)
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
	var t := UiKit.tokens()
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_add_row.get_parent().visible = has_account
	_add_btn.visible = has_account
	_footer.get_parent().visible = has_account
	if not has_account:
		_header.text = ""
		_strip_count.text = ""
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		var m := _pad(box, 20)
		var l := UiKit.label(tr("HUD_FRIENDS_LOGIN_HINT") if not request.is_valid() else tr("HUD_FRIENDS_GUEST_HINT"),
			&"small", t.text_dim)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
		if not request.is_valid():
			var b := UiKit.button(tr("HUD_FRIENDS_LOGIN"), func() -> void: login_requested.emit(), &"secondary", 36)
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			box.add_child(b)
		_list.add_child(m)
		return
	var q := _add.text.strip_edges().to_lower()
	var shown := entries.filter(func(e: Dictionary) -> bool:
		return q == "" or str(e.display_name).to_lower().contains(q))
	var friends := entries.filter(func(e: Dictionary) -> bool: return e.relation == AccountCodec.REL_FRIEND)
	var online := friends.filter(func(e: Dictionary) -> bool: return e.status >= LobbyCodec.STATUS_ONLINE).size()
	_header.text = tr("HUD_FRIENDS_N_ONLINE") % online
	_strip_count.text = str(online)
	for c in _strip_list.get_children():
		_strip_list.remove_child(c)
		c.queue_free()
	for e: Dictionary in friends:
		if e.status >= LobbyCodec.STATUS_ONLINE and _strip_list.get_child_count() < 8:
			var em := EmblemIcon.make(int(e.emblem), int(e.accent), 30.0)
			em.ring = Color(0, 0, 0, 0)
			em.status_dot = StatusDot.color_of(int(e.status))
			em.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			em.tooltip_text = str(e.display_name)
			_strip_list.add_child(em)
	var mine := shown.filter(func(e: Dictionary) -> bool: return e.relation == AccountCodec.REL_FRIEND)
	mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.display_name).to_lower() < str(b.display_name).to_lower())
	var incoming := shown.filter(func(e: Dictionary) -> bool: return e.relation == AccountCodec.REL_INCOMING)
	if not incoming.is_empty():
		_list.add_child(_group_label(tr("HUD_FRIENDS_GROUP_REQUESTS")))
	for e: Dictionary in incoming:
		_list.add_child(_row(e))
	# Grouped like a MOBA client: In lobby / In match / Online, offline folded
	# into the footer.
	var offline: Array = []
	for g: Array in [[LobbyCodec.STATUS_IN_LOBBY, "HUD_FRIENDS_GROUP_LOBBY"],
			[LobbyCodec.STATUS_IN_MATCH, "HUD_FRIENDS_GROUP_MATCH"],
			[LobbyCodec.STATUS_ONLINE, "HUD_FRIENDS_GROUP_ONLINE"],
			[LobbyCodec.STATUS_OFFLINE, "HUD_FRIENDS_GROUP_OFFLINE"]]:
		var members := mine.filter(func(e: Dictionary) -> bool:
			return (e.status if e.status >= LobbyCodec.STATUS_ONLINE else LobbyCodec.STATUS_OFFLINE) == g[0])
		if g[0] == LobbyCodec.STATUS_OFFLINE:
			offline = members
			if not _show_offline:
				continue
		if members.is_empty():
			continue
		_list.add_child(_group_label(tr(g[1])))
		for e: Dictionary in members:
			_list.add_child(_row(e))
	var pending := shown.filter(func(e: Dictionary) -> bool:
		return e.relation == AccountCodec.REL_OUTGOING or e.relation == AccountCodec.REL_BLOCKED)
	if not pending.is_empty():
		_list.add_child(_group_label(tr("HUD_FRIENDS_GROUP_OTHER")))
	for rel in [AccountCodec.REL_OUTGOING, AccountCodec.REL_BLOCKED]:
		for e: Dictionary in shown:
			if e.relation == rel:
				_list.add_child(_row(e))
	_footer.text = tr("HUD_FRIENDS_OFFLINE_N") % offline.size()
	if entries.is_empty():
		var empty := UiKit.label(tr("HUD_FRIENDS_EMPTY"), &"small", t.text_off)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(_pad(empty, 20))


func _pad(c: Control, side: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", side)
	m.add_theme_constant_override("margin_right", side)
	m.add_theme_constant_override("margin_top", 12)
	m.add_child(c)
	return m


func _group_label(text: String) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 20)
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_bottom", 6)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _caps_font())
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", UiKit.tokens().text_dim)
	m.add_child(l)
	return m


## Body semibold with the group labels' .2em tracking.
static func _caps_font() -> Font:
	var f := UiKit.body_font(600).duplicate() as FontVariation
	f.spacing_glyph = 2
	return f


## A friend row: portrait with status dot, name, status line, and actions
## that appear on hover / keyboard focus (hairline brass buttons).
func _row(e: Dictionary) -> Control:
	var t := UiKit.tokens()
	var rel: int = e.relation
	var st: int = e.status if rel == AccountCodec.REL_FRIEND else -1
	var panel := PanelContainer.new()
	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(0, 0, 0, 0)
	idle.content_margin_left = 20
	idle.content_margin_right = 20
	idle.content_margin_top = 8
	idle.content_margin_bottom = 8
	var hot := idle.duplicate() as StyleBoxFlat
	hot.bg_color = Color(t.accent, 0.07)
	panel.add_theme_stylebox_override("panel", idle)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var em := EmblemIcon.make(int(e.emblem), int(e.accent), 34.0)
	em.ring = Color(0, 0, 0, 0)
	em.status_dot = StatusDot.color_of(st) if rel == AccountCodec.REL_FRIEND else (t.accent_hi if rel == AccountCodec.REL_INCOMING else t.text_off)
	em.dim = rel == AccountCodec.REL_FRIEND and st < LobbyCodec.STATUS_ONLINE
	em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(em)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	var nm := Label.new()
	nm.text = str(e.display_name)
	nm.add_theme_font_override("font", UiKit.body_font(500))
	nm.add_theme_font_size_override("font_size", 14)
	nm.add_theme_color_override("font_color", t.text if st >= LobbyCodec.STATUS_ONLINE or rel != AccountCodec.REL_FRIEND else t.text_dim)
	nm.clip_text = true
	text.add_child(nm)
	var key: String = ["", "HUD_FRIENDS_INCOMING", "HUD_FRIENDS_OUTGOING", "HUD_FRIENDS_BLOCKED"][rel] \
		if rel != AccountCodec.REL_FRIEND else STATUS_KEYS[clampi(st, 0, 3)]
	var sl := Label.new()
	sl.text = tr(key)
	sl.add_theme_font_size_override("font_size", 12)
	sl.add_theme_color_override("font_color", StatusDot.color_of(st) if rel == AccountCodec.REL_FRIEND else t.accent_hi)
	sl.clip_text = true
	text.add_child(sl)
	row.add_child(text)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 4)
	row.add_child(acts)
	var id: String = e.id
	match rel:
		AccountCodec.REL_INCOMING:
			acts.add_child(_small(tr("HUD_FRIENDS_ACCEPT"), func() -> void: _op(AccountCodec.OP_FRIEND_ACCEPT, id)))
			acts.add_child(_small(tr("HUD_FRIENDS_REMOVE_X"), func() -> void: _op(AccountCodec.OP_FRIEND_DECLINE, id)))
		AccountCodec.REL_FRIEND:
			if allow_join and (st == LobbyCodec.STATUS_IN_LOBBY or st == LobbyCodec.STATUS_IN_MATCH):
				acts.add_child(_small(tr("HUD_FRIENDS_JOIN"), func() -> void: join_requested.emit(id)))
			acts.add_child(_small(tr("HUD_FRIENDS_BLOCK"), func() -> void: _op(AccountCodec.OP_BLOCK, id)))
			var rm := _small(tr("HUD_FRIENDS_REMOVE_X"), func() -> void: _op(AccountCodec.OP_FRIEND_REMOVE, id))
			rm.tooltip_text = tr("HUD_FRIENDS_REMOVE")
			acts.add_child(rm)
		AccountCodec.REL_OUTGOING:
			acts.add_child(_small(tr("HUD_FRIENDS_REMOVE_X"), func() -> void: _op(AccountCodec.OP_FRIEND_REMOVE, id)))
		AccountCodec.REL_BLOCKED:
			acts.add_child(_small(tr("HUD_FRIENDS_UNBLOCK"), func() -> void: _op(AccountCodec.OP_UNBLOCK, id)))
	# Hover-reveal: the actions show while the row is hovered or focused
	# (rows take keyboard / gamepad focus; Right / Tab then reaches a button).
	acts.visible = false
	panel.focus_mode = Control.FOCUS_ALL
	panel.add_theme_stylebox_override("focus", UiKit.focus_box())
	var sync := func() -> void:
		if not panel.is_inside_tree():
			return
		var r := Rect2(Vector2.ZERO, panel.size)
		var on := r.has_point(panel.get_local_mouse_position()) or panel.has_focus()
		for b in acts.get_children():
			on = on or (b as Control).has_focus()
		acts.visible = on
		panel.add_theme_stylebox_override("panel", hot if on else idle)
	panel.mouse_entered.connect(sync)
	panel.mouse_exited.connect(sync)
	panel.focus_entered.connect(sync)
	panel.focus_exited.connect(func() -> void: sync.call_deferred())
	for b in acts.get_children():
		(b as Control).mouse_exited.connect(sync)
		(b as Control).focus_exited.connect(func() -> void: sync.call_deferred())
	return panel


func _small(text: String, on_press: Callable) -> Button:
	var t := UiKit.tokens()
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(28, 28)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = t.accent_dim
	sb.set_border_width_all(1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	var hv := sb.duplicate() as StyleBoxFlat
	hv.border_color = t.accent
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("hover_pressed", hv)
	b.add_theme_stylebox_override("focus", UiKit.focus_box())
	b.add_theme_font_override("font", UiKit.body_font(500))
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", t.accent_hi)
	b.add_theme_color_override("font_hover_color", t.text)
	b.add_theme_color_override("font_focus_color", t.text)
	UiSfx.attach(b)
	b.pressed.connect(on_press)
	return b


## Header add-friend icon: sends the typed name, or focuses the field.
func _on_add_pressed() -> void:
	if _add.text.strip_edges() == "":
		_add.grab_focus()
	else:
		_on_add()


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
	_hint.add_theme_color_override("font_color", UiKit.tokens().text_dim if ok else UiKit.tokens().warn)


## Status marker: a shape per status (never colour alone): filled circle =
## online, diamond = in lobby, square = in match, hollow ring = offline.
class StatusDot:
	extends Control
	var status: int = -1

	static func color_of(st: int) -> Color:
		match st:
			LobbyCodec.STATUS_ONLINE:
				return UiKit.tokens().cyan
			LobbyCodec.STATUS_IN_LOBBY:
				return UiKit.tokens().accent
			LobbyCodec.STATUS_IN_MATCH:
				return UiKit.tokens().in_match
		return UiKit.tokens().text_off

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
