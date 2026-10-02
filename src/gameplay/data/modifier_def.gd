class_name ModifierDef
extends Resource
## Data form of a Modifier (ADR-0004 §6): skill-tree nodes, passives and mods
## author these; they become Modifier objects on a StatBlock.
## `stat` is a StatCatalog name: a HERO_NAMES entry when `hero_scope`, else a
## SKILL_PARAMS entry of the owning skill.

@export var stat: StringName = &""
@export var op: Modifier.Op = Modifier.Op.ADD
@export var value: float = 0.0
@export var hero_scope: bool = false


## Stat index in its scope's catalog (-1 if unknown).
func index() -> int:
	return StatCatalog.hero_index(stat) if hero_scope else StatCatalog.skill_index(stat)


func to_modifier(source_id: int, expires_tick: int = -1) -> Modifier:
	return Modifier.make(index(), op, value, source_id, expires_tick)


static func make(stat_: StringName, op_: Modifier.Op, value_: float, hero: bool = false) -> ModifierDef:
	var d := ModifierDef.new()
	d.stat = stat_
	d.op = op_
	d.value = value_
	d.hero_scope = hero
	return d
