class_name MatchmakingCodec
extends RefCounted
## Matchmaking messages (protocol v17, design/gdd/matchmaking.md,
## docs/architecture/matchmaking-client-api.md). Two message ids, like the
## account messages:
##   MM_REQ   (C->S) = u8 op + fields
##   MM_EVENT (S->C) = u8 op, u8 code + fields (fields only when code == OK,
##                     except QUEUE_STATUS / READY_RESULT / ACK that always carry them)
## The fields of each op are fixed by REQ_SCHEMA / EVT_SCHEMA. Decoding is
## strict (exact field list, bounded sizes, no trailing bytes) and returns {}
## on any mismatch. Reliable, ch0.
## Field types: b = u8, u = u16, w = u32, d = signed i16 (rating deltas x10),
## i = account id (16 B, zeros = none / bot / hidden), s = str8 (<= 64 B),
## T = join ticket str8 (<= 255 B ASCII), S = seat list, H = u16 list,
## R = ranked list, M = member list.
## Time on the wire is always "seconds left" (no shared clock).
## Heroes are ContentDB HERO indices (u16, 0 = none); lanes are LANE_* (u8).

## C->S ops.
const OP_QUEUE_JOIN: int = 1         ## party leader: queue, primary lane, secondary lane
const OP_QUEUE_LEAVE: int = 2        ## the whole party leaves the queue
const OP_READY_REPLY: int = 3        ## accept (1) / decline (0) the found match
const OP_PICK: int = 4               ## draft pick (hero index)
const OP_ARAM_REROLL: int = 5        ## 3v3: reroll own hero
const OP_ARAM_BENCH: int = 6         ## 3v3: take `hero` from the team bench
const OP_ARAM_SWAP_REQUEST: int = 7  ## 3v3: ask teammate in seat `seat` to swap
const OP_ARAM_SWAP_ACCEPT: int = 8   ## 3v3: accept the swap asked by seat `seat`
const OP_REMAKE_VOTE: int = 9        ## in match (match process): yes / no (the first yes starts the vote)
const OP_REPORT: int = 10            ## post-match report: match id, target, category index
const OP_HONOUR: int = 11            ## post-match honour: match id, target
const OP_RANKED_INFO: int = 12       ## ask for own RANKED_INFO
const OP_CUSTOM_CREATE: int = 13     ## host: map index, pick mode, bots on/off, team size
const OP_CUSTOM_INVITE: int = 14     ## host: invite a friend (id zeros = the whole party)
const OP_CUSTOM_JOIN: int = 15       ## join the custom lobby of host `host`
const OP_CUSTOM_LEAVE: int = 16      ## leave (the host leaving closes it)
const OP_CUSTOM_TEAM: int = 17       ## switch team
const OP_CUSTOM_PICK: int = 18       ## pick a hero in a custom lobby
const OP_CUSTOM_START: int = 19      ## host: start the custom match
const OP_REJOIN: int = 20            ## reconnect: ask for a fresh ticket to the own running match
const OP_STATE_SYNC: int = 21        ## v20: ask for a full PHASE snapshot (after a reconnect)
const OP_HOVER: int = 22             ## v20: declare a hero (pick or ban phase; hero 0 clears)
const OP_CUSTOM_BOTS: int = 23       ## v20: host: bots per team (255 = fill) and bot difficulty
const OP_LOAD_PROGRESS: int = 24     ## v20: own match loading progress, percent (only rises)

## S->C ops.
const EV_QUEUE_STATUS: int = 1
const EV_MATCH_FOUND: int = 2
const EV_READY_RESULT: int = 3
const EV_PICK_STATE: int = 4
const EV_MATCH_ASSIGNED: int = 5
const EV_RANKED_INFO: int = 6
const EV_LOCKOUT: int = 7
const EV_REMAKE_STATE: int = 8
const EV_MATCH_RESULT: int = 9
const EV_CUSTOM_STATE: int = 10
const EV_ACK: int = 11               ## answer to a request: code = OK or an error
const EV_PHASE: int = 12             ## v20: the player's state machine (PhaseMachine.Player), versioned
const EV_LOAD_PROGRESS: int = 13     ## v20: every seat's loading percent (seat order; bots 100)

