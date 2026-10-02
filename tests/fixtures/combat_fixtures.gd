class_name CombatFixtures
extends RefCounted
## Factory functions for combat tests (weapons, feeds, a firing range scene).

const VESPER := "res://assets/data/heroes/hero_vesper_loom.tres"
const BRANNOC := "res://assets/data/heroes/hero_brannoc.tres"


static func vesper() -> HeroDef:
	return load(VESPER) as HeroDef


static func brannoc() -> HeroDef:
	return load(BRANNOC) as HeroDef


## Vesper's stats and gun without her kit (E10): a squad owner with the BASE
## squad of 3 (no Conductor +2 / +15% HP / aura), for Wardling rule tests.
static func base_commander() -> HeroDef:
	var d := vesper().duplicate() as HeroDef
	d.passive_modifiers = []
	d.wardling_aura_radius_m = 0.0
	d.conduct_radius_m = 0.0
	return d


## Full-auto test gun with a huge pool so only the fire rate gates it.
static func auto_gun(rate: float) -> WeaponDef:
	var w := WeaponDef.new()
	w.feed_kind = WeaponDef.FeedKind.MANA
	w.fire_rate = rate
	w.semi_auto = false
	w.mana_pool = 100000
	w.mana_cost = 1.0
	return w


## Breakline AR-7 magazine values (weapons-and-mods.md §3.3): 30 / 150, 1.6 s, empty 1.9 s.
static func rifle_mag() -> WeaponDef:
	var w := WeaponDef.new()
	w.feed_kind = WeaponDef.FeedKind.MAGAZINE
	w.magazine = 30
	w.reserve = 150
	w.reload_s = 1.6
	w.reload_empty_s = 1.9
	w.reload_per_round = false
	return w


## Flat floor, PlayerSpawn at the origin facing -Z, DummySpawn1 8 m ahead.
## `wall` puts a 4 x 3 m wall halfway between them.
static func range_scene(wall: bool) -> PackedScene:
	var root := Node3D.new()
	root.name = "Range"
	_box(root, "Floor", Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0))
	if wall:
		_box(root, "Wall", Vector3(4.0, 3.0, 0.5), Vector3(0.0, 1.5, -4.0))
	_marker(root, "PlayerSpawn", Vector3(0.0, 0.05, 0.0))
	_marker(root, "DummySpawn1", Vector3(0.0, 0.05, -8.0))
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


## Input that stands still facing -Z, pitched at a target's chest `dist` m
## ahead, pressing fire every `period` ticks (1 tick held).
static func shooter_input(dist: float, period: int) -> ScriptedInputDef:
	var d := ScriptedInputDef.new()
	d.segments = PackedVector2Array([Vector2.ZERO])
	d.start_yaw_deg = 0.0
	d.pitch_deg = rad_to_deg(atan2(1.1 - 1.62, dist))
	d.fire_period_ticks = period
	d.fire_hold_ticks = 1
	return d


static func idle_input() -> ScriptedInputDef:
	var d := ScriptedInputDef.new()
	d.segments = PackedVector2Array([Vector2.ZERO])
	return d


static func _marker(root: Node3D, n: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = n
	m.position = pos
	root.add_child(m)
	m.owner = root


static func _box(root: Node3D, n: String, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = n
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.owner = root
	shape.owner = root
