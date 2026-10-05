class_name VitalsPanel
extends HudWidget
## Bottom-left "me" block (design/ux/hud.md §4.2, §4.4, §4.5; v0.12 look,
## design/ux/hud-v0.12.md §2): hero portrait (93 px) inside a 114 px level ring
## (brass Resonance arc on a 14% track; flash on level-up), the level in a
## cut-corner brass chip; HP numerals 51 + "/ max" + an outlined shield chip;
## status chips (teal buffs, warn debuffs, caps + outline); the segmented HP bar
## (354×10, one segment = tuning.hp_segment HP, shield block outlined; ≤ 25%
## damage colour with a static 1 px frame, no flash); the Lumen row (brass-hi
## diamond glyph, value, gain flyout), RES % and the solid brass "+N SP" chip.
## On the Tab scoreboard only the HP block stays (hud.md §14). Idle: RES 55%.

const W: float = 560.0
const H: float = 132.0
const RING_R: float = 57.0
const FACE_R: float = 46.5
const BAR_W: float = 354.0
const BAR_H: float = 10.0
## [status bit, key, debuff]
const STATUS := [[StatusComponent.BIT_STUN, "HUD_STATUS_STUN", true], [StatusComponent.BIT_ROOT, "HUD_STATUS_ROOT", true],
	[StatusComponent.BIT_SLOW, "HUD_STATUS_SLOW", true], [StatusComponent.BIT_KNOCKBACK, "HUD_STATUS_KNOCKBACK", true],
	[StatusComponent.BIT_DR, "HUD_STATUS_FORTIFIED", false], [StatusComponent.BIT_CC_IMMUNE, "HUD_STATUS_UNSTOPPABLE", false]]

var _econ: EconomyRulesDef
var _flash: float = 0.0
var _last_lumen: int = -1
var _gain: int = 0
var _gain_t: float = 0.0


func bind(c: HudContext) -> void:
	super(c)
	_econ = load(GameSession.ECONOMY_RULES) as EconomyRulesDef
	if c.client != null:
		c.client.level_changed.connect(func(_l: int) -> void: _flash = 1.2)


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_gain_t = maxf(0.0, _gain_t - delta)
	var p := ctx.client.progress if ctx.client != null else null
	if p != null:
		if _last_lumen >= 0 and p.lumen > _last_lumen:
			_gain = p.lumen - _last_lumen
			_gain_t = ctx.tuning.lumen_flyout_seconds
		_last_lumen = p.lumen
	super(delta)


## True when `hp` of `max_hp` is in the critical band (hud.md §4.2).
static func is_critical(hp: int, max_hp: int, low_frac: float) -> bool:
	return clampf(float(hp) / maxf(1.0, max_hp), 0.0, 1.0) <= low_frac


func _draw() -> void:
	var c := ctx.client
	if c == null or c.combat == null:
		return
	var cb := c.combat
	var p := c.progress
	var board := ctx.scoreboard_open
	var top := size.y - H
	var dmg := HudPalette.damage_color(ctx.settings.colorblind)
	var x := 0.0
	if not board:
		_ring(Vector2(RING_R, top + H - RING_R - 8.0), c, p)
		x = 2.0 * RING_R + 24.0
	# HP numerals + max + shield chip + status chips.
	var hp_frac := clampf(float(cb.hp) / maxf(1.0, cb.max_hp), 0.0, 1.0)
	var critical := hp_frac <= ctx.tuning.low_hp_frac and not cb.dead
	var base_y := top + 54.0
	var hs := str(cb.hp)
	text(hs, Vector2(x, base_y), 51, dmg if critical else HudPalette.IVORY, ctx.font_numbers)
	var cx := x + text_width(hs, 51, ctx.font_numbers) + 9.0
	var mx := "/ %d" % cb.max_hp
	text(mx, Vector2(cx, base_y), 22, HudPalette.MUTED, ctx.font_numbers)
	cx += text_width(mx, 22, ctx.font_numbers) + 12.0
	if cb.shield > 0:
		var st := "+%d" % cb.shield
		var sw := text_width(st, 20, ctx.font_numbers) + 14.0
		var sr := Rect2(cx, base_y - ts(20) - 3.0, sw, ts(20) + 9.0)
		draw_rect(sr, Color(HudPalette.IVORY, 0.7), false, 1.5)
		text(st, Vector2(cx + 7.0, base_y), 20, HudPalette.IVORY, ctx.font_numbers)
		cx += sw + 12.0
	for s in STATUS:
		if (cb.status & int(s[0])) != 0:
			var col := HudPalette.WARN_UI if s[2] else HudPalette.TEAL
			var t := tr(s[1])
			var tw := caps_width(t, 15, 0.16) + 18.0
			var r := Rect2(cx, base_y - ts(15) - 6.0, tw, ts(15) + 10.0)
			draw_rect(r, Color(col, 0.6), false, 1.0)
			caps(t, Vector2(cx + 9.0, base_y - 3.0), 15, col, 0.16)
			cx += tw + 9.0
	# The bar shrinks on narrow canvases (720p floor scale) so it stays clear of the skill bar.
	_hp_bar(Rect2(x, top + 70.0, minf(BAR_W, size.x - x - 12.0), BAR_H), cb, hp_frac, critical, dmg)
	if p == null or board:
		return
	_lumen_row(Vector2(x, top + 108.0), p)


