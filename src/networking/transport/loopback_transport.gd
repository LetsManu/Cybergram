class_name LoopbackTransport
extends Transport
## In-memory Transport endpoint (ADR-0002). Created by LoopbackLink; packets go
## through the link's NetSimConditioner. Same interface as the future ENetTransport.

var _link: LoopbackLink
var _peer_id: int
var _pending: Array = []  # [deliver_at, order, Packet], sorted by (deliver_at, order)
var _ready: Array[Transport.Packet] = []
var _order: int = 0


func _init(link: LoopbackLink, peer_id: int) -> void:
	_link = link
	_peer_id = peer_id


func get_local_peer_id() -> int:
	return _peer_id


func send(to_peer: int, channel: int, data: PackedByteArray) -> void:
	_count_sent(channel, data.size())
	_link._route(_peer_id, to_peer, channel, data)


func poll() -> void:
	var due := 0
	while due < _pending.size() and _pending[due][0] <= _link.now_usec:
		_ready.append(_pending[due][2])
		due += 1
	if due > 0:
		_pending = _pending.slice(due)


func pop_packet() -> Transport.Packet:
	if _ready.is_empty():
		return null
	return _ready.pop_front()


## Packets in flight towards this endpoint (tests/diagnostics).
func pending_count() -> int:
	return _pending.size()


func _enqueue(at: int, from_peer: int, channel: int, data: PackedByteArray) -> void:
	var pkt := Transport.Packet.new()
	pkt.from_peer = from_peer
	pkt.channel = channel
	pkt.data = data
	var entry := [at, _order, pkt]
	_order += 1
	var i := _pending.size()
	while i > 0 and _pending[i - 1][0] > at:
		i -= 1
	_pending.insert(i, entry)
