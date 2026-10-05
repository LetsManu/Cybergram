class_name ComfortOverlay
extends CanvasLayer
## Comfort overlay (W16-COMFORT; receives `session` like the other overlays):
##  - damage feedback: a direction indicator (arc on a ring around the centre
##    pointing at the attacker, following the view) and a red damage vignette,
##    both scaled by Screen effects intensity (DamageFeedbackModel). The attacker
##    is found without a protocol change (DamageAttribution): hero shots, mana
##    bolts, ability areas / lines / projectiles, melee Wardlings and instant
##    casts, all from events and snapshots the client already gets. Only true
##    environment damage (fall, Sudden Death ring, Leyfall) shows the plain ring.
##  - the comfort vignette (soft edge darkening during fast / forced moves),
##  - the fixed centre dot, drawn at the exact screen centre UNDER the HUD
##    crosshair (this layer sits below HudRoot), also while dead or spectating.
## A second layer above the pause menu redraws the dot while it is open, so the
## dot stays visible in menus over gameplay. Reads ClientWorld; no gameplay writes.

const SHADER := "res://assets/shaders/canvas_fx_comfort_vignette.gdshader"
const LAYER_UNDER_HUD := 4
const LAYER_OVER_MENU := 61

var session: Node
## Injectable for tests; null = process-wide settings.
var settings: GameSettings
var rules: ComfortRulesDef = ComfortRulesDef.load_default()
var model: ComfortVignetteModel
## Debug (evidence): force the vignette level (-1 = off), `--comfort-vignette`.
var debug_level: float = -1.0

var feedback: DamageFeedbackModel
## Debug (evidence): `--debug-damage left|right|front|back|env` re-fires a hit.
var debug_damage: String = ""

var _vig: ColorRect
var _dmg: ColorRect
var _ring: _Ring
var _prev_hp: int = -1
var _shots: Array = []  # {src: int, impact: Vector3, t: float}
var _bolts: Array = []  # {from, to, t}
var _fx: Array = []  # enemy ability FX seen recently: {kind, team, pos, pos2, t}
var _wardlings: Array = []  # latest snapshot: {pos, team, combat}
var _casts: Array = []  # {src: int, pos: Vector3, t}
var _pending: Array = []  # {amount: float, max_hp: float, t: float}
var _hooked: Object
## HUD colour-blind preset source (re-read twice a second: F6 saves the file).
var hud_settings: HudSettings = HudSettings.new()
var _hud_t: float = 0.0
var _dot: _Dot
var _dot_top: _Dot
# --- W19-HUD ---
var _edge: _Edge
var _edge_vig: ColorRect
## Low-HP threshold (HudTuningDef.low_hp_frac).
var low_hp_frac: float = 0.25


## Static 3 px edge line in the warning colour (low HP / outside the ring).
class _Edge extends Control:
	var col: Color = Color(0, 0, 0, 0)

	func _draw() -> void:
		if col.a <= 0.01:
			return
		draw_rect(Rect2(Vector2.ZERO, size).grow(-1.5), col, false, 3.0)
# --- end W19-HUD ---
var _top_layer: CanvasLayer


## A Control that draws the dot from the settings.
class _Dot extends Control:
	var gs: GameSettings
	var on_menu_only: bool = false
	var active: bool = true

	func _draw() -> void:
		if gs == null or not gs.comfort_center_dot or not active:
			return
		# W19-HUD v0.12: brass-hi with a 1 px ink outline (size / opacity stay the player's).
		draw_circle(size * 0.5, gs.comfort_dot_size_px * 0.5 + 1.0, Color(HudPalette.INK_DEEP, 0.8 * gs.comfort_dot_opacity))
		draw_circle(size * 0.5, gs.comfort_dot_size_px * 0.5, Color(HudPalette.BRASS_HI, gs.comfort_dot_opacity))


