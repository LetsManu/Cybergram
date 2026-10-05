class_name NetSimConditioner
extends RefCounted
## Adds latency, jitter and loss to packets (architecture.md §8.8).
## Deterministic: all randomness comes from a seeded RandomNumberGenerator.
## Reliable channels are delayed and kept in order but never dropped.
##
## Example:
##   var cond := NetSimConditioner.new(profile)
##   var at := cond.schedule(now_usec, Transport.CH_INPUT, route_key)  # -1 = dropped

var profile: NetSimProfile
var dropped: int = 0
var _rng := RandomNumberGenerator.new()
var _last_reliable_at: Dictionary = {}  # route key -> usec


func _init(p: NetSimProfile) -> void:
	profile = p if p != null else NetSimProfile.new()
	_rng.seed = profile.seed


## Returns the delivery time in usec, or -1 if the packet is lost.
## `route_key` identifies a (from, to) pair so reliable order is per route.
func schedule(now_usec: int, channel: int, route_key: int) -> int:
	var reliable := Transport.is_reliable(channel)
	if not reliable and profile.loss > 0.0 and _rng.randf() < profile.loss:
		dropped += 1
		return -1
	var delay_ms := profile.one_way_latency_ms
	if profile.jitter_ms > 0:
		delay_ms += _rng.randi_range(0, profile.jitter_ms)
	var at := now_usec + delay_ms * 1000
	if reliable:
		at = maxi(at, int(_last_reliable_at.get(route_key, 0)))
		_last_reliable_at[route_key] = at
	return at
