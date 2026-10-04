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
	&"wardling_damage_mult": "HUD_STAT_WARDLING_DMG"}

var open: bool = false
var tab: int = ShopModel.Tab.ALL
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
var _toast_col: Color = HudPalette.HEAL
var _hint_t: float = 0.0
var _pending: Dictionary = {}
var _last_socket: int = -1
var _mouse_before: int = -1
var _was_open: bool = false
## --debug-armory: open once when the hero first stands on the pad.
var _auto_open: bool = false

const _KEYS: Array[int] = [KEY_F, KEY_B, KEY_ESCAPE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER,
	KEY_1, KEY_2, KEY_3, KEY_BACKSPACE, KEY_Q, KEY_E, KEY_PAGEUP, KEY_PAGEDOWN, KEY_SLASH, KEY_R, KEY_Z]
const _JOY: Array[int] = [JOY_BUTTON_Y, JOY_BUTTON_B, JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
	JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER,
	JOY_BUTTON_RIGHT_STICK]


func bind(c: HudContext) -> void:
	super(c)
	_econ = load(GameSession.ECONOMY_RULES) as EconomyRulesDef
	_builds = load(RecommendedBuildsDef.DEFAULT_PATH) as RecommendedBuildsDef
	var lc = c.session.get("launch_config") if c.session != null else null
	_auto_open = lc != null and lc.get("debug_armory") == true


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
	model.update(client.progress)
	_scan()
	var at := (client.progress.flags & SnapshotData.ProgressState.FLAG_AT_ARMORY) != 0
	if not at or client.is_dead():
		open = false
	elif _auto_open:
		_auto_open = false
		open = true
	if not searching:
		if _e(KEY_F) or _je(JOY_BUTTON_Y) or _open_edge():
			if at and not client.is_dead():
				open = not open
			elif _e(KEY_B) or _open_edge():
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
		tab = ShopModel.Tab.ALL
		query = ""
		searching = false
		_scroll = 0
		_refresh_rows()
		_jump_recommended()
		_mouse_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		searching = false
		if _mouse_before == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_mouse_before = -1


func _refresh_rows() -> void:
	_rows = model.rows(tab, query)
	selected = clampi(selected, 0, maxi(0, _rows.size() - 1))
	_ensure_visible()


## F / the open_shop action (key B fallback when the action is not registered yet).
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
		_set_tab(tab - 1)
	if _e(KEY_E) or _e(KEY_PAGEDOWN) or _je(JOY_BUTTON_RIGHT_SHOULDER):
		_set_tab(tab + 1)
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
	if _e(KEY_R):
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


func _set_tab(t: int) -> void:
	tab = posmod(t, ShopModel.TAB_KEYS.size())
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
		tab = ShopModel.Tab.ALL
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
	_pending = {"kind": "buy", "index": index, "tier": model.held_tier(index), "med": ctx.client.progress.medpacks,
		"cost": model.purchase_cost(index, tier), "t": 0.0}
	_request(InputCommand.ACTION_BUY, ShopModel.buy_arg(index, tier))


func _sell(index: int) -> void:
	var socket := model.sell_socket(index)
	if socket < 0:
		_show_toast(tr("HUD_SHOP_NO_SELL"), HudPalette.WARN)
		return
	_send_sell(socket, model.sell_value(socket))


func _undo() -> void:
	var socket := model.undo_socket(_last_socket)
	if socket < 0:
		_show_toast(tr("HUD_SHOP_NO_UNDO"), HudPalette.WARN)
		return
	_send_sell(socket, model.sell_value(socket))


func _send_sell(socket: int, value: int) -> void:
	var slot := SnapshotData.ProgressState.MOUNT_SOCKETS.find(socket)
	_pending = {"kind": "sell", "slot": slot, "item": ctx.client.progress.mount_item[slot], "value": value, "t": 0.0}
	_request(InputCommand.ACTION_SELL, socket)


