class_name MatchmakingRulesDef
extends Resource
## Every matchmaking, rating and fair-play tuning knob
## (design/gdd/matchmaking.md §4 / §7; data:
## assets/data/net/matchmaking_rules.tres). Tuning lives here, not in code.
## Each knob documents its safe range; validate() lists violations.

const PATH := "res://assets/data/net/matchmaking_rules.tres"
## Seat ids starting with this are bots (labelled, never rated or stored).
const BOT_PREFIX := "bot:"

@export_group("Queues")
## The queues: Normal 5v5, Ranked 5v5, 3v3 All Random, Custom.
@export var queues: Array[MatchQueueDef] = []
## Largest party allowed in any queue. Safe range 1-5 (5 = a full team).
@export_range(1, 5) var party_max: int = 5

@export_group("Ready check")
## Seconds everyone has to accept a found match. Safe range 5-30.
@export_range(5.0, 30.0) var ready_check_s: float = 10.0

@export_group("Search window")
## Rating distance accepted at once (Glicko scale). Safe range 25-300.
@export_range(25.0, 300.0) var search_window_base: float = 100.0
## Window growth per second of waiting. Safe range 0.5-20.
@export_range(0.5, 20.0) var search_window_growth_per_s: float = 5.0
## The window never grows beyond this. Safe range 200-2000.
@export_range(200.0, 2000.0) var search_window_max: float = 800.0
## Weight of a premade-size mismatch in team balancing, in rating points per
## player of mismatch. Safe range 0-200 (0 = ignore premades).
@export_range(0.0, 200.0) var premade_mismatch_weight: float = 60.0
## Weight of one unmet lane preference step in team balancing, in rating
## points. Safe range 0-100 (0 = lanes do not affect teams).
@export_range(0.0, 100.0) var lane_mismatch_weight: float = 15.0
## Estimated wait shown when the queue has no history yet (s). Safe 10-600.
@export_range(10.0, 600.0) var default_wait_estimate_s: float = 60.0
## How many recent matches the wait estimate averages. Safe range 1-100.
@export_range(1, 100) var wait_estimate_samples: int = 20

@export_group("Parties")
## Ranked only: highest minus lowest member rating allowed in a party.
## Safe range 100-1500.
@export_range(100.0, 1500.0) var ranked_party_gap_max: float = 500.0

@export_group("Bots")
## Seconds the oldest ticket waits before bots fill (Normal and 3v3 only).
## Safe range 60-90 (the design's band); wider values work but are untested.
@export_range(30.0, 300.0) var bot_fill_delay_s: float = 75.0
## Rating a bot counts as when balancing teams. Safe range 800-1800.
@export_range(800.0, 1800.0) var bot_rating: float = 1300.0
## False: a match with any bot changes nobody's rating. Recommended false.
@export var rate_bot_matches: bool = false

@export_group("Lockouts")
## Queue lockout (s) per strike for declining or missing a ready check, or
## dodging the pick phase. The last step repeats. Safe steps 0-3600 each.
@export var decline_lockout_steps_s: PackedFloat32Array = PackedFloat32Array([30.0, 120.0, 300.0, 900.0, 1800.0])
## Ranked queue lockout (s) per abandon strike. The last step repeats.
## Safe steps 0-604800 (a week).
@export var leaver_lockout_steps_s: PackedFloat32Array = PackedFloat32Array([600.0, 3600.0, 14400.0, 86400.0])
## One decline strike decays after this long without a new one. Safe range
## 3600-604800 (1 h - 7 d).
@export_range(3600.0, 604800.0) var decline_strike_decay_s: float = 21600.0
## One leaver strike decays after this long without a new one. Safe range
## 86400-2592000 (1-30 d).
@export_range(86400.0, 2592000.0) var leaver_strike_decay_s: float = 604800.0

