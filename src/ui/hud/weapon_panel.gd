class_name WeaponPanel
extends HudWidget
## Weapon panel, bottom right (design/ux/hud.md §4.3): weapon name; Mana: a
## segmented pool bar + % (dimmed grey with BURNOUT when the pool hit 0);
## Mechanical: magazine large, reserve small, magazine tick strip, amber at
## ≤ 25% with the [R] prompt, RELOADING / DRY states; mount strip for the
## slice sockets (Core / Frame / Chamber) with tier pips, empty = outlined box.

const W: float = 360.0
const H: float = 124.0
const SEGMENTS: int = 20
const SOCKET_KEYS := {1: "HUD_SOCKET_CORE", 2: "HUD_SOCKET_BARREL", 3: "HUD_SOCKET_FRAME", 4: "HUD_SOCKET_CHAMBER"}


func _draw() -> void:
	var client := ctx.client
	if client == null or client.combat == null:
		return
	var c := client.combat
	var x := size.x - W
	var top := size.y - H
	panel(Rect2(x, top, W, H))
	var wd := client.hero_def.weapon if client.hero_def != null else null
	var wname := wd.display_name.to_upper() if wd != null else ""
	text(wname, Vector2(x + 14.0, top + 22.0), 15, HudPalette.TEXT_DIM, ctx.font_display)
	var burnout := (c.ammo_flags & AmmoFeed.FLAG_BURNOUT) != 0
	var reloading := (c.ammo_flags & AmmoFeed.FLAG_RELOADING) != 0
	var dry := (c.ammo_flags & AmmoFeed.FLAG_DRY) != 0
	var frac := clampf(c.ammo / maxf(1.0, c.ammo_capacity), 0.0, 1.0)
	var state := ""
	var state_col := HudPalette.WARN
	if c.feed_kind == WeaponDef.FeedKind.MANA:
		var col := HudPalette.BURNOUT if burnout else HudPalette.MANA
		var br := Rect2(x + 14.0, top + 34.0, W - 128.0, 16.0)
		var sw := br.size.x / SEGMENTS
		for i in SEGMENTS:
			var sr := Rect2(br.position.x + i * sw, br.position.y, sw - 3.0, br.size.y)
			var on := float(i + 1) / SEGMENTS <= frac + 0.001
			draw_rect(sr, col if on else Color(0, 0, 0, 0.55))
		text("%d%%" % HudFormat.percent(frac), Vector2(br.end.x + 6.0, top + 52.0), 28,
			HudPalette.TEXT_DIM if burnout else HudPalette.TEXT, ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT,
			x + W - 12.0 - (br.end.x + 6.0))
		text(tr("HUD_MANA"), Vector2(x + 14.0, top + 68.0), 12, HudPalette.MANA, ctx.font_display)
		if burnout:
			state = tr("HUD_BURNOUT")
			state_col = HudPalette.TEXT_DIM
	else:
		var low := frac <= 0.25
		var mag_col := HudPalette.WARN if low else HudPalette.TEXT
		var mag := str(roundi(c.ammo))
		text(mag, Vector2(x + 14.0, top + 66.0), 44, mag_col, ctx.font_numbers)
		var mw := text_width(mag, 44, ctx.font_numbers)
		text("| %d" % c.reserve, Vector2(x + 22.0 + mw, top + 66.0), 22, HudPalette.TEXT_DIM, ctx.font_numbers)
		var n := maxi(c.ammo_capacity, 1)
		var tw := (W - 28.0) / n
		for i in n:
			draw_rect(Rect2(x + 14.0 + i * tw, top + 72.0, maxf(tw - 1.5, 1.0), 4.0),
				mag_col if i < roundi(c.ammo) else Color(1, 1, 1, 0.15))
		if reloading:
			state = tr("HUD_RELOADING")
		elif dry:
			state = tr("HUD_DRY")
		elif low:
			state = tr("HUD_RELOAD_PROMPT")
	if state != "":
		text(state, Vector2(x, top + 22.0), 15, state_col, ctx.font_display, HORIZONTAL_ALIGNMENT_RIGHT, W - 14.0)
	_mounts(client, Vector2(x + 14.0, top + 84.0))


func _mounts(client: ClientWorld, at: Vector2) -> void:
	var items := client.mount_items()
	var p := client.progress
	var bw := (W - 28.0 - 2.0 * 8.0) / 3.0
	for i in SnapshotData.ProgressState.MOUNT_SOCKETS.size():
		var r := Rect2(at + Vector2(i * (bw + 8.0), 0.0), Vector2(bw, 30.0))
		var item: ArmoryItemDef = items[i] if i < items.size() else null
		var socket: int = SnapshotData.ProgressState.MOUNT_SOCKETS[i]
		if item == null:
			draw_rect(r, Color(1, 1, 1, 0.3), false, 1.0)
			text(tr(SOCKET_KEYS.get(socket, "HUD_SOCKET_CORE")), r.position + Vector2(6.0, 20.0), 12, HudPalette.TEXT_OFF,
				ctx.font_display)
			continue
		draw_rect(r, Color(item.hue, 0.25))
		draw_rect(Rect2(r.position, Vector2(4.0, r.size.y)), item.hue)
		text(item.display_name, r.position + Vector2(10.0, 15.0), 12, HudPalette.TEXT, ctx.font_body,
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 14.0)
		var tier := p.mount_tier[i] if p != null else 0
		for k in item.tiers():
			draw_rect(Rect2(r.position + Vector2(10.0 + k * 11.0, 21.0), Vector2(8.0, 4.0)),
				HudPalette.LUMEN if k < tier else Color(1, 1, 1, 0.2))
