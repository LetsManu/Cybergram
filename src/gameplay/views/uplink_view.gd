class_name UplinkView
extends Node3D
## Client-side greybox of one Mana Uplink (E9; match-flow-and-map.md §3.6,
## design/ux/hud.md §4.8). Sealed: a translucent team-coloured shell closes over
## the map's core. Exposed: the shell opens (hidden), a hot pulsing core and
## "EXPOSED" label appear. Destroyed: the core goes dark. A compact billboard
## shows the Integrity % within HardpointView.LABEL_NEAR_M, or at any range
## while Exposed / destroyed (the objective). Reads SnapshotData.UplinkState only.

const SHELL_RADIUS: float = 2.4
const SHELL_HEIGHT: float = 4.2
## Core centre above the Uplink floor (the slice map's UplinkCore node).
const CORE_Y: float = 7.3
const EXPOSED_COLOR := Color(1.0, 0.25, 0.2)
const DEAD_COLOR := Color(0.12, 0.12, 0.14)

var team: int = 0
var exposed: bool = false
var destroyed: bool = false
var _shell: MeshInstance3D
var _shell_mat: StandardMaterial3D
var _core: MeshInstance3D
var _core_mat: StandardMaterial3D
var _label: Label3D
var _t: float = 0.0
var _text: String = ""
var _label_color := Color.WHITE
## Art pass: the 45 m neon mana spire (UplinkModel); null = greybox only.
var model: UplinkModel


func setup(hq: HqDef) -> void:
	team = hq.team
	name = "UplinkView%d" % team
	position = hq.uplink
	var col := HardpointView.team_color(team)
	_shell_mat = StandardMaterial3D.new()
	_shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shell_mat.albedo_color = Color(col, 0.35)
	_shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shell := CylinderMesh.new()
	shell.top_radius = SHELL_RADIUS * 0.8
	shell.bottom_radius = SHELL_RADIUS
	shell.height = SHELL_HEIGHT
	shell.radial_segments = 6
	shell.material = _shell_mat
	_shell = MeshInstance3D.new()
	_shell.mesh = shell
	_shell.position.y = CORE_Y
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shell)
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = EXPOSED_COLOR
	var core := SphereMesh.new()
	core.radius = 1.9
	core.height = 3.8
	core.material = _core_mat
	_core = MeshInstance3D.new()
	_core.mesh = core
	_core.position.y = CORE_Y
	_core.visible = false
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	_label = HardpointView.make_world_label()
	_label_color = col.lightened(0.3)
	_label.position.y = CORE_Y + 4.5
	add_child(_label)
	if ModelCatalog.models_enabled():
		_attach_model.call_deferred()


## Art hook: builds the spire and hides the map's greybox spire / core meshes
## at this Uplink (presentation only; their collision stays).
func _attach_model() -> void:
	model = UplinkModel.new()
	add_child(model)
	model.setup(team, CORE_Y)
	_shell.scale = Vector3(1.25, 1.2, 1.25)
	var root := get_parent()
	if root == null:
		return
	for n in root.find_children("Uplink*", "Node3D", true, false):
		if n.name != &"UplinkSpire" and n.name != &"UplinkCore":
			continue
		var p := (n as Node3D).global_position
		if Vector2(p.x - global_position.x, p.z - global_position.z).length() > 4.0:
			continue
		for c in n.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).visible = false


## Applies one replicated Uplink state.
func apply(st: SnapshotData.UplinkState) -> void:
	exposed = st.exposed
	destroyed = st.integrity <= 0.0
	var pct := 100.0 * st.integrity / maxf(st.max_integrity, 1.0)
	_shell.visible = not exposed and not destroyed
	_core.visible = (exposed or destroyed) and model == null
	if model != null:
		model.set_state(exposed, destroyed, st.integrity / maxf(st.max_integrity, 1.0))
	if destroyed:
		_core_mat.albedo_color = DEAD_COLOR
		_text = "UPLINK DESTROYED"
	elif exposed:
		_text = "EXPOSED  %d%%" % ceili(pct)
		_label_color = EXPOSED_COLOR.lightened(0.3)
	else:
		_text = "UPLINK  %d%%" % ceili(pct)
		_label_color = HardpointView.team_color(team).lightened(0.3)
	_update_label()


func _update_label() -> void:
	if _label == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	var dist := cam.global_position.distance_to(_label.global_position) if cam != null else 0.0
	HardpointView.apply_label(_label, dist, exposed or destroyed, _text, _text, _label_color)


func _process(delta: float) -> void:
	_update_label()
	if not exposed or destroyed:
		return
	_t += delta
	var k := 0.5 + 0.5 * sin(_t * TAU * 1.5)
	_core_mat.albedo_color = EXPOSED_COLOR.lerp(Color(1.0, 0.95, 0.8), k * 0.6)
	_core.scale = Vector3.ONE * (1.0 + 0.08 * k)
