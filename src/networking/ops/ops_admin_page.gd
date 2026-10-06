class_name OpsAdminPage
extends RefCounted
## The /admin HTML page (P1): a plain, self-contained table view of the admin
## snapshot (no scripts, no external assets). Refreshes every 5 s. Every value
## is HTML-escaped. Shows pseudonymous player tags, never names.


static func html(snap: Dictionary) -> String:
	var b := PackedStringArray()
	b.append("<!doctype html><html><head><meta charset=\"utf-8\"><meta http-equiv=\"refresh\" content=\"5\">")
	b.append("<title>Cybergram front</title><style>body{font:13px system-ui,sans-serif;margin:16px;background:#0e1116;color:#d8dee9}")
	b.append("h2{margin:18px 0 6px;font-size:15px}table{border-collapse:collapse;margin-bottom:8px}")
	b.append("td,th{border:1px solid #2b3240;padding:3px 8px;text-align:left}th{background:#1a2030}")
	b.append(".muted{color:#8a93a6}</style></head><body>")
	var h: Dictionary = snap.get("health", {})
	b.append("<h1>Cybergram front</h1><p class=\"muted\">build %s, up %ss, %s client(s) connected</p>" % [
		esc(h.get("version", "?")), esc(h.get("uptime_s", "?")), esc(h.get("clients", "?"))])
	b.append(_table("Queues", ["queue", "players", "parties", "estimate_s"], snap.get("queues", [])))
	b.append(_table("Lobbies and matches", ["match", "queue", "state", "since_s", "humans", "bots"], snap.get("matches", [])))
	b.append(_table("Parties", ["party", "state", "size", "leader"], snap.get("parties", [])))
	b.append(_table("Players", ["player", "phase", "since_s", "seq", "party", "match"], snap.get("players", [])))
	b.append(_table("Last events (newest first)", ["ts", "level", "event", "msg", "player", "party", "match"],
		snap.get("events", [])))
	b.append("</body></html>")
	return "".join(b)


static func _table(title: String, cols: Array, rows: Array) -> String:
	var b := PackedStringArray(["<h2>%s (%d)</h2><table><tr>" % [esc(title), rows.size()]])
	for c in cols:
		b.append("<th>%s</th>" % esc(c))
	b.append("</tr>")
	for r in rows:
		b.append("<tr>")
		for c in cols:
			b.append("<td>%s</td>" % esc((r as Dictionary).get(c, "")))
		b.append("</tr>")
	b.append("</table>")
	return "".join(b)


static func esc(v: Variant) -> String:
	return str(v).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;")
