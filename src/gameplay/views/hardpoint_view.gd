class_name HardpointView
extends Node3D
## Client-side presentation of one hardpoint (E7): a zone ring tinted by owner,
## a segmented progress ring that fills in the capturing team's colour, and a
## billboard label (progress %, CONTESTED / OVERTIME). Reads replicated
## SnapshotData.HardpointState only (architecture.md §11: views never simulate).
## E14 greybox task views: Breach shows a shield bubble while the Ward Generator
## is shielded and a Generator HP bar; Plant shows the
## Mana Cell (at its Cradle, carried, dropped or planted, with a beam while
## planted) and a channel ring for pickup / plant / defuse.

const SEGMENTS: int = 48
## Holdstone light pillar (design/art-bible.md §6.3: a 12 m pillar of light),
## starting at the crystal's tip.
const HOLD_PILLAR_M: float = 12.0
const HOLD_PILLAR_BASE_M: float = 4.4
## Planted-Cell beam: from just above the Cell (2.9 m, Charge Cradle socket) up.
const PLANT_BEAM_BASE_M: float = 3.4
const PLANT_BEAM_M: float = 11.0
## Art bible §4 palette: azure_core, ember_core, neutral.
const COLOR_CONCORD := Color("#2E86FF")
const COLOR_SYNDICATE := Color("#FF5A1F")
const COLOR_NEUTRAL := Color(0.92, 0.9, 1.0)
const COLOR_EMPTY := Color(0.1, 0.1, 0.14, 0.6)
## World label LOD (M1 clutter fix, see production/qa/evidence/e12/hud_1080p.png):
## a label shows only within LABEL_NEAR_M of the camera, or while its node is the
## team's current objective; it fades out over LABEL_FADE_M past that range.
## No-depth billboard at a fixed, small on-screen size (LABEL_PIXEL_SIZE x
## LABEL_FONT_SIZE is about 18 px at 1080p). Shared by UplinkView.
const LABEL_NEAR_M: float = 40.0
const LABEL_FADE_M: float = 12.0
const LABEL_PIXEL_SIZE: float = 0.00065
const LABEL_FONT_SIZE: int = 28
const LABEL_OUTLINE: int = 8
## Far objective labels are dimmed to this alpha.
const LABEL_OBJECTIVE_ALPHA: float = 0.85

var def: HardpointDef
var _ring_mat: StandardMaterial3D
var _seg_on: StandardMaterial3D
var _seg_off: StandardMaterial3D
var _segments: Array[MeshInstance3D] = []
var _label: Label3D
var _lit: int = -1
var _ring_base: Color = COLOR_NEUTRAL
var _seg_base: Color = COLOR_NEUTRAL
var _progress: float = 0.0
# E14 task views.
var _shield: MeshInstance3D
var _shield_mat: StandardMaterial3D
var _gen_bar: MeshInstance3D
var _gen_bar_bg: MeshInstance3D
var _gen_bar_mat: StandardMaterial3D
var _cell: Node3D
var _cell_mat: StandardMaterial3D
## Phase 6: the baked Mana Cell inside `_cell` (null = greybox prism) and the
## team its material is for.
var _cell_model: Node3D
var _cell_team: int = -2
var _beam: MeshInstance3D
var _channel_ring: MeshInstance3D
## Phase 6: the Holdstone (hero-pipeline asset, tools/art/world/holdstone.py) on
## Hold hardpoints, its holo light pillar and the owner it is tinted for.
var _holdstone: Node3D
var _pillar: MeshInstance3D
var _pillar_mat: ShaderMaterial
var _art_owner: int = -2
## Phase 6 Plant art (tools/art/world/plant_kit.py): the Charge Cradle and its
## four pad corner brackets, tinted for the owner like the Holdstone.
var _cradle_art: Array[Node3D] = []
## The own team's current objective (ClientWorld: the lane front, C15).
var objective: bool = false
var _near_text: String = ""
var _far_text: String = ""
var _label_color := Color.WHITE


