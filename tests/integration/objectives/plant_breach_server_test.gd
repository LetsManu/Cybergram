extends GdUnitTestSuite
## E14 integration: Plant and Breach on the slice map through the real server
## tick (InputCommand -> HeroSim -> ObjectiveSystem), with the slice rules (tasks
## live). Concord already holds the Mid (debug setup).
##   1. A Concord hero holds Interact at the Mid Cradle (1 s), carries the Cell at
##      90 % speed (5.4 m/s ±2 %, AC 7), plants it in Scrap Bazaar (3 s) and
##      stays until the charge flips S-BO (F3, 75 s ±1 s).
##   2. With S-BO held, hitscan from outside Furnace Gate's zone does nothing; from
##      inside it hurts the Generator; a Wardling bolt counts 50 %; the Generator
##      falls, the 20 s hold flips S-BI and the Syndicate Uplink is Exposed.

const HZ: int = 30
const C := MapDef.TEAM_CONCORD
const S := MapDef.TEAM_SYNDICATE


## Walks (Owner), and optionally holds Interact or fires at a point once arrived.
## Fires in bursts that keep the mana pool out of Burnout (refill above 90 %).
class TaskHero extends WardlingFixtures.Owner:
	var interact: bool = false
	var fire_at: Vector3 = Vector3.INF
	var _resting: bool = false

	func go(to: Vector3, stop: float) -> void:
		goal = to
		stop_m = stop
		arrived = false
		_path = PackedVector3Array()
		_i = 1

	func sample(seq: int, out: InputCommand) -> void:
		super.sample(seq, out)
		var h := server.hero(hero_id)
		if h == null or not arrived:
			return
		if interact:
			out.buttons |= InputCommand.BTN_INTERACT
		if fire_at != Vector3.INF:
			var eye := h.state.position + Vector3(0.0, h.eye_height(), 0.0)
			var to := fire_at - eye
			out.yaw = fposmod(atan2(-to.x, -to.z), TAU)
			out.pitch = atan2(to.y, Vector2(to.x, to.z).length())
			var f := h.combat.weapon.feed
			var frac := f.current() / maxf(f.capacity(), 1.0)
			_resting = frac < 0.9 if _resting else frac < 0.3
			if seq % 2 == 0 and not _resting:
				out.buttons |= InputCommand.BTN_FIRE
		out.quantize()


var _server: ServerWorld


func _build() -> MapDef:
	var built := WardlingFixtures.slice_server(self, WardlingFixtures.rules(), false)
	_server = built[0]
	auto_free(built[3])
	var def := WardlingFixtures.map_def()
	_server.setup_match(def, 1.0)
	_server.match_flow.debug_start_s = 120.0  # Skirmish: Mids unlocked
	assert_bool(_server.rules.stage_all_as_hold).is_false()
	return def


func _hero(start: Vector3) -> TaskHero:
	var t := TaskHero.new()
	t.server = _server
	t.hero_id = _server.add_scripted_hero(t, start, CombatFixtures.vesper(), C)
	return t


func _ticks(n: int, until: Callable = Callable()) -> int:
	for i in n:
		_server.step()
		if until.is_valid() and until.call():
			return i + 1
	return -1


