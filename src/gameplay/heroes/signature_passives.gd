class_name SignaturePassives
extends RefCounted
## The 14 Signature passives of one hero (design/gdd/items-and-armory.md §3.5.3,
## §5). Server only; held by HeroCombat. Numbers come from SignatureRulesDef.
##
## Which passives are on is set from outside (ServerWorld reads the active
## copies of the hero's ItemInventory each tick, set_active()). A passive that
## goes off (sold, undone) clears its own state at once; death clears all
## passive state (on_death()).
##
## Hooks the server calls:
##   step(tick)                  once per server tick (timers, continuous effects)
##   on_fired(tick)              the weapon fired a shot
##   on_damaged(type, hp, total) this hero lost `hp` HP (`total` incl. shields)
##   on_kill_or_assist()         Kindle
##   on_head_hit()               True Line (once per shot)
##   on_ult_cast(tick)           Resonant Cast
##   add_rend(tick, rules)       Rend stack on this hero (from an attacker's Breaker Bore)
## Timers are server ticks; "never" is NEVER.
##
## Example:
##   c.passives.set_active([&"lattice"], tick)  # overshield full at once

const KINDLE := &"kindle"
const OVERDRIVE_LOOP := &"overdrive_loop"
const TRUE_LINE := &"true_line"
const LONG_REACH := &"long_reach"
const REND := &"rend"
const DEEP_RESERVE := &"deep_reserve"
const COLD_START := &"cold_start"
const PLANTED := &"planted"
const BRACE := &"brace"
const GROUNDING := &"grounding"
const REGROWTH := &"regrowth"
const LATTICE := &"lattice"
const RESONANT_CAST := &"resonant_cast"
const SIEGEBREAKER := &"siegebreaker"

const NEVER: int = -1000000000

var rules: SignatureRulesDef
var combat: HeroCombat
var tick_hz: int
## Passive id -> true for every passive on now.
var active: Dictionary = {}

## Server tick of the latest damage taken (HP or any shield), shot fired, and
## the first tick of the current still / crouched spell (NEVER = moving).
var last_damaged_tick: int = NEVER
var last_fire_tick: int = NEVER
var still_since_tick: int = NEVER
## Overdrive Loop: first tick of the current continuous-fire streak.
var streak_start_tick: int = NEVER
## Brace: [tick, weapon HP lost] within the window; active until; ready again at.
var brace_hits: Array = []
var brace_until_tick: int = NEVER
var brace_ready_tick: int = NEVER
## Cold Start (Mech): last_fire_tick the instant reload was armed for.
var _cold_armed_for: int = 0
var _cold_armed_once: bool = false
## Rend on this hero (gear-armor points, from any attacker) and its expiry.
var rend: float = 0.0
var rend_until_tick: int = NEVER
## Planted: last horizontal position (stillness is measured tick to tick).
var _last_pos: Vector3 = Vector3.INF
var _crouching: bool = false


func _init(combat_: HeroCombat, tick_hz_: int, rules_: SignatureRulesDef = null) -> void:
	combat = combat_
	tick_hz = tick_hz_
	rules = rules_ if rules_ != null else SignatureRulesDef.shared()


func has(id: StringName) -> bool:
	return active.has(id)


## Seconds -> whole ticks (rounded, at least 1).
func ticks(seconds: float) -> int:
	return maxi(1, roundi(seconds * tick_hz))


## Sets the passives that are on. A passive turned off clears its state; Lattice
## turned on starts full (items-and-armory.md §3.5.3).
func set_active(ids: Array, tick: int) -> void:
	var now := {}
	for id in ids:
		if id != &"":
			now[StringName(id)] = true
	for id in active.keys():
		if not now.has(id):
			active.erase(id)
			_clear(id)
	for id in now:
		if not active.has(id):
			active[id] = true
			_turned_on(id, tick)