## A compact world label: no-depth billboard, fixed small on-screen size.
static func make_world_label() -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = LABEL_PIXEL_SIZE
	l.font_size = LABEL_FONT_SIZE
	l.outline_size = LABEL_OUTLINE
	l.line_spacing = -4.0
	l.render_priority = 2
	l.outline_render_priority = 1
	l.visible = false
	return l


## Label alpha at `dist` metres from the camera: 1 within LABEL_NEAR_M, a
## linear fade to 0 over LABEL_FADE_M; an objective never drops below
## LABEL_OBJECTIVE_ALPHA.
static func label_alpha(dist: float, is_objective: bool) -> float:
	var a := clampf(1.0 - (dist - LABEL_NEAR_M) / LABEL_FADE_M, 0.0, 1.0)
	return maxf(a, LABEL_OBJECTIVE_ALPHA) if is_objective else a


## Shows `label` with the near or far text and the distance fade (camera-relative).
static func apply_label(label: Label3D, dist: float, is_objective: bool, near_text: String, far_text: String,
		color: Color) -> void:
	var a := label_alpha(dist, is_objective)
	label.visible = a > 0.01
	if not label.visible:
		return
	label.text = near_text if dist <= LABEL_NEAR_M else far_text
	label.modulate = Color(color, a)
	label.outline_modulate = Color(0.0, 0.0, 0.0, a * 0.85)


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
	_label = make_world_label()
	_label.position = Vector3(0.0, d.zone_height + 1.0, 0.0)
	# Hidden from inside the zone (the HUD objective strip shows it there).
	_label.visibility_range_begin = d.zone_radius + 2.0
	add_child(_label)
	# C5 Garrison posts and Supply Cache are not in the game yet (no Sentinels, no
	# refill): their map markers would promise a feature, so they stay hidden
	# until the systems exist (docs/assets/plant.md, PROGRESS.md Objective B).
	_hide_map_nodes.call_deferred(["Placements_" + String(d.id).to_upper()])
	match d.task:
		HardpointDef.TaskKind.BREACH:
			_build_breach(d)
		HardpointDef.TaskKind.PLANT:
			_build_plant(d)
		HardpointDef.TaskKind.HOLD:
			_build_hold(d)


## Phase 6 (design/art-bible.md §6.3 Holdstone): the baked dais, plinth and
## dormant crystal replace the map's greybox meshes (their collision stays), and
## the 12 m pillar of light is a team-coloured hologram. No-op without the asset.
func _build_hold(d: HardpointDef) -> void:
	if not WorldModel.exists(&"holdstone"):
		return
	_holdstone = WorldModel.instantiate(&"holdstone", d.initial_owner)
	_holdstone.name = "Holdstone"
	add_child(_holdstone)
	_art_owner = d.initial_owner
	_pillar_mat = ModelMaterials.holo(team_color(d.initial_owner).lightened(0.25), 1.1).duplicate() as ShaderMaterial
	_pillar_mat.set_shader_parameter("alpha", 0.32)
	_pillar_mat.set_shader_parameter("scan_density", 10.0)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.55
	cyl.height = HOLD_PILLAR_M
	cyl.radial_segments = 16
	cyl.cap_top = false
	cyl.cap_bottom = false
	_pillar = MeshInstance3D.new()
	_pillar.mesh = cyl
	_pillar.material_override = _pillar_mat
	_pillar.position.y = HOLD_PILLAR_BASE_M + HOLD_PILLAR_M * 0.5
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pillar)
	_hide_greybox.call_deferred([&"Dais", &"Plinth", &"LightPillar"])


