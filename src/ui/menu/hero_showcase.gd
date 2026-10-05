class_name HeroShowcase
extends Control
## Main-menu hero showcase (design/ux/mockups/v0.9 Main.dc.html, HOME): the
## selected hero's live 3D model (HeroModelBuilder, the builder the match
## uses) in ONE SubViewport, lit like the rendered portraits (warm key, teal
## rim), standing on a warm floor spotlight; on the left an eyebrow
## (role · weapon), the huge name, a one-line description, the Q/E/C/G skill
## list with key chips and a row of round portrait thumbs. Reduce motion
## stops the turntable. Display only: emits `hero_changed`; the menu stores
## the pick.
##
## Laid out in the mockup's reference px (the menu scales its whole stage).
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
## One-line description key per hero: HUD_HERO_LINE_<STEM> (built, so the
## key scanner does not read the prefix as a key).
const LINE_KEY_PREFIX := "HUD" + "_HERO_LINE_"
## Portrait thumb side (px).
const BADGE := 52
## Default keys of the four skill actions (skill_1..4) when unbound.
const SKILL_KEYS: Array[String] = ["Q", "E", "C", "G"]
## Hero stage rect in this control (mockup: img left 600, top 92, h 700,
## portrait aspect 0.72), relative to the content area below the top bar.
const STAGE_RECT := Rect2(600, 20, 504, 700)
## Text block origin and width.
const TEXT_POS := Vector2(64, 60)
const TEXT_W := 500.0

## HeroCatalog.entries() (set before adding to the tree).
var heroes: Array = []
## Index into `heroes`.
var selected: int = 0
## Render the 3D model (tests / headless may turn it off).
var with_model: bool = true
## false = only the 3D stage, filling the control (the lobby draws its own
## hero info).
var chrome: bool = true

var _vp: SubViewport
var _view: TextureRect
var _turn: Node3D
var _model: Node3D
var _glow: TextureRect
var _name: Label
var _eyebrow: Label
var _line: Label
var _skills: GridContainer
var _badges: Array[Button] = []
var _info: VBoxContainer


func _ready() -> void:
	HudStrings.ensure_loaded()
	var t := UiKit.tokens()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow = floor_glow()
	add_child(_glow)
	if with_model:
		_build_stage()
	resized.connect(_layout_stage)
	_layout_stage()
	if not chrome:
		select(selected, false)
		return
	_info = VBoxContainer.new()
	_info.position = TEXT_POS
	_info.custom_minimum_size.x = TEXT_W
	_info.size.x = TEXT_W
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_theme_constant_override("separation", 0)
	add_child(_info)
	_eyebrow = UiKit.eyebrow("", t.accent, 13)
	_info.add_child(_eyebrow)
	_info.add_child(UiKit.spacer(14))
	_name = Label.new()
	_name.add_theme_font_override("font", UiKit.display_font(600, 1))
	_name.add_theme_font_size_override("font_size", 72)
	_name.add_theme_constant_override("line_spacing", -22)
	_name.add_theme_color_override("font_color", t.text)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.uppercase = true
	_info.add_child(_name)
	_info.add_child(UiKit.spacer(14))
	_line = Label.new()
	_line.add_theme_font_override("font", UiKit.body_font(400))
	_line.add_theme_font_size_override("font_size", 16)
	_line.add_theme_constant_override("line_spacing", 7)
	_line.add_theme_color_override("font_color", t.text_dim)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size.x = 420
	_line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_info.add_child(_line)
	_info.add_child(UiKit.spacer(28))
	_skills = GridContainer.new()
	_skills.columns = 2
	_skills.add_theme_constant_override("h_separation", 24)
	_skills.add_theme_constant_override("v_separation", 12)
	_skills.custom_minimum_size.x = 440
	_skills.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_info.add_child(_skills)
	for k in 4:  # built once; select() only swaps the names
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(UiKit.key_chip(skill_key(k)))
		var nm := Label.new()
		nm.add_theme_font_override("font", UiKit.body_font(400))
		nm.add_theme_font_size_override("font_size", 14)
		nm.add_theme_color_override("font_color", t.text)
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.custom_minimum_size.x = 168
		row.add_child(nm)
		_skills.add_child(row)
	_info.add_child(UiKit.spacer(36))
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 14)
	_info.add_child(strip)
	for i in heroes.size():
		var b := thumb_button(int(heroes[i].index), BADGE)
		b.tooltip_text = str(heroes[i].name)
		b.pressed.connect(func() -> void: select(i))
		strip.add_child(b)
		_badges.append(b)
	select(selected, false)


## A round portrait button (`side` px): 1 px hairline ring at rest, 2 px
## brass when pressed (toggle), pale brass while hovered / focused. The
## HeroBadge is child 0.
static func thumb_button(hero_index: int, side: int) -> Button:
	var t := UiKit.tokens()
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(side, side)
	b.focus_mode = Control.FOCUS_ALL
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, empty)
	var badge := HeroBadge.make(hero_index, side, t.line_strong)
	badge.ring_width = 1.0
	badge.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(badge)
	var sync := func() -> void:
		var hot := b.is_hovered() or b.has_focus()
		badge.ring = t.accent if b.button_pressed else (t.accent_hi if hot else t.line_strong)
		badge.ring_width = 2.0 if b.button_pressed or hot else 1.0
		badge.position.y = -2.0 if hot and not UiKit.reduce_motion() else 0.0
	b.toggled.connect(func(_on: bool) -> void: sync.call())
	b.mouse_entered.connect(sync)
	b.mouse_exited.connect(sync)
	b.focus_entered.connect(sync)
	b.focus_exited.connect(sync)
	b.draw.connect(sync)  # set_pressed_no_signal() does not emit toggled
	UiSfx.attach(b)
	return b


