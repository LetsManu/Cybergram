class_name BotBrain
extends RefCounted
## One bot's mind (architecture.md §9, ADR-0005 §2-3). Server-only.
##   decide()  at BotProfile.decision_hz, staggered by slot: blackboard from
##             match state + BotSensor -> GoalSelector -> skill and squad rules.
##   produce() every tick: navigation, AimHumanizer, trigger, reload, skill
##             press and squad order -> one InputCommand (the same message a
##             human client sends; HeroSim cannot tell the difference).
## Deterministic for a given seed: its RNG is seeded by the director.

const FIRE_ALT_TICKS: int = 2  # semi-auto: press every other tick
const SKILL_TIMEOUT_S: float = 1.0
const SKILL_POINT_TOL_DEG: float = 6.0
const LOOK_AHEAD_M: float = 8.0
const SPRINT_MIN_M: float = 14.0
const LOG_MAX: int = 256
const TRIPWIRE_B_WINDOW_S: float = 4.0
const SENSOR_CHEST_Y: float = 1.1

var server: ServerWorld
var profile: BotProfile
var hero_id: int = 0
var slot: int = 0
var rng := RandomNumberGenerator.new()
var bb := BotBlackboard.new()
var selector := GoalSelector.new()
var goal: BotGoal = null
var sensor: BotSensor
var aim: AimHumanizer
var nav: BotNavigator
var decide_every: int = 3
var decisions: int = 0
## Goal transitions "t<tick> <from>-><to>" (bounded; architecture.md §9 logging).
var log_lines: PackedStringArray = PackedStringArray()
## Counters for tests and the match report.
var shots_pressed: int = 0
var skills_pressed: int = 0
var squad_orders: int = 0
## Ticks alive spent in each BotGoal.Kind, and wall-clock µs spent in decide().
var goal_ticks: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
var decide_usec: int = 0

var _tick_hz: int = 30
var _wander: Vector3 = Vector3.ZERO
var _strafe: float = 1.0
var _strafe_until: int = 0
var _mana_pause: bool = false
var _pending_skill: BotSkillRules.SkillUse = null
var _skill_deadline: int = 0
var _skill_pressed_tick: int = -10
var _squad_cmd: int = InputCommand.SQUAD_NONE
var _squad_target: int = 0
var _last_order_tick: int = -1000000
var _was_dead: bool = true
var _blank := InputCommand.new()
## Skill slots in learning priority (BotRosterDef.build_orders); E15 points.
var build_order: PackedInt32Array = PackedInt32Array([3, 0, 1, 2, 0, 1, 2])
## W10-T1 Fork choice per basic slot (1 = A, 2 = B; BotRosterDef.fork_prefs).
var fork_prefs: PackedInt32Array = PackedInt32Array([1, 1, 1])
var _learn_choice: int = 0
var skills_learned: int = 0
var _learn_slot: int = -1
var _learn_key: int = -1
var _calm_ready: bool = false
var _calm_move: Vector2 = Vector2.ZERO
var _calm_buttons: int = 0
## E14: every brain of the match (BotDirector.brains, shared) and the shared Cell
## job claims ("<team>:<hardpoint>:<job>" -> hero net id), so one bot per team
## takes each Cell job.
var team_brains: Array = []
var claims: Dictionary = {}
## W14: shared lane planner (null = lane 0). `lane` = this bot's lane this decision.
var lanes: BotLanePlanner
var lane: int = 0
var interacts: int = 0
## W10-W3 thresholds (BotRosterDef.skill_tuning) and behaviour counters for
## tests and the match report.
var tuning := BotSkillTuning.new()
var beam_ticks: int = 0
var detonations: int = 0
var wires_placed: int = 0
var hops_used: int = 0
var _beam_id: int = 0
var _wire_cache: Dictionary = {}
var _wire_ray := PhysicsRayQueryParameters3D.new()
var _beam_hold_range: float = 14.0
## Armory step 6: bots shop through the same ACTION_BUY a player's Armory
## panel sends, choosing with the same BuildAdvisor and the hero's default
## guide (docs/armory.md). `builds` is injected by the director, else loaded.
var builds: RecommendedBuildsDef
var items_bought: int = 0
## Armory v2: items sold to make room in the open slots (items-and-armory.md §3.10 rule 6).
var items_sold: int = 0
var _shop_arg: int = -1
var _sell_arg: int = -1
var _shop_key: String = ""
## Armory v2: catalog indices the bot's guide may use (steps, choices and
## every recipe part below them); a loose item outside it may be sold.
var _plan: Dictionary = {}
var _plan_guide: RecommendedBuildDef


func _init(s: ServerWorld, p: BotProfile, seed_: int, slot_: int) -> void:
	server = s
	profile = p
	slot = slot_
	rng.seed = seed_
	_tick_hz = s.net.tick_rate_hz
	bb.tick_hz = _tick_hz
	decide_every = maxi(1, roundi(_tick_hz / maxf(p.decision_hz, 0.1)))
	sensor = BotSensor.new(s, p)
	_wire_ray.collision_mask = HeroBody.LAYER_WORLD
	aim = AimHumanizer.new(p, rng, _tick_hz)
	nav = BotNavigator.new(s.get_world_3d().navigation_map, _tick_hz)


func hero() -> HeroBody:
	return server.hero(hero_id)


## Called by the director when this bot's hero took damage.
func on_damaged(attacker_id: int, tick: int) -> void:
	bb.last_damaged_tick = tick
	bb.last_attacker_id = attacker_id


## Fills `out` for tick `tick` (ServerWorld calls it through BotInputSource).
func produce(tick: int, out: InputCommand) -> void:
	out.copy_from(_blank)  # every field reset (ServerWorld reuses one command object)
	out.seq = tick
	out.view_tick = tick  # ADR-0005 §4: no rewind advantage
	var h := hero()
	if h == null or h.combat.dead:
		_was_dead = true
		aim.set_target(0, tick)
		out.yaw = aim.yaw
		out.pitch = aim.pitch
		if h != null and (tick + slot) % decide_every == 0:
			_decide_spawn(h, out)
		out.quantize()
		return
	if _was_dead:
		_was_dead = false
		aim.yaw = h.look_yaw
		aim.pitch = 0.0
		nav.clear()
		goal = null
		bb.current_goal = -1
		_pending_skill = null
		_beam_id = 0
	if (tick + slot) % decide_every == 0 or goal == null:
		var t0 := Time.get_ticks_usec()
		decide(tick, h)
		decide_usec += Time.get_ticks_usec() - t0
	goal_ticks[goal.kind] += 1
	_act(tick, h, out)
	out.quantize()


