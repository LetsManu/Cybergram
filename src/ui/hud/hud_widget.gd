class_name HudWidget
extends Control
## Base for HUD widgets: a Control placed by anchors inside a HudRoot zone,
## redrawn every frame while visible, with the v0.12 premium-dark helpers
## (design/ux/hud-v0.12.md §1, "Shared code"): shadowed text and tracked caps
## (scaled by the HUD text-scale setting), cut-corner polygons, brass key chips,
## hatch, task glyphs shared by the front strip / minimap / scoreboard, the
## radial ink backdrop and idle-fade alpha. No boxes: readability comes from the
## HudRoot scrims and the text shadow.
## Widgets read ctx.client (replicated state) and never write gameplay state.

## Text shadow: 1 px drop (black 75%) plus a soft ink glow (outline).
const SHADOW := Color(0.0, 0.0, 0.0, 0.75)
const GLOW := Color(0.031, 0.047, 0.063, 0.38)

static var _radial: GradientTexture2D

var ctx: HudContext


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(c: HudContext) -> void:
	ctx = c


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## `size` design px scaled by the HUD text-scale setting.
func ts(px: int) -> int:
	var k := ctx.settings.text_scale if ctx != null and ctx.settings != null else 1.0
	return maxi(1, roundi(px * k))


## Alpha multiplier of an idle-fading part whose idle opacity is `idle_alpha`.
func idle_a(idle_alpha: float) -> float:
	return lerpf(1.0, idle_alpha, ctx.idle_k) if ctx != null else 1.0


