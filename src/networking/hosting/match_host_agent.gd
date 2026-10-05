class_name MatchHostAgent
extends RefCounted
## The match-process side of the supervisor channel (W17). One per match
## process. Phase B hook (docs/architecture/matchmaking-phaseB-hosting.md):
##
##   var agent := MatchHostAgent.from_cmdline(OS.get_cmdline_user_args())
##   if agent != null:                      # started by a MatchSupervisor
##       agent.allocated.connect(_start_match)   # setup: MatchSetup dictionary
##       agent.mark_ready()                 # once listening on agent.port()
##   # every frame:   agent.tick(Time.get_ticks_msec() / 1000.0)
##   # join:          agent.verify_ticket(ticket, Time.get_unix_time_from_system())
##   # leaver:        agent.report_abandon(account_id)
##   # end:           agent.report_result(winner_team, players, abandons)
##   #                or agent.report_void("reason")
##   # exit when:     agent.should_exit()
##
## Reads the owner-only boot file named by --host-boot (and deletes it), sends
## READY and a heartbeat every boot.heartbeat_s, resends RESULT/VOID until the
## supervisor acknowledges it, and asks to exit on SHUTDOWN.

signal allocated(setup: Dictionary)
signal drain_requested
signal shutdown_requested

const ARG_BOOT := "--host-boot"
const RESEND_S := 0.5

var boot: Dictionary = {}
var setup: Dictionary = {}
var link: Variant  # HostChannelUdp (client) or a test fake: send(data), poll()
var files: MatchHostFiles
var drain_asked: bool = false
var shutdown_asked: bool = false
var ready_sent: bool = false
var report_acked: bool = false

var _secret: PackedByteArray
var _slot: int = 0
var _tx_seq: int = 0
var _rx_seq: int = 0
var _last_hb: float = -1.0e9
var _report: Dictionary = {}  # {op, payload} waiting for RESULT_ACK
var _last_send: float = -1.0e9
var _verifier: JoinTicketVerifier
var _ring: TicketKeyRing


## The boot file path in `args` ("" when this process was not supervised).
static func boot_path_from_args(args: PackedStringArray) -> String:
	var i := args.find(ARG_BOOT)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else ""


## An agent connected over loopback UDP, or null when `args` has no
## --host-boot or the boot file is missing/invalid.
static func from_cmdline(args: PackedStringArray) -> MatchHostAgent:
	var path := boot_path_from_args(args)
	if path == "":
		return null
	var files_ := MatchHostFiles.new(path.get_base_dir())
	var b := files_.read_and_delete(path)
	if not valid_boot(b):
		push_error("[host-agent] boot file missing or invalid")
		return null
	var udp := HostChannelUdp.new()
	if udp.open_client(int(b.channel_port)) != OK:
		push_error("[host-agent] cannot open the supervisor channel")
		return null
	return MatchHostAgent.new(b, udp, files_)


static func valid_boot(b: Dictionary) -> bool:
	for k in ["slot", "port", "channel_port", "channel_secret", "build", "ticket_kid", "ticket_key"]:
		if not b.has(k):
			return false
	return str(b.channel_secret).length() == 64 and str(b.channel_secret).is_valid_hex_number()


func _init(boot_: Dictionary, link_: Variant, files_: MatchHostFiles) -> void:
	boot = boot_
	link = link_
	files = files_
	_slot = int(boot.slot)
	_secret = str(boot.channel_secret).hex_decode()
	_ring = TicketKeyRing.parse_spec("%s:%s" % [boot.ticket_kid, boot.ticket_key])


## The UDP port this match must listen on.
func port() -> int:
	return int(boot.port)


func build() -> String:
	return str(boot.build)


func match_id() -> String:
	return str(setup.get("match_id", ""))


## Tell the supervisor this process can take a match.
func mark_ready() -> void:
	ready_sent = true
	_send(HostChannelCodec.OP_READY, {"build": build()})


func tick(now: float) -> void:
	for pkt: Variant in link.poll():
		_on_packet(pkt.data if pkt is Dictionary else pkt)
	if ready_sent and now - _last_hb >= float(boot.get("heartbeat_s", 1.0)):
		_last_hb = now
		_send(HostChannelCodec.OP_HEARTBEAT, {})
	if not _report.is_empty() and not report_acked and now - _last_send >= RESEND_S:
		_last_send = now
		_send(int(_report.op), _report.payload)


## Checks a player's join ticket for this match: {result, account}.
func verify_ticket(ticket: String, now_unix: float) -> Dictionary:
	if _verifier == null:
		return {"result": JoinTicketVerifier.Result.WRONG_MATCH, "account": ""}
	return _verifier.verify(ticket, now_unix)


## A player left for good (leaver penalty input). Sent once, best effort.
func report_abandon(account_id: String) -> void:
	_send(HostChannelCodec.OP_ABANDON, {"match_id": match_id(), "account": account_id})


## The match ended. `players`: [{account, team, kills, deaths, assists, ...}]
## (ids and numbers only), `abandons`: account ids that left for good.
func report_result(winner_team: int, players: Array, abandons: Array = []) -> void:
	_queue_report(HostChannelCodec.OP_RESULT, {"match_id": match_id(), "winner": winner_team,
		"players": players, "abandons": abandons})


## The match cannot count (internal error, nobody connected ...).
func report_void(reason: String) -> void:
	_queue_report(HostChannelCodec.OP_VOID, {"match_id": match_id(), "reason": reason.left(64)})


## True when the process should exit now: its report was acknowledged, or the
## supervisor asked an idle process to stop.
func should_exit() -> bool:
	return report_acked or (shutdown_asked and match_id() == "")


## Last words before exiting (best effort).
func close() -> void:
	_send(HostChannelCodec.OP_BYE, {})


func _queue_report(op: int, payload: Dictionary) -> void:
	if not _report.is_empty():
		return
	_report = {"op": op, "payload": payload}
	_last_send = -1.0e9


func _on_packet(data: PackedByteArray) -> void:
	if HostChannelCodec.peek_slot(data) != _slot:
		return
	var m := HostChannelCodec.decode(data, _secret)
	if m.is_empty() or int(m.seq) <= _rx_seq:
		return
	_rx_seq = int(m.seq)
	var pl: Dictionary = m.payload
	match int(m.op):
		HostChannelCodec.OP_ALLOCATE:
			if match_id() != "":
				return
			var s := files.read_and_delete(str(pl.get("path", "")))
			if MatchSetup.validate(s) != "" or str(s.match_id) != str(pl.get("match_id", "")):
				push_error("[host-agent] invalid match setup")
				return
			setup = s
			_verifier = JoinTicketVerifier.new(_ring, match_id(), float(boot.get("ticket_max_ttl_s", 30.0)))
			_send(HostChannelCodec.OP_ALLOCATED, {"match_id": match_id()})
			allocated.emit(setup)
		HostChannelCodec.OP_DRAIN:
			drain_asked = true
			drain_requested.emit()
		HostChannelCodec.OP_SHUTDOWN:
			shutdown_asked = true
			shutdown_requested.emit()
		HostChannelCodec.OP_RESULT_ACK:
			if str(pl.get("match_id", "")) == match_id():
				report_acked = true


func _send(op: int, payload: Dictionary) -> void:
	_tx_seq += 1
	link.send(HostChannelCodec.encode(op, _slot, _tx_seq, payload, _secret))