## Watches the replicated progress for the outcome of the last request.
func _check_pending(dt: float) -> void:
	if _pending.is_empty():
		return
	_pending["t"] = float(_pending["t"]) + dt
	var p := ctx.client.progress
	if _pending["kind"] == "buy":
		var idx: int = _pending["index"]
		if model.held_tier(idx) > int(_pending["tier"]) or p.medpacks > int(_pending["med"]):
			var it := ctx.client.catalog.at(idx)
			_show_toast(tr("HUD_SHOP_TOAST_BOUGHT") % [it.display_name, _pending["cost"]], HudPalette.HEAL)
			if model.sell_socket(idx) >= 0:
				_last_socket = int(it.socket)
			_pending.clear()
			return
	else:
		var slot: int = _pending["slot"]
		if p.mount_item[slot] != int(_pending["item"]):
			var it := ctx.client.catalog.at(int(_pending["item"]))
			_show_toast(tr("HUD_SHOP_TOAST_SOLD") % [it.display_name if it != null else "", _pending["value"]],
				HudPalette.LUMEN)
			_last_socket = -1
			_pending.clear()
			return
	if float(_pending["t"]) > PENDING_TIMEOUT_S:
		_show_toast(tr("HUD_SHOP_TOAST_REFUSED"), HudPalette.DANGER)
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
		_hover = _card_at(event.position)
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
	for t in ShopModel.TAB_KEYS.size():
		if _tab_rect(t).has_point(pos):
			_set_tab(t)
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
		if model.undo_socket(_last_socket) >= 0 and model.sell_socket(idx) < 0:
			_undo()
		else:
			_sell(idx)
	for t in 3:
		if _tier_rect(t).has_point(pos) and idx >= 0 and model.catalog.at(idx).tiers() > t:
			_buy(idx, t + 1)
	var steps := model.build().steps() if model.build() != null else 0
	for s in steps:
		if _chip_rect(s).has_point(pos):
			var ci := model.catalog.index_of(model.build().item_at(s))
			if ci >= 0:
				if not _rows.has(ci):
					tab = ShopModel.Tab.ALL
					query = ""
					_rows = model.rows(tab, query)
				selected = maxi(0, _rows.find(ci))
				_ensure_visible()


# --- Layout (design units, shared by drawing and hit tests) ----------------------------

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


func _tab_rect(t: int) -> Rect2:
	var x := PAD
	for i in t:
		x += _tab_w(i) + 6.0
	return Rect2(x, TAB_Y, _tab_w(t), TAB_H)


func _tab_w(t: int) -> float:
	return text_width(tr(ShopModel.TAB_KEYS[t]), 16, ctx.font_display) + 34.0


func _search_rect() -> Rect2:
	return Rect2(size.x * 0.34, 14.0, 300.0, 40.0)


func _close_rect() -> Rect2:
	return Rect2(size.x - PAD - 44.0, 14.0, 44.0, 40.0)


func _buy_rect() -> Rect2:
	return Rect2(size.x * 0.60, size.y - FOOTER_H + 6.0, 250.0, 56.0)


func _sell_rect() -> Rect2:
	var x := size.x * 0.60 + 262.0
	return Rect2(x, size.y - FOOTER_H + 6.0, size.x - PAD - x, 56.0)


func _tier_rect(t: int) -> Rect2:
	var d := _detail_rect()
	return Rect2(d.position.x + 12.0, d.position.y + 250.0 + 32.0 * t, d.size.x - 24.0, 30.0)


func _chip_rect(step: int) -> Rect2:
	var n := maxi(1, model.build().steps() if model != null and model.build() != null else 1)
	var w := minf(84.0, (_left_w() + GAP) / n)
	return Rect2(PAD + step * w, size.y - FOOTER_H - BUILD_H + 38.0, w - 6.0, 52.0)


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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.075, 0.97))
	draw_rect(Rect2(Vector2.ZERO, size), HudPalette.KEYLINE, false, 1.0)
	_draw_header(p)
	_draw_tabs()
	_draw_cards()
	_draw_build_strip()
	_draw_detail()
	_draw_footer()
	_draw_toast()


