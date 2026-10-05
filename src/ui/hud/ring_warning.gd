class_name RingWarning
extends HudWidget
## W16-SDWATER: "OUTSIDE THE RING" while the local hero is outside the Sudden
## Death ring and takes damage (design: match-flow-and-map.md §3.1). Reads
## ClientWorld.sudden_death (SuddenDeathRing) and the own body position only.
## The pulse scales with comfort effects intensity and is static with
## reduce-motion. Strings: assets/localization/hud.csv (HUD_RING_*).

const W: float = 360.0
const H: float = 56.0

var _t: float = 0.0


## True when the warning should show for `ring` and a hero at `pos`.
static func shows(ring: SuddenDeathRing, pos: Vector3, dead: bool) -> bool:
	return ring != null and not dead and ring.is_outside(pos)


func _draw() -> void:
	var c := ctx.client if ctx != null else null
	if c == null or c.body == null or not RingWarning.shows(c.sudden_death, c.body.state.position, c.is_dead()):
		return
	var gs := GameSettings.shared()
	_t += get_process_delta_time()
	var calm := UiKit.reduce_motion()
	var k := clampf(gs.comfort_fx_intensity, 0.0, 1.0)
	var pulse := 0.0 if calm else 0.5 + 0.5 * sin(_t * 6.0)
	var a := 0.85 + 0.15 * pulse * k
	var r := Rect2((size.x - W) * 0.5, 0.0, W, H)
	panel(r)
	var col := Color(HudPalette.DANGER, a)
	text(tr("HUD_RING_OUTSIDE"), Vector2(r.position.x, 28.0), 24, col, ctx.font_display, HORIZONTAL_ALIGNMENT_CENTER, W)
	text(tr("HUD_RING_RETURN"), Vector2(r.position.x, 48.0), 14, HudPalette.TEXT_DIM, ctx.font_display, HORIZONTAL_ALIGNMENT_CENTER, W)
	# Colour-free cue: a chevron pointing toward the ring centre on screen is the
	# damage indicator's job; here a bar of ink-edged ticks reinforces the text.
	var tick := Color(HudPalette.DANGER, 0.5 + 0.5 * pulse * k)
	draw_rect(Rect2(r.position.x, r.end.y - 3.0, W, 3.0), tick)
