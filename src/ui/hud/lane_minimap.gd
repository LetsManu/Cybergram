class_name LaneMinimap
extends HudWidget
## W14 lane minimap (top-left): the map's lanes, flank tunnels and hardpoints in
## schematic top-down form, rotated 180° for the Syndicate so the own HQ is
## always on the left. Chips use the FrontStrip glyphs' colours (own / enemy /
## neutral) with a white outline while contested; the own team's front in each
## lane gets a white tick; the local hero is a white arrow. Presentation only:
## it reads ClientWorld.map_def (static layout), .hardpoints and .fronts
## (replicated) and the local body; no gameplay state.

const PAD: float = 10.0
const CHIP_R: float = 4.5
# --- W19-HUD: v0.12 frame (hud-v0.12.md §2): map area 318×204, label below ---
const MAP_SIZE := Vector2(318.0, 204.0)
# --- end W19-HUD ---


func _draw() -> void:
	var c := ctx.client
	if c == null or c.map_def == null or c.map_def.lanes.is_empty() or c.hardpoints.is_empty():
		return
	var md := c.map_def
	var team := ctx.own_team()
	var bounds := _bounds(md)
	# --- W19-HUD: radial ink backdrop + brass corner ticks instead of a box; label ---
	var r := Rect2(Vector2.ZERO, MAP_SIZE)
	radial_backdrop(r.grow(24.0), 0.75)
	corner_ticks(r, 15.0, Color(HudPalette.BRASS, 0.7))
	_label(c, Vector2(0.0, r.end.y + 24.0))
	# --- end W19-HUD ---
	var inner := r.grow(-PAD)
	var flip := team == MapDef.TEAM_SYNDICATE
	var to_px := func(p: Vector3) -> Vector2:
		var u := (-p.z - bounds.position.x) / maxf(bounds.size.x, 1.0)
		var v := (p.x - bounds.position.y) / maxf(bounds.size.y, 1.0)
		if flip:
			u = 1.0 - u
			v = 1.0 - v
		return inner.position + Vector2(u * inner.size.x, v * inner.size.y)
	var line_col := Color(1, 1, 1, 0.28)
	for hq in md.hqs:
		var gates: PackedVector3Array = hq.lane_gates if not hq.lane_gates.is_empty() else PackedVector3Array([hq.lane_gate])
		for li in md.lanes.size():
			var hps := md.lanes[li].hardpoints
			if hps.is_empty():
				continue
			var near: HardpointDef = hps[0] if hq.team == MapDef.TEAM_CONCORD else hps[hps.size() - 1]
			var g: Vector3 = gates[mini(li, gates.size() - 1)]
			draw_line(to_px.call(hq.sanctum), to_px.call(g), line_col, 2.0)
			draw_line(to_px.call(g), to_px.call(near.position), line_col, 2.0)
		draw_circle(to_px.call(hq.uplink), 5.0, ctx.team_color(hq.team))
	# W18-GEO: the between-lane jungle, drawn faintly under the lanes.
	for path in md.jungle_paths:
		for k in path.size() - 1:
			draw_line(to_px.call(path[k]), to_px.call(path[k + 1]), Color(1.0, 0.35, 0.75, 0.22), 1.0)
	for lane in md.lanes:
		for k in lane.hardpoints.size() - 1:
			draw_line(to_px.call(lane.hardpoints[k].position), to_px.call(lane.hardpoints[k + 1].position), line_col, 2.0)
		for f in lane.flank_loops:
			for k in f.waypoints.size() - 1:
				draw_line(to_px.call(f.waypoints[k]), to_px.call(f.waypoints[k + 1]), Color(0.7, 0.55, 1.0, 0.35), 1.0)
	var base := 0
	for li in md.lanes.size():
		var hps := md.lanes[li].hardpoints
		var fi := li * 2 + team
		var front := c.fronts[fi] if fi < c.fronts.size() else -1
		for k in hps.size():
			var i := base + k
			if i >= c.hardpoints.size():
				break
			var st := c.hardpoints[i]
			var p: Vector2 = to_px.call(hps[k].position)
			var col := ctx.team_color(st.owner) if st.owner >= 0 else Color(0.2, 0.2, 0.25)
			draw_circle(p, CHIP_R, col)
			draw_arc(p, CHIP_R + 1.0, 0.0, TAU, 12, Color.WHITE if st.contested else Color(1, 1, 1, 0.5),
				2.0 if st.contested else 1.0, true)
			if k == front:
				draw_arc(p, CHIP_R + 4.0, 0.0, TAU, 16, Color.WHITE, 1.5, true)
		base += hps.size()
	# W21-G2: the own Armory (shop glyph) and Foundry (squad refill glyph).
	var own_hq := md.hq(team)
	var glyph_r := _marker_def().minimap_glyph_r
	if own_hq != null:
		draw_armory_glyph(self, to_px.call(own_hq.armory), HudPalette.BRASS_HI, glyph_r)
		draw_foundry_glyph(self, to_px.call(own_hq.foundry), HudPalette.TEAL, glyph_r)
	# W16-SDWATER: the Sudden Death ring (danger colour), same radius as the server.
	if c.sudden_death != null and c.sudden_death.active:
		var ring := PackedVector2Array()
		var rr := c.sudden_death.radius()
		var cc := c.sudden_death.centre
		for k in 49:
			var ang := TAU * float(k) / 48.0
			ring.append(to_px.call(cc + Vector3(cos(ang) * rr, 0.0, sin(ang) * rr)))
		draw_polyline(ring, Color(0, 0, 0, 0.6), 4.0, true)
		draw_polyline(ring, HudPalette.DANGER, 2.0, true)
	if c.body != null:
		var me: Vector2 = to_px.call(c.body.global_position)
		var yaw: float = c.body.look_yaw if "look_yaw" in c.body else 0.0
		var fwd3 := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var ahead: Vector2 = to_px.call(c.body.global_position + fwd3 * 12.0)
		var d := (ahead - me).normalized()
		var side := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([me + d * 7.0, me - d * 4.0 + side * 4.0, me - d * 4.0 - side * 4.0]), Color.WHITE)


