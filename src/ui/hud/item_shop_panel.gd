class_name ItemShopPanel
extends HudWidget
## Armory v2 shop screen (design/gdd/items-and-armory.md §3.9, League-style):
## tabs Recommended / All Items / Item Sets over an always-on bottom strip
## (Lumen, the 4 gun sockets with the Chamber's type + mod, the 6 open slots
## with spares unlit, the squad / Med-Pack row, "Signatures n/2", Undo last
## and Sell on the focused owned item). Used by HudRoot when the catalog is a
## recipe catalog; the v1 catalog keeps ArmoryPanel.
##
## Layout is designed on a 1200 x 634 canvas and scaled to the panel (`_k`),
## so 1080p is the 720p layout scaled (§3.9). Pure view: the logic is
## ItemShopModel / BuildsViewModel, every request goes through
## PlayerInputSource.request_action and the server re-checks it; the toast
## shows the exact server Result (shop_seq / shop_result).
##
## Keys (parity with ArmoryPanel, docs/armory.md): F / interact or B opens on
## the pad, Esc / pad B closes; Q / E, PageUp / PageDown, LB / RB switch tabs;
## arrows / D-pad move (left of the grid: the stat filters; below the items:
## the bottom strip); Enter / A buys (the next part on a Recommended card);
## Backspace / X sells the focused owned item, or undoes it when it was bought
## this visit; Ctrl+Z / R3 Undo last; R / L3 jumps to the advisor's next buy;
## / or Ctrl+F searches; Tab / View clears the filters. Item Sets: Enter / A
## use, N / L3 new from the guide, D / R3 duplicate, Delete / X twice delete,
## C copy, V paste. Mouse: click focuses, double-click buys, right-click on an
## owned item sells / undoes, wheel scrolls.

const VW: float = 1200.0
const VH: float = 634.0
const PAD: float = 16.0
const BODY_Y: float = 52.0
const BODY_B: float = 470.0
const STRIP_Y: float = 482.0
const CARD_H: float = 64.0
const CARD_PITCH: float = 70.0
const TILE: float = 42.0
const TILE_PITCH_X: float = 48.0
const TILE_PITCH_Y: float = 58.0
const GRID_X: float = 160.0
const GRID_W: float = 676.0
const DETAIL_X: float = 846.0
const REC_RIGHT_X: float = 820.0
const TOAST_LIFE_S: float = 2.5
const HINT_LIFE_S: float = 2.5
const PENDING_TIMEOUT_S: float = 1.5

enum Area { MAIN, FILTERS, STRIP }

var open: bool = false
var tab: int = ItemShopModel.Tab.RECOMMENDED
var model: ItemShopModel
var builds_vm: BuildsViewModel
var area: int = Area.MAIN
var query: String = ""
var searching: bool = false
## Focused entry of `_items` (Recommended cards / All Items tiles) or Item Sets row.
var sel: int = 0
var filter_sel: int = 0
## Focused inventory place (ItemShopModel.P_*) while area == STRIP.
var strip_sel: int = 0

var _k: float = 1.0
var _items: Array[Dictionary] = []
var _labels: Array[Dictionary] = []
var _scroll: float = 0.0
var _view: Vector2 = Vector2(BODY_Y, BODY_B)
var _held: Dictionary = {}
var _edges: Dictionary = {}
var _econ: EconomyRulesDef
var _guides: RecommendedBuildsDef
var _advice_rules: AdviceRulesDef
var _toast: String = ""
var _toast_t: float = 0.0
var _toast_col: Color = HudPalette.TEAL
var _hint_t: float = 0.0
var _pending: Dictionary = {}
var _confirm: int = -1
var _mouse_before: int = -1
var _was_open: bool = false
var _auto_open: bool = false
var _debug_builds: bool = false
var _debug_catalog: bool = false

const _KEYS: Array[int] = [KEY_F, KEY_B, KEY_ESCAPE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER,
	KEY_BACKSPACE, KEY_Q, KEY_E, KEY_PAGEUP, KEY_PAGEDOWN, KEY_SLASH, KEY_R, KEY_Z, KEY_TAB, KEY_N, KEY_D, KEY_C, KEY_V,
	KEY_DELETE]
const _JOY: Array[int] = [JOY_BUTTON_Y, JOY_BUTTON_B, JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
	JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER,
	JOY_BUTTON_RIGHT_STICK, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_BACK]


func bind(c: HudContext) -> void:
	super(c)
	_econ = load(GameSession.ECONOMY_RULES) as EconomyRulesDef
	_guides = load(RecommendedBuildsDef.active_path()) as RecommendedBuildsDef
	_advice_rules = load(AdviceRulesDef.DEFAULT_PATH) as AdviceRulesDef
	var lc = c.session.get("launch_config") if c.session != null else null
	_auto_open = lc != null and lc.get("debug_armory") == true
	_debug_builds = lc != null and lc.get("debug_armory_builds") == true
	_debug_catalog = lc != null and lc.get("debug_armory_catalog") == true
	# Evidence runs use an in-memory store, never the player's file.
	builds_vm = BuildsViewModel.new(null, "" if _debug_builds else CustomBuildStore.DEFAULT_PATH)
	builds_vm.load_store()


## True while something must be drawn: the shop or the off-pad hint.
func wants_draw() -> bool:
	return open or _hint_t > 0.0


# --- Per-frame update -------------------------------------------------------------

## Polls keys, open state, toasts and pending requests (HudRoot, each frame).
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
		model = ItemShopModel.new()
	model.catalog = client.catalog
	model.rules = _econ
	model.builds = _guides
	model.hero_id = client.hero_def.id
	model.weapon = client.hero_def.weapon
	model.advice_rules = _advice_rules
	builds_vm.setup(client.hero_def.id, client.catalog, client.hero_def.weapon, _guides)
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
	if not searching:
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
		_layout()
		if not searching:
			_keys()
			_layout()
	mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if client.player_input != null:
		client.player_input.ui_captured = open


func _sync_open() -> void:
	if open == _was_open:
		return
	_was_open = open
	if open:
		tab = ItemShopModel.Tab.RECOMMENDED
		area = Area.MAIN
		query = ""
		searching = false
		_scroll = 0.0
		sel = 0
		if _debug_builds:
			_debug_builds = false
			var e := builds_vm.new_from_default()
			builds_vm.use(e)
			tab = ItemShopModel.Tab.SETS
			sel = maxi(0, e)
		elif _debug_catalog:
			_debug_catalog = false
			tab = ItemShopModel.Tab.ALL
			_layout()
			_focus_index(ctx.client.catalog.index_of(&"ember_heart"))
		else:
			_layout()
			_jump_next()
		_mouse_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		searching = false
		_confirm = -1
		if _mouse_before == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_mouse_before = -1


func _update_context(client: ClientWorld) -> void:
	var team := client.own_team()
	var allies: Array = client.team_hero_defs(team)
	allies.append(client.hero_def)
	var enemies: Array = client.team_hero_defs(1 - team) if team == 0 or team == 1 else []
	var size_ := maxi(allies.size(), enemies.size())
	var t := client.match_state.time_s if client.match_state != null else 0.0
	model.set_context(t, &"3v3" if size_ <= 3 else &"5v5", size_, enemies, allies)


func _toggle_edge() -> bool:
	if InputMap.has_action(&"interact"):
		return _track(2001, Input.is_action_pressed(&"interact"))
	return _e(KEY_F) or _je(JOY_BUTTON_Y)


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


