class_name SocialView
extends VBoxContainer
## Friends and party in the launcher's right rail (W15). Uses the launcher's
## signed-in link (LauncherLogin.request): friends list with presence, add by
## username, accept / decline requests, block / unblock, invite a friend to
## the party, join / decline party invites, leave. The server decides
## everything; this view only shows its answers. Polls only while visible
## and signed in (friends every FRIENDS_EVERY_S, party every PARTY_EVERY_S).

const FRIENDS_EVERY_S: float = 15.0
const PARTY_EVERY_S: float = 5.0
## Indexed by LobbyCodec.STATUS_* (v20: in queue, hero select, away).
const STATUS_TEXT: Array[String] = ["Offline", "Online", "In lobby", "In match", "In queue", "Hero select", "Away"]
## Sort / group rank per status (busy first, away and offline last).
const STATUS_RANK: Array[int] = [0, 3, 4, 7, 5, 6, 1]
## Queue names by MatchmakingClient queue index (v20 presence mode).
const QUEUE_NAMES: Array[String] = ["Normal", "Ranked", "3v3", "Custom"]  # short: the rail is narrow

var login: LauncherLogin
## Last OP_FRIENDS list and OP_PARTY state.
var friends: Array = []
var party: Dictionary = {}
## Sample data mode (screenshots): never sends anything.
var preview: bool = false
var _signed_in: bool = false
var _since_f: float = FRIENDS_EVERY_S
var _since_p: float = PARTY_EVERY_S
var _out: Label
var _party_box: VBoxContainer
var _friends_box: VBoxContainer
var _friends_head: Label
var _add_row: HBoxContainer
var _add_edit: LineEdit
var _msg: Label
var _leave: Button
## Local time the last OP_PARTY arrived (invite countdowns count from it).
var _party_at: float = 0.0
var _tick: float = 0.0


func _ready() -> void:
	var t: UiKitTokens = UiKit.tokens()
	add_theme_constant_override("separation", 8)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_out = UiKit.label("Sign in to see your friends and invite them to a party.", &"small", t.text_dim)
	_out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_out)
	var ph: HBoxContainer = HBoxContainer.new()
	add_child(ph)
	var pt: Label = UiKit.eyebrow("PARTY", t.text_dim, 12)
	pt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pt)
	_leave = _small_link("Leave", func() -> void: _send(AccountCodec.OP_PARTY_LEAVE))
	ph.add_child(_leave)
	_party_box = VBoxContainer.new()
	_party_box.add_theme_constant_override("separation", 4)
	add_child(_party_box)
	add_child(UiKit.hairline())
	var fh: HBoxContainer = HBoxContainer.new()
	add_child(fh)
	_friends_head = UiKit.eyebrow("FRIENDS", t.text_dim, 12)
	_friends_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fh.add_child(_friends_head)
	fh.add_child(UiKit.icon_button(&"add_friend", func() -> void:
		_add_row.visible = not _add_row.visible
		if _add_row.visible:
			_add_edit.grab_focus(), "Add a friend by username", 24))
	_add_row = HBoxContainer.new()
	_add_row.visible = false
	_add_row.add_theme_constant_override("separation", 6)
	add_child(_add_row)
	_add_edit = UiKit.line_edit("Username", AccountCodec.STR_MAX)
	_add_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_edit.text_submitted.connect(func(_s: String) -> void: _add())
	_add_row.add_child(_add_edit)
	_add_row.add_child(UiKit.button("ADD", _add, &"secondary", 32))
	_msg = UiKit.label("", &"small", t.text_dim)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.visible = false
	add_child(_msg)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_friends_box = VBoxContainer.new()
	_friends_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friends_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_friends_box)
	_paint()


## Connects to the launcher's link (results arrive as account_result).
func bind(login_: LauncherLogin) -> void:
	login = login_
	login.account_result.connect(on_result)
	login.login_result.connect(func(ok: bool, _m: String, _n: String) -> void:
		if ok:
			_since_f = FRIENDS_EVERY_S
			_since_p = PARTY_EVERY_S)


