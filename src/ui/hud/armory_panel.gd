class_name ArmoryPanel
extends HudWidget
## Armory panel (design/ux/hud.md §10, slice subset §19). Keyboard: F opens it
## on the HQ Armory pad, Up/Down select, Enter buys the next tier, 1/2/3 buy
## that tier, Backspace sells / undoes, Esc closes; gamepad: D-pad Up/Down,
## A buy, X sell, B close. Items with prices, owned / mounted tier,
## wrong-family reason, the auto-sell or undo amount and the per-hit damage
## delta for Core lines. The 3D turntable is out (the first-person gun shows
## the mounts live). While open, HudRoot hides the squad strip, skills and kill
## feed (hud.md §14) so nothing overlaps it.
## Sends requests through PlayerInputSource.request_action only.

const SECTIONS := [["HUD_SOCKET_CORE", ArmoryItemDef.Kind.MOUNT, ArmoryItemDef.Socket.CORE],
	["HUD_SOCKET_FRAME", ArmoryItemDef.Kind.MOUNT, ArmoryItemDef.Socket.FRAME],
	["HUD_SOCKET_CHAMBER", ArmoryItemDef.Kind.AMMO, ArmoryItemDef.Socket.CHAMBER],
	["HUD_ARMORY_SQUAD", ArmoryItemDef.Kind.SQUAD, ArmoryItemDef.Socket.NONE],
	["HUD_ARMORY_CONSUMABLES", ArmoryItemDef.Kind.CONSUMABLE, ArmoryItemDef.Socket.NONE]]
const TIER_NAMES := ["", "I", "II", "III"]
const ROW_H: float = 24.0
const SEL_BG := Color(0.2, 0.3, 0.5, 0.75)

var open: bool = false
var selected: int = 0
var _rows: Array[int] = []
var _keys: Dictionary = {}
var _econ: EconomyRulesDef


func bind(c: HudContext) -> void:
	super(c)
	_econ = load(GameSession.ECONOMY_RULES) as EconomyRulesDef
	var lc = c.session.get("launch_config") if c.session != null else null
	if lc != null and lc.get("debug_armory") == true:
		open = true


## Polls keys (edge-triggered) and updates `open`; called by HudRoot each frame.
func poll() -> void:
	var client := ctx.client
	if client == null or client.progress == null or client.catalog == null:
		open = false
		return
	var p := client.progress
	_build_rows()
	var at := (p.flags & SnapshotData.ProgressState.FLAG_AT_ARMORY) != 0
	if not at or client.is_dead():
		open = false
	if (_edge(KEY_F) or _joy_edge(JOY_BUTTON_Y)) and at:
		open = not open
	if open:
		_panel_keys()
	if client.player_input != null:
		client.player_input.ui_captured = open


func _panel_keys() -> void:
	if _edge(KEY_ESCAPE) or _joy_edge(JOY_BUTTON_B):
		open = false
		return
	if _edge(KEY_DOWN) or _joy_edge(JOY_BUTTON_DPAD_DOWN):
		selected = (selected + 1) % maxi(1, _rows.size())
	if _edge(KEY_UP) or _joy_edge(JOY_BUTTON_DPAD_UP):
		selected = (selected - 1 + _rows.size()) % maxi(1, _rows.size())
	var idx := _rows[selected] if selected < _rows.size() else -1
	if idx < 0:
		return
	if _edge(KEY_ENTER) or _edge(KEY_KP_ENTER) or _joy_edge(JOY_BUTTON_A):
		_request(InputCommand.ACTION_BUY, idx)
	for t in 3:
		if _edge(KEY_1 + t):
			_request(InputCommand.ACTION_BUY, idx | ((t + 1) << 8))
	if _edge(KEY_BACKSPACE) or _joy_edge(JOY_BUTTON_X):
		var item := ctx.client.catalog.at(idx)
		if item != null and item.socket != ArmoryItemDef.Socket.NONE:
			_request(InputCommand.ACTION_SELL, item.socket)


func _request(action: int, arg: int) -> void:
	if ctx.client.player_input != null:
		ctx.client.player_input.request_action(action, arg)


func _edge(key: int) -> bool:
	return _track(key, Input.is_physical_key_pressed(key))