## One decision: blackboard -> goal -> skill / squad intents.
func decide(tick: int, h: HeroBody) -> void:
	decisions += 1
	_fill_blackboard(tick, h)
	sensor.scan(h, aim.yaw, bb, goal != null and goal.kind == BotGoal.Kind.SIEGE)
	var g := selector.pick(bb, profile)
	if g == null:
		g = selector.goal(BotGoal.Kind.PUSH)
	if goal == null or g.kind != goal.kind:
		_log_transition(tick, goal, g)
		if goal != null and goal.kind == BotGoal.Kind.RETREAT and bb.hp_frac < profile.return_hp_frac:
			bb.retreat_block_until_tick = tick + roundi(profile.retreat_cooldown_s * _tick_hz)
		goal = g
		bb.current_goal = g.kind
		bb.goal_since_tick = tick
		_new_wander()
	if sensor.target_visible:
		aim.set_target(bb.target_id, tick)
	else:
		aim.set_target(0, tick)
	_decide_learn(h)
	_decide_shop(tick, h)
	_decide_beam(tick, h)
	_decide_skill(tick, h)
	_decide_squad(tick, h)


func _fill_blackboard(tick: int, h: HeroBody) -> void:
	var c := h.combat
	bb.tick = tick
	bb.team = c.team
	bb.pos = h.state.position
	bb.hp_frac = c.health.hp / maxf(c.def.max_hp, 1.0)
	bb.ammo_frac = _ammo_frac(c)
	var md := server.wardlings.map_def if server.wardlings != null else null
	if md != null and md.hq(c.team) != null:
		bb.home_pos = md.hq(c.team).sanctum
	bb.front_index = BotBlackboard.NO_HARDPOINT
	bb.front_task_progress = 0.0
	bb.defend_index = BotBlackboard.NO_HARDPOINT
	var objs := server.objectives
	if objs != null and not objs.lanes.is_empty():
		_plan_lanes(objs, md, c.team)
		lane = clampi(lanes.lane_of(hero_id, c.team) if lanes != null else 0, 0, objs.lanes.size() - 1)
		var li := lane
		var lane: Array = objs.lanes[li]
		var fi := objs.front.front_for(c.team, li)
		if fi >= 0:
			var fh: HardpointSim = lane[fi]
			bb.front_index = objs.global_index(fh)  # map-wide (Go Capture on any lane)
			bb.front_pos = fh.def.position
			bb.front_radius = fh.def.zone_radius
			bb.front_is_own = fh.owner == c.team
			bb.front_task_progress = _task_progress(fh, c.team)
		var best_d := INF
		for hp in lane:
			var hs := hp as HardpointSim
			if hs.owner == c.team and hs.is_under_attack() and (hs.cell_state != HardpointSim.CellState.CARRIED \
					or BotBlackboard.flat_dist(hs.cell_pos, hs.def.position) <= profile.defend_carrier_radius_m):
				# E14: Generator hit, Cell planted, or an enemy carrier closing in
				var d := BotBlackboard.flat_dist(bb.pos, hs.def.position)
				if d < best_d:
					best_d = d
					bb.defend_index = objs.global_index(hs)
					bb.defend_pos = hs.def.position
					bb.defend_radius = hs.def.zone_radius
					bb.defend_progress = hs.pressure()
		_fill_tasks(objs, lane, fi, c.team)
	bb.enemy_uplink_exposed = false
	var mf := server.match_flow
	if mf != null and mf.is_live():
		var u := mf.uplink_of(1 - c.team)
		if u != null and u.exposed and not u.is_destroyed():
			bb.enemy_uplink_exposed = true
			bb.enemy_uplink_id = u.net_id
			bb.enemy_uplink_pos = u.aim_point()
			bb.siege_pos = _siege_point(u, c.team)
			_fill_regroup(u, c.team)


## W14: on a multi-lane map, one bot per team evaluation re-spreads the team
## over the lanes by need (BotLanePlanner; weights in BotProfile "Lanes").
func _plan_lanes(objs: ObjectiveSystem, md: MapDef, team: int) -> void:
	if lanes == null or objs.lanes.size() <= 1 or md == null:
		return
	for b in team_brains:  # every bot of the team holds an assignment
		var br := b as BotBrain
		var bh := br.hero()
		if bh != null:
			lanes.lane_of(br.hero_id, bh.combat.team)
	var now_s := float(bb.tick) / float(maxi(_tick_hz, 1))
	if not lanes.due(team, now_s):
		return
	var dead := {}
	for b in team_brains:
		var bh := (b as BotBrain).hero()
		if bh != null and bh.combat.team == team and bh.combat.dead:
			dead[(b as BotBrain).hero_id] = true
	var moved := lanes.rebalance(team, lane_need(objs, md, team, _all_heroes(), profile), dead, now_s)
	if moved != 0:
		print("[bots] team %d: hero %d -> lane %d (need-based rebalance)" % [team, moved, lanes.assignment[moved]])


func _all_heroes() -> Array:
	var out := []
	for id in server.registry.ids():
		var h := server.registry.get_node_by_id(id) as HeroBody
		if h != null and h.combat != null:
			out.append(h)
	return out


