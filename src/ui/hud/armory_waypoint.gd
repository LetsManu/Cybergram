class_name ArmoryWaypoint
extends HudWidget
## Guidance waypoint to the own Armory pad (W21-G2, design/ux/hud.md §10, §14):
## a brass chevron with "ARMORY 24 m" that tracks the pad's bearing across the
## top of the view and pins to the screen edge, pointing sideways, when the pad
## is off-screen. Shown only in the own base, off the pad, while alive and
## (the hero can afford something OR for the first seconds of the match);
## hidden in Sudden Death, at match end, in the shop and on the scoreboard by
## HudRoot.context_visibility. Reads replicated state only; the pure rules are
## static so they can be tested without a scene.

const CHEVRON: float = 11.0
const ARROWS: Array[String] = ["↑", "→", "↓", "←"]

## Tuning (ArmoryMarkerDef .tres).
var def: ArmoryMarkerDef
## Own ItemShopModel for the affordability test (state() over the catalog).
var model: ItemShopModel
## Seconds of "first spawn" guidance left (-1 = not started yet).
var spawn_left: float = -1.0
## Result of the last evaluation (tests, HudRoot).
var shown: bool = false
var distance_m: float = 0.0
var rel_angle: float = 0.0
var _econ: EconomyRulesDef
var _builds: RecommendedBuildsDef
var _t: float = 0.0
var _afford: bool = false
var _sig: int = -1
var _poll_t: float = 0.0
## Draw caches: label text per whole metre, its width, the chevron polygons.
var _label_m: int = -1
var _label: String = ""
var _label_w: float = 0.0
var _word: String = ""
var _tri: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _tri_in: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


func bind(c: HudContext) -> void:
	super(c)
	def = load(ArmoryMarkerDef.DEFAULT_PATH) as ArmoryMarkerDef
	_econ = load(GameSession.ECONOMY_RULES) as EconomyRulesDef
	_builds = load(RecommendedBuildsDef.active_path()) as RecommendedBuildsDef


# --- Pure rules -------------------------------------------------------------------

## Flat (XZ) distance between two world points.
static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Signed bearing (radians, +right, 0 = straight ahead) of `to` seen from `from`
## looking along `yaw` (0 = -Z, positive turns left, like InputCommand yaw).
static func relative_angle(yaw: float, from: Vector3, to: Vector3) -> float:
	var d := Vector2(to.x - from.x, to.z - from.z)
	if d.length_squared() < 0.0001:
		return 0.0
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	return atan2(d.dot(right), d.dot(fwd))


## Horizontal screen position of a bearing: returns [x, side] with side 0 when
## the bearing is inside the view, -1 / +1 when it is pinned to the left / right
## edge (off-screen or behind). `hfov_half` = half the horizontal FOV (radians).
static func screen_x(rel: float, hfov_half: float, width: float, margin_frac: float) -> Array:
	var lo := width * margin_frac
	var hi := width * (1.0 - margin_frac)
	if absf(rel) < PI * 0.5 - 0.01:
		var x := width * 0.5 + tan(rel) / maxf(tan(hfov_half), 0.01) * width * 0.5
		if x >= lo and x <= hi:
			return [x, 0]
	var side := 1 if rel >= 0.0 else -1
	return [hi if side > 0 else lo, side]


## Whether the waypoint shows. `first_spawn_left` > 0 is the match-start window.
static func should_show(dead: bool, at_pad: bool, in_base: bool, can_afford: bool, first_spawn_left: float) -> bool:
	return not dead and not at_pad and in_base and (can_afford or first_spawn_left > 0.0)


## True when `pos` is within `radius` (flat) of the own Sanctum.
static func in_own_base(pos: Vector3, sanctum: Vector3, radius: float) -> bool:
	return flat_distance(pos, sanctum) <= radius


## Arrow glyph for a bearing: ahead, right, behind or left.
static func arrow_for(rel: float) -> String:
	var a := absf(rel)
	if a < PI * 0.25:
		return ARROWS[0]
	if a > PI * 0.75:
		return ARROWS[2]
	return ARROWS[1] if rel > 0.0 else ARROWS[3]


## Direction suffix of the off-pad B hint: "24 m →".
static func hint_suffix(dist: float, rel: float) -> String:
	return "%d m %s" % [roundi(dist), arrow_for(rel)]


## Any catalog line the hero can buy right now (replicated Lumen, family, tier).
static func can_afford_any(m: ItemShopModel) -> bool:
	if m == null or m.catalog == null or m.progress == null:
		return false
	for i in m.catalog.items.size():
		if m.state(i) == ItemShopModel.State.AVAILABLE:
			return true
	return false


# --- Frame update ----------------------------------------------------------------