func _draw_hint() -> void:
	var t := tr("HUD_SHOP_OFF_PAD")
	var w := text_width(t, 22, ctx.font_display) + 48.0
	var r := Rect2(size.x * 0.5 - w * 0.5, size.y - 150.0, w, 48.0)
	panel(r, ctx.panel_strong)
	text_c(t, r.get_center(), 22, HudPalette.LUMEN, ctx.font_display)


func _draw_header(p: SnapshotData.ProgressState) -> void:
	text(tr("HUD_ARMORY"), Vector2(PAD, 44.0), 32, HudPalette.TEXT, ctx.font_display)
	var b := model.build()
	if b != null:
		text(tr("HUD_SHOP_BUILD_FOR") % b.display_name, Vector2(PAD, 62.0), 14, HudPalette.TEXT_DIM, ctx.font_body)
	var lumen := HudFormat.thousands(p.lumen)
	text(lumen, Vector2(0.0, 54.0), 38, HudPalette.LUMEN, ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, size.x - PAD - 80.0)
	text(tr("HUD_LUMEN"), Vector2(0.0, 18.0), 13, HudPalette.TEXT_DIM, ctx.font_display, HORIZONTAL_ALIGNMENT_RIGHT,
		size.x - PAD - 80.0)
	diamond(Vector2(size.x - PAD - 80.0 - text_width(lumen, 38, ctx.font_numbers) - 24.0, 42.0), 11.0, HudPalette.LUMEN)
	var cr := _close_rect()
	draw_rect(cr, CARD_BG)
	draw_rect(cr, HudPalette.KEYLINE, false, 1.0)
	draw_line(cr.get_center() + Vector2(-8, -8), cr.get_center() + Vector2(8, 8), HudPalette.TEXT, 2.5)
	draw_line(cr.get_center() + Vector2(-8, 8), cr.get_center() + Vector2(8, -8), HudPalette.TEXT, 2.5)
	draw_line(Vector2(PAD, HEADER_H), Vector2(size.x - PAD, HEADER_H), HudPalette.KEYLINE, 1.0)


func _draw_tabs() -> void:
	for t in ShopModel.TAB_KEYS.size():
		var r := _tab_rect(t)
		var on := t == tab
		draw_rect(r, SEL_BG if on else CARD_BG)
		draw_rect(r, HudPalette.KEYLINE, false, 1.0)
		if on:
			draw_rect(Rect2(r.position.x, r.end.y - 3.0, r.size.x, 3.0), HudPalette.LUMEN)
		text_c(tr(ShopModel.TAB_KEYS[t]), r.get_center(), 16, HudPalette.TEXT if on else HudPalette.TEXT_DIM, ctx.font_display)
	var s := _search_rect()
	draw_rect(s, CARD_BG)
	draw_rect(s, HudPalette.LUMEN if searching else HudPalette.KEYLINE, false, 2.0 if searching else 1.0)
	var shown := query + ("_" if searching else "")
	if shown == "":
		text(tr("HUD_SHOP_SEARCH"), s.position + Vector2(12.0, 26.0), 15, HudPalette.TEXT_OFF)
	else:
		text(shown, s.position + Vector2(12.0, 26.0), 16, HudPalette.TEXT)