## Text with the HUD shadow. `pos` is the baseline-left point; `width` > 0 with
## `align` aligns inside [pos.x, pos.x + width]. `size` is scaled by ts().
func text(t: String, pos: Vector2, size: int, col: Color, font: Font = null,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	_shadowed(font if font != null else ctx.font_body, t, pos, ts(size), col, align, width)


## Caps label in Chakra Petch with `em` letter tracking (the mockup's caps
## roles: 15/16 px at .22em). Upper-cases `t`.
func caps(t: String, pos: Vector2, size: int, col: Color, em: float = 0.22,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var px := ts(size)
	_shadowed(ctx.caps_font(px, em), t.to_upper(), pos, px, col, align, width)


func caps_width(t: String, size: int, em: float = 0.22) -> float:
	var px := ts(size)
	return ctx.caps_font(px, em).get_string_size(t.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


func _shadowed(f: Font, t: String, pos: Vector2, px: int, col: Color, align: HorizontalAlignment, width: float) -> void:
	draw_string_outline(f, pos, t, align, width, px, 6, Color(GLOW, GLOW.a * col.a))
	draw_string(f, pos + Vector2(0.0, 1.0), t, align, width, px, Color(SHADOW, SHADOW.a * col.a))
	draw_string(f, pos, t, align, width, px, col)


## Text centred on `center` (both axes, approximately).
func text_c(t: String, center: Vector2, size: int, col: Color, font: Font = null) -> void:
	var f := font if font != null else ctx.font_body
	var px := ts(size)
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	_shadowed(f, t, center + Vector2(-w * 0.5, px * 0.36), px, col, HORIZONTAL_ALIGNMENT_LEFT, -1.0)


## Caps text centred on `center`.
func caps_c(t: String, center: Vector2, size: int, col: Color, em: float = 0.22) -> void:
	var px := ts(size)
	var f := ctx.caps_font(px, em)
	var w := f.get_string_size(t.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	_shadowed(f, t.to_upper(), center + Vector2(-w * 0.5, px * 0.36), px, col, HORIZONTAL_ALIGNMENT_LEFT, -1.0)


func text_width(t: String, size: int, font: Font = null) -> float:
	var f := font if font != null else ctx.font_body
	return f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, ts(size)).x


## Legacy boxed panel (v0.12 has no boxes; kept for debug widgets).
func panel(r: Rect2, style: StyleBox = null) -> void:
	draw_style_box(style if style != null else ctx.panel, r)


## Rect with the v0.12 chamfer: top-left and bottom-right corners cut by `c`
## (CSS --cut). `all4` cuts every corner.
static func cut_poly(r: Rect2, c: float, all4: bool = false) -> PackedVector2Array:
	var p := r.position
	var e := r.end
	if all4:
		return PackedVector2Array([Vector2(p.x + c, p.y), Vector2(e.x - c, p.y), Vector2(e.x, p.y + c), Vector2(e.x, e.y - c),
			Vector2(e.x - c, e.y), Vector2(p.x + c, e.y), Vector2(p.x, e.y - c), Vector2(p.x, p.y + c)])
	return PackedVector2Array([Vector2(p.x + c, p.y), Vector2(e.x, p.y), Vector2(e.x, e.y - c), Vector2(e.x - c, e.y),
		Vector2(p.x, e.y), Vector2(p.x, p.y + c)])


func cut_fill(r: Rect2, c: float, col: Color, all4: bool = false) -> void:
	draw_colored_polygon(cut_poly(r, c, all4), col)


func cut_line(r: Rect2, c: float, col: Color, w: float = 1.0, all4: bool = false) -> void:
	var pts := cut_poly(r.grow(-w * 0.5), c, all4)
	pts.append(pts[0])
	draw_polyline(pts, col, w)


## Brass key chip (hud-v0.12.md §1): 1 px brass-dim frame on ink 45%, mono
## brass-hi label, centred at `c`; `h` is the chip height in design px.
## Returns the chip rect.
func key_chip(c: Vector2, label: String, h: float = 30.0, a: float = 1.0) -> Rect2:
	var px := ts(roundi(h * 0.55))
	var w := maxf(h, ctx.font_mono.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + h * 0.4)
	var r := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
	draw_rect(r, Color(HudPalette.INK_DEEP, 0.45 * a))
	draw_rect(r.grow(-0.5), Color(HudPalette.BRASS_DIM, a), false, 1.0)
	draw_string(ctx.font_mono, Vector2(r.position.x, c.y + px * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, w, px,
		Color(HudPalette.BRASS_HI, a))
	return r


## Brass "+N SP"-style action chip: solid brass, cut corners, ink caps label,
## left edge at `pos.x`, vertically centred on `pos.y`. Returns its width.
func brass_chip(pos: Vector2, label: String, size: int = 16, a: float = 1.0) -> float:
	var px := ts(size)
	var f := ctx.caps_font(px, 0.16)
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + px * 1.2
	var h := px * 1.8
	var r := Rect2(Vector2(pos.x, pos.y - h * 0.5), Vector2(w, h))
	cut_fill(r, 5.0, Color(HudPalette.BRASS, a))
	draw_string(f, Vector2(r.position.x + px * 0.6, pos.y + px * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, px,
		Color(HudPalette.INK, a))
	return w


## Soft vertical ink scrim over `r`: `top_a` alpha at the top edge, `bottom_a`
## at the bottom (one polygon).
func scrim(r: Rect2, top_a: float, bottom_a: float) -> void:
	var t := Color(HudPalette.INK_DEEP, top_a)
	var b := Color(HudPalette.INK_DEEP, bottom_a)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([t, t, b, b]))


## Horizontal ink gradient (kill feed rows, toasts): `left_a` to `right_a`.
func scrim_h(r: Rect2, left_a: float, right_a: float) -> void:
	var l := Color(HudPalette.INK_DEEP, left_a)
	var rr := Color(HudPalette.INK_DEEP, right_a)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([l, rr, rr, l]))


## Radial ink backdrop (minimap, ring warning, top-centre): ink at `a` in the
## middle fading to 0 at the rect edge. One textured quad.
func radial_backdrop(r: Rect2, a: float) -> void:
	if _radial == null:
		var g := Gradient.new()
		g.set_color(0, Color(HudPalette.INK_DEEP, 1.0))
		g.set_color(1, Color(HudPalette.INK_DEEP, 0.0))
		g.add_point(0.6, Color(HudPalette.INK_DEEP, 0.6))
		_radial = GradientTexture2D.new()
		_radial.gradient = g
		_radial.fill = GradientTexture2D.FILL_RADIAL
		_radial.fill_from = Vector2(0.5, 0.5)
		_radial.fill_to = Vector2(1.0, 0.5)
		_radial.width = 64
		_radial.height = 64
	draw_texture_rect(_radial, r, false, Color(1, 1, 1, a))


## Brass corner ticks (minimap frame, clock plate): L-shapes of `len` at the
## four corners of `r` (or only the top two).
func corner_ticks(r: Rect2, len: float, col: Color, top_only: bool = false) -> void:
	var p := r.position
	var e := r.end
	draw_polyline(PackedVector2Array([Vector2(p.x, p.y + len), p, Vector2(p.x + len, p.y)]), col, 1.0)
	draw_polyline(PackedVector2Array([Vector2(e.x - len, p.y), Vector2(e.x, p.y), Vector2(e.x, p.y + len)]), col, 1.0)
	if top_only:
		return
	draw_polyline(PackedVector2Array([Vector2(p.x, e.y - len), Vector2(p.x, e.y), Vector2(p.x + len, e.y)]), col, 1.0)
	draw_polyline(PackedVector2Array([Vector2(e.x - len, e.y), e, Vector2(e.x, e.y - len)]), col, 1.0)


## Hero face in a circle of radius `r` at `c` (UiKit portrait + face crop),
## on a raised-ink disc; returns false when the hero has no portrait.
func face_circle(c: Vector2, r: float, hero_id: StringName, a: float = 1.0) -> bool:
	draw_circle(c, r, Color("#111A20", a))
	var stem := String(hero_id).trim_prefix("hero_")
	var tex := UiKit.portrait_texture(stem)
	if tex == null:
		return false
	var uv := UiKit.portrait_face(stem)
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	pts.resize(28)
	uvs.resize(28)
	for k in 28:
		var d := Vector2(cos(TAU * k / 28.0), sin(TAU * k / 28.0))
		pts[k] = c + d * r
		uvs[k] = uv.position + (d * 0.5 + Vector2(0.5, 0.5)) * uv.size
	draw_colored_polygon(pts, Color(1, 1, 1, a), uvs, tex)
	return true


## Ally chevron (pointing up) — art bible §4.4 nameplate glyph.
func chevron(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(-s, s * 0.6), c + Vector2(0.0, -s * 0.6), c + Vector2(s, s * 0.6),
		c + Vector2(0.0, s * 0.15)])
	draw_colored_polygon(pts, col)


## Hollow ally chevron (empty squad slot, dead ally pip).
func chevron_line(c: Vector2, s: float, col: Color, w: float = 1.0) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(-s, s * 0.6), c + Vector2(0.0, -s * 0.6), c + Vector2(s, s * 0.6),
		c + Vector2(0.0, s * 0.15), c + Vector2(-s, s * 0.6)]), col, w, true)