## W14 per-lane need for `team` (BotProfile "Lanes" weights): base, own
## hardpoints under attack, enemy heroes in the lane (nearest lane by x) and
## whether the enemy holds one of our Outer / Inner hardpoints there.
static func lane_need(objs: ObjectiveSystem, md: MapDef, team: int, heroes: Array, p: BotProfile) -> PackedFloat32Array:
	var need := PackedFloat32Array()
	need.resize(objs.lanes.size())
	for li in objs.lanes.size():
		need[li] = p.lane_need_base
		for hp in objs.lanes[li]:
			var hs := hp as HardpointSim
			if hs.owner == team and hs.is_under_attack():
				need[li] += p.lane_need_attacked
			elif hs.owner == 1 - team and hs.def.tier != HardpointDef.Tier.MID and hs.def.initial_owner == team:
				need[li] += p.lane_need_losing
	for h in heroes:
		var hb := h as HeroBody
		if hb == null or hb.combat.dead or hb.combat.team == team:
			continue
		var hq := md.hq(1 - team)
		if hq != null and BotBlackboard.flat_dist(hb.state.position, hq.sanctum) < 45.0:
			continue  # still at home
		need[md.nearest_lane(hb.state.position)] += p.lane_need_enemy_hero
	return need


## E14: how far `team` has got with the task on hardpoint `hs` (0..~1.5).
static func _task_progress(hs: HardpointSim, team: int) -> float:
	if hs.owner == team:
		return 0.0
	var p := hs.progress if hs.capturing_team == team else 0.0
	match hs.task:
		HardpointDef.TaskKind.PLANT:
			if hs.cell_team == team and hs.cell_state == HardpointSim.CellState.PLANTED:
				return 0.3 + p
		HardpointDef.TaskKind.BREACH:
			if hs.owner != MapDef.TEAM_NEUTRAL and hs.eligible[team]:
				return 0.5 + p if hs.breach_phase == 2 else 1.0 - hs.gen_frac
	return p


## E14: the bot's Cell job (Plant) and the enemy Generator to shoot (Breach).
func _fill_tasks(objs: ObjectiveSystem, lane: Array, front: int, team: int) -> void:
	bb.cell_job = BotBlackboard.CellJob.NONE
	bb.generator_id = 0
	var mine := objs.carried_by(hero_id)
	bb.carrying = mine != null
	if front >= 0:
		var fh: HardpointSim = lane[front]
		if fh.generator_attackable_by(team):
			var g := server.generator_of(fh)
			if g != null:
				bb.generator_id = g.net_id
				bb.generator_pos = g.global_position
				bb.generator_zone_radius = fh.def.zone_radius
	if mine != null:
		_set_job(BotBlackboard.CellJob.PLANT, mine.def.position, mine.def.zone_radius * 0.45)
		return
	var best := BotBlackboard.CellJob.NONE
	for hp in lane:
		var hs := hp as HardpointSim
		if hs.task != HardpointDef.TaskKind.PLANT or hs.owner == MapDef.TEAM_NEUTRAL:
			continue
		var rules := objs.rules
		if hs.owner != team and hs.cell_team == team:
			if hs.cell_state == HardpointSim.CellState.CRADLE and _claim(team, hs, "pickup", hs.cell_pos):
				_set_job(BotBlackboard.CellJob.PICKUP, hs.cell_pos, rules.cell_interact_radius_m * 0.4)
				best = BotBlackboard.CellJob.PICKUP
			elif hs.cell_state == HardpointSim.CellState.DROPPED and _claim(team, hs, "touch", hs.cell_pos):
				_set_job(BotBlackboard.CellJob.TOUCH, hs.cell_pos, rules.cell_touch_radius_m * 0.4)
				best = BotBlackboard.CellJob.TOUCH
		elif hs.owner == team and hs.cell_team == 1 - team:
			if hs.cell_state == HardpointSim.CellState.PLANTED and _claim(team, hs, "defuse", hs.def.position):
				_set_job(BotBlackboard.CellJob.DEFUSE, hs.def.position, hs.def.zone_radius * 0.45)
				return  # defusing comes first
			if hs.cell_state == HardpointSim.CellState.DROPPED and best == BotBlackboard.CellJob.NONE \
					and BotBlackboard.flat_dist(bb.pos, hs.cell_pos) < profile.disperse_range_m and _claim(team, hs, "disperse", hs.cell_pos):
				_set_job(BotBlackboard.CellJob.DISPERSE, hs.cell_pos, rules.cell_touch_radius_m * 0.4)


func _set_job(job: int, at: Vector3, radius: float) -> void:
	bb.cell_job = job
	bb.cell_job_pos = at
	bb.cell_job_radius = radius


## One bot per team takes a Cell job: the live, non-carrying bot nearest to `at`
## when the job appears; it keeps the claim while alive and no more than
## profile.cell_claim_hysteresis_m worse off than the nearest. True if this bot holds the claim.
func _claim(team: int, hs: HardpointSim, job: String, at: Vector3) -> bool:
	var key := "%d:%s:%s" % [team, hs.def.id, job]
	var best_id := 0
	var best_d := INF
	var holder_d := INF
	var holder: int = claims.get(key, 0)
	for b in team_brains:
		var br := b as BotBrain
		var h := br.hero()
		if h == null or h.combat.dead or h.combat.team != team or server.objectives.carried_by(br.hero_id) != null:
			continue
		var d := BotBlackboard.flat_dist(h.state.position, at)
		if br.hero_id == holder:
			holder_d = d
		if d < best_d:
			best_d = d
			best_id = br.hero_id
	if holder != 0 and holder_d < INF and holder_d <= best_d + profile.cell_claim_hysteresis_m:
		best_id = holder
	claims[key] = best_id
	return best_id == hero_id


## Where to shoot the Exposed Uplink from (E14): inside the enemy HQ gate,
## profile.siege_range_m from the core on the lane side, so every weapon is in
## its damage band (the Inner zone edge was ~48 m out: shotguns barely scored).
## The held Inner stays held (retaking it is a Breach). Without a lane, 30 m short.
func _siege_point(u: UplinkSim, team: int) -> Vector3:
	var objs := server.objectives
	var mf := server.match_flow
	if objs != null:
		for hs in objs.all:
			if hs.owner == team and mf.half_of(hs) == u.team and hs.def.tier == HardpointDef.Tier.INNER:
				var to := Vector3(hs.def.position.x - u.base.x, 0.0, hs.def.position.z - u.base.z)
				return u.base + to.normalized() * profile.siege_range_m
	var back := bb.home_pos - u.base
	back.y = 0.0
	return u.base + back.normalized() * 30.0


