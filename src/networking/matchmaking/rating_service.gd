class_name RatingService
extends RefCounted
## Applies match results to ratings (W17-MM, design/gdd/matchmaking.md
## "Rating and ranks"). One rating per account per track; Glicko2 does the
## math; a RatingStore keeps the entries.
##
## Team update (one match = one rating period, every player one term):
##   mu_T  = mean mu of the player's team, mu_O = mean mu of the other team
##   phi_O = sqrt(mean phi^2 of the other team)   (the composite opponent)
##   E     = 1 / (1 + exp(-g(phi_O) (mu_T - mu_O)))  — the same for a team
##   then Glicko2.update() with the player's OWN mu, phi and sigma, so each
##   change is scaled by the player's own deviation (phi'^2): new or
##   uncertain players move fast, settled players slowly.
## The deviation never drops below rules.deviation_min.
##
## Worked example (tests/unit/matchmaking/rating_service_test.gd): team A
## 1500/350, 1600/80, 1400/200, 1550/120, 1450/300 beats team B 1520/100,
## 1480/150, 1500/90, 1510/200, 1490/60 -> A1 1674.64 (RD 256.17),
## A2 1616.56 (78.88); B5 1481.59 (60.30).
##
## Special results:
## - Void / remake (voided = true): nothing changes, games do not count.
## - Leaver (rule chosen for W17-MM): the leaver is rated as a loss even if
##   the team won, then loses rules.leaver_penalty more points. Teammates who
##   lost lose only rules.leaver_teammate_loss_scale of their normal loss
##   (their deviation and volatility update normally); if they won, they gain
##   normally. The other team is rated normally. Lockouts are separate
##   (LockoutTracker).
## - Bots: a match with a bot changes nothing unless rules.rate_bot_matches;
##   then a bot counts as bot_rating / deviation_min and is never stored.
## - Ranked pick-phase dodge: minus rules.dodge_rating_penalty, no game.
##
## Visible rank (ranked track only): hidden (-1) until calibration_games are
## played, then round(rating) and its medal band.

const TRACK_RANKED: StringName = &"ranked"
const ROMAN: Array[String] = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

var store: RatingStore
var rules: MatchmakingRulesDef


func _init(store_: RatingStore, rules_: MatchmakingRulesDef = null) -> void:
	store = store_
	rules = rules_ if rules_ != null else MatchmakingRulesDef.load_default()


## The stored entry, or a fresh one with the initial values.
func entry(account_id: String, track: StringName) -> Dictionary:
	var e := store.get_entry(account_id, track)
	if e.is_empty():
		e = {"rating": rules.rating_initial, "rd": rules.deviation_initial,
			"vol": rules.volatility_initial, "games": 0, "updated_at": 0}
	return e


## Applies one match. `winner` 0 = team_a won, 1 = team_b won. Returns
## {account id: {before: float, after: float, delta: float}}; empty when
## nothing changed (void, unrated bot match, no track).
func apply_result(track: StringName, team_a: Array, team_b: Array, winner: int, now_unix: int,
		leavers: Array = [], voided: bool = false) -> Dictionary:
	if voided or String(track) == "" or team_a.is_empty() or team_b.is_empty():
		return {}
	if not rules.rate_bot_matches and (_has_bot(team_a) or _has_bot(team_b)):
		return {}
	var a := _load(team_a, track)
	var b := _load(team_b, track)
	var out := {}
	_rate_team(a, b, 1.0 if winner == 0 else 0.0, leavers, track, now_unix, out)
	_rate_team(b, a, 1.0 if winner == 1 else 0.0, leavers, track, now_unix, out)
	return out


## Ranked dodge in the pick phase: a flat loss, no game counted.
func apply_dodge_penalty(account_id: String, track: StringName, now_unix: int) -> float:
	var e := entry(account_id, track)
	var before: float = e.rating
	e.rating = before - rules.dodge_rating_penalty
	e.updated_at = now_unix
	store.put_entry(account_id, track, e)
	return e.rating - before