const REQ_SCHEMA := {
	OP_QUEUE_JOIN: [["queue", "b"], ["lane1", "b"], ["lane2", "b"]],
	OP_QUEUE_LEAVE: [],
	OP_READY_REPLY: [["accept", "b"]],
	OP_PICK: [["hero", "u"]],
	OP_ARAM_REROLL: [],
	OP_ARAM_BENCH: [["hero", "u"]],
	OP_ARAM_SWAP_REQUEST: [["seat", "b"]],
	OP_ARAM_SWAP_ACCEPT: [["seat", "b"]],
	OP_REMAKE_VOTE: [["yes", "b"]],
	OP_REPORT: [["match", "s"], ["target", "i"], ["category", "b"]],
	OP_HONOUR: [["match", "s"], ["target", "i"]],
	OP_RANKED_INFO: [],
	OP_CUSTOM_CREATE: [["map", "b"], ["mode", "b"], ["bots", "b"], ["team_size", "b"]],
	OP_CUSTOM_INVITE: [["id", "i"]],
	OP_CUSTOM_JOIN: [["host", "i"]],
	OP_CUSTOM_LEAVE: [],
	OP_CUSTOM_TEAM: [["team", "b"]],
	OP_CUSTOM_PICK: [["hero", "u"]],
	OP_CUSTOM_START: [],
	OP_REJOIN: [],
	OP_STATE_SYNC: [],
	OP_HOVER: [["hero", "u"]],
	OP_CUSTOM_BOTS: [["bots_a", "b"], ["bots_b", "b"], ["difficulty", "b"]],
	OP_LOAD_PROGRESS: [["pct", "b"]],
}

const EVT_SCHEMA := {
	## state QS_*, queue index, seconds waited, estimate, players queued, lockout seconds left.
	EV_QUEUE_STATUS: [["state", "b"], ["queue", "b"], ["waited", "u"], ["estimate", "u"], ["players", "u"],
		["locked", "u"]],
	EV_MATCH_FOUND: [["match", "s"], ["queue", "b"], ["seconds", "b"], ["humans", "b"], ["accepted", "b"],
		["you_accepted", "b"]],
	## outcome RR_*, lockout seconds left (when locked).
	EV_READY_RESULT: [["outcome", "b"], ["locked", "u"]],
	## mode PM_*, turn, turn team, seconds left, own seat index, seats, own rerolls,
	## own team bench (heroes), seats asking you to swap (draft: trade offers),
	## v20: stage PS_*, banned heroes (after the ban phase), trade seconds left.
	EV_PICK_STATE: [["mode", "b"], ["turn", "b"], ["turn_team", "b"], ["seconds", "u"], ["you", "b"],
		["seats", "S"], ["rerolls", "b"], ["bench", "H"], ["swap_from", "H"], ["stage", "b"], ["bans", "H"],
		["trade_s", "u"]],
	EV_MATCH_ASSIGNED: [["host", "s"], ["port", "u"], ["ticket", "T"], ["match", "s"], ["team", "b"],
		["hero", "u"], ["map", "s"]],
	EV_RANKED_INFO: [["tracks", "R"]],
	## lockout seconds left, ranked-only (1) or all queues (0), reason LK_*.
	EV_LOCKOUT: [["seconds", "u"], ["ranked", "b"], ["reason", "b"]],
	## state RV_*, yes votes, needed, seconds left, team.
	EV_REMAKE_STATE: [["state", "b"], ["yes", "b"], ["needed", "b"], ["seconds", "b"], ["team", "b"]],
	## won/lost from your side, void, duration, rated, own rating delta x10, players (stats).
	EV_MATCH_RESULT: [["match", "s"], ["queue", "b"], ["won", "b"], ["voided", "b"], ["duration", "u"],
		["rated", "b"], ["delta", "d"], ["players", "M"]],
	## v20: bots per team (255 = fill the empty seats) and BOT_DIFFICULTIES index.
	EV_CUSTOM_STATE: [["host", "i"], ["phase", "b"], ["map", "b"], ["mode", "b"], ["bots", "b"],
		["team_size", "b"], ["members", "M"], ["bots_a", "b"], ["bots_b", "b"], ["difficulty", "b"]],
	EV_ACK: [["req", "b"]],
	## server epoch (start time), sequence (grows per player), phase and previous
	## phase (PhaseMachine.Player), snapshot flag (1 = full state, accept even
	## with a lower seq), queue index (255 none), party size, you lead (1),
	## seconds queued, estimate, lockout seconds left, match id, party id.
	EV_PHASE: [["epoch", "w"], ["seq", "w"], ["phase", "b"], ["prev", "b"], ["snap", "b"], ["queue", "b"],
		["party_size", "b"], ["leader", "b"], ["waited", "u"], ["estimate", "u"], ["locked", "u"], ["match", "s"],
		["party", "s"]],
	## v20: loading percent per seat, in EV_PICK_STATE seat order (0-100).
	EV_LOAD_PROGRESS: [["loads", "H"]],
}
## Events whose fields travel with any code (the code is an error detail).
const ALWAYS_FIELDS := [EV_QUEUE_STATUS, EV_READY_RESULT, EV_ACK]

