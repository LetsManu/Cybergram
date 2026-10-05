class_name HeroShowcase
extends Control
## Main-menu hero banner (design/ux/ui-kit.md §8.1): the selected hero's 3D
## model (HeroModelBuilder, the same builder the match uses) in ONE
## SubViewport on a lit pedestal with a slow turntable, the hero's name, role
## and weapon, prev / next arrows and a strip of hero badges. Reduce motion
## stops the turntable. Display only: emits `hero_changed`; the menu stores
## the pick.
##
## Example:
##   var sc := HeroShowcase.new()
##   sc.heroes = HeroCatalog.entries()
##   sc.hero_changed.connect(func(i): _hero_index = i)

signal hero_changed(index: int)

## Role line per hero stem (heroes.md §2 table).
const ROLE_KEYS := {
	"vesper_loom": "HUD_ROLE_COMMANDER", "sable": "HUD_ROLE_INFILTRATOR", "juniper_quill": "HUD_ROLE_TRAPPER",
	"ryker_vance": "HUD_ROLE_SOLDIER", "brannoc": "HUD_ROLE_TANK", "liora_vale": "HUD_ROLE_HEALER",
	"hex": "HUD_ROLE_HACKER",
}
const HERO_DIR := "res://assets/data/heroes"
## Badge strip button side (px).
const BADGE := 44

## HeroCatalog.entries() (set before adding to the tree).
var heroes: Array = []
## Index into `heroes`.
var selected: int = 0
## Render the 3D model (tests / headless may turn it off).
var with_model: bool = true

var _vp: SubViewport
var _vpc: SubViewportContainer
var _turn: Node3D
var _model: Node3D
var _name: Label
var _role: Label
var _weapon: Label
var _badges: Array[Button] = []
var _info: VBoxContainer


