class_name WardlingDirector
extends RefCounted
## Schedules all Wardling thinking (architecture.md §10.2, ADR-0005 §8):
## squad brains at 5 Hz and wave brains at 2 Hz first (shared decisions), then
## per-Wardling brains at 10 Hz staggered by net id under a deterministic
## count cap (overflow waits a tick) and a per-tick LOS ray budget.
## Wired from a higher layer: ServerWorld never names src/ai; attach() injects
## think() into WardlingWorld.think_hook.
##
## Example:
##   var director := WardlingDirector.new()
##   director.attach(server)   # after server.enable_wardlings(...)

signal brain_state_changed(net_id: int, from: int, to: int)

var world: WardlingWorld
var rules: WardlingRulesDef
var brains: Dictionary = {}  # net id -> WardlingBrain
var wave_brains: Dictionary = {}  # wave id -> WaveBrain
var decisions_last_tick: int = 0
var rays_last_tick: int = 0
## Per-transition log (bounded; architecture.md §10.1 "transitions are logged").
var log_lines: PackedStringArray = PackedStringArray()
var log_enabled: bool = false
var _rays_left: int = 0


## Hooks this director into `server.wardlings`. Returns false without Wardlings.
func attach(server: ServerWorld) -> bool:
	if server == null or server.wardlings == null:
		return false
	world = server.wardlings
	rules = world.rules
	world.think_hook = think
	world.wardling_minted.connect(_on_minted)
	world.wardling_removed.connect(_on_removed)
	# E10: subvert / revert changes squad or wave; the brain restarts from scratch.
	world.wardling_allegiance_changed.connect(_on_minted)
	for w in world.wardlings:
		_on_minted(w)
	return true


func brain(net_id: int) -> WardlingBrain:
	return brains.get(net_id)


func think(tick: int) -> void:
	_rays_left = rules.max_los_rays_per_tick
	var sq_every := rules.squad_think_interval_ticks
	for sq in world.squads.values():
		if (tick + sq.id) % sq_every == 0 or sq.slots.size() != sq.members.size():
			SquadBrain.think(sq, world, rules)
	for sq in world.orphan_squads:
		if (tick + sq.id) % sq_every == 0:
			SquadBrain.think(sq, world, rules)
	for wave in world.waves:
		var wb: WaveBrain = wave_brains.get(wave.id)
		if wb == null:
			wb = WaveBrain.new(wave, world, rules)
			wave_brains[wave.id] = wb
			wb.think(tick)
		elif (tick + wave.id) % rules.wave_think_interval_ticks == 0:
			wb.think(tick)
	var every := rules.decision_interval_ticks
	var n := 0
	for w in world.wardlings:
		var b: WardlingBrain = brains.get(w.net_id)
		if b == null or w.dead:
			continue
		if b.overdue or (tick + w.net_id) % every == 0:
			if n < rules.max_decisions_per_tick:
				b.think(tick)
				n += 1
			else:
				b.overdue = true
	decisions_last_tick = n
	rays_last_tick = rules.max_los_rays_per_tick - _rays_left
	if tick % 60 == 0:
		_prune_waves()


## Budgeted LOS: 1 clear, 0 blocked, -1 when this tick's ray budget is spent.
func los(from: Vector3, to: Vector3) -> int:
	if _rays_left <= 0:
		return -1
	_rays_left -= 1
	return 1 if world.has_los(from, to) else 0


func _on_minted(w: WardlingSim) -> void:
	var b := WardlingBrain.new(w, world, rules)
	b.los_probe = los
	b.on_transition = _on_transition
	brains[w.net_id] = b


func _on_removed(w: WardlingSim, _killer: int) -> void:
	brains.erase(w.net_id)


func _on_transition(net_id: int, from: int, to: int) -> void:
	if log_enabled:
		if log_lines.size() >= 512:
			log_lines.remove_at(0)
		log_lines.append("t%d w%d %s->%s" % [world.server.tick, net_id,
			WardlingBrain.State.keys()[from], WardlingBrain.State.keys()[to]])
	brain_state_changed.emit(net_id, from, to)


func _prune_waves() -> void:
	var live := {}
	for wave in world.waves:
		live[wave.id] = true
	for id in wave_brains.keys():
		if not live.has(id):
			wave_brains.erase(id)
