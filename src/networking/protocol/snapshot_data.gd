class_name SnapshotData
extends RefCounted
## Decoded server snapshot (architecture.md §8.2). Always the full state the
## client holds at `tick`: since v16 (W16-NET) the wire is a delta against an
## acknowledged baseline, which SnapshotDecoder resolves before this is built.

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
	## E10: StatusComponent.BIT_* (slow, stun, Fortify DR, casting, dashing...).
	var status: int = 0
	## M1: hero identity, ContentDB.index_of(ContentDB.HERO, HeroDef.id)
	## (0 = unknown). Drives the remote HeroView model.
	var hero_index: int = 0
	## W11-V1: Fork / Mastery of the 3 basic skills, 3 bits per slot (slot i at bit 3i):
	## bits 0-1 Fork (0 none, 1 A, 2 B), bit 2 Mastery. Use fork_of() / mastery_of().
	var fork_bits: int = 0

	func fork_of(slot: int) -> int:
		return (fork_bits >> (slot * 3)) & 3

	func mastery_of(slot: int) -> bool:
		return ((fork_bits >> (slot * 3 + 2)) & 1) != 0

	## Builds fork_bits from one slot's values.
	static func with_slot(bits: int, slot: int, fork: int, mastery: bool) -> int:
		var v := (clampi(fork, 0, 2)) | (4 if mastery else 0)
		return (bits & ~(7 << (slot * 3))) | (v << (slot * 3))

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
	## E10 skill bar, per slot S1/S2/S3/Ult: ticks of cooldown left, cooldown
	## length (ticks) and AbilityRunner.FLAG_* (locked, active, casting).
	var skill_cd_left: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var skill_cd_total: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var skill_flags: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	## E10: shield HP, hero level, own StatusComponent.BIT_*.
	var shield: int = 0
	var level: int = 1
	var status: int = 0

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
	## M1: Surge tier I-III the Wardling was minted at (WardlingSim.tier).
	var tier: int = 1
	## W16-NET (client side): not refreshed in this snapshot (deferred by the
	## server's priority / budget); the values are from an older tick, so the
	## interpolation buffer must not take them as a sample at this tick.
	var stale: bool = false

## Replicated skill FX / deployable (E10, AbilityWorld.FX_*): walls, beacons,
## zones, thread projectiles, telegraphs. Everyone sees them (enemy telegraphs).
class FxState:
	var id: int = 0
	var kind: int = 0
	var team: int = 0
	var position: Vector3 = Vector3.ZERO
	## Second point (line end) or size (wall w/h/thickness, circle radius in x).
	var position2: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	## 0..1 (deployable HP fraction).
	var param: float = 1.0
	var ticks_left: int = 0

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
	## E14: effective task (HardpointDef.TaskKind) this match runs.
	var task: int = 0
	## Breach: Generator HP fraction (phase 1, quantised to 1/255), phase 2 flag, shield.
	var gen_frac: float = 0.0
	var breach_phase2: bool = false
	var shielded: bool = false
	## Mid Forward Beacon of the owner (ProgressionSystem.Beacon: 0 none,
	## 1 attuning, 2 ready, 3 under attack) and the attunement fraction (1/15 steps).
	var beacon: int = 0
	var beacon_attune: float = 0.0
	## Plant: HardpointSim.CellState, the Cell's team (-1 none), position, carrier
	## net id (0 none), and the interact channel (HardpointSim.Channel, 0..1 done).
	var cell_state: int = 0
	var cell_team: int = -1
	var cell_pos: Vector3 = Vector3.ZERO
	var carrier_id: int = 0
	var channel: int = 0
	var channel_frac: float = 0.0

## Replicated state of one Uplink (E9).
class UplinkState:
	var team: int = 0
	var integrity: float = 0.0
	var max_integrity: float = 0.0
	var exposed: bool = false

## Match phase, clock and result (E9; MatchRules).
class MatchState:
	## MatchRules.Phase value.
	var phase: int = 0
	## Match clock seconds.
	var time_s: float = 0.0
	## Match time the next phase starts (-1 = none).
	var next_phase_s: float = -1.0
	## Winning team at End (-1 = none / draw).
	var winner: int = -1
	## MatchRules.EndReason value.
	var end_reason: int = 0
	var uplinks: Array[UplinkState] = []

