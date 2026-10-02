class_name GameEvent
extends RefCounted
## A reliable gameplay event sent server -> client (architecture.md §8.2 Event).
## HIT_CONFIRM goes to the shooter only (hit marker + damage number);
## KILL goes to every client (kill feed, E12).

const HIT_CONFIRM: int = 1
const KILL: int = 2

const FLAG_HEADSHOT: int = 1
const FLAG_KILL: int = 2

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