func _process(delta: float) -> void:
	if preview:
		return
	var now_in: bool = login != null and login.is_logged_in() and login.secure
	if now_in != _signed_in:
		_signed_in = now_in
		if not now_in:
			friends = []
			party = {}
		_paint()
	if not now_in or not is_visible_in_tree():
		return
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		if not (party_rows(party).invites_in as Array).is_empty():
			_paint()  # v20: the invite countdown
	_since_f += delta
	_since_p += delta
	if _since_f >= FRIENDS_EVERY_S:
		_since_f = 0.0
		login.request(AccountCodec.OP_FRIENDS)
	if _since_p >= PARTY_EVERY_S:
		_since_p = 0.0
		login.request(AccountCodec.OP_PARTY)


## Handles an ACCOUNT_RESULT for friends / party ops.
func on_result(d: Dictionary) -> void:
	var op: int = int(d.get("op", 0))
	var ok: bool = int(d.get("code", -1)) == AccountCodec.OK
	match op:
		AccountCodec.OP_FRIENDS:
			if ok:
				friends = d.get("friends", [])
				_paint()
		AccountCodec.OP_PARTY:
			if ok:
				party = d
				_party_at = Time.get_ticks_msec() / 1000.0
				_paint()
		AccountCodec.OP_NOTIFY:
			if ok:
				var text := notify_text(d)
				if text != "":
					_note(text)
				_since_p = PARTY_EVERY_S
				_since_f = FRIENDS_EVERY_S
		AccountCodec.OP_PARTY_JOIN_REQUEST:
			_note("Asked to join. Their party leader decides." if ok else action_text(op, int(d.code)))
		AccountCodec.OP_FRIEND_REQUEST, AccountCodec.OP_FRIEND_ACCEPT, AccountCodec.OP_FRIEND_DECLINE, \
				AccountCodec.OP_FRIEND_REMOVE, AccountCodec.OP_BLOCK, AccountCodec.OP_UNBLOCK:
			_note(action_text(op, int(d.code)))
			_since_f = FRIENDS_EVERY_S
		AccountCodec.OP_PARTY_INVITE, AccountCodec.OP_PARTY_ACCEPT, AccountCodec.OP_PARTY_DECLINE, AccountCodec.OP_PARTY_LEAVE:
			_note(action_text(op, int(d.code)))
			_since_p = PARTY_EVERY_S


## Player-facing text for the result of an action.
static func action_text(op: int, code: int) -> String:
	if code == AccountCodec.OK:
		match op:
			AccountCodec.OP_FRIEND_REQUEST:
				return "Friend request sent."
			AccountCodec.OP_PARTY_INVITE:
				return "Party invite sent."
			AccountCodec.OP_PARTY_ACCEPT:
				return "You joined the party."
			AccountCodec.OP_PARTY_LEAVE:
				return "You left the party."
			AccountCodec.OP_BLOCK:
				return "Blocked."
		return ""
	match code:
		AccountCodec.E_NOT_FOUND:
			return "Not found (or no longer available)." if op >= AccountCodec.OP_PARTY else "No player with that username."
		AccountCodec.E_LIMIT:
			return "The party is full." if op >= AccountCodec.OP_PARTY else "List limit reached."
		AccountCodec.E_NOT_SECURE:
			return "This needs an encrypted connection."
	return "That did not work (code %d)." % code


## v20: the note for a server push (chat and DMs are read in the game, not here).
static func notify_text(d: Dictionary) -> String:
	var name := String(d.get("name", ""))
	match int(d.get("kind", 0)):
		AccountCodec.N_PARTY_INVITE:
			return "%s invited you to a party." % name
		AccountCodec.N_FRIEND_REQUEST:
			return "%s sent you a friend request." % name
		AccountCodec.N_JOIN_REQUEST:
			return "%s wants to join your party. Invite them with +." % name
		AccountCodec.N_KICKED:
			return "The party leader removed you from the party."
		AccountCodec.N_DM:
			return "New message from %s (open the game to reply)." % name
	return ""