## Result codes (EV_* code byte).
const OK: int = 0
const E_BAD_REQUEST: int = 1
const E_QUEUE: int = 2         ## unknown or closed queue
const E_PARTY_SIZE: int = 3    ## party too big for the queue
const E_PARTY_GAP: int = 4     ## ranked: party rating gap too large
const E_LOCKED: int = 5        ## queue lockout running
const E_ALREADY: int = 6       ## already queued / in a match
const E_LANES: int = 7
const E_NOT_LEADER: int = 8    ## only the party leader may queue
const E_NOT_LOGGED_IN: int = 9
const E_GUEST: int = 10        ## ranked needs an account
const E_IN_MATCH: int = 11     ## a party member is in a match
const E_NOT_ALLOWED: int = 12  ## not your turn / not a seat / closed / not the host
const E_TAKEN: int = 13        ## hero taken by a teammate
const E_NO_REROLLS: int = 14
const E_NOT_FOUND: int = 15
const E_DUPLICATE: int = 16
const E_BUSY: int = 17         ## no match server free right now
const E_DRAINING: int = 18     ## the server is restarting for a patch
const E_TOO_LATE: int = 19     ## remake window over
const CODE_COUNT: int = 20

## Queue status states.
const QS_IDLE: int = 0
const QS_QUEUED: int = 1
const QS_READY_CHECK: int = 2
const QS_PICKING: int = 3
const QS_IN_MATCH: int = 4
const QS_LOCKED: int = 5

## Ready-check outcomes.
const RR_GO: int = 0         ## everyone accepted: the pick phase starts
const RR_REQUEUED: int = 1   ## someone else failed it: back in the queue with priority
const RR_REMOVED: int = 2    ## your party was removed (a party member failed it)
const RR_LOCKED: int = 3     ## you failed it: lockout
const RR_VOIDED: int = 4     ## match server lost before or during the match: re-queue

## Pick modes.
const PM_DRAFT: int = 0
const PM_ALL_RANDOM: int = 1
const PM_CUSTOM: int = 2
const PM_BLIND: int = 3       ## v20: Normal 5v5 blind pick (enemy picks hidden until all locked)
## v20 pick stages (EV_PICK_STATE stage).
const PS_PICK: int = 0
const PS_BAN: int = 1
const PS_FINALIZE: int = 2

## Lanes (LaneAssigner ids).
const LANES: Array[StringName] = [&"north", &"center", &"south", &"flex"]
const LANE_FILL: int = 255

## Seat flags.
const SEAT_BOT: int = 1
const SEAT_AUTO: int = 2     ## hero chosen on timeout / dealt
const SEAT_PICKING: int = 4  ## this seat picks now
const SEAT_YOU: int = 8
const SEAT_PICKED: int = 16
const SEAT_HOVER: int = 32   ## v20: `hero` is the seat's declared (not locked) hero; allies only
const SEAT_BANNING: int = 64 ## v20: this seat bans now; `hero` = its ban (own team only)

## Member flags (custom lobby, match result).
const MEM_BOT: int = 1
const MEM_LEAVER: int = 2
const MEM_HOST: int = 4
const MEM_YOU: int = 8

