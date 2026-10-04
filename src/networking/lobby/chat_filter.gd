class_name ChatFilter
extends RefCounted
## Server-side lobby chat hygiene (design/ux/lobby-and-social.md §2.3):
## sanitize() cleans one message, RateLimiter is a per-player token bucket.
## The client never decides what is shown to others.
##
## Example:
##   var clean := ChatFilter.sanitize(raw)      # "" = drop it
##   var rl := ChatFilter.RateLimiter.new()
##   if rl.allow(now_s): broadcast(clean)

## Burst size and refill period of the chat token bucket.
const BURST: int = 4
const REFILL_S: float = 1.5


## Token bucket: BURST messages at once, then one more every REFILL_S.
class RateLimiter:
	extends RefCounted
	var tokens: float = float(BURST)
	var last_s: float = -1.0

	## True (and a token spent) when a message at time `now_s` may pass.
	func allow(now_s: float) -> bool:
		if last_s >= 0.0:
			tokens = minf(float(BURST), tokens + (now_s - last_s) / REFILL_S)
		last_s = now_s
		if tokens < 1.0:
			return false
		tokens -= 1.0
		return true


## Cleans a chat message: drops control characters, bidi overrides / isolates,
## zero-width and other invisible format characters, the replacement char;
## collapses runs of whitespace; trims; cuts to LobbyCodec.CHAT_MAX_CHARS.
## Returns "" when nothing printable is left.
static func sanitize(raw: String) -> String:
	var out := ""
	var space := false
	for i in raw.length():
		var c := raw.unicode_at(i)
		if _is_space(c):
			space = true
			continue
		if _is_invisible(c):
			continue
		if space and out != "":
			out += " "
		space = false
		out += String.chr(c)
		if out.length() >= LobbyCodec.CHAT_MAX_CHARS:
			break
	return out.substr(0, LobbyCodec.CHAT_MAX_CHARS)


static func _is_space(c: int) -> bool:
	return c == 0x20 or c == 0x09 or c == 0x0A or c == 0x0D or c == 0xA0 or c == 0x3000 \
		or (c >= 0x2000 and c <= 0x200A) or c == 0x2028 or c == 0x2029 or c == 0x202F or c == 0x205F


static func _is_invisible(c: int) -> bool:
	return c < 0x20 or (c >= 0x7F and c <= 0x9F) \
		or (c >= 0x200B and c <= 0x200F) \
		or (c >= 0x202A and c <= 0x202E) \
		or (c >= 0x2060 and c <= 0x206F) \
		or c == 0xFEFF or c == 0xFFFD or c == 0x00AD or c == 0x034F \
		or (c >= 0xFE00 and c <= 0xFE0F) or (c >= 0xFFF0 and c <= 0xFFFF) \
		or (c >= 0xE0000 and c <= 0xE007F) or (c >= 0xD800 and c <= 0xDFFF)
