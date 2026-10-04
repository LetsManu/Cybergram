extends GdUnitTestSuite
## W10-W2: Whisperfang burst cadence, deterministic spread bloom/recovery, bolt travel
## (weapons-and-mods.md 3.2, 3.3).

const HZ: int = 30
const WHISPER := "res://assets/data/weapons/weapon_whisperfang.tres"
const HALO := "res://assets/data/weapons/weapon_halo_repeater.tres"


func _shots(w: WeaponSim, ticks: int, held: Callable) -> Array[int]:
	var cmd := InputCommand.new()
	var out: Array[int] = []
	for t in ticks:
		cmd.buttons = InputCommand.BTN_FIRE if held.call(t) else 0
		if w.step(cmd, t, true):
			out.append(t)
	return out


func test_burst_is_three_bolts_two_ticks_apart() -> void:
	var w := WeaponSim.new(load(WHISPER) as WeaponDef, HZ, 1)
	var shots := _shots(w, 40, func(_t: int) -> bool: return true)
	assert_int(shots[0]).is_equal(0)
	assert_int(shots[1]).is_equal(2)  # 15 shots/s at 30 Hz
	assert_int(shots[2]).is_equal(4)
	assert_int(shots[3]).is_equal(11)  # next burst: 0.35 s = 10.5 ticks later


func test_burst_completes_after_release_and_dps_band() -> void:
	var w := WeaponSim.new(load(WHISPER) as WeaponDef, HZ, 1)
	var shots := _shots(w, 30, func(t: int) -> bool: return t == 0)
	assert_int(shots.size()).is_equal(3)
	var w2 := WeaponSim.new(load(WHISPER) as WeaponDef, HZ, 1)
	var n := _shots(w2, 300, func(_t: int) -> bool: return true).size()
	# Held for 10 s: pool 100 / 4 per bolt = 25 bolts (mana-limited), 3 per 0.35 s cycle.
	assert_int(n).is_between(25, 100)
	var d := load(WHISPER) as WeaponDef
	assert_float(d.damage * d.burst_size / d.burst_cycle_s).is_equal_approx(188.57, 0.5)


func test_burst_breaks_when_not_allowed() -> void:
	var w := WeaponSim.new(load(WHISPER) as WeaponDef, HZ, 1)
	var cmd := InputCommand.new()
	cmd.buttons = InputCommand.BTN_FIRE
	assert_bool(w.step(cmd, 0, true)).is_true()
	assert_bool(w.step(cmd, 1, false)).is_false()
	assert_bool(w.step(cmd, 2, true)).is_false()  # the burst was cancelled
	assert_bool(w.step(cmd, 3, true)).is_false()


func test_spread_is_deterministic_per_seed_tick() -> void:
	var a := WeaponSim.new(load(HALO) as WeaponDef, HZ, 7)
	var b := WeaponSim.new(load(HALO) as WeaponDef, HZ, 7)
	var c := WeaponSim.new(load(HALO) as WeaponDef, HZ, 8)
	var cmd := InputCommand.new()
	cmd.buttons = InputCommand.BTN_FIRE
	a.step(cmd, 5, true)
	b.step(cmd, 5, true)
	c.step(cmd, 5, true)
	var fwd := Vector3.FORWARD
	assert_vector(a.pellet_directions(fwd)[0]).is_equal(b.pellet_directions(fwd)[0])
	assert_vector(a.pellet_directions(fwd)[0]).is_not_equal(c.pellet_directions(fwd)[0])
	# Stateless: asking twice gives the same direction.
	assert_vector(a.pellet_directions(fwd)[0]).is_equal(a.pellet_directions(fwd)[0])


func test_spread_blooms_then_recovers_and_recoil_mult_scales_it() -> void:
	var d := load(HALO) as WeaponDef
	var w := WeaponSim.new(d, HZ, 1)
	_shots(w, 20, func(_t: int) -> bool: return true)
	assert_float(w.spread_deg).is_greater(d.spread_base_deg)
	assert_float(w.spread_deg).is_less_equal(d.spread_max_deg)
	var cmd := InputCommand.new()
	for t in range(20, 200):
		w.step(cmd, t, true)
	assert_float(w.spread_deg).is_equal_approx(d.spread_base_deg, 1e-5)
	var half := WeaponSim.new(d, HZ, 1)
	half.recoil_mult = 0.5
	cmd.buttons = InputCommand.BTN_FIRE
	half.step(cmd, 0, true)
	assert_float(half.spread_deg - d.spread_base_deg).is_equal_approx(d.spread_bloom_deg * 0.5, 1e-5)


func test_bolt_travel_time_comes_from_speed() -> void:
	var d := load(HALO) as WeaponDef
	var bolts := WeaponBolts.new()
	bolts.spawn(1, d, Vector3.ZERO, Vector3.FORWARD, 0, 0.0)
	var ticks := [0]
	var resolve := func(b: WeaponBolts.Bolt, seg: float) -> bool:
		ticks[0] += 1
		return b.traveled + seg >= 30.0
	for i in 50:
		bolts.step(1.0 / HZ, resolve, func(_id: int) -> bool: return true)
	assert_int(ticks[0]).is_equal(10)  # 30 m at 90 m/s = 1/3 s = 10 ticks
	assert_int(bolts.bolts.size()).is_equal(0)


func test_bolt_dies_at_range_and_when_owner_gone() -> void:
	var d := load(HALO) as WeaponDef
	var bolts := WeaponBolts.new()
	bolts.spawn(1, d, Vector3.ZERO, Vector3.FORWARD, 0, 0.0)
	bolts.spawn(2, d, Vector3.ZERO, Vector3.FORWARD, 0, 0.0)
	bolts.step(1.0 / HZ, func(_b, _s) -> bool: return false, func(id: int) -> bool: return id == 1)
	assert_int(bolts.bolts.size()).is_equal(1)
	for i in 60:
		bolts.step(1.0 / HZ, func(_b, _s) -> bool: return false, func(_id: int) -> bool: return true)
	assert_int(bolts.bolts.size()).is_equal(0)  # 120 m range at 3 m/tick