func _ready() -> void:
	HudStrings.ensure_loaded()
	var t := UiKit.tokens()
	clip_contents = true
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	var fb := UiKit.panel_box(Color(t.bg_deep, 0.35), 0, Color(t.gold, 0.35))
	frame.add_theme_stylebox_override("panel", fb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	if with_model:
		_build_stage()
	# Left-side gradient so the text reads over the stage.
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(t.bg_deep, 0.85))
	g.set_color(1, Color(t.bg_deep, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 4
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.anchor_right = 0.55
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# Hero text, bottom left.
	var info_box := MarginContainer.new()
	info_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		info_box.add_theme_constant_override("margin_" + side, t.space_xl)
	info_box.add_theme_constant_override("margin_bottom", BADGE + t.space_xl * 2)
	add_child(info_box)
	_info = VBoxContainer.new()
	_info.alignment = BoxContainer.ALIGNMENT_END
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_theme_constant_override("separation", 2)
	info_box.add_child(_info)
	_info.add_child(UiKit.label(tr("HUD_MENU_HERO").to_upper(), &"caption", t.gold))
	_name = UiKit.label("", &"display")
	_info.add_child(_name)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", t.space_xl)
	_info.add_child(meta)
	_role = _meta(meta, tr("HUD_SHOWCASE_ROLE"))
	_weapon = _meta(meta, tr("HUD_SHOWCASE_WEAPON"))
	# Arrows, vertically centred on the stage.
	var prev := UiKit.icon_button(&"left", func() -> void: select(selected - 1), tr("HUD_SHOWCASE_PREV"), 44)
	prev.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	prev.position = Vector2(t.space_m, -22)
	prev.anchor_top = 0.42
	prev.anchor_bottom = 0.42
	add_child(prev)
	var next := UiKit.icon_button(&"right", func() -> void: select(selected + 1), tr("HUD_SHOWCASE_NEXT"), 44)
	next.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	next.anchor_top = 0.42
	next.anchor_bottom = 0.42
	next.offset_left = -44 - t.space_m
	next.offset_right = -t.space_m
	next.offset_top = -22
	next.offset_bottom = 22
	add_child(next)
	# Badge strip, bottom left.
	var strip := HBoxContainer.new()
	strip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	strip.offset_left = t.space_xl
	strip.offset_top = -BADGE - t.space_l
	strip.offset_bottom = -t.space_l
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip.add_theme_constant_override("separation", 6)
	add_child(strip)
	var group := ButtonGroup.new()
	for i in heroes.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(BADGE, BADGE)
		b.tooltip_text = str(heroes[i].name)
		UiKit.swatch_button(b, Color(t.panel_sunken, 0.8))
		var badge := HeroBadge.make(int(heroes[i].index), BADGE - 8)
		badge.position = Vector2(4, 4)
		badge.size = Vector2(BADGE - 8, BADGE - 8)
		b.add_child(badge)
		b.pressed.connect(func() -> void: select(i))
		UiSfx.attach(b)
		strip.add_child(b)
		_badges.append(b)
	select(selected, false)


func _meta(row: HBoxContainer, caption: String) -> Label:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(UiKit.label(caption, &"caption", UiKit.tokens().text_off))
	var l := UiKit.label("", &"body")
	v.add_child(l)
	row.add_child(v)
	return l


## The selected hero's id stem ("" when there are no heroes).
func selected_stem() -> String:
	return str(heroes[selected].stem) if selected >= 0 and selected < heroes.size() else ""


## Shows hero `i` (wraps). `notify` = emit hero_changed.
func select(i: int, notify := true) -> void:
	if heroes.is_empty():
		return
	selected = posmod(i, heroes.size())
	var h: Dictionary = heroes[selected]
	if _name == null:
		return
	_name.text = str(h.name).to_upper()
	_role.text = tr(ROLE_KEYS.get(str(h.stem), "HUD_ROLE_SOLDIER"))
	var def := _def(str(h.stem))
	_weapon.text = def.weapon.display_name if def != null and def.weapon != null else "-"
	_name.add_theme_color_override("font_color", UiKit.tokens().text)
	for k in _badges.size():
		_badges[k].set_pressed_no_signal(k == selected)
	_show_model(str(h.stem))
	UiKit.transition_in(_info, Vector2.ZERO, UiKit.tokens().motion_base)
	if notify:
		hero_changed.emit(selected)


## The badge of the selected hero (focus target).
func focus_badge() -> void:
	if selected < _badges.size():
		_badges[selected].grab_focus()


func _def(stem: String) -> HeroDef:
	var p := "%s/hero_%s.tres" % [HERO_DIR, stem]
	return load(p) as HeroDef if ResourceLoader.exists(p) else null


func _build_stage() -> void:
	var t := UiKit.tokens()
	_vpc = SubViewportContainer.new()
	_vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vpc.anchor_left = 0.3
	_vpc.stretch = true
	_vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vpc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_vpc.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.75)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.2, 5.6)
	cam.fov = 30.0
	_vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.98, 0))
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.92, 0.82)
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-35, 35, 0)
	_vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = t.accent
	rim.light_energy = 3.0
	rim.omni_range = 5.0
	rim.position = Vector3(-1.2, 2.0, -1.6)
	_vp.add_child(rim)
	var fill := OmniLight3D.new()
	fill.light_color = t.cyan
	fill.light_energy = 0.8
	fill.omni_range = 5.0
	fill.position = Vector3(1.8, 0.6, 1.2)
	_vp.add_child(fill)
	# Pedestal: dark disc with an emissive accent ring.
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.85
	cm.bottom_radius = 0.9
	cm.height = 0.08
	cm.radial_segments = 48
	disc.mesh = cm
	disc.position.y = -0.04
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.06, 0.06, 0.12)
	dm.metallic = 0.6
	dm.roughness = 0.35
	disc.material_override = dm
	_vp.add_child(disc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.875
	tm.outer_radius = 0.89
	tm.rings = 48
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(t.accent_hi, 0.7)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	_vp.add_child(ring)
	_turn = Node3D.new()
	_vp.add_child(_turn)


func _show_model(stem: String) -> void:
	if _turn == null:
		return
	if _model != null:
		_model.queue_free()
		_model = null
	var key := ModelCatalog.hero_key_from_id(stem)
	if key == &"":
		return
	_model = HeroModelBuilder.build(key, ModelPalette.TEAM_NEUTRAL)
	_turn.add_child(_model)
	_turn.rotation.y = deg_to_rad(200.0)  # face the camera, slightly turned


func _process(delta: float) -> void:
	if _turn != null and is_visible_in_tree() and not UiKit.reduce_motion():
		_turn.rotation.y += deg_to_rad(UiKit.tokens().turntable_deg_s) * delta
