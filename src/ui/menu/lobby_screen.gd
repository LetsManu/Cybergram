class_name LobbyScreen
extends Control
## Online lobby view, League-style champ select (W12-L2, design/ux/ui-kit.md
## §8.2): phase title + countdown bar on top, your team's tall slot cards on the
## left and the enemy team on the right, the selected hero (3D stage, role,
## weapon, four skills) and a searchable / role-filtered hero grid in the
## centre, team chat bottom left and a big LOCK IN button bottom centre. When
## everyone has locked, a short finalization overlay shows both teams' heroes.
## SWITCH TEAM when the other side has room; leave; friends docking.
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
## Side column : centre column width ratio (the bottom row uses the same).
const HERO_TILE := 56
const SLOT_MIN_H := 60

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
## Render the 3D hero stage (tests / headless may turn it off).
var with_model: bool = DisplayServer.get_name() != "headless"

var _lobby: LobbyClient
var _host: String = ""
var _port: int = ENetTransport.DEFAULT_PORT
var _waited: float = 0.0
var _status: Label
var _title: Label
var _sub: Label
var _bar: ProgressBar
var _bar_fill: StyleBoxFlat
var _timer: Label
var _count_max: int = 0
## Column (0 = left / own team, 1 = right) -> lobby team id.
var _col_team: Array[int] = [0, 1]
var _col_rows: Array[VBoxContainer] = []
var _col_count: Array[Label] = []
var _switch: Array[Button] = []
var _hero_tiles: Dictionary = {}  # ContentDB index -> Button
var _hero_index: int = 0
var _stage: HeroShowcase
var _info_name: Label
var _info_role: Label
var _info_weapon: Label
var _skill_cells: Array[Dictionary] = []
var _search: LineEdit
var _role_filter: String = ""
var _query: String = ""
var _no_match: Label
var _lock_btn: Button
var _final: PanelContainer
var _final_row: HBoxContainer
var _chat_log: RichTextLabel
var _chat_in: LineEdit
var _chat_lines: int = 0
var _prev_ready: Dictionary = {}  # player id -> was locked in
var _cards: Dictionary = {}  # player id -> slot card
var _last_slots: Array = []
var _phase: int = LobbyCodec.PHASE_WAITING
var _final_shown: bool = false


func _ready() -> void:
	HudStrings.ensure_loaded()
	if moderation == null:
		moderation = LocalModeration.shared()
	var h := HeroCatalog.find_stem(hero_id)
	_hero_index = int(h.get("index", 0))
	_build()
	var hp := address.rsplit(":", true, 1)
	_host = hp[0]
	if hp.size() == 2 and hp[1].is_valid_int():
		_port = clampi(hp[1].to_int(), 1, 65535)
	_status.text = tr("HUD_LOBBY_JOINING")
	_open()
	_lock_btn.grab_focus.call_deferred()


# --- layout -----------------------------------------------------------------

func _build() -> void:
	var t := UiKit.tokens()
	theme = UiKit.theme()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP  # the lobby owns the screen
	var bg := UiKit.background()
	UiKit.set_background_layout(bg, 720.0, Vector2(720, 390), 300.0, false)
	if bg.material != null:
		(bg.material as ShaderMaterial).set_shader_parameter("spot_alpha", 0.16)
	add_child(bg)
	_build_centre(t)
	_build_top(t)
	_team_box(0)
	_team_box(1)
	_build_abilities(t)
	_build_bottom(t)
	_build_grid(t)
	_build_final(self, t)
	_show_hero(_hero_index)


