class_name EconomyHud
extends CanvasLayer
## E13/E15 HUD (design/ux/hud.md §4.4–§4.5, §9, §10, §19 slice subset):
## - bottom-left: level ring filled with Resonance progress, level number,
##   RES bar, `LUMEN 1,240` with a gain flyout, the violet `+N SP` badge,
##   Med-Pack count [4] and a level-up flash;
## - Armory panel (keyboard: F open at the HQ Armory pad, Up/Down select, Enter
##   buy next tier, 1/2/3 buy that tier, Backspace sell / undo, Esc close): items
##   with prices, owned / mounted tier, wrong-family reason, the auto-sell or
##   undo amount and the per-hit damage delta for Core lines. The 3D turntable
##   is out (the first-person gun shows the mounts live);
## - death screen: respawn timer and the Sanctum / Mid Beacon choice ([1] / [2]).
## Reads ClientWorld's replicated state; sends requests through PlayerInputSource.

const SP_COLOR := Color("#B07CFF")
const LUMEN_COLOR := Color("#FFD34D")
const RES_COLOR := Color("#5FD3FF")
const PANEL_BG := Color(0.03, 0.05, 0.09, 0.88)
const SEL_BG := Color(0.2, 0.3, 0.5, 0.75)
const GREY := Color(0.5, 0.52, 0.58)
const SOCKET_NAMES := {1: "CORE", 2: "BARREL", 3: "FRAME", 4: "CHAMBER"}
const TIER_NAMES := ["", "I", "II", "III"]
## Panel sections (hud.md §10 tabs; slice: no Barrel).
const SECTIONS := [["CORE", ArmoryItemDef.Kind.MOUNT, ArmoryItemDef.Socket.CORE],
	["FRAME", ArmoryItemDef.Kind.MOUNT, ArmoryItemDef.Socket.FRAME],
	["CHAMBER", ArmoryItemDef.Kind.AMMO, ArmoryItemDef.Socket.CHAMBER],
	["SQUAD", ArmoryItemDef.Kind.SQUAD, ArmoryItemDef.Socket.NONE],
	["CONSUMABLES", ArmoryItemDef.Kind.CONSUMABLE, ArmoryItemDef.Socket.NONE]]

## Set by AppRoot (the GameSession node).
var session: Node
var armory_open: bool = false
var selected: int = 0
var _client: ClientWorld
var _canvas: Control
var _font: Font
var _rows: Array[int] = []  # catalog indices in panel order
var _keys: Dictionary = {}
var _flash: float = 0.0
var _last_lumen: int = -1
var _gain: int = 0
var _gain_t: float = 0.0
var _econ: EconomyRulesDef


func _ready() -> void:
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw)
	add_child(_canvas)
	_font = ThemeDB.fallback_font
	_econ = load(GameSession.ECONOMY_RULES) as EconomyRulesDef
	_client = session.get("client") as ClientWorld if session != null else null
	if _client != null:
		_client.level_changed.connect(func(_l: int) -> void: _flash = 1.2)
	var lc = session.get("launch_config") if session != null else null
	if lc != null and lc.get("debug_armory") == true:
		armory_open = true


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_gain_t = maxf(0.0, _gain_t - delta)
	if _client == null or _client.progress == null:
		return
	var p := _client.progress
	if _last_lumen >= 0 and p.lumen > _last_lumen:
		_gain = p.lumen - _last_lumen
		_gain_t = 1.2
	_last_lumen = p.lumen
	_build_rows()
	var at := (p.flags & SnapshotData.ProgressState.FLAG_AT_ARMORY) != 0
	if not at or _client.is_dead():
		armory_open = false
	if _edge(KEY_F) and at:
		armory_open = not armory_open
	if armory_open:
		_panel_keys()
	elif _client.is_dead():
		if _edge(KEY_1):
			_request(InputCommand.ACTION_SPAWN_CHOICE, HeroProgress.SPAWN_SANCTUM)
		if _edge(KEY_2):
			_request(InputCommand.ACTION_SPAWN_CHOICE, HeroProgress.SPAWN_BEACON)
	if _client.player_input != null:
		_client.player_input.ui_captured = armory_open
	_canvas.queue_redraw()


