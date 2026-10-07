extends GdUnitTestSuite
## E11 integration: 10 bots (BotDirector, BotInputSource) on the slice map with
## Wardlings, hardpoints and match flow, through the real server tick. The
## 10-bot cases build their own 5v5 rules (Canon C1); the slice data plays 3v3.
##   1. Within a capped number of ticks a hardpoint flips and heroes die, and
##      every command the bots emit is a valid InputCommand.
##   2. A whole bot match reaches End (Uplink kill or Time-out) with a summary.

const HZ: int = 30
const ROSTER := "res://assets/data/ai/bot_roster_slice.tres"

var _invalid: Array = []
var _commands: int = 0


## Slice rules with `team_size` heroes per team (5 = Canon C1; the slice .tres is 3).
static func rules_with_team_size(team_size: int) -> MatchRulesDef:
	var r := (load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef).duplicate() as MatchRulesDef
	r.team_size = team_size
	return r


func _build(clock_scale: float, seed_: int, team_size: int = 5) -> Array:
	var built := WardlingFixtures.slice_server(self, WardlingFixtures.rules(), true, rules_with_team_size(team_size))
	var server: ServerWorld = built[0]
	auto_free(built[3])
	var def := WardlingFixtures.map_def()
	server.setup_match(def, clock_scale)
	server.wardlings.clock_scale = clock_scale
	server.enable_progression(load("res://assets/data/economy/economy_rules_slice.tres") as EconomyRulesDef,
		load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef, def)  # E15: skills must be learned
	var roster := load(ROSTER) as BotRosterDef
	var director := BotDirector.new()
	director.setup(server, roster, roster.profile("normal"), seed_)
	return [server, director]


func _check(_hero_id: int, cmd: InputCommand) -> void:
	_commands += 1
	var ok := cmd.move.length() <= 1.0 + 1e-4 \
		and cmd.yaw >= 0.0 and cmd.yaw < TAU \
		and absf(cmd.pitch) <= PI / 2.0 + 1e-4 \
		and (cmd.buttons & ~InputCommand.BUTTON_MASK) == 0 \
		and cmd.squad_cmd in [InputCommand.SQUAD_NONE, InputCommand.SQUAD_FOLLOW, InputCommand.SQUAD_HOLD,
			InputCommand.SQUAD_ATTACK, InputCommand.SQUAD_CAPTURE] \
		and cmd.squad_target >= 0 and cmd.squad_target <= 0xFFFF
	# Already at wire precision: a quantize round trip changes nothing.
	var q := cmd.duplicate_command()
	q.quantize()
	if not ok or not q.equals(cmd):
		if _invalid.size() < 5:
			_invalid.append([cmd.seq, cmd.move, cmd.yaw, cmd.pitch, cmd.buttons, cmd.squad_cmd, cmd.squad_target])


func test_ten_bots_flip_a_hardpoint_and_score_kills() -> void:
	var b := _build(1.0, 11)  # real cadence (a 10x clock floods the Mid with Vanguard waves)
	var server: ServerWorld = b[0]
	var director: BotDirector = b[1]
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server)).is_true()
	assert_int(director.fill(false)).is_equal(10)
	for src in director.sources:
		src.observer = _check
	var heroes := {0: 0, 1: 0}
	for br in director.brains:
		heroes[server.hero(br.hero_id).combat.team] += 1
	assert_dict(heroes).is_equal({0: 5, 1: 5})
	var flips := []
	server.objectives.hardpoint_flipped.connect(func(h: HardpointSim, _o: int, n: int) -> void: flips.append([h.def.id, n]))
	var kills := [0]
	server.hero_died.connect(func(_v: int, _k: int) -> void: kills[0] += 1)
	var cap := 600 * HZ  # 10:00 of match time; slice matches flip the Mid around 2:00-4:30
	while server.tick < cap and (flips.is_empty() or kills[0] == 0):
		server.step()
	var s := director.meter.summary()
	print("bots: %d ticks, flips %s, kills %d, commands %d, bot cost avg %.3f ms p95 %.3f ms/tick" % [
		server.tick, flips, kills[0], _commands, s.avg_ms, s.p95_ms])
	assert_array(flips).is_not_empty()
	assert_int(kills[0]).is_greater(0)
	assert_int(_commands).is_greater(server.tick * 9)
	if not _invalid.is_empty():
		print("invalid bot commands: %s" % [_invalid])
	assert_array(_invalid).is_empty()
	var shots := 0
	var orders := 0
	var learned := 0
	for br in director.brains:
		shots += br.shots_pressed
		orders += br.squad_orders
		learned += br.skills_learned
	assert_int(shots).is_greater(0)
	assert_int(orders).is_greater(0)
	# Every bot spends its level-1 skill point through ACTION_LEARN.
	assert_int(learned).is_greater_equal(10)
	for br in director.brains:
		var h := server.hero(br.hero_id)
		var learned_any := false
		for sk in h.combat.abilities.skills:
			learned_any = learned_any or sk.unlocked
		assert_bool(learned_any).is_true()


