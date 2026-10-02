class_name NetFixtures
extends RefCounted
## Factory functions for networking/movement tests (no file I/O).


static func net_config() -> NetConfig:
	return NetConfig.new()  # defaults mirror assets/data/net/net_config.tres


static func profile(one_way_ms: int, jitter_ms: int, loss: float, seed: int = 7) -> NetSimProfile:
	var p := NetSimProfile.new()
	p.one_way_latency_ms = one_way_ms
	p.jitter_ms = jitter_ms
	p.loss = loss
	p.seed = seed
	return p


## Flat floor plus a ramp and a block, built as a PackedScene for both worlds.
static func course_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "Course"
	_box(root, "Floor", Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0), 0.0)
	_box(root, "Ramp", Vector3(4.0, 0.5, 10.0), Vector3(0.0, 1.2, -14.0), 15.0)
	_box(root, "Block", Vector3(2.0, 0.8, 2.0), Vector3(6.0, 0.4, -6.0), 0.0)
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector3(0.0, 0.05, 0.0)
	root.add_child(spawn)
	spawn.owner = root
	var dummy := Marker3D.new()
	dummy.name = "DummySpawn1"
	dummy.position = Vector3(20.0, 0.05, 20.0)
	root.add_child(dummy)
	dummy.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


## Forward, strafe, sprint, jump and crouch phases (deterministic).
static func walk_pattern() -> ScriptedInputDef:
	var d := ScriptedInputDef.new()
	d.segments = PackedVector2Array([Vector2(0, 1), Vector2(1, 0), Vector2(-0.7, 0.7), Vector2(0, -1)])
	d.ticks_per_segment = 20
	d.start_yaw_deg = 0.0
	d.yaw_deg_per_tick = 0.5
	d.sprint = true
	d.jump_interval_ticks = 23
	d.crouch_segments = PackedInt32Array([3])
	return d


static func _box(root: Node3D, n: String, size: Vector3, pos: Vector3, rot_x_deg: float) -> void:
	var body := StaticBody3D.new()
	body.name = n
	body.position = pos
	body.rotation_degrees.x = rot_x_deg
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.owner = root
	shape.owner = root