## Header: leave link (left), phase title + subtitle (centre), countdown
## (right, mono brass), then the hairline progress.
func _build_top(t: UiKitTokens) -> void:
	var leave := Button.new()
	leave.text = "←  " + tr("HUD_LOBBY_LEAVE")
	leave.position = Vector2(40, 22)
	leave.custom_minimum_size.y = 32
	var bare := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		leave.add_theme_stylebox_override(st, bare)
	leave.add_theme_stylebox_override("focus", UiKit.focus_box())
	leave.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(13, 0.2)))
	leave.add_theme_font_size_override("font_size", 13)
	leave.add_theme_color_override("font_color", t.text_dim)
	leave.add_theme_color_override("font_hover_color", t.text)
	leave.add_theme_color_override("font_focus_color", t.text)
	leave.pressed.connect(func() -> void: _cancel(""))
	UiSfx.attach(leave)
	add_child(leave)
	var centre := VBoxContainer.new()
	centre.set_anchors_preset(Control.PRESET_CENTER_TOP)
	centre.offset_left = -400
	centre.offset_right = 400
	centre.offset_top = 22
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.add_theme_constant_override("separation", 6)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(26, 0.22)))
	_title.add_theme_font_size_override("font_size", 26)
	centre.add_child(_title)
	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", 13)
	_sub.add_theme_color_override("font_color", t.text_dim)
	centre.add_child(_sub)
	_timer = Label.new()
	_timer.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer.offset_left = -200
	_timer.offset_right = -40
	_timer.offset_top = 22
	_timer.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer.add_theme_font_override("font", UiKit.mono_font())
	_timer.add_theme_font_size_override("font_size", 26)
	_timer.add_theme_color_override("font_color", t.accent)
	add_child(_timer)
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_status.offset_left = -360
	_status.offset_right = -40
	_status.offset_top = 96
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", t.warn)
	add_child(_status)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_left = 40
	_bar.offset_right = -40
	_bar.offset_top = 87
	_bar.offset_bottom = 89
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0)
	track.border_color = t.line
	track.border_width_bottom = 1
	_bar.add_theme_stylebox_override("background", track)
	_bar_fill = StyleBoxFlat.new()
	_bar_fill.bg_color = t.accent
	_bar.add_theme_stylebox_override("fill", _bar_fill)
	add_child(_bar)
	_set_title(LobbyCodec.PHASE_WAITING, false)


## A team column (0 = yours, left; 1 = enemy, right-aligned): header line
## with the switch link, then slot rows.
func _team_box(col: int) -> void:
	var t := UiKit.tokens()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	box.custom_minimum_size.x = 300
	if col == 0:
		box.position = Vector2(40, 124)
		box.size.x = 300
	else:
		box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		box.offset_left = -340
		box.offset_right = -40
		box.offset_top = 124
		box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.alignment = BoxContainer.ALIGNMENT_BEGIN if col == 0 else BoxContainer.ALIGNMENT_END
	box.add_child(head)
	var count := Label.new()
	count.add_theme_font_override("font", _caps(11, 0.22))
	count.add_theme_font_size_override("font_size", 11)
	count.add_theme_color_override("font_color", t.accent if col == 0 else t.text_dim)
	var sw := _link_button(tr("HUD_LOBBY_SWITCH"), "", func() -> void: _switch_to(_col_team[col]))
	sw.visible = false
	if col == 0:
		head.add_child(count)
		head.add_child(sw)
	else:
		head.add_child(sw)
		head.add_child(count)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 22)
	box.add_child(rows)
	_col_rows.append(rows)
	_col_count.append(count)
	_switch.append(sw)


## Body-face caps label font with `em` tracking at `size` px.
static func _caps(size: int, em: float) -> Font:
	var f := UiKit.body_font(600).duplicate() as FontVariation
	f.spacing_glyph = UiKit.track(size, em)
	return f


# --- W17B-UI --- the matchmaking pick screens share the lobby's caption face.
## Public alias of _caps() (body-face caps, `em` tracking at `size` px).
static func caps_font(size: int, em: float) -> Font:
	return _caps(size, em)
# --- end W17B-UI ---


## The centred hero (live model on a warm spotlight) and its eyebrow + name.
func _build_centre(t: UiKitTokens) -> void:
	_stage = HeroShowcase.new()
	_stage.heroes = HeroCatalog.entries()
	_stage.chrome = false
	_stage.with_model = with_model
	_stage.selected = maxi(0, _entry_pos(_hero_index))
	_stage.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_stage.offset_left = -202
	_stage.offset_right = 202
	_stage.offset_top = 64
	_stage.offset_bottom = 624
	_stage.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_stage)
	var info := VBoxContainer.new()
	info.set_anchors_preset(Control.PRESET_CENTER_TOP)
	info.offset_left = -340
	info.offset_right = 340
	info.offset_top = 588
	info.grow_horizontal = Control.GROW_DIRECTION_BOTH
	info.add_theme_constant_override("separation", 2)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info)
	_info_role = Label.new()
	_info_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_role.add_theme_font_override("font", _caps(12, 0.24))
	_info_role.add_theme_font_size_override("font_size", 12)
	_info_role.add_theme_color_override("font_color", t.accent)
	info.add_child(_info_role)
	_info_name = Label.new()
	_info_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_name.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(34, 0.06)))
	_info_name.add_theme_font_size_override("font_size", 34)
	info.add_child(_info_name)
	_info_weapon = _info_role  # the eyebrow carries role and weapon