## A warm elliptical floor spotlight (brass, 0.32 at the centre), sized by
## the caller.
static func floor_glow() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(UiKit.tokens().accent, 0.32))
	g.set_color(1, Color(UiKit.tokens().accent, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 32
	var r := TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Keyboard label of skill slot `i` (0..3): the first key bound to
## skill_<i+1>, else the default Q / E / C / G.
static func skill_key(i: int) -> String:
	var action := "skill_%d" % (i + 1)
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			var k := ev as InputEventKey
			if k != null:
				var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
				var txt := OS.get_keycode_string(code)
				if txt != "":
					return txt.left(3).to_upper()
	return SKILL_KEYS[i] if i < SKILL_KEYS.size() else "?"


## The selected hero's id stem ("" when there are no heroes).
func selected_stem() -> String:
	return str(heroes[selected].stem) if selected >= 0 and selected < heroes.size() else ""


## Shows hero `i` (wraps). `notify` = emit hero_changed.
func select(i: int, notify := true) -> void:
	if heroes.is_empty():
		return
	selected = posmod(i, heroes.size())
	var h: Dictionary = heroes[selected]
	var stem := str(h.stem)
	_show_model(stem)
	if _name == null:
		return
	var def := hero_def(stem)
	_name.text = str(h.name)
	_eyebrow.text = eyebrow_text(stem, def)
	_line.text = hero_line(stem)
	for k in _skills.get_child_count():
		var row := _skills.get_child(k) as HBoxContainer
		var has := def != null and k < def.skills.size()
		row.modulate.a = 1.0 if has else 0.0
		(row.get_child(1) as Label).text = def.skills[k].display_name if has else ""
	for k in _badges.size():
		_badges[k].set_pressed_no_signal(k == selected)
		_badges[k].queue_redraw()
	UiKit.transition_in(_info, Vector2.ZERO, UiKit.tokens().motion_base)
	if notify:
		hero_changed.emit(selected)


## "COMMANDER  ·  THREADCASTER" for a hero.
static func eyebrow_text(stem: String, def: HeroDef) -> String:
	var role := TranslationServer.translate(LobbyPhase.role_short_key(LobbyPhase.role_key(stem)))
	var weapon := def.weapon.display_name if def != null and def.weapon != null else ""
	return (role + ("  ·  " + weapon if weapon != "" else "")).to_upper()


## The hero's one-line description ("" when the key is missing).
static func hero_line(stem: String) -> String:
	var key := LINE_KEY_PREFIX + stem.to_upper()
	var t := TranslationServer.translate(key)
	return t if t != key else ""


## The portrait thumb of the selected hero (focus target).
func focus_badge() -> void:
	if selected < _badges.size():
		_badges[selected].grab_focus()


## The HeroDef of `stem` (null when missing).
static func hero_def(stem: String) -> HeroDef:
	var p := "%s/hero_%s.tres" % [HERO_DIR, stem]
	return load(p) as HeroDef if ResourceLoader.exists(p) else null


## The stage rect in this control: STAGE_RECT with chrome, else the whole
## control fitted to the portrait aspect (centred).
func stage_rect() -> Rect2:
	if chrome:
		return STAGE_RECT
	var aspect := STAGE_RECT.size.x / STAGE_RECT.size.y
	var h := size.y
	var w := minf(size.x, h * aspect)
	h = w / aspect
	return Rect2((size.x - w) * 0.5, size.y - h, w, h)


func _layout_stage() -> void:
	var r := stage_rect()
	# Floor spotlight under the feet (mockup: 300x36 under a 504x700 hero).
	_glow.size = Vector2(r.size.x * 0.6, r.size.y * 36.0 / 700.0)
	_glow.position = r.position + Vector2(r.size.x * 0.5, r.size.y * 0.877) - _glow.size * 0.5
	if _view == null:
		return
	_view.position = r.position
	_view.size = r.size
	_sync_viewport_size()


## Renders the viewport at screen resolution (the stage may be scaled).
func _sync_viewport_size() -> void:
	if _vp == null or _view == null:
		return
	var s := get_global_transform_with_canvas().get_scale() if is_inside_tree() else Vector2.ONE
	var px := Vector2i((_view.size * s).round())
	if px.x > 4 and px.y > 4 and px != _vp.size:
		_vp.size = px


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_viewport_size()


func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.size = Vector2i(STAGE_RECT.size)
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	_view = TextureRect.new()
	_view.texture = _vp.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	set_notify_transform(true)
	# Same look as tools/art/render_hero_portraits.gd: soft cool ambient, a
	# warm key from the front left, a teal rim from behind. No pedestal.
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.48, 0.55)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 26.0
	_vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.4, 1.25, 6.2), Vector3(0, 1.0, 0))
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.66)
	key.light_energy = 1.5
	key.rotation_degrees = Vector3(-28, 40, 0)
	_vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.25, 0.85, 0.8)
	rim.light_energy = 4.0
	rim.omni_range = 6.0
	rim.position = Vector3(1.6, 2.2, -1.8)
	_vp.add_child(rim)
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
	_model = HeroModelLoader.build(key, ModelPalette.TEAM_NEUTRAL)  # rigged toon model, box fallback
	_turn.add_child(_model)
	if _model.has_method(&"play_showcase"):
		_model.call(&"play_showcase")  # menu idle clip; box models have none
	_turn.rotation.y = deg_to_rad(205.0)  # the portrait's three-quarter view


func _process(delta: float) -> void:
	if _turn != null and is_visible_in_tree() and not UiKit.reduce_motion():
		_turn.rotation.y += deg_to_rad(UiKit.tokens().turntable_deg_s) * delta
