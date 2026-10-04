class_name LobbyScreen
extends VBoxContainer
## Online lobby view (LoL champ-select style on one server,
## design/ux/lobby-and-social.md §2.2/§2.3): two team columns with each
## player's emblem, name, hero badge and ready / locked state; SWITCH TEAM when
## the other side has room; a data-driven hero picker (HeroCatalog); Ready =
## lock in; the countdown and its locked final seconds; lobby chat; leave.
## It runs on the menu's logged-in connection (`online`, a LobbyClient).
## Chat safety: MUTE hides a player's chat for this session (memory only);
## BLOCK and "+" (friend request) go to the server account (not for guests).
## Display only: the server decides every seat, team, pick and chat line.
## When the server starts the match it emits start_requested with the
## --connect/--hero/--token args.
##
## Example (MainMenu):
##   var lobby := LobbyScreen.new()
##   lobby.address = "cyber.djboeck.at:7777"
##   lobby.online = logged_in_client
##   lobby.start_requested.connect(...)
##   add_child(lobby)

signal start_requested(args: PackedStringArray)
## `reason` is already translated ("" = the player left).
signal cancelled(reason: String)
## "+" on another player's row.
signal add_friend_requested(id: String, name: String)
## An account answer that arrived while the lobby is open (friends panel).
signal account_result(result: Dictionary)
## Every lobby state: the seats (lets the friends list resolve names to ids).
signal roster_seen(slots: Array)

const CONNECT_TIMEOUT_S := 8.0
const SYS_KEYS := ["", "HUD_LOBBY_SYS_JOINED", "HUD_LOBBY_SYS_LEFT", "HUD_LOBBY_SYS_RECONNECTING",
	"HUD_LOBBY_SYS_RECONNECTED", "HUD_LOBBY_SYS_SWITCHED", "HUD_LOBBY_SYS_LOCKED_IN", "HUD_LOBBY_SYS_SLOW_DOWN",
	"HUD_LOBBY_SYS_TEAM_FULL"]

var address: String = ""
## The logged-in connection (required): account session + lobby messages.
var online: LobbyClient
## Its ENet link (for disconnect detection; null on loopback tests).
var link: ENetTransport
## Hero id stem pre-selected ("vesper_loom").
var hero_id: String = "vesper_loom"
## A friend's id to sit with ("Join friend"; "" = none).
var party_id: String = ""
## Debug / testing: press Ready as soon as the lobby answers (--auto-ready).
var auto_ready: bool = false
## Ids that are already friends (no "+" on their rows).
var friend_ids: PackedStringArray = PackedStringArray()
## Session mutes (memory only).
var moderation: LocalModeration

var _lobby: LobbyClient
var _host: String = ""
var _port: int = ENetTransport.DEFAULT_PORT
var _waited: float = 0.0
var _status: Label
var _count: Label
var _team_cols: Array[VBoxContainer] = []
var _team_heads: Array[Label] = []
var _switch: Array[Button] = []
var _hero_buttons: Dictionary = {}  # ContentDB index -> Button
var _hero_index: int = 0
var _ready_btn: Button
var _chat_log: RichTextLabel
var _chat_in: LineEdit
var _chat_lines: int = 0


func _ready() -> void:
	HudStrings.ensure_loaded()
	if moderation == null:
		moderation = LocalModeration.shared()
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(900, 0)
	var h := HeroCatalog.find_stem(hero_id)
	_hero_index = int(h.get("index", 0))
	_build()
	var hp := address.rsplit(":", true, 1)
	_host = hp[0]
	if hp.size() == 2 and hp[1].is_valid_int():
		_port = clampi(hp[1].to_int(), 1, 65535)
	_status.text = tr("HUD_LOBBY_JOINING")
	_open()
	_ready_btn.grab_focus.call_deferred()


