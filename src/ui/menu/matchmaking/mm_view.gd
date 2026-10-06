class_name MmView
extends RefCounted
## W17B-UI: display helpers shared by the matchmaking screens (design/gdd/
## matchmaking.md). Pure functions: string keys, clock text, hero lookups,
## what a seat may click. The server decides every rule; these only decide
## what the UI shows from the state it was sent.
##
## Example:
##   MmView.clock(75.0)                        # "1:15"
##   tr(MmView.queue_key(&"ranked_5v5"))      # "RANKED 5V5"
##   MmView.ranked_line(info)                  # "Gold III · 1563" / "Calibrating 3/10"

## The four queues, in PLAY order: [id, name key, description key].
const QUEUES: Array = [
	[&"normal_5v5", "HUD_MM_Q_NORMAL", "HUD_MM_Q_NORMAL_DESC"],
	[&"ranked_5v5", "HUD_MM_Q_RANKED", "HUD_MM_Q_RANKED_DESC"],
	[&"all_random_3v3", "HUD_MM_Q_ARAM", "HUD_MM_Q_ARAM_DESC"],
	[&"custom", "HUD_MM_Q_CUSTOM", "HUD_MM_Q_CUSTOM_DESC"],
]
const Q_NORMAL: StringName = &"normal_5v5"
const Q_RANKED: StringName = &"ranked_5v5"
const Q_ARAM: StringName = &"all_random_3v3"
const Q_CUSTOM: StringName = &"custom"
## Lane choices: north / center / south / flex, or fill.
const LANES: Array[StringName] = [&"north", &"center", &"south", &"flex", &"fill"]
const LANE_KEYS := {&"north": "HUD_MM_LANE_NORTH", &"center": "HUD_MM_LANE_CENTER",
	&"south": "HUD_MM_LANE_SOUTH", &"flex": "HUD_MM_LANE_FLEX", &"fill": "HUD_MM_LANE_FILL", &"": "HUD_MM_LANE_NONE"}
## Report categories (MatchmakingRulesDef.report_categories) -> label keys.
const REPORT_KEYS := {&"cheating": "HUD_MM_REPORT_CHEATING", &"griefing": "HUD_MM_REPORT_GRIEFING",
	&"abusive_chat": "HUD_MM_REPORT_ABUSIVE", &"afk": "HUD_MM_REPORT_AFK",
	&"offensive_name": "HUD_MM_REPORT_NAME"}
## ContentDB hero id prefix ("hero_brannoc").
const HERO_PREFIX := "hero_"


## "m:ss" for a duration in seconds (negative = 0:00).
static func clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds - 0.0001)) if seconds > 0.0 else 0
	return "%d:%02d" % [s / 60, s % 60]


## Whole seconds left, rounded up ("10", "9", ... "0").
static func secs(seconds: float) -> int:
	return maxi(0, ceili(seconds - 0.0001)) if seconds > 0.0 else 0


static func queue_key(id: StringName) -> String:
	for q: Array in QUEUES:
		if q[0] == id:
			return q[1]
	return "HUD_MM_Q_CUSTOM"


static func queue_desc_key(id: StringName) -> String:
	for q: Array in QUEUES:
		if q[0] == id:
			return q[2]
	return "HUD_MM_Q_CUSTOM_DESC"


static func lane_key(lane: StringName) -> String:
	return LANE_KEYS.get(lane, "HUD_MM_LANE_NONE")


## True when the pair is a legal lane preference (LaneAssigner rules): fill
## alone, or two different lanes.
static func lanes_valid(primary: StringName, secondary: StringName) -> bool:
	if primary == &"fill":
		return true
	return LaneAssigner.valid_prefs([primary, secondary])


## The preference array sent with a queue join.
static func lane_prefs(primary: StringName, secondary: StringName) -> Array:
	return [&"fill"] if primary == &"fill" else [primary, secondary]


## The secondary lane to show after the primary changed: keeps it when it
## stays legal, else the first other lane.
static func fix_secondary(primary: StringName, secondary: StringName) -> StringName:
	if primary == &"fill" or (secondary != primary and secondary != &"fill"):
		return secondary
	for l in LANES:
		if l != primary and l != &"fill":
			return l
	return &"flex"


## Catalog entry ({index, stem, name, ...}) of a ContentDB hero id, or {}.
static func hero_entry(hero_id: StringName) -> Dictionary:
	if hero_id == &"":
		return {}
	return HeroCatalog.find_stem(String(hero_id).trim_prefix(HERO_PREFIX))


## ContentDB hero index of a hero id (0 = none).
static func hero_index(hero_id: StringName) -> int:
	return int(hero_entry(hero_id).get("index", 0))