## v20: "In queue · Ranked 5v5" for a friend (mode only while queued / picking / playing).
static func status_line(e: Dictionary) -> String:
	var st := clampi(int(e.get("status", 0)), 0, STATUS_TEXT.size() - 1)
	var line := STATUS_TEXT[st]
	var mode := int(e.get("mode", 255))
	if mode < QUEUE_NAMES.size() and st in [LobbyCodec.STATUS_IN_QUEUE, LobbyCodec.STATUS_IN_SELECT, LobbyCodec.STATUS_IN_MATCH]:
		line += " · " + QUEUE_NAMES[mode]
	return line


static func rank(status: int) -> int:
	return STATUS_RANK[clampi(status, 0, STATUS_RANK.size() - 1)]


## {friends, incoming, outgoing, blocked}; friends sorted by presence then name.
static func group(list: Array) -> Dictionary:
	var g: Dictionary = {"friends": [], "incoming": [], "outgoing": [], "blocked": []}
	var keys: Array = ["friends", "incoming", "outgoing", "blocked"]
	for e: Dictionary in list:
		var r: int = int(e.get("relation", 0))
		if r >= 0 and r < keys.size():
			(g[keys[r]] as Array).append(e)
	(g.friends as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if rank(int(a.status)) != rank(int(b.status)):
			return rank(int(a.status)) > rank(int(b.status))
		return String(a.display_name).naturalnocasecmp_to(String(b.display_name)) < 0)
	return g


## Party entries split by kind: {members (leader first), invites_in, invites_out}.
static func party_rows(state: Dictionary) -> Dictionary:
	var out: Dictionary = {"members": [], "invites_in": [], "invites_out": []}
	for e: Dictionary in state.get("members", []):
		match int(e.kind):
			AccountCodec.PARTY_LEADER:
				(out.members as Array).push_front(e)
			AccountCodec.PARTY_MEMBER:
				(out.members as Array).append(e)
			AccountCodec.PARTY_INVITE_IN:
				(out.invites_in as Array).append(e)
			AccountCodec.PARTY_INVITE_OUT:
				(out.invites_out as Array).append(e)
	return out


## Fills sample data (screenshots); nothing is sent.
func show_sample(with_invite: bool) -> void:
	preview = true
	_signed_in = true
	var me := {"id": "a".repeat(32), "kind": AccountCodec.PARTY_LEADER, "status": 1, "display_name": "Djboeck", "emblem": 0, "accent": 0}
	friends = [
		{"id": "1".repeat(32), "status": LobbyCodec.STATUS_IN_MATCH, "relation": 0, "username": "", "display_name": "Mira", "emblem": 0, "accent": 0},
		{"id": "2".repeat(32), "status": LobbyCodec.STATUS_IN_SELECT, "mode": 1, "relation": 0, "username": "", "display_name": "Kestrel", "emblem": 0, "accent": 0},
		{"id": "6".repeat(32), "status": LobbyCodec.STATUS_IN_QUEUE, "mode": 0, "relation": 0, "username": "", "display_name": "Talia", "emblem": 0, "accent": 0},
		{"id": "3".repeat(32), "status": LobbyCodec.STATUS_ONLINE, "relation": 0, "username": "", "display_name": "Juno", "emblem": 0, "accent": 0},
		{"id": "7".repeat(32), "status": LobbyCodec.STATUS_AWAY, "relation": 0, "username": "", "display_name": "Brin", "emblem": 0, "accent": 0},
		{"id": "4".repeat(32), "status": LobbyCodec.STATUS_OFFLINE, "relation": 0, "username": "", "display_name": "Oskar", "emblem": 0, "accent": 0},
		{"id": "5".repeat(32), "status": 0, "relation": 1, "username": "", "display_name": "Vex", "emblem": 0, "accent": 0},
	]
	var members: Array = [me]
	if with_invite:
		members = [{"id": "2".repeat(32), "kind": AccountCodec.PARTY_INVITE_IN, "status": 2, "display_name": "Kestrel", "emblem": 0, "accent": 0, "expires": 102}]
	else:
		members.append({"id": "3".repeat(32), "kind": AccountCodec.PARTY_MEMBER, "status": 1, "display_name": "Juno", "emblem": 0, "accent": 0, "flags": AccountCodec.PF_READY})
		members.append({"id": "1".repeat(32), "kind": AccountCodec.PARTY_INVITE_OUT, "status": 3, "display_name": "Mira", "emblem": 0, "accent": 0})
	party = {"party": "p".repeat(0), "leader": me.id, "members": members}
	_party_at = Time.get_ticks_msec() / 1000.0
	if with_invite:
		_note("Kestrel invited you to a party.")
	_paint()


