class_name AccountAdmin
extends RefCounted
## Host-side password reset (W21-N1, docs/HOSTING.md "Resetting a player's
## password"). The admin tool (account_admin_cli.gd) never edits an account
## file itself: the running server caches every account in memory and writes
## the whole record back on many paths (logins, friend requests from other
## players, the leaderboard opt-in), so a file changed behind its back would
## silently be overwritten with the old password hash. Instead the tool drops
## a request into the admin folder (AuthConfig.admin_dir(), Docker:
## /data/admin) and the server, the only writer of account files, applies it
## within AuthRulesDef.admin_poll_s (AccountService.step()) and answers with
## a result file. A request left while no server runs is applied at its next
## start.
##
## The request carries the username and the PBKDF2 hash of a fresh recovery
## code, never the code itself, never a password. The tool prints the code
## once; the player then sets a new password with "Forgot password?".
##
## Files (owner-only, written atomically): `<id>.req.json` (tool -> server),
## `<id>.work` (claimed by a server), `<id>.done.json` (server -> tool).

const REQ_SUFFIX := ".req.json"
const WORK_SUFFIX := ".work"
const DONE_SUFFIX := ".done.json"
const OP_RESET := "reset_password"
const VERSION := 1


## A reset request for `username` with a fresh recovery code. Returns
## {code: plaintext (show once), request: Dictionary (hash only)}. Runs one
## PBKDF2 (AuthRulesDef.pbkdf2_iterations) on the calling thread: tool only.
static func make_reset(username: String, rules: AuthRulesDef, now_unix: int) -> Dictionary:
	var code := RecoveryCode.generate(rules)
	var salt := Crypto.new().generate_random_bytes(rules.salt_bytes)
	var canon := RecoveryCode.normalize(code, rules)
	var h := Pbkdf2.derive(canon.to_utf8_buffer(), salt, rules.pbkdf2_iterations, Pbkdf2.HLEN)
	return {"code": code, "request": {"v": VERSION, "op": OP_RESET, "username": username,
		"recovery": RecoveryCode.record(h, salt, rules.pbkdf2_iterations, now_unix), "requested_at": now_unix}}


## Writes `request` into `dir` (created owner-only when missing). Returns the
## request id, or "" when it could not be written.
static func submit(dir: String, request: Dictionary) -> String:
	var d := _abs(dir)
	if DirAccess.make_dir_recursive_absolute(d) != OK and not DirAccess.dir_exists_absolute(d):
		return ""
	FileAccountStore._owner_only(d, FileAccountStore.DIR_MODE)
	var id := PlayerProfile.random_hex(8)
	return id if _write_atomic(d.path_join(id + REQ_SUFFIX), JSON.stringify(request, "\t")) else ""


## Waits up to `timeout_s` for the server's answer to request `id`; returns
## it ({ok, error, tag}) and removes the file, or {} on timeout (the request
## stays queued). Blocking: tool only.
static func wait_result(dir: String, id: String, timeout_s: float) -> Dictionary:
	var path := _abs(dir).path_join(id + DONE_SUFFIX)
	var waited := 0
	while not FileAccess.file_exists(path):
		if waited >= int(timeout_s * 1000.0):
			return {}
		OS.delay_msec(100)
		waited += 100
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(path)
	return data if data is Dictionary else {"ok": false, "error": "unreadable result"}


## True when request `id` is still waiting for a server.
static func is_queued(dir: String, id: String) -> bool:
	return FileAccess.file_exists(_abs(dir).path_join(id + REQ_SUFFIX))


## Server side: claims every waiting request (rename to .work, so two
## processes never apply the same one) and returns [{id, request}]. A
## malformed file is claimed too and comes back with request {}.
static func take_requests(dir: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := _abs(dir)
	if not DirAccess.dir_exists_absolute(d):
		return out
	for f in DirAccess.get_files_at(d):
		if not f.ends_with(REQ_SUFFIX):
			continue
		var id := f.trim_suffix(REQ_SUFFIX)
		var work := d.path_join(id + WORK_SUFFIX)
		if DirAccess.rename_absolute(d.path_join(f), work) != OK:
			continue  # another process took it
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(work))
		DirAccess.remove_absolute(work)
		out.append({"id": id, "request": data if data is Dictionary else {}})
	return out


## Server side: the answer for request `id` (`result` = {ok, error, tag}).
static func write_result(dir: String, id: String, result: Dictionary) -> void:
	_write_atomic(_abs(dir).path_join(id + DONE_SUFFIX), JSON.stringify(result))


## True when `req` is a well-formed reset request (hash record only).
static func is_valid_reset(req: Dictionary) -> bool:
	if int(req.get("v", 0)) != VERSION or str(req.get("op", "")) != OP_RESET:
		return false
	if not (req.get("username") is String) or not (req.get("recovery") is Dictionary):
		return false
	var rec: Dictionary = req.recovery
	var h := str(rec.get("hash", ""))
	return h.length() == Pbkdf2.HLEN * 2 and _is_hex(h) and _is_hex(str(rec.get("salt", ""))) \
		and int(rec.get("iterations", 0)) >= 1000


static func _is_hex(s: String) -> bool:
	if s == "" or s.length() % 2 != 0:
		return false
	for c in s.to_lower():
		if not "0123456789abcdef".contains(c):
			return false
	return true


## Tool side: the account with `username` read straight from the account
## files, without any side effect (FileAccountStore.open() also tidies the
## folder, which must not race the running server). {} when there is none.
static func find_username_readonly(data_dir: String, username: String) -> Dictionary:
	var d := _abs(data_dir)
	if not DirAccess.dir_exists_absolute(d):
		return {}
	var want := username.to_lower()
	for f in DirAccess.get_files_at(d):
		if not f.ends_with(".json"):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(d.path_join(f)))
		if data is Dictionary and str((data as Dictionary).get("username", "")).to_lower() == want:
			return data
	return {}


static func _write_atomic(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	FileAccountStore._owner_only(tmp, FileAccountStore.FILE_MODE)
	f.store_string(text)
	f.flush()
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	return true


static func _abs(p: String) -> String:
	return FileAccountStore._abs(p)