## E14 spawn choice (match-flow §3.5 Forward Beacon, C11): while the team pushes
## past the Mid (its front is an enemy Outer / Inner, or the enemy Uplink is
## Exposed), respawn at the Mid Beacon (11 s from the enemy Outer instead of
## 46 s from the Sanctum, but no squad); otherwise at the Sanctum for a squad.
## Sent as ACTION_SPAWN_CHOICE while dead, like a player's spawn-select click.
func _decide_spawn(h: HeroBody, out: InputCommand) -> void:
	var prog = server.get("progression")
	var objs := server.objectives
	if prog == null or objs == null or objs.lanes.is_empty() or not profile.beacon_spawn:
		return
	var team := h.combat.team
	var li := clampi(lane, 0, objs.lanes.size() - 1)
	var lane: Array = objs.lanes[li]
	var mid := lane.size() / 2
	var fi := objs.front.front_for(team, li)
	var past_mid := fi >= 0 and (fi > mid if team == MapDef.TEAM_CONCORD else fi < mid) \
		and (lane[fi] as HardpointSim).owner != team
	var mf := server.match_flow
	if mf != null and mf.uplink_of(1 - team) != null and mf.uplink_of(1 - team).exposed:
		past_mid = true
	var want := HeroProgress.SPAWN_BEACON if past_mid and (lane[mid] as HardpointSim).owner == team \
		else HeroProgress.SPAWN_SANCTUM
	if prog.progress_of(h).spawn_choice != want:
		out.action = InputCommand.ACTION_SPAWN_CHOICE
		out.action_arg = want


## E14 regroup before the siege: staging point siege_stage_m out from the enemy
## Uplink toward the lane, the live allies there, and whether this bot is in.
func _fill_regroup(u: UplinkSim, team: int) -> void:
	var to := Vector3(bb.siege_pos.x - u.base.x, 0.0, bb.siege_pos.z - u.base.z).normalized()
	bb.siege_stage_pos = u.base + to * profile.siege_stage_m
	var n := 0
	var inside := 0
	var list: Array = server.wardlings.heroes() if server.wardlings != null else []
	for item in list:
		var a := item as HeroBody
		if a.combat.dead or a.combat.team != team:
			continue
		var d := BotBlackboard.flat_dist(a.state.position, u.base)
		if d <= profile.siege_commit_m:
			inside += 1
		elif BotBlackboard.flat_dist(a.state.position, bb.siege_stage_pos) <= profile.siege_stage_radius_m:
			n += 1
	bb.siege_allies_staged = n
	var me_in := BotBlackboard.flat_dist(bb.pos, u.base) <= profile.siege_commit_m
	bb.siege_committed = me_in or inside > 0 or n >= profile.siege_group_min


## E15 skill points: the first slot of the build order the server would accept
## (dry run), sent as an ACTION_LEARN command like a player's Alt + skill key.
func _decide_learn(h: HeroBody) -> void:
	var prog = server.get("progression")
	if prog == null or _learn_slot >= 0:
		return
	var p: HeroProgress = prog.progress_of(h)
	if p.skill_points() < 1:
		return
	# E14 bot cost: points stay banked once the reduced tree is full, so only
	# re-run the dry runs when the level or the spent count changed.
	var key := p.level * 1000 + p.spent
	if key == _learn_key:
		return
	_learn_key = key
	for s in build_order:
		var r: int = prog.can_learn(h, s)
		if r == HeroProgress.Result.OK:
			_learn_slot = s
			_learn_choice = 0
			_learn_key = -1  # re-check after this point is spent
			return
		if r == HeroProgress.Result.FORK_CHOICE and s >= 0 and s < fork_prefs.size():
			_learn_slot = s  # W10-T1: Fork point, the choice comes from the roster data
			_learn_choice = fork_prefs[s]
			_learn_key = -1
			return


func _decide_skill(tick: int, h: HeroBody) -> void:
	if _pending_skill != null and tick < _skill_deadline:
		return
	_pending_skill = null
	var ab := h.combat.abilities
	if bb.carrying or ab.is_casting() or ab.is_dashing():
		return  # E14: a carrier uses no skills (mobility drops the Cell)
	var det := _decide_detonation(tick, h)
	if det != null:
		_pending_skill = det
		_skill_deadline = tick + roundi(SKILL_TIMEOUT_S * _tick_hz)
		detonations += 1
		return
	if rng.randf() >= profile.skill_use_chance:
		return
	var zone_c := Vector3.ZERO
	var zone_r := 0.0
	if goal != null and goal.kind == BotGoal.Kind.DEFEND:
		zone_c = bb.defend_pos
		zone_r = bb.defend_radius
	elif bb.front_index >= 0:
		zone_c = bb.front_pos
		zone_r = bb.front_radius
	var ready := func(s: int) -> bool: return _skill_ready(h, s, tick)
	var use := _decide_special(tick, h, zone_c, zone_r)
	if use == null:
		use = BotSkillRules.choose(ab.skills, bb, h, ready, zone_c, zone_r)
	if use == null or (use.aim == BotSkillRules.Aim.TRACK and not sensor.target_visible):
		return
	_pending_skill = use
	_skill_deadline = tick + roundi(SKILL_TIMEOUT_S * _tick_hz)