## Hides the map's greybox meshes of this hardpoint (presentation only: the
## StaticBody3D collision stays). The map names its node "Hardpoint_<ID>".
func _hide_greybox(names: Array) -> void:
	if not is_inside_tree():
		return
	var vis := get_tree().root.find_child("Hardpoint_" + String(def.id).to_upper(), true, false)
	if vis == null:
		return
	for n: StringName in names:
		var node := vis.get_node_or_null(NodePath(String(n)))
		if node == null:
			continue
		if node is MeshInstance3D:
			(node as MeshInstance3D).visible = false
		for c in node.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).visible = false


## Re-tints the task machine (Holdstone + pillar, Charge Cradle + brackets)
## when the owner changes.
func _apply_task_art(owner: int) -> void:
	if owner == _art_owner:
		return
	if _holdstone != null:
		_art_owner = owner
		_tint(_holdstone, &"holdstone", owner)
		_pillar_mat.set_shader_parameter("color", team_color(owner).lightened(0.25))
	if not _cradle_art.is_empty():
		_art_owner = owner
		for n in _cradle_art:
			_tint(n, &"charge_cradle", owner)


static func _tint(node: Node, key: StringName, team: int) -> void:
	var mat := WorldModel.material(key, team)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat


## Hides map greybox nodes anywhere in the scene by name, with all their meshes
## (presentation only; collision stays). For greybox that the map does not put
## under Hardpoint_<ID> (Cradle pads, C5 placement markers).
func _hide_map_nodes(names: Array) -> void:
	if not is_inside_tree():
		return
	var root := get_tree().root
	for n: String in names:
		var node := root.find_child(n, true, false)
		if node == null:
			continue
		if node is MeshInstance3D:
			(node as MeshInstance3D).visible = false
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visible = false


func _build_breach(d: HardpointDef) -> void:
	_shield_mat = _unshaded(Color(team_color(d.initial_owner), 0.28))
	_shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield = MeshInstance3D.new()
	_shield.name = "ShieldBubble"
	var sm := SphereMesh.new()
	sm.radius = 3.0
	sm.height = 6.0
	sm.material = _shield_mat
	_shield.mesh = sm
	_shield.position.y = 1.2
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shield)
	# Generator HP bar: a billboard strip above the core.
	_gen_bar_bg = _bar(Color(0.08, 0.08, 0.1, 0.8), 2.0)
	_gen_bar_mat = _unshaded(team_color(d.initial_owner))
	_gen_bar_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_gen_bar_mat.billboard_keep_scale = true
	_gen_bar_mat.no_depth_test = true
	_gen_bar_mat.render_priority = 1
	_gen_bar = _bar(_gen_bar_mat.albedo_color, 2.0)
	_gen_bar.material_override = _gen_bar_mat
	_gen_bar.position.z = 0.01


func _bar(c: Color, width: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width, 0.16)
	var mat := _unshaded(c)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.no_depth_test = true
	q.material = mat
	m.mesh = q
	m.position = Vector3(0.0, 4.2, 0.0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func _build_plant(d: HardpointDef) -> void:
	_cell_mat = _unshaded(COLOR_NEUTRAL)
	_cell = Node3D.new()
	_cell.name = "ManaCell"
	_cell.top_level = true
	_cell.visible = false
	add_child(_cell)
	if WorldModel.exists(&"mana_cell"):
		# Phase 6: the baked capsule in its chrome cage, re-tinted per Cell team.
		_cell_model = WorldModel.instantiate(&"mana_cell", ModelPalette.TEAM_NEUTRAL)
		_cell.add_child(_cell_model)
	else:
		var prism := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.45, 0.7, 0.45)
		pm.material = _cell_mat
		prism.mesh = pm
		prism.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cell.add_child(prism)
	_build_plant_art(d)
	_beam = MeshInstance3D.new()
	_beam.name = "PlantBeam"
	var bm := CylinderMesh.new()
	# Starts above the Charge Cradle's socket, so the planted Cell stays visible.
	bm.top_radius = 0.18
	bm.bottom_radius = 0.18
	bm.height = PLANT_BEAM_M
	bm.material = _cell_mat
	_beam.mesh = bm
	_beam.position.y = PLANT_BEAM_BASE_M + PLANT_BEAM_M * 0.5
	_beam.visible = false
	add_child(_beam)
	_channel_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.1
	tm.outer_radius = 1.35
	tm.material = _cell_mat
	_channel_ring.mesh = tm
	_channel_ring.top_level = true
	_channel_ring.visible = false
	add_child(_channel_ring)


