extends RefCounted
## In-memory loopback "network" for the W17-SUP tests: one server channel
## (supervisor side) and any number of client links (match-process side).

class ServerEnd:
	var links: Dictionary  # shared with the owner (no back reference: no cycle)
	var inbox: Array = []
	func poll() -> Array:
		var out := inbox
		inbox = []
		return out
	func send_to(_ip: String, port: int, data: PackedByteArray) -> void:
		if links.has(port):
			links[port].inbox.append(data)
	func local_port() -> int:
		return 9999


class ClientEnd:
	var server: ServerEnd
	var port: int
	var inbox: Array = []
	var muted: bool = false
	func send(data: PackedByteArray) -> void:
		if not muted:
			server.inbox.append({"data": data, "ip": "127.0.0.1", "port": port})
	func poll() -> Array:
		var out := inbox
		inbox = []
		return out


var server := ServerEnd.new()
var links: Dictionary = {}  # port -> ClientEnd
var _next_port: int = 40000


func _init() -> void:
	server.links = links


func new_link() -> ClientEnd:
	var c := ClientEnd.new()
	c.server = server
	c.port = _next_port
	_next_port += 1
	links[c.port] = c
	return c
