class_name AnnouncerQueue
extends RefCounted
## W21-A1: announcer line scheduling (pure logic; VoiceDirector plays it).
## Rules (audio direction spec §7, values in AnnouncerDef):
##  * queue of at most queue_max lines, highest priority first (then oldest);
##    when full the lowest-priority line is dropped;
##  * a queued line older than max_wait_s is dropped;
##  * a pending line listed in `upgrades` is replaced in place by its upgrade
##    (pending double_kill + new triple_kill -> one triple_kill);
##  * gap_s of silence between lines;
##  * the same line never repeats within its repeat_s (default_repeat_s);
##  * only priority >= interrupt_priority interrupts a playing line (and only
##    a less important one).
## Time is passed in (seconds), so tests are deterministic.

var def: AnnouncerDef
var _queue: Array = []  # [line_id, priority, queued_at]
var _last_played: Dictionary = {}  # line id -> start time
var _playing: StringName = &""
var _playing_priority: int = -1
var _busy_until: float = -1000.0
## Set by push() when the new line must cut the current one (director stops it).
var interrupt_requested: bool = false


func _init(announcer_def: AnnouncerDef = null) -> void:
	def = announcer_def if announcer_def != null else AnnouncerDef.new()


func priority_of(line: StringName) -> int:
	var l: Dictionary = def.lines.get(line, {})
	return int(l.get("priority", 0))


func repeat_of(line: StringName) -> float:
	var l: Dictionary = def.lines.get(line, {})
	return float(l.get("repeat_s", def.default_repeat_s))


## Queued line ids, in play order (tests / debug).
func pending() -> Array[StringName]:
	var out: Array[StringName] = []
	for q in _queue:
		out.append(q[0])
	return out


func playing() -> StringName:
	return _playing


## Offers `line` at time `now`. Returns false when it was rejected (unknown,
## repeat window, or dropped because the queue is full of more important lines).
func push(line: StringName, now: float) -> bool:
	if not def.lines.has(line):
		return false
	if _last_played.has(line) and now - float(_last_played[line]) < repeat_of(line):
		return false
	var pri := priority_of(line)
	for q in _queue:
		if def.upgrades.get(q[0], &"") == line:
			q[0] = line
			q[1] = pri
			_sort()
			return true
		if q[0] == line:
			return true  # already pending
	if _playing != &"" and now < _busy_until and pri >= def.interrupt_priority and pri > _playing_priority:
		interrupt_requested = true
		_busy_until = now - def.gap_s
	_queue.append([line, pri, now])
	_sort()
	while _queue.size() > def.queue_max:
		var dropped: Array = _queue.pop_back()
		if dropped[0] == line:
			return false
	return true


## The line to start at `now`, or &"" (busy, in the gap, or nothing valid queued).
func next(now: float) -> StringName:
	_queue = _queue.filter(func(q: Array) -> bool: return now - float(q[2]) <= def.max_wait_s)
	if _queue.is_empty() or now < _busy_until + def.gap_s:
		return &""
	var q: Array = _queue.pop_front()
	return q[0]


## The director started `line` at `now`, lasting `duration_s`.
func started(line: StringName, now: float, duration_s: float) -> void:
	_playing = line
	_playing_priority = priority_of(line)
	_last_played[line] = now
	_busy_until = now + maxf(duration_s, 0.0)
	interrupt_requested = false


## True while a line is still sounding at `now`.
func is_busy(now: float) -> bool:
	return now < _busy_until


func _sort() -> void:
	_queue.sort_custom(func(a: Array, b: Array) -> bool:
		return a[1] > b[1] or (a[1] == b[1] and float(a[2]) < float(b[2])))
