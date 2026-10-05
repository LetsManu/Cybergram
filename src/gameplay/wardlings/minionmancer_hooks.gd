class_name MinionmancerHooks
extends RefCounted
## Server-side Wardling hooks for skills (design/gdd/wardlings-and-economy.md
## §13; heroes.md §4.1 Vesper Loom). Gameplay rules only; brains in src/ai react
## to the blackboard fields these write (Squad attack order, VanguardWave
## forced threat) and to WardlingWorld.wardling_allegiance_changed.
##   squad_capacity_bonus    -> capacity_bonus()
##   apply_squad_modifier    -> apply_squad_modifier() / mod_mult()
##   rewrite_to_elite        -> rewrite_to_elite()
##   subvert                 -> subvert() / revert()
##   command_vanguard        -> command_vanguard_attack()
##   issue_command (skills)  -> skill_attack() / order_at()


## Vesper Conductor: extra personal squad slots of `h` (StatCatalog stat).
static func capacity_bonus(h: HeroBody) -> int:
	if h == null or h.combat == null:
		return 0
	return roundi(h.combat.stats.get_value(StatCatalog.SQUAD_CAPACITY_BONUS))


## On mint: the owner's WARDLING_HP_MULT (Vesper +15%) scales max HP.
static func on_minted(ww: WardlingWorld, w: WardlingSim) -> void:
	if w.owner_net_id == 0:
		return
	var owner := ww.server.hero(w.owner_net_id)
	if owner == null or owner.combat == null:
		return
	var m := owner.combat.stats.get_value(StatCatalog.WARDLING_HP_MULT)
	if not is_equal_approx(m, 1.0):
		w.health.max_hp *= m
		w.health.hp = w.health.max_hp


## Buckets `damage`, `damage_taken`, `move_speed`, `hp`, `heal_out`. The same
## source refreshes; different sources multiply.
static func apply_squad_modifier(w: WardlingSim, bucket: StringName, mult: float, until_tick: int, source: int) -> void:
	w.squad_mods[source] = [bucket, mult, until_tick]


static func mod_mult(w: WardlingSim, bucket: StringName, tick: int) -> float:
	var m := 1.0
	for src in w.squad_mods.keys():
		var e: Array = w.squad_mods[src]
		if tick >= int(e[2]):
			w.squad_mods.erase(src)
		elif e[0] == bucket:
			m *= float(e[1])
	return m


static func stun(w: WardlingSim, until_tick: int) -> void:
	w.stun_until_tick = maxi(w.stun_until_tick, until_tick)


static func is_stunned(w: WardlingSim, tick: int) -> bool:
	return tick < w.stun_until_tick


## Outgoing bolt damage multiplier: Elite tier, damage modifiers and the
## strongest allied hero aura in range (Vesper Conductor +10% in 15 m).
static func damage_mult(ww: WardlingWorld, w: WardlingSim, tick: int) -> float:
	var m := mod_mult(w, &"damage", tick)
	if w.elite_until_tick > tick:
		m *= ww.rules.elite_damage_mult
	var aura := 0.0
	for h in ww.heroes():
		if h.combat.dead or h.combat.team != w.team:
			continue
		var a := h.combat.stats.get_value(StatCatalog.WARDLING_AURA_DAMAGE)
		var r := h.combat.def.wardling_aura_radius_m
		if a > aura and WardlingWorld._flat(h.state.position, w.global_position) <= r:
			aura = a
	if w.owner_net_id != 0:  # E13 Amplifier Emitters (owner's squad)
		var owner := ww.server.hero(w.owner_net_id)
		if owner != null and owner.combat != null:
			m *= owner.combat.stats.get_value(StatCatalog.WARDLING_DAMAGE_MULT)
	return m * (1.0 + aura)


static func damage_taken_mult(w: WardlingSim, tick: int) -> float:
	return mod_mult(w, &"damage_taken", tick)


## Allied Vanguard waves with a member within `h`'s conduct radius (Conductor).
static func conducted_waves(ww: WardlingWorld, h: HeroBody) -> Array[VanguardWave]:
	var out: Array[VanguardWave] = []
	var r := h.combat.def.conduct_radius_m
	if r <= 0.0:
		return out
	for wave in ww.waves:
		if wave.team != h.combat.team:
			continue
		for m in wave.members:
			if not m.dead and WardlingWorld._flat(m.global_position, h.state.position) <= r:
				out.append(wave)
				break
	return out


## issue_command from a skill: the owner's squad attacks `target_id` for
## `ticks` (no command-range / LOS validation: the skill already hit it).
static func skill_attack(ww: WardlingWorld, owner: HeroBody, target_id: int, ticks: int) -> bool:
	var sq := ww.squad_of(owner.net_id)
	if sq == null:
		return false
	sq.issue(Squad.CMD_ATTACK, ww.server.tick, Vector3.ZERO, target_id)
	sq.attack_expire_tick = ww.server.tick + ticks
	ww.squad_command_issued.emit(owner.net_id, Squad.CMD_ATTACK)
	return true


## command_vanguard (Attack Target only in M1): the wave focuses `target_id`.
static func command_vanguard_attack(ww: WardlingWorld, wave: VanguardWave, target_id: int, ticks: int) -> void:
	wave.forced_threat_id = target_id
	wave.forced_until_tick = ww.server.tick + ticks
	wave.threat_id = target_id


