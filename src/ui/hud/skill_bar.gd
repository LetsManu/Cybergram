class_name SkillBar
extends HudWidget
## Skill bar, bottom centre (design/ux/hud.md §4.4, §11; v0.12 look, design/ux/
## hud-v0.12.md §2): four 87 px cut-corner slots, 18 px apart: ink 66% inside a
## 1 px brass 55% rim (the ult rim is a brass-hi → brass gradient, no shimmer),
## a line icon per skill (SkillIcons), brass rank-pip diamonds above and a brass
## key chip below showing the current binding (gamepad glyph while a pad is in
## use). Cooldown: a conic brass sweep on the rim plus an ink sweep inside and
## the seconds in 27 numerals (tenths ≤ 3 s). Locked: icon at 22%, padlock, the
## level gate "LV n" in caps above. Active (wall / stance up): teal rim. A brass
## "+" corner chip marks a slot a point can buy now. E15 tree: Boost = brass "B"
## chip, Fork A / B chip in its tint, Mastery "M"; while Alt is held a line
## names the node the key would buy; the Fork choice shows a flyout. The
## Med-Pack slot (66 px, ×N, key 4) follows a hairline divider.
## Idle: key chips and pips fade to 55%.
## Reads ClientWorld.combat / progress and hero_def.skills; writes nothing.

const BINDS: Array[String] = ["Q", "E", "C", "G"]
const ACTIONS: Array[StringName] = [&"skill_1", &"skill_2", &"skill_3", &"skill_4"]
const ICON: float = 87.0
const GAP: float = 18.0
const MED: float = 66.0
const CUT: float = 12.0
const KEY_H: float = 30.0
const FORK_A_TINT := Color("#5CC8FF")  # W10-T1 cool tint (heroes.md Pillar 4)
const FORK_B_TINT := Color("#FF9440")  # warm tint
const ULT_GATES: Array[int] = [6, 10, 14]
## Width of the four skills plus the divider and the consumable slot.
const WIDTH: float = 4.0 * ICON + 3.0 * GAP + 30.0 + MED


func _draw() -> void:
	var client := ctx.client
	if client == null or client.hero_def == null:
		return
	var c := client.combat
	var skills := client.hero_def.skills
	var hz := float(client.net.tick_rate_hz) if client.net != null else 30.0
	var y := size.y - KEY_H - 9.0 - ICON
	var x0 := (size.x - WIDTH) * 0.5
	var chrome_a := idle_a(0.55)
	for i in 4:
		var r := Rect2(Vector2(x0 + i * (ICON + GAP), y), Vector2(ICON, ICON))
		var def: SkillDef = skills[i] if i < skills.size() else null
		var left := c.skill_cd_left[i] if c != null else 0
		var total := c.skill_cd_total[i] if c != null else 0
		var flags := c.skill_flags[i] if c != null else 0
		var locked := def == null or (flags & AbilityRunner.FLAG_LOCKED) != 0
		var active := (flags & (AbilityRunner.FLAG_ACTIVE | AbilityRunner.FLAG_CASTING)) != 0
		var cooling := left > 0 and total > 0 and not locked
		var ult := def != null and def.ultimate
		_slot(r, ult, locked, active, 1.0 - float(left) / float(total) if cooling else -1.0)
		var label := def.short_label if def != null else "-"
		var icol := Color(HudPalette.IVORY, 0.22 if locked else (0.35 if cooling else 1.0))
		if not SkillIcons.draw(self, label, r.get_center(), 45.0, icol):
			caps_c(label, r.get_center(), 16, icol, 0.12)
		if cooling:
			text_c(HudFormat.cooldown(left / hz), r.get_center(), 27, HudPalette.IVORY, ctx.font_numbers)
		if locked:
			padlock(r.get_center() + Vector2(0.0, 2.0), 16.0, HudPalette.IVORY)
			if def != null:
				caps_c(tr("HUD_LEVEL_GATE") % def.required_level, Vector2(r.get_center().x, y - 12.0), 15,
					HudPalette.MUTED, 0.14)
		else:
			_pips(def, flags, Vector2(r.get_center().x, y - 12.0), chrome_a)
		_draw_tree(client, r, def, flags)
		key_chip(Vector2(r.get_center().x, r.end.y + 9.0 + KEY_H * 0.5), ctx.key_label(ACTIONS[i], BINDS[i]), KEY_H, chrome_a)
	var dx := x0 + 4.0 * ICON + 3.0 * GAP + 15.0
	draw_rect(Rect2(dx, y + ICON - 66.0, 1.0, 60.0), HudPalette.HAIR_STRONG)
	_consumable(client, Rect2(Vector2(dx + 15.0, y + ICON - MED), Vector2(MED, MED)), chrome_a)