## Remake vote states (RemakeVote.State).
const RV_IDLE: int = 0
const RV_OPEN: int = 1
const RV_PASSED: int = 2
const RV_FAILED: int = 3

## Lockout reasons.
const LK_DECLINE: int = 0
const LK_LEAVE: int = 1

## Rating tracks (RANKED_INFO).
const TRACKS: Array[StringName] = [&"normal", &"ranked", &"all_random"]
const RATING_HIDDEN: int = 0xFFFF

## Custom lobby phases.
## v20 custom-game bot difficulty (BotRosterDef profiles), by index.
const BOT_DIFFICULTIES: Array[String] = ["easy", "normal", "hard"]
## v20: bots_a / bots_b value meaning "fill every empty seat".
const BOTS_FILL: int = 255
const CP_OPEN: int = 0
const CP_STARTING: int = 1
const CP_CLOSED: int = 2

## Custom game maps (index on the wire).
const CUSTOM_MAPS: Array[StringName] = [&"shardline_front", &"slice"]

const STR_MAX: int = 64
const TICKET_MAX: int = 255
const MAX_SEATS: int = 10
const MAX_LIST: int = 16
const ID_ZERO := "00000000000000000000000000000000"


static func encode_request(op: int, fields: Dictionary = {}) -> PackedByteArray:
	var w := LobbyCodec.Writer.new(MsgType.MM_REQ)
	w.u8(op)
	_write(w, REQ_SCHEMA.get(op, []), fields)
	return w.b


## {op, ...fields} or {} when malformed / unknown op.
static func decode_request(b: PackedByteArray) -> Dictionary:
	if b.size() < 2 or b.size() > LobbyCodec.MAX_C2S_BYTES or b.decode_u8(0) != MsgType.MM_REQ:
		return {}
	var op := b.decode_u8(1)
	if not REQ_SCHEMA.has(op):
		return {}
	var r := LobbyCodec.Reader.new(b)
	r.pos = 2
	var d := _read(r, REQ_SCHEMA[op])
	if not r.done():
		return {}
	d["op"] = op
	return d


static func encode_event(op: int, code: int, fields: Dictionary = {}) -> PackedByteArray:
	var w := LobbyCodec.Writer.new(MsgType.MM_EVENT)
	w.u8(op)
	w.u8(code)
	if code == OK or ALWAYS_FIELDS.has(op):
		_write(w, EVT_SCHEMA.get(op, []), fields)
	return w.b


## {op, code, ...fields} or {}.
static func decode_event(b: PackedByteArray) -> Dictionary:
	if b.size() < 3 or b.decode_u8(0) != MsgType.MM_EVENT:
		return {}
	var op := b.decode_u8(1)
	var code := b.decode_u8(2)
	if not EVT_SCHEMA.has(op) or code >= CODE_COUNT:
		return {}
	var r := LobbyCodec.Reader.new(b)
	r.pos = 3
	var d := {}
	if code == OK or ALWAYS_FIELDS.has(op):
		d = _read(r, EVT_SCHEMA[op])
	if not r.done():
		return {}
	d["op"] = op
	d["code"] = code
	return d


## Lane id -> wire byte (unknown / fill = LANE_FILL).
static func lane_byte(lane: StringName) -> int:
	var i := LANES.find(lane)
	return i if i >= 0 else LANE_FILL


static func lane_of(b: int) -> StringName:
	return LANES[b] if b >= 0 and b < LANES.size() else &"fill"