## Abilities list (right, above LOCK IN): key chip, name, one-line description.
func _build_abilities(t: UiKitTokens) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -360
	box.offset_right = -40
	box.offset_top = 470
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var head := Label.new()
	head.text = tr("HUD_LOBBY_ABILITIES")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_theme_font_override("font", _caps(11, 0.22))
	head.add_theme_font_size_override("font_size", 11)
	head.add_theme_color_override("font_color", t.text_dim)
	box.add_child(head)
	for i in 4:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 12)
		var tag := UiKit.key_chip(HeroShowcase.skill_key(i))
		tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		cell.add_child(tag)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(v)
		var nm := Label.new()
		nm.add_theme_font_override("font", UiKit.body_font(500))
		nm.add_theme_font_size_override("font_size", 14)
		v.add_child(nm)
		var ds := Label.new()
		ds.add_theme_font_size_override("font_size", 12)
		ds.add_theme_color_override("font_color", t.text_dim)
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.custom_minimum_size.x = 260
		v.add_child(ds)
		box.add_child(cell)
		_skill_cells.append({"cell": cell, "tag": tag, "name": nm, "desc": ds})


## The portrait picker row (centre bottom) plus a quiet search / role filter.
func _build_grid(t: UiKitTokens) -> void:
	var entries := HeroCatalog.entries()
	var grid := HBoxContainer.new()
	grid.set_anchors_preset(Control.PRESET_CENTER_TOP)
	grid.offset_left = -340
	grid.offset_right = 340
	grid.offset_top = 672
	grid.offset_bottom = 728
	grid.grow_horizontal = Control.GROW_DIRECTION_BOTH
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("separation", 14)
	add_child(grid)
	for e: Dictionary in entries:
		var b := HeroShowcase.thumb_button(int(e.index), HERO_TILE)
		b.tooltip_text = str(e.name)
		var idx: int = e.index
		b.pressed.connect(func() -> void:
			_hero_index = idx
			_show_hero(idx)
			_send_pick())
		b.set_pressed_no_signal(idx == _hero_index)
		grid.add_child(b)
		_hero_tiles[idx] = b
	var filt := HBoxContainer.new()
	filt.set_anchors_preset(Control.PRESET_CENTER_TOP)
	filt.offset_left = -340
	filt.offset_right = 340
	filt.offset_top = 742
	filt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	filt.alignment = BoxContainer.ALIGNMENT_CENTER
	filt.add_theme_constant_override("separation", 4)
	add_child(filt)
	var glass := UiIcon.make(&"search", 13.0, t.text_off)
	glass.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	filt.add_child(glass)
	_search = UiKit.line_edit(tr("HUD_LOBBY_SEARCH"), 24)
	_search.custom_minimum_size = Vector2(130, 26)
	_search.add_theme_font_size_override("font_size", 12)
	_search.text_changed.connect(func(q: String) -> void:
		_query = q
		_apply_filter())
	filt.add_child(_search)
	var group := ButtonGroup.new()
	var roles: Array = [""] + LobbyPhase.roles_of(entries)
	for r: String in roles:
		var chip := UiKit.tab_button(tr("HUD_LOBBY_ROLE_ALL") if r == "" else tr(LobbyPhase.role_short_key(r)))
		chip.custom_minimum_size.y = 26
		chip.add_theme_font_override("font", _caps(11, 0.12))
		chip.add_theme_font_size_override("font_size", 11)
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			var box := chip.get_theme_stylebox(st) as StyleBoxFlat
			box.content_margin_left = 6
			box.content_margin_right = 6
		chip.button_group = group
		chip.set_pressed_no_signal(r == "")
		chip.pressed.connect(func() -> void:
			_role_filter = r
			_apply_filter())
		filt.add_child(chip)
	_no_match = UiKit.label(tr("HUD_LOBBY_NO_MATCH"), &"small", t.text_off, HORIZONTAL_ALIGNMENT_CENTER)
	_no_match.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_no_match.offset_left = -340
	_no_match.offset_right = 340
	_no_match.offset_top = 688
	_no_match.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_no_match.visible = false
	add_child(_no_match)


