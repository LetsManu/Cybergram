class_name ItemShopPanel
extends HudWidget
## Armory v2 shop screen (design/gdd/items-and-armory.md §3.9), built to the
## owner's mockup (design/ux/reference/armory-v2-owner-mockup.webp): gold
## ARMORY title, tabs (Recommended / All Items / Item Sets), search, Lumen
## with its income chip; on Recommended the NEXT PURCHASE card (the advisor's
## next part, can-afford / need chip, BUY [ENTER], the full reason), the
## BUILD PATH node graph (done ticked, current gold, branch to the last
## step's choices) and up to 3 SITUATIONAL cards with a short reason; on
## every tab the YOUR LOADOUT row (4 gun sockets with the Chamber's type +
## mod, the 6 open slots, Sell / Undo, Signatures / Med-Pack / Squad chips),
## the right detail pane (stats with the real gain, the recipe with owned
## parts ticked and the next part highlighted, builds into, passive) and the
## keycap footer. Used by HudRoot when the catalog is a recipe catalog.
##
## Designed on a 1600 x 900 canvas and scaled to the panel (`_k`): 1080p is
## the design size, 720p the same layout scaled down. Pure view: the logic is
## ItemShopModel / BuildsViewModel; requests go through
## PlayerInputSource.request_action and the server re-checks every rule; the
## toast shows the exact server Result (shop_seq / shop_result).
##
## Keys (parity with ArmoryPanel, docs/armory.md): F / interact or B opens on
## the pad, Esc / pad B closes; Q / E, PageUp / PageDown, LB / RB switch tabs;
## arrows / D-pad move (left of the grid: the stat filters; below: the
## loadout row); Enter / A buys (the next part of the focused goal);
## Backspace / X sells the focused owned item or undoes it when it was bought
## this visit; Ctrl+Z / R3 Undo last; R / L3 jumps to the advisor's next buy;
## / or Ctrl+F searches; Tab / View clears the filters. Item Sets: Enter / A
## use, N / L3 new from the guide, D / R3 duplicate, Delete / X twice delete,
## C copy, V paste. Mouse: hover shows details, click focuses, double-click
## buys, right-click on a loadout slot sells / undoes.

const VW: float = 1600.0
const VH: float = 900.0
const L: float = 48.0
const LR: float = 1150.0
const PX: float = 1190.0
const PR: float = 1560.0
const HEAD_B: float = 96.0
const BODY_Y: float = 112.0
const BODY_B: float = 690.0
const LOAD_Y: float = 716.0
const SLOT: float = 72.0
const SLOT_GAP: float = 10.0
const FOOT_Y: float = 872.0
const CUT: float = 12.0
## All Items grid.
const FILTER_W: float = 176.0
const GRID_X: float = 244.0
const TILE: float = 56.0
const TILE_PX: float = 64.0
const TILE_PY: float = 84.0
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
## Focused entry of `_items` (or the Item Sets row).
var sel: int = 0
var filter_sel: int = 0
## Focused inventory place (ItemShopModel.P_*) while area == STRIP.
var strip_sel: int = 0

var _k: float = 1.0
var _items: Array[Dictionary] = []
var _labels: Array[Dictionary] = []
var _hover: int = -1
var _thumbs: ItemThumbs
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
## Evidence only (env CYBERGRAM_SHOP_EVIDENCE=full): fill the open slots, then
## send one buy the server refuses (INVENTORY_FULL) to show its toast.
var _evidence: Array = []
var _evidence_t: float = 0.0

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
	if _auto_open and OS.get_environment("CYBERGRAM_SHOP_EVIDENCE") == "full":
		_evidence = [&"steady_part", &"stride_clip", &"lens_part"]
	_thumbs = ItemThumbs.new()
	add_child(_thumbs)


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
	if open and not _evidence.is_empty():
		_evidence_step(dt)
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
		sel = 0
		_hover = -1
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


## Evidence only: one raw ACTION_BUY every 0.6 s (the last one is refused by
## the server, so its exact Result toast shows), then the All Items tab.
func _evidence_step(dt: float) -> void:
	_evidence_t += dt
	if _evidence_t < 0.6 or not _pending.is_empty():
		return
	_evidence_t = 0.0
	var idx := ctx.client.catalog.index_of(_evidence.pop_front())
	_send("buy", idx, InputCommand.ACTION_BUY, idx, model.cost(idx))
	if _evidence.is_empty():
		_set_tab(ItemShopModel.Tab.ALL)
		_focus_index(idx)


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
	if (_e(KEY_Z) and Input.is_key_pressed(KEY_CTRL)) or (_je(JOY_BUTTON_RIGHT_STICK) and tab != ItemShopModel.Tab.SETS):
		_undo_last()
	if tab == ItemShopModel.Tab.SETS:
		_sets_keys()
		return
	if _e(KEY_TAB) or _je(JOY_BUTTON_BACK):
		model.filters.clear()
	if _e(KEY_SLASH) or (_e(KEY_F) and Input.is_key_pressed(KEY_CTRL)):
		if tab != ItemShopModel.Tab.ALL:
			_set_tab(ItemShopModel.Tab.ALL)
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
	_hover = -1
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
			elif dir.y > 0.0:
				area = Area.STRIP
			elif dir.x < 0.0 and tab == ItemShopModel.Tab.ALL:
				area = Area.FILTERS


## Spatial navigation over `_items`: the nearest item in `dir` (same row first
## for left / right; nearest row, then nearest x for up / down).
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
			if signf(d.x) == signf(dir.x) and absf(d.y) < 40.0:
				score = absf(d.x) + absf(d.y)
		elif signf(d.y) == signf(dir.y) and absf(d.y) > 10.0:
			score = absf(d.y) * 4.0 + absf(d.x)
		if score < best_d:
			best_d = score
			best = i
	return best


func _set_tab(t: int) -> void:
	tab = t
	sel = 0
	_hover = -1
	area = Area.MAIN
	searching = false
	_confirm = -1
	_layout()


func _sel_index() -> int:
	return int(_items[sel]["index"]) if sel >= 0 and sel < _items.size() else -1


## Focuses the advisor's next buy (Recommended: the NEXT PURCHASE card).
func _jump_next() -> void:
	var a := model.advice().best()
	if a == null:
		return
	if tab != ItemShopModel.Tab.RECOMMENDED and tab != ItemShopModel.Tab.ALL:
		_set_tab(ItemShopModel.Tab.RECOMMENDED)
	if tab == ItemShopModel.Tab.RECOMMENDED:
		for i in _items.size():
			if String(_items[i].get("kind", "")) == "hero":
				sel = i
				area = Area.MAIN
				return
	_focus_index(a.item_index)


func _focus_index(idx: int) -> void:
	for i in _items.size():
		if int(_items[i]["index"]) == idx:
			sel = i
			area = Area.MAIN
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
	var k := _focus_place()
	if k >= 0:
		_sell_place(k)
		return
	var idx := _sel_index()
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
	_layout()
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not open:
		return
	if event is InputEventMouseMotion:
		_hover = -1
		var mp: Vector2 = (event as InputEventMouseMotion).position / _k
		for i in _items.size():
			if (_items[i]["rect"] as Rect2).has_point(mp):
				_hover = i
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var p := mb.position / _k
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_click(p, mb.double_click)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			for k in ItemShopModel.PLACES:
				if _place_rect(k).has_point(p):
					_sell_place(k)
		accept_event()
	elif event is InputEventMouseButton:
		accept_event()


func _click(p: Vector2, double: bool) -> void:
	searching = _search_rect().has_point(p)
	if searching and tab != ItemShopModel.Tab.ALL:
		_set_tab(ItemShopModel.Tab.ALL)
		searching = true
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
	if tab == ItemShopModel.Tab.RECOMMENDED and _buy_rect().has_point(p):
		var hb := _hero_item()
		if hb >= 0:
			sel = hb
			_buy(int(_items[hb]["index"]))
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
				return
	for i in _items.size():
		if (_items[i]["rect"] as Rect2).has_point(p):
			sel = i
			area = Area.MAIN
			if double:
				_buy(int(_items[i]["index"]))
			return