## One server tick: timers and the continuous effects. `pos` is the hero's
## position, `crouching` its stance.
func step(tick: int, pos: Vector3 = Vector3.ZERO, crouching: bool = false) -> void:
	_step_rend(tick)
	if combat.dead:
		_last_pos = Vector3.INF
		return
	_step_still(tick, pos, crouching)
	if active.is_empty():
		return
	var health := combat.health
	if has(LATTICE) and tick - last_damaged_tick >= ticks(rules.lattice_delay_s):
		health.overshield = rules.lattice_shield
	if has(REGROWTH) and tick - last_damaged_tick >= ticks(rules.regrowth_delay_s) and health.hp < health.max_hp:
		health.heal(health.max_hp * rules.regrowth_frac_s / tick_hz, 0)
	if has(BRACE):
		health.brace_dr = rules.brace_dr if tick < brace_until_tick else 0.0
	if has(GROUNDING):
		combat.status.cc_duration_mult = rules.grounding_mult
	if has(PLANTED):
		combat.status.knockback_mult = rules.planted_knockback_mult if is_planted(tick) else 1.0
	var w := combat.weapon
	if w == null:
		return
	if has(OVERDRIVE_LOOP):
		var on := overdrive_on(tick)
		var pellets := w.def.pellets > 1
		w.passive_bloom_mult = rules.overdrive_bloom_mult if on and not pellets else 1.0
		w.passive_cone_mult = rules.overdrive_pellet_cone_mult if on and pellets else 1.0
	var idle := tick - last_fire_tick >= ticks(rules.cold_start_idle_s)
	if w.feed is ManaPoolFeed:
		var mf := w.feed as ManaPoolFeed
		mf.no_burnout = has(DEEP_RESERVE)
		mf.regen_scale = rules.cold_start_regen_mult if has(COLD_START) and idle else 1.0
	elif w.feed is MagazineFeed and has(COLD_START) and idle:
		# "Your next reload is instant": armed once per idle spell, spent by the reload.
		if not _cold_armed_once or _cold_armed_for != last_fire_tick:
			(w.feed as MagazineFeed).instant_reload = true
			_cold_armed_for = last_fire_tick
			_cold_armed_once = true


## Planted: crouched, or still for planted_still_s.
func is_planted(tick: int) -> bool:
	if _crouching:
		return true
	return still_since_tick != NEVER and tick - still_since_tick >= ticks(rules.planted_still_s)


## Overdrive Loop: continuous fire (shots <= overdrive_gap_s apart) for overdrive_after_s.
func overdrive_on(tick: int) -> bool:
	if streak_start_tick == NEVER or tick - last_fire_tick > ticks(rules.overdrive_gap_s):
		return false
	return last_fire_tick - streak_start_tick >= ticks(rules.overdrive_after_s)


## Client recoil kick multiplier (Planted -25% more), 1.0 otherwise.
func recoil_mult(tick: int) -> float:
	return rules.planted_recoil_mult if has(PLANTED) and is_planted(tick) else 1.0


## Siegebreaker: weapon damage multiplier vs Ward Generators and an Exposed Uplink.
func siege_mult() -> float:
	return 1.0 + rules.siege_bonus if has(SIEGEBREAKER) else 1.0


## Deep Reserve: Mech Supply Cache refill multiplier.
func refill_mult() -> float:
	return rules.deep_reserve_refill_mult if has(DEEP_RESERVE) else 1.0


## The weapon fired a shot at `tick` (Overdrive streak, Cold Start reset).
func on_fired(tick: int) -> void:
	if streak_start_tick == NEVER or tick - last_fire_tick > ticks(rules.overdrive_gap_s):
		streak_start_tick = tick
	last_fire_tick = tick
	var w := combat.weapon
	if w != null and w.feed is ManaPoolFeed:
		(w.feed as ManaPoolFeed).regen_scale = 1.0  # Cold Start: "until you fire"


## This hero took damage: `hp_lost` HP of `damage_type` (DamageInfo.Type) and
## `total` including shields. Resets the Lattice / Regrowth timers; weapon HP
## losses feed Brace.
func on_damaged(damage_type: int, hp_lost: float, total: float, tick: int) -> void:
	if total <= 0.0 and hp_lost <= 0.0:
		return
	last_damaged_tick = tick
	if not has(BRACE) or damage_type != DamageInfo.Type.WEAPON or hp_lost <= 0.0:
		return
	var window := ticks(rules.brace_window_s)
	brace_hits.append([tick, hp_lost])
	var lost := 0.0
	for i in range(brace_hits.size() - 1, -1, -1):
		if tick - int(brace_hits[i][0]) >= window:
			brace_hits.remove_at(i)
		else:
			lost += float(brace_hits[i][1])
	if tick >= brace_ready_tick and lost >= rules.brace_threshold * combat.health.max_hp - 1e-4:
		brace_until_tick = tick + ticks(rules.brace_s)
		brace_ready_tick = tick + ticks(rules.brace_cooldown_s)
		brace_hits.clear()
		combat.health.brace_dr = rules.brace_dr


