class_name PublicSnapshot
extends RefCounted
## W20-WEB: the front's public, read-only snapshot for the website
## (web/, docs/HOSTING.md "Website"). The front writes one JSON file every
## OnlineRulesDef.public_snapshot_every_s into CYBERGRAM_PUBLIC_DIR (a volume
## shared with the web container, which serves it as /data/snapshot.json).
## No HTTP server runs in the game: a file is the smallest, most robust API.
##
## Contents (schema 1):
##   {schema, updated (unix s), status ("up" / "draining"), build,
##    players_online, matches_running, matches_forming,
##    queues: [{id, name, players, estimated_wait_s}],
##    leaderboard: {updated, entries: [{rank, name, rating, medal, band}]}}
## Privacy (PRIVACY.md): counts only, plus display names and ranked ratings
## of accounts that opted in (AccountService.is_leaderboard_public). Never
## account ids, usernames, IPs or anything about players who did not opt in.
## The leaderboard is recomputed every public_leaderboard_every_s, so an
## opt-out or a deleted account leaves the file within that time.
##
## The file is replaced atomically (temp file + rename), so the web server
## never serves half a file. A stale `updated` means the front is down.
##
## Example (FrontServer):
##   var snap := PublicSnapshot.new()          # reads CYBERGRAM_PUBLIC_DIR
##   snap.tick(delta, front, accounts.peers.size())

const ENV_DIR: String = "CYBERGRAM_PUBLIC_DIR"
const FILE_NAME: String = "snapshot.json"
const SCHEMA: int = 1

var dir: String = ""
var rules: OnlineRulesDef
var _since: float = 1.0e9
var _since_board: float = 1.0e9
var _board: Array = []
var _board_at: int = 0


## `dir_` empty reads the environment variable (empty there too = disabled).
func _init(dir_: String = "", rules_: OnlineRulesDef = null) -> void:
	dir = dir_ if dir_ != "" else OS.get_environment(ENV_DIR).strip_edges()
	rules = rules_ if rules_ != null else OnlineRulesDef.load_default()


## True when a target directory is configured.
func enabled() -> bool:
	return dir != ""


## The output file path ("" when disabled).
func path() -> String:
	return dir.path_join(FILE_NAME) if enabled() else ""


## Call every front frame. Writes when public_snapshot_every_s passed;
## recomputes the leaderboard every public_leaderboard_every_s. Returns true
## when a file write happened.
func tick(delta: float, front: MatchmakingFront, players_online: int) -> bool:
	if not enabled() or front == null:
		return false
	_since += delta
	_since_board += delta
	if _since < rules.public_snapshot_every_s:
		return false
	_since = 0.0
	var now_unix := int(front.now())
	if _since_board >= rules.public_leaderboard_every_s:
		_since_board = 0.0
		_board = front.leaderboard(rules.public_leaderboard_size)
		_board_at = now_unix
	return write_now(JSON.stringify(build(front, players_online, now_unix, _board, _board_at)))


## The snapshot Dictionary (static, unit tested). `board` is a
## MatchmakingFront.leaderboard() result computed at `board_at`.
static func build(front: MatchmakingFront, players_online: int, now_unix: int, board: Array,
		board_at: int) -> Dictionary:
	var status := "up"
	var build_tag := ""
	var sup: Variant = front.supervisor
	if sup != null and sup is Object and (sup as Object).has_method("status"):
		var st: Dictionary = (sup as Object).call("status")
		build_tag = str(st.get("build", ""))
		if bool(st.get("draining", false)):
			status = "draining"
	return {"schema": SCHEMA, "updated": now_unix, "status": status, "build": build_tag,
		"players_online": maxi(0, players_online), "matches_running": front.running_matches(),
		"matches_forming": front.forming_matches(), "queues": front.queue_overview(),
		"leaderboard": {"updated": board_at, "entries": board}}


## Atomically replaces the snapshot with `text`. False on any I/O error (the
## front keeps running; a missing snapshot only shows "down" on the website).
func write_now(text: String) -> bool:
	if not enabled():
		return false
	if not DirAccess.dir_exists_absolute(dir) and DirAccess.make_dir_recursive_absolute(dir) != OK:
		return false
	var target := path()
	var tmp := target + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if DirAccess.rename_absolute(tmp, target) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	return true
