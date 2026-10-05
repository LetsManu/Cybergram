class_name LaunchHandoff
extends RefCounted
## Launcher -> game hand-over (W15 "sign in once"). The launcher passes a
## single-use launch token (LaunchTokenStore) to the game it starts through
## the child's ENVIRONMENT, never the command line (other users can read
## process command lines) and never a password or the launcher's own session
## token. The game reads the variables once at start and unsets them so
## nothing it starts inherits them. A token is worth nothing after 60 s or
## after its first use. Also carries the Discord presence opt-in (not a secret).
## Shared with the launcher (launcher/tools/shared_files.txt).

const ENV_TOKEN := "CYBERGRAM_LAUNCH_TOKEN"
const ENV_SERVER := "CYBERGRAM_LAUNCH_SERVER"
const ENV_ACCOUNT := "CYBERGRAM_LAUNCH_ACCOUNT"
## "1" when the player opted in to Discord Rich Presence in the launcher.
const ENV_PRESENCE := "CYBERGRAM_DISCORD_PRESENCE"
## The hand-over variables that carry a credential (cleared after use).
const SECRET_KEYS: Array[String] = [ENV_TOKEN, ENV_SERVER, ENV_ACCOUNT]


## {token, server, account} from `env` (name -> value), or {} when anything is
## missing or malformed: token = 64 hex chars, account = 32 hex chars,
## server = "host:port".
static func parse(env: Dictionary) -> Dictionary:
	var tok := str(env.get(ENV_TOKEN, "")).strip_edges().to_lower()
	var acc := str(env.get(ENV_ACCOUNT, "")).strip_edges().to_lower()
	var srv := str(env.get(ENV_SERVER, "")).strip_edges()
	if tok.length() != 64 or not tok.is_valid_hex_number() or acc.length() != 32 or not acc.is_valid_hex_number():
		return {}
	var hp := srv.rsplit(":", true, 1)
	if hp.size() != 2 or hp[0] == "" or not hp[1].is_valid_int() or srv.length() > 255:
		return {}
	return {"token": tok, "server": srv, "account": acc}


## Reads the hand-over from this process's environment and unsets the
## credential variables. {} when the launcher passed nothing usable.
static func take_from_os() -> Dictionary:
	var env := {}
	for k in SECRET_KEYS:
		if OS.has_environment(k):
			env[k] = OS.get_environment(k)
		OS.unset_environment(k)
	return parse(env)


## True when the launcher passed the Discord presence opt-in.
static func presence_opted_in() -> bool:
	return OS.get_environment(ENV_PRESENCE) == "1"


## Launcher: puts `h` ({token, server, account}) into this process's
## environment so the child started next inherits it. Call clear_os() right
## after starting the child. False (nothing set) when `h` is incomplete.
static func put_into_os(h: Dictionary) -> bool:
	var env := {ENV_TOKEN: str(h.get("token", "")), ENV_SERVER: str(h.get("server", "")),
		ENV_ACCOUNT: str(h.get("account", ""))}
	if parse(env).is_empty():
		return false
	for k: String in env:
		OS.set_environment(k, env[k])
	return true


## Launcher: removes the credential variables from its own environment.
static func clear_os() -> void:
	for k in SECRET_KEYS:
		OS.unset_environment(k)
