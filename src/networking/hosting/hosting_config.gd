class_name HostingConfig
extends RefCounted
## Match hosting settings (W17), from environment variables with defaults
## (design/gdd/matchmaking.md "Hosting"). No path or address is specific to one
## machine: everything a VPS or a NAS needs differently is an env var.
##
##   CYBERGRAM_PUBLIC_HOST     address handed to clients ("" = the address the
##                             client used to reach the front)
##   CYBERGRAM_BIND_HOST       address match processes bind (default "*")
##   CYBERGRAM_MATCH_PORTS     UDP range "first-last" (default 7800-7809)
##   CYBERGRAM_MAX_MATCHES     concurrent matches (0/unset = matches_per_core x cores)
##   CYBERGRAM_MATCHES_PER_CORE  (default 2; a 5v5 is about 22 % of a core)
##   CYBERGRAM_WARM_POOL       Ready processes kept waiting (default 1, max 2)
##   CYBERGRAM_BUILD_VERSION   build tag of the processes this front spawns
##   CYBERGRAM_DRAIN_MAX_S     longest graceful drain in seconds (default 3600)
##   CYBERGRAM_DRAIN_FILE      drain request file (the entrypoint touches it on SIGTERM)
##   CYBERGRAM_HEALTH_FILE     status file rewritten every few seconds (Docker HEALTHCHECK)
## Later these defaults move into MatchmakingRulesDef; the env vars stay as overrides.

const DEFAULT_PORT_FIRST := 7800
const DEFAULT_PORT_LAST := 7809
const MAX_WARM_POOL := 2

var public_host: String = ""
var bind_host: String = "*"
var port_first: int = DEFAULT_PORT_FIRST
var port_last: int = DEFAULT_PORT_LAST
## Explicit cap (0 = derived from cores).
var max_matches: int = 0
var matches_per_core: int = 2
var cores: int = 1
var warm_pool: int = 1
var build_version: String = "dev"
var drain_max_s: float = 3600.0
var drain_file: String = ""
var health_file: String = ""
## Heartbeat: the process sends one every interval; silence for timeout = dead.
var heartbeat_interval_s: float = 1.0
var heartbeat_timeout_s: float = 6.0
## A spawned process must report Ready within this.
var start_timeout_s: float = 30.0
## An allocated process must confirm its match setup within this.
var allocate_timeout_s: float = 10.0
## After its result a process must exit within this (then it is killed).
var exit_grace_s: float = 15.0
## Join ticket lifetime.
var ticket_ttl_s: float = 15.0


## Concurrent match processes allowed: the explicit or core-derived cap,
## never more than the port range holds.
func capacity() -> int:
	var cap := max_matches if max_matches > 0 else maxi(1, matches_per_core * cores)
	return mini(cap, port_count())


func port_count() -> int:
	return maxi(0, port_last - port_first + 1)


## Parses "7800-7809" (or a single "7800"). [] when malformed.
static func parse_port_range(text: String) -> Array:
	var p := text.strip_edges().split("-")
	if p.size() < 1 or p.size() > 2:
		return []
	var a_s := p[0].strip_edges()
	var b_s := p[p.size() - 1].strip_edges()
	if not a_s.is_valid_int() or not b_s.is_valid_int():
		return []
	var a := a_s.to_int()
	var b := b_s.to_int()
	if a < 1024 or b > 65535 or b < a:
		return []
	return [a, b]


## Reads `env` (name -> value); an empty dictionary reads the process
## environment. Bad values keep the default and are reported in `errors`.
static func from_env(env: Dictionary = {}, cores_: int = -1) -> HostingConfig:
	var c := HostingConfig.new()
	var use_os := env.is_empty()
	var g := func(k: String) -> String:
		return (OS.get_environment(k) if use_os else str(env.get(k, ""))).strip_edges()
	c.cores = cores_ if cores_ > 0 else OS.get_processor_count()
	c.public_host = g.call("CYBERGRAM_PUBLIC_HOST")
	if g.call("CYBERGRAM_BIND_HOST") != "":
		c.bind_host = g.call("CYBERGRAM_BIND_HOST")
	if g.call("CYBERGRAM_MATCH_PORTS") != "":
		var r := parse_port_range(g.call("CYBERGRAM_MATCH_PORTS"))
		if r.is_empty():
			push_warning("[hosting] CYBERGRAM_MATCH_PORTS is malformed; using %d-%d" % [c.port_first, c.port_last])
		else:
			c.port_first = r[0]
			c.port_last = r[1]
	if str(g.call("CYBERGRAM_MAX_MATCHES")).is_valid_int():
		c.max_matches = clampi(str(g.call("CYBERGRAM_MAX_MATCHES")).to_int(), 0, 256)
	if str(g.call("CYBERGRAM_MATCHES_PER_CORE")).is_valid_int():
		c.matches_per_core = clampi(str(g.call("CYBERGRAM_MATCHES_PER_CORE")).to_int(), 1, 16)
	if str(g.call("CYBERGRAM_WARM_POOL")).is_valid_int():
		c.warm_pool = clampi(str(g.call("CYBERGRAM_WARM_POOL")).to_int(), 0, MAX_WARM_POOL)
	if g.call("CYBERGRAM_BUILD_VERSION") != "":
		c.build_version = str(g.call("CYBERGRAM_BUILD_VERSION")).left(32)
	if str(g.call("CYBERGRAM_DRAIN_MAX_S")).is_valid_float():
		c.drain_max_s = clampf(str(g.call("CYBERGRAM_DRAIN_MAX_S")).to_float(), 0.0, 86400.0)
	c.drain_file = g.call("CYBERGRAM_DRAIN_FILE")
	c.health_file = g.call("CYBERGRAM_HEALTH_FILE")
	return c
