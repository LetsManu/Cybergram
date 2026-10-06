class_name PartyService
extends RefCounted
## Parties (W15): a leader plus members, built from friends' invites. Memory
## only (PRIVACY.md "Party"). Kept deliberately simple so the later
## matchmaking wave can extend it (queue as a party, ready checks): a party is
## {id, leader, members}; every account is in at most one party; an invite
## puts the invitee into the inviter's party (created on the first accept).
## The server seats party members on the same lobby team (LobbyServer).
## Time is injected (`now` in seconds).

const OK := 0
const E_BAD := 1
const E_FULL := 2
const E_NO_INVITE := 3
## P2: not the leader / not in that party.
const E_NOT_ALLOWED := 4

var max_size: int = 3
var invite_ttl_s: float = 120.0
var parties: Dictionary = {}    # party id -> {leader: String, members: Array[String]}
var member_of: Dictionary = {}  # account id -> party id
var invites: Dictionary = {}    # invitee id -> {inviter id: expires (s)}
## P2: members who marked themselves ready (account id -> true); cleared for
## the whole party whenever its members change.
var ready: Dictionary = {}
var _crypto := Crypto.new()


func _init(max_size_: int = 3, invite_ttl_s_: float = 120.0) -> void:
	max_size = max_size_
	invite_ttl_s = invite_ttl_s_


## `from` invites `to` (the caller checked that they are friends).
func invite(from: String, to: String, now: float) -> int:
	if from == to or from == "" or to == "":
		return E_BAD
	var pid: String = member_of.get(from, "")
	if pid != "" and pid == member_of.get(to, ""):
		return OK  # already together
	if pid != "" and (parties[pid].members as Array).size() >= max_size:
		return E_FULL
	(invites.get_or_add(to, {}) as Dictionary)[from] = now + invite_ttl_s
	return OK


## `me` accepts the invite of `inviter`: joins the inviter's party.
func accept(me: String, inviter: String, now: float) -> int:
	var mine: Dictionary = invites.get(me, {})
	if not mine.has(inviter) or now > float(mine[inviter]):
		mine.erase(inviter)
		return E_NO_INVITE
	var pid: String = member_of.get(inviter, "")
	if pid != "" and (parties[pid].members as Array).size() >= max_size:
		return E_FULL
	mine.erase(inviter)
	if pid != "" and pid == member_of.get(me, ""):
		return OK
	leave(me)
	if pid == "":
		pid = _crypto.generate_random_bytes(16).hex_encode()
		parties[pid] = {"leader": inviter, "members": [inviter]}
		member_of[inviter] = pid
	(parties[pid].members as Array).append(me)
	member_of[me] = pid
	_clear_ready(pid)
	return OK


func decline(me: String, inviter: String) -> int:
	(invites.get(me, {}) as Dictionary).erase(inviter)
	return OK


## Leaves the party; a leaving leader hands over to the longest member; a
## party of one is dissolved. Also drops the account's open invites.
func leave(me: String) -> void:
	var pid: String = member_of.get(me, "")
	member_of.erase(me)
	ready.erase(me)
	for k in invites:
		(invites[k] as Dictionary).erase(me)  # an invite from someone who left is stale
	if pid == "" or not parties.has(pid):
		return
	var p: Dictionary = parties[pid]
	(p.members as Array).erase(me)
	_clear_ready(pid)
	if (p.members as Array).size() <= 1:
		for m in p.members:
			member_of.erase(m)
		parties.erase(pid)
		return
	if p.leader == me:
		p.leader = p.members[0]


## P2: the leader hands leadership to member `to`.
func promote(leader: String, to: String) -> int:
	var pid: String = member_of.get(leader, "")
	if pid == "" or parties[pid].leader != leader or member_of.get(to, "") != pid or to == leader:
		return E_NOT_ALLOWED
	parties[pid].leader = to
	return OK


## P2: the leader removes member `who` (who may join again only by a new invite).
func kick(leader: String, who: String) -> int:
	var pid: String = member_of.get(leader, "")
	if pid == "" or parties[pid].leader != leader or member_of.get(who, "") != pid or who == leader:
		return E_NOT_ALLOWED
	leave(who)
	return OK


## P2: a member marks itself ready (or not). Only inside a party.
func set_ready(me: String, on: bool) -> int:
	if member_of.get(me, "") == "":
		return E_NOT_ALLOWED
	if on:
		ready[me] = true
	else:
		ready.erase(me)
	return OK


func _clear_ready(pid: String) -> void:
	if parties.has(pid):
		for m in parties[pid].members:
			ready.erase(m)


## Forgets an account completely (no session left, account deleted).
func forget(me: String) -> void:
	leave(me)
	invites.erase(me)
	for k in invites:
		(invites[k] as Dictionary).erase(me)


## {party, leader, members, invites_in, invites_out} for `me` ("" / [] when none).
func state_of(me: String, now: float) -> Dictionary:
	purge(now)
	var pid: String = member_of.get(me, "")
	var p: Dictionary = parties.get(pid, {})
	var out_inv: Array = []
	for invitee in invites:
		if (invites[invitee] as Dictionary).has(me):
			out_inv.append(invitee)
	return {"party": pid, "leader": str(p.get("leader", "")), "members": (p.get("members", []) as Array).duplicate(),
		"invites_in": (invites.get(me, {}) as Dictionary).keys(), "invites_out": out_inv}


## The other members of `me`'s party.
func mates_of(me: String) -> Array:
	var pid: String = member_of.get(me, "")
	if pid == "":
		return []
	return (parties[pid].members as Array).filter(func(m: String) -> bool: return m != me)


## Accounts in any party (session cleanup).
func members() -> Array:
	return member_of.keys()


func purge(now: float) -> void:
	for k in invites.keys():
		var d: Dictionary = invites[k]
		for f in d.keys():
			if now > float(d[f]):
				d.erase(f)
		if d.is_empty():
			invites.erase(k)
