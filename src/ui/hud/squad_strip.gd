class_name SquadStrip
extends HudWidget
## Squad strip (design/ux/hud.md §4.6; wardlings-and-economy.md §8; v0.12 look,
## design/ux/hud-v0.12.md §2), bottom left above the vitals: "SQUAD" caps over
## the current command (FOLLOW …), then one 45 px pip per squad slot (min 3):
## an ally chevron, a 3 px HP line and the slot number + state letter in mono —
## letters, never colour only: F Follow, H Hold, A Attack, C Capture, ! in
## combat (warn), R returning, D dissolving. Empty slots: a hollow chevron at
## 30%. Shown only while the squad has members (hud.md §2). Idle: 42%.

const PIP_W: float = 45.0
const H: float = 60.0
const MIN_SLOTS: int = 3
const COMMAND_LETTER := {0: "-", 1: "F", 2: "H", 3: "A", 4: "C"}
const COMMAND_KEYS := {1: "HUD_CMD_FOLLOW", 2: "HUD_CMD_HOLD", 3: "HUD_CMD_ATTACK", 4: "HUD_CMD_CAPTURE"}


func _draw() -> void:
	var c := ctx.client
	if c == null or c.wardlings == null:
		return
	var pips := c.wardlings.own_squad
	if pips.is_empty():
		return
	var a := idle_a(0.42)
	var n := maxi(MIN_SLOTS, pips.size())
	var y := size.y - H
	caps(tr("HUD_SQUAD"), Vector2(0.0, y + 22.0), 16, Color(HudPalette.MUTED, a), 0.22)
	var head := headline_key(pips)
	var head_col := HudPalette.IVORY if head in COMMAND_KEYS.values() else HudPalette.WARN_UI
	caps(tr(head), Vector2(0.0, y + 49.0), 18, Color(head_col, a), 0.2)
	var hw := maxf(caps_width(tr("HUD_SQUAD"), 16), caps_width(tr(head), 18, 0.2))
	var x0 := hw + 21.0
	var col := ctx.team_color(ctx.own_team())
	for i in n:
		var cx := x0 + i * (PIP_W + 3.0) + PIP_W * 0.5
		var gc := Vector2(cx, y + 14.0)
		var hp_r := Rect2(cx - 18.0, y + 27.0, 36.0, 3.0)
		if i >= pips.size():
			chevron_line(gc, 9.0, Color(col, 0.3 * a))
			draw_rect(hp_r, Color(HudPalette.IVORY, 0.18 * 0.3 * a))
			text_c(str(i + 1), Vector2(cx, y + 45.0), 15, Color(HudPalette.MUTED, a), ctx.font_mono)
			continue
		var p: WardlingPresenter.SquadPip = pips[i]
		chevron(gc, 9.0, Color(col, a))
		bar(hp_r, p.hp_frac, Color(HudPalette.IVORY if p.hp_frac > 0.35 else HudPalette.damage_color(ctx.settings.colorblind), a),
			Color(HudPalette.IVORY, 0.18 * a))
		var badge := badge_of(p)
		var normal: bool = badge == COMMAND_LETTER.get(p.command, "-")
		text_c("%d%s" % [i + 1, badge], Vector2(cx, y + 45.0), 15,
			Color(HudPalette.MUTED if normal else HudPalette.WARN_UI, a), ctx.font_mono)


## Headline under "SQUAD": what the squad is actually doing (polish
## 2026-10-05). All members dissolving -> DISSOLVING; every live member walking
## back -> RETURNING; otherwise the command of the first live member.
static func headline_key(pips: Array) -> String:
	var live: Array = pips.filter(func(p: WardlingPresenter.SquadPip) -> bool: return not p.dissolving)
	if live.is_empty():
		return "HUD_SQ_DISSOLVING"
	if live.all(func(p: WardlingPresenter.SquadPip) -> bool: return (p.flags & WardlingSim.FLAG_RETURNING) != 0):
		return "HUD_SQ_RETURNING"
	return COMMAND_KEYS.get((live[0] as WardlingPresenter.SquadPip).command, "HUD_SQUAD")


## State badge letter for one pip.
static func badge_of(p: WardlingPresenter.SquadPip) -> String:
	if p.dissolving:
		return "D"
	if (p.flags & WardlingSim.FLAG_RETURNING) != 0:
		return "R"
	if (p.flags & WardlingSim.FLAG_COMBAT) != 0 and p.command != 3:
		return "!"
	return COMMAND_LETTER.get(p.command, "-")