## Draws the damage direction indicator arcs.
class _Ring extends Control:
	var owner_overlay: Node
	var fx: float = 1.0
	var reduce: bool = false
	var own_pos: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var active: bool = false
	## Warning colour of the HUD colour-blind preset (HudPalette.damage_color).
	var base_color: Color = HudPalette.DANGER

	func _draw() -> void:
		var o := owner_overlay
		if o == null or not active:
			return
		var m: DamageFeedbackModel = o.feedback
		var c := size * 0.5
		var r := m.rules.indicator_ring_radius * size.y
		# --- W19-HUD v0.12: 1 px ivory 8% guide ring while an indicator shows ---
		var guide := 0.0
		for ind in m.indicators:
			guide = maxf(guide, m.indicator_alpha(ind, fx, reduce))
		if guide > 0.01:
			draw_arc(c, r, 0.0, TAU, 96, Color(HudPalette.IVORY, 0.08 * minf(guide * 2.0, 1.0)), 1.0, true)
		# --- end W19-HUD ---
		for ind in m.indicators:
			var a := m.indicator_alpha(ind, fx, reduce)
			if a <= 0.01:
				continue
			var w := m.indicator_width_px(ind, fx, reduce)
			var col := Color(base_color, a)
			var dark := Color(0, 0, 0, a * 0.55)
			if ind.has_dir:
				var mid := DamageFeedbackModel.relative_angle(own_pos, yaw, ind.pos) - PI * 0.5  # 0 = up on screen
				var half := m.indicator_half_arc_rad(ind)
				draw_arc(c, r, mid - half, mid + half, 24, Color(dark, dark.a * 0.6), w + 3.0, true)
				_faded_arc(c, r, mid - half, mid + half, col, w)  # W19-HUD: fades at both ends
				# Shape cue (direction never relies on colour alone): a chevron at the
				# arc centre pointing outward toward the attacker.
				var dir := Vector2(cos(mid), sin(mid))
				var perp := Vector2(-dir.y, dir.x)
				var base := c + dir * (r + w * 0.5 + 5.0)
				var tip := c + dir * (r + w * 0.5 + 5.0 + 12.0 + w)
				var wing := 6.0 + w * 0.6
				var pts := PackedVector2Array([base + perp * wing, tip, base - perp * wing])
				draw_polyline(pts, dark, 5.0, true)
				draw_polyline(pts, col, 3.0, true)
			else:  # environment / unattributed: a thin full ring pulse
				draw_arc(c, r, 0.0, TAU, 64, dark, w * 0.5 + 2.0, true)
				draw_arc(c, r, 0.0, TAU, 64, Color(col, a * 0.8), w * 0.5, true)


	## W19-HUD v0.12: the arc in `col`, fully opaque in the middle third and
	## fading to 0 at both ends (one polyline with per-point colours).
	func _faded_arc(c: Vector2, r: float, a0: float, a1: float, col: Color, w: float) -> void:
		var n := 24
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		pts.resize(n + 1)
		cols.resize(n + 1)
		for k in n + 1:
			var t := float(k) / n
			var a := lerpf(a0, a1, t)
			pts[k] = c + Vector2(cos(a), sin(a)) * r
			cols[k] = Color(col, col.a * clampf(minf(t, 1.0 - t) * 3.0, 0.0, 1.0))
		draw_polyline_colors(pts, cols, w, true)


func _ready() -> void:
	layer = LAYER_UNDER_HUD
	feedback = DamageFeedbackModel.new(rules)
	hud_settings = HudSettings.load_user(OS.get_cmdline_user_args())
	var dd := OS.get_cmdline_user_args().find("--debug-damage")
	if dd >= 0 and dd + 1 < OS.get_cmdline_user_args().size():
		debug_damage = OS.get_cmdline_user_args()[dd + 1]
	model = ComfortVignetteModel.new(rules)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--comfort-vignette")
	if i >= 0 and i + 1 < args.size():
		debug_level = float(args[i + 1])
	_vig = ColorRect.new()
	_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = load(SHADER) as Shader
	m.set_shader_parameter("tint", Vector3(HudPalette.INK.r, HudPalette.INK.g, HudPalette.INK.b))  # W19-HUD: ink, not black
	_vig.material = m
	_vig.visible = false
	add_child(_vig)
	_dmg = ColorRect.new()
	_dmg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dm := ShaderMaterial.new()
	dm.shader = load(SHADER) as Shader
	dm.set_shader_parameter("tint", Vector3(0.75, 0.04, 0.03))
	_dmg.material = dm
	_dmg.visible = false
	add_child(_dmg)
	# --- W19-HUD v0.12: low-HP / outside-the-ring edge (soft red vignette + a
	# static 3 px edge line, no flash; scaled by Screen effects, off at 0%) ---
	_edge = _Edge.new()
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var em := ShaderMaterial.new()
	em.shader = load(SHADER) as Shader
	_edge_vig = ColorRect.new()
	_edge_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_vig.material = em
	_edge_vig.visible = false
	add_child(_edge_vig)
	add_child(_edge)
	# --- end W19-HUD ---
	_ring = _Ring.new()
	_ring.owner_overlay = self
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)
	_dot = _make_dot(self)
	_top_layer = CanvasLayer.new()
	_top_layer.layer = LAYER_OVER_MENU
	add_child(_top_layer)
	_dot_top = _make_dot(_top_layer)
	_dot_top.active = false


