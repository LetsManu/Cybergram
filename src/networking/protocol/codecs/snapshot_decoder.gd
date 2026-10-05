class_name SnapshotDecoder
extends RefCounted
## W16-NET: client-side snapshot decoder. Resolves each delta against the
## decoded view of its baseline tick and keeps the last `ring_ticks` views.
##
## Example:
##   var dec := SnapshotDecoder.new(net.client_baseline_ticks)
##   var s := dec.decode(bytes)   # null: see last_error

var ring_ticks: int
## OK, ERR_INVALID_DATA (malformed) or ERR_DOES_NOT_EXIST (baseline not held).
var last_error: int = OK
var _views: Dictionary = {}  # tick -> View


func _init(ring: int = 64) -> void:
	ring_ticks = maxi(ring, 1)


func decode(b: PackedByteArray) -> SnapshotData:
	var r := SnapshotCodec.decode_delta(b, _views)
	last_error = r[1]
	if r[1] != OK:
		return null
	var s: SnapshotData = r[0]
	_views[s.tick] = r[2]
	for t in _views.keys():
		if t <= s.tick - ring_ticks:
			_views.erase(t)
	return s


## Forgets every baseline (reconnect).
func reset() -> void:
	_views.clear()
