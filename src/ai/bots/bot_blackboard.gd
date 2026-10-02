class_name BotBlackboard
extends RefCounted
## What one bot knows at its last decision (architecture.md §9 Blackboard).
## Filled by BotBrain from BotSensor (LOS-gated, no omniscience) and public
## match state (hardpoints, Uplink exposure are on every player's HUD).
## Goals score from this alone, so unit tests can build situations by hand.

const NO_HARDPOINT: int = -1

var tick: int = 0
var tick_hz: int = 30
var team: int = 0
var pos: Vector3 = Vector3.ZERO
var hp_frac: float = 1.0
## Weapon resource left, 0..1 (magazine + reserve, or mana).
var ammo_frac: float = 1.0

## Lane front (LaneFrontResolver) for this bot's team.
var front_index: int = NO_HARDPOINT
var front_pos: Vector3 = Vector3.ZERO
var front_radius: float = 12.0
var front_is_own: bool = false
## Own hardpoint the enemy is taking (progress > 0), nearest to the bot.
var defend_index: int = NO_HARDPOINT
var defend_pos: Vector3 = Vector3.ZERO
var defend_radius: float = 12.0
var defend_progress: float = 0.0

## Current fight target (hero, Wardling or Uplink) chosen by the sensor.
var target_id: int = 0
var target_is_hero: bool = false
var target_dist: float = INF
var target_pos: Vector3 = Vector3.ZERO
## Target hero's HP fraction (1 for non-heroes).
var target_hp_frac: float = 1.0
## Visible enemy heroes / Wardlings within engage range.
var enemy_heroes_seen: int = 0
var enemy_wardlings_seen: int = 0
## Ticks of the last sighting of an enemy hero and of the last damage taken.
var last_seen_enemy_tick: int = -1000000
var last_damaged_tick: int = -1000000
var last_attacker_id: int = 0

## Enemy Uplink Exposed (F6) and where to shoot it from.
var enemy_uplink_exposed: bool = false
var enemy_uplink_id: int = 0
var enemy_uplink_pos: Vector3 = Vector3.ZERO
var siege_pos: Vector3 = Vector3.ZERO

## HQ (Sanctum) of the bot's team: retreat target.
var home_pos: Vector3 = Vector3.ZERO
## Goal chosen at the previous decision (BotGoal.Kind) and when it started.
var current_goal: int = -1
## A retreat that ended without healing (no regen in the slice) blocks the
## next one until this tick, so a hurt bot fights on instead of shuttling.
var retreat_block_until_tick: int = -1000000
var goal_since_tick: int = 0


func seconds_since(t: int) -> float:
	return float(tick - t) / float(tick_hz)


## Damaged or saw an enemy hero within `window_s`.
func threatened(window_s: float) -> bool:
	return seconds_since(last_damaged_tick) <= window_s or seconds_since(last_seen_enemy_tick) <= window_s


static func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
