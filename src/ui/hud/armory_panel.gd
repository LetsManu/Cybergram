class_name ArmoryPanel
extends HudWidget
## Armory shop screen (design/ux/hud.md §10), League of Legends / Dota 2 style:
## category tabs + search, item cards (glyph, name, price, owned / maxed,
## "can't afford" dimming), a detail pane (description, per-tier effects and
## prices, damage delta, sell / undo), the recommended build of the hero with
## the next step highlighted, Lumen top right and a purchase toast.
##
## Opens with F or the `open_shop` action (fallback key B) on the HQ Armory pad;
## off the pad B only shows the hint "Return to your Armory pad to buy".
## Keyboard: arrows move, Q/E or PageUp/PageDown switch tabs, Enter buys the
## next tier, 1/2/3 buy that tier, Backspace sells, Ctrl+Z undoes the last
## purchase, R jumps to the recommended item, / or Ctrl+F searches, Esc closes.
## Mouse: click selects, double-click buys, wheel scrolls, buttons and tabs.
## Gamepad: D-pad moves, LB/RB tabs, A buys, X sells, R3 undoes, Y / B close.
## My builds tab (private builds, BuildsViewModel): Enter / A follows a build,
## N / L3 new from the guide, D / R3 duplicate, Delete / X twice deletes,
## C copies and V pastes a build string. In the catalog, + / RT adds the
## focused item to the build in use and - / LT removes it.
## Never mutates state: requests go through PlayerInputSource.request_action
## and the server re-checks every rule (ShopModel holds the pure logic).

const TIER_NAMES := ["", "I", "II", "III"]
## Card columns: 3 when the left side is wide enough, else 2.
const WIDE_CARD_W: float = 270.0
const PAD: float = 20.0
const HEADER_H: float = 68.0
const TAB_Y: float = 76.0
const TAB_H: float = 40.0
const GRID_Y: float = 128.0
const CARD_H: float = 104.0
const GAP: float = 10.0
const FOOTER_H: float = 76.0
const BUILD_H: float = 92.0
const TOAST_LIFE_S: float = 2.5
const HINT_LIFE_S: float = 2.5
const PENDING_TIMEOUT_S: float = 1.5
const SEL_BG := Color(0.2, 0.3, 0.5, 0.75)
const CARD_BG := Color(0.07, 0.09, 0.15, 0.9)
## Localization keys of the stat names shown in the tier table.
const STAT_KEYS := {&"mod_damage": "HUD_STAT_DAMAGE", &"mana_regen": "HUD_STAT_REGEN", &"regen_delay": "HUD_STAT_REGEN_DELAY",
	&"reload_time": "HUD_STAT_RELOAD", &"squad_capacity_bonus": "HUD_STAT_SQUAD", &"wardling_hp_mult": "HUD_STAT_WARDLING_HP",
	&"wardling_damage_mult": "HUD_STAT_WARDLING_DMG",
	&"falloff_range": "HUD_STAT_FALLOFF", &"armor_pen_bonus": "HUD_STAT_ARMOR_PEN",
	&"weapon_damage_taken": "HUD_STAT_GUN_DMG_TAKEN", &"skill_damage_taken": "HUD_STAT_SKILL_DMG_TAKEN"}

var open: bool = false
var tab: int = ShopModel.Tab.RECOMMENDED
## Expert detail in the item pane (matched rules, tags, counters).
var expert: bool = false
var _advice_rules: AdviceRulesDef
var query: String = ""
var searching: bool = false
## Position in the visible row list.
var selected: int = 0
var model: ShopModel

var _rows: Array[int] = []
var _scroll: int = 0
var _hover: int = -1
var _held: Dictionary = {}
var _edges: Dictionary = {}
var _econ: EconomyRulesDef
var _builds: RecommendedBuildsDef
var _toast: String = ""
var _toast_t: float = 0.0
var _toast_col: Color = HudPalette.TEAL
var _hint_t: float = 0.0
var _pending: Dictionary = {}
## Catalog index of the last purchase this visit (Ctrl+Z / R3 undo target).
var _last_index: int = -1
var _mouse_before: int = -1
var _was_open: bool = false
## Private builds of this PC (user://builds.json).
var builds_vm: BuildsViewModel
## --debug-armory: open once when the hero first stands on the pad.
var _auto_open: bool = false
## --debug-armory-builds: open on My builds with a sample build.
var _debug_builds: bool = false

const _KEYS: Array[int] = [KEY_F, KEY_B, KEY_ESCAPE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER,
	KEY_1, KEY_2, KEY_3, KEY_BACKSPACE, KEY_Q, KEY_E, KEY_PAGEUP, KEY_PAGEDOWN, KEY_SLASH, KEY_R, KEY_Z, KEY_O, KEY_TAB,
	KEY_I, KEY_N, KEY_D, KEY_C, KEY_V, KEY_DELETE, KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]
const _JOY: Array[int] = [JOY_BUTTON_Y, JOY_BUTTON_B, JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
	JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER,
	JOY_BUTTON_RIGHT_STICK, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_BACK]


func bind(c: HudContext) -> void:
	super(c)
	_econ = load(GameSession.ECONOMY_RULES) as EconomyRulesDef
	_builds = load(RecommendedBuildsDef.DEFAULT_PATH) as RecommendedBuildsDef
	_advice_rules = load(AdviceRulesDef.DEFAULT_PATH) as AdviceRulesDef
	var lc = c.session.get("launch_config") if c.session != null else null
	_auto_open = lc != null and lc.get("debug_armory") == true
	_debug_builds = lc != null and lc.get("debug_armory_builds") == true
	# --debug-armory-builds: an in-memory store, so evidence runs never touch the player's file.
	builds_vm = BuildsViewModel.new(null, "" if _debug_builds else CustomBuildStore.DEFAULT_PATH)
	builds_vm.load_store()


## True while something must be drawn: the shop or the off-pad hint.
func wants_draw() -> bool:
	return open or _hint_t > 0.0


# --- Per-frame update -------------------------------------------------------------

## Polls keys (edge-triggered), updates `open`, the purchase toast and pending
## requests; called by HudRoot each frame.
func poll() -> void:
	var client := ctx.client
	if client == null or client.progress == null or client.catalog == null:
		open = false
		_sync_open()
		return
	var dt := get_process_delta_time()
	_toast_t = maxf(0.0, _toast_t - dt)
	_hint_t = maxf(0.0, _hint_t - dt)
	if model == null:
		model = ShopModel.new()
	model.catalog = client.catalog
	model.rules = _econ
	model.builds = _builds
	model.hero_id = client.hero_def.id
	model.weapon = client.hero_def.weapon
	model.advice_rules = _advice_rules
	if builds_vm != null:
		builds_vm.setup(client.hero_def.id, client.catalog, client.hero_def.weapon, _builds)
		model.set_custom_guide(builds_vm.active_guide())
	model.update(client.progress)
	if open:
		_update_context(client)
	_scan()
	var at := (client.progress.flags & SnapshotData.ProgressState.FLAG_AT_ARMORY) != 0
	if not at or client.is_dead():
		open = false
	elif _auto_open:
		_auto_open = false
		open = true
		if _debug_builds:
			_seed_debug_build(client)
	if not searching:
		# Ctrl+F searches inside the open panel; it must not toggle it shut.
		var toggle := _toggle_edge() and not (open and Input.is_key_pressed(KEY_CTRL))
		var shop := _open_edge()
		if toggle or shop:
			if at and not client.is_dead():
				open = not open
			elif _e(KEY_B) or shop:
				_hint_t = HINT_LIFE_S if not client.is_dead() else 0.0
	_sync_open()
	_check_pending(dt)
	if open:
		_refresh_rows()
		if not searching:
			_panel_keys()
	mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if client.player_input != null:
		client.player_input.ui_captured = open


## Open / close transitions: reset the view, free / restore the mouse.
func _sync_open() -> void:
	if open == _was_open:
		return
	_was_open = open
	if open:
		tab = ShopModel.Tab.BUILDS if _debug_builds else ShopModel.Tab.RECOMMENDED
		query = ""
		searching = false
		_scroll = 0
		_refresh_rows()
		if tab != ShopModel.Tab.BUILDS:
			_jump_recommended()
		_mouse_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		searching = false
		if _mouse_before == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_mouse_before = -1


