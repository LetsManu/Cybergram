class_name SkillInstance
extends RefCounted
## Runtime state of one skill slot (ADR-0004 §3, architecture.md §7.2): the
## skill's own StatBlock (params seeded from SkillDef.params; tree nodes add
## Modifiers), cooldown in ticks and the "active" window of skills whose
## cooldown starts when their effect ends (heroes.md §3.4).

var def: SkillDef
var slot: int = 0
var stats: StatBlock
## Ultimate rank (0 = not learned yet; basics ignore it).
var rank: int = 0
var learned: Array[SkillNodeDef] = []
var cooldown_end_tick: int = 0
## Length of the current cooldown (HUD sweep).
var cooldown_total_ticks: int = 0
## Effect running; the cooldown starts when it ends (cooldown_on_end skills).
var active: bool = false
var active_until_tick: int = -1
## Times this skill completed a cast (diagnostics / tests).
var casts: int = 0


func _init(skill: SkillDef, slot_: int) -> void:
	def = skill
	slot = slot_
	stats = StatCatalog.new_skill_block(skill.params)


## Current value of a SKILL_PARAMS param (base + node modifiers).
func param(name: StringName) -> float:
	var i := StatCatalog.skill_index(name)
	return stats.get_value(i) if i >= 0 else 0.0


## Applies a tree node's skill-scope modifiers (E15 calls this on LEVEL_SKILL).
## Hero-scope modifiers of the node go to `hero_stats`.
func learn(node: SkillNodeDef, hero_stats: StatBlock = null) -> void:
	var src := Modifier.source(Modifier.SRC_SKILL_NODE, slot * 16 + learned.size())
	for m in node.modifiers:
		if m == null or m.index() < 0:
			continue
		if m.hero_scope:
			if hero_stats != null:
				hero_stats.add_modifier(m.to_modifier(src))
		else:
			stats.add_modifier(m.to_modifier(src))
	if node.kind == SkillNodeDef.Kind.ULT_RANK:
		rank = maxi(rank, node.rank)
	learned.append(node)


func on_cooldown(tick: int) -> bool:
	return tick < cooldown_end_tick


func cooldown_ticks_left(tick: int) -> int:
	return maxi(cooldown_end_tick - tick, 0)


## Effect list: the def's effects plus effects appended by learned nodes.
func effects() -> Array:
	var out: Array = def.effects.duplicate()
	for n in learned:
		out.append_array(n.added_effects)
	return out
