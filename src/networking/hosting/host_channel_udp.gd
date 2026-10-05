class_name HostChannelUdp
extends RefCounted
## Loopback UDP endpoint for the supervisor <-> match-process channel (W17).
## Server side (supervisor): open_server(0) binds 127.0.0.1 on a free port.
## Client side (match process): open_client(port) sends to 127.0.0.1:port.
## Datagrams from any other address are dropped. Same API as the in-memory
## fake used by the tests: poll() -> [{data, ip, port}], send_to(), send().

const LOOPBACK := "127.0.0.1"

var _udp := PacketPeerUDP.new()
var _client := false


func open_server(port: int = 0) -> Error:
	return _udp.bind(port, LOOPBACK)


func open_client(server_port: int) -> Error:
	_client = true
	var err := _udp.bind(0, LOOPBACK)
	if err != OK:
		return err
	_udp.set_dest_address(LOOPBACK, server_port)
	return OK


func local_port() -> int:
	return _udp.get_local_port()


func poll() -> Array:
	var out: Array = []
	while _udp.get_available_packet_count() > 0:
		var data := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		if ip == LOOPBACK or ip == "::ffff:127.0.0.1":
			out.append({"data": data, "ip": ip, "port": _udp.get_packet_port()})
	return out


## Server side: answer a sender.
func send_to(ip: String, port: int, data: PackedByteArray) -> void:
	_udp.set_dest_address(ip, port)
	_udp.put_packet(data)


## Client side: to the supervisor.
func send(data: PackedByteArray) -> void:
	_udp.put_packet(data)


func close() -> void:
	_udp.close()