@export_group("Rating (Glicko-2)")
## Starting rating. Safe range 1000-2000.
@export_range(1000.0, 2000.0) var rating_initial: float = 1500.0
## Starting rating deviation. Safe range 200-350.
@export_range(200.0, 350.0) var deviation_initial: float = 350.0
## Deviation floor, so ratings never freeze. Safe range 30-100.
@export_range(30.0, 100.0) var deviation_min: float = 50.0
## Starting volatility. Safe range 0.03-0.1.
@export_range(0.03, 0.1) var volatility_initial: float = 0.06
## System constant tau (how fast volatility may move). Safe range 0.3-1.2.
@export_range(0.3, 1.2) var tau: float = 0.5
## Ranked games before the visible number and medal are shown. Safe 3-20.
@export_range(1, 30) var calibration_games: int = 10
## Extra rating points a leaver loses on top of the loss. Safe range 0-50.
@export_range(0.0, 50.0) var leaver_penalty: float = 15.0
## Share of a normal loss the leaver's teammates lose. Safe range 0-1.
@export_range(0.0, 1.0) var leaver_teammate_loss_scale: float = 0.5
## Ranked pick-phase dodge: rating points lost. Safe range 0-30.
@export_range(0.0, 30.0) var dodge_rating_penalty: float = 5.0
## Medal bands for the visible ranked number, ascending by min rating.
## Each entry {name: String, min: float, divisions: int}. Names: classic
## metals, lowest to highest (owner decision 2026-10-05).
@export var medal_bands: Array[Dictionary] = [
	{"name": "Iron", "min": 0.0, "divisions": 5},
	{"name": "Bronze", "min": 1100.0, "divisions": 5},
	{"name": "Silver", "min": 1300.0, "divisions": 5},
	{"name": "Gold", "min": 1500.0, "divisions": 5},
	{"name": "Platinum", "min": 1700.0, "divisions": 5},
	{"name": "Diamond", "min": 1900.0, "divisions": 5},
	{"name": "Master", "min": 2100.0, "divisions": 1},
]
## Rating span of one medal division (bands split into equal steps). Safe
## range 20-100.
@export_range(20.0, 100.0) var medal_division_span: float = 40.0

@export_group("Pick phase")
## Seconds per draft turn before a random legal hero is picked. Safe 15-60.
@export_range(10.0, 90.0) var pick_turn_s: float = 30.0
## Draft order: picks per turn, teams alternating, first team starts.
@export var draft_order: PackedInt32Array = PackedInt32Array([1, 2, 2, 2, 2, 1])
## Seconds of the 3v3 All Random phase (rerolls, bench, swaps). Safe 15-90.
@export_range(10.0, 120.0) var all_random_s: float = 45.0
## Rerolls each player gets per 3v3 game. Safe range 0-3 (design: 1-2).
@export_range(0, 3) var rerolls_per_player: int = 1
## A teammate swap request expires after this long (s). Safe range 5-30.
@export_range(5.0, 60.0) var swap_request_ttl_s: float = 10.0
## W17B: a player disconnected from the front this long during the pick
## phase counts as a dodge. Safe range 5-30.
@export_range(2.0, 60.0) var pick_disconnect_grace_s: float = 10.0

@export_group("Fair play")
## A remake vote may start only this long after the match starts (s).
## Safe range 60-300 (design: about 3 min).
@export_range(60.0, 300.0) var remake_window_s: float = 180.0
## A started remake vote stays open this long (s). Safe range 15-60.
@export_range(10.0, 90.0) var remake_vote_s: float = 30.0
## Report categories (ids; the client localises them).
@export var report_categories: Array[StringName] = [&"cheating", &"griefing", &"abusive_chat", &"afk", &"offensive_name"]
## Reports are deleted this many days after they were filed (PRIVACY.md).
## Safe range 7-90.
@export_range(1, 365) var report_retention_days: int = 30
## W17B: reports and honour are accepted this long after a match (s). Safe 120-1800.
@export_range(60.0, 3600.0) var report_window_s: float = 600.0
## W17B: match history entries (ids, heroes, result, duration) are deleted
## this many days after the match (PRIVACY.md). Safe range 30-365.
@export_range(1, 3650) var history_retention_days: int = 180
## W17B: persisted lockout strikes of an account are deleted this many days
## after its last strike (PRIVACY.md). Safe range 7-90.
@export_range(1, 365) var lockout_retention_days: int = 30

