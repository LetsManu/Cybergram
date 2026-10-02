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
var goal_ticks: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
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
var skills_learned: int = 0
var _learn_slot: int = -1


func _init(s: ServerWorld, p: BotProfile, seed_: int, slot_: int) -> void:
	server = s
	profile = p
	slot = slot_
	rng.seed = seed_
	_tick_hz = s.net.tick_rate_hz
	bb.tick_hz = _tick_hz
	decide_every = maxi(1, roundi(_tick_hz / maxf(p.decision_hz, 0.1)))
	sensor = BotSensor.new(s, p)
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
	bb.defend_index = BotBlackboard.NO_HARDPOINT
	var objs := server.objectives
	if objs != null and not objs.lanes.is_empty():
		var lane: Array = objs.lanes[0]
		var fi := objs.front.front_for(c.team, 0)
		if fi >= 0:
			var fh: HardpointSim = lane[fi]
			bb.front_index = fi
			bb.front_pos = fh.def.position
			bb.front_radius = fh.def.zone_radius
			bb.front_is_own = fh.owner == c.team
		var best_d := INF
		for hp in lane:
			var hs := hp as HardpointSim
			if hs.owner == c.team and hs.progress > 0.0 and hs.capturing_team == 1 - c.team:
				var d := BotBlackboard.flat_dist(bb.pos, hs.def.position)
				if d < best_d:
					best_d = d
					bb.defend_index = hs.index
					bb.defend_pos = hs.def.position
					bb.defend_radius = hs.def.zone_radius
					bb.defend_progress = hs.progress
	bb.enemy_uplink_exposed = false
	var mf := server.match_flow
	if mf != null and mf.is_live():
		var u := mf.uplink_of(1 - c.team)
		if u != null and u.exposed and not u.is_destroyed():
			bb.enemy_uplink_exposed = true
			bb.enemy_uplink_id = u.net_id
			bb.enemy_uplink_pos = u.aim_point()
			bb.siege_pos = _siege_point(u, c.team)


## Where to shoot the Exposed Uplink from: inside the held enemy Inner's zone,
## on its edge toward the Uplink (presence keeps it Exposed); else 30 m short.
func _siege_point(u: UplinkSim, team: int) -> Vector3:
	var objs := server.objectives
	var mf := server.match_flow
	if objs != null:
		for hs in objs.all:
			if hs.owner == team and mf.half_of(hs) == u.team and hs.def.tier == HardpointDef.Tier.INNER:
				var to := Vector3(u.base.x - hs.def.position.x, 0.0, u.base.z - hs.def.position.z)
				return hs.def.position + to.normalized() * hs.def.zone_radius * 0.6
	var back := bb.home_pos - u.base
	back.y = 0.0
	return u.base + back.normalized() * 30.0


## E15 skill points: the first slot of the build order the server would accept
## (dry run), sent as an ACTION_LEARN command like a player's Alt + skill key.
func _decide_learn(h: HeroBody) -> void:
	var prog = server.get("progression")
	if prog == null or _learn_slot >= 0 or prog.progress_of(h).skill_points() < 1:
		return
	for s in build_order:
		if prog.can_learn(h, s) == HeroProgress.Result.OK:
			_learn_slot = s
			return


func _decide_skill(tick: int, h: HeroBody) -> void:
	if _pending_skill != null and tick < _skill_deadline:
		return
	_pending_skill = null
	var ab := h.combat.abilities
	if ab.is_casting() or ab.is_dashing() or rng.randf() >= profile.skill_use_chance:
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
	var use := BotSkillRules.choose(ab.skills, bb, h, ready, zone_c, zone_r)
	if use == null or (use.aim == BotSkillRules.Aim.TRACK and not sensor.target_visible):
		return
	_pending_skill = use
	_skill_deadline = tick + roundi(SKILL_TIMEOUT_S * _tick_hz)


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
	elif sensor.target_visible and (bb.target_is_hero or sensor.target is UplinkSim) \
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
	if fighting:
		if tick >= _strafe_until:
			_strafe = -_strafe if rng.randf() < 0.7 else _strafe
			_strafe_until = tick + roundi(rng.randf_range(profile.strafe_min_s, profile.strafe_max_s) * _tick_hz)
		var toward2 := Vector3(sensor.target.global_position.x - pos.x, 0.0, sensor.target.global_position.z - pos.z).normalized()
		var side := Vector3(-toward2.z, 0.0, toward2.x) * _strafe
		wish = (wish + side * 0.8).limit_length(1.0)
	if nav.check_stuck(pos, tick, wish.length_squared() > 0.25 and not c.abilities.is_dashing(), rng):
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
	if visible and c.weapon != null and aim.can_fire(tick) and c.can_shoot():
		var in_range := eye.distance_to(sensor.aim_point(false)) <= c.weapon.def.range_m
		if in_range and _resource_ok(c) and aim.on_target(sensor.aim_point(aim.aim_head), eye, sensor.target_radius()):
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
	# --- skill press (edge) ---
	if skill != null:
		if tick >= _skill_deadline:
			_pending_skill = null
		elif tick - _skill_pressed_tick > 1 and _skill_aim_ok(skill, eye):
			out.buttons |= AbilityRunner.SLOT_BUTTONS[skill.slot]
			_skill_pressed_tick = tick
			skills_pressed += 1
			_pending_skill = null
	# --- skill point (one-tick action) ---
	if _learn_slot >= 0:
		out.action = InputCommand.ACTION_LEARN
		out.action_arg = _learn_slot
		_learn_slot = -1
		skills_learned += 1
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
	_wander = Vector3(cos(a), 0.0, sin(a)) * rng.randf() * r if goal == null or goal.kind != BotGoal.Kind.SIEGE \
		else Vector3.ZERO


func _log_transition(tick: int, from: BotGoal, to: BotGoal) -> void:
	if log_lines.size() >= LOG_MAX:
		log_lines.remove_at(0)
	log_lines.append("t%d h%d %s->%s" % [tick, hero_id, BotGoal.NAMES[from.kind] if from != null else "-",
		BotGoal.NAMES[to.kind]])