## Enemy diamond — art bible §4.4 nameplate glyph.
func diamond(c: Vector2, s: float, col: Color, filled: bool = true) -> void:
	var pts := PackedVector2Array([c + Vector2(0.0, -s), c + Vector2(s, 0.0), c + Vector2(0.0, s), c + Vector2(-s, 0.0)])
	if filled:
		draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		draw_polyline(pts, col, 1.5, true)


## Ally chevron or enemy diamond for `team` relative to the own team.
func team_glyph(c: Vector2, s: float, team: int) -> void:
	if team < 0:
		return
	if team == ctx.own_team():
		chevron(c, s, ctx.team_color(team))
	else:
		diamond(c, s * 0.8, ctx.team_color(team))


## Horizontal bar with a faint ivory track; `frac` of it filled.
func bar(r: Rect2, frac: float, col: Color, track: Color = Color(HudPalette.IVORY, 0.14)) -> void:
	draw_rect(r, track)
	if frac > 0.0:
		draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)


## Diagonal hatching inside `r` (enemy ownership pattern, art bible §4.4).
func hatch(r: Rect2, col: Color, step: float = 6.0, width: float = 2.0) -> void:
	var x := r.position.x - r.size.y
	while x < r.end.x:
		var a := Vector2(x, r.end.y)
		var b := Vector2(x + r.size.y, r.position.y)
		# clip to r
		if a.x < r.position.x:
			a = Vector2(r.position.x, r.end.y - (r.position.x - a.x))
		if b.x > r.end.x:
			b = Vector2(r.end.x, r.position.y + (b.x - r.end.x))
		if a.x <= b.x:
			draw_line(a, b, col, width)
		x += step