func _ring(rc: Vector2, c: ClientWorld, p: SnapshotData.ProgressState) -> void:
	var level := p.level if p != null else c.combat.level
	var frac := 0.0
	if p != null and _econ != null:
		var cur := EconomyMath.exp_for_level(_econ, p.level)
		var need := EconomyMath.exp_to_next(_econ, p.level)
		frac = 1.0 if need <= 0 else clampf(float(p.exp - cur) / need, 0.0, 1.0)
	face_circle(rc, FACE_R, c.hero_def.id if c.hero_def != null else &"")
	draw_arc(rc, RING_R - 3.0, 0.0, TAU, 48, Color(HudPalette.IVORY, 0.14), 4.0, true)
	if frac > 0.0:
		draw_arc(rc, RING_R - 3.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 48, HudPalette.BRASS, 4.0, true)
	if _flash > 0.0:
		var fx := GameSettings.shared().comfort_fx_intensity
		var grow := 0.0 if UiKit.reduce_motion() else (1.2 - _flash) * 12.0
		draw_arc(rc, RING_R + 2.0 + grow, 0.0, TAU, 48, Color(HudPalette.BRASS_HI, _flash / 1.2 * fx), 2.5, true)
		caps(tr("HUD_LEVEL_UP"), Vector2(rc.x + RING_R + 24.0, rc.y - RING_R - 6.0), 15,
			Color(HudPalette.BRASS_HI, minf(1.0, _flash * 2.0)), 0.22)
	# Level chip: ink, brass outline, cut corners, brass-hi number.
	var ls := str(level)
	var w := maxf(33.0, text_width(ls, 18, ctx.font_numbers) + 12.0)
	var lr := Rect2(rc.x - w * 0.5, rc.y + RING_R - 15.0, w, 27.0)
	cut_fill(lr, 6.0, HudPalette.INK)
	cut_line(lr, 6.0, HudPalette.BRASS, 1.5)
	text(ls, Vector2(lr.position.x, lr.position.y + 20.0), 18, HudPalette.BRASS_HI, ctx.font_numbers,
		HORIZONTAL_ALIGNMENT_CENTER, w)


