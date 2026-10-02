class_name Modifier
extends RefCounted
## One change to one stat (architecture.md §7.1): {stat_index, op, value,
## source_id, expires_tick}. Sources tag their modifiers so they can be removed
## together (StatBlock.remove_by_source). expires_tick -1 = permanent.

enum Op { ADD, PCT, MUL, OVERRIDE }

## Source kinds (source_id = kind << 24 | index).
const SRC_LEVEL: int = 1
const SRC_SKILL_NODE: int = 2
const SRC_MOD: int = 3
const SRC_STATUS: int = 4
const SRC_SURGE: int = 5
const SRC_PASSIVE: int = 6
const SRC_ZONE: int = 7

var stat: int = 0
var op: Op = Op.ADD
var value: float = 0.0
var source_id: int = 0
var expires_tick: int = -1
## Set by StatBlock.add_modifier (insertion order; the latest OVERRIDE wins).
var handle: int = 0


static func make(stat_: int, op_: Op, value_: float, source: int = 0, expires: int = -1) -> Modifier:
	var m := Modifier.new()
	m.stat = stat_
	m.op = op_
	m.value = value_
	m.source_id = source
	m.expires_tick = expires
	return m


static func source(kind: int, index: int) -> int:
	return (kind << 24) | (index & 0xFFFFFF)
