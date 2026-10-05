class_name SnapshotStats
extends RefCounted
## W16-NET: server-side send statistics for one client connection. Counts every
## packet the server sends to the peer per channel, and per snapshot its size,
## modelled ENet fragment count and whether it broke the byte budget. A window
## (reset by take_window()) feeds the 10 s server log line; lifetime totals feed
## the benchmark. Holds numbers only: no player names or addresses (privacy).
##
## Example:
##   stats.on_send(Transport.CH_SNAPSHOT, bytes.size())
##   stats.on_snapshot(bytes.size(), budget)
##   var w := stats.take_window(10.0)  # {snap_avg, snap_p95, snap_max, pps, kbps[4], frags, ...}

## ENet payload per fragment: default MTU 1392 - protocol header 4 - SEND_FRAGMENT
## command 24 (enet/protocol.c). A larger packet is split, and ENet sends an
## unreliable packet's fragments RELIABLY unless FLAG_UNRELIABLE_FRAGMENT is set.
const ENET_FRAGMENT_PAYLOAD: int = 1364

var _win_sizes: PackedInt32Array = PackedInt32Array()
var _win_bytes: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
var _win_packets: int = 0
var _win_frag_snaps: int = 0
var _win_over: int = 0
## Lifetime totals.
var total_bytes: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
var total_packets: int = 0
var snapshots: int = 0
var snapshot_bytes: int = 0
## Snapshots that needed more than one ENet fragment.
var fragmented_snapshots: int = 0
## Snapshots larger than the configured budget.
var over_budget: int = 0
## Delta snapshots (encoded against an acknowledged baseline) vs full ones.
var delta_snapshots: int = 0
## Wardling updates deferred by the priority accumulator (step 3).
var deferred_updates: int = 0
## Benchmarks: keep every snapshot size in `history`.
var keep_history: bool = false
var history: PackedInt32Array = PackedInt32Array()


## ENet fragments a packet of `size` bytes is sent as (1 = not fragmented).
static func fragments_for(size: int) -> int:
	return 1 if size <= ENET_FRAGMENT_PAYLOAD else ceili(size / float(ENET_FRAGMENT_PAYLOAD))


## Any packet sent to the peer.
func on_send(channel: int, size: int) -> void:
	if channel < 0 or channel >= _win_bytes.size():
		return
	_win_bytes[channel] += size
	total_bytes[channel] += size
	_win_packets += 1
	total_packets += 1


## A snapshot of `size` bytes (call in addition to on_send).
func on_snapshot(size: int, budget: int, is_delta: bool = false, deferred: int = 0) -> void:
	_win_sizes.append(size)
	if keep_history:
		history.append(size)
	snapshots += 1
	snapshot_bytes += size
	if fragments_for(size) > 1:
		_win_frag_snaps += 1
		fragmented_snapshots += 1
	if budget > 0 and size > budget:
		_win_over += 1
		over_budget += 1
	if is_delta:
		delta_snapshots += 1
	deferred_updates += deferred


## Percentile `q` (0..1) of `values` (nearest rank; 0 when empty).
static func percentile(values: PackedInt32Array, q: float) -> int:
	if values.is_empty():
		return 0
	var s := values.duplicate()
	s.sort()
	return s[clampi(ceili(q * s.size()) - 1, 0, s.size() - 1)]


## Summary of the window covering `seconds`, then starts a new window.
func take_window(seconds: float) -> Dictionary:
	var sec := maxf(seconds, 0.001)
	var sum := 0
	var mx := 0
	for v in _win_sizes:
		sum += v
		mx = maxi(mx, v)
	var kbps := []
	for ch in _win_bytes.size():
		kbps.append(_win_bytes[ch] / sec / 1000.0)
	var out := {
		"snaps": _win_sizes.size(),
		"snap_avg": float(sum) / maxi(_win_sizes.size(), 1),
		"snap_p95": percentile(_win_sizes, 0.95),
		"snap_max": mx,
		"pps": _win_packets / sec,
		"kbps": kbps,
		"frag_snaps": _win_frag_snaps,
		"over_budget": _win_over,
	}
	_win_sizes.clear()
	_win_bytes = PackedInt64Array([0, 0, 0, 0])
	_win_packets = 0
	_win_frag_snaps = 0
	_win_over = 0
	return out


## The compact log line for one window (`peer` is the transport peer id, never
## a name). `link` is Transport.peer_stats() ({} when unknown).
static func format_line(peer: int, w: Dictionary, link: Dictionary) -> String:
	var k: Array = w.kbps
	var t := "[net] peer=%d snap avg=%dB p95=%dB max=%dB n=%d frag=%d over=%d | pps=%.1f kB/s c0=%.2f c1=%.2f c2=%.2f c3=%.2f" % [
		peer, roundi(w.snap_avg), w.snap_p95, w.snap_max, w.snaps, w.frag_snaps, w.over_budget, w.pps,
		k[0], k[1], k[2], k[3]]
	if link.has("rtt_ms"):
		t += " | rtt=%dms var=%dms loss=%.1f%%" % [link.rtt_ms, link.get("rtt_var_ms", 0), link.get("loss_pct", 0.0)]
	return t