## Ownership of a hardpoint relative to `own` team: 0 own, 1 enemy, 2 neutral.
static func ownership(owner: int, own: int) -> int:
	if owner < 0 or owner > 1:
		return 2
	return 0 if owner == own else 1


## Task shape (hud-v0.12.md §2a): Hold = circle, Plant = square, Breach =
## triangle, all fitting a box of side `s` centred at `c`.
static func task_shape(c: Vector2, s: float, task: int) -> PackedVector2Array:
	var r := s * 0.5
	match task:
		HardpointDef.TaskKind.PLANT:
			var q := r * 0.86
			return PackedVector2Array([c + Vector2(-q, -q), c + Vector2(q, -q), c + Vector2(q, q), c + Vector2(-q, q)])
		HardpointDef.TaskKind.BREACH:
			return PackedVector2Array([c + Vector2(0.0, -r * 1.05), c + Vector2(r * 1.08, r * 0.8), c + Vector2(-r * 1.08, r * 0.8)])
		_:
			var pts := PackedVector2Array()
			pts.resize(16)
			for k in 16:
				var a := TAU * k / 16.0
				pts[k] = c + Vector2(cos(a), sin(a)) * r
			return pts


## Hardpoint chip shared by the front strip, minimap and scoreboard: shape =
## task; own = solid team colour with an ink inner mark, enemy = outline +
## diagonal hatch, neutral = ivory hollow. `halo` draws the ink disc behind it.
## `a` multiplies the whole chip (Overtime "others dimmed").
func task_chip(c: Vector2, s: float, task: int, own_state: int, team_col: Color, halo: bool = true, a: float = 1.0) -> void:
	if halo:
		draw_circle(c, s * 0.5 + 3.5, Color(HudPalette.INK_DEEP, 0.85 * a))
	var pts := task_shape(c, s if own_state == 0 else s - 1.0, task)
	match own_state:
		0:
			draw_colored_polygon(pts, Color(team_col, a))
			draw_colored_polygon(task_shape(c + (Vector2(0.0, s * 0.08) if task == HardpointDef.TaskKind.BREACH else Vector2.ZERO),
				s * (0.36 if task == HardpointDef.TaskKind.BREACH else 0.34), task), Color(HudPalette.INK, a))
		1:
			var box := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
			var inset := 0.0 if task == HardpointDef.TaskKind.PLANT else s * 0.18
			draw_colored_polygon(pts, Color(team_col, 0.18 * a))
			hatch(box.grow(-inset), Color(team_col, 0.9 * a), maxf(3.0, s * 0.28), maxf(1.0, s * 0.11))
			pts.append(pts[0])
			draw_polyline(pts, Color(team_col, a), maxf(1.2, s * 0.09), true)
		_:
			pts.append(pts[0])
			draw_polyline(pts, Color(HudPalette.IVORY, 0.8 * a), maxf(1.2, s * 0.09), true)


## Contested / capturing ring around a chip: a thin ivory ring at `ring_a` plus
## a 2 px progress arc in `col` clockwise from 12 o'clock.
func capture_ring(c: Vector2, s: float, progress: float, col: Color, ring_a: float) -> void:
	var r := s * 0.5 + 3.5
	draw_arc(c, r, 0.0, TAU, 24, Color(HudPalette.IVORY, 0.45 * ring_a), 1.0, true)
	if progress > 0.0:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0), 24, col, 2.0, true)


## Small padlock (locked chips, locked abilities): body centred at `c`.
func padlock(c: Vector2, s: float, col: Color) -> void:
	draw_rect(Rect2(c + Vector2(-s * 0.5, -s * 0.1), Vector2(s, s * 0.72)), col, false, maxf(1.0, s * 0.11))
	draw_arc(c + Vector2(0.0, -s * 0.1), s * 0.3, PI, TAU, 10, col, maxf(1.0, s * 0.11), true)


## Pulse factor 1 → `low` → 1 over `period` s, or 1 when motion is reduced /
## effects are 0 (hud-v0.12.md §3).
func pulse(t: float, period: float, low: float = 0.4) -> float:
	if UiKit.reduce_motion() or GameSettings.shared().comfort_fx_intensity <= 0.001:
		return 1.0
	return lerpf(low, 1.0, 0.5 + 0.5 * cos(t * TAU / period))
