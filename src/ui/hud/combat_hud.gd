class_name CombatHud
extends CanvasLayer
## Minimal combat HUD (E12.1 / E4): HP meter, ammo or mana meter with reload and
## Burnout states, hit marker, floating damage numbers and the respawn countdown.
## Reads ClientWorld's replicated state and signals only; writes nothing.

const _MARKER_TIME: float = 0.25
const _NUMBER_TIME: float = 0.9
const _HP_COLOR := Color(0.35, 0.95, 0.55)
const _MANA_COLOR := Color(0.35, 0.75, 1.0)
const _MAG_COLOR := Color(1.0, 0.8, 0.3)
const _BURNOUT_COLOR := Color(0.45, 0.45, 0.5)

## Set by AppRoot (the GameSession node).
var session: Node
var _client: ClientWorld
var _hp_label: Label
var _hp_fill: ColorRect
var _ammo_label: Label
var _ammo_fill: ColorRect
var _state_label: Label
var _center_label: Label
var _marker: Control
var _marker_left: float = 0.0
var _marker_kill: bool = false
var _numbers: Array = []  # [Label, world pos, time left]


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_hp_label = _label(root, 26, Control.PRESET_BOTTOM_LEFT, Vector2(24.0, -86.0))
	_hp_fill = _bar(root, Control.PRESET_BOTTOM_LEFT, Vector2(24.0, -44.0), _HP_COLOR)
	_ammo_label = _label(root, 26, Control.PRESET_BOTTOM_RIGHT, Vector2(-284.0, -86.0))
	_ammo_fill = _bar(root, Control.PRESET_BOTTOM_RIGHT, Vector2(-284.0, -44.0), _MANA_COLOR)
	_state_label = _label(root, 18, Control.PRESET_BOTTOM_RIGHT, Vector2(-284.0, -118.0))
	_center_label = _label(root, 30, Control.PRESET_CENTER, Vector2(-220.0, 60.0))
	_center_label.custom_minimum_size = Vector2(440.0, 0.0)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker = Control.new()
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	root.add_child(_marker)
	_client = session.get("client") as ClientWorld if session != null else null
	if _client != null:
		_client.hit_confirmed.connect(_on_hit)


func _process(delta: float) -> void:
	if _client == null:
		return
	var c := _client.combat
	if c != null:
		_hp_label.text = "HP  %d / %d" % [c.hp, c.max_hp]
		_hp_fill.size.x = 260.0 * clampf(float(c.hp) / maxf(1.0, c.max_hp), 0.0, 1.0)
		var burnout := (c.ammo_flags & AmmoFeed.FLAG_BURNOUT) != 0
		if c.feed_kind == WeaponDef.FeedKind.MANA:
			_ammo_label.text = "MANA  %d / %d" % [floori(c.ammo), c.ammo_capacity]
			_ammo_fill.color = _BURNOUT_COLOR if burnout else _MANA_COLOR
		else:
			_ammo_label.text = "%d / %d   | %d" % [roundi(c.ammo), c.ammo_capacity, c.reserve]
			_ammo_fill.color = _MAG_COLOR
		_ammo_fill.size.x = 260.0 * clampf(c.ammo / maxf(1.0, c.ammo_capacity), 0.0, 1.0)
		var st := ""
		if burnout:
			st = "BURNOUT"
		elif (c.ammo_flags & AmmoFeed.FLAG_RELOADING) != 0:
			st = "RELOADING"
		elif (c.ammo_flags & AmmoFeed.FLAG_DRY) != 0:
			st = "DRY"
		_state_label.text = st
		_center_label.text = "ELIMINATED - respawn in %.1f s" % _client.respawn_seconds_left() if c.dead else ""
	_marker_left = maxf(0.0, _marker_left - delta)
	_marker.queue_redraw()
	_update_numbers(delta)


func _on_hit(e: GameEvent) -> void:
	_marker_left = _MARKER_TIME
	_marker_kill = (e.flags & GameEvent.FLAG_KILL) != 0
	var l := Label.new()
	l.text = str(roundi(e.amount))
	l.add_theme_font_size_override("font_size", 30 if (e.flags & GameEvent.FLAG_HEADSHOT) != 0 else 24)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if (e.flags & GameEvent.FLAG_HEADSHOT) != 0 else Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
	_numbers.append([l, e.position + Vector3(randf_range(-0.3, 0.3), 0.2, 0.0), _NUMBER_TIME])


func _update_numbers(delta: float) -> void:
	var cam := _client.rig.camera if _client.rig != null else null
	for i in range(_numbers.size() - 1, -1, -1):
		var n: Array = _numbers[i]
		n[2] -= delta
		n[1] += Vector3(0.0, 0.8 * delta, 0.0)
		var l: Label = n[0]
		if n[2] <= 0.0 or cam == null or cam.is_position_behind(n[1]):
			l.queue_free()
			_numbers.remove_at(i)
			continue
		l.position = cam.unproject_position(n[1]) - l.size / 2.0
		l.modulate.a = clampf(n[2] / _NUMBER_TIME * 2.0, 0.0, 1.0)


func _draw_marker() -> void:
	if _marker_left <= 0.0:
		return
	var c := _marker.size / 2.0
	var col := Color(1.0, 0.2, 0.2) if _marker_kill else Color(1.0, 1.0, 1.0)
	col.a = _marker_left / _MARKER_TIME
	for s in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		_marker.draw_line(c + s * 7.0, c + s * 16.0, col, 3.0, true)


func _label(parent: Control, font: int, preset: int, offset: Vector2) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.position += offset
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


func _bar(parent: Control, preset: int, offset: Vector2, color: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bg.set_anchors_preset(preset)
	bg.position += offset
	bg.size = Vector2(264.0, 22.0)
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2(2.0, 2.0)
	fill.size = Vector2(260.0, 18.0)
	bg.add_child(fill)
	return fill
