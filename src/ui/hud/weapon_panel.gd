class_name WeaponPanel
extends HudWidget
## Weapon block, bottom right (design/ux/hud.md §4.3; v0.12 look, design/ux/
## hud-v0.12.md §2), right-aligned, 393 wide, no box: the weapon name in caps
## (ivory) with MANA / AMMO caps muted on the right; Mana: the value in 54
## numerals + "%", then a 20-segment 8 px pool bar (ivory 85%; BURNOUT = dim
## grey plus the label); Mechanical: magazine 54 / reserve 22, the tick strip,
## RELOADING / DRY in warn and the [R] key chip at ≤ 25%. Mounts CORE / FRAME /
## CHAMBER: brass-dim hairline cells with tier diamonds; empty = a dashed
## hairline. Idle: mounts fade to 42%.

const W: float = 393.0
const H: float = 170.0
const SEGMENTS: int = 20
const SOCKET_KEYS := {1: "HUD_SOCKET_CORE", 2: "HUD_SOCKET_BARREL", 3: "HUD_SOCKET_FRAME", 4: "HUD_SOCKET_CHAMBER"}


func _draw() -> void:
	var client := ctx.client
	if client == null or client.combat == null:
		return
	var c := client.combat
	var x := size.x - W
	var top := size.y - H
	var wd := client.hero_def.weapon if client.hero_def != null else null
	var wname := wd.display_name if wd != null else ""
	caps(wname, Vector2(x, top + 20.0), 20, HudPalette.IVORY, 0.24)
	var mana := c.feed_kind == WeaponDef.FeedKind.MANA
	caps(tr("HUD_MANA") if mana else tr("HUD_AMMO"), Vector2(x, top + 20.0), 15, HudPalette.MUTED, 0.22,
		HORIZONTAL_ALIGNMENT_RIGHT, W)
	var burnout := (c.ammo_flags & AmmoFeed.FLAG_BURNOUT) != 0
	var reloading := (c.ammo_flags & AmmoFeed.FLAG_RELOADING) != 0
	var dry := (c.ammo_flags & AmmoFeed.FLAG_DRY) != 0
	var frac := clampf(c.ammo / maxf(1.0, c.ammo_capacity), 0.0, 1.0)
	var big_y := top + 76.0
	var bar_y := top + 92.0
	if mana:
		var pct := str(HudFormat.percent(frac))
		var sw := text_width("%", 21, ctx.font_numbers)
		text("%", Vector2(x, big_y), 21, HudPalette.MUTED, ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, W)
		text(pct, Vector2(x, big_y), 54, HudPalette.DIM if burnout else HudPalette.IVORY, ctx.font_numbers,
			HORIZONTAL_ALIGNMENT_RIGHT, W - sw - 6.0)
		var sgw := (W + 3.0) / SEGMENTS
		var on_col := Color(HudPalette.DIM, 0.85) if burnout else Color(HudPalette.IVORY, 0.85)
		for i in SEGMENTS:
			var on := float(i + 1) / SEGMENTS <= frac + 0.001
			draw_rect(Rect2(x + i * sgw, bar_y, sgw - 3.0, 8.0), on_col if on else Color(HudPalette.IVORY, 0.16))
		if burnout:
			caps(tr("HUD_BURNOUT"), Vector2(x, big_y), 16, HudPalette.MUTED, 0.22)
	else:
		var low := frac <= 0.25
		var mag_col := HudPalette.WARN_UI if low else HudPalette.IVORY
		var res := "/ %d" % c.reserve
		var rw := text_width(res, 22, ctx.font_numbers)
		text(res, Vector2(x, big_y), 22, HudPalette.MUTED, ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, W)
		text(str(roundi(c.ammo)), Vector2(x, big_y), 54, mag_col, ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, W - rw - 9.0)
		var n := maxi(c.ammo_capacity, 1)
		var tw := (W + 1.5) / n
		for i in n:
			draw_rect(Rect2(x + i * tw, bar_y + 2.0, maxf(tw - 1.5, 1.0), 5.0),
				mag_col if i < roundi(c.ammo) else Color(HudPalette.IVORY, 0.16))
		var state := ""
		if reloading:
			state = tr("HUD_RELOADING")
		elif dry:
			state = tr("HUD_DRY")
		if state != "":
			caps(state, Vector2(x, big_y), 16, HudPalette.WARN_UI, 0.22)
		elif low:
			key_chip(Vector2(x + 15.0, big_y - 10.0), ctx.key_label(&"reload", "R"), 30.0)
	_mounts(client, Vector2(x, top + H - 39.0))


func _mounts(client: ClientWorld, at: Vector2) -> void:
	var items := client.mount_items()
	var p := client.progress
	var a := idle_a(0.42)
	var bw := (W - 2.0 * 9.0) / 3.0
	for i in SnapshotData.ProgressState.MOUNT_SOCKETS.size():
		var r := Rect2(at + Vector2(i * (bw + 9.0), 0.0), Vector2(bw, 39.0))
		var item: ArmoryItemDef = items[i] if i < items.size() else null
		var socket: int = SnapshotData.ProgressState.MOUNT_SOCKETS[i]
		var label := tr(SOCKET_KEYS.get(socket, "HUD_SOCKET_CORE"))
		var tier := p.mount_tier[i] if p != null and item != null else 0
		var tiers := item.tiers() if item != null else 3
		if item == null:
			_dashed(r, Color(HudPalette.HAIR_STRONG, a))
		else:
			draw_rect(r.grow(-0.5), Color(HudPalette.BRASS_DIM, a), false, 1.0)
		var pips_w := tiers * 10.5 + 8.0
		var lsz := 14 if caps_width(label, 14, 0.1) <= r.size.x - pips_w - 14.0 else 12
		caps(label, Vector2(r.position.x + 8.0, r.get_center().y + 5.0), lsz,
			Color(HudPalette.BRASS_HI if item != null else HudPalette.DIM, a), 0.06 if lsz == 12 else 0.1)
		for k in tiers:
			var pc := Vector2(r.end.x - 10.0 - (tiers - 1 - k) * 10.5, r.get_center().y)
			if k < tier:
				diamond(pc, 3.6, Color(HudPalette.BRASS, a))
			else:
				draw_polyline(PackedVector2Array([pc + Vector2(0, -3.6), pc + Vector2(3.6, 0), pc + Vector2(0, 3.6),
					pc + Vector2(-3.6, 0), pc + Vector2(0, -3.6)]), Color(HudPalette.BRASS_DIM if item != null else HudPalette.DIM, a), 1.0)


## Dashed hairline rectangle (empty mount).
func _dashed(r: Rect2, col: Color) -> void:
	var p := r.grow(-0.5)
	draw_dashed_line(p.position, Vector2(p.end.x, p.position.y), col, 1.0, 4.0)
	draw_dashed_line(Vector2(p.end.x, p.position.y), p.end, col, 1.0, 4.0)
	draw_dashed_line(p.end, Vector2(p.position.x, p.end.y), col, 1.0, 4.0)
	draw_dashed_line(Vector2(p.position.x, p.end.y), p.position, col, 1.0, 4.0)