func _draw_cards() -> void:
	var p := ctx.client.progress
	if _rows.is_empty():
		text(tr("HUD_SHOP_EMPTY"), Vector2(PAD + 8.0, GRID_Y + 40.0), 18, HudPalette.TEXT_DIM)
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
		var dim := st == ShopModel.State.CANT_AFFORD or st == ShopModel.State.WRONG_FAMILY or st == ShopModel.State.LOCKED
		var a := 0.45 if dim else 1.0
		var held := model.held_tier(idx)
		draw_rect(r, SEL_BG if i == selected else CARD_BG)
		draw_rect(r, HudPalette.KEYLINE, false, 1.0)
		if i == _hover and i != selected:
			draw_rect(r, Color(1, 1, 1, 0.06))
		if i == selected:
			draw_rect(r, HudPalette.LUMEN, false, 2.5)
		if idx == next:
			draw_rect(r.grow(-4.0), HudPalette.HEAL, false, 2.0)
		ShopIcons.draw(self, it, Rect2(r.position + Vector2(10.0, 12.0), Vector2(80.0, 80.0)), Color(it.hue, a))
		var tx := r.position.x + 102.0
		text(_fit(it.display_name, 18, r.size.x - 112.0, ctx.font_display), Vector2(tx, r.position.y + 30.0), 18,
			Color(HudPalette.TEXT, a), ctx.font_display)
		var label := ""
		var col := HudPalette.LUMEN
		match st:
			ShopModel.State.OWNED, ShopModel.State.MAXED:
				label = tr("HUD_ARMORY_OWNED") if st == ShopModel.State.OWNED else tr("HUD_ARMORY_MAXED")
				col = HudPalette.HEAL
			ShopModel.State.WRONG_FAMILY:
				label = tr("HUD_ARMORY_MANA_ONLY") if it.family == ArmoryItemDef.Family.CRYSTAL else tr("HUD_ARMORY_MECH_ONLY")
				col = HudPalette.TEXT_OFF
			ShopModel.State.LOCKED:
				label = tr("HUD_ARMORY_NEEDS") % ctx.client.catalog.find(it.requires).display_name
				col = HudPalette.WARN
			ShopModel.State.CARRY_FULL:
				label = tr("HUD_SHOP_CARRY_FULL")
				col = HudPalette.HEAL
			_:
				label = HudFormat.thousands(model.purchase_cost(idx))
				col = HudPalette.LUMEN if st == ShopModel.State.AVAILABLE else HudPalette.DANGER
		var lx := tx
		if st == ShopModel.State.AVAILABLE or st == ShopModel.State.CANT_AFFORD:
			diamond(Vector2(tx + 7.0, r.position.y + 55.0), 6.0, Color(col, a))
			lx += 20.0
		text(_fit(label, 17, r.end.x - lx - 8.0, ctx.font_numbers), Vector2(lx, r.position.y + 62.0), 17, Color(col, a),
			ctx.font_numbers)
		_draw_pips(it, held, Vector2(tx, r.position.y + 84.0), a)
		if it.kind == ArmoryItemDef.Kind.CONSUMABLE:
			text(tr("HUD_ARMORY_CARRY") % [p.medpacks, it.carry_limit], Vector2(tx, r.position.y + 94.0), 13,
				Color(HudPalette.TEXT_DIM, a))
		if model.is_recommended(idx):
			ShopIcons.star(self, r.position + Vector2(r.size.x - 16.0, 16.0), 9.0, HudPalette.CRIT)
		if idx == next:
			var tag := tr("HUD_SHOP_NEXT")
			var tw := text_width(tag, 12, ctx.font_display) + 12.0
			var tr_ := Rect2(r.end.x - tw - 30.0, r.position.y + 6.0, tw, 20.0)
			draw_rect(tr_, HudPalette.HEAL)
			text_c(tag, tr_.get_center(), 12, Color.BLACK, ctx.font_display)


## Tier pips: filled = held, hollow = not yet (only for tiered lines).
func _draw_pips(it: ArmoryItemDef, held: int, at: Vector2, a: float) -> void:
	if it.tiers() <= 1:
		return
	for t in it.tiers():
		var c := at + Vector2(7.0 + 18.0 * t, -4.0)
		diamond(c, 6.0, Color(HudPalette.HEAL if t < held else HudPalette.TEXT_OFF, a), t < held)


