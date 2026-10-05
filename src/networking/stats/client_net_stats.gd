class_name ClientNetStats
extends RefCounted
## W16-NET: client-side link statistics for the net graph and the adaptive
## interpolation delay. Fed by ClientSession with a monotonic clock in usec
## (injected, so tests drive it deterministically).
##
## - Jitter: each snapshot's arrival offset (arrival - tick * tick length); the
##   lateness of a snapshot is its offset minus the smallest offset in the
##   window. jitter_p95_ms() is the 95th percentile of that lateness, i.e. how
##   much later than the best case a snapshot typically lands (poll granularity
##   included, which is what the interpolation buffer actually sees).
## - Loss: snapshot ticks missing between consecutive received ticks (the
##   server sends one snapshot per tick).
## - Rates: bytes in (all channels / snapshots only) and out over the last second.

## Arrival samples kept for jitter (90 = 3 s at 30 Hz).
var window: int = 90
var tick_usec: float = 1_000_000.0 / 30.0
var _offsets: PackedInt64Array = PackedInt64Array()
var _ticks_seen: PackedInt32Array = PackedInt32Array()  # 1 = received, 0 = missed (per tick slot)
var _last_tick: int = -1
var _sizes: PackedInt32Array = PackedInt32Array()
## Rate buckets: [start_usec, in_bytes, snap_bytes, out_bytes] for this and the last second.
var _bucket_start: int = -1
var _cur := PackedInt64Array([0, 0, 0])
var _last := PackedInt64Array([0, 0, 0])
var _last_span_s: float = 1.0
## Totals.
var bytes_in: int = 0
var bytes_out: int = 0
var snapshots: int = 0
var snapshots_missed: int = 0
## Delta snapshots that referenced a baseline this client no longer has.
var baseline_misses: int = 0


func _init(tick_rate_hz: int = 30, window_samples: int = 90) -> void:
	tick_usec = 1_000_000.0 / maxi(tick_rate_hz, 1)
	window = maxi(window_samples, 4)


## Any packet received.
func on_in(size: int, now_usec: int) -> void:
	_roll(now_usec)
	_cur[0] += size
	bytes_in += size


## Any packet sent.
func on_out(size: int, now_usec: int) -> void:
	_roll(now_usec)
	_cur[2] += size
	bytes_out += size


## A decoded, in-order snapshot of `size` bytes for server `tick`.
func on_snapshot(tick: int, size: int, now_usec: int) -> void:
	_roll(now_usec)
	_cur[1] += size
	snapshots += 1
	_sizes.append(size)
	if _sizes.size() > window:
		_sizes.remove_at(0)
	_offsets.append(now_usec - roundi(tick * tick_usec))
	if _offsets.size() > window:
		_offsets.remove_at(0)
	if _last_tick >= 0 and tick > _last_tick:
		var gap := mini(tick - _last_tick - 1, window)
		snapshots_missed += tick - _last_tick - 1
		for i in gap:
			_ticks_seen.append(0)
	_ticks_seen.append(1)
	while _ticks_seen.size() > window:
		_ticks_seen.remove_at(0)
	_last_tick = tick


## 95th-percentile snapshot lateness in ms over the window (0 with < 2 samples).
func jitter_p95_ms() -> float:
	return _lateness_percentile(0.95)


## Mean snapshot lateness in ms (a smoother "jitter" figure for display).
func jitter_mean_ms() -> float:
	if _offsets.size() < 2:
		return 0.0
	var mn := _offsets[0]
	for o in _offsets:
		mn = mini(mn, o)
	var sum := 0
	for o in _offsets:
		sum += o - mn
	return sum / float(_offsets.size()) / 1000.0


func _lateness_percentile(q: float) -> float:
	if _offsets.size() < 2:
		return 0.0
	var mn := _offsets[0]
	for o in _offsets:
		mn = mini(mn, o)
	var late := PackedInt64Array()
	for o in _offsets:
		late.append(o - mn)
	late.sort()
	return late[clampi(ceili(q * late.size()) - 1, 0, late.size() - 1)] / 1000.0


## Snapshot loss over the window, 0..100.
func loss_pct() -> float:
	if _ticks_seen.is_empty():
		return 0.0
	var miss := 0
	for v in _ticks_seen:
		if v == 0:
			miss += 1
	return 100.0 * miss / _ticks_seen.size()


## Mean snapshot size (bytes) over the window.
func snapshot_avg_bytes() -> float:
	if _sizes.is_empty():
		return 0.0
	var s := 0
	for v in _sizes:
		s += v
	return float(s) / _sizes.size()


## Snapshot sizes in the window, oldest first (net graph history).
func sizes() -> PackedInt32Array:
	return _sizes


## Largest snapshot (bytes) in the window.
func snapshot_max_bytes() -> int:
	var m := 0
	for v in _sizes:
		m = maxi(m, v)
	return m


## kB/s received (all channels) over the last full second.
func kbps_in() -> float:
	return _last[0] / _last_span_s / 1000.0


## kB/s of snapshots received over the last full second.
func kbps_snapshots() -> float:
	return _last[1] / _last_span_s / 1000.0


## kB/s sent over the last full second.
func kbps_out() -> float:
	return _last[2] / _last_span_s / 1000.0


func _roll(now_usec: int) -> void:
	if _bucket_start < 0:
		_bucket_start = now_usec
		return
	var span := now_usec - _bucket_start
	if span < 1_000_000:
		return
	_last = _cur
	_last_span_s = span / 1_000_000.0
	_cur = PackedInt64Array([0, 0, 0])
	_bucket_start = now_usec
