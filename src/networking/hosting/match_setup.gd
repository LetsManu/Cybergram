class_name MatchSetup
extends RefCounted
## The match setup a match process receives at allocation (W17, like Riot's
## "Megapacket"): who plays, on which team, with which pick, which mode, map
## and rules. Plain Dictionary on the wire/in the file; this class validates it.
##   {match_id, mode, map, rules: {}, roster: [{account, team, hero, lane, bot}]}
## - account: 32 hex (AccountStore id), "" for a bot;
## - team: 0 or 1; hero/lane: short ids ("" = not picked / any).
## No display names or other personal data: the match process looks names up
## through the front when it needs them (GDPR: the file holds ids only).

const MAX_ROSTER := 10
const MAX_ID := 48


## "" when `s` is a valid setup, else the reason.
static func validate(s: Dictionary) -> String:
	if not JoinTicket.valid_match_id(str(s.get("match_id", ""))):
		return "match_id"
	for k in ["mode", "map"]:
		var v := str(s.get(k, ""))
		if v == "" or v.length() > MAX_ID or v.validate_filename() != v:
			return k
	if s.has("rules") and not s.rules is Dictionary:
		return "rules"
	var roster: Variant = s.get("roster", null)
	if not roster is Array or roster.is_empty() or roster.size() > MAX_ROSTER:
		return "roster"
	var seen := {}
	for e: Variant in roster:
		if not e is Dictionary:
			return "roster entry"
		var bot := bool(e.get("bot", false))
		var acc := str(e.get("account", ""))
		if bot != (acc == ""):
			return "roster account"
		if not bot and (not JoinTicket.valid_account(acc) or seen.has(acc)):
			return "roster account"
		seen[acc] = true
		var team: Variant = e.get("team", -1)
		if not (team is int or team is float) or (int(team) != 0 and int(team) != 1):
			return "roster team"
		for k in ["hero", "lane"]:
			if str(e.get(k, "")).length() > MAX_ID:
				return "roster " + k
	return ""


## True when `account_id` is a human player of `s`.
static func has_account(s: Dictionary, account_id: String) -> bool:
	for e: Variant in s.get("roster", []):
		if e is Dictionary and not bool(e.get("bot", false)) and str(e.get("account", "")) == account_id:
			return true
	return false
