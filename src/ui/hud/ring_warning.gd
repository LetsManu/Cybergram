class_name RingWarning
extends HudWidget
## W16-SDWATER: "OUTSIDE THE RING" while the local hero is outside the Sudden
## Death ring and takes damage (design: match-flow-and-map.md §3.1). Reads
## ClientWorld.sudden_death (SuddenDeathRing) and the own body position only.
## v0.12: a static banner (no pulse) on a radial ink backing. Strings: assets/localization/hud.csv (HUD_RING_*).

const W: float = 534.0
const H: float = 90.0

var _t: float = 0.0
## True when the last _draw put the banner on screen (tests / debugging).
var drawn: bool = false


## True when the warning should show for `ring` and a hero at `pos`.
static func shows(ring: SuddenDeathRing, pos: Vector3, dead: bool) -> bool:
	return ring != null and not dead and ring.is_outside(pos)


func _draw() -> void:
	drawn = false
	var c := ctx.client if ctx != null else null
	if c == null or c.body == null or not RingWarning.shows(c.sudden_death, c.body.state.position, c.is_dead()):
		return
	drawn = true
	var gs := GameSettings.shared()
	_t += get_process_delta_time()
	# W19-HUD v0.12 (hud-v0.12.md §2): static banner (no pulse), radial ink
	# backing, tracked caps with hairline wings, a sub-line with the damage rate
	# and the ring timer.
	var _calm := UiKit.reduce_motion() or gs.comfort_fx_intensity <= 0.0
	var dmg := HudPalette.damage_color(ctx.settings.colorblind)
	var cx := size.x * 0.5
	radial_backdrop(Rect2(cx - W * 0.5 - 300.0, -30.0, W + 600.0, H + 70.0), 0.72)
	var title := tr("HUD_RING_OUTSIDE")
	var tw := caps_width(title, 33, 0.32)
	var shift := UiKit.track(ts(33), 0.32) * 0.5
	caps(title, Vector2(cx - tw * 0.5 + shift, 38.0), 33, dmg, 0.32)
	var wy := 38.0 - ts(33) * 0.36
	for side: float in [-1.0, 1.0]:
		var x0 := cx + side * (tw * 0.5 + 24.0)
		var x1 := x0 + side * 135.0
		draw_polygon(PackedVector2Array([Vector2(x0, wy), Vector2(x1, wy), Vector2(x1, wy + 1.5), Vector2(x0, wy + 1.5)]),
			PackedColorArray([dmg, Color(dmg, 0.0), Color(dmg, 0.0), dmg]))
	var sd := c.sudden_death
	var hp_s := 0
	if c.combat != null and sd.rules != null:
		hp_s = roundi(sd.rules.sudden_death_outside_frac_s * c.combat.max_hp)
	var left := HudFormat.clock(ceilf(maxf(sd.rules.sudden_death_shrink_s - sd.elapsed_s, 0.0))) if sd.rules != null else ""
	var parts := [tr("HUD_RING_RETURN_INSIDE"), tr("HUD_RING_HP_S") % hp_s, tr("HUD_RING_CLOSES") % left]
	var line := " · ".join(parts)
	var lw := text_width(line, 19)
	var x := cx - lw * 0.5
	var y := 76.0
	for i in parts.size():
		var seg: String = parts[i] + (" · " if i < parts.size() - 1 else "")
		text(seg, Vector2(x, y), 19, dmg if i == 1 else HudPalette.IVORY)
		x += text_width(seg, 19)