func _hero_item() -> int:
	for i in _items.size():
		if String(_items[i].get("kind", "")) == "hero":
			return i
	return -1


# --- Layout (canvas units; _k scales to pixels) ----------------------------------------

func _layout() -> void:
	_k = maxf(0.4, minf(size.x / VW, size.y / VH))
	_items.clear()
	_labels.clear()
	if model == null:
		return
	match tab:
		ItemShopModel.Tab.RECOMMENDED:
			_layout_rec()
		ItemShopModel.Tab.ALL:
			_layout_all()
	if tab == ItemShopModel.Tab.SETS:
		sel = clampi(sel, 0, maxi(0, builds_vm.entries().size() - 1))
	else:
		sel = clampi(sel, 0, maxi(0, _items.size() - 1))
	if _hover >= _items.size():
		_hover = -1


## Hero card, build path nodes (+ the branch), situational cards.
func _layout_rec() -> void:
	var best := model.advice().best()
	if best != null:
		var c := model.card(best.goal_index if best.goal_index >= 0 else best.item_index, model.reason_for(best), best.situational)
		_items.append({"rect": _hero_rect(), "index": int(c["next"]), "goal": int(c["goal"]), "card": c, "kind": "hero"})
	var s := model.sections()
	var path: Array = s["path"]
	var n := mini(path.size(), 7)
	var branch: Array = []
	if n > 0 and (path[n - 1]["cards"] as Array).size() > 1:
		branch = path[n - 1]["cards"]
	var x0 := L + 64.0
	var x1 := (LR - 420.0) if not branch.is_empty() else (LR - 64.0)
	var step := (x1 - x0) / maxf(1.0, n - 1)
	var cy := _path_y()
	# The current node is the step of the NEXT PURCHASE (else the first open step).
	var current := -1
	var best_goal := best.goal_index if best != null else -1
	for i in n:
		for cc in path[i]["cards"]:
			if int(cc["goal"]) == best_goal and not bool(path[i]["done"]):
				current = i
	for i in n:
		var node: Dictionary = path[i]
		if current < 0 and not bool(node["done"]):
			current = i
	for i in n:
		var node: Dictionary = path[i]
		var cards: Array = node["cards"]
		if cards.is_empty():
			continue
		var c: Dictionary = cards[0]
		for cc in cards:
			if bool(cc["done"]):
				c = cc
		var center := Vector2(x0 + step * i, cy)
		_items.append({"rect": Rect2(center - Vector2(38.0, 38.0), Vector2(76.0, 76.0)), "index": int(c["next"]),
			"goal": int(c["goal"]), "card": c, "kind": "node", "label": String(node["label"]), "done": bool(node["done"]),
			"current": i == current, "center": center, "label_w": minf(step - 14.0, 132.0)})
	var split := Vector2(x0 + step * (n - 1) + 100.0, cy)
	for j in mini(branch.size(), 3):
		var c: Dictionary = branch[j]
		var oc := Vector2(split.x + 70.0, cy + (j - (mini(branch.size(), 3) - 1) * 0.5) * 54.0)
		_items.append({"rect": Rect2(oc - Vector2(22.0, 22.0), Vector2(LR - oc.x + 22.0, 44.0)), "index": int(c["next"]),
			"goal": int(c["goal"]), "card": c, "kind": "branch", "center": oc, "split": split})
	var sit: Array = s["situational"]
	var ns := clampi(sit.size(), 2, 3)
	var cw := (LR - L - (ns - 1) * 24.0) / ns
	for j in mini(sit.size(), 3):
		var c: Dictionary = sit[j]
		_items.append({"rect": Rect2(L + j * (cw + 24.0), _sit_y(), cw, 130.0), "index": int(c["next"]),
			"goal": int(c["goal"]), "card": c, "kind": "sit"})


func _hero_rect() -> Rect2:
	return Rect2(L, BODY_Y, LR - L, 180.0)


func _buy_rect() -> Rect2:
	return Rect2(LR - 32.0 - 224.0, BODY_Y + 52.0, 224.0, 50.0)


func _afford_rect() -> Rect2:
	var b := _buy_rect()
	return Rect2(b.position.x - 20.0 - 210.0, b.position.y, 210.0, 50.0)


func _path_y() -> float:
	return BODY_Y + 180.0 + 48.0 + 60.0


func _sit_y() -> float:
	return _path_y() + 130.0


## All Items: shelves of tiles right of the stat filters.
func _layout_all() -> void:
	var per := floori((LR - GRID_X + TILE_PX - TILE) / TILE_PX)
	var y := BODY_Y + 22.0
	var col := 0
	var prev := -1
	for sh in model.shelves(query):
		var shelf := int(sh["shelf"])
		var items: Array = sh["items"]
		var join := shelf == ItemShopModel.Shelf.CONSUMABLE and prev == ItemShopModel.Shelf.SQUAD \
			and col + 1 + items.size() <= per
		if join:
			col += 1
			_labels.append({"key": ItemShopModel.SHELF_KEYS[shelf], "pos": Vector2(GRID_X + col * TILE_PX, y - 8.0 - TILE_PY)})
			y -= TILE_PY
		else:
			col = 0
			_labels.append({"key": ItemShopModel.SHELF_KEYS[shelf], "pos": Vector2(GRID_X, y - 8.0)})
		for i in items.size():
			if col >= per:
				col = 0
				y += TILE_PY
			_items.append({"rect": Rect2(GRID_X + col * TILE_PX, y, TILE, TILE), "index": int(items[i]),
				"goal": int(items[i]), "kind": "tile"})
			col += 1
		y += TILE_PY + 22.0
		prev = shelf


func _tab_rect(t: int) -> Rect2:
	var x := 330.0
	for i in t:
		x += _tab_w(i) + 12.0
	return Rect2(x, 28.0, _tab_w(t), 50.0)


func _tab_w(t: int) -> float:
	return caps_width(tr(ItemShopModel.TAB_KEYS[t]), _px(18.0), 0.12) / _k + 36.0


func _search_rect() -> Rect2:
	return Rect2(880.0, 30.0, 330.0, 46.0)


func _close_rect() -> Rect2:
	return Rect2(VW - 34.0, 4.0, 28.0, 28.0)


func _filter_rect(f: int) -> Rect2:
	return Rect2(L, BODY_Y + 8.0 + f * 40.0, FILTER_W, 36.0)


func _set_rect(i: int) -> Rect2:
	return Rect2(L, BODY_Y + 8.0 + i * 70.0, 560.0, 62.0)


## Loadout square of inventory place `k`: Core, Barrel, Frame, Ammo Type,
## Ammo Mod, then the 6 open slots.
func _place_rect(k: int) -> Rect2:
	var y := LOAD_Y + 34.0
	if k <= ItemShopModel.P_MOD:
		return Rect2(L + k * (SLOT + SLOT_GAP), y, SLOT, SLOT)
	var x0 := L + 5.0 * (SLOT + SLOT_GAP) + 22.0
	return Rect2(x0 + (k - ItemShopModel.P_SLOT) * (SLOT + SLOT_GAP), y, SLOT, SLOT)


func _sell_rect() -> Rect2:
	return Rect2(LR - 170.0, LOAD_Y + 34.0, 170.0, 32.0)


func _undo_rect() -> Rect2:
	return Rect2(LR - 170.0, LOAD_Y + 74.0, 170.0, 32.0)


# --- Drawing helpers (canvas units) -----------------------------------------------------

func _px(v: float) -> int:
	return maxi(1, roundi(v * _k))


func _r(r: Rect2) -> Rect2:
	return Rect2(r.position * _k, r.size * _k)


