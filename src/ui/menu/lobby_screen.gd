class_name LobbyScreen
extends VBoxContainer
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
const SIDE_RATIO := 1.0
const CENTRE_RATIO := 1.9
const HERO_TILE := 48
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
var _count_max: int = 0
## Column (0 = left / own team, 1 = right) -> lobby team id.
var _col_team: Array[int] = [0, 1]
var _col_cards: Array[UiCard] = []
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
	custom_minimum_size = Vector2(900, 0)
	add_theme_constant_override("separation", t.space_s)
	_build_top(t)
	var wrap := MarginContainer.new()
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(wrap)
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", t.space_l)
	wrap.add_child(mid)
	mid.add_child(_build_team(0))
	mid.add_child(_build_centre(t))
	mid.add_child(_build_team(1))
	_build_final(wrap, t)
	_build_bottom(t)
	_show_hero(_hero_index)


func _build_top(t: UiKitTokens) -> void:
	var row := HBoxContainer.new()
	add_child(row)
	var left := UiKit.label(address, &"caption", t.text_off)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	left.clip_text = true
	row.add_child(left)
	var centre := VBoxContainer.new()
	centre.add_theme_constant_override("separation", 2)
	centre.custom_minimum_size.x = 380
	row.add_child(centre)
	_title = UiKit.label("", &"title", Color(0, 0, 0, 0), HORIZONTAL_ALIGNMENT_CENTER)
	centre.add_child(_title)
	_sub = UiKit.label("", &"small", t.text_dim, HORIZONTAL_ALIGNMENT_CENTER)
	centre.add_child(_sub)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.custom_minimum_size = Vector2(380, 8)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var track := UiKit.panel_box(t.panel_sunken, 0, t.line_strong)
	_bar.add_theme_stylebox_override("background", track)
	_bar_fill = UiKit.panel_box(t.accent, 0, t.accent_hi)
	_bar.add_theme_stylebox_override("fill", _bar_fill)
	centre.add_child(_bar)
	_status = UiKit.label("", &"small", t.warn, HORIZONTAL_ALIGNMENT_RIGHT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_status)
	_set_title(LobbyCodec.PHASE_WAITING, false)


func _build_team(col: int) -> Control:
	var t := UiKit.tokens()
	var card := UiKit.card(tr("HUD_LOBBY_YOUR_TEAM" if col == 0 else "HUD_LOBBY_ENEMY_TEAM").to_upper(), 8)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = SIDE_RATIO
	card.custom_minimum_size.x = 150
	var head := HBoxContainer.new()
	card.body.add_child(head)
	var count := UiKit.label("", &"small", t.text_dim)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(count)
	var sw := UiKit.button(tr("HUD_LOBBY_SWITCH"), func() -> void: _switch_to(_col_team[col]), &"secondary", 24)
	sw.add_theme_font_size_override("font_size", 11)
	sw.visible = false
	head.add_child(sw)
	card.body.add_theme_constant_override("separation", t.space_s)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", t.space_s)
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.body.add_child(rows)
	_col_cards.append(card)
	_col_rows.append(rows)
	_col_count.append(count)
	_switch.append(sw)
	return card


func _build_centre(t: UiKitTokens) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = CENTRE_RATIO
	col.add_theme_constant_override("separation", t.space_s)
	# Hero stage: text on the left, the 3D model on the right.
	var stage_row := HBoxContainer.new()
	stage_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_row.add_theme_constant_override("separation", t.space_m)
	col.add_child(stage_row)
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 150
	info.size_flags_stretch_ratio = 0.8
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 2)
	stage_row.add_child(info)
	info.add_child(UiKit.label(tr("HUD_MENU_HERO").to_upper(), &"caption", t.gold))
	_info_name = UiKit.label("", &"title")
	_info_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_info_name)
	_info_role = UiKit.label("", &"small", t.accent_hi)
	info.add_child(_info_role)
	_info_weapon = UiKit.label("", &"caption", t.text_dim)
	info.add_child(_info_weapon)
	_stage = HeroShowcase.new()
	_stage.heroes = HeroCatalog.entries()
	_stage.chrome = false
	_stage.with_model = with_model
	_stage.selected = maxi(0, _entry_pos(_hero_index))
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.size_flags_stretch_ratio = 1.2
	_stage.custom_minimum_size = Vector2(150, 110)
	stage_row.add_child(_stage)
	# Skills.
	var skills := HBoxContainer.new()
	skills.add_theme_constant_override("separation", t.space_s)
	col.add_child(skills)
	for i in 4:
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size = Vector2(60, 78)
		cell.add_theme_stylebox_override("panel", UiKit.panel_box(t.panel_sunken, 6))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		cell.add_child(v)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		v.add_child(head)
		var tag := UiKit.label("", &"caption", t.gold)
		head.add_child(tag)
		var nm := UiKit.label("", &"small", t.text)
		nm.clip_text = true
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(nm)
		var ds := UiKit.label("", &"caption", t.text_dim)
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.custom_minimum_size.x = 50
		ds.custom_minimum_size.y = 30
		ds.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(ds)
		skills.add_child(cell)
		_skill_cells.append({"cell": cell, "tag": tag, "name": nm, "desc": ds})
	col.add_child(_build_grid(t))
	return col