func _joy_edge(button: int) -> bool:
	return _track(1000 + button, Input.is_joy_button_pressed(0, button))


func _track(id: int, down: bool) -> bool:
	var was: bool = _keys.get(id, false)
	_keys[id] = down
	return down and not was


func _build_rows() -> void:
	_rows.clear()
	var cat := ctx.client.catalog
	for sec in SECTIONS:
		for i in cat.items.size():
			var it := cat.items[i]
			if it.kind == sec[1] and (sec[2] == ArmoryItemDef.Socket.NONE or it.socket == sec[2]):
				_rows.append(i)
	selected = clampi(selected, 0, maxi(0, _rows.size() - 1))


func _draw() -> void:
	var client := ctx.client
	if not open or client == null or client.progress == null:
		return
	var p := client.progress
	var cat := client.catalog
	var w := size.x
	var panel_r := Rect2(Vector2.ZERO, size)
	panel(panel_r, ctx.panel_strong)
	text(tr("HUD_ARMORY"), Vector2(16.0, 34.0), 26, HudPalette.TEXT, ctx.font_display)
	text(tr("HUD_ARMORY_KEYS"), Vector2(150.0, 31.0), 13, HudPalette.TEXT_DIM, ctx.font_body)
	text(tr("HUD_LUMEN") + " " + HudFormat.thousands(p.lumen), Vector2(0.0, 34.0), 22, HudPalette.LUMEN,
		ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, w - 16.0)
	var weapon := client.hero_def.weapon
	var y := 48.0
	var r := 0
	var price_x := w * 0.40
	var status_x := w * 0.68
	for sec in SECTIONS:
		text("[%s]" % tr(sec[0]), Vector2(16.0, y + 15.0), 13, HudPalette.MANA, ctx.font_display)
		y += 19.0
		for i in cat.items.size():
			var it := cat.items[i]
			if it.kind != sec[1] or (sec[2] != ArmoryItemDef.Socket.NONE and it.socket != sec[2]):
				continue
			var row := Rect2(Vector2(8.0, y), Vector2(w - 16.0, ROW_H - 2.0))
			if r == selected:
				draw_rect(row, SEL_BG)
				draw_rect(Rect2(row.position, Vector2(3.0, row.size.y)), HudPalette.LUMEN)
			var fits := it.kind != ArmoryItemDef.Kind.MOUNT or it.fits(weapon)
			var col := HudPalette.TEXT if fits else HudPalette.TEXT_OFF
			draw_rect(Rect2(row.position + Vector2(10.0, 5.0), Vector2(12.0, 12.0)), it.hue if fits else HudPalette.TEXT_OFF)
			text(it.display_name, row.position + Vector2(30.0, 17.0), 15, col)
			var prices := ""
			for t in it.tiers():
				prices += ("%s %d   " % [TIER_NAMES[t + 1], it.prices[t]]) if it.tiers() > 1 else "%d" % it.prices[t]
			text(prices, Vector2(price_x, row.position.y + 17.0), 14, HudPalette.LUMEN if fits else HudPalette.TEXT_OFF,
				ctx.font_numbers)
			text(_status(p, i, it, fits), Vector2(status_x, row.position.y + 17.0), 13, _status_color(p, i, it, fits),
				ctx.font_display, HORIZONTAL_ALIGNMENT_LEFT, w - status_x - 12.0)
			y += ROW_H
			r += 1
	if selected < _rows.size():
		_footer(p, cat.at(_rows[selected]), Vector2(16.0, size.y - 46.0), w)


