class_name Predictor
extends RefCounted
## Own-hero client-side prediction and reconciliation (ADR-0002 §5,
## architecture.md §8.4). Runs the shared HeroMotor on the client's HeroBody,
## keeps a ring of (command, resulting state) per seq, and on each snapshot
## compares the server state at last_processed_seq with the prediction. Above
## reconcile_epsilon_m it resets to the server state and replays the newer inputs
## (max max_replay_ticks, else it snaps). The visual jump is returned as an
## offset the camera decays over error_smoothing_s.

var net: NetConfig
var body: HeroBody
var dt: float
## Diagnostics.
var last_error_m: float = 0.0
var max_error_m: float = 0.0
var corrections: int = 0
var snaps: int = 0
var reconciled_snapshots: int = 0
var latest_seq: int = 0

var _cmds: Array[InputCommand] = []
var _states: Array[MotorState] = []
var _seqs: PackedInt64Array


func _init(net_config: NetConfig, hero: HeroBody) -> void:
	net = net_config
	body = hero
	dt = net.tick_dt()
	var n := net.prediction_history_size
	_seqs.resize(n)
	_seqs.fill(-1)
	for i in n:
		_cmds.append(InputCommand.new())
		_states.append(MotorState.new())


## Predicts one tick with an already-quantized command.
func predict(cmd: InputCommand) -> void:
	body.step(cmd, dt)
	_record(cmd)


## Reconciles against the server's state after `seq`. Returns the visual offset
## (old predicted position - new predicted position), or ZERO.
func reconcile(server_state: MotorState, seq: int) -> Vector3:
	var i := seq % _seqs.size()
	if seq <= 0 or _seqs[i] != seq:
		return Vector3.ZERO  # too old or not predicted yet
	reconciled_snapshots += 1
	var predicted := _states[i]
	last_error_m = predicted.position.distance_to(server_state.position)
	max_error_m = maxf(max_error_m, last_error_m)
	var same_flags := predicted.grounded == server_state.grounded and predicted.crouching == server_state.crouching
	if last_error_m <= net.reconcile_epsilon_m and same_flags:
		return Vector3.ZERO
	corrections += 1
	var before := body.state.position
	body.state.copy_from(server_state)
	predicted.copy_from(server_state)
	body.motor.restore(body.state)
	if latest_seq - seq > net.max_replay_ticks:
		snaps += 1
		_forget_after(seq)
	else:
		for s in range(seq + 1, latest_seq + 1):
			var k := s % _seqs.size()
			if _seqs[k] != s:
				break
			body.step(_cmds[k], dt)
			_states[k].copy_from(body.state)
	return before - body.state.position


func _record(cmd: InputCommand) -> void:
	var i := cmd.seq % _seqs.size()
	_seqs[i] = cmd.seq
	_cmds[i].copy_from(cmd)
	_states[i].copy_from(body.state)
	latest_seq = cmd.seq


func _forget_after(seq: int) -> void:
	for i in _seqs.size():
		if _seqs[i] > seq:
			_seqs[i] = -1
	latest_seq = seq