func _build_grid(t: UiKitTokens) -> Control:
	var card := UiKit.card(tr("HUD_LOBBY_HEROES_TITLE").to_upper(), 8)
	_search = UiKit.line_edit(tr("HUD_LOBBY_SEARCH"), 24)
	_search.custom_minimum_size = Vector2(150, 26)
	_search.add_theme_font_size_override("font_size", 12)
	_search.text_changed.connect(func(q: String) -> void:
		_query = q
		_apply_filter())
	card.header_right.add_child(_search)
	var entries := HeroCatalog.entries()
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 0)
	chips.add_theme_constant_override("v_separation", 0)
	card.body.add_child(chips)
	var group := ButtonGroup.new()
	var roles: Array = [""] + LobbyPhase.roles_of(entries)
	for r: String in roles:
		var chip := UiKit.tab_button(tr("HUD_LOBBY_ROLE_ALL") if r == "" else tr(LobbyPhase.role_short_key(r)))
		chip.custom_minimum_size.y = 28
		chip.add_theme_font_size_override("font_size", 12)
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			var box := chip.get_theme_stylebox(st) as StyleBoxFlat
			box.content_margin_left = 7
			box.content_margin_right = 7
		chip.button_group = group
		chip.set_pressed_no_signal(r == "")
		chip.pressed.connect(func() -> void:
			_role_filter = r
			_apply_filter())
		chips.add_child(chip)
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	card.body.add_child(grid)
	for e: Dictionary in entries:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(HERO_TILE, HERO_TILE)
		b.tooltip_text = str(e.name)
		UiKit.swatch_button(b, Color(t.panel_sunken, 0.9))
		var badge := HeroBadge.make(int(e.index), HERO_TILE - 12)
		badge.position = Vector2(6, 6)
		badge.size = Vector2(HERO_TILE - 12, HERO_TILE - 12)
		b.add_child(badge)
		UiSfx.attach(b)
		var idx: int = e.index
		b.pressed.connect(func() -> void:
			_hero_index = idx
			_show_hero(idx)
			_send_pick())
		b.set_pressed_no_signal(idx == _hero_index)
		grid.add_child(b)
		_hero_tiles[idx] = b
	_no_match = UiKit.label(tr("HUD_LOBBY_NO_MATCH"), &"small", t.text_off)
	_no_match.visible = false
	card.body.add_child(_no_match)
	return card


