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
## E15: the basic skill's Unlock node is learned (ultimates: rank >= 1).
var unlocked: bool = false
var cooldown_end_tick: int = 0
## Length of the current cooldown (HUD sweep).
var cooldown_total_ticks: int = 0
## Effect running; the cooldown starts when it ends (cooldown_on_end skills).
var active: bool = false
var active_until_tick: int = -1
## Times this skill completed a cast (diagnostics / tests).
var casts: int = 0
## W9-H2 multi-charge skills (param `charges` > 1; `cooldown` = seconds per
## charge). -1 = not initialised (full).
var charges_left: int = -1


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
	if node.kind == SkillNodeDef.Kind.UNLOCK or node.kind == SkillNodeDef.Kind.ULT_RANK:
		unlocked = true
	learned.append(node)


## E15: a learned node of `kind` (BOOST, FORK_A...).
func has_node(kind: int) -> bool:
	for n in learned:
		if n.kind == kind:
			return true
	return false


## E15: the def's node of `kind` (ult ranks: of `rank_`), or null.
func node_of(kind: int, rank_: int = 0) -> SkillNodeDef:
	for n in def.nodes:
		if n != null and n.kind == kind and (kind != SkillNodeDef.Kind.ULT_RANK or n.rank == rank_):
			return n
	return null


func on_cooldown(tick: int) -> bool:
	if is_multi():
		sync_charges(tick)
		return charges_left <= 0
	return tick < cooldown_end_tick


func cooldown_ticks_left(tick: int) -> int:
	if is_multi():
		sync_charges(tick)
		return maxi(cooldown_end_tick - tick, 0) if charges_left <= 0 else 0
	return maxi(cooldown_end_tick - tick, 0)


## True when the skill has several charges (`charges` param > 1, Boost-able).
func is_multi() -> bool:
	return param(&"charges") > 1.5


func max_charges() -> int:
	return maxi(1, roundi(param(&"charges")))


## Grants the charges whose recharge timer elapsed (one at a time).
func sync_charges(tick: int) -> void:
	var mx := max_charges()
	if charges_left < 0 or charges_left > mx or (charges_left < mx and cooldown_total_ticks <= 0):
		charges_left = mx
	while charges_left < mx and tick >= cooldown_end_tick:
		charges_left += 1
		if charges_left < mx:
			cooldown_end_tick += maxi(cooldown_total_ticks, 1)


## Spends one charge; starts the recharge timer when the skill was full.
func consume_charge(tick: int, recharge_ticks: int) -> void:
	sync_charges(tick)
	var was_full := charges_left >= max_charges()
	charges_left = maxi(charges_left - 1, 0)
	if was_full:
		cooldown_total_ticks = recharge_ticks
		cooldown_end_tick = tick + recharge_ticks


## Effect list: the def's effects plus effects appended by learned nodes.
func effects() -> Array:
	var out: Array = def.effects.duplicate()
	for n in learned:
		out.append_array(n.added_effects)
	return out
