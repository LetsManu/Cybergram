class_name BotDirector
extends RefCounted
## Fills empty hero slots with bots and owns their brains (architecture.md §9,
## ADR-0005 §1-3; Canon C1). Each bot is a ServerWorld scripted hero fed by a
## BotInputSource, so its commands go through exactly the hero pipeline a
## human's do. Decisions are staggered across slots (BotBrain.slot).
## Wired from src/ai (BotAiInstaller); gameplay never names this class.
##
## Example:
##   var d := BotDirector.new()
##   d.setup(server, roster, roster.profile("normal"), 7)
##   d.fill(true)   # 9 bots around one human on team 0, slot 0

var server: ServerWorld
var roster: BotRosterDef
var profile: BotProfile
var seed_value: int = 0
var brains: Array[BotBrain] = []
var meter := BotCostMeter.new()
var sources: Array[BotInputSource] = []
var _by_hero: Dictionary = {}  # hero net id -> BotBrain
var _claims: Dictionary = {}  # E14 Cell job claims, shared by every brain


func setup(s: ServerWorld, r: BotRosterDef, p: BotProfile, seed_: int) -> void:
	server = s
	roster = r
	profile = p
	seed_value = seed_
	if not server.hero_damaged.is_connected(_on_hero_damaged):
		server.hero_damaged.connect(_on_hero_damaged)


## Adds a bot for every empty slot of both teams. `human_on_team0` keeps
## team 0 slot 0 for the local player. Returns the number of bots added.
func fill(human_on_team0: bool) -> int:
	var humans: Array[int] = [1 if human_on_team0 else 0, 0]
	return fill_around(humans)


## Adds bots for every slot not kept for humans: the first humans[team] slots
## of each team stay empty (online lobby reservations).
func fill_around(humans: Array[int]) -> int:
	var md := server.wardlings.map_def if server.wardlings != null else null
	var n := 0
	for team in 2:
		for s in team_size():
			if s < humans[team]:
				continue
			var hq := md.hq(team) if md != null else null
			var spawn := server.team_spawn(team, Vector3.ZERO)
			var yaw := 0.0
			if hq != null:
				if s < hq.spawn_points.size():
					spawn = hq.spawn_points[s]
				yaw = deg_to_rad(hq.spawn_yaw_deg)
			add_bot(team, roster.hero_for(s), spawn, yaw)
			n += 1
	return n


## Heroes per team: the match rules' format (MatchRulesDef.team_size, Canon C1
## 5v5, slice 3v3), else the roster's fallback.
func team_size() -> int:
	if server != null and server.rules != null:
		return server.rules.team_size
	return roster.team_size if roster != null else 5


## Adds one bot hero. Returns its brain.
func add_bot(team: int, hero_def: HeroDef, spawn: Vector3, yaw: float = 0.0) -> BotBrain:
	var idx := brains.size()
	var b := BotBrain.new(server, profile, hash([seed_value, idx]), idx)
	b.build_order = roster.build_order_for(hero_def)
	b.fork_prefs = roster.fork_prefs_for(hero_def)
	b.team_brains = brains  # E14: shared, for Cell job claims
	b.claims = _claims
	var src := BotInputSource.new(b, meter)
	sources.append(src)
	b.hero_id = server.add_scripted_hero(src, spawn, hero_def, team)
	var h := server.hero(b.hero_id)
	if h != null:
		h.look_yaw = fposmod(yaw, TAU)
	b.aim.yaw = fposmod(yaw, TAU)
	brains.append(b)
	_by_hero[b.hero_id] = b
	return b


## Registers a brain that drives a hero added elsewhere (debug --bot-player).
func adopt(b: BotBrain) -> void:
	b.team_brains = brains
	b.claims = _claims
	brains.append(b)
	_by_hero[b.hero_id] = b


## Online: a human took over this bot's hero; stop thinking for it.
func release_hero(hero_id: int) -> void:
	var b: BotBrain = _by_hero.get(hero_id)
	if b == null:
		return
	_by_hero.erase(hero_id)
	brains.erase(b)


## Online: a human left; a new bot brain drives their hero from now on.
func take_over(hero_id: int) -> BotBrain:
	var h := server.hero(hero_id)
	if h == null or _by_hero.has(hero_id):
		return null
	var b := BotBrain.new(server, profile, hash([seed_value, brains.size(), hero_id]), brains.size())
	b.build_order = roster.build_order_for(h.combat.def)
	b.fork_prefs = roster.fork_prefs_for(h.combat.def)
	b.team_brains = brains
	b.claims = _claims
	var src := BotInputSource.new(b, meter)
	sources.append(src)
	b.hero_id = hero_id
	b.aim.yaw = h.look_yaw
	brains.append(b)
	_by_hero[hero_id] = b
	server.attach_source(hero_id, src)
	return b


func brain_of(hero_id: int) -> BotBrain:
	return _by_hero.get(hero_id)


func _on_hero_damaged(victim: int, attacker: int, _amount: float) -> void:
	var b: BotBrain = _by_hero.get(victim)
	if b != null:
		b.on_damaged(attacker, server.tick)