## Team chat (bottom left, no box) and the brass LOCK IN (bottom right).
func _build_bottom(t: UiKitTokens) -> void:
	var chat := VBoxContainer.new()
	chat.position = Vector2(40, 560)
	chat.size = Vector2(320, 0)
	chat.custom_minimum_size.x = 320
	chat.add_theme_constant_override("separation", 10)
	add_child(chat)
	var head := Label.new()
	head.text = tr("HUD_LOBBY_CHAT_TITLE").to_upper()
	head.add_theme_font_override("font", _caps(11, 0.22))
	head.add_theme_font_size_override("font_size", 11)
	head.add_theme_color_override("font_color", t.text_dim)
	chat.add_child(head)
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = false  # player text is never parsed as markup
	_chat_log.scroll_following = true
	_chat_log.custom_minimum_size = Vector2(320, 92)
	_chat_log.add_theme_font_size_override("normal_font_size", 13)
	_chat_log.add_theme_constant_override("line_separation", 6)
	_chat_log.add_theme_color_override("default_color", t.text_dim)
	_chat_log.focus_mode = Control.FOCUS_NONE
	_chat_log.get_v_scroll_bar().modulate.a = 0.0  # wheel still scrolls; no bar in the look
	chat.add_child(_chat_log)
	_chat_in = UiKit.line_edit(tr("HUD_LOBBY_CHAT_HINT"), LobbyCodec.CHAT_MAX_CHARS)
	_chat_in.custom_minimum_size.y = 30
	_chat_in.add_theme_font_size_override("font_size", 13)
	_chat_in.text_submitted.connect(func(txt: String) -> void:
		if _lobby != null:
			_lobby.say(txt)
		_chat_in.text = "")
	chat.add_child(_chat_in)
	_lock_btn = UiKit.button(tr("HUD_LOBBY_LOCK_IN"), Callable(), &"play", 52)
	_lock_btn.toggle_mode = true
	_lock_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_lock_btn.offset_left = -360
	_lock_btn.offset_right = -40
	_lock_btn.offset_top = -86
	_lock_btn.offset_bottom = -34
	_lock_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_lock_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_lock_btn.add_theme_font_override("font", UiKit.display_font(700, UiKit.track(18, 0.24)))
	(_lock_btn.get_theme_stylebox("normal") as UiBevelBox).bevel = 12
	# Locked in: hairline-grey fill, pale brass text (mockup lockBg / lockFg).
	for st in ["pressed", "hover_pressed"]:
		var sb := (_lock_btn.get_theme_stylebox(st) as UiBevelBox).duplicate() as UiBevelBox
		sb.fill = t.line_strong
		sb.fill_hover = t.line_strong.lightened(0.08)
		sb.bevel = 12
		_lock_btn.add_theme_stylebox_override(st, sb)
	_lock_btn.add_theme_color_override("font_pressed_color", t.accent_hi)
	_lock_btn.add_theme_color_override("font_hover_pressed_color", t.accent_hi)
	_lock_btn.toggled.connect(func(_on: bool) -> void: _send_pick())
	add_child(_lock_btn)


## The finalization overlay (both teams' heroes), hidden until PHASE_LOCKED.
func _build_final(wrap: Control, t: UiKitTokens) -> void:
	_final = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(t.bg_deep, 0.96)
	_final.add_theme_stylebox_override("panel", sb)
	_final.set_anchors_preset(Control.PRESET_FULL_RECT)
	_final.offset_top = 100
	_final.visible = false
	_final.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_final_row = HBoxContainer.new()
	_final_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_final_row.add_theme_constant_override("separation", 64)
	_final.add_child(_final_row)
	wrap.add_child(_final)


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








# --- state ------------------------------------------------------------------

