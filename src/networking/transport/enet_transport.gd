class_name ENetTransport
extends Transport
## UDP Transport over Godot's ENetConnection (ADR-0002 §4: the M2 transport;
## same interface as LoopbackTransport). Channels 0-1 are sent reliable and
## ordered, 2-3 unreliable sequenced. Gameplay never touches ENet directly.
##
## Peer ids match the loopback convention: the server is always peer 1 and
## remote clients get 2, 3, ... in connection order.
##
## Example:
##   var t := ENetTransport.listen(7777, 16)        # dedicated server
##   var t := ENetTransport.connect_to("1.2.3.4", 7777)  # client
##   DTLS (v0.5): ENetTransport.listen(7777, 16, TLSOptions.server(key, cert)) and
##   ENetTransport.connect_to("cyber.djboeck.at", 7777, TLSOptions.client());
##   `is_secure` says whether the link is encrypted (accounts need it).
##   t.poll() every tick, then pop_packet() as with any Transport.

const SERVER_PEER: int = 1
const DEFAULT_PORT: int = 7777
const CONNECT_TIMEOUT_MS: int = 5000

## A peer connected (server: a client; client: the server).
signal peer_connected(peer_id: int)
## A peer disconnected or timed out.
signal peer_disconnected(peer_id: int)

var _host := ENetConnection.new()
var _is_server: bool = false
var _local_id: int = 0
var _next_id: int = SERVER_PEER + 1
var _id_of: Dictionary = {}  # ENetPacketPeer -> peer id
var _peer_of: Dictionary = {}  # peer id -> ENetPacketPeer
var _ready_q: Array[Transport.Packet] = []
var _outbox: Array = []  # [to_peer, channel, data] queued until the server link is up
var _connected: bool = false
## True when this endpoint runs DTLS (encrypted, server authenticated).
var is_secure: bool = false
## Last error text ("" = fine), for menus and logs.
var error_text: String = ""


## Server endpoint bound to `port` on all interfaces. Check error_text.
## With `tls` (TLSOptions.server) every client must speak DTLS.
static func listen(port: int, max_clients: int, tls: TLSOptions = null) -> ENetTransport:
	var t := ENetTransport.new()
	t._is_server = true
	t._local_id = SERVER_PEER
	var err := t._host.create_host_bound("*", port, max_clients, CHANNEL_COUNT)
	if err != OK:
		t.error_text = "cannot listen on UDP port %d (%s)" % [port, error_string(err)]
		return t
	if tls != null:
		err = t._host.dtls_server_setup(tls)
		if err != OK:
			t.error_text = "cannot start DTLS on UDP port %d (%s)" % [port, error_string(err)]
			return t
		t.is_secure = true
	return t


## Client endpoint connecting to `address:port`. Sends are queued until the
## connection is up. Check error_text / is_connected().
## With `tls` (TLSOptions.client) the link is DTLS; `tls_hostname` is the
## name checked against the certificate ("" = `address`).
static func connect_to(address: String, port: int, tls: TLSOptions = null, tls_hostname: String = "") -> ENetTransport:
	var t := ENetTransport.new()
	var err := t._host.create_host(1, CHANNEL_COUNT)
	if err != OK:
		t.error_text = "cannot create ENet client (%s)" % error_string(err)
		return t
	if tls != null:
		err = t._host.dtls_client_setup(tls_hostname if tls_hostname != "" else address, tls)
		if err != OK:
			t.error_text = "cannot start DTLS (%s)" % error_string(err)
			return t
		t.is_secure = true
	var ip := address
	if not address.is_valid_ip_address():
		ip = IP.resolve_hostname(address, IP.TYPE_IPV4)  # DNS (e.g. cyber.djboeck.at)
		if ip == "":
			t.error_text = "cannot find server %s (DNS lookup failed)" % address
			return t
	var p := t._host.connect_to_host(ip, port, CHANNEL_COUNT)
	if p == null:
		t.error_text = "cannot resolve %s:%d" % [address, port]
		return t
	t._id_of[p] = SERVER_PEER
	t._peer_of[SERVER_PEER] = p
	return t


func get_local_peer_id() -> int:
	return _local_id


func is_server_connected() -> bool:
	return _connected


func send(to_peer: int, channel: int, data: PackedByteArray) -> void:
	if not _is_server and not _connected:
		_outbox.append([to_peer, channel, data])
		return
	var p: ENetPacketPeer = _peer_of.get(to_peer)
	if p == null:
		return
	_count_sent(channel, data.size())
	var flags := ENetPacketPeer.FLAG_RELIABLE if Transport.is_reliable(channel) else 0
	p.send(channel, data, flags)


func poll() -> void:
	while true:
		var ev: Array = _host.service(0)
		var kind: int = ev[0]
		if kind == ENetConnection.EVENT_NONE:
			break
		var p: ENetPacketPeer = ev[1]
		match kind:
			ENetConnection.EVENT_CONNECT:
				_on_connect(p)
			ENetConnection.EVENT_DISCONNECT:
				_on_disconnect(p)
			ENetConnection.EVENT_RECEIVE:
				var id: int = _id_of.get(p, 0)
				var data := p.get_packet()
				if id == 0:
					continue
				var pkt := Transport.Packet.new()
				pkt.from_peer = id
				pkt.channel = ev[3]
				pkt.data = data
				_ready_q.append(pkt)
			ENetConnection.EVENT_ERROR:
				error_text = "network error"
				break
	_host.flush()


func pop_packet() -> Transport.Packet:
	if _ready_q.is_empty():
		return null
	return _ready_q.pop_front()


## Closes every connection (call before quitting).
func close() -> void:
	for p: ENetPacketPeer in _peer_of.values():
		p.peer_disconnect()
	_host.flush()
	_host.destroy()


func _on_connect(p: ENetPacketPeer) -> void:
	if _is_server:
		var id := _next_id
		_next_id += 1
		_id_of[p] = id
		_peer_of[id] = p
		peer_connected.emit(id)
		return
	_connected = true
	_local_id = 0  # assigned by the server's Welcome (own_net_id), not by ENet
	for m: Array in _outbox:
		send(m[0], m[1], m[2])
	_outbox.clear()
	peer_connected.emit(SERVER_PEER)


func _on_disconnect(p: ENetPacketPeer) -> void:
	var id: int = _id_of.get(p, 0)
	_id_of.erase(p)
	_peer_of.erase(id)
	if not _is_server:
		_connected = false
		if error_text == "":
			error_text = "disconnected from server"
	if id != 0:
		peer_disconnected.emit(id)
