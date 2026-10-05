class_name LockoutTracker
extends RefCounted
## Queue lockouts with escalation and decay (W17-MM, design "Ready check" /
## "Leaver penalty"). Two kinds of strike per account:
## - DECLINE: declining or missing a ready check, or dodging the pick phase.
##   Locks every matchmade queue for decline_lockout_steps_s[strikes - 1].
## - LEAVE: abandoning a running match. Locks the ranked queue for
##   leaver_lockout_steps_s[strikes - 1].
## The last step repeats. One strike decays every *_strike_decay_s without a
## new strike of that kind (strikes never go below 0).
## Memory only; to_dict()/from_dict() let the front keep it across restarts.
## Time is injected (`now` in seconds).

enum Kind { DECLINE, LEAVE }

var rules: MatchmakingRulesDef
var _state: Dictionary = {}  # account id -> {Kind (int): {strikes, since, until}}


func _init(rules_: MatchmakingRulesDef = null) -> void:
	rules = rules_ if rules_ != null else MatchmakingRulesDef.load_default()


## Records a strike; returns the lockout it starts (seconds).
func record(account_id: String, kind: Kind, now: float) -> float:
	var st := _state_of(account_id, kind, now)
	st.strikes += 1
	st.since = now
	var steps := _steps(kind)
	var secs: float = steps[mini(st.strikes, steps.size()) - 1]
	st.until = maxf(float(st.until), now + secs)
	return secs


## Strikes after decay.
func strikes(account_id: String, kind: Kind, now: float) -> int:
	return int(_state_of(account_id, kind, now).strikes)


## Time the account may queue again (0 = free). `ranked` adds LEAVE locks.
func locked_until(account_id: String, now: float, ranked: bool = false) -> float:
	var until := float(_state_of(account_id, Kind.DECLINE, now).until)
	if ranked:
		until = maxf(until, float(_state_of(account_id, Kind.LEAVE, now).until))
	return until if until > now else 0.0


func is_locked(account_id: String, now: float, ranked: bool = false) -> bool:
	return locked_until(account_id, now, ranked) > 0.0


## Forgets accounts with no strikes and no running lockout.
func sweep(now: float) -> void:
	for id in _state.keys():
		var keep := false
		for k in [Kind.DECLINE, Kind.LEAVE]:
			var st := _state_of(id, k, now)
			if st.strikes > 0 or float(st.until) > now:
				keep = true
		if not keep:
			_state.erase(id)


func to_dict() -> Dictionary:
	return _state.duplicate(true)


func from_dict(d: Dictionary) -> void:
	_state = d.duplicate(true)


func _steps(kind: Kind) -> PackedFloat32Array:
	return rules.decline_lockout_steps_s if kind == Kind.DECLINE else rules.leaver_lockout_steps_s


func _decay_s(kind: Kind) -> float:
	return rules.decline_strike_decay_s if kind == Kind.DECLINE else rules.leaver_strike_decay_s


func _state_of(account_id: String, kind: Kind, now: float) -> Dictionary:
	var per: Dictionary = _state.get_or_add(account_id, {})
	var st: Dictionary = per.get_or_add(kind, {"strikes": 0, "since": now, "until": 0.0})
	var decay := _decay_s(kind)
	if st.strikes > 0:
		var n := int(floor((now - float(st.since)) / decay))
		if n > 0:
			st.strikes = maxi(0, int(st.strikes) - n)
			st.since = float(st.since) + n * decay
	else:
		st.since = now
	return st