## Recommendation context: match clock, team size / mode and both teams' heroes.
func _update_context(client: ClientWorld) -> void:
	var team := client.own_team()
	var allies: Array = client.team_hero_defs(team)
	allies.append(client.hero_def)
	var enemies: Array = client.team_hero_defs(1 - team) if team == 0 or team == 1 else []
	var size_ := maxi(allies.size(), enemies.size())
	var t := client.match_state.time_s if client.match_state != null else 0.0
	model.set_context(t, &"3v3" if size_ <= 3 else &"5v5", size_, enemies, allies)


func _refresh_rows() -> void:
	if tab == ShopModel.Tab.BUILDS:
		_rows.clear()
		for i in builds_vm.entries().size() if builds_vm != null else 0:
			_rows.append(i)
	else:
		_rows = model.rows(tab, query)
	selected = clampi(selected, 0, maxi(0, _rows.size() - 1))
	_ensure_visible()


## Interact (rebindable, keyboard or pad) toggles the panel on the Armory pad:
## the same action the "[%s] ARMORY" prompt names. Falls back to F / pad Y.
func _toggle_edge() -> bool:
	if InputMap.has_action(&"interact"):
		return _track(2001, Input.is_action_pressed(&"interact"))
	return _e(KEY_F) or _je(JOY_BUTTON_Y)


## The open_shop action (key B fallback when the action is not registered yet).
func _open_edge() -> bool:
	return _e(KEY_B) if not InputMap.has_action(&"open_shop") else _track(2000, Input.is_action_pressed(&"open_shop"))


func _scan() -> void:
	_edges.clear()
	for k in _KEYS:
		_edges[k] = _track(k, Input.is_physical_key_pressed(k))
	for b in _JOY:
		_edges[1000 + b] = _track(1000 + b, Input.is_joy_button_pressed(0, b))


func _e(key: int) -> bool:
	return _edges.get(key, false)


func _je(button: int) -> bool:
	return _edges.get(1000 + button, false)


func _track(id: int, down: bool) -> bool:
	var was: bool = _held.get(id, false)
	_held[id] = down
	return down and not was


func _panel_keys() -> void:
	if _e(KEY_ESCAPE) or _je(JOY_BUTTON_B):
		open = false
		return
	if _e(KEY_Q) or _e(KEY_PAGEUP) or _je(JOY_BUTTON_LEFT_SHOULDER):
		_step_tab(-1)
	if _e(KEY_E) or _e(KEY_PAGEDOWN) or _je(JOY_BUTTON_RIGHT_SHOULDER):
		_step_tab(1)
	if _e(KEY_O):
		model.sort_mode = (model.sort_mode + 1) % ShopModel.Sort.size()
		_refresh_rows()
	if _e(KEY_TAB) or _je(JOY_BUTTON_BACK):
		model.affordable_only = not model.affordable_only
		_refresh_rows()
	if _e(KEY_I):
		expert = not expert
	if tab == ShopModel.Tab.BUILDS:
		_builds_keys()
		return
	if _e(KEY_SLASH) or (_e(KEY_F) and Input.is_key_pressed(KEY_CTRL)):
		searching = true
	if _e(KEY_DOWN) or _je(JOY_BUTTON_DPAD_DOWN):
		_move(_cols())
	if _e(KEY_UP) or _je(JOY_BUTTON_DPAD_UP):
		_move(-_cols())
	if _e(KEY_RIGHT) or _je(JOY_BUTTON_DPAD_RIGHT):
		_move(1)
	if _e(KEY_LEFT) or _je(JOY_BUTTON_DPAD_LEFT):
		_move(-1)
	if _e(KEY_R) or _je(JOY_BUTTON_LEFT_STICK):
		_jump_recommended()
	if _e(KEY_Z) and Input.is_key_pressed(KEY_CTRL) or _je(JOY_BUTTON_RIGHT_STICK):
		_undo()
	var idx := _sel_index()
	if idx < 0:
		return
	if _e(KEY_ENTER) or _e(KEY_KP_ENTER) or _je(JOY_BUTTON_A):
		_buy(idx, 0)
	for t in 3:
		if _e(KEY_1 + t):
			_buy(idx, t + 1)
	if _e(KEY_BACKSPACE) or _je(JOY_BUTTON_X):
		_sell(idx)
	if _e(KEY_EQUAL) or _e(KEY_KP_ADD) or _track(3001, Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.6):
		_add_to_build(idx)
	if _e(KEY_MINUS) or _e(KEY_KP_SUBTRACT) or _track(3002, Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.6):
		_remove_from_build(idx)


# --- My builds ----------------------------------------------------------------------

func _builds_keys() -> void:
	if _e(KEY_DOWN) or _je(JOY_BUTTON_DPAD_DOWN):
		_move_build(1)
	if _e(KEY_UP) or _je(JOY_BUTTON_DPAD_UP):
		_move_build(-1)
	if _e(KEY_ENTER) or _e(KEY_KP_ENTER) or _je(JOY_BUTTON_A):
		if builds_vm.use(selected):
			_show_toast(tr("HUD_BUILDS_USED") % _build_name(builds_vm.entries()[selected]), HudPalette.TEAL)
	if _e(KEY_N) or _je(JOY_BUTTON_LEFT_STICK):
		_select_build(builds_vm.new_from_default(), "HUD_BUILDS_CREATED")
	if _e(KEY_D) or _je(JOY_BUTTON_RIGHT_STICK):
		_select_build(builds_vm.duplicate_entry(selected), "HUD_BUILDS_CREATED")
	if _e(KEY_DELETE) or _e(KEY_BACKSPACE) or _je(JOY_BUTTON_X):
		if builds_vm.delete_entry(selected):
			_refresh_rows()
			_show_toast(tr("HUD_BUILDS_DELETED"), HudPalette.BRASS)
		elif builds_vm.confirm_delete != "":
			_show_toast(tr("HUD_BUILDS_DELETE_CONFIRM"), HudPalette.BRASS)
	if _e(KEY_C):
		var t := builds_vm.export_entry(selected)
		if t != "":
			DisplayServer.clipboard_set(t)
			_show_toast(tr("HUD_BUILDS_COPIED"), HudPalette.TEAL)
	if _e(KEY_V):
		var e := builds_vm.import_text(DisplayServer.clipboard_get())
		if e >= 0:
			_select_build(e, "HUD_BUILDS_PASTED")
		else:
			_show_toast(tr("HUD_BUILDS_PASTE_BAD"), HudPalette.BRASS)


## Evidence only: a custom build from the guide plus one off-family item (a warning).
func _seed_debug_build(client: ClientWorld) -> void:
	var e := builds_vm.new_from_default()
	builds_vm.use(e)
	var odd := &"rifling" if client.hero_def.weapon.feed_kind == 0 else &"focus_lens"
	builds_vm.add_item(client.catalog.index_of(odd), 1)
	builds_vm.add_item(client.catalog.index_of(&"quick_mint"), 1)
	_sync_open()
	selected = e


func _move_build(delta: int) -> void:
	selected = clampi(selected + delta, 0, maxi(0, _rows.size() - 1))
	builds_vm.confirm_delete = ""


func _select_build(entry: int, toast_key: String) -> void:
	if entry < 0:
		return
	_refresh_rows()
	selected = entry
	_show_toast(tr(toast_key), HudPalette.TEAL)


func _build_name(e: Dictionary) -> String:
	return tr("HUD_BUILDS_DEFAULT") if String(e["id"]) == "" else String(e["name"])


## + / RT on a catalog item: the next tier (or one more Med-Pack) joins the
## build in use (a new build from the guide when the guide is in use).
func _add_to_build(idx: int) -> void:
	var it := model.catalog.at(idx)
	var target := 1
	if it.kind == ArmoryItemDef.Kind.MOUNT:
		target = mini(model.held_tier(idx) + 1, it.tiers())
	if builds_vm.add_item(idx, target) > 0:
		var b := builds_vm.store.find(builds_vm.active_id())
		_show_toast(tr("HUD_BUILDS_ADDED") % String(b["name"]), HudPalette.TEAL)


func _remove_from_build(idx: int) -> void:
	if builds_vm.remove_item(idx):
		var b := builds_vm.store.find(builds_vm.active_id())
		_show_toast(tr("HUD_BUILDS_REMOVED") % String(b["name"]), HudPalette.BRASS)


## Moves `delta` tabs left / right through the visible tabs (wraps).
func _step_tab(delta: int) -> void:
	var tabs := model.tabs()
	_set_tab(tabs[posmod(tabs.find(tab) + delta, tabs.size())])


func _set_tab(t: int) -> void:
	tab = t
	selected = 0
	_scroll = 0
	_refresh_rows()


