class_name ReportReview
extends RefCounted
## The owner's report review commands (tools/server/review_reports.sh).
## Pure: takes a ReportStore, arguments and the time; returns
## {code: int (0 ok, 1 not found, 2 usage), text: String}.
##   list [--all]                  open (or all) reports, oldest first, plus
##                                 open reports per target
##   show <id>                     one report
##   resolve <id> <dismissed|warned|actioned>
##   purge                         delete reports past the retention period
##   honour <account id>           honour count

const USAGE := "usage: review_reports [--dir <reports dir>] list [--all] | show <id> | resolve <id> <dismissed|warned|actioned> | purge | honour <account id>"


static func run(store: ReportStore, args: Array, now_unix: int) -> Dictionary:
	if args.is_empty():
		return {"code": 2, "text": USAGE}
	match String(args[0]):
		"list":
			return {"code": 0, "text": _list(store, args.has("--all"))}
		"show":
			if args.size() < 2:
				return {"code": 2, "text": USAGE}
			var r := store.get_report(String(args[1]))
			return {"code": 0, "text": _line(r)} if not r.is_empty() else {"code": 1, "text": "no report %s" % args[1]}
		"resolve":
			if args.size() < 3 or not ReportStore.RESOLUTIONS.has(String(args[2])):
				return {"code": 2, "text": USAGE}
			if store.resolve(String(args[1]), String(args[2]), now_unix):
				return {"code": 0, "text": "resolved %s: %s" % [args[1], args[2]]}
			return {"code": 1, "text": "no report %s" % args[1]}
		"purge":
			return {"code": 0, "text": "purged %d report(s) older than %d days" % [store.purge(now_unix), store.rules.report_retention_days]}
		"honour":
			if args.size() < 2:
				return {"code": 2, "text": USAGE}
			return {"code": 0, "text": "%s honour %d" % [args[1], store.honour_count(String(args[1]))]}
	return {"code": 2, "text": USAGE}


static func _list(store: ReportStore, all: bool) -> String:
	var rs := store.list("" if all else "open")
	if rs.is_empty():
		return "no reports"
	var lines: Array[String] = []
	var per_target := {}
	for r in rs:
		lines.append(_line(r))
		if r.status == "open":
			per_target[r.target] = int(per_target.get(r.target, 0)) + 1
	lines.append("open reports per target:")
	var targets := per_target.keys()
	targets.sort_custom(func(a: String, b: String) -> bool:
		return per_target[a] > per_target[b] if per_target[a] != per_target[b] else a < b)
	for t in targets:
		lines.append("  %s  %d" % [t, per_target[t]])
	return "\n".join(lines)


static func _line(r: Dictionary) -> String:
	var when := Time.get_datetime_string_from_unix_time(int(r.created_at), true)
	var s := "%s  %s  match %s  %s -> %s  %s  %s" % [r.id, when, r.match_id, r.reporter, r.target, r.category, r.status]
	if r.status == "resolved":
		s += " (%s)" % r.resolution
	return s
