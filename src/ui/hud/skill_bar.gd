class_name SkillBar
extends Control
## Skill bar (design/ux/hud.md §4.4): four 64 px icons labelled with their
## binds S1 [Q], S2 [E], S3 [C], Ult [G]. Cooldown: dark radial sweep +
## seconds (≤ 3 s shows tenths). Ready: bright. Locked (ult below level 6):
## greyed with a lock and the level gate. Active (wall / stance up): team-rim
## border, cooldown starts when it ends. Greybox: icons are text labels.
## E15 (hud.md §4.4, §11 quick spend): an unlearned skill is greyed with a
## lock; a "+" (violet) marks slots a point can buy now; a learned Boost adds a
## gold "B" badge and a double border; the ultimate shows its rank pips (1–3)
## and next gate (6 / 10 / 14). While Alt is held, a flyout above each icon
## names the node the skill key would buy.
## Reads ClientWorld.combat (replicated) and hero_def.skills; writes nothing.

const BINDS: Array[String] = ["Q", "E", "C", "G"]
const ICON: float = 64.0
const GAP: float = 12.0
const READY := Color(0.9, 0.95, 1.0)
const RIM := Color("#2E86FF")
const LOCK := Color(0.45, 0.45, 0.5)
const ACTIVE := Color("#FFC93C")
const SP := Color("#B07CFF")
const BOOST := Color("#FFD866")
const ULT_GATES: Array[int] = [6, 10, 14]

var client: ClientWorld
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(4.0 * ICON + 3.0 * GAP, ICON + 30.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if client == null or client.hero_def == null:
		return
	var c := client.combat
	var skills := client.hero_def.skills
	var hz := float(client.net.tick_rate_hz) if client.net != null else 30.0
	for i in 4:
		var x := i * (ICON + GAP)
		var r := Rect2(Vector2(x, 0.0), Vector2(ICON, ICON))
		var def: SkillDef = skills[i] if i < skills.size() else null
		var left := c.skill_cd_left[i] if c != null else 0
		var total := c.skill_cd_total[i] if c != null else 0
		var flags := c.skill_flags[i] if c != null else 0
		var locked := def == null or (flags & AbilityRunner.FLAG_LOCKED) != 0
		var active := (flags & (AbilityRunner.FLAG_ACTIVE | AbilityRunner.FLAG_CASTING)) != 0
		draw_rect(r, Color(0.05, 0.06, 0.1, 0.8))
		var label := def.short_label if def != null else "-"
		var fg := LOCK if locked else READY
		if left > 0 and not locked:
			fg = READY.darkened(0.45)
		_text(label, r.position + Vector2(ICON * 0.5, ICON * 0.42), 15, fg)
		if left > 0 and total > 0 and not locked:
			_sweep(r, float(left) / float(total))
			var s := left / hz
			_text("%.1f" % s if s <= 3.0 else str(ceili(s)), r.position + Vector2(ICON * 0.5, ICON * 0.78), 18, Color.WHITE)
		if locked:
			_text("LOCK", r.position + Vector2(ICON * 0.5, ICON * 0.78), 13, LOCK)
			if def != null:
				_text("Lv %d" % def.required_level, r.position + Vector2(ICON * 0.5, -10.0), 13, LOCK)
		var border := RIM if not locked and left == 0 else Color(0.3, 0.3, 0.35)
		if active:
			border = ACTIVE
			_text("ACTIVE", r.position + Vector2(ICON * 0.5, ICON * 0.78), 12, ACTIVE)
		draw_rect(r, border, false, 3.0 if active or (left == 0 and not locked) else 2.0)
		_draw_tree(r, def, flags)
		_text("[%s]" % BINDS[i], r.position + Vector2(ICON * 0.5, ICON + 16.0), 14, Color(0.8, 0.85, 0.95))


## E15 tree state: Boost badge, ult rank pips + next gate, learnable "+",
## quick-spend flyout (Alt held).
func _draw_tree(r: Rect2, def: SkillDef, flags: int) -> void:
	if def == null:
		return
	var boosted := (flags & AbilityRunner.FLAG_BOOSTED) != 0
	var learnable := (flags & AbilityRunner.FLAG_LEARNABLE) != 0
	var rank := (flags & AbilityRunner.RANK_MASK) >> AbilityRunner.RANK_SHIFT
	if boosted:
		draw_rect(r.grow(4.0), BOOST, false, 2.0)
		var b := Rect2(r.position + Vector2(-6.0, -6.0), Vector2(18.0, 18.0))
		draw_rect(b, BOOST)
		_text("B", b.get_center() + Vector2(0.0, -1.0), 13, Color.BLACK)
	if def.ultimate:
		for k in 3:
			var pip := Rect2(r.position + Vector2(ICON * 0.5 - 22.0 + k * 16.0, ICON - 9.0), Vector2(12.0, 5.0))
			draw_rect(pip, BOOST if k < rank else Color(0.25, 0.25, 0.3))
		if rank < 3 and (flags & AbilityRunner.FLAG_LOCKED) == 0:
			_text("Lv %d" % ULT_GATES[rank], r.position + Vector2(ICON * 0.5, -10.0), 12, LOCK)
	if learnable:
		var c := r.position + Vector2(ICON - 4.0, 4.0)
		draw_circle(c, 10.0, SP)
		_text("+", c + Vector2(0.0, -1.0), 18, Color.WHITE)
	var pi := client.player_input
	if pi != null and pi.quick_spend:
		var next := _next_node(def, flags, rank)
		var col := SP if learnable else LOCK
		_text(next, r.position + Vector2(ICON * 0.5, -30.0), 12, col)


func _next_node(def: SkillDef, flags: int, rank: int) -> String:
	if def.ultimate:
		return "MAX" if rank >= 3 else "RANK %d (L%d)" % [rank + 1, ULT_GATES[rank]]
	if (flags & AbilityRunner.FLAG_LOCKED) != 0:
		return "UNLOCK"
	if (flags & AbilityRunner.FLAG_BOOSTED) == 0:
		return "BOOST (L3)"
	return "MAX"


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


func _text(t: String, center: Vector2, size: int, col: Color) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := center + Vector2(-w * 0.5, size * 0.35)
	draw_string_outline(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color.BLACK)
	draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