func _move(delta: int) -> void:
	var n := _rows.size()
	if n == 0:
		return
	var to := selected + delta
	if absi(delta) == _cols() and (to < 0 or to >= n):
		to = clampi(to, 0, n - 1) if (selected / _cols()) != ((n - 1) / _cols()) and delta > 0 else selected
	selected = clampi(to, 0, n - 1)
	_ensure_visible()


## Selects the next recommended item (switching to the tab that shows it).
func _jump_recommended() -> void:
	var idx := model.recommended_next()
	if idx < 0:
		return
	if not _rows.has(idx):
		tab = ShopModel.Tab.RECOMMENDED if model.rows(ShopModel.Tab.RECOMMENDED).has(idx) else ShopModel.Tab.ALL
		query = ""
		_rows = model.rows(tab, query)
	selected = maxi(0, _rows.find(idx))
	_ensure_visible()


func _sel_index() -> int:
	return _rows[selected] if selected >= 0 and selected < _rows.size() else -1


func _ensure_visible() -> void:
	var row := selected / _cols()
	var vis := _visible_rows()
	if row < _scroll:
		_scroll = row
	elif row >= _scroll + vis:
		_scroll = row - vis + 1
	_scroll = clampi(_scroll, 0, maxi(0, ceili(_rows.size() / float(_cols())) - vis))


# --- Requests -----------------------------------------------------------------------

func _request(action: int, arg: int) -> void:
	if ctx.client.player_input != null:
		ctx.client.player_input.request_action(action, arg)


## Sends ACTION_BUY for `index` (tier 0 = next) unless the model already knows it fails.
func _buy(index: int, tier: int) -> void:
	var st := model.state(index, tier)
	if st != ShopModel.State.AVAILABLE:
		_show_toast(_reason(index, st), HudPalette.WARN)
		return
	_send("buy", index, InputCommand.ACTION_BUY, ShopModel.buy_arg(index, tier), model.purchase_cost(index, tier))


## Sells the selected mount line, or undoes a squad upgrade / Med-Pack bought this visit.
func _sell(index: int) -> void:
	var socket := model.sell_socket(index)
	if socket >= 0:
		_send("undo" if model.is_undo(socket) else "sell", index, InputCommand.ACTION_SELL, socket,
			model.sell_value(socket))
		return
	var arg := model.undo_arg(index)
	if arg < 0:
		_show_toast(tr("HUD_SHOP_NO_SELL"), HudPalette.WARN)
		return
	_send("undo", index, InputCommand.ACTION_SELL, arg, model.undo_value(index))


func _undo() -> void:
	var arg := model.undo_arg(_last_index)
	if arg < 0:
		_show_toast(tr("HUD_SHOP_NO_UNDO"), HudPalette.WARN)
		return
	_send("undo", _last_index, InputCommand.ACTION_SELL, arg, model.undo_value(_last_index))


## Sends one Armory request and remembers the server's shop_seq to match its result.
func _send(kind: String, index: int, action: int, arg: int, value: int) -> void:
	_pending = {"kind": kind, "index": index, "value": value, "seq": ctx.client.progress.shop_seq, "t": 0.0}
	_request(action, arg)


## Watches the replicated progress for the outcome of the last request: the
## server bumps shop_seq and reports the HeroProgress.Result (v21).
func _check_pending(dt: float) -> void:
	if _pending.is_empty():
		return
	_pending["t"] = float(_pending["t"]) + dt
	var p := ctx.client.progress
	if p.shop_seq != int(_pending["seq"]):
		var idx: int = _pending["index"]
		var it := ctx.client.catalog.at(idx)
		var name := it.label() if it != null else ""
		if p.shop_result == HeroProgress.Result.OK:
			match String(_pending["kind"]):
				"buy":
					_show_toast(tr("HUD_SHOP_TOAST_BOUGHT") % [name, _pending["value"]], HudPalette.TEAL)
					_last_index = idx
				"undo":
					_show_toast(tr("HUD_SHOP_TOAST_UNDONE") % [name, _pending["value"]], HudPalette.BRASS)
					_last_index = -1
				_:
					_show_toast(tr("HUD_SHOP_TOAST_SOLD") % [name, _pending["value"]], HudPalette.BRASS)
					_last_index = -1
		else:
			_show_toast(tr(ShopModel.result_key(p.shop_result)), HudPalette.DANGER)
		_pending.clear()
		return
	if float(_pending["t"]) > PENDING_TIMEOUT_S:
		_show_toast(tr("HUD_SHOP_TOAST_NO_ANSWER"), HudPalette.DANGER)
		_pending.clear()


func _show_toast(t: String, col: Color) -> void:
	_toast = t
	_toast_col = col
	_toast_t = TOAST_LIFE_S


## Plain-language reason a buy is refused.
func _reason(index: int, st: int) -> String:
	var it := ctx.client.catalog.at(index)
	match st:
		ShopModel.State.CANT_AFFORD:
			return tr("HUD_SHOP_NEED_LUMEN") % maxi(0, model.purchase_cost(index) - model.swap_credit(index) - ctx.client.progress.lumen)
		ShopModel.State.OWNED:
			return tr("HUD_ARMORY_OWNED")
		ShopModel.State.MAXED:
			return tr("HUD_ARMORY_MAXED")
		ShopModel.State.LOCKED:
			var req := ctx.client.catalog.find(it.requires)
			return tr("HUD_ARMORY_NEEDS") % (req.display_name if req != null else "?")
		ShopModel.State.WRONG_FAMILY:
			return tr("HUD_ARMORY_MANA_ONLY") if it.family == ArmoryItemDef.Family.CRYSTAL else tr("HUD_ARMORY_MECH_ONLY")
		ShopModel.State.CARRY_FULL:
			return tr("HUD_SHOP_CARRY_FULL")
		ShopModel.State.DISABLED:
			return tr("HUD_SHOP_DISABLED")
	return ""


# --- Mouse and search typing --------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not (open and searching) or not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	match k.keycode:
		KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_DOWN:
			searching = false
		KEY_BACKSPACE:
			query = query.left(maxi(0, query.length() - 1))
		_:
			if k.unicode >= 32 and k.unicode != 127 and query.length() < 24:
				query += char(k.unicode)
	_refresh_rows()
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not open:
		return
	if event is InputEventMouseMotion:
		_hover = _card_at(event.position) if tab != ShopModel.Tab.BUILDS else -1
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN or mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll = clampi(_scroll + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0,
				maxi(0, ceili(_rows.size() / float(_cols())) - _visible_rows()))
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_click(mb.position, mb.double_click)
		accept_event()
	elif event is InputEventMouseButton:
		accept_event()


func _click(pos: Vector2, double: bool) -> void:
	searching = _search_rect().has_point(pos)
	if _close_rect().has_point(pos):
		open = false
		return
	var tabs := model.tabs()
	for i in tabs.size():
		if _tab_rect(i).has_point(pos):
			_set_tab(tabs[i])
			return
	if tab == ShopModel.Tab.BUILDS:
		for i in _rows.size():
			if _build_row_rect(i).has_point(pos):
				selected = i
				builds_vm.confirm_delete = ""
				if double:
					builds_vm.use(i)
		return
	var c := _card_at(pos)
	if c >= 0:
		selected = c
		if double:
			_buy(_rows[c], 0)
		return
	var idx := _sel_index()
	if _buy_rect().has_point(pos) and idx >= 0:
		_buy(idx, 0)
	elif _sell_rect().has_point(pos) and idx >= 0:
		if model.sell_socket(idx) < 0 and model.undo_arg(idx) < 0 and model.undo_arg(_last_index) >= 0:
			_undo()
		else:
			_sell(idx)
	for t in 3:
		if _tier_rect(t).has_point(pos) and idx >= 0 and model.catalog.at(idx).tiers() > t:
			_buy(idx, t + 1)
	var path := model.path()
	var win := _strip_window()
	for s in range(win.x, win.x + win.y):
		if _chip_rect(s).has_point(pos):
			var ci: int = path[s]["item"]
			if ci >= 0:
				if not _rows.has(ci):
					tab = ShopModel.Tab.ALL
					query = ""
					_rows = model.rows(tab, query)
				selected = maxi(0, _rows.find(ci))
				_ensure_visible()


# --- Layout (design units, shared by drawing and hit tests) ----------------------------

const BUILD_ROW_H: float = 58.0
## Narrowest build-strip chip (glyph + tier label without overlap).
const STRIP_MIN_W: float = 66.0


