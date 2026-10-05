class_name OnlineRulesDef
extends Resource
## Server tuning for the W15 online features (data:
## assets/data/net/online_rules.tres): launch tokens, the message of the day,
## crash reports and parties. Tuning lives here, not in code.

const PATH := "res://assets/data/net/online_rules.tres"

## A launch token (launcher -> game sign-in) is valid this long, single use.
@export_range(5.0, 300.0) var launch_token_ttl_s: float = 60.0
## Most launch tokens held at once (a flood guard; the oldest go first).
@export_range(16, 100000) var launch_tokens_max: int = 4096
## Message of the day: plain text, at most this many characters.
@export_range(16, 1000) var motd_max_chars: int = 200
## Crash reports: largest accepted report (compressed bytes).
@export_range(1024, 1048576) var crash_max_bytes: int = 65536
## Crash reports are deleted after this many days (PRIVACY.md).
@export_range(1, 365) var crash_retention_days: int = 30
## The crash folder never grows beyond this (oldest reports go first).
@export_range(1, 10000) var crash_dir_cap_mb: int = 200
## Reports accepted per source address per hour and per account per day.
@export_range(1, 100) var crash_per_ip_per_hour: int = 3
@export_range(1, 100) var crash_per_account_per_day: int = 5
## Seconds an unfinished chunked report may take before it is dropped.
@export_range(5.0, 600.0) var crash_upload_timeout_s: float = 60.0
## Party size (leader included). 5 since W17B (any party size 1-5 in every queue).
@export_range(2, 10) var party_max: int = 5
## A party invite expires after this long.
@export_range(10.0, 3600.0) var party_invite_ttl_s: float = 120.0

## W20-WEB public snapshot (CYBERGRAM_PUBLIC_DIR, read by the website):
## seconds between writes of the counts (players, matches, queues).
@export_range(1.0, 300.0) var public_snapshot_every_s: float = 5.0
## Seconds between leaderboard recomputations (a scan of all ratings).
@export_range(10.0, 3600.0) var public_leaderboard_every_s: float = 60.0
## Leaderboard rows published (opted-in, calibrated ranked players only).
@export_range(0, 500) var public_leaderboard_size: int = 100


## The rules from PATH, or defaults.
static func load_default() -> OnlineRulesDef:
	var r := load(PATH) as OnlineRulesDef if ResourceLoader.exists(PATH) else null
	return r if r != null else OnlineRulesDef.new()