func test_a_hero_carries_plants_and_charges_a_cell_to_flip_scrap_bazaar() -> void:
	_build()
	var objs := _server.objectives
	objs.debug_set_owner(&"s_mid", C)
	var bo := objs.find(&"s_bo")
	assert_bool(await WardlingFixtures.await_nav(get_tree(), _server)).is_true()
	_ticks(2)
	assert_int(bo.cell_state).is_equal(HardpointSim.CellState.CRADLE)
	var cradle := bo.cell_pos
	var t := _hero(cradle + Vector3(0.0, 0.05, 1.0))
	t.go(cradle, 1.5)
	t.interact = true
	var took := _ticks(HZ * 5, func() -> bool: return bo.cell_state == HardpointSim.CellState.CARRIED)
	assert_int(took).is_between(roundi(_server.rules.cell_pickup_s * HZ), roundi(_server.rules.cell_pickup_s * HZ) + 3)
	assert_int(bo.carrier_id).is_equal(t.hero_id)
	# Walk to the Socket: measure the carrier's ground speed on a straight stretch.
	t.interact = false
	t.go(bo.def.position + Vector3(0.0, 0.0, 1.0), 2.0)
	var h := _server.hero(t.hero_id)
	_ticks(HZ)  # accelerate
	var p0 := h.state.position
	_ticks(HZ * 2)
	var speed := Vector2(h.state.position.x - p0.x, h.state.position.z - p0.z).length() / 2.0
	var expect := h.motor.def.base_move_speed * _server.rules.cell_carrier_speed_mult
	assert_float(speed).is_between(expect * 0.98, expect * 1.02)
	_ticks(HZ * 30, func() -> bool: return t.arrived)
	assert_bool(t.arrived).is_true()
	t.interact = true
	var plant := _ticks(HZ * 6, func() -> bool: return bo.cell_state == HardpointSim.CellState.PLANTED)
	assert_int(plant).is_between(roundi(_server.rules.plant_channel_s * HZ), roundi(_server.rules.plant_channel_s * HZ) + 3)
	t.interact = false
	var flip := _ticks(HZ * 90, func() -> bool: return bo.owner == C)
	assert_float(flip / float(HZ)).is_between(bo.base_s - 1.0, bo.base_s + 1.0)


func test_generator_takes_hitscan_only_from_inside_its_zone_and_the_breach_exposes_the_uplink() -> void:
	_build()
	var objs := _server.objectives
	objs.debug_set_owner(&"s_mid", C)
	objs.debug_set_owner(&"s_bo", C)
	var bi := objs.find(&"s_bi")
	var g := _server.generator_of(bi)
	assert_object(g).is_not_null()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), _server)).is_true()
	# Outside the zone (20 m short of the Generator, clear line of fire): shielded.
	var out_pos := bi.def.position + Vector3(0.0, 0.0, 20.0)
	var t := _hero(out_pos + Vector3(0.0, 0.05, 0.0))
	t.go(out_pos, 2.0)
	t.fire_at = g.aim_point()
	_ticks(HZ * 3)
	assert_float(bi.gen_frac).is_equal(1.0)
	# Inside the zone: hitscan lands.
	t.go(bi.def.position + Vector3(4.0, 0.0, 6.0), 1.5)
	_ticks(HZ * 6)
	assert_float(bi.gen_frac).is_less(1.0)
	# A Wardling bolt (raw 10) from inside the zone counts 50 %.
	var before := bi.generator_hp()
	var from := g.aim_point() + Vector3(0.0, 0.0, 6.0)
	_server.wardlings.projectiles.spawn(from, Vector3.FORWARD, 55.0, 12.0, 10.0, C, 0, g.aim_point())
	t.fire_at = Vector3.INF
	_ticks(8)
	assert_float(before - bi.generator_hp()).is_equal_approx(10.0 * _server.rules.generator_wardling_damage_scale, 0.01)
	# Shoot it down, then hold 20 s (1 hero alone: Δ 1.0, M 0.64 -> 31.25 s).
	t.fire_at = g.aim_point()
	var down := _ticks(HZ * 180, func() -> bool: return bi.breach_phase == 2)
	assert_int(down).is_greater(0)
	assert_object(_server.wardlings.live_entity(g.net_id)).is_null()
	t.fire_at = Vector3.INF
	var su := _server.match_flow.uplink_of(S)
	assert_bool(su.exposed).is_false()
	var flip := _ticks(HZ * 45, func() -> bool: return bi.owner == C)
	assert_float(flip / float(HZ)).is_between(bi.base_s / 0.64 - 1.0, bi.base_s / 0.64 + 1.0)
	_ticks(1)
	assert_bool(su.exposed).is_true()
