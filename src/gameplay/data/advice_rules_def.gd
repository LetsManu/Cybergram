class_name AdviceRulesDef
extends Resource
## Tuning of the Armory recommendation rules (BuildAdvisor) and of the server
## signals they read (ProgressionSystem advice signals). Data only; see
## docs/armory.md "Adding a situational rule".

const DEFAULT_PATH := "res://assets/data/economy/advice_rules.tres"

@export_group("Signals (server)")
## Rolling window for "what hurt me lately" (seconds).
@export_range(5.0, 300.0, 1.0) var damage_window_s: float = 45.0
## Damage of one type inside the window, as a fraction of max HP, that sets
## SIG_WEAPON_DAMAGE / SIG_SKILL_DAMAGE (the larger type wins ties).
@export_range(0.1, 5.0, 0.05) var damage_threshold_frac: float = 1.0
## Deaths inside this window that set SIG_DIED_OFTEN.
@export_range(30.0, 900.0, 5.0) var deaths_window_s: float = 240.0
@export_range(1, 10) var deaths_threshold: int = 2
## HP fraction under which SIG_LOW_HEALTH is set.
@export_range(0.05, 0.95, 0.05) var low_health_frac: float = 0.5
## Resonance deficit factor (EconomyMath.deficit) at or above which the team
## counts as behind; a lead of the same size in average level counts as ahead.
@export_range(1.0, 2.0, 0.01) var behind_deficit: float = 1.08
@export_range(0.5, 5.0, 0.1) var ahead_levels: float = 1.5
## SIG_OBJECTIVE_SOON this many seconds before the next Surge.
@export_range(10.0, 300.0, 5.0) var objective_soon_s: float = 60.0

@export_group("Scoring (client + bots)")
## Enemy heroes carrying a threat tag needed for an enemy_<tag> rule (per mode
## team size: 3v3 uses the first value, 5v5 the second).
@export var enemy_tag_threshold: PackedInt32Array = PackedInt32Array([1, 2])
## Score bonus per matched rule id (BuildAdvisor.RULES). Missing ids score 0.
@export var bonus: Dictionary = {
	"core_tier_ready": 40, "affordable_now": 15, "counters_enemy": 35,
	"taking_weapon_damage": 60, "taking_skill_damage": 60, "died_often": 50, "low_health": 30,
	"team_behind": 45, "team_ahead": 30, "objective_soon": 35,
	"enemy_cc": 40, "enemy_burst": 40, "enemy_sustain": 30, "enemy_weapon_dps": 40, "enemy_skill_dps": 40,
	"enemy_mobility": 25, "enemy_zone": 25, "enemy_squad": 30, "enemy_frontline": 30,
	"team_lacks_sustain": 30, "team_lacks_frontline": 30,
}
## "Affordable soon": reachable within this many seconds of expected income.
@export_range(10.0, 300.0, 5.0) var affordable_soon_s: float = 60.0
## Expected Lumen per minute for "affordable soon" (trickle plus a typical share
## of bounties; wardlings-and-economy.md §18 curve slope at 5-10 min).
@export_range(0.0, 2000.0, 10.0) var expected_income_per_min: float = 270.0


func bonus_of(rule_id: String) -> int:
	return int(bonus.get(rule_id, 0))


## Enemy-tag count threshold for a team of `team_size`.
func tag_threshold(team_size: int) -> int:
	if enemy_tag_threshold.is_empty():
		return 2
	return enemy_tag_threshold[0] if team_size <= 3 or enemy_tag_threshold.size() < 2 else enemy_tag_threshold[1]
