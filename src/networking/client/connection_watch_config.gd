class_name ConnectionWatchConfig
extends Resource
## W21-U2: tunables of the online connection watchdog (ConnectionWatch).
## Data file: assets/data/net/connection_watch.tres.

## Seconds to wait for the UDP / DTLS link before the player is told it failed.
@export var connect_timeout_s: float = 10.0
## Seconds to wait for the login / resume / guest answer once the link is up.
@export var login_timeout_s: float = 10.0
## Seconds to wait for the first queue status after "Find match".
@export var queue_ack_timeout_s: float = 8.0

const PATH: String = "res://assets/data/net/connection_watch.tres"


## The shipped data, or the defaults when it cannot be loaded.
static func load_default() -> ConnectionWatchConfig:
	var c := load(PATH) as ConnectionWatchConfig
	return c if c != null else ConnectionWatchConfig.new()
