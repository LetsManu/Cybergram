class_name AmmoEffects
extends RefCounted
## Ammo Type and Ammo Mod effects (design/gdd/weapons-and-mods.md §3.7.1,
## §3.7.2, §4.5, §5; items-and-armory.md §4.3). Pure rules over
## AmmoTargetState: callers (ServerWorld) pass one Hit per damaged target and
## apply the returned Outcome (heals, mana, arcs, Disrupted, marks). No world
## access here, so every number is unit-testable.
##
## Rules kept here:
## - Effects scale with final damage dealt (after armor, before shields).
## - Uplink immune to all effects; structures take none (only the Piercing /
##   Sunder damage modifiers in DamageMath); heroes and constructs take all.
## - Separate Burn pools and Charge meters per shooter; one shared Chill meter.
## - A Mod does nothing on Standard ammo or on a type it does not fit.
##
## Example:
##   var hit := AmmoEffects.Hit.new()
##   hit.ammo = DamageMath.AMMO_SHOCK; hit.damage = 18.0; ...
##   var out := effects.apply_hit(target.combat.status.ammo, hit)


## One damaging hit on a target.
class Hit:
	var shooter_id: int = 0
	var team: int = -1
	var ammo: int = DamageMath.AMMO_STANDARD
	var mod: int = DamageMath.MOD_NONE
	## DamageMath.TARGET_*.
	var target_class: int = DamageMath.TARGET_HERO
	## Final damage of the hit (after armor).
	var damage: float = 0.0
	var tick: int = 0
	## The shooter's gun is a Mana gun (Siphon restores mana).
	var mana_gun: bool = false


## What the caller must do after a hit (or a Volatile kill burst).
class Outcome:
	## HP to heal the shooter (Siphon) and mana to restore.
	var heal: float = 0.0
	var mana: float = 0.0
	## Overload fired: arc `arc_damage` to up to `arc_targets` other enemies within `arc_radius`.
	var overload: bool = false
	var arc_damage: float = 0.0
	var arc_targets: int = 0
	var arc_radius: float = 0.0
	## Disrupted on the target's weapon (ticks) and the Mech reload penalty (s).
	var disrupt_s: float = 0.0
	var reload_penalty_s: float = 0.0
	## Tracer: mark the target for the shooter's team for this many seconds.
	var mark_s: float = 0.0
	## Volatile burst (on kill): radius, Burn added per enemy, Chill added per
	## enemy, damage to each construct, heal to the shooter and allies in heal_radius.
	var burst_radius: float = 0.0
	var burst_burn: float = 0.0
	var burst_chill: float = 0.0
	var burst_construct_damage: float = 0.0
	var burst_heal: float = 0.0
	var burst_heal_radius: float = 0.0


var rules: AmmoRulesDef
var tick_hz: int
## Wardling states (WardlingSim -> AmmoTargetState); heroes use StatusComponent.ammo.
var others: Dictionary = {}


func _init(rules_: AmmoRulesDef = null, tick_hz_: int = 60) -> void:
	rules = rules_ if rules_ != null else DamageMath.rules()
	tick_hz = maxi(tick_hz_, 1)


## State for a non-hero target `key` (created on first use).
func state_for(key: Object) -> AmmoTargetState:
	var s: AmmoTargetState = others.get(key)
	if s == null:
		s = AmmoTargetState.new()
		others[key] = s
	return s


## Status effects reach this target class (§3.7.1 global rules).
static func takes_effects(target_class: int) -> bool:
	return target_class == DamageMath.TARGET_HERO or target_class == DamageMath.TARGET_CONSTRUCT


## True if `mod` changes `ammo` (§3.7.2 compatibility; Standard takes no mod).
func mod_fits(mod: int, ammo: int) -> bool:
	if ammo == DamageMath.AMMO_STANDARD or mod == DamageMath.MOD_NONE:
		return false
	match mod:
		DamageMath.MOD_LINGERING:
			return rules.lingering_types.has(ammo)
		DamageMath.MOD_VOLATILE:
			return rules.volatile_types.has(ammo)
	return true


## Potency Pot of `mod` on `ammo` (1.0 when the mod does not fit).
func potency(ammo: int, mod: int) -> float:
	if not mod_fits(mod, ammo):
		return 1.0
	if mod == DamageMath.MOD_SATURATED:
		return rules.saturated_potency
	if mod == DamageMath.MOD_OVERCHARGED:
		return rules.overcharged_potency
	return 1.0


