class_name GameEvent
extends RefCounted
## A reliable gameplay event sent server -> client (architecture.md §8.2 Event).
## HIT_CONFIRM goes to the shooter only (hit marker + damage number);
## KILL goes to every client (kill feed, E12).

const HIT_CONFIRM: int = 1
const KILL: int = 2
## E9: match phase change, to every client. target_net_id = MatchRules.Phase,
## source_net_id = winner + 1 (0 = none / draw), flags = MatchRules.EndReason,
## amount = match clock seconds.
const MATCH_PHASE: int = 3
## A weapon shot, to every client, for bullet tracers. source_net_id = the
## shooter, position = where the pellet stopped (hit point, wall or max range).
## One event per traced pellet (capped per shot by ServerWorld).
const SHOT: int = 4

## W10-W4: one per hero and stat, to every client, once when the match ends.
## target_net_id = the hero, flags = MatchStats.Stat, amount = the total.
## Same 22-byte record: no layout change (clients that do not know the kind skip it).
const PLAYER_STAT: int = 5

## W11-V1: a hero cast a skill, to every client (clients skip their own: they detect
## those from cooldowns). source_net_id = the caster, position = the caster's feet,
## flags = slot (bits 0-1, 0..2 basic skills, 3 ultimate) | Fork (bits 2-3, 0 none /
## 1 A / 2 B) | FLAG_CAST_MASTERY (bit 4). Same 22-byte record.
const SKILL_CAST: int = 6
const CAST_SLOT_MASK: int = 3
const CAST_FORK_SHIFT: int = 2
const FLAG_CAST_MASTERY: int = 16

const FLAG_HEADSHOT: int = 1
const FLAG_KILL: int = 2
## E9: the hit landed on a sealed (not Exposed) Uplink and was dropped (ImmuneHit cue).
const FLAG_IMMUNE: int = 4

var kind: int = 0
## HIT_CONFIRM: the target hit. KILL: the victim.
var target_net_id: int = 0
## HIT_CONFIRM: the shooter. KILL: the killer.
var source_net_id: int = 0
## HP removed (after armor) by this shot, all pellets summed.
var amount: float = 0.0
var flags: int = 0
## World position of the (first) hit.
var position: Vector3 = Vector3.ZERO


static func hit_confirm(target: int, source: int, amount_: float, flags_: int, pos: Vector3) -> GameEvent:
	var e := GameEvent.new()
	e.kind = HIT_CONFIRM
	e.target_net_id = target
	e.source_net_id = source
	e.amount = amount_
	e.flags = flags_
	e.position = pos
	return e


static func kill(victim: int, killer: int, pos: Vector3) -> GameEvent:
	var e := GameEvent.new()
	e.kind = KILL
	e.target_net_id = victim
	e.source_net_id = killer
	e.position = pos
	return e


static func shot(shooter: int, end: Vector3) -> GameEvent:
	var e := GameEvent.new()
	e.kind = SHOT
	e.source_net_id = shooter
	e.position = end
	return e


static func match_phase(phase: int, winner: int, reason: int, time_s: float) -> GameEvent:
	var e := GameEvent.new()
	e.kind = MATCH_PHASE
	e.target_net_id = phase
	e.source_net_id = winner + 1
	e.flags = reason
	e.amount = time_s
	return e


static func player_stat(hero_net_id: int, stat: int, value: float) -> GameEvent:
	var e := GameEvent.new()
	e.kind = PLAYER_STAT
	e.target_net_id = hero_net_id
	e.flags = stat
	e.amount = value
	return e


static func skill_cast(caster: int, slot: int, fork: int, mastery: bool, pos: Vector3) -> GameEvent:
	var e := GameEvent.new()
	e.kind = SKILL_CAST
	e.source_net_id = caster
	e.position = pos
	e.flags = (slot & CAST_SLOT_MASK) | ((clampi(fork, 0, 2) << CAST_FORK_SHIFT) & 12) \
		| (FLAG_CAST_MASTERY if mastery else 0)
	return e


## SKILL_CAST accessors.
func cast_slot() -> int:
	return flags & CAST_SLOT_MASK


func cast_fork() -> int:
	return (flags >> CAST_FORK_SHIFT) & 3


func cast_mastery() -> bool:
	return (flags & FLAG_CAST_MASTERY) != 0
