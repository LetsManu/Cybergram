class_name LobbyPhase
extends RefCounted
## Pure champ-select view logic (no nodes): phase title / subtitle keys, the
## countdown bar fill, and the hero grid filter. Display only; the server owns
## the phase (LobbyCodec.PHASE_*).
##
## Example:
##   LobbyPhase.title_key(LobbyCodec.PHASE_COUNTDOWN, true)  # "HUD_LOBBY_PHASE_LOCK"

## Seconds under which the countdown bar turns to the warning colour.
const WARN_S := 10
## Role chip label prefix (built, so the key scanner does not read it as a key).
const ROLE_SHORT_PREFIX := "HUD" + "_ROLE_SHORT_"
const SKILL_PREFIX := "HUD" + "_SKILL_"


## Title key for the lobby phase; `own_ready` = the local player is locked in.
static func title_key(phase: int, own_ready: bool) -> String:
	match phase:
		LobbyCodec.PHASE_COUNTDOWN:
			return "HUD_LOBBY_PHASE_LOCK"
		LobbyCodec.PHASE_LOCKED, LobbyCodec.PHASE_IN_MATCH:
			return "HUD_LOBBY_PHASE_START"
	return "HUD_LOBBY_PHASE_LOCKED_WAIT" if own_ready else "HUD_LOBBY_PHASE_PICK"


## True while a timer runs (countdown or the locked final seconds).
static func has_timer(phase: int) -> bool:
	return phase == LobbyCodec.PHASE_COUNTDOWN or phase == LobbyCodec.PHASE_LOCKED


## Number of slots with `ready` set.
static func locked_count(slots: Array) -> int:
	var n := 0
	for s: Dictionary in slots:
		if s.get("ready", false):
			n += 1
	return n


## Countdown bar fill 0..1; `max_s` = the longest countdown seen.
static func bar_fill(seconds: int, max_s: int) -> float:
	return clampf(float(seconds) / float(maxi(1, max_s)), 0.0, 1.0)


## Slot ids whose `ready` went false -> true between two states (previous
## empty = first state: nobody flashes).
static func newly_locked(prev: Dictionary, slots: Array) -> Array:
	var out: Array = []
	if prev.is_empty():
		return out
	for s: Dictionary in slots:
		if s.get("ready", false) and not prev.get(str(s.id), false):
			out.append(str(s.id))
	return out


## Role key of a hero stem ("HUD_ROLE_TANK").
static func role_key(stem: String) -> String:
	return str(HeroShowcase.ROLE_KEYS.get(stem, "HUD_ROLE_SOLDIER"))


## Chip label key for a role key.
static func role_short_key(role: String) -> String:
	return ROLE_SHORT_PREFIX + role.get_slice("_ROLE_", 1)


## Distinct role keys of `entries`, in first-seen order.
static func roles_of(entries: Array) -> Array:
	var out: Array = []
	for h: Dictionary in entries:
		var r := role_key(str(h.stem))
		if not out.has(r):
			out.append(r)
	return out


## Heroes whose name contains `query` (case-insensitive) and whose role key is
## `role` ("" = any role).
static func filter_heroes(entries: Array, query: String, role: String) -> Array:
	var q := query.strip_edges().to_lower()
	var out: Array = []
	for h: Dictionary in entries:
		if role != "" and role_key(str(h.stem)) != role:
			continue
		if q != "" and not str(h.name).to_lower().contains(q):
			continue
		out.append(h)
	return out


## Localisation key of a skill's blurb.
static func skill_desc_key(skill: SkillDef) -> String:
	return SKILL_PREFIX + String(skill.id).trim_prefix("skill_").to_upper()
