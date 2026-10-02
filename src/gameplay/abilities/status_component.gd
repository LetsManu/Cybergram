class_name StatusComponent
extends RefCounted
## Hero statuses (ADR-0004 §5, design/gdd/heroes.md §3.6). Each status is a
## timed entry; the component folds all live entries into Modifiers on the
## hero StatBlock under one STATUS source, so the rules are applied in one place:
## - Slow: Σ slows capped at AbilityRulesDef.slow_cap (40%).
## - Root / Stun: move speed overridden to 0; Stun also blocks firing and skills.
## - Hard CC (Root, Stun, Knockback) diminishing returns per type: the 2nd within
##   cc_dr_window_s of the 1st lasts 50%, the 3rd 0. CC_IMMUNE blocks hard CC,
##   KNOCKBACK_IMMUNE blocks knockback.
## - DR: additive damage reduction (clamped with armor by DamageMath at 70%).
## - Shield: an absorb pool on the HealthComponent.
## Same kind + same source refreshes; different sources stack.
## Server-only; visual_bits() is what clients see.

enum Kind { SLOW, ROOT, STUN, KNOCKBACK, DR, CC_IMMUNE, SHIELD }

## Replicated visual bits (SnapshotData.EntityState.status).
const BIT_SLOW: int = 1
const BIT_ROOT: int = 2
const BIT_STUN: int = 4
const BIT_DR: int = 8
const BIT_CC_IMMUNE: int = 16
const BIT_SHIELD: int = 32
const BIT_CASTING: int = 64
const BIT_DASHING: int = 128
const BIT_KNOCKBACK: int = 256

const _HARD_CC: Array[int] = [Kind.ROOT, Kind.STUN, Kind.KNOCKBACK]


class Entry:
	var kind: int
	var magnitude: float
	var expires_tick: int
	var source_id: int


var stats: StatBlock
var health: HealthComponent
var rules: AbilityRulesDef
var tick_hz: int
var entries: Array[Entry] = []
## Source tag of the folded modifiers on `stats`.
var source_id: int

var _cc_first_tick: Dictionary = {}  # kind -> tick of the first CC in the window
var _cc_count: Dictionary = {}       # kind -> applications in the window
var _shield_expires: int = -1


func _init(stats_: StatBlock, health_: HealthComponent, rules_: AbilityRulesDef, tick_hz_: int, owner_index: int) -> void:
	stats = stats_
	health = health_
	rules = rules_
	tick_hz = tick_hz_
	source_id = Modifier.source(Modifier.SRC_STATUS, owner_index)


static func is_hard_cc(kind: int) -> bool:
	return _HARD_CC.has(kind)


## Applies a status for `duration_ticks`. Returns the ticks actually applied
## (0 when blocked by immunity or diminishing returns).
func apply(kind: int, duration_ticks: int, magnitude: float, source: int, tick: int) -> int:
	if duration_ticks <= 0:
		return 0
	var ticks := duration_ticks
	if is_hard_cc(kind):
		if stats.get_value(StatCatalog.CC_IMMUNE) > 0.0:
			return 0
		if kind == Kind.KNOCKBACK and stats.get_value(StatCatalog.KNOCKBACK_IMMUNE) > 0.0:
			return 0
		ticks = roundi(ticks * _dr_factor(kind, tick))
		if ticks <= 0:
			return 0
	for e in entries:
		if e.kind == kind and e.source_id == source:
			e.expires_tick = maxi(e.expires_tick, tick + ticks)
			e.magnitude = magnitude
			_after_change(kind, tick + ticks, magnitude)
			return ticks
	var n := Entry.new()
	n.kind = kind
	n.magnitude = magnitude
	n.expires_tick = tick + ticks
	n.source_id = source
	entries.append(n)
	_after_change(kind, n.expires_tick, magnitude)
	return ticks


func has(kind: int) -> bool:
	for e in entries:
		if e.kind == kind:
			return true
	return false