# --- Keys ---------------------------------------------------------------------------

func _keys() -> void:
	if _e(KEY_ESCAPE) or _je(JOY_BUTTON_B):
		open = false
		return
	if _e(KEY_Q) or _e(KEY_PAGEUP) or _je(JOY_BUTTON_LEFT_SHOULDER):
		_set_tab(posmod(tab - 1, 3))
	if _e(KEY_E) or _e(KEY_PAGEDOWN) or _je(JOY_BUTTON_RIGHT_SHOULDER):
		_set_tab(posmod(tab + 1, 3))
	if (_e(KEY_Z) and Input.is_key_pressed(KEY_CTRL)) or _je(JOY_BUTTON_RIGHT_STICK) and tab != ItemShopModel.Tab.SETS:
		_undo_last()
	if tab == ItemShopModel.Tab.SETS:
		_sets_keys()
		return
	if _e(KEY_TAB) or _je(JOY_BUTTON_BACK):
		model.filters.clear()
	if _e(KEY_SLASH) or (_e(KEY_F) and Input.is_key_pressed(KEY_CTRL)):
		if tab == ItemShopModel.Tab.ALL:
			searching = true
	if _e(KEY_R) or _je(JOY_BUTTON_LEFT_STICK):
		_jump_next()
	var dir := Vector2.ZERO
	if _e(KEY_UP) or _je(JOY_BUTTON_DPAD_UP):
		dir = Vector2.UP
	elif _e(KEY_DOWN) or _je(JOY_BUTTON_DPAD_DOWN):
		dir = Vector2.DOWN
	elif _e(KEY_LEFT) or _je(JOY_BUTTON_DPAD_LEFT):
		dir = Vector2.LEFT
	elif _e(KEY_RIGHT) or _je(JOY_BUTTON_DPAD_RIGHT):
		dir = Vector2.RIGHT
	if dir != Vector2.ZERO:
		_move(dir)
	var buy := _e(KEY_ENTER) or _e(KEY_KP_ENTER) or _je(JOY_BUTTON_A)
	var sell := _e(KEY_BACKSPACE) or _je(JOY_BUTTON_X)
	match area:
		Area.FILTERS:
			if buy:
				model.toggle_filter(ItemShopModel.FILTERS[filter_sel])
				sel = 0
				_scroll = 0.0
		Area.STRIP:
			if sell:
				_sell_place(strip_sel)
		_:
			var idx := _sel_index()
			if buy and idx >= 0:
				_buy(idx)
			if sell and idx >= 0:
				_sell_focused()


func _move(dir: Vector2) -> void:
	_confirm = -1
	match area:
		Area.FILTERS:
			if dir.y != 0.0:
				filter_sel = clampi(filter_sel + int(dir.y), 0, ItemShopModel.FILTERS.size() - 1)
			elif dir.x > 0.0:
				area = Area.MAIN
		Area.STRIP:
			if dir.x != 0.0:
				strip_sel = clampi(strip_sel + int(dir.x), 0, ItemShopModel.PLACES - 1)
			elif dir.y < 0.0:
				area = Area.MAIN
		_:
			var to := _nav(sel, dir)
			if to >= 0:
				sel = to
				_ensure_visible()
			elif dir.y > 0.0:
				area = Area.STRIP
			elif dir.x < 0.0 and tab == ItemShopModel.Tab.ALL:
				area = Area.FILTERS


## Spatial navigation over `_items` (virtual rects): the nearest item in `dir`
## (same row first for left / right; nearest row, then nearest x for up / down).
func _nav(from: int, dir: Vector2) -> int:
	if from < 0 or from >= _items.size():
		return 0 if not _items.is_empty() else -1
	var c: Vector2 = (_items[from]["rect"] as Rect2).get_center()
	var best := -1
	var best_d := INF
	for i in _items.size():
		if i == from:
			continue
		var o: Vector2 = (_items[i]["rect"] as Rect2).get_center()
		var d := o - c
		var score := INF
		if dir.x != 0.0:
			if signf(d.x) == signf(dir.x) and absf(d.y) < 20.0:
				score = absf(d.x)
		elif signf(d.y) == signf(dir.y) and absf(d.y) > 10.0:
			score = absf(d.y) * 4.0 + absf(d.x)
		if score < best_d:
			best_d = score
			best = i
	return best


func _ensure_visible() -> void:
	if sel < 0 or sel >= _items.size() or not bool(_items[sel].get("scroll", false)):
		return
	var r: Rect2 = _items[sel]["rect"]
	if r.position.y - _scroll < _view.x:
		_scroll = r.position.y - _view.x
	elif r.end.y - _scroll > _view.y:
		_scroll = r.end.y - _view.y
	_scroll = maxf(0.0, _scroll)


func _set_tab(t: int) -> void:
	tab = t
	sel = 0
	area = Area.MAIN
	_scroll = 0.0
	searching = false
	_confirm = -1
	_layout()


func _sel_index() -> int:
	return int(_items[sel]["index"]) if sel >= 0 and sel < _items.size() else -1


## Focuses the advisor's next buy (Recommended: its card; All Items: its tile).
func _jump_next() -> void:
	var a := model.advice().best()
	if a == null:
		return
	if tab == ItemShopModel.Tab.RECOMMENDED:
		for i in _items.size():
			if int(_items[i].get("goal", -1)) == a.goal_index or int(_items[i]["index"]) == a.item_index:
				sel = i
				area = Area.MAIN
				_ensure_visible()
				return
	_focus_index(a.item_index)


func _focus_index(idx: int) -> void:
	for i in _items.size():
		if int(_items[i]["index"]) == idx:
			sel = i
			area = Area.MAIN
			_ensure_visible()
			return


func _sets_keys() -> void:
	var n := builds_vm.entries().size()
	if _e(KEY_DOWN) or _je(JOY_BUTTON_DPAD_DOWN):
		sel = clampi(sel + 1, 0, n - 1)
		builds_vm.confirm_delete = ""
	if _e(KEY_UP) or _je(JOY_BUTTON_DPAD_UP):
		sel = clampi(sel - 1, 0, n - 1)
		builds_vm.confirm_delete = ""
	if _e(KEY_ENTER) or _e(KEY_KP_ENTER) or _je(JOY_BUTTON_A):
		if builds_vm.use(sel):
			_show_toast(tr("HUD_BUILDS_USED") % _set_name(builds_vm.entries()[sel]), HudPalette.TEAL)
	if _e(KEY_N) or _je(JOY_BUTTON_LEFT_STICK):
		_select_set(builds_vm.new_from_default(), "HUD_BUILDS_CREATED")
	if _e(KEY_D) or _je(JOY_BUTTON_RIGHT_STICK):
		_select_set(builds_vm.duplicate_entry(sel), "HUD_BUILDS_CREATED")
	if _e(KEY_DELETE) or _e(KEY_BACKSPACE) or _je(JOY_BUTTON_X):
		if builds_vm.delete_entry(sel):
			sel = clampi(sel, 0, builds_vm.entries().size() - 1)
			_show_toast(tr("HUD_BUILDS_DELETED"), HudPalette.BRASS)
		elif builds_vm.confirm_delete != "":
			_show_toast(tr("HUD_BUILDS_DELETE_CONFIRM"), HudPalette.BRASS)
	if _e(KEY_C):
		var t := builds_vm.export_entry(sel)
		if t != "":
			DisplayServer.clipboard_set(t)
			_show_toast(tr("HUD_BUILDS_COPIED"), HudPalette.TEAL)
	if _e(KEY_V):
		var e := builds_vm.import_text(DisplayServer.clipboard_get())
		if e >= 0:
			_select_set(e, "HUD_BUILDS_PASTED")
		elif builds_vm.last_error == CustomBuildStore.ERR_OLD_ARMORY:
			_show_toast(tr("HUD_SHOP2_SETS_OLD"), HudPalette.WARN)
		else:
			_show_toast(tr("HUD_BUILDS_PASTE_BAD"), HudPalette.WARN)