func _t(s: String, x: float, y: float, px: float, col: Color, font: Font = null,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void:
	text(s, Vector2(x, y) * _k, _px(px), col, font, align, w * _k if w > 0.0 else -1.0)


func _c(s: String, x: float, y: float, px: float, col: Color, em: float = 0.14,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void:
	caps(s, Vector2(x, y) * _k, _px(px), col, em, align, w * _k if w > 0.0 else -1.0)


## Caps width in canvas units.
func _cw(s: String, px: float, em: float = 0.14) -> float:
	return caps_width(s, _px(px), em) / _k


## Text width in canvas units.
func _tw(s: String, px: float, font: Font = null) -> float:
	return text_width(s, _px(px), font) / _k


## Largest of `sizes` at which caps `s` fits `w` (never cut: the copy is sized to fit).
func _fit_px(s: String, w: float, sizes: Array, em: float = 0.14) -> float:
	for px in sizes:
		if _cw(s, px, em) <= w:
			return px
	return sizes[sizes.size() - 1]


func _card_bg(r: Rect2, edge: Color, w: float = 1.0) -> void:
	cut_fill(_r(r), CUT * _k, HudPalette.NAVY_CARD)
	cut_line(_r(r), CUT * _k, edge, w)


## Item picture: a rendered thumbnail (C6 part mesh) on a dark disc with a
## soft glow, or the line-art glyph when there is no mesh.
func _thumb(index: int, r: Rect2, a: float = 1.0, disc: bool = true) -> void:
	var it := model.catalog.at(index)
	if it == null:
		return
	var pr := _r(r)
	var c := pr.get_center()
	var rad := minf(pr.size.x, pr.size.y) * 0.5
	if disc:
		draw_circle(c, rad, Color(0.02, 0.035, 0.06, a))
		for i in 4:
			draw_circle(c, rad * (0.85 - 0.17 * i), Color(it.hue, 0.045 * a))
	var tex := _thumbs.texture(model.catalog, index, model.mana_gun()) if _thumbs != null else null
	if tex != null:
		draw_texture_rect(tex, Rect2(c - Vector2(rad, rad) * 0.92, Vector2(rad, rad) * 1.84), false, Color(1, 1, 1, a))
	else:
		ShopIcons.draw_v2(self, it, Rect2(c - Vector2(rad, rad) * 0.62, Vector2(rad, rad) * 1.24), Color(1, 1, 1, a))


## Tier pips (Component / Assembly / Signature = 1 / 2 / 3 filled of 3).
func _pips(x: float, y: float, index: int, s: float = 7.0) -> void:
	var it := model.catalog.at(index)
	if it == null or not it.is_recipe_item():
		return
	for i in 3:
		var c := Vector2(x + s + i * s * 2.8, y) * _k
		diamond(c, s * _k, HudPalette.GOLD if i < int(it.tier) else HudPalette.GOLD_DIM, i < int(it.tier))


func _price(x: float, y: float, value: int, px: float, col: Color = HudPalette.GOLD) -> float:
	var n := HudFormat.thousands(value)
	_t(n, x, y, px, col, ctx.font_numbers)
	var w := _tw(n, px, ctx.font_numbers)
	_c(tr("HUD_SHOP2_LUMEN_UNIT"), x + w + px * 0.35, y, px * 0.62, col, 0.16)
	return w + px * 0.35 + _cw(tr("HUD_SHOP2_LUMEN_UNIT"), px * 0.62, 0.16)


func _chip(r: Rect2, label: String, col: Color, px: float, tick: bool = false) -> void:
	draw_rect(_r(r), Color(col, 0.12))
	draw_rect(_r(r).grow(-0.5), col, false, 1.5)
	var x := r.position.x + 14.0
	if tick:
		ShopIcons.check(self, Vector2(x + 8.0, r.get_center().y) * _k, 7.0 * _k, col)
		x += 24.0
	_c(label, x, r.get_center().y + px * 0.36, px, col, 0.14)


# --- Drawing ------------------------------------------------------------------------

func _draw() -> void:
	var client := ctx.client
	if client == null or client.progress == null or model == null:
		return
	if not open:
		if _hint_t > 0.0:
			_draw_hint()
		return
	var bg := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), Vector2(size.x, size.y - 40.0 * _k),
		Vector2(size.x - 40.0 * _k, size.y), Vector2(0.0, size.y)])
	draw_colored_polygon(bg, HudPalette.NAVY)
	_draw_header()
	match tab:
		ItemShopModel.Tab.RECOMMENDED:
			_draw_rec()
		ItemShopModel.Tab.ALL:
			_draw_all()
		_:
			_draw_sets()
	_draw_loadout()
	_draw_pane()
	_draw_footer()
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
	_c(tr("HUD_ARMORY"), L, 72.0, 46.0, HudPalette.GOLD, 0.1)
	for t in 3:
		var r := _tab_rect(t)
		var on := t == tab
		_c(tr(ItemShopModel.TAB_KEYS[t]), r.position.x, r.position.y + 30.0, 18.0,
			HudPalette.GOLD if on else HudPalette.MUTED, 0.12, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		if on:
			draw_rect(_r(Rect2(r.position.x + 8.0, r.end.y - 4.0, r.size.x - 16.0, 3.0)), HudPalette.GOLD)
	# Search.
	var s := _search_rect()
	draw_rect(_r(s), Color(HudPalette.NAVY_CARD, 1.0))
	draw_rect(_r(s).grow(-0.5), HudPalette.GOLD if searching else HudPalette.NAVY_EDGE, false, 1.5)
	var mc := Vector2(s.position.x + 24.0, s.get_center().y - 2.0) * _k
	draw_arc(mc, 8.0 * _k, 0.0, TAU, 20, HudPalette.MUTED, 2.0, true)
	draw_line(mc + Vector2(6.0, 6.0) * _k, mc + Vector2(12.0, 12.0) * _k, HudPalette.MUTED, 2.0, true)
	var shown := query + ("_" if searching else "")
	_t(shown if shown != "" else tr("HUD_SHOP2_SEARCH"), s.position.x + 46.0, s.position.y + 30.0, 17.0,
		HudPalette.IVORY if shown != "" else HudPalette.DIM)
	# Lumen and income.
	var p := ctx.client.progress
	_c(tr("HUD_LUMEN"), 0.0, 34.0, 13.0, HudPalette.MUTED, 0.2, HORIZONTAL_ALIGNMENT_RIGHT, PR)
	var n := HudFormat.thousands(p.lumen)
	_t(n, 0.0, 70.0, 36.0, HudPalette.GOLD, ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, PR)
	var gx := PR - _tw(n, 36.0, ctx.font_numbers) - 22.0
	diamond(Vector2(gx, 57.0) * _k, 11.0 * _k, HudPalette.GOLD, false)
	diamond(Vector2(gx, 57.0) * _k, 4.5 * _k, HudPalette.GOLD)
	var inc := tr("HUD_SHOP2_INCOME") % roundi(_econ.trickle_per_min if _econ != null else 0.0)
	var iw := _cw(inc, 13.0) + 20.0
	var ir := Rect2(PR - iw, 78.0, iw, 22.0)
	draw_rect(_r(ir), Color(HudPalette.GOLD, 0.14))
	draw_rect(_r(ir).grow(-0.5), HudPalette.GOLD_DIM, false, 1.0)
	_c(inc, ir.position.x + 10.0, ir.position.y + 16.0, 13.0, HudPalette.GOLD, 0.14)
	var cr := _r(_close_rect())
	var c := cr.get_center()
	var d := 7.0 * _k
	draw_line(c + Vector2(-d, -d), c + Vector2(d, d), HudPalette.DIM, 1.6)
	draw_line(c + Vector2(-d, d), c + Vector2(d, -d), HudPalette.DIM, 1.6)
	draw_line(Vector2(L, HEAD_B + 6.0) * _k, Vector2(PR, HEAD_B + 6.0) * _k, HudPalette.NAVY_EDGE, 1.0)


func _foc(i: int) -> bool:
	return (i == sel and area == Area.MAIN) or i == _hover


func _draw_rec() -> void:
	var hero := -1
	for i in _items.size():
		if String(_items[i]["kind"]) == "hero":
			hero = i
	_draw_hero(hero)
	_c(tr("HUD_SHOP2_BUILD_PATH"), L, _path_y() - 66.0, 20.0, HudPalette.GOLD, 0.14)
	draw_rect(_r(Rect2(L, _path_y() - 54.0, LR - L, 142.0)), Color(HudPalette.NAVY_CARD, 0.5))
	# Path edges first, then nodes.
	var prev := Vector2.ZERO
	for i in _items.size():
		var e: Dictionary = _items[i]
		if String(e["kind"]) == "node":
			var c: Vector2 = e["center"]
			if prev != Vector2.ZERO:
				var a := prev + Vector2(44.0, 0.0)
				var b := c - Vector2(44.0, 0.0)
				draw_line(a * _k, b * _k, HudPalette.NAVY_EDGE.lightened(0.25), 2.0, true)
				draw_polyline(PackedVector2Array([(b + Vector2(-7.0, -5.0)) * _k, b * _k, (b + Vector2(-7.0, 5.0)) * _k]),
					HudPalette.NAVY_EDGE.lightened(0.25), 2.0, true)
			prev = c
		elif String(e["kind"]) == "branch":
			var sp: Vector2 = e["split"]
			var oc: Vector2 = e["center"]
			draw_line((prev + Vector2(44.0, 0.0)) * _k, sp * _k, HudPalette.NAVY_EDGE.lightened(0.25), 2.0, true)
			draw_line(sp * _k, (oc - Vector2(28.0, 0.0)) * _k, HudPalette.NAVY_EDGE.lightened(0.25), 2.0, true)
	for i in _items.size():
		var e: Dictionary = _items[i]
		match String(e["kind"]):
			"node":
				_draw_node(e, _foc(i))
			"branch":
				_draw_branch(e, _foc(i))
			"sit":
				_draw_sit(e, _foc(i))
	_c(tr("HUD_SHOP2_SEC_SITUATIONAL"), L, _sit_y() - 16.0, 20.0, HudPalette.GOLD, 0.14)
	var any_sit := false
	for e in _items:
		if String(e["kind"]) == "sit":
			any_sit = true
	if not any_sit:
		_t(tr("HUD_SHOP2_SEC_NONE"), L + 4.0, _sit_y() + 40.0, 17.0, HudPalette.DIM)


## NEXT PURCHASE card: big picture, name, pips, price, can-afford / need chip,
## BUY [ENTER] and the full reason.
func _draw_hero(i: int) -> void:
	var r := _hero_rect()
	cut_fill(_r(r), 18.0 * _k, HudPalette.NAVY_CARD)
	cut_line(_r(r), 18.0 * _k, HudPalette.GOLD, 2.0, true)
	_c(tr("HUD_SHOP2_NEXT_PURCHASE"), r.position.x + 28.0, r.position.y + 26.0, 15.0, HudPalette.GOLD, 0.2)
	if i < 0:
		_t(tr("HUD_SHOP2_BUILD_DONE"), r.position.x + 28.0, r.position.y + 100.0, 22.0, HudPalette.MUTED)
		return
	var e: Dictionary = _items[i]
	var c: Dictionary = e["card"]
	var nxt := int(c["next"])
	var ib := Rect2(r.position.x + 28.0, r.position.y + 36.0, 128.0, 128.0)
	cut_fill(_r(ib), 12.0 * _k, Color(0.02, 0.035, 0.06))
	cut_line(_r(ib), 12.0 * _k, HudPalette.GOLD_DIM, 1.0, true)
	_thumb(nxt, ib.grow(-10.0), 1.0, false)
	var x := ib.end.x + 32.0
	var namew := _afford_rect().position.x - x - 16.0
	var name_ := model.name_of(nxt).to_upper()
	var npx := _fit_px(name_, namew, [34.0, 30.0, 26.0, 22.0], 0.1)
	_c(name_, x, r.position.y + 76.0, npx, HudPalette.IVORY, 0.1)
	_pips(x, r.position.y + 96.0, nxt, 8.0)
	if int(c["goal"]) != nxt:
		_t(tr("HUD_SHOP2_FOR") % model.name_of(int(c["goal"])), x + 80.0, r.position.y + 102.0, 16.0, HudPalette.MUTED)
	_price(x, r.position.y + 138.0, int(c["next_cost"]), 32.0)
	var reason := tr(String(c["reason"]))
	_t(reason, x, r.position.y + 166.0, 17.0, HudPalette.MUTED, ctx.font_body)
	var st := model.state(nxt)
	var ar := _afford_rect()
	if st == ItemShopModel.State.AVAILABLE:
		_chip(ar, tr("HUD_SHOP2_CAN_AFFORD"), HudPalette.TEAL, 16.0, true)
	elif st == ItemShopModel.State.CANT_AFFORD:
		_chip(ar, tr("HUD_SHOP2_NEED") % HudFormat.thousands(model.shortfall(nxt)), HudPalette.DANGER, 16.0)
	else:
		var why := tr(ItemShopModel.state_key(st))
		var cr := Rect2(ar.end.x - maxf(ar.size.x, _cw(why, 14.0) + 28.0), ar.position.y, maxf(ar.size.x, _cw(why, 14.0) + 28.0),
			ar.size.y)
		_chip(cr, why, HudPalette.WARN_UI, 14.0)
	var br := _buy_rect()
	var ok := st == ItemShopModel.State.AVAILABLE
	cut_fill(_r(br), 8.0 * _k, HudPalette.GOLD if ok else Color(HudPalette.GOLD, 0.25))
	if _foc(i):
		cut_line(_r(br.grow(3.0)), 9.0 * _k, HudPalette.IVORY, 1.5)
	_c(tr("HUD_SHOP2_BUY"), br.position.x + 26.0, br.position.y + 33.0, 20.0, HudPalette.NAVY if ok else HudPalette.DIM, 0.16)
	var kr := Rect2(br.end.x - 104.0, br.position.y + 10.0, 92.0, 30.0)
	draw_rect(_r(kr), HudPalette.NAVY)
	_c(tr("HUD_SHOP2_KEY_ENTER"), kr.position.x, kr.position.y + 21.0, 14.0, HudPalette.IVORY, 0.12,
		HORIZONTAL_ALIGNMENT_CENTER, kr.size.x)


func _draw_node(e: Dictionary, focused: bool) -> void:
	var c: Vector2 = e["center"]
	var done := bool(e["done"])
	var cur := bool(e["current"])
	var pc := c * _k
	var rad := 36.0 * _k
	if cur:
		for g in 4:
			draw_arc(pc, rad + (4.0 + g * 3.0) * _k, 0.0, TAU, 40, Color(HudPalette.GOLD, 0.16 - g * 0.035), 3.0 * _k, true)
	draw_circle(pc, rad, Color(0.02, 0.035, 0.06))
	_thumb(int(e["goal"]), Rect2(c - Vector2(30.0, 30.0), Vector2(60.0, 60.0)), 1.0 if done or cur else 0.5, false)
	var ring := HudPalette.GOLD if cur else (HudPalette.TEAL if done else HudPalette.NAVY_EDGE.lightened(0.2))
	draw_arc(pc, rad, 0.0, TAU, 40, ring, (3.0 if cur else 2.0) * _k, true)
	if focused:
		draw_arc(pc, rad + 5.0 * _k, 0.0, TAU, 40, HudPalette.IVORY, 1.5, true)
	if done:
		var tc := (c + Vector2(28.0, -26.0)) * _k
		draw_circle(tc, 11.0 * _k, HudPalette.TEAL)
		ShopIcons.check(self, tc, 5.5 * _k, HudPalette.NAVY)
	var label := tr(String(e["label"]))
	var col := HudPalette.GOLD if cur else (HudPalette.TEAL if done else HudPalette.DIM)
	# Fixed label width (the node spacing): one line when it fits at 15 px,
	# else two lines at 14 px ("CORE" / "SIGNATURE"); never wider than its slot.
	var w := float(e.get("label_w", 120.0))
	if _cw(label, 15.0, 0.12) <= w or not label.contains(" "):
		_c(label, c.x - w * 0.5, c.y + 64.0, _fit_px(label, w, [15.0, 14.0, 13.0, 12.0], 0.12), col, 0.12,
			HORIZONTAL_ALIGNMENT_CENTER, w)
	else:
		var parts := label.split(" ", false, 1)
		_c(parts[0], c.x - w * 0.5, c.y + 60.0, _fit_px(parts[0], w, [14.0, 13.0, 12.0], 0.12), col, 0.12,
			HORIZONTAL_ALIGNMENT_CENTER, w)
		_c(parts[1], c.x - w * 0.5, c.y + 78.0, _fit_px(parts[1], w, [14.0, 13.0, 12.0], 0.12), col, 0.12,
			HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_branch(e: Dictionary, focused: bool) -> void:
	var c: Vector2 = e["center"]
	var cd: Dictionary = e["card"]
	var pc := c * _k
	draw_circle(pc, 22.0 * _k, Color(0.02, 0.035, 0.06))
	_thumb(int(e["goal"]), Rect2(c - Vector2(18.0, 18.0), Vector2(36.0, 36.0)), 0.9, false)
	draw_arc(pc, 22.0 * _k, 0.0, TAU, 32, HudPalette.TEAL if bool(cd["done"]) else HudPalette.NAVY_EDGE.lightened(0.2),
		1.5 * _k, true)
	if focused:
		draw_arc(pc, 26.0 * _k, 0.0, TAU, 32, HudPalette.IVORY, 1.5, true)
	var name_ := model.name_of(int(e["goal"])).to_upper()
	var w := (e["rect"] as Rect2).end.x - c.x - 34.0
	_c(name_, c.x + 34.0, c.y + 6.0, _fit_px(name_, w, [15.0, 14.0, 13.0, 12.0], 0.12), HudPalette.MUTED, 0.12)


## SITUATIONAL card: round picture, name, price, NEED badge, short reason footer.
func _draw_sit(e: Dictionary, focused: bool) -> void:
	var r: Rect2 = e["rect"]
	var c: Dictionary = e["card"]
	_card_bg(r, HudPalette.IVORY if focused else HudPalette.NAVY_EDGE, 1.5 if focused else 1.0)
	var goal := int(c["goal"])
	_thumb(goal, Rect2(r.position + Vector2(18.0, 14.0), Vector2(72.0, 72.0)))
	draw_arc((r.position + Vector2(54.0, 50.0)) * _k, 36.0 * _k, 0.0, TAU, 36, HudPalette.NAVY_EDGE.lightened(0.2), 1.5, true)
	var x := r.position.x + 108.0
	var w := r.end.x - x - 16.0
	var need := not bool(c["done"]) and int(c["state"]) == ItemShopModel.State.CANT_AFFORD
	var badge_w := 0.0
	if need:
		var nt := tr("HUD_SHOP2_NEED") % HudFormat.thousands(model.shortfall(int(c["next"])))
		badge_w = _cw(nt, 12.0) + 20.0
		var br := Rect2(r.end.x - 14.0 - badge_w, r.position.y + 12.0, badge_w, 22.0)
		draw_rect(_r(br), Color(HudPalette.DANGER, 0.22))
		draw_rect(_r(br).grow(-0.5), HudPalette.DANGER, false, 1.0)
		_c(nt, br.position.x + 10.0, br.position.y + 16.0, 12.0, HudPalette.DANGER, 0.14)
	var name_ := model.name_of(goal).to_upper()
	_c(name_, x, r.position.y + 52.0, _fit_px(name_, w, [18.0, 16.0, 15.0, 14.0], 0.12), HudPalette.IVORY, 0.12)
	if bool(c["done"]):
		_c(tr("HUD_ARMORY_OWNED"), x, r.position.y + 80.0, 16.0, HudPalette.TEAL, 0.14)
	else:
		_price(x, r.position.y + 82.0, int(c["cost"]), 20.0)
	var why_key := ItemShopModel.why_key(String(c["reason"]))
	var why := tr(why_key) if why_key != "" else tr("HUD_SHOP2_WHY_SITUATIONAL")
	draw_line(Vector2(r.position.x + 16.0, r.position.y + 98.0) * _k, Vector2(r.end.x - 16.0, r.position.y + 98.0) * _k,
		HudPalette.NAVY_EDGE, 1.0)
	_why_glyph(why_key, Vector2(r.position.x + 28.0, r.position.y + 114.0))
	_c(why, r.position.x + 46.0, r.position.y + 119.0, _fit_px(why, r.size.x - 62.0, [13.0, 12.0, 11.0], 0.12),
		HudPalette.MUTED, 0.12)


## Footer glyph of a situational reason: enemy = triangle, you = shield, team = three dots.
func _why_glyph(key: String, c: Vector2) -> void:
	var pc := c * _k
	var s := 7.0 * _k
	var col := HudPalette.MUTED
	if key.contains("_YOU_"):
		draw_polyline(PackedVector2Array([pc + Vector2(-s, -s), pc + Vector2(s, -s), pc + Vector2(s, 0.0), pc + Vector2(0.0, s),
			pc + Vector2(-s, 0.0), pc + Vector2(-s, -s)]), col, 1.5, true)
	elif key.contains("_TEAM_"):
		for i in 3:
			draw_circle(pc + Vector2((i - 1) * s * 1.1, 0.0), s * 0.4, col)
	else:
		draw_polyline(PackedVector2Array([pc + Vector2(0.0, -s), pc + Vector2(s, s * 0.8), pc + Vector2(-s, s * 0.8),
			pc + Vector2(0.0, -s)]), col, 1.5, true)


func _draw_all() -> void:
	for f in ItemShopModel.FILTERS.size():
		var fr := _filter_rect(f)
		var on := model.filters.has(ItemShopModel.FILTERS[f])
		var foc := area == Area.FILTERS and f == filter_sel
		if foc:
			draw_rect(_r(fr), Color(HudPalette.GOLD, 0.12))
		var box := Rect2(fr.position + Vector2(8.0, 10.0), Vector2(16.0, 16.0))
		draw_rect(_r(box), HudPalette.GOLD if on else HudPalette.NAVY_EDGE.lightened(0.2), on, 1.5)
		_t(tr(ItemShopModel.FILTER_KEYS[f]), fr.position.x + 34.0, fr.position.y + 24.0, 17.0,
			HudPalette.IVORY if on or foc else HudPalette.MUTED, ctx.font_body)
	for l in _labels:
		var pos: Vector2 = l["pos"]
		_c(tr(String(l["key"])), pos.x, pos.y, 14.0, HudPalette.GOLD, 0.18)
	for i in _items.size():
		var r: Rect2 = _items[i]["rect"]
		var idx := int(_items[i]["index"])
		var st := model.state(idx)
		var owned := not model.places_of(idx).is_empty() or st == ItemShopModel.State.OWNED
		var a := 1.0 if st == ItemShopModel.State.AVAILABLE or owned else (0.65 if st == ItemShopModel.State.CANT_AFFORD else 0.35)
		var foc := _foc(i)
		cut_fill(_r(r), 7.0 * _k, Color(0.02, 0.035, 0.06))
		cut_line(_r(r), 7.0 * _k, HudPalette.GOLD if foc else Color(HudPalette.NAVY_EDGE.lightened(0.15), a),
			2.0 if foc else 1.0)
		_thumb(idx, r.grow(-3.0), a, false)
		_pips(r.position.x + 1.0, r.position.y + 7.0, idx, 3.0)
		if owned:
			var tc := (r.end - Vector2(7.0, 7.0)) * _k
			draw_circle(tc, 7.0 * _k, HudPalette.TEAL)
			ShopIcons.check(self, tc, 3.5 * _k, HudPalette.NAVY)
		var price := HudFormat.thousands(model.cost(idx) if not owned else model.total(idx))
		_t(price, r.position.x - 4.0, r.end.y + 18.0, 14.0,
			Color(HudPalette.GOLD if st == ItemShopModel.State.AVAILABLE else HudPalette.MUTED, maxf(a, 0.75)),
			ctx.font_numbers, HORIZONTAL_ALIGNMENT_CENTER, TILE + 8.0)
	if _items.is_empty():
		_t(tr("HUD_SHOP_EMPTY"), GRID_X, BODY_Y + 40.0, 18.0, HudPalette.MUTED)


func _draw_sets() -> void:
	var es := builds_vm.entries()
	var max_rows := floori((BODY_B - BODY_Y - 40.0) / 70.0)
	for i in mini(es.size(), max_rows):
		var e: Dictionary = es[i]
		var r := _set_rect(i)
		_card_bg(r, HudPalette.GOLD if i == sel else HudPalette.NAVY_EDGE, 1.5 if i == sel else 1.0)
		if bool(e["active"]):
			draw_rect(_r(Rect2(r.position, Vector2(4.0, r.size.y))), HudPalette.TEAL)
		_t(_set_name(e), r.position.x + 20.0, r.position.y + 28.0, 19.0, HudPalette.IVORY, ctx.font_display)
		var sub := tr("HUD_BUILDS_STEPS") % int(e["steps"])
		var w: PackedStringArray = e["warnings"]
		if not w.is_empty():
			sub += "  ·  " + tr("HUD_BUILDS_WARN") % w.size()
		_t(sub, r.position.x + 20.0, r.position.y + 50.0, 15.0, HudPalette.WARN_UI if not w.is_empty() else HudPalette.MUTED)
		if bool(e["active"]):
			_c(tr("HUD_BUILDS_ACTIVE"), 0.0, r.position.y + 38.0, 14.0, HudPalette.TEAL, 0.2, HORIZONTAL_ALIGNMENT_RIGHT,
				r.end.x - 18.0)
		elif builds_vm.confirm_delete != "" and builds_vm.confirm_delete == String(e["id"]):
			_c(tr("HUD_BUILDS_DELETE_CONFIRM"), 0.0, r.position.y + 38.0, 13.0, HudPalette.GOLD, 0.12,
				HORIZONTAL_ALIGNMENT_RIGHT, r.end.x - 18.0)
	_t(tr("HUD_SHOP2_SETS_NOTE"), L, BODY_B - 8.0, 15.0, HudPalette.DIM)
	var x := 640.0
	var pw := LR - x
	if sel < 0 or sel >= es.size():
		return
	var e: Dictionary = es[sel]
	_c(_set_name(e), x, BODY_Y + 28.0, 22.0, HudPalette.GOLD, 0.12)
	_c(tr("HUD_BUILDS_LOCAL"), x, BODY_Y + 50.0, 12.0, HudPalette.DIM, 0.16)
	if String(e["id"]) == "":
		draw_multiline_string(ctx.font_body, Vector2(x, BODY_Y + 84.0) * _k, tr("HUD_BUILDS_DEFAULT_NOTE"),
			HORIZONTAL_ALIGNMENT_LEFT, pw * _k, ts(_px(16.0)), 5, HudPalette.MUTED)
		return
	var steps: Array = builds_vm.build_at(sel)["steps"]
	var per_col := 11
	var shown := mini(steps.size(), per_col * 2)
	for k in shown:
		var col := k / per_col
		var row := k % per_col
		var sx := x + col * (pw * 0.5)
		var sy := BODY_Y + 70.0 + row * 44.0
		var idx := model.catalog.index_of(StringName(steps[k]["item"]))
		_t("%d." % (k + 1), sx, sy + 26.0, 15.0, HudPalette.DIM, ctx.font_numbers)
		if idx >= 0:
			_thumb(idx, Rect2(sx + 32.0, sy + 4.0, 34.0, 34.0))
		_t(model.name_of(idx) if idx >= 0 else String(steps[k]["item"]), sx + 76.0, sy + 26.0, 16.0,
			HudPalette.IVORY if idx >= 0 else HudPalette.WARN_UI)
	if steps.size() > shown:
		_t(tr("HUD_SHOP2_MORE_STEPS") % (steps.size() - shown), x, BODY_B - 8.0, 15.0, HudPalette.MUTED)


## YOUR LOADOUT (always on): gun sockets + Chamber, 6 open slots, chips, Sell / Undo.
func _draw_loadout() -> void:
	var p := ctx.client.progress
	draw_line(Vector2(L, LOAD_Y - 18.0) * _k, Vector2(LR, LOAD_Y - 18.0) * _k, HudPalette.NAVY_EDGE, 1.0)
	_c(tr("HUD_SHOP2_LOADOUT"), L, LOAD_Y + 12.0, 20.0, HudPalette.GOLD, 0.14)
	# Chips: Signatures n/2, Med-Pack, Squad.
	var sig := model.signatures()
	var chips: Array = [[tr("HUD_SHOP2_SIGNATURES") % [sig.x, sig.y], HudPalette.WARN_UI if sig.x >= sig.y else HudPalette.GOLD],
		[tr("HUD_SHOP2_MED_CHIP") % p.medpacks, HudPalette.MUTED if p.medpacks == 0 else HudPalette.IVORY],
		[tr("HUD_SHOP2_SQUAD_CHIP") % model.squad_owned().size(), HudPalette.IVORY],
		[tr("HUD_SHOP2_SLOTS") % [model.slots_used(), model.open_slots()],
			HudPalette.WARN_UI if model.slots_used() >= model.open_slots() else HudPalette.MUTED]]
	var cx := L + _cw(tr("HUD_SHOP2_LOADOUT"), 20.0) + 28.0
	for ch in chips:
		var w := _cw(String(ch[0]), 13.0) + 20.0
		var r := Rect2(cx, LOAD_Y - 6.0, w, 24.0)
		draw_rect(_r(r).grow(-0.5), Color(ch[1], 0.5), false, 1.0)
		_c(String(ch[0]), r.position.x + 10.0, r.position.y + 17.0, 13.0, ch[1], 0.14)
		cx += w + 10.0
	for k in ItemShopModel.PLACES:
		_draw_place(k)
	var keys := ["HUD_SHOP2_SOCK_CORE", "HUD_SHOP2_SOCK_BARREL", "HUD_SHOP2_SOCK_FRAME", "HUD_SHOP2_SOCK_AMMO",
		"HUD_SHOP2_SOCK_MOD"]
	for k in 5:
		var r := _place_rect(k)
		_c(tr(keys[k]), r.position.x - 6.0, r.end.y + 18.0, 12.0, HudPalette.DIM, 0.14, HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x + 12.0)
	var r0 := _place_rect(ItemShopModel.P_SLOT)
	var r5 := _place_rect(ItemShopModel.PLACES - 1)
	_c(tr("HUD_SHOP2_OPEN_SLOTS"), r0.position.x, r0.end.y + 18.0, 12.0, HudPalette.DIM, 0.14, HORIZONTAL_ALIGNMENT_CENTER,
		r5.end.x - r0.position.x)
	# Sell / Undo.
	var k := _focus_place()
	var sr := _sell_rect()
	var on := k >= 0
	var label := tr("HUD_SHOP2_SELL")
	if on:
		label = tr("HUD_SHOP2_UNDO_ITEM") if model.can_undo(k) else tr("HUD_SHOP2_SELL_FOR") % HudFormat.thousands(model.sell_value(k))
	cut_fill(_r(sr), 6.0 * _k, Color(HudPalette.GOLD, 0.12 if on else 0.0))
	cut_line(_r(sr), 6.0 * _k, HudPalette.GOLD if on else HudPalette.NAVY_EDGE, 1.5)
	_c(label, sr.position.x, sr.position.y + 22.0, _fit_px(label, sr.size.x - 16.0, [15.0, 14.0, 13.0, 12.0]),
		HudPalette.GOLD if on else HudPalette.DIM, 0.14, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x)
	var ur := _undo_rect()
	var can := model.undo_last_available()
	cut_fill(_r(ur), 6.0 * _k, Color(HudPalette.IVORY, 0.06 if can else 0.0))
	cut_line(_r(ur), 6.0 * _k, HudPalette.IVORY if can else HudPalette.NAVY_EDGE, 1.0)
	var uc := Vector2(ur.position.x + 30.0, ur.get_center().y) * _k
	draw_arc(uc, 6.0 * _k, PI * 0.9, PI * 2.3, 10, HudPalette.IVORY if can else HudPalette.DIM, 1.5, true)
	_c(tr("HUD_SHOP2_UNDO"), ur.position.x + 44.0, ur.position.y + 22.0, 15.0, HudPalette.IVORY if can else HudPalette.DIM, 0.14)


## The owned place Sell / Undo acts on: the focused loadout square, or the focused item's.
func _focus_place() -> int:
	if area == Area.STRIP:
		return strip_sel if model.item_at(strip_sel) >= 0 else -1
	var idx := int(_items[sel]["goal"]) if sel >= 0 and sel < _items.size() else -1
	var places := model.places_of(idx)
	for k in places:
		if model.can_undo(k):
			return k
	return places[places.size() - 1] if not places.is_empty() else -1


func _draw_place(k: int) -> void:
	var r := _place_rect(k)
	var idx := model.item_at(k)
	var foc := area == Area.STRIP and strip_sel == k
	if idx < 0:
		# Empty: dashed frame and a "+".
		var pr := _r(r)
		var dash := 6.0 * _k
		var col := HudPalette.GOLD if foc else HudPalette.NAVY_EDGE.lightened(0.25)
		for side in 4:
			var a := [pr.position, Vector2(pr.end.x, pr.position.y), pr.end, Vector2(pr.position.x, pr.end.y)][side] as Vector2
			var b := [Vector2(pr.end.x, pr.position.y), pr.end, Vector2(pr.position.x, pr.end.y), pr.position][side] as Vector2
			var n := int(a.distance_to(b) / (dash * 2.0))
			for j in n:
				draw_line(a.lerp(b, (j * 2.0) / (n * 2.0)), a.lerp(b, (j * 2.0 + 1.0) / (n * 2.0)), col, 1.0)
		var c := pr.get_center()
		draw_line(c + Vector2(-9.0, 0.0) * _k, c + Vector2(9.0, 0.0) * _k, col, 2.0)
		draw_line(c + Vector2(0.0, -9.0) * _k, c + Vector2(0.0, 9.0) * _k, col, 2.0)
		return
	var spare := model.is_spare(k)
	cut_fill(_r(r), 8.0 * _k, Color(0.02, 0.035, 0.06))
	cut_line(_r(r), 8.0 * _k, HudPalette.GOLD if foc else (HudPalette.NAVY_EDGE.lightened(0.2) if spare else HudPalette.TEAL),
		2.0 if foc else 1.0)
	_thumb(idx, r.grow(-6.0), 0.35 if spare else 1.0, false)
	if spare:
		_c(tr("HUD_SHOP2_SPARE"), r.position.x, r.end.y - 6.0, 11.0, HudPalette.MUTED, 0.14, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	else:
		var tc := (r.end - Vector2(8.0, 8.0)) * _k
		draw_circle(tc, 8.0 * _k, HudPalette.TEAL)
		ShopIcons.check(self, tc, 4.0 * _k, HudPalette.NAVY)
	if model.can_undo(k):
		var c := (r.position + Vector2(12.0, 12.0)) * _k
		draw_arc(c, 6.0 * _k, PI * 0.9, PI * 2.3, 10, HudPalette.GOLD, 1.6, true)


## Right detail pane: the hovered / focused item, else the advisor's next goal.
func _draw_pane() -> void:
	draw_line(Vector2(PX - 20.0, BODY_Y) * _k, Vector2(PX - 20.0, FOOT_Y - 30.0) * _k, HudPalette.NAVY_EDGE, 1.0)
	var i := _hover if _hover >= 0 else (sel if area == Area.MAIN and tab != ItemShopModel.Tab.SETS else -1)
	var idx := -1
	var card: Dictionary = {}
	if i >= 0 and i < _items.size():
		idx = int(_items[i]["goal"])
		card = _items[i].get("card", {})
	elif area == Area.STRIP:
		idx = model.item_at(strip_sel)
	if idx < 0:
		var a := model.advice().best()
		if a != null:
			idx = a.goal_index if a.goal_index >= 0 else a.item_index
			card = model.card(idx, model.reason_for(a), a.situational)
	if idx < 0:
		return
	if card.is_empty():
		card = model.card(idx, "")
	_draw_detail(idx, card)


func _draw_detail(idx: int, card: Dictionary) -> void:
	var it := model.catalog.at(idx)
	var x := PX
	var w := PR - PX
	var y := BODY_Y
	var ib := Rect2(x, y, 116.0, 116.0)
	cut_fill(_r(ib), 12.0 * _k, Color(0.02, 0.035, 0.06))
	cut_line(_r(ib), 12.0 * _k, HudPalette.NAVY_EDGE.lightened(0.2), 1.0, true)
	_thumb(idx, ib.grow(-8.0), 1.0, false)
	var tx := ib.end.x + 20.0
	var tw := PR - tx
	var name_ := model.name_of(idx).to_upper()
	var words := name_.split(" ", false)
	var npx := _fit_px(name_, tw, [26.0, 23.0, 21.0], 0.1)
	var ny := y + 34.0
	if _cw(name_, npx, 0.1) > tw and words.size() > 1:
		var half := ceili(words.size() / 2.0)
		_c(" ".join(words.slice(0, half)), tx, ny, 21.0, HudPalette.IVORY, 0.1)
		ny += 26.0
		_c(" ".join(words.slice(half)), tx, ny, 21.0, HudPalette.IVORY, 0.1)
	else:
		_c(name_, tx, ny, npx, HudPalette.IVORY, 0.1)
	_pips(tx, ny + 22.0, idx, 7.0)
	var owned := not model.places_of(idx).is_empty()
	if owned:
		_c(tr("HUD_ARMORY_OWNED"), tx, ny + 62.0, 18.0, HudPalette.TEAL, 0.14)
	else:
		_price(tx, ny + 64.0, model.cost(idx), 26.0)
	y = ib.end.y + 22.0
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
	if head != "":
		_c(head, x, y, _fit_px(head, w, [13.0, 12.0, 11.0], 0.12), HudPalette.MUTED, 0.12)
		y += 14.0
	draw_line(Vector2(x, y) * _k, Vector2(PR, y) * _k, HudPalette.NAVY_EDGE, 1.0)
	y += 30.0
	# Stats with the real gain now (green), or capped.
	for l in model.stat_lines(idx):
		var key := String(l["key"])
		var sid := String(l["id"])
		_stat_glyph(sid, Vector2(x + 9.0, y - 6.0))
		_t(ItemShopModel.stat_text(sid, float(l["value"])), x + 28.0, y, 17.0, HudPalette.IVORY, ctx.font_numbers)
		_c(tr(key) if key != "" else sid, x + 96.0, y, 13.0, HudPalette.MUTED, 0.12)
		var gain := float(l.get("gain", 0.0))
		if bool(l["capped"]):
			_c(tr("HUD_SHOP2_CAPPED"), 0.0, y, 13.0, HudPalette.WARN_UI, 0.12, HORIZONTAL_ALIGNMENT_RIGHT, PR)
		elif not owned and gain != 0.0:
			_t("(%s)" % ItemShopModel.stat_text(sid, gain), 0.0, y, 16.0, HudPalette.TEAL, ctx.font_numbers,
				HORIZONTAL_ALIGNMENT_RIGHT, PR)
		y += 30.0
	if it.stat_ids.is_empty() and it.effect_label() != "":
		y += _para(it.effect_label(), x, y - 16.0, w, 15.0, HudPalette.IVORY, 2) + 8.0
	# Why (Recommended).
	if not String(card.get("reason", "")).is_empty():
		y += _para(tr(String(card["reason"])), x, y - 14.0, w, 15.0,
			HudPalette.GOLD if bool(card.get("situational", false)) else HudPalette.MUTED, 3) + 10.0
	# Recipe: owned ticked, the next part highlighted, missing dimmed.
	var tree := model.tree(idx)
	var nxt := int(card.get("next", -1))
	if tree.size() > 1:
		_c(tr("HUD_SHOP2_RECIPE"), x, y + 6.0, 15.0, HudPalette.GOLD, 0.18)
		y += 18.0
		var rows := 0
		for e in tree:
			if rows >= 7 or y > FOOT_Y - 230.0:
				break
			var d := int(e["depth"])
			var ri := int(e["index"])
			var rr := Rect2(x, y, w, 34.0)
			var is_next := not bool(e["owned"]) and ri == nxt and d > 0
			if is_next:
				cut_fill(_r(rr), 6.0 * _k, Color(HudPalette.GOLD, 0.12))
				cut_line(_r(rr), 6.0 * _k, HudPalette.GOLD, 1.5)
			var ex := x + 8.0 + d * 18.0
			_thumb(ri, Rect2(ex, y + 4.0, 26.0, 26.0), 1.0 if bool(e["owned"]) or is_next or d == 0 else 0.5, false)
			var col := HudPalette.TEAL if bool(e["owned"]) else (HudPalette.IVORY if is_next or d == 0 else HudPalette.DIM)
			_t(model.name_of(ri), ex + 34.0, y + 23.0, 15.0, col, ctx.font_body)
			if bool(e["owned"]):
				ShopIcons.check(self, Vector2(PR - 14.0, y + 17.0) * _k, 5.0 * _k, HudPalette.TEAL)
			elif is_next:
				_c(tr("HUD_SHOP2_NEXT_TAG"), 0.0, y + 22.0, 12.0, HudPalette.GOLD, 0.16, HORIZONTAL_ALIGNMENT_RIGHT, PR - 10.0)
			else:
				var ec := model.catalog.at(ri)
				var pp := ec.combine_cost if not ec.recipe.is_empty() else ec.price(1)
				_t("+" + HudFormat.thousands(pp), 0.0, y + 23.0, 14.0, HudPalette.DIM, ctx.font_numbers,
					HORIZONTAL_ALIGNMENT_RIGHT, PR - 8.0)
			y += 36.0
			rows += 1
		_t(tr("HUD_SHOP2_TOTAL_COMPLETE") % [HudFormat.thousands(model.total(idx)), HudFormat.thousands(model.cost(idx))],
			x, y + 18.0, 15.0, HudPalette.GOLD, ctx.font_body)
		y += 30.0
	# Builds into.
	var into := model.builds_into(idx)
	if not into.is_empty() and y < FOOT_Y - 170.0:
		y += 10.0
		_c(tr("HUD_SHOP2_BUILDS_INTO"), x, y + 6.0, 15.0, HudPalette.GOLD, 0.18)
		y += 16.0
		for j in mini(into.size(), 2 if y > FOOT_Y - 260.0 else 3):
			_thumb(into[j], Rect2(x, y + 2.0, 34.0, 34.0))
			_t(model.name_of(into[j]), x + 46.0, y + 18.0, 15.0, HudPalette.IVORY, ctx.font_body)
			_t(HudFormat.thousands(model.total(into[j])), x + 46.0, y + 36.0, 13.0, HudPalette.GOLD, ctx.font_numbers)
			y += 44.0
	# Passive (Signatures).
	if it.passive != &"" and y < FOOT_Y - 110.0:
		y += 8.0
		var ptxt := tr(String(ItemShopModel.PASSIVE_KEYS.get(it.passive, String(it.passive))))
		y += _para(ptxt, x, y, w, 14.0, HudPalette.GOLD, 4) + 6.0
	# Why it cannot be bought now.
	var st := model.state(idx)
	if not owned and st != ItemShopModel.State.AVAILABLE and y < FOOT_Y - 60.0:
		_t(_state_text(idx, st), x, y + 22.0, 15.0, HudPalette.WARN_UI, ctx.font_body)


func _stat_glyph(id: String, c: Vector2) -> void:
	var pc := c * _k
	var s := 6.0 * _k
	diamond(pc, s, HudPalette.MUTED, false)
	if ItemShopModel.CAPS.has(id) and float(ItemShopModel.CAPS[id]) < 0.0:
		draw_line(pc + Vector2(-s * 0.5, 0.0), pc + Vector2(s * 0.5, 0.0), HudPalette.MUTED, 1.2)
	else:
		diamond(pc, s * 0.4, HudPalette.MUTED)


## Wrapped paragraph, first baseline at `y` + px; returns its height (canvas units).
func _para(t: String, x: float, y: float, w: float, px: float, col: Color, max_lines: int) -> float:
	var f := ctx.font_body
	var fs := ts(_px(px))
	var lines := mini(max_lines, roundi(f.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, w * _k, fs).y / f.get_height(fs)))
	draw_multiline_string(f, Vector2(x, y + px) * _k, t, HORIZONTAL_ALIGNMENT_LEFT, w * _k, fs, max_lines, col)
	return maxf(1.0, float(lines)) * f.get_height(fs) / _k


## Footer keycaps: [R] Jump to recommended · [/] Search · [Ctrl+Z] Undo · [Esc] Close.
func _draw_footer() -> void:
	var pad := not Input.get_connected_joypads().is_empty()
	var items: Array
	if tab == ItemShopModel.Tab.SETS:
		items = [["ENTER", "HUD_SHOP2_K_USE"], ["N", "HUD_SHOP2_K_NEW"], ["C", "HUD_SHOP2_K_COPY"], ["V", "HUD_SHOP2_K_PASTE"],
			["ESC", "HUD_SHOP2_K_CLOSE"]]
		if pad:
			items = [["A", "HUD_SHOP2_K_USE"], ["L3", "HUD_SHOP2_K_NEW"], ["B", "HUD_SHOP2_K_CLOSE"]]
	elif pad:
		items = [["A", "HUD_SHOP2_K_BUY"], ["X", "HUD_SHOP2_K_SELL"], ["L3", "HUD_SHOP2_K_JUMP"], ["R3", "HUD_SHOP2_K_UNDO"],
			["LB RB", "HUD_SHOP2_K_TABS"], ["B", "HUD_SHOP2_K_CLOSE"]]
	else:
		items = [["R", "HUD_SHOP2_K_JUMP"], ["/", "HUD_SHOP2_K_SEARCH"], ["BKSP", "HUD_SHOP2_K_SELL"],
			["CTRL+Z", "HUD_SHOP2_K_UNDO"], ["ESC", "HUD_SHOP2_K_CLOSE"]]
	var x := LR
	var widths: Array = []
	var total := 0.0
	for it in items:
		var kw := maxf(30.0, _tw(String(it[0]), 14.0, ctx.font_mono) + 16.0)
		var lw := _cw(tr(String(it[1])), 13.0)
		widths.append([kw, lw])
		total += kw + 10.0 + lw + 34.0
	x = LR - total + 34.0
	for j in items.size():
		var kw: float = widths[j][0]
		key_chip(Vector2(x + kw * 0.5, FOOT_Y) * _k, String(items[j][0]), 28.0 * _k)
		_c(tr(String(items[j][1])), x + kw + 10.0, FOOT_Y + 5.0, 13.0, HudPalette.MUTED, 0.14)
		x += kw + 10.0 + float(widths[j][1]) + 34.0


func _draw_toast() -> void:
	if _toast_t <= 0.0 or _toast == "":
		return
	var a := clampf(_toast_t / 0.4, 0.0, 1.0)
	var w := _tw(_toast, 18.0) + 48.0
	var r := Rect2((L + LR) * 0.5 - w * 0.5, LOAD_Y - 70.0, w, 40.0)
	draw_rect(_r(r), Color(HudPalette.NAVY, 0.96 * a))
	draw_rect(_r(r).grow(-0.5), Color(_toast_col, 0.6 * a), false, 1.0)
	draw_rect(_r(Rect2(r.position, Vector2(4.0, r.size.y))), Color(_toast_col, a))
	_t(_toast, r.position.x, r.position.y + 27.0, 18.0, Color(HudPalette.IVORY, a), ctx.font_body,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