func _paint() -> void:
	if _friends_box == null:
		return
	var t: UiKitTokens = UiKit.tokens()
	_out.visible = not _signed_in
	for c in [_party_box, _friends_box]:
		for k in c.get_children():
			c.remove_child(k)
			k.queue_free()
	for n in get_children():
		if n != _out:
			n.visible = _signed_in and n != _msg and n != _add_row or (n == _msg and _signed_in and _msg.text != "") \
				or (n == _add_row and _signed_in and _add_row.visible)
	if not _signed_in:
		return
	var pr: Dictionary = party_rows(party)
	_leave.visible = (pr.members as Array).size() > 0
	if (pr.members as Array).is_empty() and (pr.invites_in as Array).is_empty():
		_party_box.add_child(UiKit.label("Not in a party. Invite a friend with +.", &"small", t.text_off))
	for e: Dictionary in pr.members:
		var lead: bool = int(e.kind) == AccountCodec.PARTY_LEADER
		var tags: Array[String] = []
		if lead:
			tags.append("LEADER")
		if int(e.get("flags", 0)) & AccountCodec.PF_READY != 0:
			tags.append("READY")
		_party_box.add_child(_row(e, " · ".join(tags), [], []))
	for e: Dictionary in pr.invites_out:
		_party_box.add_child(_row(e, "INVITED" + _left(e), [], []))
	for e: Dictionary in pr.invites_in:
		if e.has("expires") and _left_s(e) <= 0:
			continue  # expired: gone at the next refresh
		_party_box.add_child(_row(e, "INVITES YOU" + _left(e), ["JOIN", func() -> void: _send(AccountCodec.OP_PARTY_ACCEPT, {"id": e.id})],
			[["Decline the invite", func() -> void: _send(AccountCodec.OP_PARTY_DECLINE, {"id": e.id})]]))
	var g: Dictionary = group(friends)
	var online: int = (g.friends as Array).filter(func(e: Dictionary) -> bool: return int(e.status) != LobbyCodec.STATUS_OFFLINE).size()
	_friends_head.text = "FRIENDS  %d/%d ONLINE" % [online, (g.friends as Array).size()]
	var in_party: Array = (pr.members as Array).map(func(e: Dictionary) -> String: return String(e.id)) \
		+ (pr.invites_out as Array).map(func(e: Dictionary) -> String: return String(e.id))
	for e: Dictionary in g.incoming:
		_friends_box.add_child(_row(e, "REQUEST", ["ACCEPT", func() -> void: _send(AccountCodec.OP_FRIEND_ACCEPT, {"id": e.id})],
			[["Decline", func() -> void: _send(AccountCodec.OP_FRIEND_DECLINE, {"id": e.id})],
			["Block", func() -> void: _send(AccountCodec.OP_BLOCK, {"id": e.id})]]))
	for e: Dictionary in g.friends:
		var primary: Array = []
		var busy: bool = int(e.status) in [LobbyCodec.STATUS_IN_QUEUE, LobbyCodec.STATUS_IN_SELECT, LobbyCodec.STATUS_IN_MATCH]
		# Busy friends keep the invite in the "..." menu: the status line needs the room.
		if int(e.status) != LobbyCodec.STATUS_OFFLINE and not busy and not in_party.has(String(e.id)):
			primary = ["+ PARTY", func() -> void: _send(AccountCodec.OP_PARTY_INVITE, {"id": e.id})]
		_friends_box.add_child(_row(e, status_line(e), primary,
			[["Invite to party", func() -> void: _send(AccountCodec.OP_PARTY_INVITE, {"id": e.id})],
			["Ask to join their party", func() -> void: _send(AccountCodec.OP_PARTY_JOIN_REQUEST, {"id": e.id})],
			["Remove friend", func() -> void: _send(AccountCodec.OP_FRIEND_REMOVE, {"id": e.id})],
			["Block", func() -> void: _send(AccountCodec.OP_BLOCK, {"id": e.id})]]))
	for e: Dictionary in g.outgoing:
		_friends_box.add_child(_row(e, "REQUEST SENT", [], [["Cancel request", func() -> void: _send(AccountCodec.OP_FRIEND_REMOVE, {"id": e.id})]]))
	for e: Dictionary in g.blocked:
		_friends_box.add_child(_row(e, "BLOCKED", [], [["Unblock", func() -> void: _send(AccountCodec.OP_UNBLOCK, {"id": e.id})]]))
	if (g.friends as Array).is_empty() and (g.incoming as Array).is_empty():
		_friends_box.add_child(UiKit.label("No friends yet. Add one by username.", &"small", t.text_off))