## Phase 6 (design/art-bible.md §6.3 Plant, docs/assets/plant.md): the Charge
## Cradle ("Y" pylon whose socket takes the Cell at 2.9 m) with four corner
## brackets at the zone's half-width, and each team's Cell Cradle (pickup
## station). They replace the map's greybox meshes; collision stays. No-op per
## asset that is not built.
func _build_plant_art(d: HardpointDef) -> void:
	_art_owner = -2
	if WorldModel.exists(&"charge_cradle"):
		var inst := WorldModel.instantiate(&"charge_cradle", d.initial_owner)
		inst.name = "ChargeCradle"
		var bracket := WorldModel.piece(inst, &"bracket")
		var hw := d.zone_radius
		if bracket != null:
			bracket.get_parent().remove_child(bracket)
			# The piece's corner is its origin; its legs run along -X and -Z (yaw 0 = the +X+Z corner).
			for c in [[1.0, 1.0, 0.0], [-1.0, 1.0, -90.0], [-1.0, -1.0, 180.0], [1.0, -1.0, 90.0]]:
				var b := bracket.duplicate() as MeshInstance3D
				b.name = "Bracket"
				b.position = Vector3(c[0] * hw, 0.0, c[1] * hw)
				b.rotation_degrees.y = c[2]
				add_child(b)
				_cradle_art.append(b)
			bracket.free()
		add_child(inst)
		_cradle_art.append(inst)
		_art_owner = d.initial_owner
		var names: Array = [&"PylonStem", &"ProngL", &"ProngR", &"Socket", &"Awning"]
		for s in ["-1", "1"]:
			for t in ["-1", "1"]:
				names.append(StringName("BracketX%s%s" % [s, t]))
				names.append(StringName("BracketZ%s%s" % [s, t]))
		_hide_greybox.call_deferred(names)
	if WorldModel.exists(&"cell_cradle"):
		var hidden: Array = []
		for team in d.cell_cradles.size():
			var at := d.cell_cradles[team]
			if not at.is_finite():
				continue
			var cradle := WorldModel.instantiate(&"cell_cradle", team)
			cradle.name = "CellCradle_%d" % team
			cradle.top_level = true
			add_child(cradle)
			cradle.position = at
			var tag := String(d.id).to_upper()
			hidden.append("CellCradle_%s_%d" % [tag, team])
			hidden.append("CellCradleGlow_%s_%d" % [tag, team])
		_hide_map_nodes.call_deferred(hidden)


## Applies the latest replicated state.
func apply(st: SnapshotData.HardpointState) -> void:
	_apply_task_art(st.owner)
	_ring_base = team_color(st.owner)
	_seg_base = team_color(st.capturing_team)
	_progress = st.progress
	_ring_mat.albedo_color = _ring_base
	_seg_on.albedo_color = _seg_base
	var lit := roundi(st.progress * SEGMENTS)
	if lit != _lit:
		_lit = lit
		for i in SEGMENTS:
			_segments[i].material_override = _seg_on if i < lit else _seg_off
	# Compact: one line far away (name + %), the task state underneath up close.
	var pct := "  %d%%" % floori(st.progress * 100.0) if st.progress > 0.0 else ""
	var flag := "  CONTESTED" if st.contested else ("  OVERTIME" if st.overtime else "")
	_far_text = def.display_name + pct
	_near_text = def.display_name + pct + flag + _apply_task(st)
	_label_color = team_color(st.owner)
	_update_label()


## The own team's current objective (label stays up at any range).
func set_objective(on: bool) -> void:
	if on != objective:
		objective = on
		_update_label()