func _draw_build_strip() -> void:
	var b := model.build()
	var y := size.y - FOOTER_H - BUILD_H
	draw_line(Vector2(PAD, y + 2.0), Vector2(PAD + _left_w(), y + 2.0), HudPalette.KEYLINE, 1.0)
	if b == null:
		text(tr("HUD_SHOP_NO_BUILD"), Vector2(PAD, y + 28.0), 15, HudPalette.TEXT_DIM)
		return
	ShopIcons.star(self, Vector2(PAD + 9.0, y + 22.0), 9.0, HudPalette.CRIT)
	text(tr("HUD_SHOP_RECOMMENDED") % b.display_name, Vector2(PAD + 24.0, y + 28.0), 16, HudPalette.TEXT, ctx.font_display)
	text(tr("HUD_SHOP_JUMP_KEY"), Vector2(0.0, y + 28.0), 13, HudPalette.TEXT_DIM, ctx.font_body,
		HORIZONTAL_ALIGNMENT_RIGHT, PAD + _left_w())
	var next := model.next_step()
	for s in b.steps():
		var r := _chip_rect(s)
		var index := ctx.client.catalog.index_of(b.item_at(s))
		var it := ctx.client.catalog.at(index)
		if it == null:
			continue
		var done := model.step_done(s)
		var a := 0.4 if done else 1.0
		draw_rect(r, CARD_BG)
		draw_rect(r, HudPalette.HEAL if s == next else HudPalette.KEYLINE, false, 2.5 if s == next else 1.0)
		ShopIcons.draw(self, it, Rect2(r.position + Vector2(4.0, 6.0), Vector2(40.0, 40.0)), Color(it.hue, a))
		var lab: String = TIER_NAMES[b.target_at(s)] if it.tiers() > 1 else ("x%d" % b.target_at(s) if it.kind == ArmoryItemDef.Kind.CONSUMABLE else "")
		text(lab, r.position + Vector2(48.0, 32.0), 16, Color(HudPalette.TEXT, a), ctx.font_numbers)
		if done:
			ShopIcons.check(self, r.position + Vector2(r.size.x - 12.0, 12.0), 6.0, HudPalette.HEAL)


