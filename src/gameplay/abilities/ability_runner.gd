class_name AbilityRunner
extends RefCounted
## Per-hero skill gate and cast state machine (ADR-0004 §3, architecture.md
## §7.2, design/gdd/heroes.md §3.4). Server-authoritative: skills fire on the
## press edge of InputCommand.BTN_SKILL1..4 (S1 Q, S2 E, S3 C, Ult G).
##
## try_activate gates, in order: alive -> learned (ultimate: level >= 6, or
## the --grant-ult debug flag) -> not stunned -> not casting -> recast (Rally
## Beacon double-tap, while its deployable lives) -> cooldown -> 0.25 s shared
## lockout. Then: cast time (telegraph, cancellable by Stun -> 50% cooldown) ->
## targeting -> effects -> cooldown (or "active" until the effect ends).
## EffectiveCD = max(min, CD × (1 − min(0.25, CDR))).
##
## States per slot: READY -> (CASTING) -> ACTIVE | COOLDOWN -> READY.

signal skill_activated(slot: int, tick: int)
signal cooldown_started(slot: int, end_tick: int)
signal skill_rejected(slot: int, reason: int)

enum Reject { NONE, DEAD, LOCKED, STUNNED, CASTING, COOLDOWN, LOCKOUT, NO_TARGET }

const SLOT_BUTTONS: Array[int] = [InputCommand.BTN_SKILL1, InputCommand.BTN_SKILL2,
	InputCommand.BTN_SKILL3, InputCommand.BTN_SKILL4]
const ULT_SLOT: int = 3

## Replicated per-slot flags (SnapshotData.OwnCombat.skill_flags).
const FLAG_LOCKED: int = 1
const FLAG_ACTIVE: int = 2
const FLAG_CASTING: int = 4
## E15 skill tree (replicated in the same byte): Boost learned, ultimate rank
## (2 bits), a point can be spent on this slot now (set by ProgressionSystem).
const FLAG_BOOSTED: int = 8
const RANK_SHIFT: int = 4
const RANK_MASK: int = 48
const FLAG_LEARNABLE: int = 64

var combat: HeroCombat
var rules: AbilityRulesDef
var tick_hz: int
var skills: Array[SkillInstance] = []
var lockout_until_tick: int = 0
## Debug (--grant-ult): the ultimate is usable below level 6 (with the E15
## tree on: every skill is usable unlearned).
var debug_grant_ult: bool = false
## E15: skills are usable only once learned (Unlock / Ult rank 1). Off = the
## E10 rule (basics owned from L1, the ultimate by level). ProgressionSystem
## turns it on for every hero it tracks.
var tree_enabled: bool = false
var last_reject: int = Reject.NONE

var casting_slot: int = -1
var cast_end_tick: int = 0
var _cast_ctx: EffectContext
var _prev_buttons: int = 0
## Forced-motion window (charge / leap), set by AbilityWorld.
var dash_until_tick: int = -1
var _now: int = 0


func _init(c: HeroCombat, rules_: AbilityRulesDef, tick_hz_: int) -> void:
	combat = c
	rules = rules_
	tick_hz = tick_hz_
	for i in c.def.skills.size():
		if c.def.skills[i] != null:
			skills.append(SkillInstance.new(c.def.skills[i], i))


func skill(slot: int) -> SkillInstance:
	return skills[slot] if slot >= 0 and slot < skills.size() else null


func is_casting() -> bool:
	return casting_slot >= 0


func is_dashing() -> bool:
	return _now < dash_until_tick


## heroes.md §3.5: a basic is owned from L1 (Unlock); the ultimate needs its level.
func is_unlocked(slot: int) -> bool:
	var s := skill(slot)
	if s == null:
		return false
	if debug_grant_ult and (s.def.ultimate or tree_enabled):
		return true
	if tree_enabled:
		return s.unlocked
	return combat.level >= s.def.required_level


## Effective cooldown in seconds after CDR (cap 25%) and the minimum.
func effective_cooldown_s(s: SkillInstance) -> float:
	var cdr := minf(rules.cdr_cap, combat.stats.get_value(StatCatalog.COOLDOWN_REDUCTION))
	var lo := rules.min_cooldown_ult_s if s.def.ultimate else rules.min_cooldown_basic_s
	return maxf(lo, s.param(&"cooldown") * (1.0 - cdr))


func start_cooldown(s: SkillInstance, tick: int, frac: float = 1.0) -> void:
	s.active = false
	s.active_until_tick = -1
	var total := ceili(effective_cooldown_s(s) * frac * tick_hz)
	if s.is_multi():  # W9-H2: charges recharge one at a time
		s.consume_charge(tick, total)
		cooldown_started.emit(s.slot, s.cooldown_end_tick)
		return
	s.cooldown_total_ticks = total
	s.cooldown_end_tick = tick + s.cooldown_total_ticks
	cooldown_started.emit(s.slot, s.cooldown_end_tick)


## The skill's effect ended early (wall destroyed...): start its cooldown now.
func end_active(s: SkillInstance, tick: int) -> void:
	if s.active:
		start_cooldown(s, tick)


## heroes.md §3.4: HQ respawn resets basic cooldowns, never the ultimate.
func on_respawn_at_hq() -> void:
	for s in skills:
		if not s.def.ultimate:
			s.cooldown_end_tick = 0
			s.cooldown_total_ticks = 0
			s.charges_left = -1
			s.active = false
			s.active_until_tick = -1
	casting_slot = -1
	_cast_ctx = null
	dash_until_tick = -1


