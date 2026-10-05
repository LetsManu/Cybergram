class_name ComfortOverlay
extends CanvasLayer
## Comfort overlay (W16-COMFORT; receives `session` like the other overlays):
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

var _vig: ColorRect
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


func _ready() -> void:
	layer = LAYER_UNDER_HUD
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
	model.step(delta, vel, forced)
	var a := model.alpha(gs.comfort_vignette)
	if debug_level >= 0.0:
		a = debug_level * rules.vignette_max_alpha
	_vig.visible = a > 0.002
	if _vig.visible:
		var m := _vig.material as ShaderMaterial
		m.set_shader_parameter("alpha", a)
		m.set_shader_parameter("inner", rules.vignette_inner_radius)
	_dot.gs = gs
	_dot_top.gs = gs
	_dot_top.active = paused
	_dot.active = not paused
	_dot.queue_redraw()
	_dot_top.queue_redraw()