## Re-evaluates `shown`, `distance_m` and `rel_angle` from the client; returns `shown`.
func evaluate(delta: float) -> bool:
	shown = false
	var c := ctx.client if ctx != null else null
	if c == null or c.map_def == null or c.body == null or c.progress == null or c.catalog == null \
			or c.hero_def == null or def == null:
		return false
	var hq := c.map_def.hq(ctx.own_team())
	if hq == null:
		return false
	var dead := c.is_dead()
	if spawn_left < 0.0 and not dead:
		spawn_left = def.guide_spawn_s
	elif spawn_left > 0.0 and not dead:
		spawn_left = maxf(0.0, spawn_left - delta)
	if model == null:
		model = ItemShopModel.new()
	model.catalog = c.catalog
	model.rules = _econ
	model.builds = _builds
	model.hero_id = c.hero_def.id
	model.weapon = c.hero_def.weapon
	model.update(c.progress)
	var pos := c.body.global_position
	var at_pad := (c.progress.flags & SnapshotData.ProgressState.FLAG_AT_ARMORY) != 0
	var b := pad_bearing(c, ctx.own_team())
	distance_m = b.x
	rel_angle = b.y
	# can_buy over the whole catalog only when the progress changed or ~4 Hz.
	_poll_t -= delta
	var sig := progress_signature(c.progress)
	if sig != _sig or _poll_t <= 0.0:
		_sig = sig
		_poll_t = def.guide_poll_s
		_afford = can_afford_any(model)
	shown = should_show(dead, at_pad, in_own_base(pos, hq.sanctum, def.guide_base_radius_m), _afford, spawn_left)
	return shown


## Flat distance (m, x) and bearing (rad, y) from the own hero to the `team`
## Armory pad; x = -1 when the client has no body or map yet.
static func pad_bearing(c: ClientWorld, team: int) -> Vector2:
	if c == null or c.body == null or c.map_def == null:
		return Vector2(-1.0, 0.0)
	var hq := c.map_def.hq(team)
	if hq == null:
		return Vector2(-1.0, 0.0)
	var pos := c.body.global_position
	var yaw := c.body.look_yaw
	if c.rig != null and c.rig.camera != null:
		yaw = c.rig.camera.global_rotation.y
	return Vector2(flat_distance(pos, hq.armory), relative_angle(yaw, pos, hq.armory))


## Distance and arrow of the own pad for the off-pad B hint ("" when unknown).
static func hint_for(c: ClientWorld, team: int) -> String:
	var b := pad_bearing(c, team)
	return hint_suffix(b.x, b.y) if b.x >= 0.0 else ""


## Cheap fingerprint of everything in the replicated progress that changes what
## can be bought (Lumen, inventory, owned lines, Med-Packs): re-check affordability on change.
static func progress_signature(p: SnapshotData.ProgressState) -> int:
	var h := p.lumen * 31 + p.owned_bits * 17 + p.medpacks * 7 + p.level
	for i in p.inv_items.size():
		h = h * 31 + p.inv_items[i] * 5
	return h


func _process(delta: float) -> void:
	_t += delta
	if visible:
		evaluate(delta)
		queue_redraw()


func _draw() -> void:
	if not shown or ctx == null or ctx.client == null:
		return
	var c := ctx.client
	var gs := GameSettings.shared()
	var fov_v := deg_to_rad(c.rig.camera.fov) if c.rig != null and c.rig.camera != null else deg_to_rad(80.0)
	var vp := get_viewport().get_visible_rect().size
	var hfov_half := atan(tan(fov_v * 0.5) * vp.x / maxf(vp.y, 1.0))
	var sx := screen_x(rel_angle, hfov_half, size.x, def.guide_edge_margin)
	var x: float = sx[0]
	var side: int = sx[1]
	var y := size.y * 0.5
	var bob := 0.0 if gs != null and gs.reduce_motion else sin(_t * 4.0) * 2.0
	var col := HudPalette.BRASS_HI
	var p := Vector2(x, y + bob)
	if side == 0:
		_tri[0] = p + Vector2(-CHEVRON, -CHEVRON * 0.6)
		_tri[1] = p + Vector2(CHEVRON, -CHEVRON * 0.6)
		_tri[2] = p + Vector2(0.0, CHEVRON * 0.7)
	else:
		var s := float(side)
		_tri[0] = p + Vector2(CHEVRON * s, 0.0)
		_tri[1] = p + Vector2(-CHEVRON * 0.6 * s, -CHEVRON)
		_tri[2] = p + Vector2(-CHEVRON * 0.6 * s, CHEVRON)
	for i in 3:
		_tri_in[i] = _tri[i] * 0.8 + p * 0.2
	draw_colored_polygon(_tri, Color(0.0, 0.0, 0.0, 0.6))
	draw_colored_polygon(_tri_in, col)
	var m := roundi(distance_m)
	if m != _label_m:
		_label_m = m
		if _word == "":
			_word = tr("HUD_ARMORY_WAYPOINT")
		_label = "%s %d m" % [_word, m]
		_label_w = caps_width(_label, 18)
	var tx := clampf(x - _label_w * 0.5, 8.0, size.x - _label_w - 8.0)
	caps(_label, Vector2(tx, y + 38.0), 18, col, 0.16)
