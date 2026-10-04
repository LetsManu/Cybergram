class_name LoginRateLimiter
extends RefCounted
## Failed-login limiter per key (an account name or a connection), values
## from AuthRulesDef: more than `max_failures` failures inside `window_s`
## lock the key for `lockout_s`. A success clears the key. Memory only.
##
## Example:
##   var rl := LoginRateLimiter.new(5, 300.0, 300.0)
##   if rl.is_locked("neo", now): refuse()
##   rl.fail("neo", now)

var max_failures: int
var window_s: float
var lockout_s: float
## key -> {fails: Array[float], locked_until: float}
var _keys: Dictionary = {}


func _init(max_failures_: int, window_s_: float, lockout_s_: float) -> void:
	max_failures = max_failures_
	window_s = window_s_
	lockout_s = lockout_s_


func is_locked(key: String, now: float) -> bool:
	var e: Dictionary = _keys.get(key, {})
	return not e.is_empty() and now < float(e.locked_until)


## Records a failure; returns true when the key is now locked.
func fail(key: String, now: float) -> bool:
	var e: Dictionary = _keys.get(key, {})
	if e.is_empty():
		e = {"fails": [], "locked_until": 0.0}
		_keys[key] = e
	var fails: Array = e.fails
	fails.append(now)
	while not fails.is_empty() and now - float(fails[0]) > window_s:
		fails.remove_at(0)
	if fails.size() >= max_failures:
		e.locked_until = now + lockout_s
		fails.clear()
		return true
	return false


func succeed(key: String) -> void:
	_keys.erase(key)


## Drops keys with no recent failures and no active lock (bounded memory).
func purge(now: float) -> void:
	for k in _keys.keys():
		var e: Dictionary = _keys[k]
		var fails: Array = e.fails
		if now >= float(e.locked_until) and (fails.is_empty() or now - float(fails[-1]) > window_s):
			_keys.erase(k)


func size() -> int:
	return _keys.size()
