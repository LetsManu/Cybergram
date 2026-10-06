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
## P1 status bar: seconds online without any state from the server before
## the bar says so (and the client asks for a resync).
@export var phase_timeout_s: float = 10.0
## P1 status bar: a queue wait longer than estimate x this shows a hint.
@export var long_wait_factor: float = 2.0
## P1 status bar: seconds in Loading before the bar explains the delay.
@export var loading_hint_s: float = 45.0

const PATH: String = "res://assets/data/net/connection_watch.tres"


## The shipped data, or the defaults when it cannot be loaded.
static func load_default() -> ConnectionWatchConfig:
	var c := load(PATH) as ConnectionWatchConfig
	return c if c != null else ConnectionWatchConfig.new()
