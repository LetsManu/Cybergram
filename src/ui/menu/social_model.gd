class_name SocialModel
extends RefCounted
## P2: client-side social state behind the friends panel, the DM window and
## the party box (view-model, no nodes, tested headless). Fed with every
## ACCOUNT_RESULT (FRIENDS, PARTY, NOTIFY); actions go out through `request`
## (Callable(op, fields)). The server decides everything; this only keeps
## what the screens show: friends with presence, the party with ready flags,
## direct-message threads with unread counts, party chat, and pending party
## invites / join requests. Memory only: threads and chat vanish with the game.
##
## Example (main menu):
##   social = SocialModel.new(func(op, f): online.request(op, f))
##   online.account_result.connect(social.on_result)
##   social.toast.connect(func(text, kind): UiKit.toast(self, text, kind))

## Something the screens show changed.
signal changed()
## A short message for a toast (already translated), kind &"info" / &"warn".
signal toast(text: String, kind: StringName)
## The party changed (members, leader, ready flags): {party, leader, members}.
signal party_changed(party: Dictionary)

const THREAD_MAX := 50
const PARTY_CHAT_MAX := 50
## Seconds a join request stays in the list.
const JOIN_REQUEST_TTL_S := 60.0

var request: Callable
## My account id ("" = unknown).
var me: String = ""
## FRIENDS entries ({id, status, mode, relation, username, display_name, emblem, accent}).
var friends: Array = []
## Last OP_PARTY answer ({party, leader, members: [{id, kind, status, display_name, flags}]}).
var party: Dictionary = {}
## friend id -> [{mine: bool, text, t}]
var threads: Dictionary = {}
## friend id -> unread count
var unread: Dictionary = {}
## The thread on screen (its messages count as read).
var open_thread: String = ""
## [{id, name, text, t}]
var party_chat: Array = []
## inviter id -> {name, t}   (party invites waiting for me)
var join_requests: Dictionary = {}
var clock: Callable = func() -> float: return Time.get_ticks_msec() / 1000.0


func _init(request_: Callable = Callable()) -> void:
	request = request_


# --- incoming -----------------------------------------------------------------

## Every ACCOUNT_RESULT goes through here (others are ignored).
func on_result(d: Dictionary) -> void:
	var ok := int(d.get("code", -1)) == AccountCodec.OK
	match int(d.get("op", -1)):
		AccountCodec.OP_FRIENDS:
			if ok:
				friends = d.friends
				changed.emit()
		AccountCodec.OP_PARTY:
			if ok:
				party = d
				party_changed.emit(party)
				changed.emit()
		AccountCodec.OP_NOTIFY:
			if ok:
				_on_notify(d)
		AccountCodec.OP_DM:
			if not ok:
				toast.emit(TranslationServer.translate("HUD_SOCIAL_DM_OFFLINE"), &"warn")
		AccountCodec.OP_PARTY_CHAT, AccountCodec.OP_PARTY_INVITE, AccountCodec.OP_PARTY_JOIN_REQUEST:
			if int(d.code) == AccountCodec.E_RATE:
				toast.emit(TranslationServer.translate("HUD_SOCIAL_SLOW_DOWN"), &"warn")
			elif not ok:
				toast.emit(TranslationServer.translate(LobbyClient.account_error_key(int(d.code))), &"warn")


func _on_notify(d: Dictionary) -> void:
	var from := str(d.id)
	var name := str(d.name)
	var now: float = clock.call()
	match int(d.kind):
		AccountCodec.N_PARTY_CHAT:
			party_chat.append({"id": from, "name": name, "text": str(d.text), "t": now})
			if party_chat.size() > PARTY_CHAT_MAX:
				party_chat.pop_front()
		AccountCodec.N_DM:
			_add_line(from, false, str(d.text))
			if open_thread != from:
				unread[from] = int(unread.get(from, 0)) + 1
				toast.emit(_fmt("HUD_SOCIAL_DM_FROM", name), &"info")
		AccountCodec.N_PARTY_INVITE:
			toast.emit(_fmt("HUD_SOCIAL_INVITED_BY", name), &"info")
			_ask(AccountCodec.OP_PARTY)
		AccountCodec.N_FRIEND_REQUEST:
			toast.emit(_fmt("HUD_SOCIAL_FRIEND_REQUEST", name), &"info")
			_ask(AccountCodec.OP_FRIENDS)
		AccountCodec.N_JOIN_REQUEST:
			join_requests[from] = {"name": name, "t": now}
			toast.emit(_fmt("HUD_SOCIAL_WANTS_JOIN", name), &"info")
		AccountCodec.N_PARTY_CHANGED:
			_ask(AccountCodec.OP_PARTY)
		AccountCodec.N_KICKED:
			toast.emit(TranslationServer.translate("HUD_SOCIAL_KICKED"), &"warn")
			party_chat.clear()
			_ask(AccountCodec.OP_PARTY)
	changed.emit()


# --- queries ------------------------------------------------------------------

