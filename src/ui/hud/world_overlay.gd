class_name WorldOverlay
extends HudWidget
## Screen-space overlay of world-anchored HUD (full viewport, not scaled; sizes
## multiply ctx.scale):
## - hero health plates (replace the old large Label3D "550 / 550"): a compact
##   bar whose width is clamped by distance (tuning plate_*), enemy = team
##   colour + diamond, only in line of sight; ally = team colour + chevron;
##   optional small HP number (settings.plate_numbers);
## - damage numbers (hud.md §13.2): Compact merges hits per target, Full per
##   hit, Off none; white body, yellow + "!" headshot.

var numbers: DamageNumberModel
var _los: Dictionary = {}  # enemy net id -> bool (refreshed on physics frames)


func bind(c: HudContext) -> void:
	super(c)
	numbers = DamageNumberModel.new(c.settings.damage_numbers, c.tuning.damage_merge_seconds,
		c.tuning.damage_number_seconds)


func on_hit(e: GameEvent) -> void:
	numbers.mode = ctx.settings.damage_numbers
	numbers.add(e.target_net_id, e.amount, (e.flags & GameEvent.FLAG_HEADSHOT) != 0,
		(e.flags & GameEvent.FLAG_KILL) != 0, e.position)


func _process(delta: float) -> void:
	numbers.advance(delta)
	super(delta)


func _physics_process(_delta: float) -> void:
	var c := ctx.client if ctx != null else null
	if c == null or c.rig == null or c.rig.camera == null or not c.is_inside_tree():
		return
	var space := c.get_world_3d().direct_space_state
	var from := c.rig.camera.global_position
	var views := c.remote_views()
	for id in views:
		var h := ctx.roster.hero(id)
		if h == null or h.team == ctx.own_team():
			continue
		var to: Vector3 = (views[id] as Node3D).global_position + Vector3(0.0, 1.5, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		if c.body != null:
			q.exclude = [c.body.get_rid()]
		_los[id] = space.intersect_ray(q).is_empty()


func _draw() -> void:
	var c := ctx.client
	if c == null or c.rig == null or c.rig.camera == null:
		return
	var cam := c.rig.camera
	if not ctx.scoreboard_open:
		_plates(c, cam)
	_numbers(c, cam)


func _plates(c: ClientWorld, cam: Camera3D) -> void:
	var t := ctx.tuning
	var s := ctx.scale
	var views := c.remote_views()
	for id in views:
		var h := ctx.roster.hero(id)
		var v := views[id] as Node3D
		if h == null or h.dead or not v.visible or h.max_hp <= 0:
			continue
		var enemy := h.team != ctx.own_team()
		var head := v.global_position + Vector3(0.0, t.plate_height_m, 0.0)
		var dist := cam.global_position.distance_to(head)
		if not NamePlateModel.is_visible(not enemy, _los.get(id, true), dist, t) or cam.is_position_behind(head):
			continue
		var k := clampf((dist - t.plate_near_m) / maxf(t.plate_far_m - t.plate_near_m, 0.01), 0.0, 1.0)
		var w := lerpf(t.plate_max_width, t.plate_min_width, k) * s
		var bh := maxf(4.0, 6.0 * s)
		var p := cam.unproject_position(head)
		var r := Rect2(p - Vector2(w * 0.5, bh * 0.5), Vector2(w, bh))
		var col := ctx.team_color(h.team)
		draw_rect(r, Color(HudPalette.INK_DEEP, 0.6))  # v0.12: ink track, no black frame
		var frac := clampf(float(h.hp) / h.max_hp, 0.0, 1.0)
		draw_rect(Rect2(r.position, Vector2(w * frac, bh)), col)
		var g := Vector2(r.position.x - 8.0 * s, r.get_center().y)
		if enemy:
			draw_colored_polygon(_diamond(g, 5.0 * s), Color(0, 0, 0, 0.7))
			draw_colored_polygon(_diamond(g, 4.0 * s), col)
		else:
			_chev(g, 5.0 * s, col)
		_name_label(h, id, Vector2(p.x, r.position.y - 3.0 * s), s)
		if ctx.settings.plate_numbers:
			var fs := maxi(10, roundi(12.0 * s))
			text(str(h.hp), Vector2(r.end.x + 4.0 * s, r.end.y + 1.0 * s), fs, HudPalette.TEXT, ctx.font_numbers)


## Player / hero name centred above the bar, with a small diamond per Mastery.
func _name_label(h: RosterTracker.Hero, id: int, anchor: Vector2, s: float) -> void:
	var n := h.name if h.name != "" else tr("HUD_HERO_N") % id
	var fs := maxi(10, roundi(ctx.tuning.plate_name_size * s))
	var masteries := NamePlateModel.mastery_count(h.fork_bits)
	var w := text_width(n, fs)
	var gw := masteries * 9.0 * s
	var x := anchor.x - (w + gw) * 0.5
	text(n, Vector2(x, anchor.y), fs, HudPalette.IVORY)
	for i in masteries:
		var gc := Vector2(x + w + 6.0 * s + i * 9.0 * s, anchor.y - fs * 0.35)
		draw_colored_polygon(_diamond(gc, 4.5 * s), Color(0, 0, 0, 0.8))
		draw_colored_polygon(_diamond(gc, 3.2 * s), HudPalette.CRIT)


func _numbers(c: ClientWorld, cam: Camera3D) -> void:
	var s := ctx.scale
	var lift := ctx.tuning.damage_number_lift_m
	var views := c.remote_views()
	for n in numbers.numbers:
		var anchor := n.world_pos
		var v := views.get(n.target_id) as Node3D
		if v != null:
			anchor = v.global_position + Vector3(0.0, ctx.tuning.plate_height_m + lift * 0.5, 0.0)
		if not UiKit.reduce_motion():  # v0.12: with reduce motion the number fades in place
			anchor += Vector3(0.0, 0.5 * n.age, 0.0)
		if cam.is_position_behind(anchor):
			continue
		var p := cam.unproject_position(anchor) + Vector2(18.0 * s, 0.0)
		var col := Color(HudPalette.CRIT if n.headshot else Color.WHITE, numbers.alpha(n))
		var fs := roundi((28.0 if n.headshot else 25.0) * s)  # v0.12: Chakra Petch 25
		text(DamageNumberModel.text_of(n), p, fs, col, ctx.font_numbers)


func _diamond(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])


func _chev(c: Vector2, r: float, col: Color) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(-r, r * 0.5), c + Vector2(0, -r * 0.5), c + Vector2(r, r * 0.5)]),
		Color(0, 0, 0, 0.7), 4.0, true)
	draw_polyline(PackedVector2Array([c + Vector2(-r, r * 0.5), c + Vector2(0, -r * 0.5), c + Vector2(r, r * 0.5)]),
		col, 2.0, true)
