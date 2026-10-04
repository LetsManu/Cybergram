class_name LocalModeration
extends RefCounted
## Client-side chat safety for this session only (design/ux/lobby-and-social.md
## §4/§6): players muted on this computer (their lobby chat is hidden) and a
## report stub. **Memory only**: the client stores nothing on disk (server
## accounts); a lasting block is the server-side BLOCK (AccountCodec.OP_BLOCK).
##
## Example:
##   var m := LocalModeration.shared()
##   m.mute(id, "Neo")
##   if m.is_muted(id): skip_line()

const MAX_ENTRIES: int = 200
const REASON_MAX: int = 120

static var _shared: LocalModeration

## id -> name (as seen when muted).
var muted: Dictionary = {}
## Array of {id, name, reason, unix_time}; a stub until a moderation backend exists (not sent).
var reports: Array = []


## The session's moderation state (forgotten when the game closes).
static func shared() -> LocalModeration:
	if _shared == null:
		_shared = LocalModeration.new()
	return _shared


func mute(id: String, name: String) -> void:
	if PlayerProfile.is_hex_id(id) and muted.size() < MAX_ENTRIES:
		muted[id] = name


func unmute(id: String) -> void:
	muted.erase(id)


func is_muted(id: String) -> bool:
	return muted.has(id)


## Records a report in memory (no network, no file). `unix_time` from the caller.
func report(id: String, name: String, reason: String, unix_time: float) -> void:
	if not PlayerProfile.is_hex_id(id):
		return
	reports.append({"id": id, "name": name, "reason": reason.left(REASON_MAX), "unix_time": int(unix_time)})
	while reports.size() > MAX_ENTRIES:
		reports.remove_at(0)