## Rally Beacon double-tap: Hold Here at `point`, or Go Capture hardpoint
## `hp_index` (map-wide index, any lane) when the beacon stands in its zone.
static func order_at(ww: WardlingWorld, owner: HeroBody, point: Vector3, hp_index: int) -> bool:
	var sq := ww.squad_of(owner.net_id)
	if sq == null:
		return false
	if hp_index >= 0 and ww.map_def != null:
		var hp: HardpointDef = ww.map_def.hardpoint_global(hp_index)
		if hp == null:
			return false
		sq.issue(Squad.CMD_CAPTURE, ww.server.tick, hp.position, 0, hp_index)
		sq.capture_radius = hp.zone_radius
		ww.squad_command_issued.emit(owner.net_id, Squad.CMD_CAPTURE)
	else:
		sq.issue(Squad.CMD_HOLD, ww.server.tick, ww.snap(point))
		ww.squad_command_issued.emit(owner.net_id, Squad.CMD_HOLD)
	return true


## Elite (tier +1) for `ticks`: HP fraction kept, max HP × elite_hp_mult;
## bolts × elite_damage_mult (damage_mult). Refreshes when already Elite.
static func rewrite_to_elite(ww: WardlingWorld, w: WardlingSim, ticks: int) -> void:
	var t := ww.server.tick
	if w.elite_until_tick <= t:
		var f := w.health.hp / w.health.max_hp
		w.health.max_hp *= ww.rules.elite_hp_mult
		w.health.hp = w.health.max_hp * f
	w.elite_until_tick = maxi(w.elite_until_tick, t + ticks)


## Temporary team and owner swap for `ticks` (wardlings §13 subvert): the unit
## joins `new_owner`'s squad as an overflow unit. Returns false if not possible.
static func subvert(ww: WardlingWorld, w: WardlingSim, new_owner: HeroBody, ticks: int) -> bool:
	if w.dead or w.turned_until_tick >= 0:
		return false
	var sq := ww.squad_of(new_owner.net_id)
	if sq == null:
		return false
	w.turned_from_team = w.team
	w.turned_from_owner = w.owner_net_id
	w.turned_from_squad = w.squad
	w.turned_from_wave = w.wave
	if w.squad != null:
		w.squad.members.erase(w)
	if w.wave != null:
		w.wave.members.erase(w)
	_set_team(w, new_owner.combat.team)
	w.owner_net_id = new_owner.net_id
	w.squad = sq
	w.wave = null
	w.overflow = true
	sq.members.append(w)
	w.turned_until_tick = ww.server.tick + ticks
	w.clear_attack()
	w.stop()
	ww.wardling_allegiance_changed.emit(w)
	return true


## Ends a subvert: back to its wave or squad; dissolves if neither remains.
static func revert(ww: WardlingWorld, w: WardlingSim) -> void:
	if w.turned_until_tick < 0:
		return
	w.turned_until_tick = -1
	if w.squad != null:
		w.squad.members.erase(w)
	w.overflow = false
	_set_team(w, w.turned_from_team)
	w.owner_net_id = w.turned_from_owner
	w.squad = null
	w.wave = null
	var home_wave := w.turned_from_wave
	var home_squad := w.turned_from_squad
	w.turned_from_wave = null
	w.turned_from_squad = null
	w.clear_attack()
	w.stop()
	if home_wave != null:
		w.wave = home_wave
		home_wave.members.append(w)
		if not ww.waves.has(home_wave):
			ww.waves.append(home_wave)
	elif home_squad != null and (ww.squads.values().has(home_squad) or ww.orphan_squads.has(home_squad)):
		w.squad = home_squad
		home_squad.members.append(w)
	else:
		w.dead = true  # its owner and squad are gone: dissolves (no bounty)
		w.killer_id = 0
		return
	ww.wardling_allegiance_changed.emit(w)


## Rewrite (Vesper ult) on every Wardling within `radius` of `center`.
static func rewrite_area(ww: WardlingWorld, caster: HeroBody, center: Vector3, radius: float, elite_ticks: int,
		turned_ticks: int) -> void:
	var team := caster.combat.team
	for w: WardlingSim in ww.wardlings.duplicate():
		if w.dead or WardlingWorld._flat(w.global_position, center) > radius:
			continue
		if w.team == team:
			if w.turned_until_tick < 0:
				rewrite_to_elite(ww, w, elite_ticks)
		else:
			subvert(ww, w, caster, turned_ticks)


## Per tick (WardlingWorld.step): Elite and Turned expiry. A Turned unit whose
## new owner died returns at once (heroes.md §7 edge case 1).
static func step(ww: WardlingWorld, tick: int) -> void:
	for w: WardlingSim in ww.wardlings.duplicate():
		if w.dead:
			continue
		if w.elite_until_tick >= 0 and tick >= w.elite_until_tick:
			w.elite_until_tick = -1
			var f := w.health.hp / w.health.max_hp
			w.health.max_hp /= ww.rules.elite_hp_mult
			w.health.hp = w.health.max_hp * f
		if w.turned_until_tick >= 0 and (tick >= w.turned_until_tick or (w.squad != null and w.squad.is_dissolving())):
			revert(ww, w)
	for wave in ww.waves:
		if wave.forced_until_tick >= 0 and tick >= wave.forced_until_tick:
			wave.forced_until_tick = -1
			wave.forced_threat_id = 0


## Snapshot state bits 6 (Elite) and 7 (Turned).
static func state_bits(w: WardlingSim, tick: int) -> int:
	var b := 0
	if w.elite_until_tick > tick:
		b |= 1 << 6
	if w.turned_until_tick >= 0:
		b |= 1 << 7
	return b


static func _set_team(w: WardlingSim, team: int) -> void:
	w.team = team
	w.health.team = team
	w.collision_layer = WardlingSim.layer_for_team(team)
