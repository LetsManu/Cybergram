class_name VitalsPanel
extends HudWidget
## Bottom-left "me" panel (design/ux/hud.md §4.2, §4.4, §4.5): level ring
## filled with Resonance progress + level number (flash on level-up), status
## chips, HP digits + segmented bar (one segment = tuning.hp_segment HP; normal
## white, caution edge at ≤ 50%, critical ≤ 25% red frame — static, no flash),
## shield appended as a white-outlined block, `LUMEN 1,240` with a gain flyout,
## RES %, and the violet `+N SP` badge.

const W: float = 424.0
const H: float = 112.0
const RING_R: float = 34.0
const BAR_W: float = 300.0
const BAR_H: float = 16.0
const STATUS := [[StatusComponent.BIT_STUN, "HUD_STATUS_STUN"], [StatusComponent.BIT_ROOT, "HUD_STATUS_ROOT"],
	[StatusComponent.BIT_SLOW, "HUD_STATUS_SLOW"], [StatusComponent.BIT_KNOCKBACK, "HUD_STATUS_KNOCKBACK"],
	[StatusComponent.BIT_DR, "HUD_STATUS_FORTIFIED"], [StatusComponent.BIT_CC_IMMUNE, "HUD_STATUS_UNSTOPPABLE"]]

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


func _draw() -> void:
	var c := ctx.client
	if c == null or c.combat == null:
		return
	var cb := c.combat
	var p := c.progress
	var top := size.y - H
	panel(Rect2(0.0, top, W, H))
	# Level ring + Resonance.
	var rc := Vector2(14.0 + RING_R, top + H * 0.5)
	var level := p.level if p != null else cb.level
	var frac := 0.0
	if p != null and _econ != null:
		var cur := EconomyMath.exp_for_level(_econ, p.level)
		var need := EconomyMath.exp_to_next(_econ, p.level)
		frac = 1.0 if need <= 0 else clampf(float(p.exp - cur) / need, 0.0, 1.0)
	draw_circle(rc, RING_R - 3.0, Color(0.02, 0.03, 0.06, 0.9))
	draw_arc(rc, RING_R - 3.0, 0.0, TAU, 48, Color(0.22, 0.22, 0.32), 5.0, true)
	draw_arc(rc, RING_R - 3.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 48, HudPalette.RESONANCE, 5.0, true)
	if _flash > 0.0:
		draw_arc(rc, RING_R + 2.0 + (1.2 - _flash) * 12.0, 0.0, TAU, 48, Color(1, 1, 1, _flash / 1.2), 2.5, true)
		text(tr("HUD_LEVEL_UP"), Vector2(0.0, top + 19.0), 14, Color(HudPalette.SP.lightened(0.3), minf(1.0, _flash * 2.0)),
			ctx.font_display, HORIZONTAL_ALIGNMENT_RIGHT, W - 12.0)
	text_c(str(level), rc + Vector2(0.0, -2.0), 28, HudPalette.TEXT, ctx.font_numbers)
	text_c(tr("HUD_LEVEL_SHORT"), rc + Vector2(0.0, 19.0), 11, HudPalette.TEXT_DIM, ctx.font_display)
	var x := 2.0 * RING_R + 28.0
	# Status chips (newest-left order is not replicated; fixed priority order).
	var sx := x
	for s in STATUS:
		if (cb.status & int(s[0])) != 0:
			var t := tr(s[1])
			var tw := text_width(t, 12, ctx.font_display) + 10.0
			draw_rect(Rect2(sx, top + 6.0, tw, 16.0), Color(0.9, 0.9, 1.0, 0.18))
			draw_rect(Rect2(sx, top + 6.0, tw, 16.0), Color(1, 1, 1, 0.6), false, 1.0)
			text(t, Vector2(sx + 5.0, top + 19.0), 12, HudPalette.TEXT, ctx.font_display)
			sx += tw + 4.0
	# HP digits + bar.
	var hp_frac := clampf(float(cb.hp) / maxf(1.0, cb.max_hp), 0.0, 1.0)
	var critical := hp_frac <= ctx.tuning.low_hp_frac and not cb.dead
	var hp_col := HudPalette.DANGER.lightened(0.25) if critical else HudPalette.TEXT
	text(str(cb.hp), Vector2(x, top + 50.0), 26, hp_col, ctx.font_numbers)
	var hw := text_width(str(cb.hp), 26, ctx.font_numbers)
	text(" / %d" % cb.max_hp, Vector2(x + hw, top + 50.0), 17, HudPalette.TEXT_DIM, ctx.font_numbers)
	if cb.shield > 0:
		text("+%d" % cb.shield, Vector2(x + hw + text_width(" / %d" % cb.max_hp, 17, ctx.font_numbers) + 8.0, top + 50.0),
			17, HudPalette.SHIELD, ctx.font_numbers)
	_hp_bar(Rect2(x, top + 58.0, BAR_W, BAR_H), cb, hp_frac, critical)
	# Lumen, Resonance %, SP badge.
	if p == null:
		return
	var ly := top + 100.0
	var lumen := tr("HUD_LUMEN") + " " + HudFormat.thousands(p.lumen)
	text(lumen, Vector2(x, ly), 17, HudPalette.LUMEN, ctx.font_display)
	var lw := text_width(lumen, 17, ctx.font_display)
	if _gain_t > 0.0 and _gain > 0:
		var a := minf(1.0, _gain_t * 2.0)
		text("+%d" % _gain, Vector2(x + lw + 6.0, ly - (ctx.tuning.lumen_flyout_seconds - _gain_t) * 10.0), 15,
			Color(HudPalette.LUMEN, a), ctx.font_numbers)
	var res := tr("HUD_RES") + " %d%%" % floori(frac * 100.0)
	text(res, Vector2(x + lw + 54.0, ly), 15, HudPalette.RESONANCE, ctx.font_display)
	if p.skill_points > 0:
		var sp := tr("HUD_SP_BADGE") % p.skill_points
		var bw := text_width(sp, 15, ctx.font_display) + 14.0
		var br := Rect2(W - bw - 12.0, ly - 16.0, bw, 21.0)
		draw_rect(br, HudPalette.SP)
		text(sp, br.position + Vector2(7.0, 16.0), 15, Color.WHITE, ctx.font_display)


