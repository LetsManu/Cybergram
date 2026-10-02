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
	var md := server.wardlings.map_def if server.wardlings != null else null
	var n := 0
	for team in 2:
		for s in roster.team_size:
			if team == 0 and s == 0 and human_on_team0:
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


## Adds one bot hero. Returns its brain.
func add_bot(team: int, hero_def: HeroDef, spawn: Vector3, yaw: float = 0.0) -> BotBrain:
	var idx := brains.size()
	var b := BotBrain.new(server, profile, hash([seed_value, idx]), idx)
	b.build_order = roster.build_order_for(hero_def)
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


func brain_of(hero_id: int) -> BotBrain:
	return _by_hero.get(hero_id)


func _on_hero_damaged(victim: int, attacker: int, _amount: float) -> void:
	var b: BotBrain = _by_hero.get(victim)
	if b != null:
		b.on_damaged(attacker, server.tick)
