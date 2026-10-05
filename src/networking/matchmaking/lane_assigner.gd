class_name LaneAssigner
extends RefCounted
## Starting lanes from lane preferences (design "Lane preference", LoL
## position-queue style). A player's preference is [primary, secondary]
## from north / center / south / flex, or [fill]. A queue gives one lane slot
## per team member (MatchQueueDef.lane_slots).
## Score per player: primary 2, secondary 1, other 0, fill 2 (any slot is
## what they asked for). The assignment maximises the team's total score
## (exhaustive bitmask search, at most 5 x 2^5 states); ties go to the
## earlier player in the list (players are listed priority / oldest first).

const LANES: Array[StringName] = [&"north", &"center", &"south", &"flex"]
const FILL: StringName = &"fill"
const BEST: int = 2


## True when `prefs` is [fill], [] (= fill) or two different known lanes.
static func valid_prefs(prefs: Array) -> bool:
	if prefs.is_empty() or (prefs.size() == 1 and StringName(prefs[0]) == FILL):
		return true
	return prefs.size() == 2 and LANES.has(StringName(prefs[0])) and LANES.has(StringName(prefs[1])) \
		and StringName(prefs[0]) != StringName(prefs[1])


static func score(prefs: Array, lane: StringName) -> int:
	if prefs.is_empty() or StringName(prefs[0]) == FILL:
		return BEST
	if StringName(prefs[0]) == lane:
		return 2
	if prefs.size() > 1 and StringName(prefs[1]) == lane:
		return 1
	return 0


## Assigns slots. `prefs_list[i]` is player i's preference. Returns
## {lanes: Array[StringName] per player, misses: int (sum of BEST - score)}.
## No slots: every lane is &"" and misses 0.
static func assign(prefs_list: Array, slots: Array) -> Dictionary:
	var n := prefs_list.size()
	if slots.is_empty() or n == 0:
		var none: Array[StringName] = []
		none.resize(n)
		none.fill(&"")
		return {"lanes": none, "misses": 0}
	var memo := {}
	var best := _best(0, 0, prefs_list, slots, memo)
	var lanes: Array[StringName] = []
	var mask := 0
	for i in n:
		var pick: int = memo[i * 64 + mask][1]
		lanes.append(StringName(slots[pick]) if pick >= 0 else &"")
		if pick >= 0:
			mask |= 1 << pick
	return {"lanes": lanes, "misses": n * BEST - best}


static func _best(i: int, mask: int, prefs_list: Array, slots: Array, memo: Dictionary) -> int:
	if i >= prefs_list.size():
		return 0
	var key := i * 64 + mask
	if memo.has(key):
		return memo[key][0]
	var best := -1
	var pick := -1
	for s in slots.size():
		if mask & (1 << s):
			continue
		var v := score(prefs_list[i], StringName(slots[s])) + _best(i + 1, mask | (1 << s), prefs_list, slots, memo)
		if v > best:
			best = v
			pick = s
	if pick < 0:
		best = _best(i + 1, mask, prefs_list, slots, memo)  # more players than slots
	memo[key] = [best, pick]
	return best