func _build_row_rect(i: int) -> Rect2:
	return Rect2(PAD, GRID_Y + i * (BUILD_ROW_H + 6.0), _left_w(), BUILD_ROW_H)

func _cols() -> int:
	return 3 if (_left_w() - 2.0 * GAP) / 3.0 >= WIDE_CARD_W else 2


func _left_w() -> float:
	return size.x * 0.585 - PAD


func _detail_rect() -> Rect2:
	var x := size.x * 0.60
	return Rect2(x, GRID_Y, size.x - PAD - x, size.y - GRID_Y - FOOTER_H - 6.0)


func _grid_h() -> float:
	return size.y - GRID_Y - FOOTER_H - BUILD_H - 14.0


func _visible_rows() -> int:
	return maxi(1, floori((_grid_h() + GAP) / (CARD_H + GAP)))


func _card_w() -> float:
	return (_left_w() - GAP * (_cols() - 1)) / _cols()


## Card rectangle of the visible row slot `pos` (position in the row list).
func _card_rect(pos: int) -> Rect2:
	var row := pos / _cols() - _scroll
	var col := pos % _cols()
	return Rect2(PAD + col * (_card_w() + GAP), GRID_Y + row * (CARD_H + GAP), _card_w(), CARD_H)


func _card_at(p: Vector2) -> int:
	for i in _rows.size():
		var row := i / _cols() - _scroll
		if row < 0 or row >= _visible_rows():
			continue
		if _card_rect(i).has_point(p):
			return i
	return -1


## Rect of the tab at visible position `pos` (model.tabs() order).
func _tab_rect(pos: int) -> Rect2:
	var tabs := model.tabs()
	var x := PAD
	for i in pos:
		x += _tab_w(tabs[i]) + 6.0
	return Rect2(x, TAB_Y, _tab_w(tabs[pos]), TAB_H)


func _tab_w(t: int) -> float:
	return caps_width(tr(ShopModel.TAB_KEYS[t]), _tab_font(), 0.2) + _tab_pad()


## Tab label size: 16, smaller on narrow panels (720p) so all tabs keep at
## least 14 px of padding and the last one never spills past the panel edge.
func _tab_font() -> int:
	for fs in [16, 14, 13, 12]:
		if _tab_words(fs) + 14.0 * model.tabs().size() <= _tab_room():
			return fs
	return 12


func _tab_pad() -> float:
	var n := model.tabs().size()
	return clampf((_tab_room() - _tab_words(_tab_font())) / maxf(1.0, n), 10.0, 34.0)


func _tab_words(fs: int) -> float:
	var w := 0.0
	for t in model.tabs():
		w += caps_width(tr(ShopModel.TAB_KEYS[t]), fs, 0.2)
	return w


func _tab_room() -> float:
	return size.x - 2.0 * PAD - 6.0 * (model.tabs().size() - 1)


func _search_rect() -> Rect2:
	return Rect2(size.x * 0.34, 14.0, 300.0, 40.0)


func _close_rect() -> Rect2:
	return Rect2(size.x - PAD - 44.0, 14.0, 44.0, 40.0)


## BUY and SELL share the footer right of the key hints: BUY 58%, SELL the
## rest (fixed widths left SELL 30 px wide on a 720p panel).
func _buy_rect() -> Rect2:
	var avail := size.x - PAD - size.x * 0.60
	return Rect2(size.x * 0.60, size.y - FOOTER_H + 6.0, minf(250.0, (avail - 12.0) * 0.58), 56.0)


func _sell_rect() -> Rect2:
	var x := _buy_rect().end.x + 12.0
	return Rect2(x, size.y - FOOTER_H + 6.0, size.x - PAD - x, 56.0)


func _tier_rect(t: int) -> Rect2:
	var d := _detail_rect()
	return Rect2(d.position.x + 12.0, d.position.y + 250.0 + 32.0 * t, d.size.x - 24.0, 30.0)


## Chip rect of path step `step` (only steps inside _strip_window() are shown).
func _chip_rect(step: int) -> Rect2:
	var win := _strip_window()
	var n := maxi(1, win.y)
	var w := minf(84.0, (_left_w() + GAP) / n)
	return Rect2(PAD + (step - win.x) * w, size.y - FOOTER_H - BUILD_H + 38.0, w - 6.0, 52.0)


## (first step, count) of the path chips that fit at STRIP_MIN_W each; a long
## path scrolls so the next step stays in view (two done steps before it).
func _strip_window() -> Vector2i:
	var path := model.path() if model != null else []
	var fit := maxi(1, floori((_left_w() + GAP) / STRIP_MIN_W))
	if path.size() <= fit:
		return Vector2i(0, path.size())
	var nxt := 0
	for k in path.size():
		if bool(path[k]["next"]):
			nxt = k
			break
	return Vector2i(clampi(nxt - 2, 0, path.size() - fit), fit)


# --- Drawing ------------------------------------------------------------------------

func _draw() -> void:
	var client := ctx.client
	if client == null or client.progress == null or model == null:
		return
	if not open:
		if _hint_t > 0.0:
			_draw_hint()
		return
	var p := client.progress
	# v0.12: ink 94% fading to 72% to the right, no frame.
	var bg0 := Color(HudPalette.INK_DEEP, 0.94)
	var bg1 := Color(HudPalette.INK_DEEP, 0.72)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]),
		PackedColorArray([bg0, bg1, bg1, bg0]))
	_draw_header(p)
	_draw_tabs()
	if tab == ShopModel.Tab.BUILDS:
		_draw_builds()
	else:
		_draw_cards()
		_draw_detail()
	_draw_build_strip()
	_draw_footer()
	_draw_toast()


## My builds: the list (left) and the selected build's steps and warnings (right).
func _draw_builds() -> void:
	var es := builds_vm.entries()
	var max_rows := maxi(1, floori((_grid_h() + 6.0) / (BUILD_ROW_H + 6.0)))
	for i in mini(es.size(), max_rows):
		var e: Dictionary = es[i]
		var r := _build_row_rect(i)
		draw_rect(r, SEL_BG if i == selected else CARD_BG)
		if bool(e["active"]):
			draw_rect(Rect2(r.position, Vector2(3.0, r.size.y)), HudPalette.TEAL)
		var name_ := _fit(_build_name(e), 18, r.size.x - 190.0, ctx.font_display)
		text(name_, r.position + Vector2(16.0, 26.0), 18, HudPalette.IVORY, ctx.font_display)
		var sub := tr("HUD_BUILDS_STEPS") % int(e["steps"])
		var w: PackedStringArray = e["warnings"]
		if not w.is_empty():
			sub += "  ·  " + tr("HUD_BUILDS_WARN") % w.size()
		text(sub, r.position + Vector2(16.0, 47.0), 13, HudPalette.BRASS if not w.is_empty() else HudPalette.MUTED,
			ctx.font_body)
		if bool(e["active"]):
			caps(tr("HUD_BUILDS_ACTIVE"), Vector2(0.0, r.position.y + 34.0), 13, HudPalette.TEAL, 0.2,
				HORIZONTAL_ALIGNMENT_RIGHT, r.end.x - 14.0)
		elif builds_vm.confirm_delete != "" and builds_vm.confirm_delete == String(e["id"]):
			caps(tr("HUD_BUILDS_DELETE_CONFIRM"), Vector2(0.0, r.position.y + 34.0), 12, HudPalette.BRASS, 0.12,
				HORIZONTAL_ALIGNMENT_RIGHT, r.end.x - 14.0)
	# Detail: steps of the selected build (the guide's own notes for entry 0).
	var d := _detail_rect()
	if selected < 0 or selected >= es.size():
		return
	var e: Dictionary = es[selected]
	caps(_fit(_build_name(e), 22, d.size.x - 24.0, ctx.font_display), d.position + Vector2(12.0, 28.0), 22,
		HudPalette.IVORY, 0.12)
	caps(tr("HUD_BUILDS_LOCAL"), d.position + Vector2(12.0, 48.0), 11, HudPalette.DIM, 0.16)
	var y := d.position.y + 76.0
	if String(e["id"]) == "":
		draw_multiline_string(ctx.font_body, Vector2(d.position.x + 12.0, y), tr("HUD_BUILDS_DEFAULT_NOTE"),
			HORIZONTAL_ALIGNMENT_LEFT, d.size.x - 24.0, ts(15), 4, HudPalette.MUTED)
		return
	var b := builds_vm.build_at(selected)
	var steps: Array = b["steps"]
	var cat := ctx.client.catalog
	for k in steps.size():
		if y > d.end.y - 16.0 - 20.0 * mini((e["warnings"] as PackedStringArray).size(), 3) - 10.0:
			text("…", Vector2(d.position.x + 12.0, y), 15, HudPalette.DIM)
			break
		var st: Dictionary = steps[k]
		var it := cat.find(StringName(st["item"]))
		var label := it.label() if it != null else String(st["item"])
		var tgt := int(st["target"])
		var suffix := ""
		if it != null and it.kind == ArmoryItemDef.Kind.MOUNT:
			suffix = " " + TIER_NAMES[clampi(tgt, 0, 3)] if tgt <= 3 else " ?"
		elif tgt > 1:
			suffix = " ×%d" % tgt
		text("%d." % (k + 1), Vector2(d.position.x + 12.0, y), 14, HudPalette.DIM, ctx.font_numbers)
		text(_fit(label + suffix, 15, d.size.x - 60.0), Vector2(d.position.x + 44.0, y), 15,
			HudPalette.IVORY if it != null else HudPalette.BRASS)
		y += 24.0
	# Warnings pinned to the bottom of the pane, one line each, a brass diamond as the bullet.
	var w: PackedStringArray = e["warnings"]
	var n := mini(w.size(), 3)
	for k in n:
		var wy := d.end.y - 8.0 - 20.0 * (n - 1 - k)
		diamond(Vector2(d.position.x + 16.0, wy - 5.0), 3.5, HudPalette.BRASS)
		text(_fit(w[k], 13, d.size.x - 40.0), Vector2(d.position.x + 28.0, wy), 13, HudPalette.BRASS)


