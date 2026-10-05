class_name SkillNodeDef
extends Resource
## One skill-tree node (ADR-0004 §6, heroes.md §3.5, Canon C12). Nodes never add
## code paths: they carry Modifiers for the skill's StatBlock (or the hero's,
## when hero_scope) and optional effects appended to the skill's effect list.
## M1 (E10) owns every Unlock implicitly; E15 makes Boost / Ult ranks learnable.

enum Kind { UNLOCK, BOOST, FORK_A, FORK_B, MASTERY, ULT_RANK }

@export var kind: Kind = Kind.BOOST
## Minimum hero level (Boost 3, Fork 5, Mastery 9; Ult ranks 6 / 10 / 14).
@export_range(1, 15) var required_level: int = 3
## Ultimate rank this node grants (ULT_RANK only).
@export_range(0, 3) var rank: int = 0
@export var modifiers: Array[ModifierDef] = []
@export var added_effects: Array[Resource] = []
## W11-M1: effects of a second press of the skill inside its recast_window param
## (Echo, Rebound). Unlike SkillDef.recast_effects they need no cooldown / active state.
@export var recast_effects: Array[Resource] = []