static func _write(w: LobbyCodec.Writer, schema: Array, f: Dictionary) -> void:
	for field in schema:
		var v: Variant = f.get(field[0])
		match field[1]:
			"b":
				w.u8(clampi(int(v) if v != null else 0, 0, 255))
			"u":
				w.u16(clampi(int(v) if v != null else 0, 0, 65535))
			"w":
				var x := int(v) if v != null else 0
				w.u16(x & 0xFFFF)
				w.u16((x >> 16) & 0xFFFF)
			"d":
				w.u16(clampi(int(v) if v != null else 0, -32768, 32767) + 32768)
			"i":
				w.id(str(v) if v != null else "")
			"s":
				w.str8(str(v) if v != null else "", STR_MAX)
			"T":
				var t := str(v) if v != null else ""
				w.str8(t if t.length() <= TICKET_MAX else "", TICKET_MAX)
			"H":
				var l: Array = v if v is Array else []
				var n := mini(l.size(), MAX_LIST)
				w.u8(n)
				for k in n:
					w.u16(clampi(int(l[k]), 0, 65535))
			"S":
				var l: Array = v if v is Array else []
				var n := mini(l.size(), MAX_SEATS)
				w.u8(n)
				for k in n:
					var e: Dictionary = l[k]
					w.id(str(e.get("id", "")))
					w.u8(clampi(int(e.get("team", 0)), 0, 1))
					w.u8(clampi(int(e.get("lane", LANE_FILL)), 0, 255))
					w.u16(clampi(int(e.get("hero", 0)), 0, 65535))
					w.u8(int(e.get("flags", 0)) & 0xFF)
					w.str8(str(e.get("name", "")), STR_MAX)
			"R":
				var l: Array = v if v is Array else []
				var n := mini(l.size(), TRACKS.size())
				w.u8(n)
				for k in n:
					var e: Dictionary = l[k]
					w.u8(clampi(int(e.get("track", 0)), 0, 255))
					w.u16(clampi(int(e.get("rating", RATING_HIDDEN)), 0, 65535))
					w.u8(clampi(int(e.get("games_left", 0)), 0, 255))
					w.u8(clampi(int(e.get("band", 255)), 0, 255))
					w.u8(clampi(int(e.get("division", 0)), 0, 255))
			"M":
				var l: Array = v if v is Array else []
				var n := mini(l.size(), MAX_SEATS)
				w.u8(n)
				for k in n:
					var e: Dictionary = l[k]
					w.id(str(e.get("id", "")))
					w.u8(clampi(int(e.get("team", 0)), 0, 1))
					w.u16(clampi(int(e.get("hero", 0)), 0, 65535))
					w.u8(int(e.get("flags", 0)) & 0xFF)
					w.u16(clampi(int(e.get("kills", 0)), 0, 65535))
					w.u16(clampi(int(e.get("deaths", 0)), 0, 65535))
					w.u16(clampi(int(e.get("assists", 0)), 0, 65535))
					w.str8(str(e.get("name", "")), STR_MAX)


static func _read(r: LobbyCodec.Reader, schema: Array) -> Dictionary:
	var d := {}
	for field in schema:
		match field[1]:
			"b":
				d[field[0]] = r.u8()
			"u":
				d[field[0]] = r.u16()
			"w":
				var lo := r.u16()
				d[field[0]] = lo | (r.u16() << 16)
			"d":
				d[field[0]] = r.u16() - 32768
			"i":
				d[field[0]] = r.id()
			"s":
				d[field[0]] = r.str8(STR_MAX)
			"T":
				d[field[0]] = r.str8(TICKET_MAX)
			"H":
				var n := r.u8()
				if n > MAX_LIST:
					r.ok = false
				var l: Array = []
				for k in (n if r.ok else 0):
					l.append(r.u16())
				d[field[0]] = l
			"S":
				var n := r.u8()
				if n > MAX_SEATS:
					r.ok = false
				var l: Array = []
				for k in (n if r.ok else 0):
					l.append({"id": r.id(), "team": r.u8(), "lane": r.u8(), "hero": r.u16(), "flags": r.u8(),
						"name": r.str8(STR_MAX)})
				d[field[0]] = l
			"R":
				var n := r.u8()
				if n > TRACKS.size():
					r.ok = false
				var l: Array = []
				for k in (n if r.ok else 0):
					l.append({"track": r.u8(), "rating": r.u16(), "games_left": r.u8(), "band": r.u8(),
						"division": r.u8()})
				d[field[0]] = l
			"M":
				var n := r.u8()
				if n > MAX_SEATS:
					r.ok = false
				var l: Array = []
				for k in (n if r.ok else 0):
					l.append({"id": r.id(), "team": r.u8(), "hero": r.u16(), "flags": r.u8(), "kills": r.u16(),
						"deaths": r.u16(), "assists": r.u16(), "name": r.str8(STR_MAX)})
				d[field[0]] = l
		if not r.ok:
			return {}
	return d