## Duration multiplier (Lingering 1.5) of `mod` on `ammo`.
func duration(ammo: int, mod: int) -> float:
	return rules.lingering_duration_mult if mod == DamageMath.MOD_LINGERING and mod_fits(mod, ammo) else 1.0


## Overcharged costs on the shooter's feed: [mana cost mult, reload time mult].
func feed_costs(ammo: int, mod: int) -> Array[float]:
	if mod == DamageMath.MOD_OVERCHARGED and mod_fits(mod, ammo):
		return [rules.overcharged_mana_cost_mult, rules.overcharged_reload_mult]
	return [1.0, 1.0]


## b_burn of §4.3: share of this hit added to the Burn pool (0 when no Burn).
func burn_share(ammo: int, mod: int, target_class: int) -> float:
	if ammo != DamageMath.AMMO_INCENDIARY or not takes_effects(target_class):
		return 0.0
	return rules.burn_share * potency(ammo, mod)


## B_brittle of §4.3 on `state` at `tick` (1.0 or brittle_mult).
func brittle(state: AmmoTargetState, tick: int) -> float:
	return rules.brittle_mult if state != null and state.is_brittle(tick) else 1.0


func _ticks(seconds: float) -> int:
	return maxi(1, roundi(seconds * tick_hz))


## Applies one hit's ammo effects to `state` and returns what the caller does.
func apply_hit(state: AmmoTargetState, hit: Hit) -> Outcome:
	var out := Outcome.new()
	if state == null or hit.damage <= 0.0 or not takes_effects(hit.target_class):
		return out
	var pot := potency(hit.ammo, hit.mod)
	var dur := duration(hit.ammo, hit.mod)
	var applied := false
	match hit.ammo:
		DamageMath.AMMO_PIERCING:
			applied = true  # the effect is the penetration (DamageMath)
		DamageMath.AMMO_SUNDER:
			applied = hit.target_class == DamageMath.TARGET_HERO  # Tracer marks only heroes
		DamageMath.AMMO_INCENDIARY:
			var b: AmmoTargetState.BurnPool = state.burns.get(hit.shooter_id)
			if b == null:
				b = AmmoTargetState.BurnPool.new()
				b.shooter_id = hit.shooter_id
				b.team = hit.team
				state.burns[hit.shooter_id] = b
			b.pool += rules.burn_share * hit.damage * pot
			b.ticks_left = _ticks(rules.burn_duration_s * dur)  # refreshed on hit
			applied = true
		DamageMath.AMMO_SHOCK:
			_shock(state, hit, pot, dur, out)
			applied = true
		DamageMath.AMMO_SIPHON:
			var s := rules.siphon_hero if hit.target_class == DamageMath.TARGET_HERO else rules.siphon_wardling
			out.heal = s * hit.damage * pot
			if hit.mana_gun:
				out.mana = rules.siphon_mana * hit.damage * pot
			applied = true
		DamageMath.AMMO_CRYO:
			add_chill(state, rules.cryo_k * hit.damage * pot, hit.tick, dur)
			applied = true
	if applied and hit.mod == DamageMath.MOD_TRACER and mod_fits(hit.mod, hit.ammo):
		out.mark_s = rules.tracer_mark_s
	return out


func _shock(state: AmmoTargetState, hit: Hit, pot: float, dur: float, out: Outcome) -> void:
	var c: AmmoTargetState.Charge = state.charges.get(hit.shooter_id)
	if c == null:
		c = AmmoTargetState.Charge.new()
		state.charges[hit.shooter_id] = c
	c.value += rules.shock_k * hit.damage * pot
	c.last_hit_tick = hit.tick
	if c.value < rules.shock_threshold:
		return
	if hit.tick < c.icd_until:
		c.value = rules.shock_threshold  # full, waiting for the per-shooter ICD
		return
	c.value = 0.0
	c.icd_until = hit.tick + _ticks(rules.shock_icd_s)
	_fill_overload(out)
	out.disrupt_s = rules.disrupted_s * dur
	out.reload_penalty_s = rules.disrupted_reload_penalty_s


func _fill_overload(out: Outcome) -> void:
	out.overload = true
	out.arc_damage = rules.shock_arc_damage
	out.arc_targets = rules.shock_arc_targets
	out.arc_radius = rules.shock_arc_radius_m