func _draw_hint() -> void:
	var t := tr("HUD_SHOP_OFF_PAD")
	# W21-G2: say where the pad is ("... 24 m ->").
	var fmt := tr("HUD_SHOP_OFF_PAD_DIR")
	var dir := ArmoryWaypoint.hint_for(ctx.client, ctx.own_team())
	if "%s" in fmt and dir != "":
		t = fmt % dir
	var w := text_width(t, 22, ctx.font_display) + 48.0
	var r := Rect2(size.x * 0.5 - w * 0.5, size.y - 150.0, w, 48.0)
	scrim_h(r, 0.0, 0.0)
	draw_rect(r, Color(HudPalette.INK_DEEP, 0.8))
	draw_rect(Rect2(r.end.x - 3.0, r.position.y, 3.0, r.size.y), HudPalette.BRASS)
	caps_c(t, r.get_center(), 20, HudPalette.BRASS_HI, 0.16)


func _draw_header(p: SnapshotData.ProgressState) -> void:
	caps(tr("HUD_ARMORY"), Vector2(PAD, 44.0), 30, HudPalette.IVORY, 0.3)
	var b := model.build()
	if b != null:
		var pc := model.progress_counts()
		var sub := tr("HUD_SHOP_BUILD_FOR") % b.display_name
		if pc.y > 0:
			sub += "  ·  " + tr("HUD_SHOP_PROGRESS") % [pc.x, pc.y]
		text(sub, Vector2(PAD, 62.0), 14, HudPalette.MUTED, ctx.font_body)
	var lumen := HudFormat.thousands(p.lumen)
	text(lumen, Vector2(0.0, 50.0), 30, HudPalette.BRASS_HI, ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, size.x - PAD - 80.0)
	caps(tr("HUD_LUMEN"), Vector2(0.0, 18.0), 13, HudPalette.MUTED, 0.22, HORIZONTAL_ALIGNMENT_RIGHT, size.x - PAD - 80.0)
	var g := Vector2(size.x - PAD - 80.0 - text_width(lumen, 30, ctx.font_numbers) - 20.0, 40.0)
	draw_polyline(PackedVector2Array([g + Vector2(0, -10), g + Vector2(8.5, 0), g + Vector2(0, 10), g + Vector2(-8.5, 0),
		g + Vector2(0, -10)]), HudPalette.BRASS_HI, 2.0, true)
	diamond(g, 4.0, HudPalette.BRASS_HI)
	var cr := _close_rect()
	draw_rect(cr.grow(-0.5), HudPalette.HAIR_STRONG, false, 1.0)
	draw_line(cr.get_center() + Vector2(-7, -7), cr.get_center() + Vector2(7, 7), HudPalette.MUTED, 1.6)
	draw_line(cr.get_center() + Vector2(-7, 7), cr.get_center() + Vector2(7, -7), HudPalette.MUTED, 1.6)
	draw_line(Vector2(PAD, HEADER_H), Vector2(size.x - PAD, HEADER_H), HudPalette.HAIR_STRONG, 1.0)


func _draw_tabs() -> void:
	var tabs := model.tabs()
	for i in tabs.size():
		var t := tabs[i]
		var r := _tab_rect(i)
		var on := t == tab
		if on:  # v0.12: no tab boxes; a 2 px brass underline on the selected tab
			draw_rect(Rect2(r.position.x + 12.0, r.end.y - 2.0, r.size.x - 24.0, 2.0), HudPalette.BRASS)
		caps_c(tr(ShopModel.TAB_KEYS[t]), r.get_center(), _tab_font(), HudPalette.IVORY if on else HudPalette.MUTED, 0.2)
	var s := _search_rect()
	draw_rect(s, Color(HudPalette.INK_DEEP, 0.6))
	draw_rect(s.grow(-0.5), HudPalette.BRASS if searching else HudPalette.HAIR_STRONG, false, 1.0)
	var shown := query + ("_" if searching else "")
	if shown == "":
		text(tr("HUD_SHOP_SEARCH"), s.position + Vector2(12.0, 26.0), 15, HudPalette.DIM)
	else:
		text(shown, s.position + Vector2(12.0, 26.0), 16, HudPalette.IVORY)
	# View options (catalog tabs): sort and the affordable-only filter.
	if tab != ShopModel.Tab.RECOMMENDED and tab != ShopModel.Tab.BUILDS:
		var opt := tr(ShopModel.SORT_KEYS[model.sort_mode])
		if model.affordable_only:
			opt += "  ·  " + tr("HUD_SHOP_FILTER_AFFORDABLE")
		# Inside the search box, right-aligned: beside it, it ran into the Lumen total at 720p.
		text(opt, Vector2(s.position.x, s.position.y + 26.0), 13,
			HudPalette.BRASS if model.affordable_only or model.sort_mode != ShopModel.Sort.DEFAULT else HudPalette.DIM,
			ctx.font_body, HORIZONTAL_ALIGNMENT_RIGHT, s.size.x - 12.0)


