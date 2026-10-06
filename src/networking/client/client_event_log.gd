class_name ClientEventLog
extends RefCounted
## P1: the client's last network events for the diagnostics panel ("what did
## the server tell me, and when"). A ring of MAX entries, memory only, cleared
## when the game closes. Entries hold event kinds, states and error codes,
## never passwords, tokens, tickets or chat text. `to_text()` is what the
## "Copy" button puts on the clipboard for a bug report.
##
## Example:
##   log.add("phase", "Queued -> ReadyCheck", {"seq": 7})
##   label.text = log.to_text()

const MAX := 100

## [{t (local s), kind, text, data}]
var entries: Array = []
## Local monotonic clock in seconds (tests inject a fake).
var clock: Callable = func() -> float: return Time.get_ticks_msec() / 1000.0


func add(kind: String, text: String, data: Dictionary = {}) -> void:
	entries.append({"t": float(clock.call()), "kind": kind, "text": text, "data": data})
	if entries.size() > MAX:
		entries.pop_front()


func clear() -> void:
	entries.clear()


## Newest last; one line per entry: "+12.34s phase  Queued -> ReadyCheck {seq=7}".
func to_text(header: String = "") -> String:
	var lines := PackedStringArray()
	if header != "":
		lines.append(header)
	var t0: float = float(entries[0].t) if not entries.is_empty() else 0.0
	for e: Dictionary in entries:
		var extra := ""
		if not (e.data as Dictionary).is_empty():
			var parts := PackedStringArray()
			for k in e.data:
				parts.append("%s=%s" % [k, e.data[k]])
			extra = " {" + ", ".join(parts) + "}"
		lines.append("+%7.2fs %-8s %s%s" % [float(e.t) - t0, e.kind, e.text, extra])
	return "\n".join(lines)