func _select_set(entry: int, key: String) -> void:
	if entry >= 0:
		sel = entry
		_show_toast(tr(key), HudPalette.TEAL)


func _set_name(e: Dictionary) -> String:
	return tr("HUD_BUILDS_DEFAULT") if String(e["id"]) == "" else String(e["name"])


# --- Requests -----------------------------------------------------------------------

func _request(action: int, arg: int) -> void:
	if ctx.client.player_input != null:
		ctx.client.player_input.request_action(action, arg)


## Buys `index` unless the model already knows the server would refuse it. A
## socket swap that sells a held part asks for a second press (§3.4 rule 6).
func _buy(index: int) -> void:
	var st := model.state(index)
	if st != ItemShopModel.State.AVAILABLE:
		_show_toast(_state_text(index, st), HudPalette.WARN)
		return
	var it := model.catalog.at(index)
	var credit := model.swap_credit(index)
	if credit > 0 and it.kind != ArmoryItemDef.Kind.AMMO_MOD and _confirm != index:
		_confirm = index
		_show_toast(tr("HUD_SHOP2_SWAP_CONFIRM") % credit, HudPalette.BRASS)
		return
	_confirm = -1
	_send("buy", index, InputCommand.ACTION_BUY, index, model.cost(index) - credit)


## Sell / undo on the focused item: its first owned place (an undoable one
## first), or the squad / Med-Pack row undo.
func _sell_focused() -> void:
	var idx := _sel_index()
	var places := model.places_of(idx)
	for k in places:
		if model.can_undo(k):
			_sell_place(k)
			return
	if not places.is_empty():
		_sell_place(places[places.size() - 1])
		return
	var arg := model.row_undo_arg(idx)
	if arg >= 0:
		_send("undo", idx, InputCommand.ACTION_SELL, arg, model.catalog.at(idx).price(1))
	else:
		_show_toast(tr("HUD_SHOP_NO_SELL"), HudPalette.WARN)


func _sell_place(k: int) -> void:
	var idx := model.item_at(k)
	if idx < 0:
		_show_toast(tr("HUD_SHOP_NO_SELL"), HudPalette.WARN)
		return
	if model.can_undo(k):
		_send("undo", idx, InputCommand.ACTION_SELL, model.undo_arg(k), 0)
	else:
		_send("sell", idx, InputCommand.ACTION_SELL, model.sell_arg(k), model.sell_value(k))


func _undo_last() -> void:
	if not model.undo_last_available():
		_show_toast(tr("HUD_SHOP_NO_UNDO"), HudPalette.WARN)
		return
	_send("undo_last", -1, InputCommand.ACTION_SELL, InputCommand.UNDO_LAST, 0)


func _send(kind: String, index: int, action: int, arg: int, value: int) -> void:
	_pending = {"kind": kind, "index": index, "value": value, "seq": ctx.client.progress.shop_seq, "t": 0.0}
	_request(action, arg)


## Shows the server's answer to the last request (shop_seq / shop_result).
func _check_pending(dt: float) -> void:
	if _pending.is_empty():
		return
	_pending["t"] = float(_pending["t"]) + dt
	var p := ctx.client.progress
	if p.shop_seq != int(_pending["seq"]):
		var name_ := model.name_of(int(_pending["index"])) if int(_pending["index"]) >= 0 else ""
		if p.shop_result == HeroProgress.Result.OK:
			match String(_pending["kind"]):
				"buy":
					_show_toast(tr("HUD_SHOP_TOAST_BOUGHT") % [name_, _pending["value"]], HudPalette.TEAL)
				"sell":
					_show_toast(tr("HUD_SHOP_TOAST_SOLD") % [name_, _pending["value"]], HudPalette.BRASS)
				"undo":
					_show_toast(tr("HUD_SHOP2_TOAST_UNDONE") % name_, HudPalette.BRASS)
				_:
					_show_toast(tr("HUD_SHOP2_TOAST_UNDO_LAST"), HudPalette.BRASS)
		else:
			_show_toast(tr(ItemShopModel.result_key(p.shop_result)), HudPalette.DANGER)
		_pending.clear()
		return
	if float(_pending["t"]) > PENDING_TIMEOUT_S:
		_show_toast(tr("HUD_SHOP_TOAST_NO_ANSWER"), HudPalette.DANGER)
		_pending.clear()


func _show_toast(t: String, col: Color) -> void:
	_toast = t
	_toast_col = col
	_toast_t = TOAST_LIFE_S


## Plain-language greyed reason for State `st` of `index`.
func _state_text(index: int, st: int) -> String:
	if st == ItemShopModel.State.CANT_AFFORD:
		return tr("HUD_SHOP_NEED_LUMEN") % model.shortfall(index)
	var key := ItemShopModel.state_key(st)
	return tr(key) if key != "" else ""


# --- Mouse and search ----------------------------------------------------------------

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
	sel = 0
	_scroll = 0.0
	_layout()
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not open:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var p := mb.position / _k
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN or mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll = maxf(0.0, _scroll + (TILE_PITCH_Y if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -TILE_PITCH_Y))
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_click(p, mb.double_click)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			for k in ItemShopModel.PLACES:
				if _place_rect(k).has_point(p):
					_sell_place(k)
		accept_event()
	elif event is InputEventMouseButton:
		accept_event()


func _click(p: Vector2, double: bool) -> void:
	searching = _search_rect().has_point(p) and tab == ItemShopModel.Tab.ALL
	if _close_rect().has_point(p):
		open = false
		return
	for t in 3:
		if _tab_rect(t).has_point(p):
			_set_tab(t)
			return
	if _undo_rect().has_point(p):
		_undo_last()
		return
	if _sell_rect().has_point(p):
		if area == Area.STRIP:
			_sell_place(strip_sel)
		else:
			_sell_focused()
		return
	for k in ItemShopModel.PLACES:
		if _place_rect(k).has_point(p):
			area = Area.STRIP
			strip_sel = k
			return
	if tab == ItemShopModel.Tab.SETS:
		for i in builds_vm.entries().size():
			if _set_rect(i).has_point(p):
				sel = i
				if double:
					builds_vm.use(i)
		return
	if tab == ItemShopModel.Tab.ALL:
		for f in ItemShopModel.FILTERS.size():
			if _filter_rect(f).has_point(p):
				filter_sel = f
				area = Area.FILTERS
				model.toggle_filter(ItemShopModel.FILTERS[f])
				sel = 0
				_scroll = 0.0
				return
	for i in _items.size():
		if _shown(i).has_point(p):
			sel = i
			area = Area.MAIN
			if double:
				_buy(int(_items[i]["index"]))
			return


# --- Layout (canvas units; _k scales to pixels) ----------------------------------------

