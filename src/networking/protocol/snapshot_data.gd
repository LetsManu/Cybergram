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

var tick: int = 0
## Highest InputCommand.seq the server applied for the receiving client.
var last_processed_seq: int = 0
## Receiving client's hero (0 = none).
var own_net_id: int = 0
## Full motor state of the client's own hero, for reconciliation.
var own_state: MotorState = null
var entities: Array[EntityState] = []