func _draw_detail() -> void:
	var d := _detail_rect()
	panel(d, ctx.panel)
	var idx := _sel_index()
	if idx < 0:
		return
	var it := ctx.client.catalog.at(idx)
	var p := ctx.client.progress
	var st := model.state(idx)
	var x := d.position.x + 16.0
	var y := d.position.y
	ShopIcons.draw(self, it, Rect2(Vector2(x, y + 16.0), Vector2(84.0, 84.0)), it.hue)
	text(it.display_name, Vector2(x + 100.0, y + 46.0), 28, HudPalette.TEXT, ctx.font_display)
	text(_kind_line(it), Vector2(x + 100.0, y + 72.0), 15, HudPalette.TEXT_DIM)
	var bx := x + 100.0
	if model.is_recommended(idx):
		ShopIcons.star(self, Vector2(bx + 8.0, y + 90.0), 8.0, HudPalette.CRIT)
		text(tr("HUD_SHOP_RECOMMENDED_TAG"), Vector2(bx + 22.0, y + 96.0), 14, HudPalette.CRIT, ctx.font_display)
		bx += 22.0 + text_width(tr("HUD_SHOP_RECOMMENDED_TAG"), 14, ctx.font_display) + 16.0
	var held := model.held_tier(idx)
	if held > 0:
		var s := tr("HUD_ARMORY_MOUNTED") % TIER_NAMES[held] if it.tiers() > 1 and it.kind != ArmoryItemDef.Kind.SQUAD \
			else tr("HUD_ARMORY_OWNED")
		text(s, Vector2(bx, y + 96.0), 14, HudPalette.HEAL, ctx.font_display)
	draw_line(Vector2(x, y + 116.0), Vector2(d.end.x - 16.0, y + 116.0), HudPalette.KEYLINE, 1.0)
	var w := d.size.x - 32.0
	draw_multiline_string_outline(ctx.font_body, Vector2(x, y + 146.0), it.effect_text, HORIZONTAL_ALIGNMENT_LEFT, w, 17, 3, 4,
		HudPalette.OUTLINE)
	draw_multiline_string(ctx.font_body, Vector2(x, y + 146.0), it.effect_text, HORIZONTAL_ALIGNMENT_LEFT, w, 17, 3, HudPalette.TEXT)
	var ty := y + 232.0
	if it.tiers() > 1 and it.values.size() > 0:
		text(tr("HUD_SHOP_COL_TIER"), Vector2(x + 4.0, ty), 13, HudPalette.TEXT_DIM, ctx.font_display)
		text(tr("HUD_SHOP_COL_EFFECT"), Vector2(x + 70.0, ty), 13, HudPalette.TEXT_DIM, ctx.font_display)
		text(tr("HUD_SHOP_COL_PRICE"), Vector2(0.0, ty), 13, HudPalette.TEXT_DIM, ctx.font_display, HORIZONTAL_ALIGNMENT_RIGHT,
			d.end.x - 150.0)
		text(tr("HUD_SHOP_COL_UPGRADE"), Vector2(0.0, ty), 13, HudPalette.TEXT_DIM, ctx.font_display, HORIZONTAL_ALIGNMENT_RIGHT,
			d.end.x - 28.0)
		for row in model.tier_rows(idx):
			var t: int = row["tier"]
			var r := _tier_rect(t - 1)
			if bool(row["held"]):
				draw_rect(r, Color(HudPalette.HEAL, 0.18))
				draw_rect(r, HudPalette.HEAL, false, 1.0)
			elif t == held + 1 or (held == 0 and t == 1):
				draw_rect(r, Color(1, 1, 1, 0.05))
			var by := r.position.y + 21.0
			text(TIER_NAMES[t], Vector2(x + 8.0, by), 17, HudPalette.TEXT, ctx.font_numbers)
			text(_effect_text(it, row), Vector2(x + 70.0, by), 15, HudPalette.TEXT)
			text(HudFormat.thousands(row["price"]), Vector2(0.0, by), 16, HudPalette.LUMEN, ctx.font_numbers,
				HORIZONTAL_ALIGNMENT_RIGHT, d.end.x - 150.0)
			text(("+" + HudFormat.thousands(row["upgrade"])) if t > 1 else "-", Vector2(0.0, by), 15, HudPalette.TEXT_DIM,
				ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, d.end.x - 28.0)
		ty += 130.0
	elif it.values.size() > 0:
		text(_effect_text(it, model.tier_rows(idx)[0]), Vector2(x, ty + 10.0), 17, HudPalette.TEXT)
		text(tr("HUD_SHOP_PRICE") % HudFormat.thousands(it.prices[0]), Vector2(x, ty + 40.0), 17, HudPalette.LUMEN,
			ctx.font_numbers)
		ty += 80.0
	else:
		text(tr("HUD_SHOP_PRICE") % HudFormat.thousands(it.prices[0]), Vector2(x, ty + 10.0), 17, HudPalette.LUMEN,
			ctx.font_numbers)
		ty += 50.0
	if it.stat == &"mod_damage" and it.fits(ctx.client.hero_def.weapon) and st != ShopModel.State.MAXED:
		text(_damage_delta(p, it), Vector2(x, ty + 10.0), 16, HudPalette.HEAL, ctx.font_numbers)
		ty += 30.0
	var note := _note(idx, st) if st != ShopModel.State.MAXED and st != ShopModel.State.OWNED else ""
	if note != "":
		text(note, Vector2(x, ty + 10.0), 15, HudPalette.WARN if st != ShopModel.State.AVAILABLE else HudPalette.TEXT_DIM)
		ty += 28.0
	var sock := model.sell_socket(idx)
	if sock >= 0:
		var v := model.sell_value(sock)
		text((tr("HUD_SHOP_UNDO_INFO") if model.is_undo(sock) else tr("HUD_SHOP_SELL_INFO")) % v, Vector2(x, ty + 10.0), 15,
			HudPalette.LUMEN)