func _panel_keys() -> void:
	if _edge(KEY_ESCAPE):
		armory_open = false
		return
	if _edge(KEY_DOWN):
		selected = (selected + 1) % maxi(1, _rows.size())
	if _edge(KEY_UP):
		selected = (selected - 1 + _rows.size()) % maxi(1, _rows.size())
	var idx := _rows[selected] if selected < _rows.size() else -1
	if idx < 0:
		return
	if _edge(KEY_ENTER) or _edge(KEY_KP_ENTER):
		_request(InputCommand.ACTION_BUY, idx)
	for t in 3:
		if _edge(KEY_1 + t):
			_request(InputCommand.ACTION_BUY, idx | ((t + 1) << 8))
	if _edge(KEY_BACKSPACE):
		var item := _client.catalog.at(idx)
		if item != null and item.socket != ArmoryItemDef.Socket.NONE:
			_request(InputCommand.ACTION_SELL, item.socket)


func _request(action: int, arg: int) -> void:
	if _client.player_input != null:
		_client.player_input.request_action(action, arg)


func _edge(key: int) -> bool:
	var down := Input.is_physical_key_pressed(key)
	var was: bool = _keys.get(key, false)
	_keys[key] = down
	return down and not was


func _build_rows() -> void:
	_rows.clear()
	var cat := _client.catalog
	for sec in SECTIONS:
		for i in cat.items.size():
			var it := cat.items[i]
			if it.kind == sec[1] and (sec[2] == ArmoryItemDef.Socket.NONE or it.socket == sec[2]):
				_rows.append(i)
	selected = clampi(selected, 0, maxi(0, _rows.size() - 1))


# --- Drawing ----------------------------------------------------------------------

func _draw() -> void:
	if _client == null or _client.progress == null:
		return
	var p := _client.progress
	if armory_open:
		_draw_armory(p)
	else:
		_draw_status(p)
	if _client.is_dead():
		_draw_death(p)


## Bottom-left: level ring, Resonance bar, Lumen, SP badge, Med-Packs.
func _draw_status(p: SnapshotData.ProgressState) -> void:
	var h := _canvas.size.y
	h -= 18.0  # clear of the squad strip label
	var c := Vector2(58.0, h - 196.0)
	var cur := EconomyMath.exp_for_level(_econ, p.level)
	var need := EconomyMath.exp_to_next(_econ, p.level)
	var frac := 1.0 if need <= 0 else clampf(float(p.exp - cur) / need, 0.0, 1.0)
	_canvas.draw_circle(c, 30.0, Color(0.03, 0.05, 0.1, 0.85))
	_canvas.draw_arc(c, 27.0, 0.0, TAU, 48, Color(0.2, 0.22, 0.3), 5.0, true)
	_canvas.draw_arc(c, 27.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 48, RES_COLOR, 5.0, true)
	if _flash > 0.0:
		_canvas.draw_arc(c, 33.0 + (1.2 - _flash) * 14.0, 0.0, TAU, 48, Color(1, 1, 1, _flash / 1.2), 3.0, true)
		_text("LEVEL UP", c + Vector2(-28.0, -46.0), 18, Color(1, 1, 1, minf(1.0, _flash * 2.0)))
	_text("L%d" % p.level, c + Vector2(-16.0, 8.0), 22, Color.WHITE)
	var x := 100.0
	_text("LUMEN  %s" % _thousands(p.lumen), Vector2(x, h - 206.0), 22, LUMEN_COLOR)
	if _gain_t > 0.0 and _gain > 0:
		_text("+%d" % _gain, Vector2(x + 190.0, h - 206.0 - (1.2 - _gain_t) * 12.0), 18,
			Color(LUMEN_COLOR, minf(1.0, _gain_t * 2.0)))
	var bar := Rect2(Vector2(x, h - 192.0), Vector2(200.0, 9.0))
	_canvas.draw_rect(bar, Color(0, 0, 0, 0.6))
	_canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), RES_COLOR)
	var res_txt := "RES %d / %d" % [p.exp - cur, need] if need > 0 else "RES MAX"
	_text(res_txt, Vector2(x, h - 168.0), 15, RES_COLOR)
	if p.skill_points > 0:
		var badge := Rect2(Vector2(x + 210.0, h - 200.0), Vector2(84.0, 24.0))
		_canvas.draw_rect(badge, SP_COLOR)
		_text("+%d SP" % p.skill_points, badge.position + Vector2(10.0, 18.0), 17, Color.WHITE)
		_text("hold Alt + Q/E/C/G", Vector2(x + 210.0, h - 168.0), 13, SP_COLOR)
	_text("MED x%d [4]%s" % [p.medpacks, "  healing" if (p.flags & SnapshotData.ProgressState.FLAG_HEALING) != 0 else ""],
		Vector2(x + 310.0, h - 190.0), 14, Color(0.6, 1.0, 0.7))
	if (p.flags & SnapshotData.ProgressState.FLAG_AT_ARMORY) != 0:
		_text("[F] ARMORY", Vector2(_canvas.size.x * 0.5 - 50.0, h * 0.5 + 120.0), 22, LUMEN_COLOR)