func _hp_bar(r: Rect2, cb: SnapshotData.OwnCombat, frac: float, critical: bool) -> void:
	var total := float(cb.max_hp + cb.shield)
	var hp_w := r.size.x * float(cb.max_hp) / maxf(total, 1.0)
	var track := Rect2(r.position, Vector2(hp_w, r.size.y))
	draw_rect(track, Color(0, 0, 0, 0.6))
	var fill_col := HudPalette.DANGER if critical else HudPalette.HP
	draw_rect(Rect2(r.position, Vector2(hp_w * frac, r.size.y)), fill_col)
	var seg := maxi(ctx.tuning.hp_segment, 1)
	var n := cb.max_hp / seg
	for i in range(1, n + 1):
		var sx := r.position.x + hp_w * float(i * seg) / maxf(cb.max_hp, 1.0)
		if sx < track.end.x - 1.0:
			draw_line(Vector2(sx, r.position.y), Vector2(sx, r.end.y), Color(0, 0, 0, 0.75), 2.0)
	if cb.shield > 0:
		var sr := Rect2(Vector2(track.end.x + 2.0, r.position.y), Vector2(r.size.x - hp_w - 2.0, r.size.y))
		draw_rect(sr, Color(1, 1, 1, 0.25))
		draw_rect(sr, HudPalette.SHIELD, false, 1.5)
	if critical:
		draw_rect(track.grow(2.0), HudPalette.DANGER, false, 2.0)
	elif frac <= ctx.tuning.caution_frac:
		draw_rect(track.grow(1.0), HudPalette.WARN, false, 1.0)
	else:
		draw_rect(track, Color(1, 1, 1, 0.25), false, 1.0)