## One row: status dot, name over a status line, one primary action
## ([text, Callable] or []) and a "..." menu of [text, Callable] items.
func _row(e: Dictionary, sub: String, primary: Array, menu: Array) -> Control:
	var t: UiKitTokens = UiKit.tokens()
	var cols: Array = [t.text_off, t.ok, t.cyan, t.in_match, t.accent_hi, t.accent, t.warn]
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var dot: ColorRect = ColorRect.new()
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = cols[clampi(int(e.get("status", 0)), 0, cols.size() - 1)]
	row.add_child(dot)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var n: Label = UiKit.label(String(e.get("display_name", "")), &"small", t.text)
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.clip_text = true
	n.custom_minimum_size.x = 40
	v.add_child(n)
	if sub != "":
		var s: Label = UiKit.label(sub, &"small", t.accent if sub == "LEADER" else t.text_off)
		s.add_theme_font_size_override("font_size", 11)
		s.clip_text = true
		s.custom_minimum_size.x = 40
		s.tooltip_text = sub  # the full line when it is clipped
		s.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(s)
	if not primary.is_empty():
		row.add_child(_small_link(String(primary[0]), primary[1]))
	if not menu.is_empty():
		var mb: MenuButton = MenuButton.new()
		mb.text = "\u22ef"
		mb.tooltip_text = "More"
		mb.flat = true
		mb.add_theme_color_override("font_color", t.text_dim)
		mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var pm: PopupMenu = mb.get_popup()
		for i in menu.size():
			pm.add_item(String(menu[i][0]), i)
		pm.id_pressed.connect(func(id: int) -> void: (menu[id][1] as Callable).call())
		row.add_child(mb)
	return row


func _left_s(e: Dictionary) -> int:
	return ceili(float(e.get("expires", 0)) - (Time.get_ticks_msec() / 1000.0 - _party_at))


## " · 1:42" for an invite with a server expiry ("" without).
func _left(e: Dictionary) -> String:
	if not e.has("expires"):
		return ""
	var s := maxi(0, _left_s(e))
	return " · %d:%02d" % [s / 60, s % 60]


func _small_link(text: String, cb: Callable) -> Button:
	var t: UiKitTokens = UiKit.tokens()
	var b: Button = Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", t.accent)
	b.add_theme_color_override("font_hover_color", t.accent_hi)
	b.pressed.connect(cb)
	return b


func _send(op: int, fields: Dictionary = {}) -> void:
	if preview or login == null:
		return
	if not login.request(op, fields):
		_note("Sign in first.")


func _add() -> void:
	var u: String = _add_edit.text.strip_edges()
	if u == "":
		return
	_send(AccountCodec.OP_FRIEND_REQUEST, {"username": u, "id": ""})
	_add_edit.text = ""


func _note(text: String) -> void:
	_msg.text = text
	_msg.visible = text != "" and _signed_in