## hud.md §10 Armory panel (left ~55% of the screen; the gun stays visible).
func _draw_armory(p: SnapshotData.ProgressState) -> void:
	var cat := _client.catalog
	var w := minf(720.0, _canvas.size.x * 0.56)
	var top := 132.0  # below the debug overlay and the match header
	var panel := Rect2(Vector2(16.0, top), Vector2(w, minf(440.0, _canvas.size.y - top - 156.0)))
	_canvas.draw_rect(panel, PANEL_BG)
	_canvas.draw_rect(panel, Color(0.4, 0.5, 0.7), false, 2.0)
	_text("ARMORY", panel.position + Vector2(14.0, 30.0), 24, Color.WHITE)
	_text("[Up/Down] [Enter] buy [Bksp] sell [Esc]", panel.position + Vector2(130.0, 28.0), 12, GREY)
	_text("LUMEN %s" % _thousands(p.lumen), panel.position + Vector2(w - 190.0, 30.0), 22, LUMEN_COLOR)
	var weapon := _client.hero_def.weapon
	var y := panel.position.y + 44.0
	var row_h := 20.0
	var r := 0
	for sec in SECTIONS:
		_text("[%s]" % sec[0], Vector2(panel.position.x + 14.0, y + 14.0), 13, RES_COLOR)
		y += 17.0
		for i in cat.items.size():
			var it := cat.items[i]
			if it.kind != sec[1] or (sec[2] != ArmoryItemDef.Socket.NONE and it.socket != sec[2]):
				continue
			var row := Rect2(Vector2(panel.position.x + 8.0, y), Vector2(w - 16.0, row_h))
			if r == selected:
				_canvas.draw_rect(row, SEL_BG)
			var fits := it.kind != ArmoryItemDef.Kind.MOUNT or it.fits(weapon)
			var col := Color.WHITE if fits else GREY
			_canvas.draw_rect(Rect2(row.position + Vector2(6.0, 4.0), Vector2(12.0, 12.0)), it.hue if fits else GREY)
			_text(it.display_name, row.position + Vector2(26.0, 16.0), 15, col)
			var prices := ""
			for t in it.tiers():
				prices += ("%s %d   " % [TIER_NAMES[t + 1], it.prices[t]]) if it.tiers() > 1 else "%d" % it.prices[t]
			_text(prices, row.position + Vector2(220.0, 16.0), 14, LUMEN_COLOR if fits else GREY)
			_text(_status(p, i, it, fits), row.position + Vector2(w - 200.0, 16.0), 13, _status_color(p, i, it, fits))
			y += row_h
			r += 1
	if selected < _rows.size():
		_draw_footer(p, cat.at(_rows[selected]), Vector2(panel.position.x + 14.0, panel.end.y - 44.0), w)


func _draw_footer(p: SnapshotData.ProgressState, it: ArmoryItemDef, at: Vector2, w: float) -> void:
	_canvas.draw_line(at + Vector2(-6.0, -14.0), at + Vector2(w - 22.0, -14.0), Color(0.4, 0.5, 0.7), 1.0)
	_text(it.effect_text, at + Vector2(0.0, 2.0), 14, Color(0.85, 0.88, 0.95))
	var slot := SnapshotData.ProgressState.MOUNT_SOCKETS.find(int(it.socket))
	var held := _client.catalog.at(p.mount_item[slot]) if slot >= 0 else null
	var line := ""
	if held == it:
		var tier := p.mount_tier[slot]
		if tier < it.tiers():
			line = "[Enter] Upgrade to %s: %d" % [TIER_NAMES[tier + 1], EconomyMath.upgrade_cost(it, tier + 1, tier)]
		else:
			line = "Maxed"
		var sell := EconomyMath.sell_value(_econ, p.mount_paid[slot], p.mount_paid_visit[slot])
		line += "    [Bksp] %s %d" % ["Undo" if p.mount_paid_visit[slot] >= p.mount_paid[slot] else "Sell", sell]
	elif held != null:
		line = "[Enter] Buy %d  (replaces %s, sells for %d)" % [it.price(1), held.display_name,
			EconomyMath.sell_value(_econ, p.mount_paid[slot], p.mount_paid_visit[slot])]
	else:
		line = "[Enter] Buy %d" % it.price(1)
		if it.tiers() > 1:
			line += "   [1/2/3] buy tier"
	_text(line, at + Vector2(0.0, 24.0), 15, LUMEN_COLOR)
	if it.stat == &"mod_damage" and it.fits(_client.hero_def.weapon) and not (held == it and p.mount_tier[slot] >= 3):
		_text(_damage_delta(p, it, held == it), at + Vector2(w - 330.0, 4.0), 14, Color(0.7, 1.0, 0.8))


