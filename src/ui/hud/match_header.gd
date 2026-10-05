class_name MatchHeader
extends HudWidget
## Match header, top centre (design/ux/hud.md §4.8; v0.12 variant D, design/ux/
## hud-v0.12.md §2a): a chamfered ink clock plate (clock, phase, next-phase
## line; a 3 px top rule in the phase colour and brass corner ticks) between two
## framed Uplink bars. Own team on the left (chevron, YOU), enemy on the right
## (diamond). Each bar: brass-dim frame chamfered at its outer end, ink well,
## team fill with a top sheen anchored at the outer end, a fading ivory "recent
## loss" region at the inner end (so a bar never seems to heal), 3 px ink gaps
## and brass notches at the 75 / 50 / 25% thresholds. EXPOSED: white hatch over
## the bar plus a cracked-shield tag, pulsing at 1.8 s (static with reduce
## motion / effects 0). Phases: Skirmish (brass-hi), Capture Overtime (warn,
## "OT m:ss"), Sudden Death (damage colour, no respawns).

const TEAM_KEYS: Array[String] = ["HUD_TEAM_0", "HUD_TEAM_1"]
const PHASE_KEYS: Array[String] = ["HUD_PHASE_LOAD", "HUD_PHASE_DEPLOY", "HUD_PHASE_SKIRMISH", "HUD_PHASE_SURGE_I",
	"HUD_PHASE_SURGE_II", "HUD_PHASE_DROUGHT", "HUD_PHASE_TIME_OUT", "HUD_PHASE_END", "HUD_PHASE_SUDDEN_DEATH"]
## Widget height (design px): plate top offset + plate.
const H: float = 126.0
const PLATE_W: float = 240.0
const PLATE_H: float = 114.0
const PLATE_Y: float = 8.0
const BLOCK_W: float = 340.0
const BLOCK_GAP: float = 21.0
const BAR_H: float = 21.0
const CHAMFER: float = 10.0
## Uplink damage thresholds marked on each bar.
const THRESHOLDS: Array[float] = [0.75, 0.5, 0.25]

enum Phase { NORMAL, OVERTIME, SUDDEN_DEATH }

var _t: float = 0.0
## Per team: the eased "recent loss" edge (fraction), trailing the integrity.
var _trail: Array[float] = [-1.0, -1.0]


func _process(delta: float) -> void:
	_t += delta
	for i in 2:
		var u := ctx.client.uplink_state(i) if ctx.client != null and ctx.client.match_state != null else null
		if u != null:
			var f := clampf(u.integrity / maxf(u.max_integrity, 1.0), 0.0, 1.0)
			_trail[i] = f if _trail[i] < f or UiKit.reduce_motion() else move_toward(_trail[i], f, delta * 0.06)
	super(delta)


## Phase treatment for the match state (Sudden Death, Capture Overtime or normal).
static func phase_of(m: SnapshotData.MatchState, hardpoints: Array) -> int:
	if m == null:
		return Phase.NORMAL
	if m.phase == MatchRules.Phase.SUDDEN_DEATH:
		return Phase.SUDDEN_DEATH
	if m.phase == MatchRules.Phase.TIME_OUT:
		return Phase.OVERTIME
	for st in hardpoints:
		if st.overtime:
			return Phase.OVERTIME
	return Phase.NORMAL


## Colour of the phase label / plate rule.
func phase_color(ph: int) -> Color:
	match ph:
		Phase.OVERTIME:
			return HudPalette.WARN_UI
		Phase.SUDDEN_DEATH:
			return HudPalette.damage_color(ctx.settings.colorblind)
	return HudPalette.BRASS_HI


func _draw() -> void:
	var c := ctx.client
	if c == null or c.match_state == null:
		return
	var m := c.match_state
	var team := ctx.own_team()
	var ph := phase_of(m, c.hardpoints)
	var cx := size.x * 0.5
	radial_backdrop(Rect2(cx - 480.0, -60.0, 960.0, 300.0), 0.55)
	var bx := cx - PLATE_W * 0.5 - BLOCK_GAP - BLOCK_W
	_uplink(c.uplink_state(team), team, bx, false)
	_uplink(c.uplink_state(1 - team), 1 - team, cx + PLATE_W * 0.5 + BLOCK_GAP, true)
	_plate(Rect2(cx - PLATE_W * 0.5, PLATE_Y, PLATE_W, PLATE_H), m, ph, c)