## E13/E15: the receiving client's progression and wallet (own hero only).
class ProgressState:
	var level: int = 1
	## Total Resonance (floor).
	var exp: int = 0
	var skill_points: int = 0
	var lumen: int = 0
	var medpacks: int = 0
	## FLAG_* bits.
	var flags: int = 0
	## Owned squad upgrades: bit i = catalog index i.
	var owned_bits: int = 0
	## Per socket (MOUNT_SOCKETS order): catalog index (-1 = empty), tier, Lumen
	## paid for the line, part paid this Armory visit.
	var mount_item: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
	var mount_tier: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var mount_paid: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var mount_paid_visit: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	## v21 (Armory build system): Armory requests (ACTION_BUY / ACTION_SELL)
	## the server has handled, mod 256, and the HeroProgress.Result of the
	## last one. The client compares shop_seq with the value it saw when it
	## sent a request to show the exact outcome instead of guessing.
	var shop_seq: int = 0
	var shop_result: int = 0
	## Squad upgrades bought during the current Armory visit (bit i = catalog
	## index i) and Med-Packs bought this visit: these can still be undone.
	var visit_owned_bits: int = 0
	var visit_medpacks: int = 0
	## BuildAdvisor signal bits (SIG_*), server-computed from recent combat.
	var signals: int = 0
	## v22 Armory v2 (items-and-armory.md §3.1): catalog index per inventory
	## place (INV_LOCS order: Core, Barrel, Frame, Ammo Type, Ammo Mod, then
	## open slots 0..5; -1 = empty). Spares are the later copies of an id.
	var inv_items: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1])
	## Bit i: the item at INV_LOCS[i] was bought this visit and can be undone
	## on its own (not used up by a later buy).
	var inv_undo_bits: int = 0
	## Purchases / sales this visit ("Undo last" is available when > 0).
	var inv_txns: int = 0
	## Lumen Motes on the ground (everyone's; positions only).
	var motes: PackedVector3Array = PackedVector3Array()

	const FLAG_AT_ARMORY: int = 1
	const FLAG_BEACON_READY: int = 2
	const FLAG_SPAWN_BEACON: int = 4
	const FLAG_HEALING: int = 8
	## Replicated sockets (ArmoryItemDef.Socket): Core, Frame, Chamber, then
	## Barrel (v21, appended so the first three slots keep their meaning).
	const MOUNT_SOCKETS: Array[int] = [1, 3, 4, 2]
	## v22 inventory places (ItemInventory.LOC_*): sockets, Chamber, 6 open slots.
	const INV_LOCS: Array[int] = [1, 2, 3, 4, 5, 16, 17, 18, 19, 20, 21]
	## BuildAdvisor signals (v21): what hurt this hero lately (rolling window).
	const SIG_WEAPON_DAMAGE: int = 1
	const SIG_SKILL_DAMAGE: int = 2
	const SIG_DIED_OFTEN: int = 4
	const SIG_TEAM_BEHIND: int = 8
	const SIG_TEAM_AHEAD: int = 16
	const SIG_LOW_HEALTH: int = 32
	const SIG_OBJECTIVE_SOON: int = 64

var tick: int = 0
## W16-NET (client side): the acknowledged snapshot this one was delta-encoded
## against (valid when is_delta).
var base_tick: int = 0
var is_delta: bool = false
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
## Client decode: Wardling keys (net id & 0xFFFF) this snapshot removed
## explicitly. A Wardling missing from `wardlings` without being listed here
## may only be deferred: a new one that did not fit the byte budget while the
## client's acknowledged baseline predates it (SnapshotCodec.encode_delta).
var wardlings_removed: PackedInt32Array = PackedInt32Array()
## E10 skill FX and deployables.
var fx: Array[FxState] = []
## Mana bolts fired this tick (E8 tracers): [from: Vector3, to: Vector3] pairs.
var bolts: Array = []
## Hardpoints (E7); empty on maps without objectives.
var hardpoints: Array[HardpointState] = []
## Lane fronts (LaneFrontResolver), per lane [concord, syndicate] flattened; -1 = none.
var fronts: PackedInt32Array = PackedInt32Array()
## Match flow (E9); null on servers without one.
var match_state: MatchState = null
## E13/E15 own progression (null on servers without a ProgressionSystem).
var progress: ProgressState = null
