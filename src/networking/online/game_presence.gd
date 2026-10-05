class_name GamePresence
extends Node
## Discord Rich Presence for the running game (W15, PRIVACY.md "Discord Rich
## Presence"). Opt-in: active only when the launcher passed the player's
## opt-in (LaunchHandoff.presence_opted_in) AND a Discord application id is
## configured (PresenceDef). Shows only "In launcher", "In lobby" or
## "In match (<mode>)": never names, ids or the server address. Talks only to
## the local Discord app (DiscordRichPresence, vendored); fails silently when
## Discord is not running or on headless servers.
##
## Example: GamePresence.show_state(GamePresence.State.IN_LOBBY)

enum State { IN_LAUNCHER, IN_LOBBY, IN_MATCH }

## Mode labels that may appear (anything else shows as plain "In match").
const MODES: Array[String] = ["Online", "vs Bots", "Quick 3v3", "Practice", "Tutorial", "Test course"]

static var _shared: GamePresence

var enabled: bool = false
var _rpc: Node
var _start_unix: int = 0


## Sets the presence (no-op when not opted in). Creates the node on first use.
static func show_state(state: State, mode: String = "") -> void:
	var p := shared()
	if p != null:
		p.apply(state, mode)


## The process-wide node (attached to the scene root), or null without a tree.
static func shared() -> GamePresence:
	if _shared != null and is_instance_valid(_shared):
		return _shared
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_shared = GamePresence.new()
	_shared.name = "GamePresence"
	_shared.setup(LaunchHandoff.presence_opted_in(), PresenceDef.load_default())
	tree.root.add_child.call_deferred(_shared)
	return _shared


## Turns the client on when opted in and configured.
func setup(opted_in: bool, def: PresenceDef) -> void:
	enabled = opted_in and def != null and def.discord_app_id.strip_edges().is_valid_int()
	if not enabled:
		return
	var script := load("res://addons/discord_rich_presence/discord_rich_presence.gd") as Script
	if script == null:
		enabled = false
		return
	_rpc = script.new()
	_rpc.set("app_id", def.discord_app_id.strip_edges())
	add_child(_rpc)
	_large_image = def.large_image


var _large_image: String = ""


func apply(state: State, mode: String = "") -> void:
	if not enabled or _rpc == null:
		return
	if state == State.IN_MATCH:
		_start_unix = int(Time.get_unix_time_from_system())
	_rpc.call("set_activity", activity_for(state, mode, _start_unix if state == State.IN_MATCH else 0, _large_image))


## The SET_ACTIVITY object: only the state text, an optional match start time
## and the art key. Pure, so tests can check nothing personal is in it.
static func activity_for(state: State, mode: String, start_unix: int = 0, large_image: String = "") -> Dictionary:
	var a := {}
	match state:
		State.IN_LOBBY:
			a.details = "In lobby"
		State.IN_MATCH:
			a.details = "In match (%s)" % mode if mode in MODES else "In match"
			if start_unix > 0:
				a.timestamps = {"start": start_unix}
		_:
			a.details = "In launcher"
	if large_image != "":
		a.assets = {"large_image": large_image, "large_text": "Cybergram"}
	return a


## The mode label for a game start (`args` as MainMenu passes them).
static func mode_of(args: PackedStringArray) -> String:
	if args.has("--connect") or args.has("--token"):
		return "Online"
	var i := args.find("--map")
	if i >= 0 and i + 1 < args.size() and args[i + 1] == PracticeRange.MAP and PracticeRange.active:
		return "Tutorial" if PracticeRange.tutorial_requested else "Practice"
	if i >= 0 and i + 1 < args.size():
		if args[i + 1] == "slice":
			return "Quick 3v3"
		if args[i + 1] == "test_course":
			return "Test course"
	return "vs Bots"