func _build_bottom(t: UiKitTokens) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", t.space_l)
	add_child(row)
	var chat := UiKit.card(tr("HUD_LOBBY_CHAT_TITLE").to_upper(), 6)
	chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat.size_flags_stretch_ratio = SIDE_RATIO
	chat.custom_minimum_size = Vector2(150, 120)
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = false  # player text is never parsed as markup
	_chat_log.scroll_following = true
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.custom_minimum_size = Vector2(0, 48)
	_chat_log.add_theme_font_size_override("normal_font_size", 12)
	_chat_log.add_theme_color_override("default_color", t.text)
	_chat_log.focus_mode = Control.FOCUS_NONE
	chat.body.add_child(_chat_log)
	_chat_in = UiKit.line_edit(tr("HUD_LOBBY_CHAT_HINT"), LobbyCodec.CHAT_MAX_CHARS)
	_chat_in.custom_minimum_size.y = 30
	_chat_in.add_theme_font_size_override("font_size", 12)
	_chat_in.text_submitted.connect(func(txt: String) -> void:
		if _lobby != null:
			_lobby.say(txt)
		_chat_in.text = "")
	chat.body.add_child(_chat_in)
	row.add_child(chat)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_stretch_ratio = CENTRE_RATIO
	centre.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(centre)
	_lock_btn = UiKit.button(tr("HUD_LOBBY_LOCK_IN"), Callable(), &"play", 64)
	_lock_btn.toggle_mode = true
	_lock_btn.custom_minimum_size.x = 320
	_lock_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_lock_btn.toggled.connect(func(_on: bool) -> void: _send_pick())
	centre.add_child(_lock_btn)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = SIDE_RATIO
	right.alignment = BoxContainer.ALIGNMENT_END
	right.custom_minimum_size.x = 150
	var leave := UiKit.button(tr("HUD_LOBBY_LEAVE"), func() -> void: _cancel(""), &"danger", 40)
	right.add_child(leave)
	row.add_child(right)


## The finalization overlay (both teams' heroes), hidden until PHASE_LOCKED.
func _build_final(wrap: Control, t: UiKitTokens) -> void:
	_final = PanelContainer.new()
	_final.add_theme_stylebox_override("panel", UiKit.panel_box(Color(t.bg_deep, 0.97), 16, Color(t.gold, 0.5)))
	_final.visible = false
	_final.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_final_row = HBoxContainer.new()
	_final_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_final_row.add_theme_constant_override("separation", 48)
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
		var card := _slot_card(sl, i == you)
		_cards[str(sl.id)] = card
		_col_rows[c].add_child(card)
	for c in 2:
		for k in range(counts[c], team_size):
			_col_rows[c].add_child(_open_card())
		var team: int = _col_team[c]
		_col_count[c].text = "%s  %d/%d" % [tr("HUD_TEAM_%d" % team), counts[c], team_size]
		_col_count[c].add_theme_color_override("font_color", HudPalette.TEAM_COLORS[0][team])
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
	_title.add_theme_color_override("font_color", t.gold if LobbyPhase.has_timer(phase) else t.text)