## Armory step 6: bots buy their guide's steps through ACTION_BUY (the same
## command a player's Armory panel sends), on the server's rules.
func test_bots_shop_their_guides_through_action_buy() -> void:
	var b := _build(1.0, 21)
	var server: ServerWorld = b[0]
	var director: BotDirector = b[1]
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server)).is_true()
	assert_int(director.fill(false)).is_equal(10)
	var buys := [0]
	for src in director.sources:
		src.observer = func(_id: int, cmd: InputCommand) -> void:
			_check(_id, cmd)
			if cmd.action == InputCommand.ACTION_BUY:
				buys[0] += 1
	var cap := 20 * HZ  # the start purse (500) buys the opening steps on spawn
	while server.tick < cap:
		server.step()
	assert_int(buys[0]).is_greater_equal(10)
	var cat := server.progression.catalog
	for br in director.brains:
		var h := server.hero(br.hero_id)
		var p: HeroProgress = server.progression.progress_of(h)
		assert_int(br.items_bought).is_greater(0)
		assert_int(p.lumen).is_greater_equal(0)
		assert_int(p.medpacks).is_greater(0)  # every guide opens with a Med-Pack
		assert_int(p.spent_lumen).is_greater_equal(cat.find(&"med_pack").price(1))
		assert_bool(br.log_lines.size() > 0 and Array(br.log_lines).any(func(l: String) -> bool: return l.contains(" buy "))).is_true()
	assert_array(_invalid).is_empty()


func test_slice_data_fills_three_v_three_with_a_hero_mix() -> void:
	var slice := load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef
	assert_int(slice.team_size).is_equal(3)  # M1 owner decision: the 1-lane slice plays 3v3
	assert_int(MatchRulesDef.new().team_size).is_equal(5)  # Canon C1
	var built := WardlingFixtures.slice_server(self, WardlingFixtures.rules(), false)
	var server: ServerWorld = built[0]
	auto_free(built[3])
	var roster := load(ROSTER) as BotRosterDef
	var director := BotDirector.new()
	director.setup(server, roster, roster.profile("normal"), 1)
	assert_int(director.team_size()).is_equal(3)
	assert_int(director.fill(false)).is_equal(6)
	var per_team := {0: {}, 1: {}}
	for br in director.brains:
		var h := server.hero(br.hero_id)
		var ids: Dictionary = per_team[h.combat.team]
		ids[h.combat.def.id] = int(ids.get(h.combat.def.id, 0)) + 1
	for t in 2:
		var ids: Dictionary = per_team[t]
		var total := 0
		for n in ids.values():
			total += int(n)
		assert_int(total).is_equal(3)
		assert_int(ids.size()).is_greater(1)  # a hero mix (the roster has four heroes since W9-H2)
	# With the local player in team 0 slot 0, the bots fill the other 5 slots.
	var d2 := BotDirector.new()
	d2.setup(server, roster, roster.profile("normal"), 2)
	assert_int(d2.fill(true)).is_equal(5)


func test_bot_match_reaches_end_with_a_summary() -> void:
	var b := _build(60.0, 5)  # 30:00 match clock in 30 s of sim time
	var server: ServerWorld = b[0]
	var director: BotDirector = b[1]
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server)).is_true()
	director.fill(false)
	var report := BotMatchReport.new(server, director, 5)
	var cap := 40 * HZ
	while server.tick < cap and not server.match_flow.is_over():
		server.step()
	assert_bool(server.match_flow.is_over()).is_true()
	assert_int(server.match_flow.end_reason).is_not_equal(MatchRules.EndReason.NONE)
	var d: Dictionary = JSON.parse_string(report.to_json())
	print("bot match summary: %s" % report.to_json())
	assert_str(d["end_reason"]).is_not_equal("none")
	assert_bool(d.has("winner")).is_true()
	assert_bool(d.has("captures")).is_true()
	assert_bool(d.has("kills")).is_true()
	assert_bool(d.has("uplink_pct_dealt")).is_true()
	assert_float(d["duration_s"]).is_greater_equal(1800.0 if d["end_reason"] != "uplink_destroyed" else 0.0)


func test_bots_siege_an_exposed_enemy_uplink() -> void:
	var b := _build(1.0, 3)
	var server: ServerWorld = b[0]
	var director: BotDirector = b[1]
	server.wardlings.vanguard_enabled = false
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server)).is_true()
	# Concord holds the whole lane, so the Syndicate Uplink is Exposed (F6).
	for h in server.objectives.all:
		server.objectives.debug_set_owner(h.def.id, MapDef.TEAM_CONCORD)
	var def := WardlingFixtures.map_def()
	var start := def.lanes[0].hardpoints[3].position  # Scrap Bazaar, ~115 m from the Uplink
	for i in 3:
		director.add_bot(MapDef.TEAM_CONCORD, load("res://assets/data/heroes/hero_vesper_loom.tres") as HeroDef,
			start + Vector3(i * 2.0 - 2.0, 0.05, 0.0))
	var u := server.match_flow.uplink_of(MapDef.TEAM_SYNDICATE)
	var sieging := 0
	while server.tick < 60 * HZ and u.integrity >= u.max_integrity - 1000.0:
		server.step()
	for br in director.brains:
		if br.goal != null and br.goal.kind == BotGoal.Kind.SIEGE:
			sieging += 1
	print("siege: %.1f s, Syndicate Uplink %.0f / %.0f, %d bots sieging" % [
		float(server.tick) / HZ, u.integrity, u.max_integrity, sieging])
	assert_bool(u.exposed).is_true()
	assert_int(sieging).is_equal(3)
	assert_float(u.integrity).is_less(u.max_integrity - 1000.0)


func test_fill_around_caps_bots_per_team_for_custom_slots() -> void:
	var built := WardlingFixtures.slice_server(self, WardlingFixtures.rules(), false)
	var server: ServerWorld = built[0]
	auto_free(built[3])
	var roster := load(ROSTER) as BotRosterDef
	var director := BotDirector.new()
	director.setup(server, roster, roster.profile("hard"), 1)
	var humans: Array[int] = [1, 0]
	var limits: Array[int] = [1, -1]
	assert_int(director.fill_around(humans, limits)).is_equal(4)  # 1 ally bot + a full enemy team of 3
	var per_team := [0, 0]
	for br in director.brains:
		per_team[server.hero(br.hero_id).combat.team] += 1
	assert_array(per_team).is_equal([1, 3])
