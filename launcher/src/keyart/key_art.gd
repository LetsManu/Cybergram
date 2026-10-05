class_name KeyArt
extends Node
## Live key art for the Home page: each hero is a short looping Ogg Theora
## video (assets/keyart/<hero>.ogv, the game's rigged hero playing its
## `showcase` idle, rendered by tools/art/make_keyart_loops.sh) with a subtle
## mouse parallax. The videos have a black background and are blended
## additively, so only the hero shows over the launcher backdrop.
## With reduce motion on (the launcher option or the game's own
## accessibility setting) or when a video is missing, the static portrait
## stays and nothing moves.
##
## Example:
##   var ka := KeyArt.new()
##   parent.add_child(ka)
##   ka.add_layer(portrait_rect, "sable", 1.0)

## Largest parallax shift in px at depth 1.0.
const PARALLAX_PX: float = 14.0
const VIDEO_DIR: String = "res://assets/keyart"
## Video frame aspect (width / height) of the encoded loops.
const VIDEO_ASPECT: float = 0.686

var reduce_motion: bool = false
var _layers: Array[Dictionary] = []
var _offset: Vector2 = Vector2.ZERO


## True when motion must be avoided: the launcher kit flag, or the game's
## settings file [accessibility] reduce_motion in `game_dir`.
static func motion_reduced(game_dir: String) -> bool:
	if UiKit.reduce_motion():
		return true
	if game_dir == "":
		return false
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(game_dir.path_join("settings.cfg")) != OK:
		return false
	return bool(cfg.get_value("accessibility", "reduce_motion", false))


## Puts a looping video over `poster` (a TextureRect already placed). Returns
## the player, or null when staying static.
func add_layer(poster: Control, stem: String, depth: float) -> VideoStreamPlayer:
	var path: String = VIDEO_DIR.path_join(stem + ".ogv")
	var layer: Dictionary = {"poster": poster, "base": poster.position, "depth": depth, "video": null}
	_layers.append(layer)
	if reduce_motion or not ResourceLoader.exists(path):
		return null
	var stream: VideoStream = load(path) as VideoStream
	if stream == null:
		return null
	var vp: VideoStreamPlayer = VideoStreamPlayer.new()
	vp.stream = stream
	vp.loop = true
	vp.expand = true
	vp.volume_db = -80.0
	vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	vp.material = mat
	vp.modulate = Color(1, 1, 1, poster.modulate.a)
	poster.get_parent().add_child(vp)
	poster.get_parent().move_child(vp, poster.get_index() + 1)
	_fit(vp, poster)
	layer["rect"] = Rect2(vp.offset_left, vp.offset_top, vp.offset_right - vp.offset_left, vp.offset_bottom - vp.offset_top)
	poster.modulate.a = 0.0  # the video replaces the still (kept as the fallback)
	vp.play()
	layer["video"] = vp
	return vp


func _fit(vp: VideoStreamPlayer, poster: Control) -> void:
	var h: float = poster.size.y if poster.size.y > 0.0 else poster.offset_bottom - poster.offset_top
	var w: float = h * VIDEO_ASPECT
	vp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	var cx: float = (poster.offset_left + poster.offset_right) * 0.5
	vp.offset_left = cx - w * 0.5
	vp.offset_right = cx + w * 0.5
	vp.offset_top = poster.offset_top
	vp.offset_bottom = poster.offset_bottom


func _process(delta: float) -> void:
	if reduce_motion or _layers.is_empty() or not is_inside_tree():
		return
	var vp: Viewport = get_viewport()
	var size: Vector2 = vp.get_visible_rect().size
	var m: Vector2 = vp.get_mouse_position()
	var target: Vector2 = ((m / size) - Vector2(0.5, 0.5)).clampf(-0.5, 0.5) * 2.0
	_offset = _offset.lerp(target, clampf(delta * 4.0, 0.0, 1.0))
	for l in _layers:
		var v: Variant = l["video"]
		if v == null:
			continue
		var shift: Vector2 = _offset * PARALLAX_PX * float(l["depth"])
		var c: Control = v as Control
		var base: Rect2 = l["rect"]
		c.offset_left = base.position.x + shift.x
		c.offset_right = base.position.x + base.size.x + shift.x
		c.offset_top = base.position.y + shift.y
		c.offset_bottom = base.position.y + base.size.y + shift.y