func _lumen_row(at: Vector2, p: SnapshotData.ProgressState) -> void:
	var gy := at.y - 7.0
	var g := Vector2(at.x + 8.0, gy)
	var outer := PackedVector2Array([g + Vector2(0, -9.5), g + Vector2(8, 0), g + Vector2(0, 9.5), g + Vector2(-8, 0), g + Vector2(0, -9.5)])
	draw_polyline(outer, HudPalette.BRASS_HI, 2.0, true)
	diamond(g, 4.0, HudPalette.BRASS_HI)
	var x := at.x + 24.0
	var lumen := HudFormat.thousands(p.lumen)
	text(lumen, Vector2(x, at.y), 22, HudPalette.BRASS_HI, ctx.font_numbers)
	x += text_width(lumen, 22, ctx.font_numbers) + 6.0
	if _gain_t > 0.0 and _gain > 0:
		var a := minf(1.0, _gain_t * 2.0)
		var lift := 0.0 if UiKit.reduce_motion() else (ctx.tuning.lumen_flyout_seconds - _gain_t) * 10.0
		text("+%d" % _gain, Vector2(x, at.y - lift), 16, Color(HudPalette.BRASS, a), ctx.font_mono)
	# Reserve room for a 3-digit gain so the flyout never runs into RES (at 720p
	# the old fixed 30 px gap was narrower than "+24").
	var narrow := size.x < 560.0
	x += maxf(text_width("+99" if narrow else "+999", 16, ctx.font_mono) + 6.0, 30.0 if narrow else 54.0)
	var econ_frac := 0.0
	if _econ != null:
		var cur := EconomyMath.exp_for_level(_econ, p.level)
		var need := EconomyMath.exp_to_next(_econ, p.level)
		econ_frac = 1.0 if need <= 0 else clampf(float(p.exp - cur) / need, 0.0, 1.0)
	var res := tr("HUD_RES") + " %d%%" % floori(econ_frac * 100.0)
	caps(res, Vector2(x, at.y - 1.0), 16, Color(HudPalette.MUTED, idle_a(0.55)), 0.18)
	x += caps_width(res, 16, 0.18) + (12.0 if size.x < 560.0 else 21.0)
	if p.skill_points > 0:
		var bw := brass_chip(Vector2(x, at.y - 7.0), tr("HUD_SP_BADGE") % p.skill_points, 16)
		# How to spend (polish 2026-10-05): the bound quick-spend modifier, held
		# with a skill key; the skill bar then names the node each key buys.
		var kl := ctx.key_label(&"quick_spend", "Alt")
		var kw := maxf(24.0, text_width(kl, 13, ctx.font_mono) + 10.0)
		if x + bw + 6.0 + kw <= size.x:  # never into the skill bar
			key_chip(Vector2(x + bw + 6.0 + kw * 0.5, at.y - 7.0), kl, 24.0, idle_a(0.55))


## Segmented HP bar: one segment per tuning.hp_segment HP with 3 px gaps; the
## shield block outlined after it; critical = damage colour + static frame.
func _hp_bar(r: Rect2, cb: SnapshotData.OwnCombat, frac: float, critical: bool, dmg: Color) -> void:
	var seg := float(maxi(ctx.tuning.hp_segment, 1))
	var total := float(cb.max_hp + cb.shield)
	var unit := r.size.x / maxf(total, 1.0)
	var fill_col := dmg if critical else HudPalette.IVORY
	var track := Color(HudPalette.IVORY, 0.16)
	var hp := float(cb.hp)
	var lo := 0.0
	while lo < cb.max_hp:
		var hi := minf(float(cb.max_hp), lo + seg)
		var sr := Rect2(r.position.x + lo * unit, r.position.y, (hi - lo) * unit - 3.0, r.size.y)
		draw_rect(sr, track)
		var f := clampf((hp - lo) / (hi - lo), 0.0, 1.0)
		if f > 0.0:
			draw_rect(Rect2(sr.position, Vector2(sr.size.x * f, sr.size.y)), fill_col)
		lo = hi
	if cb.shield > 0:
		var sr := Rect2(r.position.x + cb.max_hp * unit, r.position.y, cb.shield * unit - 1.0, r.size.y)
		draw_rect(sr.grow(-0.75), HudPalette.SHIELD, false, 1.5)
	if critical:
		draw_rect(Rect2(r.position, Vector2(cb.max_hp * unit, r.size.y)).grow(4.0), dmg, false, 1.5)
	elif frac <= ctx.tuning.caution_frac:
		draw_rect(Rect2(r.position, Vector2(cb.max_hp * unit, r.size.y)).grow(3.0), Color(HudPalette.WARN_UI, 0.7), false, 1.0)
