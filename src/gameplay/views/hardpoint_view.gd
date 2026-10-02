class_name HardpointView
extends Node3D
## Client-side presentation of one hardpoint (E7): a zone ring tinted by owner,
## a segmented progress ring that fills in the capturing team's colour, and a
## billboard label (progress %, CONTESTED / OVERTIME). Reads replicated
## SnapshotData.HardpointState only (architecture.md §11: views never simulate).

const SEGMENTS: int = 48
## Art bible §4 palette: azure_core, ember_core, neutral.
const COLOR_CONCORD := Color("#2E86FF")
const COLOR_SYNDICATE := Color("#FF5A1F")
const COLOR_NEUTRAL := Color(0.92, 0.9, 1.0)
const COLOR_EMPTY := Color(0.1, 0.1, 0.14, 0.6)

var def: HardpointDef
var _ring_mat: StandardMaterial3D
var _seg_on: StandardMaterial3D
var _seg_off: StandardMaterial3D
var _segments: Array[MeshInstance3D] = []
var _label: Label3D
var _lit: int = -1


static func team_color(team: int) -> Color:
	match team:
		MapDef.TEAM_CONCORD:
			return COLOR_CONCORD
		MapDef.TEAM_SYNDICATE:
			return COLOR_SYNDICATE
	return COLOR_NEUTRAL


func setup(d: HardpointDef) -> void:
	def = d
	name = "HardpointView_%s" % d.id
	position = d.position
	_ring_mat = _unshaded(team_color(d.initial_owner))
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = d.zone_radius - 0.35
	torus.outer_radius = d.zone_radius
	torus.rings = 96
	torus.ring_segments = 4
	torus.material = _ring_mat
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.4, 1.0)
	ring.position.y = 0.12
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_seg_on = _unshaded(COLOR_NEUTRAL)
	_seg_off = _unshaded(COLOR_EMPTY)
	var seg_mesh := BoxMesh.new()
	var r := d.zone_radius - 1.0
	seg_mesh.size = Vector3(TAU * r / SEGMENTS * 0.7, 0.08, 0.6)
	for i in SEGMENTS:
		var m := MeshInstance3D.new()
		m.mesh = seg_mesh
		m.material_override = _seg_off
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Clockwise from the -Z side (lane-forward) as seen from above.
		var a := -float(i) / SEGMENTS * TAU
		m.position = Vector3(sin(a) * r, 0.1, -cos(a) * r)
		m.rotation.y = a
		add_child(m)
		_segments.append(m)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0015
	_label.font_size = 28
	_label.outline_size = 8
	_label.position = Vector3(0.0, d.zone_height + 1.0, 0.0)
	# Hidden from inside the zone (the HUD objective strip shows it there).
	_label.visibility_range_begin = d.zone_radius + 2.0
	add_child(_label)


## Applies the latest replicated state.
func apply(st: SnapshotData.HardpointState) -> void:
	_ring_mat.albedo_color = team_color(st.owner)
	_seg_on.albedo_color = team_color(st.capturing_team)
	var lit := roundi(st.progress * SEGMENTS)
	if lit != _lit:
		_lit = lit
		for i in SEGMENTS:
			_segments[i].material_override = _seg_on if i < lit else _seg_off
	var txt := def.display_name
	if st.progress > 0.0:
		txt += "\n%d%%" % floori(st.progress * 100.0)
	if st.contested:
		txt += "  CONTESTED"
	elif st.overtime:
		txt += "  OVERTIME"
	_label.text = txt
	_label.modulate = team_color(st.owner)


static func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