func _draw_cards() -> void:
	var p := ctx.client.progress
	if _rows.is_empty():
		var empty := tr("HUD_SHOP_BUILD_DONE") if tab == ShopModel.Tab.RECOMMENDED and model.build() != null \
			else tr("HUD_SHOP_EMPTY")
		text(empty, Vector2(PAD + 8.0, GRID_Y + 40.0), 18, HudPalette.MUTED)
		return
	var next := model.recommended_next()
	for i in _rows.size():
		var row := i / _cols() - _scroll
		if row < 0 or row >= _visible_rows():
			continue
		var idx := _rows[i]
		var it := ctx.client.catalog.at(idx)
		var r := _card_rect(i)
		var st := model.state(idx)
		var dim := st == ShopModel.State.CANT_AFFORD or st == ShopModel.State.WRONG_FAMILY or st == ShopModel.State.LOCKED \
			or st == ShopModel.State.DISABLED
		var a := 0.45 if dim else 1.0
		var held := model.held_tier(idx)
		# v0.12: cut-corner card, hairline; brass rim when selected; 45% when dim.
		cut_fill(r, 12.0, Color(0.051, 0.075, 0.094, 0.9 * a))
		cut_line(r, 12.0, HudPalette.BRASS if i == selected else Color(HudPalette.HAIR_STRONG, a), 1.5 if i == selected else 1.0)
		if i == _hover and i != selected:
			cut_fill(r, 12.0, Color(HudPalette.IVORY, 0.04))
		if idx == next:
			cut_line(r.grow(-4.0), 9.0, Color(HudPalette.BRASS_DIM, a), 1.0)
		ShopIcons.draw(self, it, Rect2(r.position + Vector2(14.0, 14.0), Vector2(64.0, 64.0)), Color(1, 1, 1, a))
		var tx := r.position.x + 102.0
		text(_fit(it.label(), 18, r.size.x - 112.0), Vector2(tx, r.position.y + 30.0), 18,
			Color(HudPalette.IVORY, a), UiKit.body_font(600))
		var label := ""
		var col := HudPalette.BRASS_HI
		match st:
			ShopModel.State.OWNED, ShopModel.State.MAXED:
				label = tr("HUD_ARMORY_OWNED") if st == ShopModel.State.OWNED else tr("HUD_ARMORY_MAXED")
				col = HudPalette.TEAL
			ShopModel.State.WRONG_FAMILY:
				label = tr("HUD_ARMORY_MANA_ONLY") if it.family == ArmoryItemDef.Family.CRYSTAL else tr("HUD_ARMORY_MECH_ONLY")
				col = HudPalette.DIM
			ShopModel.State.LOCKED:
				label = tr("HUD_ARMORY_NEEDS") % ctx.client.catalog.find(it.requires).display_name
				col = HudPalette.WARN_UI
			ShopModel.State.CARRY_FULL:
				label = tr("HUD_SHOP_CARRY_FULL")
				col = HudPalette.TEAL
			ShopModel.State.DISABLED:
				label = tr("HUD_SHOP_DISABLED")
				col = HudPalette.DIM
			_:
				label = HudFormat.thousands(model.purchase_cost(idx))
				col = HudPalette.BRASS_HI if st == ShopModel.State.AVAILABLE else HudPalette.WARN_UI
		var lx := tx
		if st == ShopModel.State.AVAILABLE or st == ShopModel.State.CANT_AFFORD:
			diamond(Vector2(tx + 7.0, r.position.y + 55.0), 5.0, Color(col, a), false)
			lx += 20.0
		var pips_room := 18.0 * it.tiers() + 18.0 if it.tiers() > 1 else 0.0
		text(_fit(label, 17, r.end.x - lx - 8.0 - pips_room, ctx.font_numbers), Vector2(lx, r.position.y + 62.0), 17, Color(col, a),
			ctx.font_numbers)
		# Pips on the price line, right-aligned: below the price they ran into the reason line.
		_draw_pips(it, held, Vector2(r.end.x - 14.0 - 18.0 * it.tiers(), r.position.y + 61.0), a)
		var adv := model.advice_for(idx) if tab == ShopModel.Tab.RECOMMENDED else null
		if adv != null:  # Recommended tab: the one-line reason, clear of the NEXT / SITUATIONAL chips
			var chip_w := 0.0
			if idx == next:
				chip_w += caps_width(tr("HUD_SHOP_NEXT"), 12, 0.16) + 20.0
			if adv.situational:
				chip_w += caps_width(tr("HUD_SHOP_SITUATIONAL"), 12, 0.18) + 14.0
			# Too little room beside the chips: skip the line (the detail pane shows it) rather than "T..".
			var reason := _fit(tr(adv.reason_key), 13, r.end.x - tx - 12.0 - chip_w)
			if reason.length() >= 8:
				text(reason, Vector2(tx, r.position.y + 96.0), 13,
					Color(HudPalette.BRASS_HI if adv.situational else HudPalette.MUTED, a), ctx.font_body)
		elif it.kind == ArmoryItemDef.Kind.CONSUMABLE:
			text(tr("HUD_ARMORY_CARRY") % [p.medpacks, it.carry_limit], Vector2(tx, r.position.y + 94.0), 13,
				Color(HudPalette.MUTED, a))
		var tag_x := r.end.x - 12.0
		if st == ShopModel.State.CANT_AFFORD and model.affordable_soon(idx):
			var soon := tr("HUD_SHOP_SOON")
			caps(soon, Vector2(r.end.x - 12.0 - caps_width(soon, 12, 0.18), r.position.y + 22.0), 12, HudPalette.TEAL, 0.18)
		if adv != null and adv.situational:
			var sit := tr("HUD_SHOP_SITUATIONAL")
			tag_x -= caps_width(sit, 12, 0.18)
			caps(sit, Vector2(tag_x, r.end.y - 12.0), 12, HudPalette.WARN_UI, 0.18)
			tag_x -= 12.0
		if model.is_recommended(idx) and tab != ShopModel.Tab.RECOMMENDED:
			var rec := tr("HUD_SHOP_REC")
			tag_x -= caps_width(rec, 13, 0.18)
			caps(rec, Vector2(tag_x, r.end.y - 12.0), 13, HudPalette.BRASS, 0.18)
			tag_x -= 12.0
		if idx == next:
			var tag := tr("HUD_SHOP_NEXT")
			var tw := caps_width(tag, 12, 0.16) + 12.0
			var tr_ := Rect2(tag_x - tw, r.end.y - 28.0, tw, 20.0)
			cut_fill(tr_, 5.0, HudPalette.BRASS)
			draw_string(ctx.caps_font(ts(12), 0.16), Vector2(tr_.position.x + 6.0, tr_.get_center().y + ts(12) * 0.36), tag.to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, ts(12), HudPalette.INK)


## Tier pips: filled = held, hollow = not yet (only for tiered lines).
func _draw_pips(it: ArmoryItemDef, held: int, at: Vector2, a: float) -> void:
	if it.tiers() <= 1:
		return
	for t in it.tiers():
		var c := at + Vector2(7.0 + 18.0 * t, -4.0)
		diamond(c, 5.0, Color(HudPalette.BRASS if t < held else HudPalette.BRASS_DIM, a), t < held)


func _draw_build_strip() -> void:
	var b := model.build()
	var y := size.y - FOOTER_H - BUILD_H
	draw_line(Vector2(PAD, y + 2.0), Vector2(PAD + _left_w(), y + 2.0), HudPalette.HAIR_STRONG, 1.0)
	if b == null:
		text(tr("HUD_SHOP_NO_BUILD"), Vector2(PAD, y + 28.0), 15, HudPalette.MUTED)
		return
	caps(tr("HUD_SHOP_RECOMMENDED") % b.display_name, Vector2(PAD, y + 28.0), 15, HudPalette.MUTED, 0.22)
	var path := model.path()
	var win := _strip_window()
	var hint := tr("HUD_SHOP_JUMP_KEY")
	if win.y < path.size():
		hint = tr("HUD_SHOP_STRIP_RANGE") % [win.x + 1, win.x + win.y, path.size()] + "  ·  " + hint
	# Never under the title: drop to the bare key hint, then nothing, when space runs out.
	var title_end := PAD + caps_width(tr("HUD_SHOP_RECOMMENDED") % b.display_name, 15, 0.22) + 16.0
	if PAD + _left_w() - text_width(hint, 13) < title_end:
		hint = tr("HUD_SHOP_JUMP_KEY")
	if PAD + _left_w() - text_width(hint, 13) < title_end:
		hint = ""
	text(hint, Vector2(0.0, y + 28.0), 13, HudPalette.MUTED, ctx.font_body, HORIZONTAL_ALIGNMENT_RIGHT, PAD + _left_w())
	for s in range(win.x, win.x + win.y):
		var e: Dictionary = path[s]
		var r := _chip_rect(s)
		var it := ctx.client.catalog.at(int(e["item"]))
		if it == null:
			continue
		var done: bool = e["done"]
		var nxt: bool = e["next"]
		var a := 0.4 if done else 1.0
		cut_fill(r, 8.0, Color(0.051, 0.075, 0.094, 0.9))
		cut_line(r, 8.0, HudPalette.BRASS if nxt else HudPalette.HAIR_STRONG, 1.5 if nxt else 1.0)
		# Glyph left, tier label right of it, check mark top-right: sized to the chip so nothing overlaps.
		var g := minf(36.0, r.size.x - 30.0)
		ShopIcons.draw(self, it, Rect2(r.position + Vector2(5.0, (r.size.y - g) * 0.5), Vector2(g, g)), Color(1, 1, 1, a))
		var tgt: int = e["target"]
		var lab: String = TIER_NAMES[mini(tgt, 3)] if it.tiers() > 1 else ("x%d" % tgt if it.kind == ArmoryItemDef.Kind.CONSUMABLE else "")
		text(lab, Vector2(r.position.x + g + 8.0, r.position.y + 36.0), 14, Color(HudPalette.IVORY, a), ctx.font_numbers)
		if done:
			ShopIcons.check(self, r.position + Vector2(r.size.x - 11.0, 11.0), 5.0, HudPalette.TEAL)