func _make_dot(parent: Node) -> _Dot:
	var d := _Dot.new()
	d.gs = _gs()
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(d)
	return d


func _gs() -> GameSettings:
	return settings if settings != null else GameSettings.shared()


func _process(delta: float) -> void:
	var gs := _gs()
	var client: Variant = session.get("client") if session != null else null
	var paused := false
	var vel := Vector3.ZERO
	var forced := false
	if client != null and client.body != null:
		vel = client.body.state.velocity
		forced = client.body.state.dash_ticks > 0
		if client.combat != null:
			forced = forced or (client.combat.status & (StatusComponent.BIT_DASHING | StatusComponent.BIT_KNOCKBACK)) != 0
		if client.player_input != null:
			paused = client.player_input.paused
	_damage_feedback(delta, client, gs)
	_low_edge(client, gs)  # W19-HUD
	model.step(delta, vel, forced)
	var a := model.alpha(gs.comfort_vignette)
	if debug_level >= 0.0:
		a = debug_level * rules.vignette_max_alpha
	_vig.visible = a > 0.002
	if _vig.visible:
		var m := _vig.material as ShaderMaterial
		m.set_shader_parameter("alpha", a)
		m.set_shader_parameter("inner", rules.vignette_inner_radius)
	# A CanvasLayer has no Control parent, so anchors resolve to size 0: size by hand.
	var vp := get_viewport().get_visible_rect().size
	_vig.size = vp
	_dmg.size = vp
	_edge.size = vp
	_edge_vig.size = vp
	_ring.size = vp
	_dot.size = vp
	_dot_top.size = vp
	_dot.gs = gs
	_dot_top.gs = gs
	_dot_top.active = paused
	_dot.active = not paused
	_dot.queue_redraw()
	_dot_top.queue_redraw()


const _EYE_H: float = 1.0


# --- W19-HUD v0.12 (hud-v0.12.md §2 "Low HP", "Ring warning", §3 effects 0%) ---
## Edge treatment: low HP (≤ low_hp_frac) or outside the Sudden Death ring.
func _low_edge(client: Variant, gs: GameSettings) -> void:
	var a := 0.0
	if client != null and client.combat != null and not client.is_dead():
		var cb = client.combat
		if float(cb.hp) / maxf(1.0, cb.max_hp) <= low_hp_frac:
			a = 0.38
		if client.body != null and client.sudden_death != null and client.sudden_death.is_outside(client.body.state.position):
			a = maxf(a, 0.32)
	a *= clampf(gs.comfort_fx_intensity, 0.0, 1.0)
	var warn := HudPalette.damage_color(hud_settings.colorblind)
	_edge_vig.visible = a > 0.002
	if _edge_vig.visible:
		var m := _edge_vig.material as ShaderMaterial
		m.set_shader_parameter("alpha", a)
		m.set_shader_parameter("inner", 0.5)
		m.set_shader_parameter("tint", Vector3(warn.r, warn.g, warn.b))
	var ec := Color(warn, 0.5 * a / 0.38) if a > 0.0 else Color(0, 0, 0, 0)
	if ec != _edge.col:
		_edge.col = ec
		_edge.queue_redraw()
# --- end W19-HUD ---


## Detects own HP drops, attributes them (see header) and drives the model.
func _damage_feedback(delta: float, client: Variant, gs: GameSettings) -> void:
	var fx := gs.comfort_fx_intensity
	var reduce := gs.reduce_motion
	_hud_t -= delta
	if _hud_t <= 0.0:
		_hud_t = 0.5
		hud_settings = HudSettings.load_user(OS.get_cmdline_user_args())
	var warn := HudPalette.damage_color(hud_settings.colorblind)
	_ring.base_color = warn
	if client != null and client.body != null and client.combat != null:
		if _hooked != client:
			_hooked = client
			client.shot_received.connect(_on_shot)
			client.skill_cast_received.connect(_on_cast)
			client.session.snapshot_received.connect(_on_snapshot)
		var hp: int = client.combat.hp
		if _prev_hp >= 0 and hp < _prev_hp and not client.is_dead():
			_pending.append({"amount": float(_prev_hp - hp), "max_hp": float(client.combat.max_hp), "t": 0.0})
		_prev_hp = hp
		var own: Vector3 = client.body.state.position + Vector3(0.0, _EYE_H, 0.0)
		for p in _pending:
			p.t += delta
		while not _pending.is_empty() and _pending[0].t >= rules.attribution_delay_s:
			var p: Dictionary = _pending.pop_front()
			var src: Variant = _attacker_of(client, own)
			if src == null:
				src = SuddenDeathView.safe_point(client, own)  # W16-SDWATER: ring damage points back to safety
			feedback.hit(p.amount, p.max_hp, src)
		_ring.own_pos = own
		_ring.yaw = client.rig.rotation.y if client.rig != null else 0.0
		_debug_damage(client, own)
	_ring.active = client != null and client.body != null
	for list in [_shots, _bolts, _fx, _casts]:
		for e in list:
			e.t += delta
		while not list.is_empty() and list[0].t > rules.shot_memory_s:
			list.pop_front()
	feedback.step(delta)
	_ring.fx = fx
	_ring.reduce = reduce
	_ring.queue_redraw()
	var a := feedback.vignette_alpha(fx, reduce)
	_dmg.visible = a > 0.002
	if _dmg.visible:
		var m := _dmg.material as ShaderMaterial
		m.set_shader_parameter("alpha", a)
		m.set_shader_parameter("inner", feedback.vignette_inner(fx))
		m.set_shader_parameter("tint", Vector3(warn.r, warn.g, warn.b) * 0.8)


