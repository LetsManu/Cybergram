class_name PhaseMachine
extends RefCounted
## Explicit state machines of the front (P1, docs/architecture/front-state.md):
## one per player, one per party, one per lobby (a formed match before it
## runs). Each machine is a table of legal transitions; `PhaseRegistry`
## keeps the current state per key and rejects (and reports) anything else.
## Pure data, no network, no clock.
##
## Player (what the launcher / menu shows):
##   OFFLINE -> IDLE | IN_PARTY | RECONNECTING
##   IDLE <-> IN_PARTY;  IDLE | IN_PARTY | POST_GAME -> QUEUED | CHAMP_SELECT (custom lobby)
##   QUEUED -> READY_CHECK | IDLE | IN_PARTY | RECONNECTING (lost connection, ticket kept for the grace)
##   READY_CHECK -> CHAMP_SELECT | QUEUED (someone else declined) | IDLE | IN_PARTY
##   CHAMP_SELECT -> LOADING | QUEUED (a dodge re-queued you) | IDLE | IN_PARTY
##   LOADING -> IN_GAME | QUEUED (voided) | IDLE | IN_PARTY
##   IN_GAME -> POST_GAME | QUEUED (voided) | IDLE | IN_PARTY | OFFLINE (the match
##     ended while the game was closed: no front connection to show POST_GAME on)
##   POST_GAME -> IDLE | IN_PARTY | QUEUED
##   any online state -> OFFLINE (disconnect outside a match)
##   READY_CHECK | CHAMP_SELECT | LOADING | IN_GAME -> RECONNECTING (connection lost, seat kept)
##   (the front derives IN_GAME from the match state: a running match owns its
##   own connection, so a closed menu connection alone does not mean RECONNECTING)
##   RECONNECTING -> the state it left, or IDLE | IN_PARTY | POST_GAME | QUEUED | OFFLINE
## Party:  NONE -> IDLE;  IDLE <-> QUEUED;  QUEUED -> IN_MATCH;  IN_MATCH -> IDLE | QUEUED;  any -> NONE
## Lobby:  READY_CHECK -> CHAMP_SELECT | CANCELLED;  CHAMP_SELECT -> LOADING | CANCELLED;
##         LOADING -> RUNNING | CANCELLED;  RUNNING -> ENDED | CANCELLED
## Setting the current state again is a no-op, never an error.

enum Kind { PLAYER, PARTY, LOBBY }

enum Player { OFFLINE, IDLE, IN_PARTY, QUEUED, READY_CHECK, CHAMP_SELECT, LOADING, IN_GAME, POST_GAME, RECONNECTING }
enum Party { NONE, IDLE, QUEUED, IN_MATCH }
enum Lobby { READY_CHECK, CHAMP_SELECT, LOADING, RUNNING, ENDED, CANCELLED }

const PLAYER_NAMES := ["Offline", "Idle", "InParty", "Queued", "ReadyCheck", "ChampSelect", "Loading", "InGame",
	"PostGame", "Reconnecting"]
const PARTY_NAMES := ["None", "Idle", "Queued", "InMatch"]
const LOBBY_NAMES := ["ReadyCheck", "ChampSelect", "Loading", "Running", "Ended", "Cancelled"]

const _P := Player
const PLAYER_LEGAL := {
	_P.OFFLINE: [_P.IDLE, _P.IN_PARTY, _P.RECONNECTING],
	_P.IDLE: [_P.IN_PARTY, _P.QUEUED, _P.CHAMP_SELECT, _P.OFFLINE],
	_P.IN_PARTY: [_P.IDLE, _P.QUEUED, _P.CHAMP_SELECT, _P.OFFLINE],
	_P.QUEUED: [_P.READY_CHECK, _P.IDLE, _P.IN_PARTY, _P.OFFLINE, _P.RECONNECTING],
	_P.READY_CHECK: [_P.CHAMP_SELECT, _P.QUEUED, _P.IDLE, _P.IN_PARTY, _P.OFFLINE, _P.RECONNECTING],
	_P.CHAMP_SELECT: [_P.LOADING, _P.QUEUED, _P.IDLE, _P.IN_PARTY, _P.OFFLINE, _P.RECONNECTING],
	_P.LOADING: [_P.IN_GAME, _P.QUEUED, _P.IDLE, _P.IN_PARTY, _P.RECONNECTING],
	_P.IN_GAME: [_P.POST_GAME, _P.QUEUED, _P.IDLE, _P.IN_PARTY, _P.RECONNECTING, _P.OFFLINE],
	_P.POST_GAME: [_P.IDLE, _P.IN_PARTY, _P.QUEUED, _P.CHAMP_SELECT, _P.OFFLINE],
	_P.RECONNECTING: [_P.READY_CHECK, _P.CHAMP_SELECT, _P.LOADING, _P.IN_GAME, _P.POST_GAME, _P.QUEUED, _P.IDLE,
		_P.IN_PARTY, _P.OFFLINE],
}
const PARTY_LEGAL := {
	Party.NONE: [Party.IDLE],
	Party.IDLE: [Party.QUEUED, Party.IN_MATCH, Party.NONE],
	Party.QUEUED: [Party.IDLE, Party.IN_MATCH, Party.NONE],
	Party.IN_MATCH: [Party.IDLE, Party.QUEUED, Party.NONE],
}
const LOBBY_LEGAL := {
	Lobby.READY_CHECK: [Lobby.CHAMP_SELECT, Lobby.CANCELLED],
	Lobby.CHAMP_SELECT: [Lobby.LOADING, Lobby.CANCELLED],
	Lobby.LOADING: [Lobby.RUNNING, Lobby.CANCELLED],
	Lobby.RUNNING: [Lobby.ENDED, Lobby.CANCELLED],
	Lobby.ENDED: [],
	Lobby.CANCELLED: [],
}


## True when `from` -> `to` is allowed for `kind` (equal states count as allowed).
static func is_legal(kind: Kind, from: int, to: int) -> bool:
	if from == to:
		return true
	return (table(kind).get(from, []) as Array).has(to)


static func table(kind: Kind) -> Dictionary:
	match kind:
		Kind.PARTY:
			return PARTY_LEGAL
		Kind.LOBBY:
			return LOBBY_LEGAL
	return PLAYER_LEGAL


## Readable state name ("Queued") for logs and the admin page.
static func name_of(kind: Kind, state: int) -> String:
	var names: Array = PLAYER_NAMES if kind == Kind.PLAYER else (PARTY_NAMES if kind == Kind.PARTY else LOBBY_NAMES)
	return names[state] if state >= 0 and state < names.size() else "?%d" % state


## Initial state of a key that was never seen.
static func initial(kind: Kind) -> int:
	match kind:
		Kind.PARTY:
			return Party.NONE
		Kind.LOBBY:
			return Lobby.READY_CHECK
	return Player.OFFLINE