func _layout() -> void:
	_k = maxf(0.5, minf(size.x / VW, size.y / VH))
	_items.clear()
	_labels.clear()
	if model == null:
		return
	match tab:
		ItemShopModel.Tab.RECOMMENDED:
			_layout_rec()
		ItemShopModel.Tab.ALL:
			_layout_all()
	sel = clampi(sel, 0, maxi(0, _items.size() - 1)) if tab != ItemShopModel.Tab.SETS \
		else clampi(sel, 0, maxi(0, builds_vm.entries().size() - 1))


func _layout_rec() -> void:
	var s := model.sections()
	var y := BODY_Y + 20.0
	_labels.append({"key": "HUD_SHOP2_SEC_STARTER", "pos": Vector2(PAD, y - 6.0)})
	var starter: Array = s["starter"]
	var sw := (REC_RIGHT_X - PAD - 12.0 - 8.0 * 3.0) / 4.0
	for i in mini(starter.size(), 4):
		_items.append({"rect": Rect2(PAD + i * (sw + 8.0), y, sw, CARD_H), "index": int(starter[i]["next"]),
			"goal": int(starter[i]["goal"]), "card": starter[i]})
	y += CARD_H + 26.0
	_labels.append({"key": "HUD_SHOP2_SEC_CORE", "pos": Vector2(PAD, y - 6.0)})
	_view = Vector2(y, BODY_B)
	var rows: Array = s["core"]
	var cw := (REC_RIGHT_X - PAD - 12.0 - 64.0 - 8.0 * 2.0) / 3.0
	for r in rows.size():
		var ry := y + r * CARD_PITCH
		var cards: Array = rows[r]["cards"]
		_labels.append({"step": r + 1, "pos": Vector2(PAD, ry), "scroll": true, "next": bool(rows[r]["next"])})
		for c in cards.size():
			_items.append({"rect": Rect2(PAD + 64.0 + c * (cw + 8.0), ry, cw, CARD_H), "index": int(cards[c]["next"]),
				"goal": int(cards[c]["goal"]), "card": cards[c], "scroll": true})
	var rx := REC_RIGHT_X
	var rw := VW - PAD - rx
	var yy := BODY_Y + 20.0
	_labels.append({"key": "HUD_SHOP2_SEC_SITUATIONAL", "pos": Vector2(rx, yy - 6.0)})
	var sit: Array = s["situational"]
	if sit.is_empty():
		_labels.append({"key": "HUD_SHOP2_SEC_NONE", "pos": Vector2(rx, yy + 22.0), "muted": true})
		yy += 36.0
	for i in mini(sit.size(), 3):
		_items.append({"rect": Rect2(rx, yy, rw, CARD_H), "index": int(sit[i]["next"]), "goal": int(sit[i]["goal"]),
			"card": sit[i]})
		yy += CARD_PITCH
	yy += 20.0
	_labels.append({"key": "HUD_SHOP2_SEC_AMMO", "pos": Vector2(rx, yy - 6.0)})
	var ammo: Array = s["ammo"]
	for i in mini(ammo.size(), 2):
		_items.append({"rect": Rect2(rx, yy, rw, CARD_H), "index": int(ammo[i]["next"]), "goal": int(ammo[i]["goal"]),
			"card": ammo[i]})
		yy += CARD_PITCH


func _layout_all() -> void:
	_view = Vector2(BODY_Y, BODY_B)
	var per := floori((GRID_W + TILE_PITCH_X - TILE) / TILE_PITCH_X)
	var y := BODY_Y + 16.0
	var col := 0
	var prev := -1
	for sh in model.shelves(query):
		var shelf := int(sh["shelf"])
		var items: Array = sh["items"]
		# Squad and Consumables share a line when it has room (fits 720p without scrolling).
		var join := shelf == ItemShopModel.Shelf.CONSUMABLE and prev == ItemShopModel.Shelf.SQUAD \
			and col + 1 + items.size() <= per
		if join:
			col += 1
			_labels.append({"key": ItemShopModel.SHELF_KEYS[shelf], "pos": Vector2(GRID_X + col * TILE_PITCH_X, y - 4.0 - TILE_PITCH_Y),
				"scroll": true})
			y -= TILE_PITCH_Y
		else:
			col = 0
			_labels.append({"key": ItemShopModel.SHELF_KEYS[shelf], "pos": Vector2(GRID_X, y - 4.0), "scroll": true})
		for i in items.size():
			if col >= per:
				col = 0
				y += TILE_PITCH_Y
			_items.append({"rect": Rect2(GRID_X + col * TILE_PITCH_X, y, TILE, TILE), "index": int(items[i]),
				"scroll": true, "tile": true})
			col += 1
		y += TILE_PITCH_Y + 16.0
		prev = shelf


## Pixel rect of `_items[i]` (scrolled; empty when outside its viewport).
func _shown(i: int) -> Rect2:
	var r: Rect2 = _items[i]["rect"]
	if bool(_items[i].get("scroll", false)):
		r.position.y -= _scroll
		if r.position.y < _view.x - 1.0 or r.end.y > _view.y + 1.0:
			return Rect2()
	return r


func _tab_rect(t: int) -> Rect2:
	var x := 150.0
	for i in t:
		x += _tab_w(i) + 4.0
	return Rect2(x, 8.0, _tab_w(t), 34.0)


func _tab_w(t: int) -> float:
	return caps_width(tr(ItemShopModel.TAB_KEYS[t]), roundi(14 * _k), 0.18) / _k + 28.0


func _search_rect() -> Rect2:
	return Rect2(GRID_X + GRID_W - 250.0, 10.0, 250.0, 30.0)


func _close_rect() -> Rect2:
	return Rect2(VW - PAD - 34.0, 8.0, 34.0, 32.0)


func _filter_rect(f: int) -> Rect2:
	return Rect2(PAD, BODY_Y + 4.0 + f * 29.0, GRID_X - PAD - 12.0, 26.0)


func _set_rect(i: int) -> Rect2:
	return Rect2(PAD, BODY_Y + 8.0 + i * 52.0, 520.0, 46.0)


## Bottom-strip box of inventory place `k`: sockets, the Chamber's two halves, open slots.
func _place_rect(k: int) -> Rect2:
	var y := STRIP_Y + 30.0
	if k <= ItemShopModel.P_FRAME:
		return Rect2(156.0 + k * 62.0, y, 56.0, 56.0)
	if k == ItemShopModel.P_AMMO:
		return Rect2(342.0, y, 50.0, 56.0)
	if k == ItemShopModel.P_MOD:
		return Rect2(394.0, y, 50.0, 56.0)
	return Rect2(470.0 + (k - ItemShopModel.P_SLOT) * 62.0, y, 56.0, 56.0)


func _row_rect() -> Rect2:
	return Rect2(852.0, STRIP_Y + 30.0, 118.0, 56.0)


func _undo_rect() -> Rect2:
	return Rect2(984.0, STRIP_Y + 30.0, VW - PAD - 984.0, 25.0)


func _sell_rect() -> Rect2:
	return Rect2(984.0, STRIP_Y + 60.0, VW - PAD - 984.0, 26.0)


# --- Drawing helpers (canvas units) -----------------------------------------------------

func _px(v: float) -> int:
	return maxi(1, roundi(v * _k))


func _r(r: Rect2) -> Rect2:
	return Rect2(r.position * _k, r.size * _k)