## Per-hit body damage now vs with the next tier (level L and M_dmg; §4.1).
func _damage_delta(p: SnapshotData.ProgressState, it: ArmoryItemDef, same: bool) -> String:
	var wd := _client.hero_def.weapon
	var lvl := DamageMath.level_mult(p.level)
	var slot := SnapshotData.ProgressState.MOUNT_SOCKETS.find(int(it.socket))
	var tier := p.mount_tier[slot] if same else 0
	var held := _client.catalog.at(p.mount_item[slot])
	var cur_m := held.values[p.mount_tier[slot] - 1] if held != null and held.stat == &"mod_damage" else 0.0
	var next_m := it.values[mini(tier, it.tiers() - 1)]
	var a := wd.damage * lvl * (1.0 + cur_m)
	var b := wd.damage * lvl * (1.0 + minf(0.25, next_m))
	return "Dmg/hit %.1f -> %.1f (%+.0f%%)" % [a, b, (b / a - 1.0) * 100.0]


func _status(p: SnapshotData.ProgressState, index: int, it: ArmoryItemDef, fits: bool) -> String:
	if not fits:
		return "Mana guns only" if it.family == ArmoryItemDef.Family.CRYSTAL else "Mech guns only"
	match it.kind:
		ArmoryItemDef.Kind.CONSUMABLE:
			return "carry %d / %d" % [p.medpacks, it.carry_limit]
		ArmoryItemDef.Kind.SQUAD:
			if (p.owned_bits & (1 << index)) != 0:
				return "OWNED"
			var req := _client.catalog.index_of(it.requires) if it.requires != &"" else -1
			return "needs %s" % _client.catalog.at(req).display_name \
				if req >= 0 and (p.owned_bits & (1 << req)) == 0 else ""
	var slot := SnapshotData.ProgressState.MOUNT_SOCKETS.find(int(it.socket))
	if slot >= 0 and p.mount_item[slot] == index:
		return "MOUNTED %s" % TIER_NAMES[p.mount_tier[slot]] if it.tiers() > 1 else "LOADED"
	return ""


func _status_color(p: SnapshotData.ProgressState, index: int, _it: ArmoryItemDef, fits: bool) -> Color:
	if not fits:
		return GREY
	var slot := SnapshotData.ProgressState.MOUNT_SOCKETS.find(int(_it.socket))
	if (slot >= 0 and p.mount_item[slot] == index) or (p.owned_bits & (1 << index)) != 0:
		return Color(0.5, 1.0, 0.6)
	return Color(0.9, 0.7, 0.5)


## hud.md §9: respawn timer + spawn selection (Sanctum always; Mid Beacon when held).
func _draw_death(p: SnapshotData.ProgressState) -> void:
	var cx := _canvas.size.x * 0.5
	var box := Rect2(Vector2(cx - 260.0, _canvas.size.y * 0.5 + 110.0), Vector2(520.0, 110.0))
	_canvas.draw_rect(box, PANEL_BG)
	_text("RESPAWN IN %ds" % ceili(_client.respawn_seconds_left()), box.position + Vector2(16.0, 30.0), 24, Color.WHITE)
	var beacon := (p.flags & SnapshotData.ProgressState.FLAG_SPAWN_BEACON) != 0
	var ready := (p.flags & SnapshotData.ProgressState.FLAG_BEACON_READY) != 0
	_text("%s [1] SANCTUM - squad + Armory" % ["( )" if beacon else "(*)"], box.position + Vector2(16.0, 60.0), 17,
		Color.WHITE)
	var bt := "%s [2] MID BEACON - no squad, no shop" % ["(*)" if beacon else "( )"]
	if not ready:
		bt += "  (not held / under attack: Sanctum)"
	_text(bt, box.position + Vector2(16.0, 86.0), 17, Color.WHITE if ready else GREY)
	if p.skill_points > 0:
		_text("+%d SP: hold Alt + Q/E/C/G" % p.skill_points, box.position + Vector2(300.0, 30.0), 15, SP_COLOR)


func _text(t: String, pos: Vector2, size: int, col: Color) -> void:
	_canvas.draw_string_outline(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, col.a))
	_canvas.draw_string(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func _thousands(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out
