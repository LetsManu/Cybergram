extends GdUnitTestSuite
## E13 + E15 integration through the loopback on the slice map: the player's
## hero kills enemy Vanguard Wardlings beside it -> instant Lumen (75%) and the
## Mote it stands on (25%) plus Resonance -> level 2 -> learns a skill with an
## ACTION_LEARN input -> a buy at the Sanctum is refused -> walks to the HQ
## Armory pad -> buys Ember Heart with ACTION_BUY -> the server's weapon damage
## rises 6% and the client's replicated progress shows Lumen, level, points and
## the mounted Crystal (and the first-person gun grows a mount mesh).

const MAP_PATH := "res://assets/data/match/map_slice_lane.tres"
const C := MapDef.TEAM_CONCORD


## Walks to `goal` (navmesh) and sends queued actions, one per tick.
class Player extends WardlingFixtures.Owner:
	var queued: Array = []

	func go(to: Vector3) -> void:
		goal = to
		stop_m = 1.5
		arrived = false
		_path = PackedVector3Array()
		_i = 1

	func sample(seq: int, out: InputCommand) -> void:
		super.sample(seq, out)
		if not queued.is_empty():
			var a: Array = queued.pop_front()
			out.action = a[0]
			out.action_arg = a[1]
		out.quantize()


var _server: ServerWorld
var _client: ClientWorld
var _link: LoopbackLink
var _net: NetConfig
var _input: Player


func _tick(n: int = 1) -> void:
	for i in n:
		_link.advance(_net.tick_dt())
		_client.session.poll()
		_client.tick()
		_server.step()


func _build() -> MapDef:
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
	_server.setup_objectives(def)
	_server.setup_match(def, 1.0)
	_server.enable_wardlings(def, WardlingFixtures.rules(), load(WardlingFixtures.PICKET) as WardlingDef)
	_server.wardlings.vanguard_enabled = false
	_server.enable_progression(load("res://assets/data/economy/economy_rules_slice.tres") as EconomyRulesDef,
		load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef, def)
	_input = Player.new()
	_input.server = _server
	_client = auto_free(ClientWorld.new())
	add_child(_client)
	_client.setup(_net, movement, LookSettings.new(), def.scene, _link.create_endpoint(2), _input,
		CombatFixtures.vesper())
	_client.setup_objectives(def)
	return def


func test_kill_wardlings_level_learn_walk_to_armory_buy_crystal() -> void:
	var def := _build()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), _server)).is_true()
	_tick(10)
	var h := _server.hero(_client.session.own_net_id)
	assert_object(h).is_not_null()
	_input.hero_id = h.net_id
	var pr := _server.progression
	assert_int(_client.progress.lumen).is_equal(500)
	assert_int(_client.progress.level).is_equal(1)
	assert_int(_client.progress.skill_points).is_equal(1)
	# 10 enemy (Syndicate) Vanguard Pickets beside the hero, killed by its damage.
	var ww := _server.wardlings
	for i in 10:
		var at := h.state.position + Vector3(0.6, 0.0, 0.0)
		var w := ww._mint(ww.picket, MapDef.TEAM_SYNDICATE, at, 0)
		ww.damage_wardling(w, DamageInfo.make(9999.0, h.net_id, C))
		_tick(2)  # despawn -> bounty; the hero stands on the Mote -> 25% share
	_tick(3)
	var p := pr.progress_of(h)
	# 10 × 35 × S(1): 75% instant (26.25) + 25% Mote (8.75); fractions carry over.
	assert_int(p.earned.get(&"wardling", 0) + p.earned.get(&"mote", 0)).is_equal(350)
	assert_int(p.earned.get(&"mote", 0)).is_between(87, 90)
	assert_int(p.lumen).is_equal(850)
	assert_float(p.exp).is_equal_approx(200.0, 1e-3)  # 10 × RV_I 20 × S(1)
	assert_int(p.level).is_equal(2)
	assert_int(_client.progress.lumen).is_equal(p.lumen)
	assert_int(_client.progress.level).is_equal(2)
	assert_int(_client.progress.exp).is_equal(200)
	assert_int(_client.progress.skill_points).is_equal(2)
	assert_int(_client.combat.level).is_equal(2)
	assert_int(_client.combat.max_hp).is_equal(260)
	assert_int(_client.combat.skill_flags[0] & AbilityRunner.FLAG_LEARNABLE).is_equal(AbilityRunner.FLAG_LEARNABLE)
	# Learn S1 (Unlock) through the input path.
	assert_int(_client.combat.skill_flags[0] & AbilityRunner.FLAG_LOCKED).is_equal(AbilityRunner.FLAG_LOCKED)
	_input.queued.append([InputCommand.ACTION_LEARN, 0])
	_tick(4)
	assert_bool(h.combat.abilities.skill(0).unlocked).is_true()
	assert_int(_client.combat.skill_flags[0] & AbilityRunner.FLAG_LOCKED).is_equal(0)
	assert_int(_client.progress.skill_points).is_equal(1)
	# A buy at the Sanctum is refused (HQ Armory pad only).
	var cat := pr.catalog
	var ember := cat.index_of(&"ember_heart")
	var dmg_before := _server.weapon_hit_damage(h, 10.0)
	_input.queued.append([InputCommand.ACTION_BUY, ember | (1 << 8)])
	_tick(4)
	assert_int(_client.progress.mount_item[0]).is_equal(-1)
	assert_int(p.lumen).is_equal(850)
	# Walk to the Armory pad.
	_input.go(def.hq(C).armory)
	for i in 600:
		_tick()
		if (_client.progress.flags & SnapshotData.ProgressState.FLAG_AT_ARMORY) != 0:
			break
	assert_int(_client.progress.flags & SnapshotData.ProgressState.FLAG_AT_ARMORY).is_not_equal(0)
	_input.queued.append([InputCommand.ACTION_BUY, ember | (1 << 8)])
	_tick(4)
	assert_int(p.lumen).is_equal(450)
	assert_float(_server.weapon_hit_damage(h, 10.0)).is_equal_approx(dmg_before * 1.06, 1e-3)
	assert_float(dmg_before).is_equal_approx(29.0 * 1.025, 1e-3)  # L2 weapon multiplier
	assert_int(_client.progress.mount_item[0]).is_equal(ember)
	assert_int(_client.progress.mount_tier[0]).is_equal(1)
	assert_int(_client.progress.mount_paid_visit[0]).is_equal(400)
	assert_int(_client.progress.lumen).is_equal(450)
	assert_int(_client.rig.mount_mesh_count()).is_greater(0)
	# Leaving the pad ends the visit: the undo amount is gone (60% from now on).
	_input.go(def.hq(C).sanctum)
	for i in 600:
		_tick()
		if (_client.progress.flags & SnapshotData.ProgressState.FLAG_AT_ARMORY) == 0:
			break
	_tick(2)
	assert_int(_client.progress.mount_paid_visit[0]).is_equal(0)
	assert_int(_client.progress.mount_paid[0]).is_equal(400)
	# Mounts persist through death and respawn.
	_server.damage_hero(h, DamageInfo.make(99999.0, 0, MapDef.TEAM_SYNDICATE))
	assert_bool(h.combat.dead).is_true()
	_server.tick = h.combat.respawn_tick
	_tick(3)
	assert_bool(h.combat.dead).is_false()
	assert_float(_server.weapon_hit_damage(h, 10.0)).is_equal_approx(dmg_before * 1.06, 1e-3)
	assert_int(_client.progress.mount_item[0]).is_equal(ember)