## Kindle: a hero kill or assist refills kindle_refill_frac of the magazine
## (from nothing, no reserve) or of the pool. Returns rounds / mana added.
func on_kill_or_assist() -> float:
	if not has(KINDLE) or combat.dead or combat.weapon == null:
		return 0.0
	var f := combat.weapon.feed
	if f is MagazineFeed:
		var mag := f as MagazineFeed
		return mag.add_rounds(maxi(1, roundi(mag.max_magazine() * rules.kindle_refill_frac)))
	if f is ManaPoolFeed:
		var mp := f as ManaPoolFeed
		return mp.add_mana(mp.max_pool() * rules.kindle_refill_frac)
	return 0.0


## True Line: a head hit on a hero refunds the shot (Mech: rounds up to the
## magazine size; Mana: the shot's mana cost). Call once per shot.
func on_head_hit() -> float:
	if not has(TRUE_LINE) or combat.weapon == null:
		return 0.0
	var f := combat.weapon.feed
	if f is MagazineFeed:
		return (f as MagazineFeed).add_rounds(rules.true_line_rounds)
	if f is ManaPoolFeed:
		return (f as ManaPoolFeed).add_mana(f.def.mana_cost * f.cost_mult)
	return 0.0


## Resonant Cast: the ultimate was cast; each basic skill's remaining cooldown
## drops by resonant_cut.
func on_ult_cast(tick: int) -> void:
	if not has(RESONANT_CAST) or combat.abilities == null:
		return
	for slot in 3:
		var s := combat.abilities.skill(slot)
		if s == null:
			continue
		var left := s.cooldown_end_tick - tick
		if left > 0:
			s.cooldown_end_tick -= roundi(left * rules.resonant_cut)


## Rend from an attacker's Breaker Bore (`r` = its rules): one stack on this
## hero, refreshes the timer, capped. Only gear armor is lowered (HealthComponent).
func add_rend(tick: int, r: SignatureRulesDef = null) -> void:
	var rr := r if r != null else rules
	rend = minf(rr.rend_max, rend + rr.rend_per_hit)
	rend_until_tick = tick + ticks(rr.rend_s)
	combat.health.rend = rend


## Death: every passive timer, pool and stack ends (items-and-armory.md §3.5.3).
func on_death() -> void:
	last_damaged_tick = NEVER
	last_fire_tick = NEVER
	still_since_tick = NEVER
	streak_start_tick = NEVER
	brace_hits.clear()
	brace_until_tick = NEVER
	brace_ready_tick = NEVER
	_cold_armed_once = false
	rend = 0.0
	rend_until_tick = NEVER
	_last_pos = Vector3.INF
	_crouching = false
	for id in active:
		_clear(id)


func _turned_on(id: StringName, _tick: int) -> void:
	if id == LATTICE:
		combat.health.overshield = rules.lattice_shield
	elif id == COLD_START:
		_cold_armed_once = false


func _clear(id: StringName) -> void:
	var h := combat.health
	var w := combat.weapon
	match id:
		LATTICE:
			h.overshield = 0.0
		BRACE:
			h.brace_dr = 0.0
			brace_hits.clear()
			brace_until_tick = NEVER
		GROUNDING:
			combat.status.cc_duration_mult = 1.0
		PLANTED:
			combat.status.knockback_mult = 1.0
		OVERDRIVE_LOOP:
			if w != null:
				w.passive_bloom_mult = 1.0
				w.passive_cone_mult = 1.0
		DEEP_RESERVE:
			if w != null and w.feed is ManaPoolFeed:
				(w.feed as ManaPoolFeed).no_burnout = false
		COLD_START:
			_cold_armed_once = false
			if w != null and w.feed is ManaPoolFeed:
				(w.feed as ManaPoolFeed).regen_scale = 1.0
			elif w != null and w.feed is MagazineFeed:
				(w.feed as MagazineFeed).instant_reload = false


func _step_rend(tick: int) -> void:
	if rend > 0.0 and tick >= rend_until_tick:
		rend = 0.0
		rend_until_tick = NEVER
	combat.health.rend = rend


func _step_still(tick: int, pos: Vector3, crouching: bool) -> void:
	var flat := Vector3(pos.x, 0.0, pos.z)
	var moved := _last_pos == Vector3.INF \
		or flat.distance_to(_last_pos) * tick_hz > rules.planted_speed_eps
	_last_pos = flat
	_crouching = crouching
	if not moved:
		if still_since_tick == NEVER:
			still_since_tick = tick
	else:
		still_since_tick = NEVER