@export_group("Match servers")
## Port range for match processes, overridden by CYBERGRAM_MATCH_PORTS.
@export var match_port_first: int = 7800
@export var match_port_last: int = 7809
## Most concurrent match processes. Safe range 1-64 (2 per core).
@export_range(1, 256) var max_concurrent_matches: int = 8
## W17B: a formed match waits this long for a free match process before it
## is voided and its players re-queued (s). Safe range 30-300.
@export_range(10.0, 600.0) var allocate_wait_s: float = 120.0
## W17B: queue status is pushed to queued players this often (s). Safe 1-5.
@export_range(0.5, 10.0) var queue_status_every_s: float = 2.0


## True when `seat_id` is a bot seat.
static func is_bot(seat_id: String) -> bool:
	return seat_id.begins_with(BOT_PREFIX)


## The rules from PATH, or code defaults (with the four standard queues).
static func load_default() -> MatchmakingRulesDef:
	var r := load(PATH) as MatchmakingRulesDef if ResourceLoader.exists(PATH) else null
	if r == null:
		r = MatchmakingRulesDef.new()
	if r.queues.is_empty():
		r.queues = standard_queues()
	return r


## The four queues of the design, as code (tests and fallback).
static func standard_queues() -> Array[MatchQueueDef]:
	var out: Array[MatchQueueDef] = []
	out.append(_q(&"normal_5v5", "Normal 5v5", &"shardline_front", 5, MatchQueueDef.PickMode.DRAFT, &"normal", false, true, true))
	out.append(_q(&"ranked_5v5", "Ranked 5v5", &"shardline_front", 5, MatchQueueDef.PickMode.DRAFT, &"ranked", true, false, true))
	out.append(_q(&"all_random_3v3", "3v3 All Random", &"slice", 3, MatchQueueDef.PickMode.ALL_RANDOM, &"all_random", false, true, true))
	out.append(_q(&"custom", "Custom game", &"", 5, MatchQueueDef.PickMode.HOST_CHOICE, &"", false, true, false))
	for q in out:
		if q.team_size == 5:
			q.lane_slots = [&"north", &"center", &"south", &"flex", &"flex"]
	return out


static func _q(id: StringName, name: String, map: StringName, size: int, mode: MatchQueueDef.PickMode,
		track: StringName, ranked: bool, bots: bool, matchmade: bool) -> MatchQueueDef:
	var q := MatchQueueDef.new()
	q.id = id
	q.display_name = name
	q.map_id = map
	q.team_size = size
	q.pick_mode = mode
	q.rating_track = track
	q.ranked = ranked
	q.bots_allowed = bots
	q.matchmade = matchmade
	return q


## The queue with `id`, or null.
func queue(id: StringName) -> MatchQueueDef:
	for q in queues:
		if q.id == id:
			return q
	return null


## Rule violations as readable strings (empty = valid).
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for q in queues:
		if seen.has(q.id):
			out.append("duplicate queue %s" % q.id)
		seen[q.id] = true
		if q.ranked and q.bots_allowed:
			out.append("ranked queue %s allows bots" % q.id)
		if not q.lane_slots.is_empty() and q.lane_slots.size() != q.team_size:
			out.append("queue %s lane_slots size != team_size" % q.id)
	var total := 0
	for n in draft_order:
		if n < 1:
			out.append("draft_order has a turn with < 1 pick")
		total += n
	for q in queues:
		if q.pick_mode == MatchQueueDef.PickMode.DRAFT and total != q.team_size * 2:
			out.append("draft_order sums to %d, queue %s needs %d" % [total, q.id, q.team_size * 2])
	if decline_lockout_steps_s.is_empty() or leaver_lockout_steps_s.is_empty():
		out.append("lockout steps must not be empty")
	var last := -INF
	for b in medal_bands:
		if float(b.get("min", 0.0)) <= last:
			out.append("medal_bands not ascending")
		last = float(b.get("min", 0.0))
	for i in medal_bands.size():
		if String(medal_bands[i].get("name", "")) == "":
			out.append("medal band %d has no name" % i)
	if search_window_base > search_window_max:
		out.append("search_window_base > search_window_max")
	if match_port_last < match_port_first:
		out.append("match port range is empty")
	return out
