class_name MmStatusModel
extends RefCounted
## P1: what the persistent status bar shows (view-model, no nodes, testable
## headless). Fed by the client adapter: the server's PHASE events, the
## connection state and ping; `view(now)` returns the texts to draw.
##
## No endless spinners: every waiting phase has a limit after which the bar
## explains what is going on (`hint`) and, where the player can do something,
## what. Limits come from ConnectionWatchConfig.
##
## Example:
##   model.set_phase({"phase": PhaseMachine.Player.QUEUED, "waited": 12, "estimate": 60}, now)
##   var v := model.view(now)   # {connection, ping, phase, timer, lockout, hint, tone}

enum Conn { CONNECTING, ONLINE, LOST }

const PHASE_KEYS := ["HUD_MMS_PH_OFFLINE", "HUD_MMS_PH_IDLE", "HUD_MMS_PH_PARTY", "HUD_MMS_PH_QUEUED",
	"HUD_MMS_PH_READY", "HUD_MMS_PH_SELECT", "HUD_MMS_PH_LOADING", "HUD_MMS_PH_INGAME", "HUD_MMS_PH_POST",
	"HUD_MMS_PH_RECONNECT"]

var config: ConnectionWatchConfig
var conn: Conn = Conn.CONNECTING
var rtt_ms: int = -1
## Last PHASE event (MatchmakingClient fields) and the local time it arrived.
var phase: Dictionary = {}
var phase_at: float = 0.0
var _conn_since: float = 0.0


func _init(config_: ConnectionWatchConfig = null) -> void:
	config = config_ if config_ != null else ConnectionWatchConfig.load_default()


func set_connection(state: Conn, now: float, rtt: int = -1) -> void:
	if state != conn:
		_conn_since = now
	conn = state
	rtt_ms = rtt


func set_phase(d: Dictionary, now: float) -> void:
	phase = d
	phase_at = now


## Texts for the bar. Keys are HUD string keys (tr() by the view) plus
## numbers; `tone` = &"ok" | &"busy" | &"warn" | &"error".
func view(now: float) -> Dictionary:
	var v := {"connection": "", "ping": "", "phase": "", "timer": "", "lockout": "", "hint": "", "tone": &"ok"}
	match conn:
		Conn.CONNECTING:
			v.connection = "HUD_MMS_CONN_CONNECTING"
			v.tone = &"busy"
			if now - _conn_since > config.connect_timeout_s:
				v.hint = "HUD_MMS_HINT_NO_SERVER"
				v.tone = &"error"
		Conn.LOST:
			v.connection = "HUD_MMS_CONN_LOST"
			v.hint = "HUD_MMS_HINT_RECONNECTING"
			v.tone = &"error"
		Conn.ONLINE:
			v.connection = "HUD_MMS_CONN_ONLINE"
			if rtt_ms >= 0:
				v.ping = "%d ms" % rtt_ms
	if phase.is_empty():
		if conn == Conn.ONLINE and now - _conn_since > config.phase_timeout_s:
			v.hint = "HUD_MMS_HINT_NO_STATE"
			v.tone = &"warn"
		return v
	var ph := int(phase.get("phase", 0))
	v.phase = PHASE_KEYS[ph] if ph >= 0 and ph < PHASE_KEYS.size() else ""
	var since := now - phase_at
	var P := PhaseMachine.Player
	match ph:
		P.QUEUED:
			var waited := float(phase.get("waited", 0)) + since
			var est := float(phase.get("estimate", 0))
			v.timer = clock(waited) + ("  ~" + clock(est) if est > 0.0 else "")
			if v.tone == &"ok":
				v.tone = &"busy"
			if est > 0.0 and waited > est * config.long_wait_factor:
				v.hint = "HUD_MMS_HINT_LONG_WAIT"
		P.READY_CHECK, P.CHAMP_SELECT:
			if v.tone == &"ok":
				v.tone = &"busy"
		P.LOADING:
			v.timer = clock(since)
			if since > config.loading_hint_s:
				v.hint = "HUD_MMS_HINT_LOADING_SLOW"
				v.tone = &"warn"
		P.RECONNECTING:
			v.hint = "HUD_MMS_HINT_RECONNECTING"
			v.tone = &"warn"
	var locked := float(phase.get("locked", 0)) - since
	if locked > 0.0:
		v.lockout = clock(locked)
		if v.hint == "":
			v.hint = "HUD_MMS_HINT_LOCKED"
		if v.tone == &"ok":
			v.tone = &"warn"
	return v


## "m:ss" (or "h:mm:ss").
static func clock(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