func _on_state(s: Dictionary) -> void:
	if auto_ready and not _lock_btn.button_pressed:
		_lock_btn.button_pressed = true  # toggled -> _send_pick()
	var you: int = s.you
	var slots: Array = s.slots
	var team_size: int = maxi(1, int(s.team_size))
	var own: Dictionary = slots[you] if you < slots.size() else {}
	roster_seen.emit(slots)
	_phase = int(s.phase)
	_last_slots = slots
	var own_team := int(own.get("team", 0))
	_col_team = [own_team, 1 - own_team]
	var flashes := LobbyPhase.newly_locked(_prev_ready, slots)
	_cards.clear()
	var counts := [0, 0]
	for c in 2:
		for n in _col_rows[c].get_children():
			_col_rows[c].remove_child(n)
			n.queue_free()
	for i in slots.size():
		var sl: Dictionary = slots[i]
		var c := 0 if clampi(int(sl.team), 0, 1) == _col_team[0] else 1
		counts[c] += 1
		var card := _slot_card(sl, i == you, c == 1)
		_cards[str(sl.id)] = card
		_col_rows[c].add_child(card)
	for c in 2:
		for k in range(counts[c], team_size):
			_col_rows[c].add_child(_open_card(c == 1))
		var team: int = _col_team[c]
		_col_count[c].text = ("%s  ·  %s" % [tr("HUD_LOBBY_YOUR_TEAM" if c == 0 else "HUD_LOBBY_ENEMY_TEAM"),
			tr("HUD_TEAM_%d" % team)]).to_upper()
		_switch[c].visible = c == 1 and own_team >= 0 and _phase != LobbyCodec.PHASE_LOCKED \
			and _phase != LobbyCodec.PHASE_IN_MATCH
		_switch[c].disabled = counts[c] >= team_size
	var locked: bool = _phase == LobbyCodec.PHASE_LOCKED
	var own_ready: bool = own.get("ready", false)
	_lock_btn.set_pressed_no_signal(own_ready)
	_lock_btn.tooltip_text = tr("HUD_LOBBY_LOCKED_CANCEL_TIP") if own_ready and not locked else ""
	_lock_btn.disabled = locked or (_hero_index == 0 and not own_ready)
	_lock_btn.text = tr("HUD_LOBBY_LOCKED") if locked else (tr("HUD_LOBBY_LOCKED_CANCEL") if own_ready \
		else (tr("HUD_LOBBY_LOCK_IN") if _hero_index != 0 else tr("HUD_LOBBY_PICK_TO_LOCK")))
	if not own.is_empty() and int(own.hero_index) != 0 and int(own.hero_index) != _hero_index:
		_hero_index = int(own.hero_index)
		_show_hero(_hero_index)
	for idx in _hero_tiles:
		var b: Button = _hero_tiles[idx]
		b.set_pressed_no_signal(idx == _hero_index)
		b.disabled = own_ready or locked
	_set_title(_phase, own_ready)
	_update_timer(s, slots)
	_status.text = ""
	for sl: Dictionary in slots:
		if not sl.connected:
			_status.text = tr("HUD_LOBBY_RECONNECTING")
	for id in flashes:
		_flash(str(id))
	if not flashes.is_empty():
		UiSfx.play(&"lock")
	_prev_ready = {}
	for sl: Dictionary in slots:
		_prev_ready[str(sl.id)] = bool(sl.ready)
	if locked and not _final_shown:
		_final_shown = true
		_show_final(slots)
	elif not locked and _final_shown:
		_final_shown = false
		_final.visible = false


func _set_title(phase: int, own_ready: bool) -> void:
	var t := UiKit.tokens()
	_title.text = tr(LobbyPhase.title_key(phase, own_ready)).to_upper()
	_title.add_theme_color_override("font_color", t.text)


func _update_timer(s: Dictionary, slots: Array) -> void:
	var t := UiKit.tokens()
	var phase := int(s.phase)
	var where := "%s  ·  %s" % [tr("HUD_LOBBY_MODE_LINE"), _host if _host != "" else address]
	if LobbyPhase.has_timer(phase):
		var secs := int(s.countdown)
		_count_max = maxi(_count_max, secs)
		_sub.text = "%s  ·  %s" % [where, tr("HUD_LOBBY_COUNTDOWN_SUB") % secs]
		_timer.text = "%d:%02d" % [secs / 60, secs % 60]
		_timer.add_theme_color_override("font_color", t.warn if secs <= LobbyPhase.WARN_S else t.accent)
		_bar_fill.bg_color = t.warn if secs <= LobbyPhase.WARN_S else t.accent
		var target := LobbyPhase.bar_fill(maxi(secs - 1, 0), _count_max)
		_bar.value = LobbyPhase.bar_fill(secs, _count_max)
		UiKit.animate(self, _bar, "value", target, 1000)
	else:
		_count_max = 0
		_bar.value = 0.0
		_timer.text = ""
		_sub.text = "%s  ·  %s  ·  %s" % [where, tr("HUD_LOBBY_WAIT_ALL"),
			tr("HUD_LOBBY_WAIT_COUNT") % [LobbyPhase.locked_count(slots), slots.size()]]


