class_name TaskActor
extends RefCounted
## A hero as Plant / Breach tasks see it this tick (match-flow-and-map.md §3.4
## Plant 1-4): who it is, where it stands and whether it may channel. ServerWorld
## fills one per hero before ObjectiveSystem.step(); tests build them by hand.

var net_id: int = 0
var team: int = 0
var position: Vector3 = Vector3.ZERO
var alive: bool = true
## Interact (F, InputCommand.BTN_INTERACT) held this tick.
var interact: bool = false
## False under crowd control (stun, root): channels break (§3.4 Plant 4).
var can_channel: bool = true
## Dashing / teleporting this tick: a carried Cell drops (§3.4 Plant 2).
var mobility: bool = false


static func make(id: int, team_: int, pos: Vector3, interact_: bool = false, alive_: bool = true) -> TaskActor:
	var a := TaskActor.new()
	a.net_id = id
	a.team = team_
	a.position = pos
	a.interact = interact_
	a.alive = alive_
	return a
