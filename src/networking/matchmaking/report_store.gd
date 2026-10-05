class_name ReportStore
extends RefCounted
## Post-match reports and honour (design "Fair play", GDPR: PRIVACY.md
## "Reports and honour").
## - A report is {id, match_id, reporter, target, category, created_at,
##   status ("open" | "resolved"), resolution, resolved_at}. No free text,
##   no IP, no chat logs.
## - Category from rules.report_categories. One report per reporter per
##   target per match; never yourself; both must be in the match.
## - Reports are deleted rules.report_retention_days after they were filed
##   (purge(), at start and daily), resolved or not.
## - Honour is positive only: a count per account. Each player gives at most
##   one honour per match, never to themselves. Who honoured whom is kept
##   only for the retention period (to stop double honour), then purged.
## - erase_account() removes an account's honour and every report it filed
##   or received (account deletion).
## Storage: `dir` == "" keeps everything in memory; otherwise one JSON file
## `<dir>/reports.json`, written atomically, 0700/0600 on Unix.
## Time is injected (`now_unix`).

enum Result { OK, E_CATEGORY, E_SELF, E_DUPLICATE, E_NOT_IN_MATCH, E_STORE }

const FILE := "reports.json"
const RESOLUTIONS: Array[String] = ["dismissed", "warned", "actioned"]
const DAY: int = 86400

var dir: String
var rules: MatchmakingRulesDef
var _reports: Array = []
var _honour: Dictionary = {}        # account id -> int
var _honour_given: Dictionary = {}  # "match|giver" -> unix time
var _seq: int = 0


func _init(dir_: String = "", rules_: MatchmakingRulesDef = null) -> void:
	dir = dir_
	rules = rules_ if rules_ != null else MatchmakingRulesDef.load_default()


func open() -> int:
	if dir == "":
		return OK
	var d := FileAccountStore._abs(dir)
	var err := DirAccess.make_dir_recursive_absolute(d)
	if err != OK and not DirAccess.dir_exists_absolute(d):
		return err
	FileAccountStore._owner_only(d, FileAccountStore.DIR_MODE)
	var path := d.path_join(FILE)
	if not FileAccess.file_exists(path):
		return OK
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		push_warning("[reports] unreadable %s, starting empty" % FILE)
		return OK
	_reports = (data.get("reports", []) as Array).filter(func(r: Variant) -> bool: return r is Dictionary)
	_honour = data.get("honour", {})
	_honour_given = data.get("honour_given", {})
	_seq = int(data.get("seq", 0))
	return OK


## Files a report. `participants`: every account id in the match.
func report(match_id: String, reporter: String, target: String, category: StringName, participants: Array,
		now_unix: int) -> Result:
	if not rules.report_categories.has(category):
		return Result.E_CATEGORY
	if reporter == target:
		return Result.E_SELF
	if not participants.has(reporter) or not participants.has(target) or MatchmakingRulesDef.is_bot(target):
		return Result.E_NOT_IN_MATCH
	for r in _reports:
		if r.match_id == match_id and r.reporter == reporter and r.target == target:
			return Result.E_DUPLICATE
	_seq += 1
	_reports.append({"id": "r%d" % _seq, "match_id": match_id, "reporter": reporter, "target": target,
		"category": String(category), "created_at": now_unix, "status": "open", "resolution": "", "resolved_at": 0})
	return Result.OK if _save() else _undo_last()


## Gives one honour (positive only).
func honour(match_id: String, giver: String, target: String, participants: Array, now_unix: int) -> Result:
	if giver == target:
		return Result.E_SELF
	if not participants.has(giver) or not participants.has(target) or MatchmakingRulesDef.is_bot(target):
		return Result.E_NOT_IN_MATCH
	var key := "%s|%s" % [match_id, giver]
	if _honour_given.has(key):
		return Result.E_DUPLICATE
	_honour_given[key] = now_unix
	_honour[target] = int(_honour.get(target, 0)) + 1
	return Result.OK if _save() else Result.E_STORE


func honour_count(account_id: String) -> int:
	return int(_honour.get(account_id, 0))


## Copies of reports, oldest first. `status` "" = all.
func list(status: String = "open") -> Array:
	var out: Array = []
	for r in _reports:
		if status == "" or r.status == status:
			out.append(r.duplicate())
	return out


func get_report(id: String) -> Dictionary:
	for r in _reports:
		if r.id == id:
			return r.duplicate()
	return {}


## Marks a report resolved with one of RESOLUTIONS.
func resolve(id: String, resolution: String, now_unix: int) -> bool:
	if not RESOLUTIONS.has(resolution):
		return false
	for r in _reports:
		if r.id == id:
			r.status = "resolved"
			r.resolution = resolution
			r.resolved_at = now_unix
			return _save()
	return false


## Deletes reports and honour-given marks older than the retention period.
## Returns how many reports were deleted.
func purge(now_unix: int) -> int:
	var cutoff := now_unix - rules.report_retention_days * DAY
	var before := _reports.size()
	_reports = _reports.filter(func(r: Dictionary) -> bool: return int(r.created_at) >= cutoff)
	for k in _honour_given.keys():
		if int(_honour_given[k]) < cutoff:
			_honour_given.erase(k)
	_save()
	return before - _reports.size()


## Account deletion: drop its honour and every report it filed or received.
func erase_account(account_id: String) -> void:
	_honour.erase(account_id)
	_reports = _reports.filter(func(r: Dictionary) -> bool: return r.reporter != account_id and r.target != account_id)
	for k in _honour_given.keys():
		if String(k).ends_with("|" + account_id):
			_honour_given.erase(k)
	_save()


func _undo_last() -> Result:
	_reports.pop_back()
	return Result.E_STORE


func _save() -> bool:
	if dir == "":
		return true
	var d := FileAccountStore._abs(dir)
	DirAccess.make_dir_recursive_absolute(d)
	var final := d.path_join(FILE)
	var tmp := final + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	FileAccountStore._owner_only(tmp, FileAccountStore.FILE_MODE)
	f.store_string(JSON.stringify({"seq": _seq, "reports": _reports, "honour": _honour,
		"honour_given": _honour_given}, "\t"))
	f.flush()
	f.close()
	if DirAccess.rename_absolute(tmp, final) != OK:
		DirAccess.remove_absolute(final)
		if DirAccess.rename_absolute(tmp, final) != OK:
			DirAccess.remove_absolute(tmp)
			return false
	return true