## Why the item is unavailable, or what a buy would swap out.
func _note(index: int, st: int) -> String:
	if st == ShopModel.State.AVAILABLE:
		var it := ctx.client.catalog.at(index)
		var cur := model.held_item(it)
		if cur != null and cur != it:
			return tr("HUD_SHOP_REPLACES") % [cur.display_name, model.swap_credit(index)]
		return ""
	return _reason(index, st)


func _kind_line(it: ArmoryItemDef) -> String:
	var fam := ""
	match it.family:
		ArmoryItemDef.Family.CRYSTAL:
			fam = " - " + tr("HUD_ARMORY_MANA_ONLY")
		ArmoryItemDef.Family.CHIP:
			fam = " - " + tr("HUD_ARMORY_MECH_ONLY")
	return tr(ShopModel.TAB_KEYS[ShopModel.tab_of(it)]) + fam


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
	draw_line(Vector2(PAD, y), Vector2(size.x - PAD, y), HudPalette.KEYLINE, 1.0)
	text(tr("HUD_SHOP_KEYS"), Vector2(PAD, y + 40.0), 14, HudPalette.TEXT_DIM, ctx.font_body)
	var idx := _sel_index()
	if idx < 0:
		return
	var st := model.state(idx)
	var it := ctx.client.catalog.at(idx)
	var b := _buy_rect()
	var ok := st == ShopModel.State.AVAILABLE
	draw_rect(b, Color(0.9, 0.7, 0.15, 0.95) if ok else Color(0.2, 0.22, 0.28, 0.9))
	draw_rect(b, HudPalette.KEYLINE, false, 1.0)
	text_c(_buy_label(idx, it, st), b.get_center(), 20, Color.BLACK if ok else HudPalette.TEXT_OFF, ctx.font_display)
	var s := _sell_rect()
	var sock := model.sell_socket(idx)
	var undo_sock := model.undo_socket(_last_socket)
	var label := ""
	var can := false
	if sock >= 0:
		label = (tr("HUD_SHOP_BTN_UNDO") if model.is_undo(sock) else tr("HUD_SHOP_BTN_SELL")) % model.sell_value(sock)
		can = true
	elif undo_sock >= 0:
		label = tr("HUD_SHOP_BTN_UNDO") % model.sell_value(undo_sock)
		can = true
	else:
		label = tr("HUD_SHOP_BTN_SELL_NA")
	draw_rect(s, Color(0.14, 0.2, 0.32, 0.95) if can else Color(0.12, 0.13, 0.18, 0.9))
	draw_rect(s, HudPalette.KEYLINE, false, 1.0)
	text_c(label, s.get_center(), 17, HudPalette.TEXT if can else HudPalette.TEXT_OFF, ctx.font_display)


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
	draw_rect(r, Color(HudPalette.PANEL_STRONG, 0.95 * a))
	draw_rect(r, Color(_toast_col, a), false, 2.0)
	text_c(_toast, r.get_center(), 22, Color(_toast_col, a), ctx.font_display)


## `t` cut with ".." so it fits `max_w` at `size_`.
func _fit(t: String, size_: int, max_w: float, font: Font = null) -> String:
	if text_width(t, size_, font) <= max_w:
		return t
	var s := t
	while s.length() > 1 and text_width(s + "..", size_, font) > max_w:
		s = s.left(s.length() - 1)
	return s + ".."
