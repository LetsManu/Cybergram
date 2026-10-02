class_name InputBuffer
extends RefCounted
## Per-client queue of received, not yet applied InputCommands (architecture.md
## §8.3 step 1). Deduplicates redundant copies, drops stale seqs, caps size.

var last_processed_seq: int = 0
var _cmds: Dictionary = {}  # seq -> InputCommand
var _max: int


func _init(max_buffered: int) -> void:
	_max = max_buffered


## Adds a received command; ignores duplicates and already-processed seqs.
func push(cmd: InputCommand) -> void:
	if cmd.seq <= last_processed_seq or _cmds.has(cmd.seq):
		return
	_cmds[cmd.seq] = cmd
	if _cmds.size() > _max:
		var keys := _cmds.keys()
		keys.sort()
		_cmds.erase(keys[0])


## Pops the lowest pending seq into `out`. Gaps (all redundant copies lost) are
## skipped; the client's reconciliation absorbs the difference.
func pop_next(out: InputCommand) -> bool:
	if _cmds.is_empty():
		return false
	var lowest: int = _cmds.keys().min()
	out.copy_from(_cmds[lowest])
	_cmds.erase(lowest)
	last_processed_seq = lowest
	return true


func size() -> int:
	return _cmds.size()
