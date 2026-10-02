class_name LoopbackLink
extends RefCounted
## In-memory "network" joining LoopbackTransport endpoints in one process
## (OFFLINE mode, tests). Owns the simulated clock and the conditioner, so time
## only moves when advance() is called: no wall-clock reads (architecture.md §1.6).
##
## Example:
##   var link := LoopbackLink.new(profile)
##   var server := link.create_endpoint(1)
##   var client := link.create_endpoint(2)
##   client.send(1, Transport.CH_CONTROL, hello); link.advance(dt); server.poll()

var conditioner: NetSimConditioner
var now_usec: int = 0
var _endpoints: Dictionary = {}  # peer id -> LoopbackTransport


func _init(profile: NetSimProfile = null) -> void:
	conditioner = NetSimConditioner.new(profile)


## Creates an endpoint with `peer_id` (1 = server by convention).
func create_endpoint(peer_id: int) -> LoopbackTransport:
	var ep := LoopbackTransport.new(self, peer_id)
	_endpoints[peer_id] = ep
	return ep


## Advances simulated time.
func advance(dt_sec: float) -> void:
	now_usec += roundi(dt_sec * 1_000_000.0)


func _route(from_peer: int, to_peer: int, channel: int, data: PackedByteArray) -> void:
	var target: LoopbackTransport = _endpoints.get(to_peer)
	if target == null:
		return
	var at := conditioner.schedule(now_usec, channel, (from_peer << 16) | to_peer)
	if at < 0:
		return
	target._enqueue(at, from_peer, channel, data.duplicate())
