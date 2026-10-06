class_name NetDiagnosis
extends RefCounted
## Connection test (owner plan 2026-10-06, docs/connecting.md): checks a server
## address step by step and explains each result in plain words with a fix.
## Used by the launcher (Settings > Connection test) and shared with the game
## (launcher/tools/shared_files.txt).
##
## Steps: ADDRESS (a name, or a bare IP that would connect without encryption),
## DNS (the name resolves; private / LAN addresses are pointed out), UDP (the
## server answers on the UDP port) and HANDSHAKE (the encrypted DTLS handshake
## and the certificate's name). UDP and HANDSHAKE come from one verified DTLS
## handshake: a completed handshake proves both; a quick rejection proves UDP
## works and the certificate does not; silence means nothing reached the server.
## A second, unverified handshake then tells "the server speaks DTLS but its
## certificate is not valid for this name" from "something else answered".
## When the server machine answers "port closed" (ICMP), the engine's send
## error is caught (a temporary Logger) and reported as REFUSED.
## Only handshakes are sent: no login, no account data; both are closed at once.
##
## Example:
##   var d := NetDiagnosis.new()
##   var steps := await d.run(get_tree(), "cyber.djboeck.at:7777")
##   for s in steps: print(s.title, ": ", s.detail)

enum State { OK, WARN, FAIL, SKIPPED }
## Outcome of one DTLS handshake attempt.
enum Handshake { CONNECTED, REJECTED, SILENT, REFUSED }

const DEFAULT_PORT: int = 7777
const CHANNELS: int = 2

## One line of the report.
class Step:
	var id: StringName
	var title: String
	var state: int = State.SKIPPED
	var detail: String = ""
	var fix: String = ""

	func _init(id_: StringName, title_: String, state_: int, detail_: String, fix_: String = "") -> void:
		id = id_
		title = title_
		state = state_
		detail = detail_
		fix = fix_

## Collects the engine's error lines during one handshake (any thread).
class _Capture extends Logger:
	var _m := Mutex.new()
	var lines: PackedStringArray = []

	func _log_error(function: String, _file: String, _line: int, code: String, _rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_m.lock()
		lines.append("%s %s" % [function, code])
		_m.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	## True when the engine saw "port closed": a failed send or the DTLS read
	## error that follows an ICMP port-unreachable.
	func refused() -> bool:
		_m.lock()
		var t := "\n".join(lines)
		_m.unlock()
		return t.contains("enet_socket_send") or t.contains("TLS handshake error: -27648")

## Seconds each handshake may take before it counts as silent.
var timeout_s: float = 5.0
## Optional pinned CA / self-signed certificate (self-hosted servers, tests);
## null = the system CA bundle, as the game uses.
var ca: X509Certificate = null
## Each finished step, as it happens (UI progress).
signal step_done(step: Step)


## Splits "host[:port]" (port defaults to DEFAULT_PORT). Pure.
static func split_target(target: String) -> Array:
	var t := target.strip_edges()
	var host := t
	var port := DEFAULT_PORT
	var i := t.rfind(":")
	if i > 0 and t.count(":") == 1:
		host = t.substr(0, i)
		port = int(t.substr(i + 1))
	return [host, port]


## True for RFC 1918 / loopback / link-local IPv4 addresses. Pure.
static func is_private_ipv4(ip: String) -> bool:
	if not ip.is_valid_ip_address() or ip.contains(":"):
		return false
	var p := ip.split(".")
	var a := int(p[0])
	var b := int(p[1])
	return a == 10 or a == 127 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) \
			or (a == 169 and b == 254)


## The ADDRESS step for `host`. Pure.
static func address_step(host: String) -> Step:
	if host.is_valid_ip_address():
		return Step.new(&"address", "Address", State.FAIL,
			"%s is an IP address. With a bare IP the game connects without encryption, and online servers only accept encrypted connections." % host,
			"Use the server name (for example cyber.djboeck.at). On your own network, map that name to the IP in your hosts file (see the guide).")
	return Step.new(&"address", "Address", State.OK, "%s is a server name: the game will connect encrypted (DTLS)." % host)


## The DNS step: `ip` = the resolved address ("" = not found). Pure.
static func dns_step(host: String, ip: String) -> Step:
	if host.is_valid_ip_address():
		return Step.new(&"dns", "Name lookup (DNS)", State.SKIPPED, "No lookup needed for an IP address.")
	if ip == "":
		return Step.new(&"dns", "Name lookup (DNS)", State.FAIL, "%s could not be found." % host,
			"Check your internet connection and the spelling. On your own network, add the name to your hosts file (for example \"192.168.1.7 %s\")." % host)
	if is_private_ipv4(ip):
		return Step.new(&"dns", "Name lookup (DNS)", State.OK,
			"%s -> %s (a local network address: you are on the server's network, or your hosts file maps it)." % [host, ip])
	return Step.new(&"dns", "Name lookup (DNS)", State.OK, "%s -> %s" % [host, ip])