func _process(_delta: float) -> void:
	_update_label()
	_glow_pulse()


## G1: capture glow. The lit progress segments and the owner ring breathe above
## 1.0 (HDR, Signal tier: ownership emissive, blooms where glow is on); the
## pulse speeds up and brightens with capture progress.
func _glow_pulse() -> void:
	if _ring_mat == null or GfxQuality.is_headless():
		return
	var t := Time.get_ticks_msec() * 0.001
	var k := 1.15 + 0.15 * sin(t * 2.0)
	_ring_mat.albedo_color = Color(_ring_base.r * k, _ring_base.g * k, _ring_base.b * k, _ring_mat.albedo_color.a)
	var p := 1.25 + 0.25 * _progress + (0.2 + 0.25 * _progress) * sin(t * (3.0 + 5.0 * _progress))
	_seg_on.albedo_color = Color(_seg_base.r * p, _seg_base.g * p, _seg_base.b * p, 1.0)


func _update_label() -> void:
	if _label == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	var dist := cam.global_position.distance_to(_label.global_position) if cam != null else 0.0
	apply_label(_label, dist, objective, _near_text, _far_text, _label_color)
	if _gen_bar != null and _gen_bar.visible and dist > LABEL_NEAR_M and not objective:
		_gen_bar.visible = false
		_gen_bar_bg.visible = false


## E14 task visuals; returns extra label text.
func _apply_task(st: SnapshotData.HardpointState) -> String:
	if _shield != null:
		var up := st.task == HardpointDef.TaskKind.BREACH and not st.breach_phase2 and st.owner != MapDef.TEAM_NEUTRAL
		_shield.visible = up and st.shielded
		_shield_mat.albedo_color = Color(team_color(st.owner), 0.28)
		_gen_bar.visible = up
		_gen_bar_bg.visible = up
		_gen_bar_mat.albedo_color = team_color(st.owner)
		_gen_bar.scale = Vector3(maxf(st.gen_frac, 0.001), 1.0, 1.0)
		_gen_bar.position.x = 0.0
		if st.task != HardpointDef.TaskKind.BREACH:
			return ""
		if st.breach_phase2:
			return "\nBREACHED"
		return "\nGENERATOR %d%%%s" % [ceili(st.gen_frac * 100.0), "  SHIELDED" if st.shielded else ""]
	if _cell != null:
		var has := st.cell_state != HardpointSim.CellState.NONE and st.task == HardpointDef.TaskKind.PLANT
		_cell.visible = has
		_beam.visible = st.cell_state == HardpointSim.CellState.PLANTED
		_cell_mat.albedo_color = team_color(st.cell_team)
		if _cell_model != null and st.cell_team != _cell_team:
			_cell_team = st.cell_team
			_tint(_cell_model, &"mana_cell", st.cell_team)
		if has:
			var lift := 2.6 if st.cell_state == HardpointSim.CellState.CARRIED else 1.0
			if st.cell_state == HardpointSim.CellState.PLANTED:
				lift = 2.9
			_cell.position = st.cell_pos + Vector3(0.0, lift, 0.0)
			_cell.rotation.y = fmod(Time.get_ticks_msec() / 600.0, TAU)
		_channel_ring.visible = st.channel != HardpointSim.Channel.NONE
		if _channel_ring.visible:
			_channel_ring.position = st.cell_pos + Vector3(0.0, 0.08, 0.0)
			var k := 0.3 + 0.7 * st.channel_frac
			_channel_ring.scale = Vector3(k, 1.0, k)
		match st.cell_state:
			HardpointSim.CellState.CARRIED:
				return "\nCELL CARRIED"
			HardpointSim.CellState.DROPPED:
				return "\nCELL DROPPED"
			HardpointSim.CellState.PLANTED:
				return "\nDEFUSING" if st.channel == HardpointSim.Channel.DEFUSE else "\nCELL PLANTED"
	return ""


static func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