# --- hero display -----------------------------------------------------------

func _entry_pos(index: int) -> int:
	var entries := HeroCatalog.entries()
	for i in entries.size():
		if int(entries[i].index) == index:
			return i
	return -1


func _def_of(stem: String) -> HeroDef:
	var p := "%s/hero_%s.tres" % [HeroShowcase.HERO_DIR, stem]
	return load(p) as HeroDef if ResourceLoader.exists(p) else null


## Shows the hero with ContentDB `index` in the stage, info and skill cells.
func _show_hero(index: int) -> void:
	var h := HeroCatalog.find_index(index)
	for k in _hero_tiles:
		(_hero_tiles[k] as Button).set_pressed_no_signal(k == index)
	if h.is_empty():
		_info_name.text = tr("HUD_LOBBY_NO_HERO")
		_info_role.text = ""
		for c in _skill_cells:
			(c.cell as Control).modulate.a = 0.0
		return
	var stem := str(h.stem)
	_info_name.text = str(h.name).to_upper()
	var def := _def_of(stem)
	_info_role.text = HeroShowcase.eyebrow_text(stem, def)
	_stage.select(_entry_pos(index), false)
	for i in _skill_cells.size():
		var c: Dictionary = _skill_cells[i]
		var skill: SkillDef = def.skills[i] if def != null and i < def.skills.size() else null
		(c.cell as Control).modulate.a = 1.0 if skill != null else 0.0
		if skill == null:
			continue
		(c.name as Label).text = skill.display_name
		(c.desc as Label).text = tr(LobbyPhase.skill_desc_key(skill))
	UiKit.transition_in(_info_name.get_parent(), Vector2.ZERO)


func _apply_filter() -> void:
	var shown := LobbyPhase.filter_heroes(HeroCatalog.entries(), _query, _role_filter)
	var ids := {}
	for e: Dictionary in shown:
		ids[int(e.index)] = true
	for k in _hero_tiles:
		(_hero_tiles[k] as Button).visible = ids.has(k)
	_no_match.visible = shown.is_empty()


# --- slot cards -------------------------------------------------------------

func _slot_card(sl: Dictionary, is_you: bool, right := false) -> Control:
	var t := UiKit.tokens()
	var connected: bool = sl.connected
	var ready: bool = sl.ready
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	if right:
		row.layout_direction = Control.LAYOUT_DIRECTION_RTL
	card.add_child(row)
	var ring := t.accent if ready else t.cyan
	if not connected:
		ring = t.warn
	var badge := HeroBadge.make(int(sl.hero_index), 60.0, ring)
	badge.ring_width = 2.0
	badge.dim = not connected
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var names := VBoxContainer.new()
	names.layout_direction = Control.LAYOUT_DIRECTION_LTR
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	var align := HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	var nm := Label.new()
	nm.text = str(sl.name) + ("  (%s)" % tr("HUD_LOBBY_YOU").to_lower() if is_you else "")
	nm.horizontal_alignment = align
	nm.add_theme_font_override("font", UiKit.body_font(600))
	nm.add_theme_font_size_override("font_size", 16)
	nm.add_theme_color_override("font_color", t.text if connected else t.text_off)
	nm.clip_text = true
	nm.tooltip_text = "#" + PlayerProfile.tag_of(str(sl.id))
	nm.mouse_filter = Control.MOUSE_FILTER_PASS
	names.add_child(nm)
	var hero := HeroCatalog.find_index(int(sl.hero_index))
	var hl := Label.new()
	hl.text = str(hero.get("name", tr("HUD_LOBBY_NO_HERO")))
	hl.horizontal_alignment = align
	hl.add_theme_font_size_override("font_size", 13)
	hl.add_theme_color_override("font_color", t.text_dim)
	hl.clip_text = true
	names.add_child(hl)
	var state_key := "HUD_LOBBY_STATE_LOCKED" if ready else "HUD_LOBBY_STATE_PICKING"
	var state_col: Color = t.accent if ready else t.cyan
	if not connected:
		state_key = "HUD_LOBBY_STATE_RECONNECTING"
		state_col = t.warn
	var state_row := HBoxContainer.new()
	state_row.add_theme_constant_override("separation", 10)
	state_row.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	var stl := Label.new()
	stl.text = tr(state_key).to_upper()
	stl.add_theme_font_override("font", _caps(11, 0.18))
	stl.add_theme_font_size_override("font_size", 11)
	stl.add_theme_color_override("font_color", state_col)
	names.add_child(state_row)
	row.add_child(names)
	if is_you:
		state_row.add_child(stl)
		return card
	# Mute / block / + : quiet links that show on hover or keyboard focus.
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 2)
	_add_actions(acts, sl)
	if right:
		state_row.add_child(acts)
		state_row.add_child(stl)
	else:
		state_row.add_child(stl)
		state_row.add_child(acts)
	acts.modulate.a = 0.0
	var sync := func() -> void:
		if not card.is_inside_tree():
			return
		var on := Rect2(Vector2.ZERO, card.size).has_point(card.get_local_mouse_position())
		for b in acts.get_children():
			on = on or (b as Control).has_focus()
		acts.modulate.a = 1.0 if on else 0.0
	card.mouse_entered.connect(sync)
	card.mouse_exited.connect(sync)
	for b in acts.get_children():
		(b as Control).mouse_entered.connect(sync)
		(b as Control).mouse_exited.connect(sync)
		(b as Control).focus_entered.connect(sync)
		(b as Control).focus_exited.connect(sync)
	return card


