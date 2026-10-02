class_name SnapshotData
extends RefCounted
## Decoded server snapshot (architecture.md §8.2). Full state for now; delta
## compression against acked baselines is a later epic but uses this same path.

## Replicated state of one entity.
class EntityState:
	var net_id: int = 0
	var kind: int = 0
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var pitch: float = 0.0
	var crouching: bool = false
	var grounded: bool = false
	var dead: bool = false
	var team: int = 0
	var hp: int = 0
	var max_hp: int = 0

## Combat state of the receiving client's own hero (health, feed, respawn).
class OwnCombat:
	var hp: int = 0
	var max_hp: int = 0
	var dead: bool = false
	## Server tick of the respawn (valid while dead).
	var respawn_tick: int = 0
	## WeaponDef.FeedKind value.
	var feed_kind: int = 0
	## Mana in the pool, or rounds in the magazine.
	var ammo: float = 0.0
	var ammo_capacity: int = 0
	var reserve: int = 0
	## AmmoFeed.FLAG_* bits.
	var ammo_flags: int = 0

## Replicated state of one Wardling (E8, compact: wardlings-and-economy.md §14).
class WardlingState:
	var net_id: int = 0
	var position: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	## HP fraction 0..1 (quantised to 1/255).
	var hp_frac: float = 1.0
	var team: int = 0
	## Ownerless Vanguard wave member.
	var vanguard: bool = false
	## Owning hero (0 = none).
	var owner_net_id: int = 0
	## bits 0-2: Squad.CMD_* (5 = Vanguard); bits 3-4: WardlingSim.FLAG_*; bit 5: dissolving.
	var state: int = 0

## Replicated state of one hardpoint (E7), in ObjectiveSystem.all order.
class HardpointState:
	## MapDef team, or MapDef.TEAM_NEUTRAL (-1).
	var owner: int = -1
	## Capture progress P in [0, 1] (quantised to 1/65535).
	var progress: float = 0.0
	## Team the progress belongs to, or -1.
	var capturing_team: int = -1
	var contested: bool = false
	var overtime: bool = false
	var severed: bool = false
	## Locked (C3-ineligible) for team 0 / team 1.
	var locked: Array[bool] = [false, false]

var tick: int = 0
## Highest InputCommand.seq the server applied for the receiving client.
var last_processed_seq: int = 0
## Receiving client's hero (0 = none).
var own_net_id: int = 0
## Full motor state of the client's own hero, for reconciliation.
var own_state: MotorState = null
## Present whenever own_state is.
var own_combat: OwnCombat = null
var entities: Array[EntityState] = []
## Wardlings (E8).
var wardlings: Array[WardlingState] = []
## Mana bolts fired this tick (E8 tracers): [from: Vector3, to: Vector3] pairs.
var bolts: Array = []
## Hardpoints (E7); empty on maps without objectives.
var hardpoints: Array[HardpointState] = []
## Lane fronts (LaneFrontResolver), per lane [concord, syndicate] flattened; -1 = none.
var fronts: PackedInt32Array = PackedInt32Array()