## W10-W3 Sable: re-press Sabotage Charge (a recast while it is on cooldown) when
## an enemy hero was sighted within the trigger radius of an armed charge, or an
## armed charge sits by an enemy Ward Generator.
func _decide_detonation(tick: int, h: HeroBody) -> BotSkillRules.SkillUse:
	var ab := h.combat.abilities
	var sk: SkillInstance = null
	for s in ab.skills:
		if s.def.id == &"skill_sable_sabotage_charge":
			sk = s
	if sk == null or not ab.is_unlocked(sk.slot) or not (sk.on_cooldown(tick) or sk.active) \
			or h.combat.status.is_stunned():
		return null
	var charges := PackedVector3Array()
	for c in server.abilities.extras.charges:
		if c.ctx.caster == h and tick >= c.armed_tick:
			charges.append(c.pos)
	if charges.is_empty():
		return null
	var max_age := roundi(tuning.sabotage_sighting_age_s * _tick_hz)
	var enemies := PackedVector3Array()
	for id in sensor.memory:
		var e := server.hero(id)
		if e != null and not e.combat.dead and e.combat.team != h.combat.team \
				and tick - int(sensor.memory[id][1]) <= max_age:
			enemies.append(e.state.position + Vector3(0.0, 0.9, 0.0))
	var gp := PackedVector3Array()
	var gr := PackedFloat32Array()
	for g in server.generators:
		if g.is_up() and g.attackable_by(h.combat.team):
			gp.append(g.global_position)
			gr.append(g.hit_radius)
	if not BotSkillBehaviours.detonation_wanted(charges, enemies, gp, gr, sk.param(&"radius"), tuning):
		return null
	var u := BotSkillRules.SkillUse.new(sk.slot, BotSkillRules.Aim.NONE)
	u.recast = true
	return u


## W10-W3 Hex Relay Hop (escape / reposition) and Juniper Tripwire Lattice.
func _decide_special(tick: int, h: HeroBody, zone_c: Vector3, zone_r: float) -> BotSkillRules.SkillUse:
	var eye := h.state.position + Vector3(0.0, h.eye_height(), 0.0)
	var hurt_now := bb.seconds_since(bb.last_damaged_tick) < 1.0
	for s in h.combat.abilities.skills:
		if not _skill_ready(h, s.slot, tick):
			continue
		match s.def.id:
			&"skill_hex_relay_hop":
				var hero_t := bb.target_id != 0 and bb.target_is_hero
				var anchor := bb.target_pos if hero_t else bb.front_pos
				var dist := bb.target_dist if hero_t else (BotBlackboard.flat_dist(bb.pos, bb.front_pos) \
					if bb.front_index >= 0 and not bb.front_is_own else INF)
				var mode := BotSkillBehaviours.hop_mode(bb.hp_frac, hurt_now, dist, tuning)
				if mode == BotSkillBehaviours.HopMode.NONE:
					continue
				if mode == BotSkillBehaviours.HopMode.ESCAPE:
					anchor = bb.home_pos
				var cands := _hop_gadgets(h)
				var idx := BotSkillBehaviours.pick_hop_gadget(bb.pos, anchor, cands, s.param(&"range"), tuning)
				if idx >= 0 and sensor.has_los(eye, cands[idx] + Vector3(0.0, 0.5, 0.0)):
					hops_used += 1
					return BotSkillRules.SkillUse.new(s.slot, BotSkillRules.Aim.POINT, cands[idx] + Vector3(0.0, 0.5, 0.0))
			&"skill_juniper_tripwire_lattice":
				if sensor.target_visible or zone_r <= 0.0 \
						or BotBlackboard.flat_dist(bb.pos, zone_c) > tuning.wire_zone_range_m:
					continue
				var wire := _wire_sites(zone_c, s.param(&"distance"))
				if wire.size() == 2 and BotSkillBehaviours.wire_in_reach(bb.pos, wire[0], wire[1], s.param(&"range"), tuning):
					var u := BotSkillRules.SkillUse.new(s.slot, BotSkillRules.Aim.POINT, wire[0])
					u.has_then = true
					u.then_point = wire[1]
					return u
	return null


## Allied Wardlings and own / allied deployables Relay Hop can land on.
func _hop_gadgets(h: HeroBody) -> PackedVector3Array:
	var out := PackedVector3Array()
	var team := h.combat.team
	if server.wardlings != null:
		for w in server.wardlings.wardlings:
			if not w.dead and w.team == team:
				out.append(w.global_position)
	for d in server.abilities.deployables:
		if d.alive and d.team == team and d.kind != TrapWorld.KIND_FIELD:
			out.append(d.pos)
	return out


## Cached Tripwire anchors across the enemy's approach (nav path from its HQ) to a zone.
func _wire_sites(zone_c: Vector3, wire_len: float) -> PackedVector3Array:
	var key := Vector2i(roundi(zone_c.x), roundi(zone_c.z))
	if _wire_cache.has(key):
		return _wire_cache[key]
	var md := server.wardlings.map_def if server.wardlings != null else null
	var out := PackedVector3Array()
	if md != null and md.hq(1 - bb.team) != null:
		var path := NavigationServer3D.map_get_path(server.get_world_3d().navigation_map,
			md.hq(1 - bb.team).sanctum, zone_c, true)
		var probe := func(p: Vector3, dir: Vector3) -> float:
			_wire_ray.from = p + Vector3.UP
			_wire_ray.to = p + Vector3.UP + dir * 8.0
			var r := server.get_world_3d().direct_space_state.intersect_ray(_wire_ray)
			return maxf((r.position as Vector3).distance_to(_wire_ray.from) - 0.4, 0.0) if not r.is_empty() else 8.0
		out = BotSkillBehaviours.pick_wire(path, wire_len, probe, tuning)
	_wire_cache[key] = out
	return out


## W10-W3 Liora: pick the allied hero to heal and whether to hold alt-fire.
func _decide_beam(tick: int, h: HeroBody) -> void:
	var prev := _beam_id
	_beam_id = 0
	var p: HeroPassiveDef = null
	for ps in h.combat.def.passives:
		if ps.kind == HeroPassiveDef.Kind.HEAL_BEAM:
			p = ps
	var w := h.combat.weapon
	if p == null or w == null or not (w.feed is ManaPoolFeed) or h.combat.status.is_stunned() \
			or bb.carrying:
		return
	_beam_hold_range = p.range_m - 4.0
	if BotSkillBehaviours.beam_blocked(bb.hp_frac, bb.seconds_since(bb.last_damaged_tick), tuning):
		return
	var feed := w.feed as ManaPoolFeed
	if not BotSkillBehaviours.beam_mana_ok(feed.current() / maxf(feed.capacity(), 1.0), prev != 0, tuning):
		return
	var eye := h.state.position + Vector3(0.0, h.eye_height(), 0.0)
	var allies: Array = []
	var list: Array = server.wardlings.heroes() if server.wardlings != null else []
	for item in list:
		var a := item as HeroBody
		if a == h or a.combat.dead or a.combat.team != h.combat.team:
			continue
		var hp := a.combat.health.hp / maxf(a.combat.def.max_hp, 1.0)
		var chest := a.state.position + Vector3(0.0, SENSOR_CHEST_Y, 0.0)
		var d := eye.distance_to(chest)
		if hp >= tuning.beam_release_hp_frac or d > p.range_m:
			continue
		allies.append(BotSkillBehaviours.AllyView.new(a.net_id, hp, d, sensor.has_los(eye, chest)))
	_beam_id = BotSkillBehaviours.pick_beam_target(allies, p.range_m, prev, tuning)