## Mute / block / "+" buttons of another player's card.
## Compact text button for the card actions (mute / block / +).
func _link_button(text: String, tip: String, cb: Callable) -> Button:
	var t := UiKit.tokens()
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(0, 0, 0, 0)
	idle.content_margin_left = 4
	idle.content_margin_right = 4
	idle.content_margin_top = 2
	idle.content_margin_bottom = 2
	var hov := idle.duplicate() as StyleBoxFlat
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, idle)
	for st in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hov)
	b.add_theme_stylebox_override("focus", UiKit.focus_box())
	b.add_theme_font_override("font", _caps(11, 0.12))
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", t.text_dim)
	b.add_theme_color_override("font_hover_color", t.accent_hi)
	b.add_theme_color_override("font_focus_color", t.accent_hi)
	b.add_theme_color_override("font_disabled_color", t.text_off)
	UiSfx.attach(b)
	b.pressed.connect(cb)
	return b


func _add_actions(row: Container, sl: Dictionary) -> void:
	var account: bool = _lobby != null and int(_lobby.session.get("guest", 1)) == 0
	var id := str(sl.id)
	var nm_s := str(sl.name)
	var mk := func(text: String, tip: String, cb: Callable) -> Button:
		return _link_button(text, tip, cb)
	if account and not friend_ids.has(id):
		row.add_child(mk.call(tr("HUD_FRIENDS_PLUS"), tr("HUD_LOBBY_ADD_FRIEND"), func() -> void:
			friend_ids.append(id)
			_lobby.request(AccountCodec.OP_FRIEND_REQUEST, {"username": "", "id": id})
			add_friend_requested.emit(id, nm_s)
			_local_line(tr("HUD_FRIENDS_REQUEST_SENT"))
			_refresh_state()))
	var muted := moderation.is_muted(id)
	row.add_child(mk.call(tr("HUD_LOBBY_UNMUTE") if muted else tr("HUD_LOBBY_MUTE"), tr("HUD_LOBBY_MUTE_TIP"),
		func() -> void:
			if moderation.is_muted(id):
				moderation.unmute(id)
			else:
				moderation.mute(id, nm_s)
			_refresh_state()))
	if account:
		row.add_child(mk.call(tr("HUD_FRIENDS_BLOCK"), tr("HUD_LOBBY_BLOCK_TIP"), func() -> void:
			moderation.mute(id, nm_s)
			_lobby.request(AccountCodec.OP_BLOCK, {"id": id})
			_local_line(tr("HUD_LOBBY_BLOCKED") % nm_s)
			_refresh_state()))