## W21-G2 shop glyph: a stall with an awning, `r` px half size.
static func draw_armory_glyph(ci: CanvasItem, at: Vector2, col: Color, r: float) -> void:
	var dark := Color(0.0, 0.0, 0.0, 0.7)
	ci.draw_rect(Rect2(at - Vector2(r + 1.5, r * 0.2 + 1.5), Vector2(2.0 * r + 3.0, r * 1.2 + 3.0)), dark)
	ci.draw_rect(Rect2(at + Vector2(-r + 1.0, 0.0), Vector2(2.0 * r - 2.0, r * 0.9)), col)
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-r - 1.0, 0.0), at + Vector2(r + 1.0, 0.0), at + Vector2(r - 1.0, -r), at + Vector2(-r + 1.0, -r)]), col.lightened(0.15))
	ci.draw_line(at + Vector2(-r - 1.0, 0.0), at + Vector2(r + 1.0, 0.0), dark, 1.0)


## W21-G2 Foundry glyph: a hexagon with a centre dot (squad refill).
static func draw_foundry_glyph(ci: CanvasItem, at: Vector2, col: Color, r: float) -> void:
	var pts := PackedVector2Array()
	for k in 7:
		var a := TAU * float(k) / 6.0
		pts.append(at + Vector2(cos(a), sin(a)) * (r + 0.5))
	ci.draw_polyline(pts, Color(0.0, 0.0, 0.0, 0.7), 4.0, true)
	ci.draw_polyline(pts, col, 2.0, true)
	ci.draw_circle(at, 1.6, col)


var _def: ArmoryMarkerDef


func _marker_def() -> ArmoryMarkerDef:
	if _def == null:
		_def = load(ArmoryMarkerDef.DEFAULT_PATH) as ArmoryMarkerDef
	return _def


# --- W19-HUD: "SHARDLINE · WAVE 0:18" under the map (idle 42%) ---
func _label(c: ClientWorld, at: Vector2) -> void:
	var a := idle_a(0.42)
	var map_name := c.map_def.display_name if c.map_def.display_name != "" else String(c.map_def.resource_path.get_file().get_basename())
	var rules: WardlingRulesDef = c.wardlings.rules if c.wardlings != null else null
	if rules == null or c.match_state == null:
		return
	var left := next_wave_in(c.match_state.time_s, rules)
	var t := HudFormat.clock(ceilf(left))
	var tw := text_width(t, 16, ctx.font_numbers)
	text(t, Vector2(MAP_SIZE.x - tw, at.y), 16, Color(HudPalette.IVORY, a), ctx.font_numbers)
	var wave_w := caps_width(tr("HUD_WAVE"), 16)
	caps(tr("HUD_WAVE"), Vector2(MAP_SIZE.x - tw - 9.0 - wave_w, at.y), 16, Color(HudPalette.MUTED, a), 0.22)
	if caps_width(map_name, 16) > MAP_SIZE.x - tw - wave_w - 30.0:
		map_name = map_name.split(" ")[0]  # "SHARDLINE FRONT" -> "SHARDLINE" when it would collide
	caps(map_name, at, 16, Color(HudPalette.MUTED, a), 0.22)


## Seconds from match time `t` to the next Vanguard wave (first at
## wave_first_s, then every wave_interval_s; wardlings-and-economy.md §10).
static func next_wave_in(t: float, rules: WardlingRulesDef) -> float:
	if t < rules.wave_first_s:
		return rules.wave_first_s - t
	var k := ceilf((t - rules.wave_first_s) / maxf(rules.wave_interval_s, 0.01))
	var nxt := rules.wave_first_s + k * rules.wave_interval_s
	return nxt - t if nxt > t else rules.wave_interval_s
# --- end W19-HUD ---


## Layout bounds in (lane distance -z, lateral x), padded.
static func _bounds(md: MapDef) -> Rect2:
	var pts: Array[Vector3] = []
	for hq in md.hqs:
		pts.append(hq.sanctum)
	for lane in md.lanes:
		for h in lane.hardpoints:
			pts.append(h.position)
	var r := Rect2(Vector2(-pts[0].z, pts[0].x), Vector2.ZERO)
	for p in pts:
		r = r.expand(Vector2(-p.z, p.x))
	return r.grow_individual(4.0, 18.0, 4.0, 18.0)
