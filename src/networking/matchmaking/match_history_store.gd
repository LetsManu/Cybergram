class_name MatchHistoryStore
extends RefCounted
## Minimal match history (W17B, design "Dependencies: progression ... match
## history"). One entry per played match:
##   {match_id, queue, ended_at (unix), duration_s, winner (-1 = void),
##    voided, players: [{id, team, hero, left}]}
## Account ids, hero ids and numbers only: no names, no addresses, no chat
## (GDPR data minimisation; PRIVACY.md "Match history"). Entries older than
## rules.history_retention_days are deleted by purge() (daily); an account
## deletion removes the account from every entry (erase_account()).
## Storage: `dir` == "" keeps it in memory; otherwise `<dir>/history.json`,
## written atomically, 0700/0600 on Unix. Time is injected.

const FILE := "history.json"
const DAY: int = 86400
## Most entries kept regardless of age (a hard cap on the file size).
const MAX_ENTRIES: int = 20000

var dir: String
var rules: MatchmakingRulesDef
var entries: Array = []


func _init(dir_: String = "", rules_: MatchmakingRulesDef = null) -> void:
	dir = dir_
	rules = rules_ if rules_ != null else MatchmakingRulesDef.load_default()


func open() -> int:
	if dir == "":
		return OK
	var data: Variant = JsonFileStore.load_json(dir, FILE)
	if data is Dictionary:
		entries = (data.get("entries", []) as Array).filter(func(e: Variant) -> bool: return e is Dictionary)
	return OK


func add(entry: Dictionary) -> bool:
	entries.append(entry.duplicate(true))
	while entries.size() > MAX_ENTRIES:
		entries.pop_front()
	return _save()


## The newest `limit` entries `account_id` played in (newest first).
func of_account(account_id: String, limit: int = 20) -> Array:
	var out: Array = []
	for i in range(entries.size() - 1, -1, -1):
		for p: Dictionary in entries[i].get("players", []):
			if str(p.get("id", "")) == account_id:
				out.append(entries[i].duplicate(true))
				break
		if out.size() >= limit:
			break
	return out


## Deletes entries older than the retention period. Returns how many.
func purge(now_unix: int) -> int:
	var cutoff := now_unix - rules.history_retention_days * DAY
	var before := entries.size()
	entries = entries.filter(func(e: Dictionary) -> bool: return int(e.get("ended_at", 0)) >= cutoff)
	if entries.size() != before:
		_save()
	return before - entries.size()


## Account deletion: the account's id is removed from every entry.
func erase_account(account_id: String) -> void:
	for e: Dictionary in entries:
		e.players = (e.get("players", []) as Array).filter(func(p: Dictionary) -> bool:
			return str(p.get("id", "")) != account_id)
	_save()


func _save() -> bool:
	if dir == "":
		return true
	return JsonFileStore.save_json(dir, FILE, {"entries": entries})
