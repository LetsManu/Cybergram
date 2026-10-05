class_name ComfortOverlay
extends CanvasLayer
## Comfort overlay (W16-COMFORT; receives `session` like the other overlays):
##  - damage feedback: a direction indicator (arc on a ring around the centre
##    pointing at the attacker, following the view) and a red damage vignette,
##    both scaled by Screen effects intensity (DamageFeedbackModel). The attacker
##    is found without a protocol change: SHOT events go to every client, so an
##    HP drop is attributed to the other hero whose shot stopped at our body.
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
var _shots: Array = []  # {src: int, pos: Vector3, t: float}
var _pending: Array = []  # {amount: float, max_hp: float, t: float}
var _hooked: Object
var _dot: _Dot
var _dot_top: _Dot
var _top_layer: CanvasLayer


## A Control that draws the dot from the settings.
class _Dot extends Control:
	var gs: GameSettings
	var on_menu_only: bool = false
	var active: bool = true

	func _draw() -> void:
		if gs == null or not gs.comfort_center_dot or not active:
			return
		draw_circle(size * 0.5, gs.comfort_dot_size_px * 0.5, Color(1, 1, 1, gs.comfort_dot_opacity))


## Draws the damage direction indicator arcs.
class _Ring extends Control:
	var owner_overlay: Node
	var fx: float = 1.0
	var reduce: bool = false
	var own_pos: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var active: bool = false

	func _draw() -> void:
		var o := owner_overlay
		if o == null or not active:
			return
		var m: DamageFeedbackModel = o.feedback
		var c := size * 0.5
		var r := m.rules.indicator_ring_radius * size.y
		for ind in m.indicators:
			var a := m.indicator_alpha(ind, fx, reduce)
			if a <= 0.01:
				continue
			var w := m.indicator_width_px(ind, fx, reduce)
			var col := Color(HudPalette.DANGER, a)
			var dark := Color(0, 0, 0, a * 0.55)
			if ind.has_dir:
				var mid := DamageFeedbackModel.relative_angle(own_pos, yaw, ind.pos) - PI * 0.5  # 0 = up on screen
				var half := m.indicator_half_arc_rad(ind)
				draw_arc(c, r, mid - half, mid + half, 24, dark, w + 3.0, true)
				draw_arc(c, r, mid - half, mid + half, 24, col, w, true)
			else:  # environment / unattributed: a thin full ring pulse
				draw_arc(c, r, 0.0, TAU, 64, dark, w * 0.5 + 2.0, true)
				draw_arc(c, r, 0.0, TAU, 64, Color(col, a * 0.8), w * 0.5, true)


func _ready() -> void:
	layer = LAYER_UNDER_HUD
	feedback = DamageFeedbackModel.new(rules)
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


## Detects own HP drops, attributes them (see header) and drives the model.
func _damage_feedback(delta: float, client: Variant, gs: GameSettings) -> void:
	var fx := gs.comfort_fx_intensity
	var reduce := gs.reduce_motion
	if client != null and client.body != null and client.combat != null:
		if _hooked != client:
			_hooked = client
			client.shot_received.connect(_on_shot)
		var hp: int = client.combat.hp
		if _prev_hp >= 0 and hp < _prev_hp and not client.is_dead():
			_pending.append({"amount": float(_prev_hp - hp), "max_hp": float(client.combat.max_hp), "t": 0.0})
		_prev_hp = hp
		var own: Vector3 = client.body.state.position + Vector3(0.0, _EYE_H, 0.0)
		for p in _pending:
			p.t += delta
		while not _pending.is_empty() and _pending[0].t >= rules.attribution_delay_s:
			var p: Dictionary = _pending.pop_front()
			feedback.hit(p.amount, p.max_hp, _attacker_of(client, own))
		_ring.own_pos = own
		_ring.yaw = client.rig.rotation.y if client.rig != null else 0.0
		_debug_damage(client, own)
	_ring.active = client != null and client.body != null
	for s in _shots:
		s.t += delta
	while not _shots.is_empty() and _shots[0].t > rules.shot_memory_s:
		_shots.pop_front()
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


func _on_shot(e: GameEvent) -> void:
	_shots.append({"src": e.source_net_id, "pos": e.position, "t": 0.0})


## Attacker position of the latest other-hero shot that stopped at our body, or
## null (environment, Wardling, ability or self damage: non-directional).
func _attacker_of(client: Variant, own: Vector3) -> Variant:
	var own_id: int = client.session.own_net_id
	for i in range(_shots.size() - 1, -1, -1):
		var s: Dictionary = _shots[i]
		if s.src == own_id or s.src == 0:
			continue
		if (s.pos as Vector3).distance_to(own) <= rules.attribution_radius_m:
			var at: Variant = client.hero_view_position(s.src)
			if at != null:
				return at
	return null


var _debug_t: float = 0.0


func _debug_damage(client: Variant, own: Vector3) -> void:
	if debug_damage == "":
		return
	_debug_t -= get_process_delta_time()
	if _debug_t > 0.0:
		return
	_debug_t = 0.35
	var yaw: float = client.rig.rotation.y if client.rig != null else 0.0
	var rel := {"front": 0.0, "right": PI * 0.5, "back": PI, "left": -PI * 0.5}
	if rel.has(debug_damage):
		feedback.hit(60.0, 250.0, DamageFeedbackModel.world_pos_at(own, yaw, rel[debug_damage]))
	else:
		feedback.hit(60.0, 250.0, null)