func _skill_ready(h: HeroBody, s: int, tick: int) -> bool:
	var ab := h.combat.abilities
	var sk := ab.skill(s)
	if sk == null or not ab.is_unlocked(s) or sk.active or sk.on_cooldown(tick) or tick < ab.lockout_until_tick:
		return false
	return not h.combat.status.is_stunned()


func _decide_squad(tick: int, h: HeroBody) -> void:
	var ww := server.wardlings
	if ww == null:
		return
	var sq := ww.squad_of(h.net_id)
	if sq == null or sq.members.is_empty() or bb.seconds_since(_last_order_tick) < profile.squad_order_interval_s:
		return
	var cmd := InputCommand.SQUAD_NONE
	var target := 0
	var kind := goal.kind if goal != null else BotGoal.Kind.PUSH
	if kind == BotGoal.Kind.RETREAT:
		if sq.command != Squad.CMD_FOLLOW:
			cmd = InputCommand.SQUAD_FOLLOW
	elif sensor.target_visible and (bb.target_is_hero or sensor.target is UplinkSim or sensor.target is GeneratorTarget) \
			and bb.target_dist <= ww.rules.command_range_m - 2.0:
		if sq.command != Squad.CMD_ATTACK or sq.attack_target_id != bb.target_id:
			cmd = InputCommand.SQUAD_ATTACK
			target = bb.target_id
	elif sq.command != Squad.CMD_ATTACK:
		var idx := bb.defend_index if kind == BotGoal.Kind.DEFEND else bb.front_index
		if idx >= 0 and (sq.command != Squad.CMD_CAPTURE or sq.capture_index != idx):
			cmd = InputCommand.SQUAD_CAPTURE
			target = idx
	if cmd != InputCommand.SQUAD_NONE:
		_squad_cmd = cmd
		_squad_target = target
		_last_order_tick = tick


# --- Per-tick action ----------------------------------------------------------