## Hard CC that blocks skills and firing.
func is_stunned() -> bool:
	return has(Kind.STUN)


## Movement is suppressed (root, stun, carried).
func is_immobile() -> bool:
	return has(Kind.ROOT) or has(Kind.STUN) or has(Kind.KNOCKBACK)


## Ticks left of the longest entry of `kind` (0 = none).
func ticks_left(kind: int, tick: int) -> int:
	var t := 0
	for e in entries:
		if e.kind == kind:
			t = maxi(t, e.expires_tick - tick)
	return t


## Total slow after the cap (0..slow_cap).
func slow_total() -> float:
	var s := 0.0
	for e in entries:
		if e.kind == Kind.SLOW:
			s += e.magnitude
	return clampf(s, 0.0, rules.slow_cap)


## Expires entries. Call once per tick.
func step(tick: int) -> void:
	var changed := false
	for i in range(entries.size() - 1, -1, -1):
		if tick >= entries[i].expires_tick:
			entries.remove_at(i)
			changed = true
	if _shield_expires >= 0 and tick >= _shield_expires:
		health.shield = 0.0
		_shield_expires = -1
	if changed:
		_fold()


## Ends every entry applied by `source` (a carry that ended early...).
func remove_source(source: int) -> void:
	var n := entries.size()
	for i in range(n - 1, -1, -1):
		if entries[i].source_id == source:
			entries.remove_at(i)
	if entries.size() != n:
		_fold()


func clear() -> void:
	entries.clear()
	_cc_first_tick.clear()
	_cc_count.clear()
	health.shield = 0.0
	_shield_expires = -1
	_fold()


func visual_bits() -> int:
	var b := 0
	for e in entries:
		match e.kind:
			Kind.SLOW:
				b |= BIT_SLOW
			Kind.ROOT:
				b |= BIT_ROOT
			Kind.STUN:
				b |= BIT_STUN
			Kind.KNOCKBACK:
				b |= BIT_KNOCKBACK
			Kind.DR:
				b |= BIT_DR
			Kind.CC_IMMUNE:
				b |= BIT_CC_IMMUNE
	if health.shield > 0.0:
		b |= BIT_SHIELD
	return b


func _dr_factor(kind: int, tick: int) -> float:
	var window := roundi(rules.cc_dr_window_s * tick_hz)
	var first: int = _cc_first_tick.get(kind, -1000000)
	if tick - first > window:
		_cc_first_tick[kind] = tick
		_cc_count[kind] = 0
	var n: int = _cc_count.get(kind, 0)
	_cc_count[kind] = n + 1
	var f := rules.cc_dr_factors
	return f[mini(n, f.size() - 1)] if not f.is_empty() else 1.0


func _after_change(kind: int, expires: int, magnitude: float) -> void:
	if kind == Kind.SHIELD:
		health.shield = maxf(health.shield, magnitude)
		_shield_expires = maxi(_shield_expires, expires)
	_fold()


## Rewrites the STATUS modifiers on the hero block from the live entries.
func _fold() -> void:
	stats.remove_by_source(source_id)
	var slow := slow_total()
	if slow > 0.0:
		stats.add_modifier(Modifier.make(StatCatalog.MOVE_SPEED, Modifier.Op.PCT, -slow, source_id))
	if is_immobile():
		stats.add_modifier(Modifier.make(StatCatalog.MOVE_SPEED, Modifier.Op.OVERRIDE, 0.0, source_id))
	var dr := 0.0
	for e in entries:
		if e.kind == Kind.DR:
			dr += e.magnitude
	if dr > 0.0:
		stats.add_modifier(Modifier.make(StatCatalog.DAMAGE_REDUCTION, Modifier.Op.ADD, dr, source_id))
	if has(Kind.CC_IMMUNE):
		stats.add_modifier(Modifier.make(StatCatalog.CC_IMMUNE, Modifier.Op.ADD, 1.0, source_id))