func _build() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var title := MenuStyle.label(tr("HUD_LOBBY_TITLE").to_upper(), 30, HudPalette.TEXT)
	top.add_child(title)
	var where := MenuStyle.label(address, 13, HudPalette.TEXT_OFF)
	where.size_flags_vertical = Control.SIZE_SHRINK_END
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(where)
	_count = MenuStyle.label("", 22, HudPalette.LUMEN, HORIZONTAL_ALIGNMENT_RIGHT)
	top.add_child(_count)
	add_child(top)
	_status = MenuStyle.label("", 15, HudPalette.LUMEN)
	add_child(_status)

	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 14)
	add_child(teams)
	for t in 2:
		var card := MenuStyle.panel_container(HudPalette.PANEL_STRONG, 10)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := card.get_theme_stylebox("panel") as StyleBoxFlat
		sb.border_color = Color(HudPalette.TEAM_COLORS[0][t], 0.8)
		sb.border_width_top = 3
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		card.add_child(col)
		var head := HBoxContainer.new()
		var name_l := MenuStyle.label("", 18, HudPalette.TEAM_COLORS[0][t])
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_l)
		var sw := MenuStyle.button(tr("HUD_LOBBY_SWITCH"), func() -> void: _switch_to(t), false, 30)
		sw.add_theme_font_size_override("font_size", 12)
		sw.visible = false
		head.add_child(sw)
		col.add_child(head)
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 4)
		col.add_child(rows)
		teams.add_child(card)
		_team_cols.append(rows)
		_team_heads.append(name_l)
		_switch.append(sw)

	add_child(MenuStyle.label(tr("HUD_LOBBY_PICK_HERO"), 13, HudPalette.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var group := ButtonGroup.new()
	for e: Dictionary in HeroCatalog.entries():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(142, 44)
		b.tooltip_text = str(e.name)
		MenuStyle.style_button(b, Color(0.03, 0.035, 0.07, 0.9))
		var inner := HBoxContainer.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.position = Vector2(5, 5)
		inner.size = Vector2(132, 34)
		inner.add_theme_constant_override("separation", 8)
		inner.add_child(HeroBadge.make(int(e.index), 34.0))
		var hl := MenuStyle.label(str(e.name), 13, HudPalette.TEXT)
		hl.clip_text = true
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(hl)
		b.add_child(inner)
		var idx: int = e.index
		b.pressed.connect(func() -> void:
			_hero_index = idx
			_send_pick())
		b.set_pressed_no_signal(idx == _hero_index)
		grid.add_child(b)
		_hero_buttons[idx] = b
	add_child(grid)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	add_child(bottom)
	var chat := MenuStyle.panel_container(HudPalette.PANEL, 8)
	chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cc := VBoxContainer.new()
	chat.add_child(cc)
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = false  # player text is never parsed as markup
	_chat_log.scroll_following = true
	_chat_log.custom_minimum_size = Vector2(0, 112)
	_chat_log.add_theme_font_size_override("normal_font_size", 13)
	_chat_log.add_theme_color_override("default_color", HudPalette.TEXT)
	_chat_log.focus_mode = Control.FOCUS_NONE
	cc.add_child(_chat_log)
	_chat_in = MenuStyle.line_edit(tr("HUD_LOBBY_CHAT_HINT"), LobbyCodec.CHAT_MAX_CHARS)
	_chat_in.text_submitted.connect(func(t: String) -> void:
		if _lobby != null:
			_lobby.say(t)
		_chat_in.text = "")
	cc.add_child(_chat_in)
	bottom.add_child(chat)
	var btns := VBoxContainer.new()
	btns.custom_minimum_size.x = 220
	btns.add_theme_constant_override("separation", 8)
	_ready_btn = MenuStyle.button(tr("HUD_LOBBY_READY"), Callable(), true, 60)
	_ready_btn.toggle_mode = true
	_ready_btn.toggled.connect(func(_on: bool) -> void: _send_pick())
	btns.add_child(_ready_btn)
	btns.add_child(MenuStyle.button(tr("HUD_LOBBY_LEAVE"), func() -> void: _cancel(""), false, 40))
	bottom.add_child(btns)


func _open() -> void:
	_lobby = online
	_lobby.state_changed.connect(_on_state)
	_lobby.chat_received.connect(_on_chat)
	_lobby.account_result.connect(_on_account)
	_lobby.match_starting.connect(_on_start)
	_lobby.failed.connect(_on_failed)
	_lobby.join(_hero_index, party_id)


## The shared client outlives this view: drop every connection to it.
func _exit_tree() -> void:
	if online == null:
		return
	for pair in [[online.state_changed, _on_state], [online.chat_received, _on_chat],
			[online.account_result, _on_account], [online.match_starting, _on_start], [online.failed, _on_failed]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _on_account(d: Dictionary) -> void:
	account_result.emit(d)


func _on_failed(key: String) -> void:
	_cancel(tr(key))


## The lobby client (tests / evidence captures); null once left or started.
func client() -> LobbyClient:
	return _lobby


func _process(delta: float) -> void:
	if _lobby == null:
		return
	var lobby := _lobby  # keep a reference: a handler below may drop _lobby
	lobby.step()
	if _lobby == null:
		return  # the match is starting (or the lobby was left) during step()
	if link != null and link.error_text != "":
		_cancel(tr("HUD_LOBBY_CONNECTION_LOST"))
		return
	if _lobby.state.is_empty():
		_waited += delta
		if _waited > CONNECT_TIMEOUT_S:
			_cancel(tr("HUD_LOBBY_NO_ANSWER") % address)








func _on_state(s: Dictionary) -> void:
	if auto_ready and not _ready_btn.button_pressed:
		_ready_btn.button_pressed = true  # toggled -> _send_pick()
	var you: int = s.you
	var slots: Array = s.slots
	var team_size: int = maxi(1, int(s.team_size))
	var own: Dictionary = slots[you] if you < slots.size() else {}
	roster_seen.emit(slots)
	var counts := [0, 0]
	for t in 2:
		for c in _team_cols[t].get_children():
			_team_cols[t].remove_child(c)
			c.queue_free()
	for i in slots.size():
		var sl: Dictionary = slots[i]
		var t := clampi(int(sl.team), 0, 1)
		counts[t] += 1
		_team_cols[t].add_child(_slot_row(sl, i == you))
	for t in 2:
		for k in range(counts[t], team_size):
			_team_cols[t].add_child(_open_row())
		_team_heads[t].text = "%s  %d/%d" % [tr("HUD_TEAM_%d" % t), counts[t], team_size]
		var own_team := int(own.get("team", -1))
		_switch[t].visible = own_team >= 0 and own_team != t and s.phase != LobbyCodec.PHASE_LOCKED \
			and s.phase != LobbyCodec.PHASE_IN_MATCH
		_switch[t].disabled = counts[t] >= team_size
	var locked: bool = s.phase == LobbyCodec.PHASE_LOCKED
	var own_ready: bool = own.get("ready", false)
	_ready_btn.set_pressed_no_signal(own_ready)
	_ready_btn.disabled = locked
	_ready_btn.text = tr("HUD_LOBBY_LOCKED") if locked else (tr("HUD_LOBBY_UNREADY") if own_ready else tr("HUD_LOBBY_READY"))
	if not own.is_empty() and int(own.hero_index) != 0:
		_hero_index = int(own.hero_index)
	for idx in _hero_buttons:
		var b: Button = _hero_buttons[idx]
		b.set_pressed_no_signal(idx == _hero_index)
		b.disabled = own_ready or locked
	match int(s.phase):
		LobbyCodec.PHASE_COUNTDOWN:
			_status.text = tr("HUD_LOBBY_STARTING") % s.countdown
			_status.add_theme_color_override("font_color", HudPalette.TEXT)
			_count.text = str(s.countdown)
		LobbyCodec.PHASE_LOCKED:
			_status.text = tr("HUD_LOBBY_LOCKED_LINE") % s.countdown
			_status.add_theme_color_override("font_color", HudPalette.LUMEN)
			_count.text = str(s.countdown)
		_:
			_status.text = tr("HUD_LOBBY_WAITING") if _hero_index != 0 else tr("HUD_LOBBY_PICK_FIRST")
			_status.add_theme_color_override("font_color", HudPalette.TEXT_DIM)
			_count.text = ""


func _slot_row(sl: Dictionary, is_you: bool) -> Control:
	var connected: bool = sl.connected
	var card := MenuStyle.panel_container(Color(0.07, 0.08, 0.14, 0.95) if is_you else Color(0.03, 0.035, 0.07, 0.8), 6)
	if is_you:
		(card.get_theme_stylebox("panel") as StyleBoxFlat).border_color = PlayerProfile.accent_of(int(sl.accent))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var em := EmblemIcon.make(int(sl.emblem), int(sl.accent), 38.0)
	em.dim = not connected
	row.add_child(em)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := MenuStyle.label(str(sl.name), 16, HudPalette.TEXT if connected else HudPalette.TEXT_OFF)
	nm.clip_text = true
	names.add_child(nm)
	var sub := "#" + PlayerProfile.tag_of(str(sl.id))
	if is_you:
		sub += "  ·  " + tr("HUD_LOBBY_YOU")
	names.add_child(MenuStyle.label(sub, 11, HudPalette.TEXT_OFF))
	row.add_child(names)
	var hero := HeroCatalog.find_index(int(sl.hero_index))
	var badge := HeroBadge.make(int(sl.hero_index), 34.0)
	badge.dim = not sl.ready
	row.add_child(badge)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hv.custom_minimum_size.x = 92
	hv.add_child(MenuStyle.label(str(hero.get("name", tr("HUD_LOBBY_NO_HERO"))), 13,
		HudPalette.TEXT if sl.ready else HudPalette.TEXT_DIM))
	var state_key := "HUD_LOBBY_STATE_READY" if sl.ready else "HUD_LOBBY_STATE_PICKING"
	var state_col: Color = HudPalette.HEAL if sl.ready else HudPalette.TEXT_OFF
	if not connected:
		state_key = "HUD_LOBBY_STATE_RECONNECTING"
		state_col = HudPalette.WARN
	hv.add_child(MenuStyle.label(tr(state_key), 11, state_col))
	row.add_child(hv)
	var account: bool = _lobby != null and int(_lobby.session.get("guest", 1)) == 0
	if not is_you and account and not friend_ids.has(str(sl.id)):
		var add := MenuStyle.button(tr("HUD_FRIENDS_PLUS"), func() -> void:
			friend_ids.append(str(sl.id))
			_lobby.request(AccountCodec.OP_FRIEND_REQUEST, {"username": "", "id": str(sl.id)})
			add_friend_requested.emit(str(sl.id), str(sl.name))
			_local_line(tr("HUD_FRIENDS_REQUEST_SENT"))
			_refresh_state(), false, 28)
		add.tooltip_text = tr("HUD_LOBBY_ADD_FRIEND")
		add.custom_minimum_size.x = 28
		add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(add)
	if not is_you:
		var id := str(sl.id)
		var nm_s := str(sl.name)
		var muted := moderation.is_muted(id)
		var mute := MenuStyle.button(tr("HUD_LOBBY_UNMUTE") if muted else tr("HUD_LOBBY_MUTE"), func() -> void:
			if moderation.is_muted(id):
				moderation.unmute(id)
			else:
				moderation.mute(id, nm_s)
			_refresh_state(), false, 28)
		mute.add_theme_font_size_override("font_size", 11)
		mute.tooltip_text = tr("HUD_LOBBY_MUTE_TIP")
		mute.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(mute)
		if account:
			var blk := MenuStyle.button(tr("HUD_FRIENDS_BLOCK"), func() -> void:
				moderation.mute(id, nm_s)
				_lobby.request(AccountCodec.OP_BLOCK, {"id": id})
				_local_line(tr("HUD_LOBBY_BLOCKED") % nm_s)
				_refresh_state(), false, 28)
			blk.add_theme_font_size_override("font_size", 11)
			blk.tooltip_text = tr("HUD_LOBBY_BLOCK_TIP")
			blk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(blk)
	return card


## A line only this client sees (e.g. a report confirmation).
func _local_line(text: String) -> void:
	if _chat_lines > 0:
		_chat_log.newline()
	_chat_lines += 1
	_chat_log.push_color(HudPalette.TEXT_OFF)
	_chat_log.add_text(text)
	_chat_log.pop()


func _open_row() -> Control:
	var card := MenuStyle.panel_container(Color(0.02, 0.025, 0.05, 0.5), 6)
	var l := MenuStyle.label(tr("HUD_LOBBY_OPEN_SLOT"), 13, HudPalette.TEXT_OFF)
	l.custom_minimum_size.y = 38
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(l)
	return card


func _refresh_state() -> void:
	if _lobby != null and not _lobby.state.is_empty():
		_on_state.call_deferred(_lobby.state)


func _on_chat(c: Dictionary) -> void:
	if int(c.kind) == LobbyCodec.CHAT_PLAYER and moderation.is_muted(str(c.get("id", ""))):
		return  # muted locally
	if _chat_lines > 0:
		_chat_log.newline()
	_chat_lines += 1
	if int(c.kind) == LobbyCodec.CHAT_SYSTEM:
		_chat_log.push_color(HudPalette.TEXT_DIM)
		_chat_log.add_text(system_text(c))
		_chat_log.pop()
		return
	var team := int(c.team)
	_chat_log.push_color(HudPalette.team_color(team) if team <= 1 else HudPalette.TEXT_DIM)
	_chat_log.add_text("■ ")
	_chat_log.pop()
	_chat_log.push_color(PlayerProfile.accent_of(int(c.accent)).lerp(HudPalette.TEXT, 0.3))
	_chat_log.add_text(str(c.name))
	_chat_log.pop()
	_chat_log.add_text(": " + str(c.text))


## Localised text of a system chat line.
static func system_text(c: Dictionary) -> String:
	var code := int(c.code)
	var key: String = SYS_KEYS[code] if code > 0 and code < SYS_KEYS.size() else ""
	if key == "":
		return ""
	var t := TranslationServer.translate(key)
	match code:
		LobbyCodec.SYS_SLOW_DOWN, LobbyCodec.SYS_TEAM_FULL:
			return t
		LobbyCodec.SYS_SWITCHED:
			return t % [str(c.name), TranslationServer.translate("HUD_TEAM_%d" % clampi(int(c.team), 0, 1))]
	return t % str(c.name)


func _on_start(token: int, _team: int, hero_index: int) -> void:
	var h := HeroCatalog.find_index(hero_index)
	var id: String = h.get("stem", hero_id)
	_lobby = null
	start_requested.emit(PackedStringArray(["--connect", "%s:%d" % [_host, _port], "--hero", id,
		"--token", str(token)]))


func _switch_to(team: int) -> void:
	if _lobby != null:
		_lobby.switch_team(team)


func _send_pick() -> void:
	if _lobby != null:
		_lobby.pick(_hero_index, _ready_btn.button_pressed)


## Leaves the lobby view; the menu closes or re-uses the connection.
func _cancel(reason: String) -> void:
	_lobby = null
	cancelled.emit(reason)