func _on_shot(e: GameEvent) -> void:
	_shots.append({"src": e.source_net_id, "impact": e.position, "t": 0.0})


func _on_cast(e: GameEvent) -> void:
	_casts.append({"src": e.source_net_id, "pos": e.position, "t": 0.0})


func _on_snapshot(s: SnapshotData) -> void:
	for b in s.bolts:
		_bolts.append({"from": b[0], "to": b[1], "t": 0.0})
	for f in s.fx:
		_fx.append({"kind": f.kind, "team": f.team, "pos": f.position, "pos2": f.position2, "t": 0.0})
	_wardlings.clear()
	for w in s.wardlings:
		_wardlings.append({"pos": w.position, "team": w.team, "combat": ((w.state >> 3) & WardlingSim.FLAG_COMBAT) != 0})


## Builds the DamageAttribution observations (enemy heroes only for shots / casts).
func _observations(client: Variant) -> Dictionary:
	var own_id: int = client.session.own_net_id
	var team: int = client.own_team()
	var shots: Array = []
	for sh in _shots:
		var at: Variant = _enemy_pos(client, sh.src, own_id, team)
		if at != null:
			shots.append({"pos": at, "impact": sh.impact})
	var casts: Array = []
	for c in _casts:
		if c.src != own_id and _is_enemy(client, c.src, team):
			casts.append({"pos": c.pos})
	var obs := {"shots": shots, "bolts": _bolts, "fx": _fx.duplicate(), "wardlings": _wardlings.duplicate(), "casts": casts}
	var enemy := 1 - team
	match debug_damage:  # evidence: synthetic sources placed relative to the view
		"wardling-left":
			obs.wardlings.append({"pos": DamageFeedbackModel.world_pos_at(_ring.own_pos, _ring.yaw, -PI * 0.5, 2.0),
				"team": enemy, "combat": true})
		"ability-back":
			obs.fx.append({"kind": AbilityWorld.FX_CIRCLE, "team": enemy, "pos2": Vector3(5.0, 0.0, 0.0),
				"pos": DamageFeedbackModel.world_pos_at(_ring.own_pos, _ring.yaw, PI, 3.0)})
	return obs


func _is_enemy(client: Variant, id: int, team: int) -> bool:
	var v: Variant = client.view(id)
	return v != null and v.team != team


func _enemy_pos(client: Variant, id: int, own_id: int, team: int) -> Variant:
	if id == own_id or id == 0 or not _is_enemy(client, id, team):
		return null
	return client.hero_view_position(id)


## Attacker position of the source that did the damage, or null for environment.
func _attacker_of(client: Variant, own: Vector3) -> Variant:
	var r := DamageAttribution.resolve(own, client.own_team(), _observations(client), rules)
	return r.pos if r.kind != DamageAttribution.Kind.NONE else null


var _debug_t: float = 0.0


func _debug_damage(client: Variant, own: Vector3) -> void:
	if debug_damage == "":
		return
	_debug_t -= get_process_delta_time()
	if _debug_t > 0.0:
		return
	_debug_t = 0.35
	var yaw: float = client.rig.rotation.y if client.rig != null else 0.0
	if debug_damage in ["wardling-left", "ability-back"]:
		_pending.append({"amount": 60.0, "max_hp": 250.0, "t": 0.0})
		return
	var rel := {"front": 0.0, "right": PI * 0.5, "back": PI, "left": -PI * 0.5}
	if rel.has(debug_damage):
		feedback.hit(60.0, 250.0, DamageFeedbackModel.world_pos_at(own, yaw, rel[debug_damage]))
	else:
		feedback.hit(60.0, 250.0, null)