func is_leader() -> bool:
	var lead := str(party.get("leader", ""))
	return lead == "" or LobbyCodec.is_none_id(lead) or lead == me


## Party members ({id, kind, status, display_name, flags}) without invites.
func members() -> Array:
	return (party.get("members", []) as Array).filter(func(m: Dictionary) -> bool:
		return int(m.kind) == AccountCodec.PARTY_LEADER or int(m.kind) == AccountCodec.PARTY_MEMBER)


## Party invites waiting for me ({id, display_name}).
func invites_in() -> Array:
	return (party.get("members", []) as Array).filter(func(m: Dictionary) -> bool:
		return int(m.kind) == AccountCodec.PARTY_INVITE_IN)


func in_my_party(id: String) -> bool:
	return members().any(func(m: Dictionary) -> bool: return str(m.id) == id)


## Live join requests (older than JOIN_REQUEST_TTL_S are dropped).
func pending_join_requests() -> Array:
	var now: float = clock.call()
	var out: Array = []
	for id in join_requests.keys():
		if now - float(join_requests[id].t) > JOIN_REQUEST_TTL_S:
			join_requests.erase(id)
		else:
			out.append({"id": id, "name": join_requests[id].name})
	return out


func total_unread() -> int:
	var n := 0
	for k in unread:
		n += int(unread[k])
	return n


## Presence line for a friend: "In queue · Ranked 5v5" (translated).
static func presence_text(status: int, mode: int) -> String:
	var key: String = FriendsPanel.STATUS_KEYS[clampi(status, 0, FriendsPanel.STATUS_KEYS.size() - 1)]
	var line := TranslationServer.translate(key)
	if mode < 255 and status in [LobbyCodec.STATUS_IN_QUEUE, LobbyCodec.STATUS_IN_SELECT, LobbyCodec.STATUS_IN_MATCH]:
		var qid: StringName = MatchmakingClient.QUEUE_IDS[mode] if mode < MatchmakingClient.QUEUE_IDS.size() else &""
		if qid != &"":
			line += " · " + TranslationServer.translate(MmView.queue_key(qid))
	return line


# --- actions ------------------------------------------------------------------

func invite(id: String) -> void:
	_ask(AccountCodec.OP_PARTY_INVITE, {"id": id})
	join_requests.erase(id)
	changed.emit()


func ask_to_join(id: String) -> void:
	_ask(AccountCodec.OP_PARTY_JOIN_REQUEST, {"id": id})
	toast.emit(TranslationServer.translate("HUD_SOCIAL_JOIN_ASKED"), &"info")


func accept_invite(inviter: String) -> void:
	_ask(AccountCodec.OP_PARTY_ACCEPT, {"id": inviter})
	_ask(AccountCodec.OP_PARTY)


func decline_invite(inviter: String) -> void:
	_ask(AccountCodec.OP_PARTY_DECLINE, {"id": inviter})
	_ask(AccountCodec.OP_PARTY)


func leave_party() -> void:
	_ask(AccountCodec.OP_PARTY_LEAVE)
	party_chat.clear()
	_ask(AccountCodec.OP_PARTY)


func promote(id: String) -> void:
	_ask(AccountCodec.OP_PARTY_PROMOTE, {"id": id})


func kick(id: String) -> void:
	_ask(AccountCodec.OP_PARTY_KICK, {"id": id})


func set_ready(on: bool) -> void:
	_ask(AccountCodec.OP_PARTY_READY, {"ready": 1 if on else 0})


func say_party(text: String) -> void:
	var s := text.strip_edges()
	if s != "":
		_ask(AccountCodec.OP_PARTY_CHAT, {"text": s.left(200)})


## Sends a DM and shows it at once in the thread (the server refuses it when
## the friend is offline; a toast then says so).
func send_dm(id: String, text: String) -> void:
	var s := text.strip_edges()
	if s == "":
		return
	_ask(AccountCodec.OP_DM, {"id": id, "text": s.left(200)})
	_add_line(id, true, s.left(200))
	changed.emit()


func open(id: String) -> void:
	open_thread = id
	unread.erase(id)
	changed.emit()


func close_thread() -> void:
	open_thread = ""


func set_away(on: bool) -> void:
	_ask(AccountCodec.OP_SET_AWAY, {"away": 1 if on else 0})


func refresh() -> void:
	_ask(AccountCodec.OP_FRIENDS)
	_ask(AccountCodec.OP_PARTY)


## Translated `key` with `arg` (safe when the string has no %s).
static func _fmt(key: String, arg: String) -> String:
	var t := TranslationServer.translate(key)
	return t % arg if t.contains("%s") else "%s %s" % [t, arg]


func _add_line(id: String, mine: bool, text: String) -> void:
	var th: Array = threads.get_or_add(id, [])
	th.append({"mine": mine, "text": text, "t": float(clock.call())})
	if th.size() > THREAD_MAX:
		th.pop_front()


func _ask(op: int, fields: Dictionary = {}) -> void:
	if request.is_valid():
		request.call(op, fields)
