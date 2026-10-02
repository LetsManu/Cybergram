class_name SquadStrip
extends HudWidget
## Squad strip (design/ux/hud.md §4.6; wardlings-and-economy.md §8), bottom
## left above the vitals panel: one slot per squad slot (min 3): slot number,
## variant letters (Pk = Picket, the only slice variant), HP bar and the state
## badge — letters, never colour only: F Follow, H Hold, A Attack, C Capture,
## ! in combat, R returning, D dissolving (death hold). Empty slots show "--".
## Shown only while the squad has members (hud.md §2).

const SLOT_W: float = 66.0
const SLOT_H: float = 42.0
const GAP: float = 6.0
const MIN_SLOTS: int = 3
const COMMAND_LETTER := {0: "-", 1: "F", 2: "H", 3: "A", 4: "C"}
const EDGE := Color(1.0, 0.86, 0.25)


func _draw() -> void:
	var c := ctx.client
	if c == null or c.wardlings == null:
		return
	var pips := c.wardlings.own_squad
	if pips.is_empty():
		return
	var n := maxi(MIN_SLOTS, pips.size())
	var y := size.y - SLOT_H
	text(tr("HUD_SQUAD"), Vector2(0.0, y - 6.0), 14, EDGE, ctx.font_display)
	for i in n:
		var r := Rect2(Vector2(i * (SLOT_W + GAP), y), Vector2(SLOT_W, SLOT_H))
		panel(r)
		if i >= pips.size():
			text("%d --" % (i + 1), r.position + Vector2(7.0, 18.0), 14, HudPalette.TEXT_OFF, ctx.font_display)
			continue
		var p: WardlingPresenter.SquadPip = pips[i]
		draw_rect(r, EDGE, false, 1.5)
		text("%d %s" % [i + 1, tr("HUD_VARIANT_PICKET")], r.position + Vector2(7.0, 18.0), 14, HudPalette.TEXT,
			ctx.font_display)
		var badge := badge_of(p)
		var normal: bool = badge == COMMAND_LETTER.get(p.command, "-")
		text(badge, r.position + Vector2(SLOT_W - 17.0, 19.0), 17, EDGE if normal else HudPalette.DANGER.lightened(0.2),
			ctx.font_numbers)
		var b := Rect2(r.position + Vector2(7.0, SLOT_H - 14.0), Vector2(SLOT_W - 14.0, 7.0))
		bar(b, p.hp_frac, HudPalette.HP if p.hp_frac > 0.35 else HudPalette.DANGER, Color(0.15, 0.15, 0.18))


## State badge letter for one pip.
static func badge_of(p: WardlingPresenter.SquadPip) -> String:
	if p.dissolving:
		return "D"
	if (p.flags & WardlingSim.FLAG_RETURNING) != 0:
		return "R"
	if (p.flags & WardlingSim.FLAG_COMBAT) != 0 and p.command != 3:
		return "!"
	return COMMAND_LETTER.get(p.command, "-")
