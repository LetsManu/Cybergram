class_name HeroProgress
extends RefCounted
## Server-side progression and wallet of one hero (wardlings-and-economy.md
## Part 2; weapons-and-mods.md §3.6): Resonance, level, skill points, Lumen,
## mounts per socket, squad upgrades, Med-Packs, kill streak and the damage
## memory used for assists. Owned by ProgressionSystem; replicated to the
## owning client as SnapshotData.ProgressState.

## Outcome of learn / buy / sell / use requests (bots read these).
enum Result {
	OK, NOT_AT_ARMORY, DEAD, UNKNOWN_ITEM, NO_FUNDS, WRONG_FAMILY, REQUIRES, LIMIT, NOT_OWNED,
	NO_POINTS, LEVEL_GATE, MAXED, NO_SKILL, NOT_IN_SLICE, DISABLED,
	# W10-T1 skill tree: a Fork needs an A/B choice; a Fork is already chosen.
	FORK_CHOICE, FORK_LOCKED,
}

## Spawn choice on the death screen (match-flow-and-map.md §3.5, hud.md §9).
const SPAWN_SANCTUM: int = 0
const SPAWN_BEACON: int = 1


## One mounted Crystal / Chip line or Ammo Type.
class Mount:
	var item: ArmoryItemDef
	## Catalog index (wire id).
	var index: int = -1
	var tier: int = 1
	## Total Lumen paid for this line (all tiers).
	var paid: int = 0
	## Part of `paid` spent during the current Armory visit (100% undo).
	var paid_visit: int = 0


var hero_id: int = 0
## Total Resonance (float: shares are fractional; HUD shows floor).
var exp: float = 0.0
var level: int = 1
## Skill points spent (learned nodes).
var spent: int = 0
var lumen: int = 0
## Lumen / Resonance earned this match by source (telemetry, economy sanity check).
var earned: Dictionary = {}
var exp_by: Dictionary = {}
## ArmoryItemDef.Socket -> Mount.
var mounts: Dictionary = {}
## Squad upgrade ids owned (last for the match).
var owned: Dictionary = {}
var medpacks: int = 0
## Inside the own HQ Armory zone and alive (a visit is open).
var at_armory: bool = false
## Kills since the last death (Shutdown bounty).
var streak: int = 0
## Hero net id -> last tick it damaged this hero (assists, last-damager credit).
var damagers: Dictionary = {}
var spawn_choice: int = SPAWN_SANCTUM
## Med-Pack heal over time: until tick, HP per tick, weapon shot count at start.
var heal_until_tick: int = -1
var heal_per_tick: float = 0.0
var heal_shots: int = 0
var _lumen_frac: float = 0.0


func _init(id: int = 0) -> void:
	hero_id = id


func skill_points() -> int:
	return EconomyMath.skill_points_total(level) - spent


## Adds `amount` Lumen (fractions carry over); returns the whole Lumen paid.
func add_lumen(amount: float, source: StringName) -> int:
	_lumen_frac += maxf(amount, 0.0)
	var whole := floori(_lumen_frac + 1e-6)
	_lumen_frac -= whole
	lumen += whole
	earned[source] = int(earned.get(source, 0)) + whole
	return whole


func total_earned() -> int:
	var t := 0
	for k in earned:
		t += int(earned[k])
	return t


func mount(socket: int) -> Mount:
	return mounts.get(socket)


## The Armory visit ends (left the zone or died): purchases lose their undo.
func end_visit() -> void:
	at_armory = false
	for s in mounts:
		(mounts[s] as Mount).paid_visit = 0