func _plate(r: Rect2, m: SnapshotData.MatchState, ph: int, c: ClientWorld) -> void:
	var ch := 21.0
	var p := r.position
	var e := r.end
	var top := Color(HudPalette.INK, 0.86)
	var bot := Color(HudPalette.INK, 0.66)
	draw_polygon(PackedVector2Array([p, Vector2(e.x, p.y), Vector2(e.x, e.y - ch), Vector2(e.x - ch, e.y),
		Vector2(p.x + ch, e.y), Vector2(p.x, e.y - ch)]), PackedColorArray([top, top, bot, bot, bot, bot]))
	var pc := phase_color(ph)
	draw_rect(Rect2(p, Vector2(r.size.x, 3.0)), pc)
	corner_ticks(Rect2(p + Vector2(9.0, 9.0), r.size - Vector2(18.0, 18.0)), 9.0, Color(HudPalette.BRASS, 0.8), true)
	var clock := HudFormat.clock(m.time_s)
	var clock_col := HudPalette.IVORY
	var label: String = tr(PHASE_KEYS[m.phase]) if m.phase < PHASE_KEYS.size() else "?"
	var sub := _next_text(m)
	if ph == Phase.OVERTIME:
		clock = tr("HUD_OT_CLOCK") % HudFormat.clock(maxf(m.next_phase_s - m.time_s, 0.0) if m.next_phase_s >= 0.0 else 0.0)
		clock_col = HudPalette.WARN_UI
		label = tr("HUD_PHASE_CAPTURE_OVERTIME")
		var n := 0
		for st in c.hardpoints:
			n += int(st.overtime)
		sub = tr("HUD_OT_TASKS") % n
	elif ph == Phase.SUDDEN_DEATH:
		sub = tr("HUD_SD_NO_RESPAWNS")
	text(clock, Vector2(r.position.x, p.y + 56.0), 48, clock_col, ctx.font_numbers, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	caps(label, Vector2(r.position.x, p.y + 81.0), 15, pc, 0.26, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if sub != "":
		text(sub.to_upper(), Vector2(r.position.x, p.y + 101.0), 15, HudPalette.MUTED, ctx.font_mono,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _next_text(m: SnapshotData.MatchState) -> String:
	if m.next_phase_s < 0.0 or m.phase == MatchRules.Phase.END \
			or m.phase == MatchRules.Phase.SUDDEN_DEATH:  # next_phase_s carries the SD draw cap
		return ""
	var left := HudFormat.clock(ceilf(m.next_phase_s - m.time_s))
	if m.phase == MatchRules.Phase.DEPLOY:
		return tr("HUD_MIDS_UNLOCK") % left
	var nxt := m.phase + 1
	if nxt >= MatchRules.Phase.SURGE_I and nxt <= MatchRules.Phase.DROUGHT:
		return tr("HUD_NEXT_PHASE_NAMED") % [tr(PHASE_KEYS[nxt]), left]
	return tr("HUD_NEXT_PHASE") % left


func _uplink(u: SnapshotData.UplinkState, team: int, x: float, right: bool) -> void:
	if u == null:
		return
	var own := team == ctx.own_team()
	var frac := clampf(u.integrity / maxf(u.max_integrity, 1.0), 0.0, 1.0)
	var col := ctx.team_color(team)
	var y := PLATE_Y + 6.0
	var mid := y + 14.0
	# Header: glyph, name, tag, % (mirrored for the enemy side).
	var name := tr(TEAM_KEYS[team])
	var gx := x + BLOCK_W - 8.0 if right else x + 8.0
	if own:
		chevron(Vector2(gx, mid), 8.0, col)
	else:
		diamond(Vector2(gx, mid), 7.0, col)
	var nw := caps_width(name, 18, 0.24)
	var nx := gx - 14.0 - nw if right else gx + 14.0
	caps(name, Vector2(nx, mid + 6.0), 18, col, 0.24)
	var tag_x := nx - 10.0 if right else nx + nw + 10.0
	if own:
		var yt := tr("HUD_YOU_TAG")
		var tw := text_width(yt, 13, ctx.font_mono)
		text(yt, Vector2(tag_x - tw if right else tag_x, mid + 5.0), 13, HudPalette.DIM, ctx.font_mono)
		tag_x += -(tw + 10.0) if right else tw + 10.0
	if u.exposed:
		_exposed_tag(Vector2(tag_x, mid), col, right)
	var pct := str(HudFormat.percent(frac))
	var pw := text_width(pct, 30, ctx.font_numbers)
	var sw := text_width("%", 16, ctx.font_numbers)
	var px := x if right else x + BLOCK_W - pw - sw
	text(pct, Vector2(px, mid + 10.0), 30, HudPalette.IVORY, ctx.font_numbers)
	text("%", Vector2(px + pw + 1.0, mid + 10.0), 16, HudPalette.MUTED, ctx.font_numbers)
	if u.integrity <= 0.0:
		caps(tr("HUD_DESTROYED"), Vector2(x, y + 70.0), 13, HudPalette.DIM, 0.22,
			HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT, BLOCK_W)
	_bar(Rect2(x, y + 39.0, BLOCK_W, BAR_H), frac, maxf(_trail[team], frac), col, right, u.exposed)


## Framed bar: frame chamfered at the outer end, fill anchored there.
func _bar(r: Rect2, frac: float, trail: float, col: Color, right: bool, exposed: bool) -> void:
	var frame := _chamfer(r, right)
	draw_colored_polygon(frame, HudPalette.BRASS_DIM)
	draw_colored_polygon(_chamfer(r.grow(-1.5), right), Color(HudPalette.INK_DEEP, 0.8))
	var inner := r.grow(-3.0)
	var fw := inner.size.x * frac
	var fill := Rect2(inner.end.x - fw if right else inner.position.x, inner.position.y, fw, inner.size.y)
	if fw > 0.5:
		var fp := _chamfer(fill, right) if fw > CHAMFER * 2.0 else PackedVector2Array([fill.position,
			Vector2(fill.end.x, fill.position.y), fill.end, Vector2(fill.position.x, fill.end.y)])
		draw_colored_polygon(fp, col)
		scrim_sheen(Rect2(fill.position, Vector2(fill.size.x, fill.size.y * 0.55)))
	var lw := inner.size.x * (trail - frac)
	if lw > 0.5:
		var lx := fill.position.x - lw if right else fill.end.x
		draw_rect(Rect2(lx, inner.position.y, lw, inner.size.y), Color(HudPalette.IVORY, 0.22))
	if exposed:
		var k := pulse(_t, 1.8, 0.4)
		hatch(inner, Color(1, 1, 1, 0.55 * k), 6.0, 2.0)
	for th in THRESHOLDS:
		var d := inner.size.x * th
		var sx := inner.end.x - d if right else inner.position.x + d
		draw_rect(Rect2(sx - 1.5, r.position.y, 3.0, r.size.y), Color(HudPalette.INK_DEEP, 0.95))
		draw_colored_polygon(PackedVector2Array([Vector2(sx - 4.5, r.position.y - 7.5), Vector2(sx + 4.5, r.position.y - 7.5),
			Vector2(sx, r.position.y - 1.5)]), HudPalette.BRASS)


## White top sheen (28% to 0) over a fill.
func scrim_sheen(r: Rect2) -> void:
	var a := Color(1, 1, 1, 0.28)
	var b := Color(1, 1, 1, 0.0)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([a, a, b, b]))


func _chamfer(r: Rect2, right: bool) -> PackedVector2Array:
	var p := r.position
	var e := r.end
	var c := minf(CHAMFER, r.size.y * 0.5)
	if right:
		return PackedVector2Array([p, Vector2(e.x - c, p.y), Vector2(e.x, p.y + c), e, Vector2(p.x, e.y)])
	return PackedVector2Array([Vector2(p.x + c, p.y), Vector2(e.x, p.y), e, Vector2(p.x, e.y), Vector2(p.x, p.y + c)])


## EXPOSED tag: team-colour hairline box with a cracked shield and caps text.
func _exposed_tag(at: Vector2, col: Color, right: bool) -> void:
	var k := pulse(_t, 1.8, 0.4)
	var t := tr("HUD_EXPOSED")
	var w := caps_width(t, 14, 0.2) + 34.0
	var r := Rect2(Vector2(at.x - w if right else at.x, at.y - 12.0), Vector2(w, 24.0))
	draw_rect(r, Color(col, k), false, 1.0)
	var s := r.position + Vector2(13.0, 12.0)
	var sh := PackedVector2Array([s + Vector2(0, -7), s + Vector2(6, -4), s + Vector2(6, 1), s + Vector2(0, 7),
		s + Vector2(-6, 1), s + Vector2(-6, -4), s + Vector2(0, -7)])
	draw_polyline(sh, Color(col, k), 1.2, true)
	draw_polyline(PackedVector2Array([s + Vector2(0.5, -5), s + Vector2(-1.5, -1), s + Vector2(1.5, 1), s + Vector2(-0.5, 5)]),
		Color(col, k), 1.2, true)
	caps(t, Vector2(r.position.x + 24.0, at.y + 5.0), 14, Color(HudPalette.IVORY, k), 0.2)