## The UDP and HANDSHAKE steps from the two handshake outcomes. `unsafe` is
## only consulted when the verified handshake was rejected. Pure.
static func handshake_steps(host: String, port: int, verified: int, unsafe: int) -> Array[Step]:
	var out: Array[Step] = []
	if verified == Handshake.SILENT:
		out.append(Step.new(&"udp", "UDP port %d" % port, State.FAIL, "No answer from the server on UDP %d." % port,
			"Check that the server is running, that the router / NAS forwards UDP %d to it (UDP, not TCP), and that no firewall blocks UDP." % port))
		out.append(Step.new(&"handshake", "Encryption and certificate", State.SKIPPED, "Not tested: nothing reached the server."))
		return out
	if verified == Handshake.REFUSED:
		out.append(Step.new(&"udp", "UDP port %d" % port, State.FAIL,
			"The server machine is reachable, but nothing listens on UDP %d there (port closed)." % port,
			"Start the game server, and check that the port mapping (Docker / Portainer / NAS) publishes %d/udp, not only TCP." % port))
		out.append(Step.new(&"handshake", "Encryption and certificate", State.SKIPPED, "Not tested: the port is closed."))
		return out
	out.append(Step.new(&"udp", "UDP port %d" % port, State.OK, "The server answers on UDP %d." % port))
	if verified == Handshake.CONNECTED:
		out.append(Step.new(&"handshake", "Encryption and certificate", State.OK,
			"Encrypted handshake done; the certificate is valid for %s." % host))
	elif unsafe == Handshake.CONNECTED:
		out.append(Step.new(&"handshake", "Encryption and certificate", State.FAIL,
			"The server speaks DTLS, but its certificate is not valid for %s (the name does not match, or it is not from a trusted authority)." % host,
			"Connect with the name the certificate was issued for, or issue the server certificate for %s (for example Let's Encrypt) and restart the server." % host))
	else:
		out.append(Step.new(&"handshake", "Encryption and certificate", State.FAIL,
			"Something answered on UDP %d but no encrypted handshake was possible." % port,
			"Another program may use this port, or the server runs without DTLS. Check the server log and the port mapping."))
	return out


## Runs every step against `target` ("host[:port]"); `tree` drives the waits.
func run(tree: SceneTree, target: String) -> Array[Step]:
	var hp := split_target(target)
	var host: String = hp[0]
	var port: int = hp[1]
	var steps: Array[Step] = []
	steps.append(_done(address_step(host)))
	var ip := host if host.is_valid_ip_address() else IP.resolve_hostname(host, IP.TYPE_IPV4)
	steps.append(_done(dns_step(host, ip)))
	if ip == "":
		return steps
	var verified: int = await _handshake(tree, host, ip, port, false)
	var unsafe: int = Handshake.SILENT
	if verified == Handshake.REJECTED:
		unsafe = await _handshake(tree, host, ip, port, true)
	for s in handshake_steps(host, port, verified, unsafe):
		steps.append(_done(s))
	return steps


func _done(s: Step) -> Step:
	step_done.emit(s)
	return s


## One DTLS handshake to ip:port checking the certificate for `host` (or not,
## with `unsafe`). Closed right after.
func _handshake(tree: SceneTree, host: String, ip: String, port: int, unsafe: bool) -> int:
	var c := ENetConnection.new()
	if c.create_host(1, CHANNELS) != OK:
		return Handshake.SILENT
	var opt := TLSOptions.client_unsafe() if unsafe else (TLSOptions.client(ca) if ca != null else TLSOptions.client())
	if c.dtls_client_setup(host, opt) != OK:
		c.destroy()
		return Handshake.REJECTED
	var peer := c.connect_to_host(ip, port, CHANNELS)
	if peer == null:
		c.destroy()
		return Handshake.SILENT
	var cap := _Capture.new()
	OS.add_logger(cap)
	var result := Handshake.SILENT
	var end_ms := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < end_ms and result == Handshake.SILENT:
		var ev: Array = c.service(0)
		while ev[0] != ENetConnection.EVENT_NONE:
			if ev[0] == ENetConnection.EVENT_CONNECT:
				result = Handshake.CONNECTED
				break
			if ev[0] == ENetConnection.EVENT_ERROR or ev[0] == ENetConnection.EVENT_DISCONNECT:
				result = Handshake.REJECTED
				break
			ev = c.service(0)
		if result == Handshake.SILENT:
			await tree.process_frame
	if result == Handshake.CONNECTED:
		peer.peer_disconnect_now()
	c.flush()
	c.destroy()
	OS.remove_logger(cap)
	if result != Handshake.CONNECTED and cap.refused():
		result = Handshake.REFUSED
	return result
