class_name MatchHeader
extends HudWidget
## Match header, top centre (design/ux/hud.md §4.8): own Uplink bar on the
## left, enemy on the right (Integrity %, a darker "lost" region so the bar
## never seems to heal, hatched pulsing border + EXPOSED when exposed), the
## match clock + phase + next-phase countdown in the middle.

const TEAM_KEYS: Array[String] = ["HUD_TEAM_0", "HUD_TEAM_1"]
const PHASE_KEYS: Array[String] = ["HUD_PHASE_LOAD", "HUD_PHASE_DEPLOY", "HUD_PHASE_SKIRMISH", "HUD_PHASE_SURGE_I",
	"HUD_PHASE_SURGE_II", "HUD_PHASE_DROUGHT", "HUD_PHASE_TIME_OUT", "HUD_PHASE_END"]
const CENTER_W: float = 190.0
const BAR_H: float = 12.0
const LOST := Color(0.25, 0.07, 0.08, 0.9)

var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	super(delta)


func _draw() -> void:
	var c := ctx.client
	if c == null or c.match_state == null:
		return
	var m := c.match_state
	var team := ctx.own_team()
	var w := size.x
	panel(Rect2(Vector2.ZERO, Vector2(w, 62.0)))
	var bar_w := (w - CENTER_W - 48.0) * 0.5
	_uplink(c.uplink_state(team), team, 16.0, bar_w, false)
	_uplink(c.uplink_state(1 - team), 1 - team, w - 16.0 - bar_w, bar_w, true)
	var cx := (w - CENTER_W) * 0.5
	text(HudFormat.clock(m.time_s), Vector2(cx, 32.0), 30, HudPalette.TEXT, ctx.font_numbers,
		HORIZONTAL_ALIGNMENT_CENTER, CENTER_W)
	var phase: String = tr(PHASE_KEYS[m.phase]) if m.phase < PHASE_KEYS.size() else "?"
	var nxt := _next_text(m)
	text(phase + ("   " + nxt if nxt != "" else ""), Vector2(cx - 20.0, 52.0), 14, HudPalette.TEXT_DIM, ctx.font_display,
		HORIZONTAL_ALIGNMENT_CENTER, CENTER_W + 40.0)


func _next_text(m: SnapshotData.MatchState) -> String:
	if m.next_phase_s < 0.0 or m.phase == MatchRules.Phase.END:
		return ""
	var left := HudFormat.clock(ceilf(m.next_phase_s - m.time_s))
	if m.phase == MatchRules.Phase.DEPLOY:
		return tr("HUD_MIDS_UNLOCK") % left
	return tr("HUD_NEXT_PHASE") % left


func _uplink(u: SnapshotData.UplinkState, team: int, x: float, bw: float, right: bool) -> void:
	if u == null:
		return
	var frac := clampf(u.integrity / maxf(u.max_integrity, 1.0), 0.0, 1.0)
	var col := ctx.team_color(team)
	var align := HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	var title := tr("HUD_UPLINK_TITLE") % [tr(TEAM_KEYS[team]), HudFormat.percent(frac)]
	text(title, Vector2(x, 21.0), 15, HudPalette.TEXT, ctx.font_display, align, bw)
	var r := Rect2(x, 28.0, bw, BAR_H)
	draw_rect(r, LOST)
	var fw := bw * frac
	draw_rect(Rect2(x + bw - fw if right else x, r.position.y, fw, BAR_H), col)
	# Own = ring glyph, enemy = tooth glyph at the outer end (colour-free cue).
	var gx := r.end.x + 8.0 if right else r.position.x - 8.0
	if team == ctx.own_team():
		draw_arc(Vector2(gx, r.get_center().y), 4.0, 0.0, TAU, 16, HudPalette.TEXT, 1.5, true)
	else:
		var gc := Vector2(gx, r.get_center().y)
		draw_colored_polygon(PackedVector2Array([gc + Vector2(-4, -4), gc + Vector2(4, -4), gc + Vector2(0, 4)]), HudPalette.TEXT)
	if u.exposed:
		var k := 0.5 + 0.5 * sin(_t * TAU * 1.5)
		var ec := Color(HudPalette.DANGER, 0.6 + 0.4 * k)
		hatch(r, Color(0, 0, 0, 0.35), 10.0, 2.0)
		draw_rect(r.grow(2.0), ec, false, 2.0)
		text(tr("HUD_EXPOSED"), Vector2(x, 56.0), 13, ec, ctx.font_display, align, bw)
	elif u.integrity <= 0.0:
		text(tr("HUD_DESTROYED"), Vector2(x, 56.0), 13, HudPalette.TEXT_OFF, ctx.font_display, align, bw)
	else:
		draw_rect(r, Color(1, 1, 1, 0.22), false, 1.0)
