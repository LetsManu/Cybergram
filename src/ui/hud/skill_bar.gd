class_name SkillBar
extends HudWidget
## Skill bar, bottom centre (design/ux/hud.md §4.4, §11): four 64 px icons
## labelled with their binds S1 [Q], S2 [E], S3 [C], Ult [G]. Cooldown: dark
## radial sweep + seconds (≤ 3 s shows tenths). Ready: bright with a team rim.
## Locked (unlearned / ult below its gate): greyed with a lock and the level
## gate. Active (wall / stance up): gold border. E15 tree state: a learned
## Boost adds a gold "B" badge and a double border, the ultimate shows its rank
## pips (1–3) and next gate (6 / 10 / 14), a violet "+" marks slots a point can
## buy now, and while Alt is held a flyout names the node the key would buy.
## A fifth, smaller slot shows the Med-Pack consumable [4].
## Reads ClientWorld.combat / progress and hero_def.skills; writes nothing.

const BINDS: Array[String] = ["Q", "E", "C", "G"]
const ICON: float = 64.0
const GAP: float = 12.0
const ACTIVE := Color("#FFC93C")
const BOOST := Color("#FFD866")
const FORK_A_TINT := Color("#5CC8FF")  # W10-T1 cool tint (heroes.md Pillar 4)
const FORK_B_TINT := Color("#FF9440")  # warm tint
const ULT_GATES: Array[int] = [6, 10, 14]
## Width of the four skills plus the consumable slot.
const WIDTH: float = 4.0 * ICON + 3.0 * GAP + 18.0 + 52.0


func _draw() -> void:
	var client := ctx.client
	if client == null or client.hero_def == null:
		return
	var c := client.combat
	var skills := client.hero_def.skills
	var hz := float(client.net.tick_rate_hz) if client.net != null else 30.0
	var y := size.y - ICON - 22.0
	var x0 := (size.x - WIDTH) * 0.5
	var rim := ctx.team_color(ctx.own_team())
	for i in 4:
		var r := Rect2(Vector2(x0 + i * (ICON + GAP), y), Vector2(ICON, ICON))
		var def: SkillDef = skills[i] if i < skills.size() else null
		var left := c.skill_cd_left[i] if c != null else 0
		var total := c.skill_cd_total[i] if c != null else 0
		var flags := c.skill_flags[i] if c != null else 0
		var locked := def == null or (flags & AbilityRunner.FLAG_LOCKED) != 0
		var active := (flags & (AbilityRunner.FLAG_ACTIVE | AbilityRunner.FLAG_CASTING)) != 0
		panel(r, ctx.panel_strong)
		var label := def.short_label if def != null else "-"
		var fg := HudPalette.TEXT_OFF if locked else HudPalette.TEXT
		if left > 0 and not locked:
			fg = HudPalette.TEXT.darkened(0.45)
		text_c(label, r.position + Vector2(ICON * 0.5, ICON * 0.4), 15, fg, ctx.font_display)
		if left > 0 and total > 0 and not locked:
			_sweep(r, float(left) / float(total))
			text_c(HudFormat.cooldown(left / hz), r.position + Vector2(ICON * 0.5, ICON * 0.74), 19, Color.WHITE,
				ctx.font_numbers)
		if locked:
			_lock(r.position + Vector2(ICON * 0.5, ICON * 0.74))
			if def != null:
				text_c(tr("HUD_LEVEL_GATE") % def.required_level, r.position + Vector2(ICON * 0.5, -10.0), 12,
					HudPalette.TEXT_OFF, ctx.font_display)
		var border := rim if not locked and left == 0 else Color(0.3, 0.3, 0.36)
		if active:
			border = ACTIVE
			text_c(tr("HUD_SKILL_ACTIVE"), r.position + Vector2(ICON * 0.5, ICON * 0.74), 12, ACTIVE, ctx.font_display)
		draw_rect(r, border, false, 3.0 if active or (left == 0 and not locked) else 1.5)
		_draw_tree(client, r, def, flags)
		text_c("[%s]" % BINDS[i], r.position + Vector2(ICON * 0.5, ICON + 12.0), 13, HudPalette.TEXT_DIM, ctx.font_display)
	_consumable(client, Rect2(Vector2(x0 + 4.0 * ICON + 3.0 * GAP + 18.0, y + 12.0), Vector2(52.0, ICON - 12.0)))


## Med-Pack slot [4] (hud.md §3.1 bottom centre consumable).
func _consumable(client: ClientWorld, r: Rect2) -> void:
	var p := client.progress
	var count := p.medpacks if p != null else 0
	panel(r, ctx.panel_strong)
	var col := HudPalette.HEAL if count > 0 else HudPalette.TEXT_OFF
	var cc := r.position + Vector2(16.0, r.size.y * 0.5)
	draw_rect(Rect2(cc - Vector2(8, 3), Vector2(16, 6)), col)
	draw_rect(Rect2(cc - Vector2(3, 8), Vector2(6, 16)), col)
	text("x%d" % count, Vector2(r.position.x, cc.y + 6.0), 15, col, ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT,
		r.size.x - 6.0)
	if p != null and (p.flags & SnapshotData.ProgressState.FLAG_HEALING) != 0:
		draw_rect(r, HudPalette.HEAL, false, 2.0)
	text_c("[4]", r.position + Vector2(r.size.x * 0.5, r.size.y + 12.0), 13, HudPalette.TEXT_DIM, ctx.font_display)