func _draw_detail() -> void:
	var d := _detail_rect()  # v0.12: no box
	var idx := _sel_index()
	if idx < 0:
		return
	var it := ctx.client.catalog.at(idx)
	var p := ctx.client.progress
	var st := model.state(idx)
	var x := d.position.x + 16.0
	var y := d.position.y
	ShopIcons.draw(self, it, Rect2(Vector2(x, y + 16.0), Vector2(84.0, 84.0)), Color.WHITE)
	var kind := _kind_line(it, idx)
	var ksz := 15
	while ksz > 11 and caps_width(kind, ksz, 0.22) > d.end.x - 16.0 - (x + 100.0):
		ksz -= 1
	caps(kind, Vector2(x + 100.0, y + 30.0), ksz, HudPalette.BRASS, 0.22)
	# Title shrinks (27 down to 18) and then cuts so it never passes the panel edge.
	var title_w := d.end.x - 16.0 - (x + 100.0)
	var tsz := 27
	while tsz > 18 and caps_width(it.label(), tsz, 0.12) > title_w:
		tsz -= 1
	var title := it.label()
	while title.length() > 2 and caps_width(title + "..", tsz, 0.12) > title_w and caps_width(title, tsz, 0.12) > title_w:
		title = title.left(title.length() - 1)
	if title != it.label():
		title += ".."
	caps(title, Vector2(x + 100.0, y + 64.0), tsz, HudPalette.IVORY, 0.12)
	var bx := x + 100.0
	var why := model.reason_key(idx)
	var held := model.held_tier(idx)
	if why != "":  # the reason is the recommendation tag
		text(_fit(tr("HUD_SHOP_WHY") % tr(why), 15, d.end.x - 16.0 - bx), Vector2(bx, y + 98.0), 15,
			HudPalette.BRASS_HI, ctx.font_body)
	elif model.is_recommended(idx):
		caps(tr("HUD_SHOP_RECOMMENDED_TAG"), Vector2(bx, y + 96.0), 14, HudPalette.BRASS, 0.18)
		bx += caps_width(tr("HUD_SHOP_RECOMMENDED_TAG"), 14, 0.18) + 16.0
	if held > 0 and why == "":
		var s := tr("HUD_ARMORY_MOUNTED") % TIER_NAMES[held] if it.tiers() > 1 and it.kind != ArmoryItemDef.Kind.SQUAD \
			else tr("HUD_ARMORY_OWNED")
		caps(s, Vector2(bx, y + 96.0), 14, HudPalette.TEAL, 0.18)
	draw_line(Vector2(x, y + 116.0), Vector2(d.end.x - 16.0, y + 116.0), HudPalette.HAIR_STRONG, 1.0)
	var w := d.size.x - 32.0
	draw_multiline_string(ctx.font_body, Vector2(x, y + 146.0), it.effect_label(), HORIZONTAL_ALIGNMENT_LEFT, w, ts(18), 3,
		HudPalette.MUTED)
	var ty := y + 232.0
	if it.tiers() > 1 and it.values.size() > 0:
		caps(tr("HUD_SHOP_COL_TIER"), Vector2(x + 4.0, ty), 13, HudPalette.DIM, 0.22)
		caps(tr("HUD_SHOP_COL_EFFECT"), Vector2(x + 70.0, ty), 13, HudPalette.DIM, 0.22)
		caps(tr("HUD_SHOP_COL_PRICE"), Vector2(0.0, ty), 13, HudPalette.DIM, 0.22, HORIZONTAL_ALIGNMENT_RIGHT, d.end.x - 150.0)
		caps(tr("HUD_SHOP_COL_UPGRADE"), Vector2(0.0, ty), 13, HudPalette.DIM, 0.22, HORIZONTAL_ALIGNMENT_RIGHT, d.end.x - 28.0)
		for row in model.tier_rows(idx):
			var t: int = row["tier"]
			var r := _tier_rect(t - 1)
			var next_t := t == held + 1 or (held == 0 and t == 1)
			draw_rect(Rect2(r.position.x, r.end.y, r.size.x, 1.0), HudPalette.HAIR)
			if bool(row["held"]):
				draw_rect(Rect2(r.position, Vector2(3.0, r.size.y)), HudPalette.TEAL)
			var by := r.position.y + 21.0
			var rc := HudPalette.IVORY if next_t else HudPalette.MUTED
			text(TIER_NAMES[t], Vector2(x + 8.0, by), 17, rc, ctx.font_numbers)
			text(_effect_text(it, row), Vector2(x + 70.0, by), 15, rc)
			text(HudFormat.thousands(row["price"]), Vector2(0.0, by), 16, HudPalette.TEAL if bool(row["held"]) else HudPalette.BRASS_HI,
				ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, d.end.x - 150.0)
			text(("+" + HudFormat.thousands(row["upgrade"])) if t > 1 else "-", Vector2(0.0, by), 15, HudPalette.MUTED,
				ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, d.end.x - 28.0)
		ty += 130.0
	elif it.values.size() > 0:
		text(_effect_text(it, model.tier_rows(idx)[0]), Vector2(x, ty + 10.0), 17, HudPalette.IVORY)
		text(tr("HUD_SHOP_PRICE") % HudFormat.thousands(it.prices[0]), Vector2(x, ty + 40.0), 17, HudPalette.BRASS_HI,
			ctx.font_numbers)
		ty += 80.0
	else:
		text(tr("HUD_SHOP_PRICE") % HudFormat.thousands(it.prices[0]), Vector2(x, ty + 10.0), 17, HudPalette.BRASS_HI,
			ctx.font_numbers)
		ty += 50.0
	if it.stat == &"mod_damage" and it.fits(ctx.client.hero_def.weapon) and st != ShopModel.State.MAXED:
		text(_damage_delta(p, it), Vector2(x, ty + 10.0), 17, HudPalette.TEAL)
		ty += 30.0
	var note := _note(idx, st) if st != ShopModel.State.MAXED and st != ShopModel.State.OWNED else ""
	if note != "":
		text(note, Vector2(x, ty + 10.0), 15, HudPalette.WARN_UI if st != ShopModel.State.AVAILABLE else HudPalette.MUTED)
		ty += 28.0
	var sock := model.sell_socket(idx)
	if sock >= 0:
		var v := model.sell_value(sock)
		text((tr("HUD_SHOP_UNDO_INFO") if model.is_undo(sock) else tr("HUD_SHOP_SELL_INFO")) % v, Vector2(x, ty + 10.0), 15,
			HudPalette.BRASS_HI)
		ty += 28.0
	elif model.undo_arg(idx) >= 0:
		text(tr("HUD_SHOP_UNDO_INFO") % model.undo_value(idx), Vector2(x, ty + 10.0), 15, HudPalette.BRASS_HI)
		ty += 28.0
	_draw_advice(idx, it, x, ty, d)


## Valid alternatives of a recommendation and (expert view) the matched
## rules, guide tags and counters, below the sell / undo line.
func _draw_advice(idx: int, it: ArmoryItemDef, x: float, ty: float, d: Rect2) -> void:
	var w := d.end.x - 16.0 - x
	var limit := d.end.y - 8.0
	var a := model.advice_for(idx)
	if a != null and not a.alternatives.is_empty() and ty + 24.0 <= limit:
		var names := PackedStringArray()
		for ai in a.alternatives:
			names.append(ctx.client.catalog.at(ai).label())
		text(_fit(tr("HUD_SHOP_ALTS") % ", ".join(names), 14, w), Vector2(x, ty + 10.0), 14, HudPalette.MUTED)
		ty += 24.0
	if not expert:
		return
	var lines := PackedStringArray()
	if a != null and not a.rules.is_empty():
		lines.append(tr("HUD_SHOP_EXPERT_RULES") % ", ".join(a.rules))
	if not it.tags.is_empty():
		lines.append(tr("HUD_SHOP_EXPERT_TAGS") % ", ".join(it.tags))
	if not it.counter_tags.is_empty():
		lines.append(tr("HUD_SHOP_EXPERT_COUNTERS") % ", ".join(it.counter_tags))
	for l in lines:
		if ty + 20.0 > limit:
			break
		text(_fit(l, 13, w), Vector2(x, ty + 10.0), 13, HudPalette.DIM, ctx.font_mono)
		ty += 20.0


## Why the item is unavailable, or what a buy would swap out.
func _note(index: int, st: int) -> String:
	if st == ShopModel.State.AVAILABLE:
		var it := ctx.client.catalog.at(index)
		var cur := model.held_item(it)
		if cur != null and cur != it:
			return tr("HUD_SHOP_REPLACES") % [cur.display_name, model.swap_credit(index)]
		return ""
	return _reason(index, st)


