class_name TaskCue
extends HudWidget
## E14 minimal Plant / Breach cue under the objective tracker (design/ux/hud.md
## §4.9 task lines): the carried Cell ("YOU ARE CARRYING THE CELL"), the plant /
## pickup / defuse channel, the Cell's whereabouts for the task the player is in
## or near, and the Ward Generator's HP and shield. Reads replicated hardpoint
## state only. Strings are keys in assets/localization/hud.csv (E12).

const W: float = 366.0
const H: float = 54.0


func _draw() -> void:
	var c := ctx.client if ctx != null else null
	if c == null or c.hardpoints.is_empty() or c.body == null:
		return
	var defs := c.hardpoint_defs()
	var team := ctx.own_team()
	var me := ctx.own_id()
	var idx := -1
	for i in c.hardpoints.size():  # the carried Cell wins
		if c.hardpoints[i].carrier_id == me and me != 0 and c.hardpoints[i].cell_state == HardpointSim.CellState.CARRIED:
			idx = i
	if idx < 0:
		idx = _nearest(c, defs)
	if idx < 0 or idx >= defs.size():
		return
	var st := c.hardpoints[idx]
	var line := ""
	var frac := -1.0
	var col := HudPalette.TEXT
	if st.task == HardpointDef.TaskKind.PLANT:
		var mine := st.cell_team == team
		match st.cell_state:
			HardpointSim.CellState.CARRIED:
				if st.carrier_id == me:
					line = tr("HUD_CELL_CARRYING") % defs[idx].display_name
					col = HudPalette.WARN_UI
				else:
					line = tr("HUD_CELL_ALLY_CARRIES") if mine else tr("HUD_CELL_ENEMY_CARRIES")
			HardpointSim.CellState.CRADLE:
				line = tr("HUD_CELL_TAKE") if mine else tr("HUD_CELL_ENEMY_CRADLE")
			HardpointSim.CellState.DROPPED:
				line = tr("HUD_CELL_DROPPED") if mine else tr("HUD_CELL_ENEMY_DROPPED")
			HardpointSim.CellState.PLANTED:
				line = tr("HUD_CELL_PLANTED") if mine else tr("HUD_CELL_DEFUSE")
				col = ctx.team_color(st.cell_team).lightened(0.3)
		if st.channel != HardpointSim.Channel.NONE:
			line = ["", tr("HUD_CHANNEL_PICKUP"), tr("HUD_CHANNEL_PLANTING"), tr("HUD_CHANNEL_DEFUSING"), tr("HUD_CHANNEL_DISPERSING")][clampi(st.channel, 0, 4)]
			frac = st.channel_frac
	elif st.task == HardpointDef.TaskKind.BREACH and st.owner >= 0:
		if st.breach_phase2:
			line = tr("HUD_GENERATOR_DOWN")
		else:
			line = tr("HUD_GENERATOR_HP") % ceili(st.gen_frac * 100.0)
			if st.shielded:
				line += tr("HUD_GENERATOR_SHIELDED")
				col = HudPalette.WARN_UI
			frac = st.gen_frac
	if line == "":
		return
	if ctx.idle_k > 0.5:
		return  # v0.12 idle: the objective collapses to glyph + verb
	# v0.12: no box; the cue line in 18 body under the objective card (muted, or
	# the state colour when it matters), with a 4 px bar for channels / Generator.
	var x := size.x - W
	text(line, Vector2(x + 21.0, 20.0), 18, HudPalette.MUTED if col == HudPalette.TEXT else col, ctx.font_body,
		HORIZONTAL_ALIGNMENT_LEFT, W - 21.0)
	if frac >= 0.0:
		bar(Rect2(x + 21.0, 31.0, W - 21.0, 4.0), frac, HudPalette.IVORY if col == HudPalette.TEXT else col)


## The Plant / Breach hardpoint the player stands in, else the nearest within the tracker range.
func _nearest(c: ClientWorld, defs: Array[HardpointDef]) -> int:
	var own := c.own_hardpoint_index()
	if own >= 0:
		return own
	var p := c.body.state.position
	var best := ctx.tuning.tracker_range_m if ctx.tuning != null else 40.0
	var idx := -1
	for i in defs.size():
		var d := Vector2(p.x - defs[i].position.x, p.z - defs[i].position.z).length() - defs[i].zone_radius
		if d < best:
			best = d
			idx = i
	return idx