func _footer(p: SnapshotData.ProgressState, it: ArmoryItemDef, at: Vector2, w: float) -> void:
	draw_line(at + Vector2(-8.0, -16.0), at + Vector2(w - 24.0, -16.0), HudPalette.KEYLINE, 1.0)
	text(it.effect_text, at + Vector2(0.0, 2.0), 14, HudPalette.TEXT_DIM)
	var slot := SnapshotData.ProgressState.MOUNT_SOCKETS.find(int(it.socket))
	var held := ctx.client.catalog.at(p.mount_item[slot]) if slot >= 0 else null
	var line := ""
	if held == it:
		var tier := p.mount_tier[slot]
		if tier < it.tiers():
			line = tr("HUD_ARMORY_UPGRADE") % [TIER_NAMES[tier + 1], EconomyMath.upgrade_cost(it, tier + 1, tier)]
		else:
			line = tr("HUD_ARMORY_MAXED")
		var sell := EconomyMath.sell_value(_econ, p.mount_paid[slot], p.mount_paid_visit[slot])
		var undo := p.mount_paid_visit[slot] >= p.mount_paid[slot]
		line += "    " + (tr("HUD_ARMORY_UNDO") if undo else tr("HUD_ARMORY_SELL")) % sell
	elif held != null:
		line = tr("HUD_ARMORY_REPLACE") % [it.price(1), held.display_name,
			EconomyMath.sell_value(_econ, p.mount_paid[slot], p.mount_paid_visit[slot])]
	else:
		line = tr("HUD_ARMORY_BUY") % it.price(1)
		if it.tiers() > 1:
			line += "   " + tr("HUD_ARMORY_BUY_TIER")
	text(line, at + Vector2(0.0, 26.0), 15, HudPalette.LUMEN, ctx.font_display)
	if it.stat == &"mod_damage" and it.fits(ctx.client.hero_def.weapon) and not (held == it and p.mount_tier[slot] >= 3):
		text(_damage_delta(p, it, held == it), at + Vector2(0.0, 2.0), 14, HudPalette.HEAL, ctx.font_numbers,
			HORIZONTAL_ALIGNMENT_RIGHT, w - 32.0)


## Per-hit body damage now vs with the next tier (level L and M_dmg).
func _damage_delta(p: SnapshotData.ProgressState, it: ArmoryItemDef, same: bool) -> String:
	var wd := ctx.client.hero_def.weapon
	var lvl := DamageMath.level_mult(p.level)
	var slot := SnapshotData.ProgressState.MOUNT_SOCKETS.find(int(it.socket))
	var tier := p.mount_tier[slot] if same else 0
	var held := ctx.client.catalog.at(p.mount_item[slot])
	var cur_m := held.values[p.mount_tier[slot] - 1] if held != null and held.stat == &"mod_damage" else 0.0
	var next_m := it.values[mini(tier, it.tiers() - 1)]
	var a := wd.damage * lvl * (1.0 + cur_m)
	var b := wd.damage * lvl * (1.0 + minf(0.25, next_m))
	return tr("HUD_ARMORY_DMG_DELTA") % [a, b, (b / a - 1.0) * 100.0]


func _status(p: SnapshotData.ProgressState, index: int, it: ArmoryItemDef, fits: bool) -> String:
	if not fits:
		return tr("HUD_ARMORY_MANA_ONLY") if it.family == ArmoryItemDef.Family.CRYSTAL else tr("HUD_ARMORY_MECH_ONLY")
	match it.kind:
		ArmoryItemDef.Kind.CONSUMABLE:
			return tr("HUD_ARMORY_CARRY") % [p.medpacks, it.carry_limit]
		ArmoryItemDef.Kind.SQUAD:
			if (p.owned_bits & (1 << index)) != 0:
				return tr("HUD_ARMORY_OWNED")
			var req := ctx.client.catalog.index_of(it.requires) if it.requires != &"" else -1
			return tr("HUD_ARMORY_NEEDS") % ctx.client.catalog.at(req).display_name \
				if req >= 0 and (p.owned_bits & (1 << req)) == 0 else ""
	var slot := SnapshotData.ProgressState.MOUNT_SOCKETS.find(int(it.socket))
	if slot >= 0 and p.mount_item[slot] == index:
		return tr("HUD_ARMORY_MOUNTED") % TIER_NAMES[p.mount_tier[slot]] if it.tiers() > 1 else tr("HUD_ARMORY_LOADED")
	return ""


func _status_color(p: SnapshotData.ProgressState, index: int, it: ArmoryItemDef, fits: bool) -> Color:
	if not fits:
		return HudPalette.TEXT_OFF
	var slot := SnapshotData.ProgressState.MOUNT_SOCKETS.find(int(it.socket))
	if (slot >= 0 and p.mount_item[slot] == index) or (p.owned_bits & (1 << index)) != 0:
		return HudPalette.HEAL
	return HudPalette.WARN
