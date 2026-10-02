class_name ObjectiveEvent
extends RefCounted
## A capture or defence outcome (match-flow-and-map.md §3.5 Rewards).
## Economy/progression hooks only: E7 emits these; Economy (Lumen) and
## Progression (Resonance/EXP) consume them later. Nothing pays out yet.

enum Kind { FLIP, DEFENCE }

var kind: Kind = Kind.FLIP
var hardpoint_id: StringName
var lane: int = 0
var index: int = 0
var tick: int = 0
## FLIP: previous owner (MapDef team or TEAM_NEUTRAL). DEFENCE: the attacker.
var old_team: int = MapDef.TEAM_NEUTRAL
## FLIP: the capturing team. DEFENCE: the defending owner.
var new_team: int = MapDef.TEAM_NEUTRAL
## Hero net ids paid `lumen_each` (FLIP: heroes of new_team in the zone within the
## participant window; DEFENCE: defender heroes in the zone).
var participants: PackedInt32Array = PackedInt32Array()
var lumen_each: int = 0
## FLIP: paid to every other hero of new_team.
var lumen_team: int = 0
## PLACEHOLDER (progression GDD owns Resonance amounts).
var exp_each: int = 0
