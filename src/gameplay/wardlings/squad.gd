class_name Squad
extends RefCounted
## A hero's personal squad (Canon C15, wardlings-and-economy.md §3, §8, §9.8).
## Gameplay rules only: membership, the current command and its lifetime
## (Attack Target timeout / LOS loss / leash), Foundry minting and the
## owner-death hold. The squad brain (src/ai) reads this and writes only the
## blackboard fields marked "AI blackboard" plus WardlingSim intents.

## Command codes; identical to InputCommand.SQUAD_* (wire values).
const CMD_NONE: int = 0
const CMD_FOLLOW: int = 1
const CMD_HOLD: int = 2
const CMD_ATTACK: int = 3
const CMD_CAPTURE: int = 4

## Why an Attack Target order ended (0 = still running).
const END_NONE: int = 0
const END_TARGET_GONE: int = 1
const END_TIMEOUT: int = 2
const END_LOS_LOST: int = 3
const END_LEASH: int = 4

var id: int = 0
var owner_net_id: int = 0
var team: int = 0
## Live members (dead / dissolved ones are removed by WardlingWorld).
var members: Array[WardlingSim] = []
var size: int = 3

var command: int = CMD_FOLLOW
## Command restored when an Attack Target order ends.
var prev_command: int = CMD_FOLLOW
var hold_point: Vector3 = Vector3.ZERO
var attack_target_id: int = 0
var attack_start_tick: int = 0
var attack_seen_tick: int = 0
## Hardpoint index in lane 0 (Go Capture), -1 = none.
var capture_index: int = -1
var capture_point: Vector3 = Vector3.ZERO
var capture_radius: float = 12.0
var last_end_reason: int = END_NONE

## Owner death (DeathHold); -1 while the owner lives.
var owner_dead_tick: int = -1
## Mints still to come (staggered) and the tick of the next one.
var pending_mints: int = 0
var next_mint_tick: int = 0

## Retaliation memory: who last damaged the owner, and when.
var owner_attacker_id: int = 0
var owner_hit_tick: int = -1000000

## AI blackboard (written by the squad brain at 5 Hz).
var anchor: Vector3 = Vector3.ZERO
var threat_id: int = 0
## net id -> formation / ring slot position.
var slots: Dictionary = {}


func _init(id_: int, owner_id: int, team_: int, size_: int) -> void:
	id = id_
	owner_net_id = owner_id
	team = team_
	size = size_


func is_dissolving() -> bool:
	return owner_dead_tick >= 0


func alive_count() -> int:
	return members.size()


## Applies a validated command. Attack Target remembers the command to revert to.
func issue(cmd: int, tick: int, point: Vector3 = Vector3.ZERO, target_id: int = 0, hp_index: int = -1) -> void:
	match cmd:
		CMD_FOLLOW:
			command = CMD_FOLLOW
		CMD_HOLD:
			command = CMD_HOLD
			hold_point = point
		CMD_ATTACK:
			if command != CMD_ATTACK:
				prev_command = command
			command = CMD_ATTACK
			attack_target_id = target_id
			attack_start_tick = tick
			attack_seen_tick = tick
		CMD_CAPTURE:
			command = CMD_CAPTURE
			capture_index = hp_index
			capture_point = point
	if cmd != CMD_ATTACK:
		attack_target_id = 0
	last_end_reason = END_NONE


## A member saw the Attack target this tick (LOS report from the brain).
func note_target_seen(tick: int) -> void:
	attack_seen_tick = maxi(attack_seen_tick, tick)


## Attack Target lifetime (§9.5): ends when the target is gone, after
## attack_timeout_s, after attack_los_timeout_s without LOS, or when the target
## leaves the leash. The squad then reverts to its previous command.
## Returns the END_* reason (END_NONE while the order stands).
func update_attack(tick: int, tick_hz: int, rules: WardlingRulesDef, target_alive: bool, target_in_leash: bool) -> int:
	if command != CMD_ATTACK:
		return END_NONE
	var reason := END_NONE
	if not target_alive:
		reason = END_TARGET_GONE
	elif tick - attack_start_tick >= roundi(rules.attack_timeout_s * tick_hz):
		reason = END_TIMEOUT
	elif tick - attack_seen_tick >= roundi(rules.attack_los_timeout_s * tick_hz):
		reason = END_LOS_LOST
	elif not target_in_leash:
		reason = END_LEASH
	if reason != END_NONE:
		command = prev_command
		attack_target_id = 0
		last_end_reason = reason
	return reason


## The owner died: whatever the command, the squad holds (DeathHold, §9.8).
func on_owner_died(tick: int, centroid: Vector3) -> void:
	owner_dead_tick = tick
	pending_mints = 0
	if command != CMD_CAPTURE:
		hold_point = centroid
	attack_target_id = 0


## True once the death hold is over (C15: 10 s).
func dissolve_due(tick: int, tick_hz: int, rules: WardlingRulesDef) -> bool:
	return owner_dead_tick >= 0 and tick - owner_dead_tick >= roundi(rules.death_hold_s * tick_hz)


## Wardlings to mint now (§3, C15): a fresh Sanctum spawn or standing in the
## Foundry tops up empty slots; anywhere else nothing is replaced.
static func mint_count(alive: int, pending: int, squad_size: int, at_foundry: bool, spawned_at_sanctum: bool) -> int:
	if not at_foundry and not spawned_at_sanctum:
		return 0
	return maxi(squad_size - alive - pending, 0)


## Records a hit on the owner (retaliation trigger).
func note_owner_hit(attacker_id: int, tick: int) -> void:
	owner_attacker_id = attacker_id
	owner_hit_tick = tick


func centroid() -> Vector3:
	if members.is_empty():
		return anchor
	var c := Vector3.ZERO
	for m in members:
		c += m.global_position
	return c / members.size()