func _act(tick: int, h: HeroBody, out: InputCommand) -> void:
	var c := h.combat
	var pos := h.state.position
	var eye := pos + Vector3(0.0, h.eye_height(), 0.0)
	var visible := sensor.target_visible and sensor.target_alive()
	# E14 bot cost: a calm bot (no target in sight, no skill to aim, not on a Cell
	# job or unsticking) steers at half rate: every other tick repeats the last
	# move / look / sprint, and only the one-tick edges (skill point, squad
	# order) are sent. Path following at 15 Hz is ample for a 6 m/s run.
	var beam_ally := _beam_ally()
	var calm := beam_ally == null and not visible and _pending_skill == null and not nav.unsticking(tick) \
		and (goal == null or goal.kind != BotGoal.Kind.CELL)
	if calm and _calm_ready and (tick + slot) % 2 == 1:
		_calm_ready = false
		out.yaw = aim.yaw
		out.pitch = aim.pitch
		out.move = _calm_move
		out.buttons |= _calm_buttons
		_emit_edges(out)
		return
	# --- movement ---
	var dest := goal.destination(bb) if goal != null else pos
	var arrive := goal.arrive_radius(bb) if goal != null else 2.0
	var fighting := visible and sensor.target is HeroBody
	var wish := Vector3.ZERO
	var to_dest := BotBlackboard.flat_dist(pos, dest)
	if goal != null and goal.kind == BotGoal.Kind.FIGHT and fighting:
		var keep := _preferred_range(c)
		var d := bb.target_dist
		var toward := Vector3(sensor.target.global_position.x - pos.x, 0.0, sensor.target.global_position.z - pos.z).normalized()
		if d > keep * 1.2 and not _in_objective_zone(pos):
			nav.set_goal(dest, pos, tick)
			wish = _nav_dir(pos, dest)
		elif d < keep * 0.6:
			wish = -toward
	elif to_dest > arrive:
		nav.set_goal(dest + _wander, pos, tick)
		wish = _nav_dir(pos, dest + _wander)
	elif BotBlackboard.flat_dist(pos, dest + _wander) > 1.5:
		wish = Vector3(dest.x + _wander.x - pos.x, 0.0, dest.z + _wander.z - pos.z).normalized()
	elif rng.randf() < 0.02:
		_new_wander()
	if beam_ally != null:
		var to_ally := beam_ally.state.position - pos
		to_ally.y = 0.0
		if to_ally.length() > _beam_hold_range:
			wish = to_ally.normalized()  # close in until the ally is well inside the beam range
	elif fighting:
		if tick >= _strafe_until:
			_strafe = -_strafe if rng.randf() < 0.7 else _strafe
			_strafe_until = tick + roundi(rng.randf_range(profile.strafe_min_s, profile.strafe_max_s) * _tick_hz)
		var toward2 := Vector3(sensor.target.global_position.x - pos.x, 0.0, sensor.target.global_position.z - pos.z).normalized()
		var side := Vector3(-toward2.z, 0.0, toward2.x) * _strafe
		wish = (wish + side * 0.8).limit_length(1.0)
	# E14 Plant: on the Cell job spot, stand and hold Interact (pickup / plant / defuse).
	if goal != null and goal.kind == BotGoal.Kind.CELL and to_dest <= arrive + 0.5:
		wish = Vector3.ZERO
		if bb.cell_job == BotBlackboard.CellJob.PICKUP or bb.cell_job == BotBlackboard.CellJob.PLANT \
				or bb.cell_job == BotBlackboard.CellJob.DEFUSE:
			out.buttons |= InputCommand.BTN_INTERACT
			interacts += 1
	if tick >= nav.next_check_tick() \
			and nav.check_stuck(pos, tick, wish.length_squared() > 0.25 and not c.abilities.is_dashing(), rng):
		out.buttons |= InputCommand.BTN_JUMP
	if nav.unsticking(tick):
		var side2 := Vector3(-wish.z, 0.0, wish.x) * nav.unstick_side
		wish = (wish * 0.3 + side2).limit_length(1.0)
		if (nav.unstick_until - tick) % 10 == 0:
			out.buttons |= InputCommand.BTN_JUMP
	# --- aim ---
	var skill := _pending_skill
	if skill != null and skill.aim == BotSkillRules.Aim.POINT:
		aim.look_at(skill.point, eye)
	elif beam_ally != null:
		aim.look_at(beam_ally.state.position + Vector3(0.0, SENSOR_CHEST_Y, 0.0), eye)
	elif visible:
		aim.track(sensor.aim_point(aim.aim_head), eye, tick)
	elif wish.length_squared() > 0.01:
		aim.look_at(eye + wish * LOOK_AHEAD_M, eye)
	elif bb.target_id != 0:
		aim.look_at(bb.target_pos + Vector3(0.0, 1.2, 0.0), eye)
	out.yaw = aim.yaw
	out.pitch = aim.pitch
	# World wish -> local move (x = strafe right, y = forward).
	var f := Vector3(-sin(aim.yaw), 0.0, -cos(aim.yaw))
	var r := Vector3(cos(aim.yaw), 0.0, -sin(aim.yaw))
	out.move = Vector2(wish.dot(r), wish.dot(f)).limit_length(1.0)
	# --- weapon ---
	var firing := false
	if beam_ally != null:
		out.buttons |= InputCommand.BTN_ALT  # heal beam: hold alt-fire on the ally
		beam_ticks += 1
	elif visible and c.weapon != null and aim.can_fire(tick) and c.can_shoot():
		var ap := sensor.aim_point(aim.aim_head)
		var in_range := eye.distance_to(ap) <= c.weapon.def.range_m
		if in_range and _resource_ok(c) and aim.on_target(ap, eye, sensor.target_radius()):
			if not c.weapon.def.semi_auto or tick % FIRE_ALT_TICKS == 0:
				out.buttons |= InputCommand.BTN_FIRE
				shots_pressed += 1
			firing = true
	if not visible and c.weapon != null and c.weapon.feed is MagazineFeed:
		var mf := c.weapon.feed as MagazineFeed
		if not mf.is_reloading() and mf.current() < mf.capacity() and mf.reserve_count() > 0:
			out.buttons |= InputCommand.BTN_RELOAD
	if not firing and not visible and out.move.y > 0.7 and to_dest > SPRINT_MIN_M and skill == null:
		out.buttons |= InputCommand.BTN_SPRINT
	_calm_ready = calm
	_calm_move = out.move
	_calm_buttons = out.buttons & (InputCommand.BTN_SPRINT | InputCommand.BTN_RELOAD)
	# --- skill press (edge) ---
	if skill != null:
		if tick >= _skill_deadline:
			_pending_skill = null
		elif tick - _skill_pressed_tick > 1 and _skill_aim_ok(skill, eye):
			out.buttons |= AbilityRunner.SLOT_BUTTONS[skill.slot]
			_skill_pressed_tick = tick
			skills_pressed += 1
			_pending_skill = null
			if skill.has_then:  # Tripwire: press 1 laid anchor A, queue press 2 for B
				wires_placed += 1
				_pending_skill = BotSkillRules.SkillUse.new(skill.slot, BotSkillRules.Aim.POINT, skill.then_point)
				_skill_deadline = tick + roundi(TRIPWIRE_B_WINDOW_S * _tick_hz)
	_emit_edges(out)


## Armory: while on the Armory pad (or in the Sanctum), the guide's best
## affordable step, sent as ACTION_BUY. Re-evaluated only when the wallet or
## the advisor signals change, so a refused request is not repeated.
func _decide_shop(tick: int, h: HeroBody) -> void:
	var prog = server.get("progression")
	if prog == null or prog.catalog == null or _shop_arg >= 0 or _sell_arg >= 0:
		return
	if not prog.is_at_armory(h):
		_shop_key = ""
		return
	var p: HeroProgress = prog.progress_of(h)
	var key := "%d:%d:%d:%d" % [p.lumen, p.spent_lumen, p.medpacks, p.signals]
	if key == _shop_key:
		return
	_shop_key = key
	if builds == null:
		builds = load(RecommendedBuildsDef.V22_PATH if prog.is_v2() else RecommendedBuildsDef.DEFAULT_PATH) \
			as RecommendedBuildsDef
	var guide: RecommendedBuildDef = builds.for_hero(h.combat.def.id) if builds != null else null
	if guide == null:
		return
	var st := BuildState.from_hero(p, prog.catalog, h.combat.def.weapon, prog.rules)
	st.time_s = server.match_seconds()
	for o in _all_heroes():
		if o == h or o.combat.def == null:
			continue
		if o.combat.team == h.combat.team:
			st.add_ally(o.combat.def)
		else:
			st.add_enemy(o.combat.def)
	var ar: AdviceRulesDef = prog.advice_rules if prog.advice_rules != null else AdviceRulesDef.new()
	# Only the top step: a bot saves for it rather than spending on lower ones.
	var a := BuildAdvisor.evaluate(guide, st, ar).best()
	if st.v2 and a != null and not a.affordable and a.cost >= (1 << 30) and st.slots_used >= st.open_slots:
		_sell_for_room(p, prog.catalog, guide, tick)
		return
	if a == null or not a.affordable or a.item_index < 0:
		return
	if st.v2:
		_shop_arg = a.item_index
		_log("t%d h%d buy %s for %s (%s)" % [tick, hero_id, prog.catalog.at(a.item_index).id,
			prog.catalog.at(a.goal_index).id if a.goal_index >= 0 else "-", a.node.id])
		return
	var it: ArmoryItemDef = prog.catalog.at(a.item_index)
	var tier := a.target if it.kind == ArmoryItemDef.Kind.MOUNT else 0
	_shop_arg = a.item_index | (tier << 8)
	_log("t%d h%d buy %s x%d (%s)" % [tick, hero_id, it.id, a.target, a.node.id])