## Slot frame: rim (brass 55%, ult gradient, teal when active, faint when
## locked / cooling) and the ink well; `elapsed` ≥ 0 draws the cooldown sweeps.
func _slot(r: Rect2, ult: bool, locked: bool, active: bool, elapsed: float) -> void:
	var outer := cut_poly(r, CUT)
	var inner := cut_poly(r.grow(-1.5), CUT - 0.6)
	if active:
		draw_colored_polygon(outer, HudPalette.TEAL)
	elif locked:
		draw_colored_polygon(outer, Color(HudPalette.IVORY, 0.14))
	elif elapsed >= 0.0:
		var fan := _fan(r, elapsed)
		_split(outer, fan, Color(HudPalette.BRASS, 0.75), Color(HudPalette.IVORY, 0.14))
		_split(inner, fan, Color(HudPalette.INK_DEEP, 0.25), Color(HudPalette.INK_DEEP, 0.78))
		return
	elif ult:
		var hi := HudPalette.BRASS_HI
		var lo := HudPalette.BRASS
		var cols := PackedColorArray()
		for p in outer:
			cols.append(hi.lerp(lo, (p.y - r.position.y) / r.size.y))
		draw_polygon(outer, cols)
	else:
		draw_colored_polygon(outer, Color(HudPalette.BRASS, 0.55))
	draw_colored_polygon(inner, Color(HudPalette.INK_DEEP, 0.66))


## Fan covering `frac` of a turn clockwise from 12 o'clock around `r`'s centre.
func _fan(r: Rect2, frac: float) -> PackedVector2Array:
	var c := r.get_center()
	var fan := PackedVector2Array([c])
	var steps := maxi(3, ceili(32.0 * frac))
	for k in steps + 1:
		var a := -PI / 2.0 + TAU * clampf(frac, 0.0, 1.0) * k / steps
		fan.append(c + Vector2(cos(a), sin(a)) * r.size.x)
	return fan


## Conic split of `poly`: the part inside `fan` in `in_col`, the rest in `out_col`.
func _split(poly: PackedVector2Array, fan: PackedVector2Array, in_col: Color, out_col: Color) -> void:
	for piece in Geometry2D.intersect_polygons(poly, fan):
		draw_colored_polygon(piece, in_col)
	for piece in Geometry2D.clip_polygons(poly, fan):
		draw_colored_polygon(piece, out_col)


## Rank pips: ult = rank of 3; basics = unlocked / boosted / Fork chosen.
func _pips(def: SkillDef, flags: int, c: Vector2, a: float) -> void:
	if def == null:
		return
	var on := 0
	if def.ultimate:
		on = (flags & AbilityRunner.RANK_MASK) >> AbilityRunner.RANK_SHIFT
	else:
		on = 1 + int((flags & AbilityRunner.FLAG_BOOSTED) != 0) + int(AbilityRunner.fork_of_flags(flags) > 0)
	for k in 3:
		var pc := c + Vector2((k - 1) * 13.5, 0.0)
		if k < on:
			diamond(pc, 4.5, Color(HudPalette.BRASS, a))
		else:
			draw_polyline(PackedVector2Array([pc + Vector2(0, -4.5), pc + Vector2(4.5, 0), pc + Vector2(0, 4.5),
				pc + Vector2(-4.5, 0), pc + Vector2(0, -4.5)]), Color(HudPalette.BRASS_DIM, a), 1.2, true)


