class_name Transport
extends RefCounted
## Abstract packet transport (ADR-0002 §4, architecture.md §8.1).
## Implementations: LoopbackTransport (in-memory, M1) and ENetTransport (M2).
## Gameplay never uses @rpc; every message is a byte packet on one of 4 channels.
##
## Example:
##   transport.send(peer_id, Transport.CH_INPUT, bytes)
##   transport.poll()
##   var pkt := transport.pop_packet()
##   while pkt != null: handle(pkt); pkt = transport.pop_packet()

const CH_CONTROL: int = 0   ## reliable: handshake, Reject, Kick
const CH_EVENTS: int = 1    ## reliable: gameplay events and commands
const CH_SNAPSHOT: int = 2  ## unreliable: snapshots
const CH_INPUT: int = 3     ## unreliable: input batches
const CHANNEL_COUNT: int = 4

## A received packet.
class Packet:
	var from_peer: int
	var channel: int
	var data: PackedByteArray

## Bytes sent per channel (bandwidth tracking, network-code rule).
var bytes_sent: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
## Packets sent per channel.
var packets_sent: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])


## Channels 0 and 1 are reliable and ordered; 2 and 3 are unreliable.
static func is_reliable(channel: int) -> bool:
	return channel == CH_CONTROL or channel == CH_EVENTS


## This endpoint's peer id.
func get_local_peer_id() -> int:
	push_error("Transport.get_local_peer_id is abstract")
	return 0


## Queues `data` for `to_peer` on `channel`.
func send(_to_peer: int, _channel: int, _data: PackedByteArray) -> void:
	push_error("Transport.send is abstract")


## Moves packets that have arrived into the receive queue.
## Remote IP address of `peer` ("" when unknown or not IP based). Server
## side, used only in memory for login rate limits (never logged or stored).
func peer_address(_peer: int) -> String:
	return ""


func poll() -> void:
	push_error("Transport.poll is abstract")


## Next received packet, or null.
func pop_packet() -> Packet:
	push_error("Transport.pop_packet is abstract")
	return null


func _count_sent(channel: int, size: int) -> void:
	bytes_sent[channel] += size
	packets_sent[channel] += 1
