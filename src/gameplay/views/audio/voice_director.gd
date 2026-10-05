class_name VoiceDirector
extends Node
## W21-A1: the announcer (design/audio/audio-events.md §Announcer). Derives
## lines from ClientWorld signals / state (MatchCallouts), schedules them
## (AnnouncerQueue) and plays each as a synth stinger + the recorded voice line
## when its file exists, on the Voice bus, with a HUD toast (tr() text).
## Created by ClientSfx in a match; a no-op headless.

signal announced(line: StringName, text_key: String, priority: int)

const DEF_PATH := "res://assets/data/audio/announcer.tres"

var def: AnnouncerDef
var queue: AnnouncerQueue
var callouts: MatchCallouts
## Player for the stinger / voice events (ClientSfx shares its own).
var events: AudioEvents
var client: Node
var enabled: bool = true
## Callable() -> float seconds (tests inject a clock).
var clock_fn: Callable = func() -> float: return Time.get_ticks_msec() / 1000.0
var _playing: Array[Node] = []
var _poll: float = 0.0
var _toast: Label
var _toast_left: float = 0.0


func _init(announcer_def: AnnouncerDef = null, headless: bool = DisplayServer.get_name() == "headless") -> void:
	def = announcer_def if announcer_def != null else load(DEF_PATH) as AnnouncerDef
	queue = AnnouncerQueue.new(def)
	callouts = MatchCallouts.new(def)
	enabled = not headless


func _ready() -> void:
	set_process(enabled)
	if not enabled:
		return
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 120.0
	_toast.offset_left = -400.0
	_toast.offset_right = 400.0
	_toast.add_theme_font_size_override("font_size", 30)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	layer.add_child(_toast)


## Follows a ClientWorld (duck-typed signals: kill_received, hardpoint_owner_changed,
## match_phase_changed, match_ended; state: match_state, own_team(), hero_id_of()).
func bind_client(c: Node) -> void:
	if not enabled:
		return
	client = c
	c.kill_received.connect(func(e: GameEvent) -> void:
		var hero: bool = c.hero_id_of(e.source_net_id) != &"" or e.source_net_id == c.session.own_net_id
		say_all(callouts.on_kill(e.target_net_id, e.source_net_id, hero, _now())))
	c.hardpoint_owner_changed.connect(func(_i: int, old_team: int, new_team: int) -> void:
		say_all(callouts.on_hardpoint(old_team, new_team, c.own_team())))
	c.match_phase_changed.connect(func(phase: int) -> void: say_all(callouts.on_phase(phase)))
	c.match_ended.connect(func(winner: int, _r: int) -> void: say_all(callouts.on_match_end(winner, c.own_team())))


## Offers one line (MatchCallouts names; unknown ids are ignored).
func say(line: StringName) -> void:
	if enabled:
		queue.push(line, _now())


func say_all(lines: Array[StringName]) -> void:
	for l in lines:
		say(l)


func _now() -> float:
	return clock_fn.call()


func _process(delta: float) -> void:
	_poll += delta
	if _poll >= 0.25 and client != null:
		_poll = 0.0
		_sample_state()
	var now := _now()
	if queue.interrupt_requested:
		for p in _playing:
			if is_instance_valid(p):
				p.call("stop")
		_playing.clear()
		queue.interrupt_requested = false
	var line := queue.next(now)
	if line != &"":
		_play(line, now)
	if _toast != null and _toast_left > 0.0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left / 0.4, 0.0, 1.0)
		_toast.visible = _toast_left > 0.0


func _sample_state() -> void:
	var ms = client.match_state
	if ms == null:
		return
	if ms.next_phase_s >= 0.0:
		say_all(callouts.on_clock(ms.phase, ms.next_phase_s - ms.time_s))
	var u = client.uplink_state(client.own_team())
	if u != null:
		say_all(callouts.on_uplink(u.integrity, u.max_integrity))


func _play(line: StringName, now: float) -> void:
	var info: Dictionary = def.lines.get(line, {})
	var length := 0.0
	_playing.clear()
	if events != null:
		for key in ["stinger", "voice"]:
			var p: Node = events.play(StringName(info.get(key, &"")))
			if p != null:
				_playing.append(p)
				var s: AudioStream = p.get("stream")
				if s != null:
					length = maxf(length, s.get_length())
	queue.started(line, now, length if length > 0.0 else def.line_s)
	var key := String(info.get("text", ""))
	if _toast != null and key != "":
		_toast.text = tr(key)
		_toast.visible = true
		_toast.modulate.a = 1.0
		_toast_left = def.toast_s
	announced.emit(line, key, queue.priority_of(line))
