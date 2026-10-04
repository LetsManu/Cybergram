extends GdUnitTestSuite
## M1 soak S2: heroes must not get over the 1.1 m lane edge rails into the
## Leyfall void. Two heroes on both sides of the open lane stretch (L 100-132)
## start airborne just above rail height and are knocked outward the way
## Brannoc's charge knocks (state.dash_velocity). With the invisible edge walls
## they land back on the lane; the control case switches the walls off and
## shows the same knock does carry them over the rail.

const MAP_PATH := "res://assets/data/match/map_slice_lane.tres"
const LANE_L := 115.0
const START_X := 7.5
const START_Y := 1.5  # above the 1.1 m rail
const KNOCK_SPEED := 12.0
const KNOCK_TICKS := 15
const TICKS := 90
const FELL_Y := -1.0

var _server: ServerWorld
var _link: LoopbackLink
var _net: NetConfig


## Returns how many of the two knocked heroes ended below FELL_Y.
func _knock_both(walls_on: bool) -> int:
	var def := load(MAP_PATH) as MapDef
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	var movement := load("res://assets/data/movement/movement_default.tres") as MovementDef
	_server.setup(_net, movement, def.scene, _link.create_endpoint(1), CombatFixtures.vesper(),
		load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)
	if not walls_on:
		for n in vp.find_children("EdgeBlock", "StaticBody3D", true, false):
			(n as StaticBody3D).collision_layer = 0
	var ids: Array[int] = []
	for s: float in [-1.0, 1.0]:
		ids.append(_server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
			Vector3(s * START_X, START_Y, -LANE_L), CombatFixtures.vesper()))
	await get_tree().physics_frame
	for i in ids.size():
		var h := _server.hero(ids[i])
		h.state.dash_velocity = Vector3(-KNOCK_SPEED if i == 0 else KNOCK_SPEED, 0.0, 0.0)
		h.state.dash_ticks = KNOCK_TICKS
		h.state.dash_launch = false
	var fell := {}
	for t in TICKS:
		_link.advance(_net.tick_dt())
		_server.step()
		for id in ids:
			if _server.hero(id).global_position.y < FELL_Y:
				fell[id] = true
	return fell.size()


func test_edge_walls_keep_knocked_heroes_on_the_lane() -> void:
	assert_int(await _knock_both(true)).is_equal(0)


func test_control_without_walls_the_knock_clears_the_rail() -> void:
	assert_int(await _knock_both(false)).is_equal(2)