func _t(s: String, x: float, y: float, px: float, col: Color, font: Font = null,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void:
	text(s, Vector2(x, y) * _k, _px(px), col, font, align, w * _k if w > 0.0 else -1.0)


func _c(s: String, x: float, y: float, px: float, col: Color, em: float = 0.18,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void:
	caps(s, Vector2(x, y) * _k, _px(px), col, em, align, w * _k if w > 0.0 else -1.0)


## `s` cut with ".." to fit `w` canvas units at `px`.
func _fit(s: String, px: float, w: float, font: Font = null) -> String:
	var max_w := w * _k
	if text_width(s, _px(px), font) <= max_w:
		return s
	var out := s
	while out.length() > 1 and text_width(out + "..", _px(px), font) > max_w:
		out = out.left(out.length() - 1)
	return out + ".."


func _icon(index: int, r: Rect2, a: float) -> void:
	var it := model.catalog.at(index)
	if it != null:
		ShopIcons.draw_v2(self, it, _r(r), Color(1, 1, 1, a))


func _tick(c: Vector2, s: float, col: Color) -> void:
	ShopIcons.check(self, c * _k, s * _k, col)


# --- Drawing ------------------------------------------------------------------------

func _draw() -> void:
	var client := ctx.client
	if client == null or client.progress == null or model == null:
		return
	if not open:
		if _hint_t > 0.0:
			_draw_hint()
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(HudPalette.INK_DEEP, 0.95))
	_draw_header()
	match tab:
		ItemShopModel.Tab.RECOMMENDED:
			_draw_rec()
		ItemShopModel.Tab.ALL:
			_draw_all()
		_:
			_draw_sets()
	_draw_strip()
	_draw_toast()


func _draw_hint() -> void:
	var t := tr("HUD_SHOP_OFF_PAD")
	var fmt := tr("HUD_SHOP_OFF_PAD_DIR")
	var dir := ArmoryWaypoint.hint_for(ctx.client, ctx.own_team())
	if "%s" in fmt and dir != "":
		t = fmt % dir
	var w := text_width(t, 22, ctx.font_display) + 48.0
	var r := Rect2(size.x * 0.5 - w * 0.5, size.y - 150.0, w, 48.0)
	draw_rect(r, Color(HudPalette.INK_DEEP, 0.8))
	draw_rect(Rect2(r.end.x - 3.0, r.position.y, 3.0, r.size.y), HudPalette.BRASS)
	caps_c(t, r.get_center(), 20, HudPalette.BRASS_HI, 0.16)


func _draw_header() -> void:
	_c(tr("HUD_ARMORY"), PAD, 33.0, 22.0, HudPalette.IVORY, 0.28)
	for t in 3:
		var r := _tab_rect(t)
		var on := t == tab
		if on:
			draw_rect(_r(Rect2(r.position.x + 10.0, r.end.y - 2.0, r.size.x - 20.0, 2.0)), HudPalette.BRASS)
		_c(tr(ItemShopModel.TAB_KEYS[t]), r.position.x, r.position.y + 22.0, 14.0,
			HudPalette.IVORY if on else HudPalette.MUTED, 0.18, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if tab == ItemShopModel.Tab.ALL:
		var s := _search_rect()
		draw_rect(_r(s), Color(HudPalette.INK_DEEP, 0.6))
		draw_rect(_r(s).grow(-0.5), HudPalette.BRASS if searching else HudPalette.HAIR_STRONG, false, 1.0)
		var shown := query + ("_" if searching else "")
		_t(shown if shown != "" else tr("HUD_SHOP_SEARCH"), s.position.x + 10.0, s.position.y + 20.0, 13.0,
			HudPalette.IVORY if shown != "" else HudPalette.DIM)
	var b := model.build()
	if b != null and tab != ItemShopModel.Tab.ALL:
		var sub := tr("HUD_SHOP_BUILD_FOR") % (b.display_name if b != model.custom_guide else b.display_name)
		_t(_fit(sub, 13.0, 380.0), VW - PAD - 44.0 - 380.0, 30.0, 13.0, HudPalette.MUTED, ctx.font_body,
			HORIZONTAL_ALIGNMENT_RIGHT, 380.0)
	var cr := _r(_close_rect())
	draw_rect(cr.grow(-0.5), HudPalette.HAIR_STRONG, false, 1.0)
	var c := cr.get_center()
	var d := 6.0 * _k
	draw_line(c + Vector2(-d, -d), c + Vector2(d, d), HudPalette.MUTED, 1.6)
	draw_line(c + Vector2(-d, d), c + Vector2(d, -d), HudPalette.MUTED, 1.6)
	draw_line(Vector2(PAD, 46.0) * _k, Vector2(VW - PAD, 46.0) * _k, HudPalette.HAIR_STRONG, 1.0)


func _draw_labels() -> void:
	for l in _labels:
		var pos: Vector2 = l["pos"]
		if bool(l.get("scroll", false)):
			pos.y -= _scroll
			if pos.y < _view.x - 2.0 or pos.y > _view.y - 10.0:
				continue
		if l.has("step"):
			var nxt := bool(l.get("next", false))
			_c(tr("HUD_SHOP2_STEP") % int(l["step"]), pos.x, pos.y + 26.0, 12.0,
				HudPalette.BRASS_HI if nxt else HudPalette.MUTED, 0.16)
			if nxt:
				_c(tr("HUD_SHOP_NEXT"), pos.x, pos.y + 44.0, 11.0, HudPalette.TEAL, 0.16)
			continue
		_c(tr(String(l["key"])), pos.x, pos.y, 12.0 if not l.has("muted") else 12.0,
			HudPalette.DIM if l.has("muted") else HudPalette.BRASS, 0.2)


func _draw_rec() -> void:
	_draw_labels()
	for i in _items.size():
		var r := _shown(i)
		if r.size == Vector2.ZERO:
			continue
		_draw_card(r, _items[i]["card"], i == sel and area == Area.MAIN)
	if _items.is_empty():
		_t(tr("HUD_SHOP_NO_BUILD"), PAD, BODY_Y + 60.0, 15.0, HudPalette.MUTED)


## One Recommended card: icon, name, total price, "Next: part · price", reason.
func _draw_card(r: Rect2, c: Dictionary, focused: bool) -> void:
	var goal := int(c["goal"])
	var nxt := int(c["next"])
	var st := int(c["state"])
	var done := bool(c["done"])
	var ok := st == ItemShopModel.State.AVAILABLE
	var a := 1.0 if ok or done or st == ItemShopModel.State.CANT_AFFORD else 0.55
	cut_fill(_r(r), 9.0 * _k, Color(0.051, 0.075, 0.094, 0.92))
	cut_line(_r(r), 9.0 * _k, HudPalette.BRASS if focused else HudPalette.HAIR_STRONG, 1.5 if focused else 1.0)
	_icon(goal, Rect2(r.position + Vector2(8.0, 12.0), Vector2(40.0, 40.0)), a)
	var x := r.position.x + 56.0
	var w := r.end.x - x - 8.0
	var total := HudFormat.thousands(int(c["total"]))
	var tw := text_width(total, _px(13.0), ctx.font_numbers) / _k
	_t(_fit(model.name_of(goal), 14.0, w - tw - 8.0), x, r.position.y + 19.0, 14.0, Color(HudPalette.IVORY, a),
		UiKit.body_font(600))
	_t(total, x, r.position.y + 19.0, 13.0, Color(HudPalette.BRASS_HI, a), ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, w)
	var line := ""
	var col := HudPalette.MUTED
	if done:
		line = tr("HUD_ARMORY_OWNED")
		col = HudPalette.TEAL
		_tick(Vector2(r.end.x - 14.0, r.position.y + 36.0), 5.0, HudPalette.TEAL)
	elif nxt != goal:
		line = tr("HUD_SHOP2_NEXT_PART") % [model.name_of(nxt), HudFormat.thousands(int(c["next_cost"]))]
		col = HudPalette.IVORY if ok else HudPalette.WARN_UI
	else:
		line = tr("HUD_SHOP2_BUY_NOW") % HudFormat.thousands(int(c["next_cost"]))
		col = HudPalette.IVORY if ok else HudPalette.WARN_UI
	_t(_fit(line, 12.0, w), x, r.position.y + 37.0, 12.0, Color(col, maxf(a, 0.8)), ctx.font_body)
	var reason := tr(String(c["reason"]))
	var rcol := HudPalette.BRASS_HI if bool(c["situational"]) else HudPalette.MUTED
	if not done and not ok and st != ItemShopModel.State.CANT_AFFORD:
		reason = _state_text(nxt, st)
		rcol = HudPalette.WARN_UI
	if bool(c["situational"]) and (done or ok or st == ItemShopModel.State.CANT_AFFORD):
		# Reason chip (§3.9: counter items carry their reason as a chip).
		var cw := minf(text_width(reason, _px(11.0), ctx.font_body) / _k + 12.0, w)
		draw_rect(_r(Rect2(x - 2.0, r.position.y + 44.0, cw, 15.0)), Color(HudPalette.BRASS, 0.18))
	_t(_fit(reason, 11.0, w - 4.0), x + (3.0 if bool(c["situational"]) else 0.0), r.position.y + 56.0, 11.0, rcol,
		ctx.font_body)


func _draw_all() -> void:
	# Stat filters (left).
	for f in ItemShopModel.FILTERS.size():
		var fr := _filter_rect(f)
		var on := model.filters.has(ItemShopModel.FILTERS[f])
		var foc := area == Area.FILTERS and f == filter_sel
		if foc:
			draw_rect(_r(fr), Color(HudPalette.BRASS, 0.14))
		var box := Rect2(fr.position + Vector2(6.0, 7.0), Vector2(12.0, 12.0))
		draw_rect(_r(box), HudPalette.BRASS if on else HudPalette.HAIR_STRONG, on, 1.0)
		_t(tr("HUD_SHOP2_F_" + String(ItemShopModel.FILTERS[f]).to_upper()), fr.position.x + 26.0, fr.position.y + 18.0,
			13.0, HudPalette.IVORY if on or foc else HudPalette.MUTED, ctx.font_body)
	_draw_labels()
	for i in _items.size():
		var r := _shown(i)
		if r.size == Vector2.ZERO:
			continue
		var idx := int(_items[i]["index"])
		var st := model.state(idx)
		var owned := not model.places_of(idx).is_empty() or st == ItemShopModel.State.OWNED
		var a := 1.0 if st == ItemShopModel.State.AVAILABLE or owned else (0.6 if st == ItemShopModel.State.CANT_AFFORD else 0.35)
		var foc := i == sel and area == Area.MAIN
		cut_fill(_r(r), 6.0 * _k, Color(0.051, 0.075, 0.094, 0.92))
		cut_line(_r(r), 6.0 * _k, HudPalette.BRASS if foc else Color(HudPalette.HAIR_STRONG, a), 2.0 if foc else 1.0)
		_icon(idx, r.grow(-5.0), a)
		if owned:
			_tick(Vector2(r.end.x - 7.0, r.position.y + 7.0), 4.0, HudPalette.TEAL)
		var price := HudFormat.thousands(model.cost(idx) if not owned else model.total(idx))
		_t(price, r.position.x - 3.0, r.end.y + 12.0, 11.0,
			Color(HudPalette.BRASS_HI if st == ItemShopModel.State.AVAILABLE else HudPalette.MUTED, maxf(a, 0.7)),
			ctx.font_numbers, HORIZONTAL_ALIGNMENT_CENTER, TILE + 6.0)
	if _items.is_empty():
		_t(tr("HUD_SHOP_EMPTY"), GRID_X, BODY_Y + 40.0, 15.0, HudPalette.MUTED)
	draw_line(Vector2(DETAIL_X - 10.0, BODY_Y) * _k, Vector2(DETAIL_X - 10.0, BODY_B) * _k, HudPalette.HAIR_STRONG, 1.0)
	var idx := _sel_index()
	if area == Area.STRIP:
		idx = model.item_at(strip_sel)
	if idx >= 0:
		_draw_detail(idx)


## Right pane: name, tier and where it goes, stats with "(capped)", passive,
## recipe tree (owned parts ticked, cost to complete), Builds into, buy state.
func _draw_detail(idx: int) -> void:
	var it := model.catalog.at(idx)
	var x := DETAIL_X
	var w := VW - PAD - x
	var y := BODY_Y + 20.0
	_t(_fit(model.name_of(idx), 17.0, w), x, y, 17.0, HudPalette.IVORY, ctx.font_display)
	y += 20.0
	var where := ""
	if it.uses_open_slot():
		where = tr("HUD_SHOP2_OPEN_SLOT")
	elif it.socket != ArmoryItemDef.Socket.NONE:
		where = tr("HUD_SHOP2_SOCKET") % tr(model.shows_on_key(idx))
	var tier_key: String = ["", "HUD_SHOP2_TIER_COMPONENT", "HUD_SHOP2_TIER_ASSEMBLY", "HUD_SHOP2_TIER_SIGNATURE"][int(it.tier)]
	var head := tr(tier_key) if tier_key != "" else ""
	if where != "":
		head = where if head == "" else head + "  ·  " + where
	if it.body_anchor != &"":
		head += "  ·  " + tr("HUD_SHOP2_SHOWS_ON") % tr(model.shows_on_key(idx))
	_t(_fit(head, 12.0, w), x, y, 12.0, HudPalette.MUTED, ctx.font_body)
	y += 18.0
	for l in model.stat_lines(idx):
		var key := String(l["key"])
		var name_ := tr(key) if key != "" else String(l["id"])
		var line := "%s  %s" % [ItemShopModel.stat_text(String(l["id"]), float(l["value"])), name_]
		if bool(l["capped"]):
			line += "  " + tr("HUD_SHOP2_CAPPED")
		_t(_fit(line, 13.0, w), x, y, 13.0, HudPalette.WARN_UI if bool(l["capped"]) else HudPalette.IVORY, ctx.font_body)
		y += 17.0
	if it.effect_label() != "" and it.stat_ids.is_empty():
		_t(_fit(it.effect_label(), 12.0, w), x, y, 12.0, HudPalette.IVORY, ctx.font_body)
		y += 17.0
	if it.passive != &"":
		var ptxt := tr("HUD_PASSIVE_" + String(it.passive).to_upper())
		draw_multiline_string(ctx.font_body, Vector2(x, y) * _k, ptxt, HORIZONTAL_ALIGNMENT_LEFT, w * _k, ts(_px(11.0)), 2,
			HudPalette.BRASS_HI)
		y += 32.0
	# Recipe tree.
	var tree := model.tree(idx)
	if tree.size() > 1:
		y += 4.0
		_c(tr("HUD_SHOP2_RECIPE"), x, y, 11.0, HudPalette.BRASS, 0.2)
		y += 4.0
		var lines := 0
		for e in tree:
			if lines >= 7:
				break
			var d := int(e["depth"])
			var ex := x + 8.0 + d * 16.0
			_icon(int(e["index"]), Rect2(ex, y + 3.0, 16.0, 16.0), 1.0 if bool(e["owned"]) else 0.6)
			var label := model.name_of(int(e["index"]))
			_t(_fit(label, 12.0, w - (ex - x) - 70.0), ex + 22.0, y + 16.0, 12.0,
				HudPalette.TEAL if bool(e["owned"]) else HudPalette.IVORY, ctx.font_body)
			if bool(e["owned"]):
				_tick(Vector2(x + w - 8.0, y + 11.0), 4.0, HudPalette.TEAL)
			else:
				var ec: ArmoryItemDef = model.catalog.at(int(e["index"]))
				var p := ec.combine_cost if d == 0 else (ec.price(1) if ec.recipe.is_empty() else ec.combine_cost)
				_t("+" + HudFormat.thousands(p), x, y + 16.0, 11.0, HudPalette.MUTED, ctx.font_numbers,
					HORIZONTAL_ALIGNMENT_RIGHT, w)
			y += 19.0
			lines += 1
		y += 2.0
		_t(tr("HUD_SHOP2_TO_COMPLETE") % HudFormat.thousands(model.cost(idx)), x, y + 12.0, 13.0, HudPalette.BRASS_HI,
			ctx.font_body)
		y += 20.0
	# Builds into.
	var into := model.builds_into(idx)
	if not into.is_empty() and y < BODY_B - 56.0:
		y += 4.0
		_c(tr("HUD_SHOP2_BUILDS_INTO"), x, y + 8.0, 11.0, HudPalette.BRASS, 0.2)
		y += 14.0
		for j in mini(into.size(), int(w / 34.0)):
			var ir := Rect2(x + j * 34.0, y, 30.0, 30.0)
			cut_fill(_r(ir), 4.0 * _k, Color(0.051, 0.075, 0.094, 0.92))
			_icon(into[j], ir.grow(-3.0), 1.0)
		y += 34.0
	# Buy state (greyed reason) pinned to the pane bottom.
	var st := model.state(idx)
	var by := BODY_B - 6.0
	if st == ItemShopModel.State.AVAILABLE:
		_t(tr("HUD_SHOP2_BUY_FOR") % HudFormat.thousands(model.cost(idx) - model.swap_credit(idx)), x, by, 14.0,
			HudPalette.BRASS_HI, ctx.font_body)
	else:
		_t(_fit(_state_text(idx, st), 13.0, w), x, by, 13.0, HudPalette.WARN_UI, ctx.font_body)


func _draw_sets() -> void:
	var es := builds_vm.entries()
	var max_rows := floori((BODY_B - BODY_Y - 8.0) / 52.0)
	for i in mini(es.size(), max_rows):
		var e: Dictionary = es[i]
		var r := _set_rect(i)
		cut_fill(_r(r), 8.0 * _k, Color(0.051, 0.075, 0.094, 0.92))
		cut_line(_r(r), 8.0 * _k, HudPalette.BRASS if i == sel else HudPalette.HAIR_STRONG, 1.5 if i == sel else 1.0)
		if bool(e["active"]):
			draw_rect(_r(Rect2(r.position, Vector2(3.0, r.size.y))), HudPalette.TEAL)
		_t(_fit(_set_name(e), 15.0, r.size.x - 160.0), r.position.x + 14.0, r.position.y + 20.0, 15.0, HudPalette.IVORY,
			ctx.font_display)
		var sub := tr("HUD_BUILDS_STEPS") % int(e["steps"])
		var w: PackedStringArray = e["warnings"]
		if not w.is_empty():
			sub += "  ·  " + tr("HUD_BUILDS_WARN") % w.size()
		_t(sub, r.position.x + 14.0, r.position.y + 38.0, 12.0, HudPalette.BRASS if not w.is_empty() else HudPalette.MUTED)
		if bool(e["active"]):
			_c(tr("HUD_BUILDS_ACTIVE"), 0.0, r.position.y + 28.0, 12.0, HudPalette.TEAL, 0.2, HORIZONTAL_ALIGNMENT_RIGHT,
				r.end.x - 12.0)
		elif builds_vm.confirm_delete != "" and builds_vm.confirm_delete == String(e["id"]):
			_c(tr("HUD_BUILDS_DELETE_CONFIRM"), 0.0, r.position.y + 28.0, 11.0, HudPalette.BRASS, 0.12,
				HORIZONTAL_ALIGNMENT_RIGHT, r.end.x - 12.0)
	# Selected set: its steps as finished items.
	var x := 560.0
	var pw := VW - PAD - x
	if sel < 0 or sel >= es.size():
		return
	var e: Dictionary = es[sel]
	_c(_fit(_set_name(e), 18.0, pw), x, BODY_Y + 22.0, 18.0, HudPalette.IVORY, 0.12)
	_c(tr("HUD_BUILDS_LOCAL"), x, BODY_Y + 40.0, 10.0, HudPalette.DIM, 0.16)
	if String(e["id"]) == "":
		draw_multiline_string(ctx.font_body, Vector2(x, BODY_Y + 66.0) * _k, tr("HUD_BUILDS_DEFAULT_NOTE"),
			HORIZONTAL_ALIGNMENT_LEFT, pw * _k, ts(_px(13.0)), 4, HudPalette.MUTED)
	else:
		var steps: Array = builds_vm.build_at(sel)["steps"]
		var half := ceili(steps.size() / 2.0) if steps.size() > 8 else steps.size()
		for k in steps.size():
			var col := 0 if k < half else 1
			var row := k if k < half else k - half
			var sx := x + col * (pw * 0.5)
			var sy := BODY_Y + 56.0 + row * 34.0
			if sy > BODY_B - 60.0:
				continue
			var idx := model.catalog.index_of(StringName(steps[k]["item"]))
			_t("%d." % (k + 1), sx, sy + 20.0, 12.0, HudPalette.DIM, ctx.font_numbers)
			if idx >= 0:
				_icon(idx, Rect2(sx + 24.0, sy + 4.0, 24.0, 24.0), 1.0)
			_t(_fit(model.name_of(idx) if idx >= 0 else String(steps[k]["item"]), 13.0, pw * 0.5 - 60.0), sx + 54.0,
				sy + 20.0, 13.0, HudPalette.IVORY if idx >= 0 else HudPalette.BRASS)
		var warn: PackedStringArray = e["warnings"]
		for k in mini(warn.size(), 2):
			_t(_fit(warn[k], 12.0, pw - 16.0), x + 14.0, BODY_B - 24.0 + k * 16.0, 12.0, HudPalette.BRASS)
	_t(tr("HUD_SHOP2_SETS_NOTE"), PAD, BODY_B - 4.0, 12.0, HudPalette.DIM, ctx.font_body)


## Bottom strip (always on, §3.9).
func _draw_strip() -> void:
	var p := ctx.client.progress
	draw_line(Vector2(PAD, STRIP_Y) * _k, Vector2(VW - PAD, STRIP_Y) * _k, HudPalette.HAIR_STRONG, 1.0)
	# Lumen.
	_c(tr("HUD_LUMEN"), PAD, STRIP_Y + 22.0, 11.0, HudPalette.MUTED, 0.22)
	var g := Vector2(PAD + 9.0, STRIP_Y + 60.0) * _k
	diamond(g, 6.0 * _k, HudPalette.BRASS_HI, false)
	_t(HudFormat.thousands(p.lumen), PAD + 24.0, STRIP_Y + 69.0, 24.0, HudPalette.BRASS_HI, ctx.font_numbers)
	# Labels over the groups.
	_c(tr("HUD_SHOP2_GUN"), 156.0, STRIP_Y + 22.0, 11.0, HudPalette.MUTED, 0.2)
	_c(tr("HUD_SOCKET_CHAMBER"), 342.0, STRIP_Y + 22.0, 11.0, HudPalette.MUTED, 0.2)
	_c(tr("HUD_SHOP2_SLOTS") % [model.slots_used(), model.open_slots()], 470.0, STRIP_Y + 22.0, 11.0,
		HudPalette.WARN_UI if model.slots_used() >= model.open_slots() else HudPalette.MUTED, 0.2)
	for k in ItemShopModel.PLACES:
		_draw_place(k)
	# Squad / Med-Pack row.
	var rr := _row_rect()
	_c(tr("HUD_SHOP2_ROW"), rr.position.x, STRIP_Y + 22.0, 11.0, HudPalette.MUTED, 0.2)
	draw_rect(_r(rr), Color(0.051, 0.075, 0.094, 0.9))
	draw_rect(_r(rr).grow(-0.5), HudPalette.HAIR_STRONG, false, 1.0)
	var med := model.catalog.index_of(&"med_pack")
	if med >= 0:
		_icon(med, Rect2(rr.position + Vector2(6.0, 6.0), Vector2(22.0, 22.0)), 1.0 if p.medpacks > 0 else 0.35)
		_t("×%d" % p.medpacks, rr.position.x + 32.0, rr.position.y + 23.0, 13.0, HudPalette.IVORY, ctx.font_numbers)
	var sq := model.squad_owned()
	_t(tr("HUD_SHOP2_SQUAD_N") % sq.size(), rr.position.x + 6.0, rr.position.y + 47.0, 12.0,
		HudPalette.IVORY if not sq.is_empty() else HudPalette.DIM, ctx.font_body)
	# Signatures, Undo last, Sell.
	var sig := model.signatures()
	_c(tr("HUD_SHOP2_SIGNATURES") % [sig.x, sig.y], 984.0, STRIP_Y + 22.0, 11.0,
		HudPalette.WARN_UI if sig.x >= sig.y else HudPalette.BRASS, 0.2)
	var ur := _undo_rect()
	var can_undo := model.undo_last_available()
	draw_rect(_r(ur).grow(-0.5), HudPalette.BRASS if can_undo else HudPalette.HAIR_STRONG, false, 1.0)
	_c(tr("HUD_SHOP2_UNDO_LAST"), ur.position.x, ur.position.y + 17.0, 11.0, HudPalette.IVORY if can_undo else HudPalette.DIM,
		0.16, HORIZONTAL_ALIGNMENT_CENTER, ur.size.x)
	var sr := _sell_rect()
	var k := _focus_place()
	var label := tr("HUD_SHOP2_SELL_NONE")
	var on := false
	if k >= 0:
		on = true
		label = tr("HUD_SHOP2_UNDO_ITEM") if model.can_undo(k) else tr("HUD_SHOP2_SELL_FOR") % HudFormat.thousands(model.sell_value(k))
	draw_rect(_r(sr), Color(HudPalette.BRASS, 0.16) if on else Color(0, 0, 0, 0))
	draw_rect(_r(sr).grow(-0.5), HudPalette.BRASS if on else HudPalette.HAIR_STRONG, false, 1.0)
	_c(_fit(label, 11.0, sr.size.x - 8.0), sr.position.x, sr.position.y + 18.0, 11.0,
		HudPalette.IVORY if on else HudPalette.DIM, 0.12, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x)
	# Key hints.
	var pad := not Input.get_connected_joypads().is_empty()
	var hk := ("HUD_BUILDS_PAD" if pad else "HUD_BUILDS_KEYS") if tab == ItemShopModel.Tab.SETS \
		else ("HUD_SHOP2_PAD" if pad else "HUD_SHOP2_KEYS")
	_t(_fit(tr(hk), 11.0, VW - 2.0 * PAD), PAD, VH - 8.0, 11.0, HudPalette.DIM, ctx.font_body)


## The owned place Sell / Undo acts on: the focused strip box, or the focused item's.
func _focus_place() -> int:
	if area == Area.STRIP:
		return strip_sel if model.item_at(strip_sel) >= 0 else -1
	var places := model.places_of(_sel_index())
	for k in places:
		if model.can_undo(k):
			return k
	return places[places.size() - 1] if not places.is_empty() else -1


func _draw_place(k: int) -> void:
	var r := _place_rect(k)
	var idx := model.item_at(k)
	var foc := area == Area.STRIP and strip_sel == k
	cut_fill(_r(r), 5.0 * _k, Color(0.051, 0.075, 0.094, 0.92))
	cut_line(_r(r), 5.0 * _k, HudPalette.BRASS if foc else HudPalette.HAIR_STRONG, 2.0 if foc else 1.0)
	if k <= ItemShopModel.P_MOD:
		var keys := ["HUD_SHOP2_SOCK_CORE", "HUD_SHOP2_SOCK_BARREL", "HUD_SHOP2_SOCK_FRAME", "HUD_SHOP2_SOCK_AMMO",
			"HUD_SHOP2_SOCK_MOD"]
		_c(tr(keys[k]), r.position.x, r.end.y - 4.0, 9.0, HudPalette.DIM, 0.14, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if idx < 0:
		return
	var spare := model.is_spare(k)
	_icon(idx, Rect2(r.position + Vector2(9.0, 5.0), Vector2(r.size.x - 18.0, r.size.y - 22.0 if k <= ItemShopModel.P_MOD else r.size.y - 18.0)),
		0.3 if spare else 1.0)
	if spare:
		_c(tr("HUD_SHOP2_SPARE"), r.position.x, r.end.y - 4.0, 9.0, HudPalette.MUTED, 0.14, HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x)
	if model.can_undo(k):
		# Per-item undo marker: a hooked arrow in the top-left corner.
		var c := (r.position + Vector2(9.0, 9.0)) * _k
		draw_arc(c, 5.0 * _k, PI * 0.9, PI * 2.3, 10, HudPalette.TEAL, 1.6, true)
		draw_line(c + Vector2(-5.0, 0.0) * _k, c + Vector2(-7.0, -3.0) * _k, HudPalette.TEAL, 1.6)


func _draw_toast() -> void:
	if _toast_t <= 0.0 or _toast == "":
		return
	var a := clampf(_toast_t / 0.4, 0.0, 1.0)
	var w := text_width(_toast, _px(15.0), ctx.font_body) / _k + 40.0
	var r := Rect2(VW * 0.5 - w * 0.5, STRIP_Y - 40.0, w, 32.0)
	draw_rect(_r(r), Color(HudPalette.INK_DEEP, 0.92 * a))
	draw_rect(_r(Rect2(r.position, Vector2(3.0, r.size.y))), Color(_toast_col, a))
	_t(_toast, r.position.x, r.position.y + 21.0, 15.0, Color(HudPalette.IVORY, a), ctx.font_body,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
