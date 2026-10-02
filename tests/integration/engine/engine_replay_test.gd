extends GdUnitTestSuite
## Verification list item 3 (architecture.md §15, ADR-0002 "Verification Required" 3):
## does calling CharacterBody3D.move_and_slide() several times within one physics
## frame (reconciliation replay) reproduce one-call-per-frame results under Jolt,
## including floor snapping and is_on_floor()?
## Results are recorded in docs/architecture/verification-4.7.md.

const _FRAMES: int = 90
const _JUMP_FRAMES: Array[int] = [20, 70]
const _RESTORE_POINTS: Array[int] = [5, 19, 21, 25, 40, 59, 65, 71, 80]
const _RUN_SPEED: float = 6.0
const _GRAVITY: float = 20.0
const _JUMP_SPEED: float = 7.0
const _PRIME_SPEED: float = 0.01
const _EXACT: float = 1e-5
## Measured on 4.7 + Jolt: priming makes most restore points bit-exact, but a
## restore right after a sharp direction change still differs by ~45 µm (hidden
## contact state priming does not rebuild). Asserted bound: 1 mm, i.e. 20x below
## NetConfig.reconcile_epsilon_m (0.02), so replay never triggers a correction.
const _REPLAY_TOLERANCE: float = 1e-3

var _body: CharacterBody3D


func before_test() -> void:
	_body = _build_course()


func _box(size: Vector3, pos: Vector3, rot_z_deg: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	body.rotation_degrees.z = rot_z_deg
	return body


func _build_course() -> CharacterBody3D:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	root.add_child(_box(Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0)))
	root.add_child(_box(Vector3(6.0, 1.0, 6.0), Vector3(8.0, 0.3, 0.0), 20.0))  # ramp
	root.add_child(_box(Vector3(2.0, 0.4, 6.0), Vector3(16.0, 0.2, 0.0)))  # step
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = capsule.height / 2.0
	body.add_child(shape)
	body.position = Vector3(0.0, 0.05, 0.0)
	root.add_child(body)
	return body


## Scripted velocity: run +x over a ramp and step, jump twice, then turn back.
func _velocity_for(frame: int, current: Vector3) -> Vector3:
	var horizontal := Vector3(_RUN_SPEED, 0.0, 0.0)
	if frame >= 60:
		horizontal = Vector3(-_RUN_SPEED, 0.0, _RUN_SPEED / 3.0)
	var vy := current.y - _GRAVITY * _body.get_physics_process_delta_time()
	if _body.is_on_floor():
		vy = -_PRIME_SPEED
	if frame in _JUMP_FRAMES:
		vy = _JUMP_SPEED
	return Vector3(horizontal.x, vy, horizontal.z)


func _run(from_frame: int, to_frame: int, out: Array) -> void:
	for i in range(from_frame, to_frame):
		_body.velocity = _velocity_for(i, _body.velocity)
		_body.move_and_slide()
		out.append([_body.global_position, _body.velocity, _body.is_on_floor()])


func _record_live() -> Array:
	await get_tree().physics_frame
	var live: Array = []
	for i in _FRAMES:
		await get_tree().physics_frame
		_run(i, i + 1, live)
	return live


func test_full_replay_in_one_frame_matches_per_frame_run() -> void:
	var start := _body.global_position
	var live: Array = await _record_live()
	_body.global_position = start
	_body.velocity = Vector3.ZERO
	var replay: Array = []
	_run(0, _FRAMES, replay)
	for i in _FRAMES:
		assert_float((live[i][0] - replay[i][0]).length()).is_less(_EXACT)
		assert_bool(replay[i][2]).is_equal(live[i][2])


func test_partial_replay_with_contact_priming_matches_per_frame_run() -> void:
	var live: Array = await _record_live()
	for k in _RESTORE_POINTS:
		var prev: Array = live[k - 1]
		# Restoring position + velocity is not enough: CharacterBody3D keeps hidden
		# floor/wall contact state from its last call. One tiny move toward the
		# recorded contact state rebuilds it, then the real state is restored.
		_body.global_position = prev[0]
		_body.velocity = Vector3(0.0, -_PRIME_SPEED if prev[2] else _PRIME_SPEED, 0.0)
		_body.move_and_slide()
		_body.global_position = prev[0]
		_body.velocity = prev[1]
		var replay: Array = []
		_run(k, _FRAMES, replay)
		for j in replay.size():
			assert_float((live[k + j][0] - replay[j][0]).length()).is_less(_REPLAY_TOLERANCE)
			assert_bool(replay[j][2]).is_equal(live[k + j][2])