func _update_timer(s: Dictionary, slots: Array) -> void:
	var t := UiKit.tokens()
	var phase := int(s.phase)
	if LobbyPhase.has_timer(phase):
		var secs := int(s.countdown)
		_count_max = maxi(_count_max, secs)
		_sub.text = tr("HUD_LOBBY_COUNTDOWN_SUB") % secs
		var fill_col: Color = t.warn if secs <= LobbyPhase.WARN_S else t.accent
		_bar_fill.bg_color = fill_col
		_bar_fill.border_color = fill_col.lightened(0.3)
		var target := LobbyPhase.bar_fill(maxi(secs - 1, 0), _count_max)
		_bar.value = LobbyPhase.bar_fill(secs, _count_max)
		UiKit.animate(self, _bar, "value", target, 1000)
	else:
		_count_max = 0
		_bar.value = 0.0
		_sub.text = "%s  ·  %s" % [tr("HUD_LOBBY_WAIT_ALL"),
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
		_info_weapon.text = ""
		for c in _skill_cells:
			(c.cell as Control).modulate.a = 0.0
		return
	var stem := str(h.stem)
	_info_name.text = str(h.name).to_upper()
	_info_role.text = tr(LobbyPhase.role_key(stem))
	var def := _def_of(stem)
	var weapon := def.weapon.display_name if def != null and def.weapon != null else "-"
	_info_weapon.text = "%s: %s" % [tr("HUD_SHOWCASE_WEAPON"), weapon]
	_stage.select(_entry_pos(index), false)
	for i in _skill_cells.size():
		var c: Dictionary = _skill_cells[i]
		var skill: SkillDef = def.skills[i] if def != null and i < def.skills.size() else null
		(c.cell as Control).modulate.a = 1.0 if skill != null else 0.0
		if skill == null:
			continue
		(c.tag as Label).text = tr("HUD_LOBBY_SKILL_ULT") if skill.ultimate else "S%d" % (i + 1)
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

func _slot_card(sl: Dictionary, is_you: bool) -> Control:
	var t := UiKit.tokens()
	var connected: bool = sl.connected
	var ready: bool = sl.ready
	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = SLOT_MIN_H
	var team_col: Color = HudPalette.TEAM_COLORS[0][clampi(int(sl.team), 0, 1)]
	var bg := Color(t.panel_raised, 0.98) if is_you else Color(t.panel_sunken, 0.9)
	var border: Color = t.gold if ready else (t.accent_hi if is_you else t.line)
	var sb := UiKit.panel_box(bg, 8, border)
	sb.border_width_left = 4
	sb.border_color = border
	if ready or is_you:
		sb.set_border_width_all(2)
		sb.border_width_left = 4
	card.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", t.space_s)
	col.add_child(row)
	var badge := HeroBadge.make(int(sl.hero_index), 46.0)
	badge.dim = not ready
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	var em := EmblemIcon.make(int(sl.emblem), int(sl.accent), 18.0)
	em.dim = not connected
	name_row.add_child(em)
	var nm := UiKit.label(str(sl.name), &"body", t.text if connected else t.text_off)
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(nm)
	names.add_child(name_row)
	var sub := "#" + PlayerProfile.tag_of(str(sl.id))
	if is_you:
		sub += "  ·  " + tr("HUD_LOBBY_YOU")
	var tag_l := UiKit.label(sub, &"caption", t.text_off)
	tag_l.clip_text = true
	names.add_child(tag_l)
	var hero := HeroCatalog.find_index(int(sl.hero_index))
	var hero_row := HBoxContainer.new()
	hero_row.add_theme_constant_override("separation", 6)
	var hl := UiKit.label(str(hero.get("name", tr("HUD_LOBBY_NO_HERO"))), &"small",
		t.text if ready else t.text_dim)
	hl.clip_text = true
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_row.add_child(hl)
	names.add_child(hero_row)
	var state_key := "HUD_LOBBY_STATE_LOCKED" if ready else "HUD_LOBBY_STATE_PICKING"
	var state_col: Color = t.gold if ready else t.text_off
	if not connected:
		state_key = "HUD_LOBBY_STATE_RECONNECTING"
		state_col = t.warn
	names.add_child(UiKit.label("● " + tr(state_key), &"caption", state_col))
	row.add_child(names)
	if not is_you:
		var acts := VBoxContainer.new()
		acts.add_theme_constant_override("separation", 0)
		acts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_add_actions(acts, sl)
		row.add_child(acts)
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
	hov.bg_color = Color(t.accent, 0.25)
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, idle)
	for st in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hov)
	b.add_theme_stylebox_override("focus", UiKit.focus_box())
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", t.text_dim)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
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


func _open_card() -> Control:
	var t := UiKit.tokens()
	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = SLOT_MIN_H
	card.add_theme_stylebox_override("panel", UiKit.panel_box(Color(t.panel_sunken, 0.45), 8, Color(t.line, 0.1)))
	var l := UiKit.label(tr("HUD_LOBBY_BOT_FILL"), &"small", t.text_off, HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(l)
	return card


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
	card.modulate = Color(2.4, 1.9, 1.2)
	card.scale = Vector2(1.06, 1.06)
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
		r.add_child(HeroBadge.make(int(sl.hero_index), 64.0))
		var v := VBoxContainer.new()
		v.layout_direction = Control.LAYOUT_DIRECTION_LTR
		v.add_child(UiKit.label(str(HeroCatalog.find_index(int(sl.hero_index)).get("name", "?")).to_upper(), &"heading"))
		v.add_child(UiKit.label(str(sl.name), &"small", t.text_dim))
		r.add_child(v)
		cols[c].add_child(r)
	_final_row.add_child(cols[0])
	_final_row.add_child(UiKit.label(tr("HUD_LOBBY_VS"), &"display", t.gold))
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
	_chat_log.push_color(HudPalette.TEXT_OFF)
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
		_lobby.pick(_hero_index, _lock_btn.button_pressed)


## Leaves the lobby view; the menu closes or re-uses the connection.
func _cancel(reason: String) -> void:
	_lobby = null
	cancelled.emit(reason)
