class_name OnlineText
extends RefCounted
## Pure helpers for the launcher's online UI (W15): server status lines, the
## message of the day, ping. Static and side-effect free, so tests cover them.

## Message of the day: the launcher shows at most this many characters even
## if a server sends more (the server cuts it too: OnlineRulesDef.motd_max_chars).
const MOTD_MAX_CHARS: int = 200
## Ping colour bands (ms): below GOOD = ok, below FAIR = warn, else danger.
const PING_GOOD_MS: int = 80
const PING_FAIR_MS: int = 150


## The MOTD of a status.json body as plain text ("" when absent): control,
## invisible and bidi characters dropped, whitespace collapsed, capped.
static func motd_of(status_json: String) -> String:
	var parsed: Variant = JSON.parse_string(status_json)
	if typeof(parsed) != TYPE_DICTIONARY or typeof((parsed as Dictionary).get("motd")) != TYPE_STRING:
		return ""
	return plain_text(String(parsed["motd"]), MOTD_MAX_CHARS)


## Plain one-paragraph text of at most `max_chars` characters.
static func plain_text(raw: String, max_chars: int) -> String:
	var out: String = ""
	var space: bool = false
	for i in raw.length():
		var c: int = raw.unicode_at(i)
		if c == 0x20 or c == 0x09 or c == 0x0A or c == 0x0D or c == 0xA0 or c == 0x3000:
			space = true
			continue
		if c < 0x20 or (c >= 0x7F and c <= 0x9F) or (c >= 0x200B and c <= 0x200F) \
				or (c >= 0x202A and c <= 0x202E) or (c >= 0x2060 and c <= 0x206F) or c == 0xFEFF:
			continue
		if space and out != "":
			out += " "
		space = false
		out += String.chr(c)
		if out.length() >= max_chars:
			break
	return out.substr(0, max_chars)


## "ONLINE" / "OFFLINE" headline for the status widget.
static func state_word(info: Dictionary) -> String:
	return "ONLINE" if bool(info.get("reachable", false)) else "OFFLINE"


## Second line: player count, or why there is none.
static func players_line(info: Dictionary) -> String:
	if not bool(info.get("reachable", false)):
		return "The game server cannot be reached."
	if not bool(info.get("has_counts", false)):
		return "Player count not published"
	var n: int = int(info.get("online", 0))
	return "%d player%s online" % [n, "" if n == 1 else "s"]


## "23 ms", or an en dash while there is no measurement.
static func ping_text(rtt_ms: int) -> String:
	return "– ms" if rtt_ms < 0 else "%d ms" % rtt_ms


## 0 = good, 1 = fair, 2 = poor, -1 = unknown.
static func ping_band(rtt_ms: int) -> int:
	if rtt_ms < 0:
		return -1
	if rtt_ms < PING_GOOD_MS:
		return 0
	return 1 if rtt_ms < PING_FAIR_MS else 2