## One tick for hero `h` with `cmd` (after movement). `world` executes effects.
func process(h: HeroBody, cmd: InputCommand, tick: int, world: AbilityWorld) -> void:
	_now = tick
	for s in skills:
		if s.active and s.active_until_tick >= 0 and tick >= s.active_until_tick:
			start_cooldown(s, tick)
	if casting_slot >= 0:
		var cs := skills[casting_slot]
		if combat.dead or (cs.def.interruptible and combat.status.is_stunned()):
			cancel_cast(tick, world)
		elif tick >= cast_end_tick:
			var ctx := _cast_ctx
			casting_slot = -1
			_cast_ctx = null
			_execute(cs, ctx, world)
	var pressed := cmd.buttons & ~_prev_buttons
	_prev_buttons = cmd.buttons
	if combat.dead:
		return
	for slot in SLOT_BUTTONS.size():
		if (pressed & SLOT_BUTTONS[slot]) != 0:
			try_activate(slot, h, cmd, tick, world)


## Stun/death during a cast: cancelled, 50% of the cooldown (heroes.md §3.4).
func cancel_cast(tick: int, world: AbilityWorld) -> void:
	if casting_slot < 0:
		return
	var cs := skills[casting_slot]
	casting_slot = -1
	_cast_ctx = null
	if world != null:
		world.clear_cast_fx(combat)
	start_cooldown(cs, tick, rules.interrupt_cooldown_frac)


func try_activate(slot: int, h: HeroBody, cmd: InputCommand, tick: int, world: AbilityWorld) -> bool:
	_now = tick
	var r := _gate(slot, tick, world)
	if r != Reject.NONE:
		return _reject(slot, r)
	var s := skills[slot]
	if (s.on_cooldown(tick) or s.active) and not s.def.recast_effects.is_empty():
		var rctx := _context(s, h, cmd, tick, world)
		rctx.run(s.def.recast_effects)
		return true
	if s.active:
		return _reject(slot, Reject.COOLDOWN)
	if s.on_cooldown(tick):
		return _reject(slot, Reject.COOLDOWN)
	if tick < lockout_until_tick:
		return _reject(slot, Reject.LOCKOUT)
	var ctx := _context(s, h, cmd, tick, world)
	if not Targeting.resolve(s.def, ctx):
		return _reject(slot, Reject.NO_TARGET)
	lockout_until_tick = tick + ceili(rules.lockout_s * tick_hz)
	var cast := roundi(s.param(&"cast_time") * tick_hz)
	if cast > 0:
		casting_slot = slot
		cast_end_tick = tick + cast
		_cast_ctx = ctx
		if world != null:
			world.cast_started(ctx, cast)
		return true
	_execute(s, ctx, world)
	return true


func _gate(slot: int, tick: int, _world: AbilityWorld) -> int:
	if skill(slot) == null:
		return Reject.LOCKED
	if combat.dead:
		return Reject.DEAD
	if not is_unlocked(slot):
		return Reject.LOCKED
	if combat.status.is_stunned():
		return Reject.STUNNED
	if casting_slot >= 0 or tick < dash_until_tick:
		return Reject.CASTING
	return Reject.NONE


func _reject(slot: int, reason: int) -> bool:
	last_reject = reason
	skill_rejected.emit(slot, reason)
	return false


func _context(s: SkillInstance, h: HeroBody, cmd: InputCommand, tick: int, world: AbilityWorld) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.world = world
	ctx.caster = h
	ctx.skill = s
	ctx.team = combat.team
	ctx.tick = tick
	ctx.yaw = cmd.yaw
	ctx.origin = h.state.position + Vector3(0.0, h.eye_height(), 0.0)
	ctx.dir = Basis(Vector3.UP, cmd.yaw) * Basis(Vector3.RIGHT, cmd.pitch) * Vector3.FORWARD
	ctx.point = h.state.position
	return ctx


func _execute(s: SkillInstance, ctx: EffectContext, world: AbilityWorld) -> void:
	ctx.tick = _now
	if world != null:
		world.clear_cast_fx(combat)
	if s.def.cooldown_on_end:
		s.active = true
		var dur := s.param(s.def.active_param)
		s.active_until_tick = _now + roundi(dur * tick_hz) if dur > 0.0 else -1
	else:
		start_cooldown(s, _now)
	s.casts += 1
	ctx.run(s.effects())
	skill_activated.emit(s.slot, _now)


## Replicated HUD state for `slot`: [ticks left, total ticks, flags].
func hud_state(slot: int, tick: int) -> Array:
	var s := skill(slot)
	if s == null:
		return [0, 0, FLAG_LOCKED]
	var f := 0
	if not is_unlocked(slot):
		f |= FLAG_LOCKED
	if s.active:
		f |= FLAG_ACTIVE
	if casting_slot == slot:
		f |= FLAG_CASTING
	if s.has_node(SkillNodeDef.Kind.BOOST):
		f |= FLAG_BOOSTED
	f |= (clampi(s.rank, 0, 3) << RANK_SHIFT) & RANK_MASK
	return [s.cooldown_ticks_left(tick), s.cooldown_total_ticks, f]