## Armory v2 (§3.10 rule 6): with every open slot full and the next step
## needing one, sell the loose item of lowest value that the plan never uses.
func _sell_for_room(p: HeroProgress, cat: ArmoryCatalogDef, guide: RecommendedBuildDef, tick: int) -> void:
	if guide != _plan_guide:
		_plan_guide = guide
		_plan.clear()
		for n in guide.nodes:
			if n == null:
				continue
			for id in [n.item_id] + Array(n.alternatives):
				_add_plan(cat, cat.index_of(StringName(id)))
	var best_loc := -1
	var best_value := 1 << 30
	for i in p.inv.slots.size():
		var idx: int = p.inv.slots[i].index
		if _plan.has(idx):
			continue
		var v := RecipeMath.total(cat, idx)
		if v < best_value:
			best_value = v
			best_loc = ItemInventory.LOC_SLOT + i
	if best_loc >= 0:
		_sell_arg = best_loc
		_log("t%d h%d sell %s for room" % [tick, hero_id, cat.at(p.inv.index_at(best_loc)).id])


func _add_plan(cat: ArmoryCatalogDef, index: int) -> void:
	var it := cat.at(index)
	if it == null or _plan.has(index):
		return
	_plan[index] = true
	for part in it.recipe:
		_add_plan(cat, cat.index_of(StringName(part)))


func _log(line: String) -> void:
	if log_lines.size() >= LOG_MAX:
		log_lines.remove_at(0)
	log_lines.append(line)


## One-tick edge events: a skill point, an Armory purchase and a squad order.
func _emit_edges(out: InputCommand) -> void:
	# --- skill point (one-tick action) ---
	if _learn_slot >= 0:
		out.action = InputCommand.ACTION_LEARN
		out.action_arg = ProgressionSystem.learn_arg(_learn_slot, _learn_choice)
		_learn_slot = -1
		_learn_choice = 0
		skills_learned += 1
	# --- Armory purchase (one action per command: waits a tick for a skill point) ---
	elif _shop_arg >= 0:
		out.action = InputCommand.ACTION_BUY
		out.action_arg = _shop_arg
		_shop_arg = -1
		items_bought += 1
	elif _sell_arg >= 0:
		out.action = InputCommand.ACTION_SELL
		out.action_arg = _sell_arg
		_sell_arg = -1
		items_sold += 1
	# --- squad order (one-tick edge event) ---
	if _squad_cmd != InputCommand.SQUAD_NONE:
		out.squad_cmd = _squad_cmd
		out.squad_target = _squad_target
		_squad_cmd = InputCommand.SQUAD_NONE
		squad_orders += 1


## Inside the zone of the hardpoint being worked (defend, else the front): a
## fighting bot holds its presence there instead of chasing out of the zone.
func _in_objective_zone(pos: Vector3) -> bool:
	if bb.defend_index >= 0:
		return BotBlackboard.flat_dist(pos, bb.defend_pos) < bb.defend_radius * 0.9
	if bb.front_index >= 0 and not bb.front_is_own:
		return BotBlackboard.flat_dist(pos, bb.front_pos) < bb.front_radius * 0.9
	return false


## The ally being beamed this tick (alive, same team), or null.
func _beam_ally() -> HeroBody:
	if _beam_id == 0:
		return null
	var a := server.hero(_beam_id)
	return a if a != null and not a.combat.dead else null


func _skill_aim_ok(skill: BotSkillRules.SkillUse, eye: Vector3) -> bool:
	match skill.aim:
		BotSkillRules.Aim.POINT:
			return aim.off_angle(skill.point, eye) <= deg_to_rad(SKILL_POINT_TOL_DEG)
		BotSkillRules.Aim.TRACK:
			return sensor.target_visible and sensor.target_alive() \
				and aim.on_target(sensor.aim_point(false), eye, sensor.target_radius() * 1.5)
	return true


func _nav_dir(pos: Vector3, dest: Vector3) -> Vector3:
	var d := nav.direction(pos)
	if d == Vector3.ZERO and nav.path.is_empty():
		d = Vector3(dest.x - pos.x, 0.0, dest.z - pos.z).normalized()
	return d


## Mana: stop near empty (avoid Burnout), resume once refilled. Magazine: rounds.
func _resource_ok(c: HeroCombat) -> bool:
	var feed := c.weapon.feed
	if feed is ManaPoolFeed:
		var frac := feed.current() / maxf(feed.capacity(), 1.0)
		if _mana_pause:
			_mana_pause = frac < profile.mana_resume_frac
		elif frac < profile.mana_stop_frac:
			_mana_pause = true
		return not _mana_pause
	return feed.can_fire()


func _ammo_frac(c: HeroCombat) -> float:
	if c.weapon == null:
		return 0.0
	var f := c.weapon.feed
	var cap := float(f.capacity() + (c.weapon.def.reserve if f is MagazineFeed else 0))
	return (f.current() + (f.reserve_count() if f is MagazineFeed else 0)) / maxf(cap, 1.0)


## Engagement distance by weapon: inside the full-damage falloff band.
func _preferred_range(c: HeroCombat) -> float:
	if c.weapon == null:
		return 10.0
	return clampf(c.weapon.def.falloff_start_m * 0.8, 5.0, 25.0)


func _new_wander() -> void:
	var r := 0.0
	if goal != null:
		r = goal.arrive_radius(bb) * 0.8
	var a := rng.randf() * TAU
	_wander = Vector3(cos(a), 0.0, sin(a)) * rng.randf() * r \
		if goal == null or (goal.kind != BotGoal.Kind.SIEGE and goal.kind != BotGoal.Kind.CELL) else Vector3.ZERO


func _log_transition(tick: int, from: BotGoal, to: BotGoal) -> void:
	if log_lines.size() >= LOG_MAX:
		log_lines.remove_at(0)
	log_lines.append("t%d h%d %s->%s" % [tick, hero_id, BotGoal.NAMES[from.kind] if from != null else "-",
		BotGoal.NAMES[to.kind]])