## Adds Chill to the shared meter; at the top it starts Brittle unless locked.
func add_chill(state: AmmoTargetState, amount: float, tick: int, dur: float = 1.0) -> void:
	state.chill = minf(rules.chill_max, state.chill + maxf(amount, 0.0))
	state.chill_last_hit = tick
	state.chill_delay_ticks = _ticks(rules.chill_decay_delay_s * dur)
	if state.chill >= rules.chill_max - 1e-4 and tick >= state.brittle_lock_until:
		state.brittle_until = tick + _ticks(rules.brittle_s * dur)
		state.brittle_lock_until = state.brittle_until + _ticks(rules.brittle_lock_s)
		state.brittle_reset_done = false


## Cryo slow of `state` (0..chill_max_slow): 25% × meter / 100. Inside the
## shared 40% slow cap (StatusComponent folds it with the other slows).
func chill_slow(state: AmmoTargetState) -> float:
	return rules.chill_max_slow * clampf(state.chill / rules.chill_max, 0.0, 1.0) if state != null else 0.0


## One tick for `state`: Burn damage out, Charge and Chill decay, Brittle end.
## Returns [[shooter_id, team, amount], ...] of Burn damage dealt this tick
## (already mitigated: apply with DamageInfo.FLAG_PREMITIGATED).
func step_target(state: AmmoTargetState, tick: int) -> Array:
	var dmg: Array = []
	if state == null:
		return dmg
	var cap := rules.burn_max_dps / tick_hz
	for id in state.burns.keys():
		var b: AmmoTargetState.BurnPool = state.burns[id]
		if b.ticks_left <= 0 or b.pool <= 0.0:
			state.burns.erase(id)
			continue
		var amount := minf(cap, b.pool / b.ticks_left)
		b.pool -= amount
		b.ticks_left -= 1
		if b.ticks_left <= 0:
			b.pool = 0.0  # pool not dealt within the window at the DPS cap is lost
		dmg.append([b.shooter_id, b.team, amount])
	for id in state.charges.keys():
		var c: AmmoTargetState.Charge = state.charges[id]
		if tick - c.last_hit_tick > _ticks(rules.shock_decay_delay_s):
			c.value = maxf(0.0, c.value - rules.shock_decay_per_s / tick_hz)
			if c.value <= 0.0 and tick >= c.icd_until:
				state.charges.erase(id)
	if not state.brittle_reset_done and tick >= state.brittle_until:
		state.chill = 0.0  # §3.7.1: after Brittle the meter resets
		state.brittle_reset_done = true
	elif state.chill > 0.0 and tick - state.chill_last_hit > state.chill_delay_ticks:
		state.chill = maxf(0.0, state.chill - rules.chill_decay_per_s / tick_hz)
	return dmg


## §3.7.2 Volatile: the burst a kill by `shooter` with `ammo` + Volatile makes
## from the victim's state (not recursive: callers never burst again for
## targets this burst kills).
func volatile_burst(victim: AmmoTargetState, shooter: int, ammo: int, mod: int) -> Outcome:
	var out := Outcome.new()
	if mod != DamageMath.MOD_VOLATILE or not mod_fits(mod, ammo):
		return out
	out.burst_radius = rules.volatile_radius_m
	match ammo:
		DamageMath.AMMO_INCENDIARY:
			out.burst_burn = rules.volatile_burn_share * (victim.burn_left(shooter) if victim != null else 0.0)
		DamageMath.AMMO_SHOCK:
			_fill_overload(out)
			out.arc_radius = rules.volatile_radius_m
		DamageMath.AMMO_SIPHON:
			out.burst_heal = rules.volatile_heal_hp
			out.burst_heal_radius = rules.volatile_heal_radius_m
		DamageMath.AMMO_CRYO:
			out.burst_chill = rules.volatile_chill
		DamageMath.AMMO_SUNDER:
			out.burst_construct_damage = rules.volatile_sunder_damage
	return out


## Volatile Incendiary: adds `amount` to `shooter`'s Burn pool on `state`.
func add_burn(state: AmmoTargetState, shooter: int, team: int, amount: float, dur: float = 1.0) -> void:
	if amount <= 0.0:
		return
	var b: AmmoTargetState.BurnPool = state.burns.get(shooter)
	if b == null:
		b = AmmoTargetState.BurnPool.new()
		b.shooter_id = shooter
		b.team = team
		state.burns[shooter] = b
	b.pool += amount
	b.ticks_left = _ticks(rules.burn_duration_s * dur)


## Drops states of targets for which `alive.call(key)` is false (dead Wardlings).
func prune(alive: Callable) -> void:
	for k in others.keys():
		if not alive.call(k):
			others.erase(k)