## Med-Pack slot [4] (hud.md §3.1 bottom centre consumable).
func _consumable(client: ClientWorld, r: Rect2, chrome_a: float) -> void:
	var p := client.progress
	var count := p.medpacks if p != null else 0
	var healing := p != null and (p.flags & SnapshotData.ProgressState.FLAG_HEALING) != 0
	cut_fill(r, 9.0, HudPalette.TEAL if healing else Color(HudPalette.IVORY, 0.28))
	cut_fill(r.grow(-1.5), 8.4, Color(HudPalette.INK_DEEP, 0.66))
	var a := 1.0 if count > 0 else 0.35
	if not SkillIcons.draw(self, "MED", r.get_center() + Vector2(-2.0, -2.0), 33.0, Color(HudPalette.IVORY, a)):
		caps_c("+", r.get_center(), 24, Color(HudPalette.IVORY, a))
	text("×%d" % count, Vector2(r.position.x, r.end.y - 6.0), 16, Color(HudPalette.IVORY, a), ctx.font_numbers,
		HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6.0)
	key_chip(Vector2(r.get_center().x, r.end.y + 9.0 + KEY_H * 0.5), ctx.key_label(&"use_medpack", "4"), KEY_H, chrome_a)


func _draw_tree(client: ClientWorld, r: Rect2, def: SkillDef, flags: int) -> void:
	if def == null:
		return
	var boosted := (flags & AbilityRunner.FLAG_BOOSTED) != 0
	var learnable := (flags & AbilityRunner.FLAG_LEARNABLE) != 0
	var rank := (flags & AbilityRunner.RANK_MASK) >> AbilityRunner.RANK_SHIFT
	if boosted:
		_badge(Rect2(r.position + Vector2(-4.0, -4.0), Vector2(21.0, 21.0)), "B", HudPalette.BRASS)
	if learnable:
		_badge(Rect2(Vector2(r.end.x - 15.0, r.position.y - 6.0), Vector2(21.0, 21.0)), "+", HudPalette.BRASS)
	if not def.ultimate:
		_draw_fork(r, def, flags)
	var pi := client.player_input
	if pi != null and pi.quick_spend:
		caps_c(_next_node(def, flags, rank), Vector2(r.get_center().x, r.position.y - 36.0), 14,
			HudPalette.BRASS_HI if learnable else HudPalette.DIM, 0.1)


## Small cut-corner chip with an ink letter.
func _badge(b: Rect2, t: String, col: Color) -> void:
	cut_fill(b, 5.0, col)
	draw_string(ctx.font_numbers, Vector2(b.position.x, b.get_center().y + ts(14) * 0.36), t, HORIZONTAL_ALIGNMENT_CENTER,
		b.size.x, ts(14), HudPalette.INK)


## W10-T1: learned Fork / Mastery badges and, when a point can buy the Fork,
## the A/B choice with short descriptions (keys 1 / 2, L1 / R1).
func _draw_fork(r: Rect2, def: SkillDef, flags: int) -> void:
	var fork := AbilityRunner.fork_of_flags(flags)
	if fork > 0:
		var col := FORK_A_TINT if fork == 1 else FORK_B_TINT
		_badge(Rect2(r.end - Vector2(19.0, 19.0), Vector2(21.0, 21.0)), tr("HUD_FORK_BADGE_A") if fork == 1 else tr("HUD_FORK_BADGE_B"), col)
		if (flags & AbilityRunner.FLAG_MASTERY) != 0:
			_badge(Rect2(Vector2(r.position.x - 2.0, r.end.y - 19.0), Vector2(21.0, 21.0)), "M", HudPalette.BRASS_HI)
	if not AbilityRunner.fork_offered(flags, def.ultimate):
		return
	var stem := String(def.id).trim_prefix("skill_").to_upper()
	var w := 360.0
	# Centred on the whole bar (not the slot) so it never runs into the squad strip.
	var p := Rect2(Vector2(size.x * 0.5 - w * 0.5, r.position.y - 132.0), Vector2(w, 92.0))
	cut_fill(p, 10.0, Color(HudPalette.INK, 0.86))
	cut_line(p, 10.0, HudPalette.BRASS, 1.0)
	caps_c(tr("HUD_FORK_CHOOSE"), p.position + Vector2(w * 0.5, 18.0), 15, HudPalette.BRASS_HI, 0.18)
	text_c("[%s] %s" % [ctx.key_label(&"fork_a", "1"), tr("HUD_FORK_%s_A" % stem)], p.position + Vector2(w * 0.5, 46.0), 17,
		FORK_A_TINT)
	text_c("[%s] %s" % [ctx.key_label(&"fork_b", "2"), tr("HUD_FORK_%s_B" % stem)], p.position + Vector2(w * 0.5, 72.0), 17,
		FORK_B_TINT)


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
