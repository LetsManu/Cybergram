class_name MatchmakingScriptClient
extends Node
## Headless scripted matchmaking client for smoke tests and the container e2e
## (W17B, `--mm-script-client <scenario> --connect host[:port] --user <name>`).
## Logs in as a guest on the front, queues Normal, accepts the ready check,
## never picks (the draft timeout auto-picks), joins the match process with
## its ticket (the GameSession becomes a normal remote client), and waits
## for the front's verdict:
##   win    exit 0 on MATCH_RESULT ("[mm-client] result ...")
##   crash  exit 0 on a void ("[mm-client] voided"), e.g. after the match
##          process was killed
## Exit 1 on a failure or after `timeout_s`. Log lines carry no personal data.

const TIMEOUT_S := 600.0

## The GameSession that runs the match client once a ticket arrives.
var session: Node
var scenario: String = "win"
var user: String = "script"
var address: String = "127.0.0.1"
var port: int = 7777
var timeout_s: float = TIMEOUT_S
var enet: ENetTransport
var lobby: LobbyClient
var _elapsed: float = 0.0
var _done: bool = false
var _logged_in: bool = false


func _ready() -> void:
	enet = ENetTransport.connect_to(address, port, AuthConfig.from_os().client_tls_for(address))
	lobby = LobbyClient.new(enet, address)
	var mm := lobby.matchmaking
	lobby.account_result.connect(_on_account)
	lobby.failed.connect(func(reason: String) -> void: _finish(1, "rejected: %s" % reason))
	mm.queue_detail.connect(func(s: Dictionary) -> void:
		if int(s.code) != MatchmakingCodec.OK:
			_finish(1, "queue refused (code %d)" % int(s.code)))
	mm.ready_check.connect(func(_d: float) -> void:
		if not mm.last_ready.get("you_accepted", 0):
			print("[mm-client] match found: accepting")
			mm.ready_accept())
	mm.draft_state.connect(func(st: Dictionary) -> void:
		print("[mm-client] pick state: turn %d, %d s left (not picking: timeout auto-pick)" % [int(st.turn), int(st.seconds)]))
	mm.ready_result.connect(_on_ready_result)
	mm.match_assigned.connect(_on_assigned)
	mm.match_result.connect(func(r: Dictionary) -> void:
		_finish(0, "result won=%d voided=%d rated=%d delta=%.1f duration=%d" % [int(r.won), int(r.voided),
			int(r.rated), float(r.delta), int(r.duration)]))
	print("[mm-client] scenario %s: connecting to %s:%d" % [scenario, address, port])


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	lobby.step()
	if not _logged_in and enet.is_server_connected() and lobby.session.is_empty() and _elapsed > 0.2:
		_logged_in = true
		lobby.request(AccountCodec.OP_GUEST, {"ver": MsgType.PROTOCOL_VERSION, "display_name": user, "emblem": 0,
			"accent": 0, "flags": AccountCodec.FLAG_PRIVACY})
	if enet.error_text != "":
		_finish(1, "front connection failed")
	elif _elapsed > timeout_s:
		_finish(1, "timeout after %.0f s" % timeout_s)


func _on_account(d: Dictionary) -> void:
	if int(d.op) != AccountCodec.OP_GUEST:
		return
	if int(d.code) != AccountCodec.OK:
		_finish(1, "guest login refused (code %d)" % int(d.code))
		return
	print("[mm-client] logged in as guest; queueing normal_5v5")
	lobby.matchmaking.queue_join(&"normal_5v5", [&"fill"])


func _on_ready_result(r: Dictionary) -> void:
	match int(r.outcome):
		MatchmakingCodec.RR_GO:
			print("[mm-client] everyone accepted: pick phase")
		MatchmakingCodec.RR_VOIDED:
			if scenario == "crash":
				_finish(0, "voided")
			else:
				_finish(1, "voided")
		_:
			print("[mm-client] ready check ended (outcome %d)" % int(r.outcome))


func _on_assigned(host: String, match_port: int, ticket: String) -> void:
	var a: Dictionary = lobby.matchmaking.last_assigned
	print("[mm-client] match assigned: %s:%d, team %d, hero %d" % [host, match_port, int(a.team), int(a.hero)])
	if session != null and session.has_method("join_matchmade"):
		session.join_matchmade(host, match_port, ticket, int(a.hero), str(a.get("map", "")))


func _finish(code: int, what: String) -> void:
	if _done:
		return
	_done = true
	print("[mm-client] %s" % what)
	if enet != null:
		enet.close()
	get_tree().quit(code)
