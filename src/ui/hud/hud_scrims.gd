class_name HudScrims
extends HudWidget
## v0.12 readability scrims (design/ux/hud-v0.12.md §1 "No boxes"): a soft ink
## band at the top (225 design px, 62% fading to 0) and at the bottom (285
## design px, 0 to 66%) of the HUD canvas, under every widget. HudRoot toggles
## `top` / `bottom` per context (hud.md §14).

const TOP_H: float = 225.0
const BOTTOM_H: float = 285.0
const TOP_A: float = 0.62
const BOTTOM_A: float = 0.66

const BACKDROP_SHADER := "res://assets/shaders/canvas_hud_backdrop.gdshader"
enum Backdrop { NONE, DEAD, OVERLAY, END }
## [saturation, brightness, blur lod] per Backdrop (hud-v0.12.md §2: death is
## greyscale at 45%; Tab / Armory blur 4 px + dim; match end blur 3 px, 50%, 60% sat).
const BACKDROPS: Array = [[1.0, 1.0, 0.0], [0.1, 0.45, 0.6], [1.0, 0.6, 2.2], [0.6, 0.5, 1.8]]

var top: bool = true
var bottom: bool = true
var backdrop: int = Backdrop.NONE
var _fx: ColorRect
## The backdrop sits in its own layer under the HUD (HudRoot is layer 5,
## ComfortOverlay 4), so only the game is greyed / blurred, never the HUD.
const BACKDROP_LAYER := 3


func _ready() -> void:
	var cl := CanvasLayer.new()
	cl.layer = BACKDROP_LAYER
	add_child(cl)
	_fx = ColorRect.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load(BACKDROP_SHADER) as Shader
	_fx.material = m
	_fx.visible = false
	cl.add_child(_fx)


## Screen treatment behind the HUD (Backdrop). Static with reduce motion: it
## switches instantly either way.
func set_backdrop(b: int) -> void:
	if _fx == null:
		return
	_fx.size = get_viewport_rect().size
	_fx.position = Vector2.ZERO
	if b == backdrop:
		return
	backdrop = b
	_fx.visible = b != Backdrop.NONE
	var v: Array = BACKDROPS[b]
	var m := _fx.material as ShaderMaterial
	m.set_shader_parameter("saturation", v[0])
	m.set_shader_parameter("brightness", v[1])
	m.set_shader_parameter("blur_lod", v[2])


func _process(_delta: float) -> void:
	pass  # static: redrawn only when a flag or the size changes


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func set_flags(t: bool, b: bool) -> void:
	if t != top or b != bottom:
		top = t
		bottom = b
		queue_redraw()


func _draw() -> void:
	if top:
		scrim(Rect2(0.0, 0.0, size.x, TOP_H), TOP_A, 0.0)
	if bottom:
		scrim(Rect2(0.0, size.y - BOTTOM_H, size.x, BOTTOM_H), 0.0, BOTTOM_A)
