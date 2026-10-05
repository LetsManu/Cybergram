class_name SnapshotEncoder
extends RefCounted
## W16-NET: server-side snapshot encoder for ONE client. Keeps the views it
## sent (tick -> SnapshotCodec.View) for `ring_ticks`, encodes each snapshot as
## a delta against the newest one the client acknowledged, and falls back to
## full state when that baseline is missing or too old. Enforces the byte
## budget; `prioritiser` (optional, step 3) orders the Wardling updates.
##
## Example:
##   var enc := SnapshotEncoder.new(net.delta_baseline_ticks, net.snapshot_budget_bytes)
##   var bytes := enc.encode(snap, client.ack_snapshot_tick)

var ring_ticks: int
var budget: int
## Optional object with `order(s: SnapshotData, view: SnapshotCodec.View, tick: int) -> Array`
## and `sent(keys: Array[int], tick: int)` (WardlingPrioritiser).
var prioritiser: Object = null
var _views: Dictionary = {}  # tick -> View
## Diagnostics of the last encode().
var last: SnapshotCodec.Encoded


func _init(ring: int = 32, budget_bytes: int = 1100) -> void:
	ring_ticks = maxi(ring, 1)
	budget = budget_bytes


## The baseline used for an ack of `ack_tick` at `tick` (null = full state).
func baseline_for(ack_tick: int, tick: int) -> SnapshotCodec.View:
	if ack_tick <= 0 or ack_tick >= tick or tick - ack_tick > ring_ticks:
		return null
	return _views.get(ack_tick)


## `cache`: see SnapshotCodec.encode_delta (shared per tick between clients).
func encode(s: SnapshotData, ack_tick: int, cache: Dictionary = {}) -> PackedByteArray:
	var base := baseline_for(ack_tick, s.tick)
	var order: Variant = null
	if prioritiser != null:
		order = prioritiser.call("order", s, base, s.tick)
	last = SnapshotCodec.encode_delta(s, base, budget, order, cache)
	if prioritiser != null:
		prioritiser.call("sent", last.fresh, s.tick)
	_views[s.tick] = last.view
	for t in _views.keys():
		if t <= s.tick - ring_ticks:
			_views.erase(t)
	return last.bytes


## Baselines held (tests).
func held_ticks() -> Array:
	var k := _views.keys()
	k.sort()
	return k