func _draw_tree(client: ClientWorld, r: Rect2, def: SkillDef, flags: int) -> void:
	if def == null:
		return
	var boosted := (flags & AbilityRunner.FLAG_BOOSTED) != 0
	var learnable := (flags & AbilityRunner.FLAG_LEARNABLE) != 0
	var rank := (flags & AbilityRunner.RANK_MASK) >> AbilityRunner.RANK_SHIFT
	if boosted:
		draw_rect(r.grow(4.0), BOOST, false, 1.5)
		var b := Rect2(r.position + Vector2(-6.0, -6.0), Vector2(17.0, 17.0))
		draw_rect(b, BOOST)
		text_c("B", b.get_center(), 12, Color.BLACK, ctx.font_numbers)
	if def.ultimate:
		for k in 3:
			var pip := Rect2(r.position + Vector2(ICON * 0.5 - 22.0 + k * 16.0, ICON - 8.0), Vector2(12.0, 4.0))
			draw_rect(pip, BOOST if k < rank else Color(0.25, 0.25, 0.3))
		if rank < 3 and (flags & AbilityRunner.FLAG_LOCKED) == 0:
			text_c(tr("HUD_LEVEL_GATE") % ULT_GATES[rank], r.position + Vector2(ICON * 0.5, -10.0), 12,
				HudPalette.TEXT_OFF, ctx.font_display)
	if learnable:
		var c := r.position + Vector2(ICON - 3.0, 3.0)
		draw_circle(c, 9.0, HudPalette.SP)
		text_c("+", c + Vector2(0.0, -1.0), 16, Color.WHITE, ctx.font_numbers)
	if not def.ultimate:
		_draw_fork(r, def, flags)
	var pi := client.player_input
	if pi != null and pi.quick_spend:
		text_c(_next_node(def, flags, rank), r.position + Vector2(ICON * 0.5, -28.0), 12,
			HudPalette.SP if learnable else HudPalette.TEXT_OFF, ctx.font_display)


## W10-T1: learned Fork / Mastery badges and, when a point can buy the Fork,
## the A/B choice with short descriptions (keys 1 / 2, L1 / R1).
func _draw_fork(r: Rect2, def: SkillDef, flags: int) -> void:
	var fork := AbilityRunner.fork_of_flags(flags)
	if fork > 0:
		var col := FORK_A_TINT if fork == 1 else FORK_B_TINT
		draw_rect(r.grow(2.0), col, false, 2.0)
		var b := Rect2(r.position + Vector2(ICON - 15.0, ICON - 15.0), Vector2(15.0, 15.0))
		draw_rect(b, col)
		text_c(tr("HUD_FORK_BADGE_A") if fork == 1 else tr("HUD_FORK_BADGE_B"), b.get_center(), 12, Color.BLACK,
			ctx.font_numbers)
		if (flags & AbilityRunner.FLAG_MASTERY) != 0:
			var m := Rect2(r.position + Vector2(0.0, ICON - 15.0), Vector2(15.0, 15.0))
			draw_rect(m, HudPalette.SP)
			text_c("M", m.get_center(), 12, Color.BLACK, ctx.font_numbers)
	if not AbilityRunner.fork_offered(flags, def.ultimate):
		return
	var stem := String(def.id).trim_prefix("skill_").to_upper()
	var w := 250.0
	var p := Rect2(Vector2(r.get_center().x - w * 0.5, r.position.y - 92.0), Vector2(w, 62.0))
	panel(p, ctx.panel_strong)
	draw_rect(p, HudPalette.SP, false, 1.5)
	text_c(tr("HUD_FORK_CHOOSE"), p.position + Vector2(w * 0.5, 11.0), 12, HudPalette.SP, ctx.font_display)
	text_c("[%s] %s" % [_key_text(&"fork_a", "1"), tr("HUD_FORK_%s_A" % stem)], p.position + Vector2(w * 0.5, 31.0), 12,
		FORK_A_TINT, ctx.font_display)
	text_c("[%s] %s" % [_key_text(&"fork_b", "2"), tr("HUD_FORK_%s_B" % stem)], p.position + Vector2(w * 0.5, 50.0), 12,
		FORK_B_TINT, ctx.font_display)


func _key_text(action: StringName, fallback: String) -> String:
	if InputMap.has_action(action):
		for e in InputMap.action_get_events(action):
			return e.as_text().trim_suffix(" (Physical)")
	return fallback


func _next_node(def: SkillDef, flags: int, rank: int) -> String:
	if def.ultimate:
		return tr("HUD_NODE_MAX") if rank >= 3 else tr("HUD_NODE_RANK") % [rank + 1, ULT_GATES[rank]]
	if (flags & AbilityRunner.FLAG_LOCKED) != 0:
		return tr("HUD_NODE_UNLOCK")
	if (flags & AbilityRunner.FLAG_BOOSTED) == 0:
		return tr("HUD_NODE_BOOST")
	if AbilityRunner.fork_of_flags(flags) == 0:
		return tr("HUD_NODE_FORK")
	if (flags & AbilityRunner.FLAG_MASTERY) == 0:
		return tr("HUD_NODE_MASTERY")
	return tr("HUD_NODE_MAX")


func _lock(c: Vector2) -> void:
	draw_rect(Rect2(c + Vector2(-6, -3), Vector2(12, 9)), HudPalette.TEXT_OFF)
	draw_arc(c + Vector2(0, -3), 4.0, PI, TAU, 10, HudPalette.TEXT_OFF, 2.0)


## Dark radial sweep covering `frac` of the icon, clockwise from 12 o'clock.
func _sweep(r: Rect2, frac: float) -> void:
	var c := r.get_center()
	var pts := PackedVector2Array([c])
	var steps := maxi(3, ceili(32.0 * frac))
	var half := ICON * 0.5
	for k in steps + 1:
		var a := -PI / 2.0 + TAU * (1.0 - frac) + TAU * frac * k / steps
		var d := Vector2(cos(a), sin(a))
		pts.append(c + d * (half / maxf(absf(d.x), absf(d.y))))
	draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, 0.6))