static func hero_name(hero_id: StringName) -> String:
	return str(hero_entry(hero_id).get("name", ""))


## Hero ids of every catalog hero ("hero_<stem>"), in catalog order.
static func all_heroes() -> Array[StringName]:
	var out: Array[StringName] = []
	for e: Dictionary in HeroCatalog.entries():
		out.append(StringName(HERO_PREFIX + str(e.stem)))
	return out


# --- ranked display ----------------------------------------------------------

## The PLAY / profile badge text of a ranked track
## ({calibrating, games_left, rating, medal: {label}}): "Gold III · 1563" or
## "Calibrating 3/10" (games played / needed).
static func ranked_line(info: Dictionary, calibration_games: int = 10) -> String:
	if info.is_empty():
		return TranslationServer.translate("HUD_MM_UNRANKED")
	if bool(info.get("calibrating", false)):
		var left := int(info.get("games_left", calibration_games))
		return TranslationServer.translate("HUD_MM_CALIBRATING") % [calibration_games - left, calibration_games]
	var medal: Dictionary = info.get("medal", {})
	return "%s · %d" % [str(medal.get("label", "")), int(info.get("rating", 0))]


## Share of the current medal division reached (0..1) for the progress bar.
## `bands`: MatchmakingRulesDef.medal_bands (divisions count from the band's min).
static func medal_progress(rating: float, division_span: float = 40.0, bands: Array = []) -> float:
	if division_span <= 0.0:
		return 0.0
	var base := 0.0
	for b: Dictionary in bands:
		if rating >= float(b.get("min", 0.0)):
			base = float(b.get("min", 0.0))
	return fposmod(rating - base, division_span) / division_span


## What the post-match screen shows of a rating change: {visible: bool,
## delta: int, text: String}. Normal / 3v3 / custom and voided matches hide it.
static func rating_change(queue: StringName, rating: Dictionary, voided: bool) -> Dictionary:
	if queue != Q_RANKED or rating.is_empty():
		return {"visible": false, "delta": 0, "text": ""}
	if voided:
		return {"visible": true, "delta": 0, "text": TranslationServer.translate("HUD_MM_POST_VOID_NO_CHANGE")}
	if bool(rating.get("calibrating", false)):
		return {"visible": true, "delta": 0, "text": TranslationServer.translate("HUD_MM_CALIBRATING")
			% [int(rating.get("games_played", 0)), int(rating.get("games_needed", 10))]}
	var d := int(rating.get("delta", 0))
	return {"visible": true, "delta": d, "text": ("+%d" % d) if d >= 0 else str(d)}


# --- pick phase ---------------------------------------------------------------

## Heroes `team` already holds in a pick state's seats.
static func team_taken(seats: Array, team: int, me: String = "") -> Array[StringName]:
	var out: Array[StringName] = []
	for s: Dictionary in seats:
		if int(s.team) != team:
			continue
		if StringName(s.get("hero", &"")) != &"":
			out.append(StringName(s.hero))
		elif str(s.id) != me and StringName(s.get("hover", &"")) != &"":
			out.append(StringName(s.hover))  # P3: an ally declared it
	return out


## The seat dictionary of `id` in `seats`, or {}.
static func seat(seats: Array, id: String) -> Dictionary:
	for s: Dictionary in seats:
		if str(s.id) == id:
			return s
	return {}


## True when `me` may pick `hero` now: my turn, not picked yet, and no
## teammate holds it (team-unique; the enemy may hold the same hero).
static func can_pick(state: Dictionary, me: String, hero: StringName) -> bool:
	var s := seat(state.get("seats", []), me)
	if s.is_empty() or not bool(s.get("picking", false)) or StringName(s.get("hero", &"")) != &"":
		return false
	if (state.get("bans", []) as Array).has(hero):
		return false
	if state.get("stage", &"pick") == &"ban":
		return not bool(s.get("ban_locked", false))
	return not team_taken(state.get("seats", []), int(s.team), me).has(hero)


## Turn labels of a draft order for team `first`: [{team, picks}] per turn.
static func turn_plan(order: PackedInt32Array, first: int = 0) -> Array:
	var out: Array = []
	for i in order.size():
		out.append({"team": (first + i) % 2, "picks": order[i]})
	return out


## Bench heroes `me` may take (3v3): every bench hero of my team.
static func can_take_bench(state: Dictionary, hero: StringName) -> bool:
	return bool(state.get("open", true)) and (state.get("bench", []) as Array).has(hero)


## True when a reroll button is live: rerolls left and the phase open.
static func can_reroll(state: Dictionary) -> bool:
	return bool(state.get("open", true)) and int(state.get("rerolls_left", 0)) > 0
