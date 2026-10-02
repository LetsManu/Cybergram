extends Node3D
## M1 scaffold entry scene. Boots a greybox stand-in for the slice lane so the
## "launch and look" evidence pipeline has something to capture. Replaced by
## AppRoot + LaunchConfig (architecture.md §4) in E3.

const _LANE_LENGTH_M: float = 120.0
const _HARDPOINT_COUNT: int = 5
const _CONCORD_BLUE := Color(0.25, 0.55, 1.0)
const _SYNDICATE_RED := Color(1.0, 0.35, 0.25)
const _NEUTRAL := Color(0.85, 0.85, 0.9)


func _ready() -> void:
	_build_environment()
	_build_lane()
	_build_camera()
	_build_overlay()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.7)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)


func _build_lane() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, _LANE_LENGTH_M)
	ground.mesh = plane
	ground.material_override = _flat(Color(0.3, 0.32, 0.38))
	add_child(ground)
	# Breach / Plant / Hold / Plant / Breach from Concord (-z) to Syndicate (+z).
	var spacing := _LANE_LENGTH_M / (_HARDPOINT_COUNT + 1)
	for i in _HARDPOINT_COUNT:
		var z := -_LANE_LENGTH_M / 2.0 + spacing * (i + 1)
		var color := _NEUTRAL
		if i < 2:
			color = _CONCORD_BLUE
		elif i > 2:
			color = _SYNDICATE_RED
		add_child(_pillar(Vector3(0.0, 0.0, z), color))


func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	cam.look_at_from_position(Vector3(10.0, 7.0, -_LANE_LENGTH_M / 2.0 - 4.0), Vector3(0.0, 2.0, 0.0))


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.position = Vector2(16.0, 12.0)
	label.add_theme_font_size_override("font_size", 22)
	label.text = "CYBERGRAM — M1 scaffold\nGodot %s · %s" % [
		Engine.get_version_info().string,
		RenderingServer.get_current_rendering_method(),
	]
	layer.add_child(label)
	add_child(layer)


func _pillar(pos: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.6
	mesh.bottom_radius = 0.9
	mesh.height = 8.0
	node.mesh = mesh
	node.position = pos + Vector3(0.0, mesh.height / 2.0, 0.0)
	node.material_override = _flat(color, true)
	return node


func _flat(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.6
	return mat