## Ranked games still needed before the number shows (0 = calibrated).
func calibration_left(account_id: String) -> int:
	return maxi(0, rules.calibration_games - int(entry(account_id, TRACK_RANKED).games))


## The visible ranked number, or -1 while calibrating.
func visible_rating(account_id: String) -> int:
	if calibration_left(account_id) > 0:
		return -1
	return roundi(float(entry(account_id, TRACK_RANKED).rating))


## What the client shows for ranked: {calibrating: bool, games_left: int,
## rating: int (-1 hidden), medal: {} or medal_for()}.
func ranked_display(account_id: String) -> Dictionary:
	var v := visible_rating(account_id)
	return {"calibrating": v < 0, "games_left": calibration_left(account_id), "rating": v,
		"medal": {} if v < 0 else medal_for(v)}


## Medal band of a visible rating: {band: int, name: String, division: int
## (1 = lowest), label: "Silver III"}. Divisions split a band into steps
## of rules.medal_division_span, clamped to the band's division count.
func medal_for(rating: float) -> Dictionary:
	var idx := 0
	for i in rules.medal_bands.size():
		if rating >= float(rules.medal_bands[i].get("min", 0.0)):
			idx = i
	var band: Dictionary = rules.medal_bands[idx]
	var divisions := maxi(1, int(band.get("divisions", 1)))
	var div := clampi(int(floor((rating - float(band.get("min", 0.0))) / rules.medal_division_span)) + 1, 1, divisions)
	var label: String = band.get("name", "")
	if divisions > 1:
		label += " " + ROMAN[mini(div, ROMAN.size()) - 1]
	return {"band": idx, "name": band.get("name", ""), "division": div, "label": label}


func _has_bot(team: Array) -> bool:
	for id in team:
		if MatchmakingRulesDef.is_bot(String(id)):
			return true
	return false


func _load(team: Array, track: StringName) -> Array:
	var out: Array = []
	for id in team:
		var sid := String(id)
		if MatchmakingRulesDef.is_bot(sid):
			out.append({"id": sid, "bot": true, "e": {"rating": rules.bot_rating, "rd": rules.deviation_min,
				"vol": rules.volatility_initial, "games": 0, "updated_at": 0}})
		else:
			out.append({"id": sid, "bot": false, "e": entry(sid, track)})
	return out


func _rate_team(team: Array, other: Array, score: float, leavers: Array, track: StringName, now_unix: int,
		out: Dictionary) -> void:
	var mu_t := 0.0
	for p in team:
		mu_t += Glicko2.to_mu(p.e.rating)
	mu_t /= team.size()
	var mu_o := 0.0
	var phi2_o := 0.0
	for p in other:
		mu_o += Glicko2.to_mu(p.e.rating)
		phi2_o += pow(Glicko2.to_phi(p.e.rd), 2)
	mu_o /= other.size()
	var g_o := Glicko2.g(sqrt(phi2_o / other.size()))
	var e_t := Glicko2.expected(mu_t, mu_o, g_o)
	var team_has_leaver := false
	for p in team:
		if leavers.has(p.id):
			team_has_leaver = true
	for p in team:
		if p.bot:
			continue
		var left: bool = leavers.has(p.id)
		var s := 0.0 if left else score
		var r := Glicko2.update(p.e.rating, p.e.rd, p.e.vol, [{"g": g_o, "e": e_t, "s": s}], rules.tau)
		var before: float = p.e.rating
		var after: float = r.rating
		if left:
			after -= rules.leaver_penalty
		elif team_has_leaver and s == 0.0:
			after = before + (after - before) * rules.leaver_teammate_loss_scale
		var e := {"rating": after, "rd": maxf(rules.deviation_min, r.rd), "vol": r.vol,
			"games": int(p.e.games) + 1, "updated_at": now_unix}
		store.put_entry(p.id, track, e)
		out[p.id] = {"before": before, "after": after, "delta": after - before}