## match-flow-and-map.md §3.5 / hud.md §9: a held, attuned Mid is a spawn
## choice; under attack (enemy hero within 25 m) it falls back to the Sanctum;
## a Beacon respawn does not reset basic cooldowns (heroes.md §3.4).
func test_mid_beacon_spawn_choice_and_fallback() -> void:
	var def := _build()
	_tick(10)
	var h := _server.hero(_client.session.own_net_id)
	var pr := _server.progression
	var mid := _server.objectives.find(&"s_mid")
	assert_object(mid).is_not_null()
	assert_bool(pr.beacon_ready(C)).is_false()  # neutral at start
	_server.objectives.debug_set_owner(&"s_mid", C)
	_tick(2)
	assert_bool(pr.beacon_ready(C)).is_false()  # 15 s attunement
	_server.match_flow.time_s += pr.rules.beacon_attune_s + 1.0
	_tick(2)  # one tick for the snapshot to reach the client
	assert_bool(pr.beacon_ready(C)).is_true()
	assert_int(_client.progress.flags & SnapshotData.ProgressState.FLAG_BEACON_READY).is_not_equal(0)
	_input.queued.append([InputCommand.ACTION_SPAWN_CHOICE, HeroProgress.SPAWN_BEACON])
	_tick(3)
	assert_int(_client.progress.flags & SnapshotData.ProgressState.FLAG_SPAWN_BEACON).is_not_equal(0)
	var at: Variant = pr.respawn_point(h)
	assert_that(at).is_not_null()
	assert_float(Vector2((at as Vector3).x - mid.def.position.x, (at as Vector3).z - mid.def.position.z).length()) \
		.is_less_equal(mid.def.zone_radius)
	# An enemy hero inside 25 m: under attack, Sanctum fallback.
	var enemy_id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		mid.def.position + Vector3(0.0, 0.05, 5.0), CombatFixtures.brannoc(), MapDef.TEAM_SYNDICATE)
	assert_bool(pr.beacon_ready(C)).is_false()
	assert_that(pr.respawn_point(h)).is_null()
	_server.abilities.teleport(_server.hero(enemy_id), def.hq(MapDef.TEAM_SYNDICATE).sanctum + Vector3(0.0, 0.05, 0.0))
	assert_bool(pr.beacon_ready(C)).is_true()
	# Die and respawn at the Beacon.
	_server.damage_hero(h, DamageInfo.make(99999.0, 0, MapDef.TEAM_SYNDICATE))
	_server.tick = h.combat.respawn_tick
	_tick(2)
	assert_bool(h.combat.dead).is_false()
	assert_float(Vector2(h.state.position.x - mid.def.position.x, h.state.position.z - mid.def.position.z).length()) \
		.is_less_equal(mid.def.zone_radius)