func _open_card(right := false) -> Control:
	var t := UiKit.tokens()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.modulate.a = 0.35
	if right:
		row.layout_direction = Control.LAYOUT_DIRECTION_RTL
	var well := UiPortrait.create(null, 60.0, t.line_strong)
	well.ring_width = 1.0
	row.add_child(well)
	var v := VBoxContainer.new()
	v.layout_direction = Control.LAYOUT_DIRECTION_LTR
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	var a := UiKit.label(tr("HUD_LOBBY_OPEN_SLOT"), &"body", t.text,
		HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT)
	a.add_theme_font_override("font", UiKit.body_font(600))
	v.add_child(a)
	var b := UiKit.label(tr("HUD_LOBBY_BOT_FILL"), &"small", t.text_dim,
		HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT)
	v.add_child(b)
	row.add_child(v)
	return row


## Lock-in flash on a player's card (glow + scale pop; instant under reduce motion).
func _flash(id: String) -> void:
	var card: Control = _cards.get(id)
	if card == null or UiKit.reduce_motion():
		return
	await get_tree().process_frame
	if not is_instance_valid(card) or not card.is_inside_tree():
		return
	var t := UiKit.tokens()
	card.pivot_offset = card.size * 0.5
	card.modulate = Color(1.6, 1.4, 1.0)
	card.scale = Vector2(1.04, 1.04)
	UiKit.animate(self, card, "modulate", Color.WHITE, t.motion_slow * 2)
	UiKit.animate(self, card, "scale", Vector2.ONE, t.motion_base)


## Finalization: both teams' heroes over the centre, fading / scaling in.
func _show_final(slots: Array) -> void:
	var t := UiKit.tokens()
	for n in _final_row.get_children():
		_final_row.remove_child(n)
		n.queue_free()
	var cols: Array[VBoxContainer] = []
	for c in 2:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", t.space_m)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		cols.append(v)
	for sl: Dictionary in slots:
		var c := 0 if clampi(int(sl.team), 0, 1) == _col_team[0] else 1
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", t.space_m)
		if c == 1:
			r.layout_direction = Control.LAYOUT_DIRECTION_RTL
		r.add_child(HeroBadge.make(int(sl.hero_index), 72.0, t.accent))
		var v := VBoxContainer.new()
		v.layout_direction = Control.LAYOUT_DIRECTION_LTR
		var hn := UiKit.label(str(HeroCatalog.find_index(int(sl.hero_index)).get("name", "?")).to_upper(), &"heading")
		hn.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(20, 0.06)))
		hn.add_theme_font_size_override("font_size", 20)
		v.add_child(hn)
		v.add_child(UiKit.label(str(sl.name), &"small", t.text_dim))
		r.add_child(v)
		cols[c].add_child(r)
	_final_row.add_child(cols[0])
	var vs := UiKit.label(tr("HUD_LOBBY_VS"), &"display", t.accent)
	vs.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(40, 0.22)))
	vs.add_theme_font_size_override("font_size", 40)
	_final_row.add_child(vs)
	_final_row.add_child(cols[1])
	_final.visible = true
	_final.modulate.a = 0.0
	UiKit.animate(self, _final, "modulate:a", 1.0, t.motion_slow)
	for c in 2:
		cols[c].modulate.a = 0.0
		if UiKit.reduce_motion():
			cols[c].modulate.a = 1.0
			continue
		var tw := create_tween()
		tw.tween_interval(0.12 * c)
		tw.tween_property(cols[c], "modulate:a", 1.0, t.motion_slow / 1000.0)


## A line only this client sees (e.g. a report confirmation).
func _local_line(text: String) -> void:
	if _chat_lines > 0:
		_chat_log.newline()
	_chat_lines += 1
	_chat_log.push_color(UiKit.tokens().text_off)
	_chat_log.add_text(text)
	_chat_log.pop()


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
		_chat_log.push_color(UiKit.tokens().text_off)
		_chat_log.add_text(system_text(c))
		_chat_log.pop()
		return
	var team := int(c.team)
	var own := _col_team[0]
	_chat_log.push_color(UiKit.tokens().cyan if team == own else UiKit.tokens().accent_hi)
	_chat_log.add_text(str(c.name))
	_chat_log.pop()
	_chat_log.add_text("  " + str(c.text))


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
		_lobby.pick(_hero_index, _lock_btn.button_pressed)


## Leaves the lobby view; the menu closes or re-uses the connection.
func _cancel(reason: String) -> void:
	_lobby = null
	cancelled.emit(reason)