## "CORE - Mana guns only - New mount": shelf, family rule, what a buy does.
func _kind_line(it: ArmoryItemDef, idx: int = -1) -> String:
	var fam := ""
	match it.family:
		ArmoryItemDef.Family.CRYSTAL:
			fam = " - " + tr("HUD_ARMORY_MANA_ONLY")
		ArmoryItemDef.Family.CHIP:
			fam = " - " + tr("HUD_ARMORY_MECH_ONLY")
	var kind := (" - " + tr(model.kind_key(idx))) if idx >= 0 and model.kind_key(idx) != "" else ""
	return tr(ShopModel.TAB_KEYS[ShopModel.tab_of(it)]) + fam + kind


## "Damage +6%" for one tier row.
func _effect_text(it: ArmoryItemDef, row: Dictionary) -> String:
	var s := _fmt_stat(it.stat, it.op, float(row["value"]))
	if it.stat2 != &"":
		s += ", " + _fmt_stat(it.stat2, it.op2, float(row["value2"]))
	return s


func _fmt_stat(stat: StringName, op: int, v: float) -> String:
	var name_ := tr(STAT_KEYS[stat]) if STAT_KEYS.has(stat) else String(stat)
	var num := ""
	if stat == &"regen_delay":
		num = "%+.1f s" % v
	elif op == Modifier.Op.ADD and stat != &"mod_damage":
		num = "%+d" % roundi(v)
	else:
		num = "%+d%%" % roundi(v * 100.0)
	return name_ + " " + num


## Per-hit body damage now vs after the next tier (level L and M_dmg).
func _damage_delta(p: SnapshotData.ProgressState, it: ArmoryItemDef) -> String:
	var wd := ctx.client.hero_def.weapon
	var lvl := DamageMath.level_mult(p.level)
	var slot := model.slot_of(it)
	var same := model.held_tier(ctx.client.catalog.index_of(it.id)) > 0
	var tier := p.mount_tier[slot] if same else 0
	var held := ctx.client.catalog.at(p.mount_item[slot])
	var cur_m := held.values[p.mount_tier[slot] - 1] if held != null and held.stat == &"mod_damage" else 0.0
	var next_m := it.values[mini(tier, it.tiers() - 1)]
	var a := wd.damage * lvl * (1.0 + cur_m)
	var b := wd.damage * lvl * (1.0 + minf(0.25, next_m))
	return tr("HUD_ARMORY_DMG_DELTA") % [a, b, (b / a - 1.0) * 100.0]


func _draw_footer() -> void:
	var y := size.y - FOOTER_H
	draw_line(Vector2(PAD, y), Vector2(size.x - PAD, y), HudPalette.HAIR_STRONG, 1.0)
	var pad := not Input.get_connected_joypads().is_empty()
	var keys := tr("HUD_SHOP_PAD_KEYS") if pad else tr("HUD_SHOP_KEYS")
	if tab == ShopModel.Tab.BUILDS:
		# No buy button here: the key line gets the full width, one line, centred in the footer.
		keys = tr("HUD_BUILDS_PAD") if pad else tr("HUD_BUILDS_KEYS")
		text(_fit(keys, 13, size.x - 2.0 * PAD), Vector2(PAD, y + FOOTER_H * 0.5 + 5.0), 13, HudPalette.MUTED)
		return
	draw_multiline_string(ctx.font_body, Vector2(PAD, y + 30.0), keys, HORIZONTAL_ALIGNMENT_LEFT,
		_buy_rect().position.x - PAD - 12.0, ts(13), 2, HudPalette.MUTED)
	var idx := _sel_index()
	if idx < 0:
		return
	var st := model.state(idx)
	var it := ctx.client.catalog.at(idx)
	var b := _buy_rect()
	var ok := st == ShopModel.State.AVAILABLE
	# v0.12: brass cut-corner BUY button with an ink ↵ chip; ghost when unavailable.
	var bl := _buy_label(idx, it, st)
	if ok:
		cut_fill(b, 12.0, HudPalette.BRASS)
		# Label shrinks (19 down to 13) so label + key chip stay inside the button.
		var bsz := 19
		while bsz > 13 and caps_width(bl, bsz, 0.2) + 42.0 > b.size.x - 16.0:
			bsz -= 1
		var f := ctx.caps_font(ts(bsz), 0.2)
		var lw := f.get_string_size(bl.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, ts(bsz)).x
		var lx := b.get_center().x - (lw + 42.0) * 0.5
		draw_string(f, Vector2(lx, b.get_center().y + ts(bsz) * 0.36), bl.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, ts(bsz), HudPalette.INK)
		var kr := Rect2(Vector2(lx + lw + 12.0, b.get_center().y - 14.0), Vector2(30.0, 28.0))
		draw_rect(kr.grow(-0.5), Color(HudPalette.INK, 0.5), false, 1.0)
		draw_string(ctx.font_mono, Vector2(kr.position.x, kr.get_center().y + ts(15) * 0.36), "↵", HORIZONTAL_ALIGNMENT_CENTER,
			kr.size.x, ts(15), HudPalette.INK)
	else:
		cut_line(b, 12.0, HudPalette.HAIR_STRONG, 1.0)
		var gsz := 17
		while gsz > 11 and caps_width(bl, gsz, 0.16) > b.size.x - 16.0:
			gsz -= 1
		caps_c(bl, b.get_center(), gsz, HudPalette.DIM, 0.16)
	var s := _sell_rect()
	var sock := model.sell_socket(idx)
	var label := ""
	var can := false
	if sock >= 0:
		label = (tr("HUD_SHOP_BTN_UNDO") if model.is_undo(sock) else tr("HUD_SHOP_BTN_SELL")) % model.sell_value(sock)
		can = true
	elif model.undo_arg(idx) >= 0:
		label = tr("HUD_SHOP_BTN_UNDO") % model.undo_value(idx)
		can = true
	elif model.undo_arg(_last_index) >= 0:
		label = tr("HUD_SHOP_BTN_UNDO") % model.undo_value(_last_index)
		can = true
	else:
		label = tr("HUD_SHOP_BTN_SELL_NA")
	draw_rect(s.grow(-0.5), HudPalette.HAIR_STRONG, false, 1.0)  # ghost SELL
	var lsz := 16
	while lsz > 11 and caps_width(label, lsz, 0.2) > s.size.x - 16.0:
		lsz -= 1
	if caps_width(label, lsz, 0.2) > s.size.x - 16.0:  # still too long: two lines
		draw_multiline_string(ctx.font_body, Vector2(s.position.x + 8.0, s.get_center().y + 4.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, s.size.x - 16.0, ts(12), 2, HudPalette.MUTED if can else HudPalette.DIM)
	else:
		caps_c(label, s.get_center(), lsz, HudPalette.MUTED if can else HudPalette.DIM, 0.2)


func _buy_label(index: int, it: ArmoryItemDef, st: int) -> String:
	match st:
		ShopModel.State.AVAILABLE, ShopModel.State.CANT_AFFORD:
			var cost := HudFormat.thousands(model.purchase_cost(index))
			var held := model.held_tier(index)
			if held > 0 and it.kind == ArmoryItemDef.Kind.MOUNT or held > 0 and it.kind == ArmoryItemDef.Kind.AMMO:
				return tr("HUD_SHOP_BTN_UPGRADE") % [TIER_NAMES[held + 1], cost]
			return tr("HUD_SHOP_BTN_BUY") % cost
	return _reason(index, st)


func _draw_toast() -> void:
	if _toast_t <= 0.0:
		return
	var a := clampf(_toast_t / 0.4, 0.0, 1.0)
	var w := text_width(_toast, 22, ctx.font_display) + 56.0
	var r := Rect2(PAD + _left_w() * 0.5 - w * 0.5, size.y - FOOTER_H - BUILD_H - 54.0, w, 46.0)
	draw_rect(r, Color(HudPalette.INK_DEEP, 0.92 * a))
	draw_rect(Rect2(r.end.x - 3.0, r.position.y, 3.0, r.size.y), Color(_toast_col, a))
	caps_c(_toast, r.get_center(), 19, Color(HudPalette.IVORY, a), 0.12)


## `t` cut with ".." so it fits `max_w` at `size_`.
func _fit(t: String, size_: int, max_w: float, font: Font = null) -> String:
	if text_width(t, size_, font) <= max_w:
		return t
	var s := t
	while s.length() > 1 and text_width(s + "..", size_, font) > max_w:
		s = s.left(s.length() - 1)
	return s + ".."
