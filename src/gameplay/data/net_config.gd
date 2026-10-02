class_name NetConfig
extends Resource
## Network and tick tunables (ADR-0002, architecture.md §6/§8). The .tres in
## assets/data/net/ is authoritative; defaults here mirror it.

## Fixed simulation rate for server and client prediction (ADR-0002: 30 Hz).
@export_range(1, 240) var tick_rate_hz: int = 30
## Remote entities render this many ticks behind the newest snapshot (100 ms).
@export_range(0, 30) var interp_delay_ticks: int = 3
## Max ticks a remote entity may be extrapolated past its newest sample.
@export_range(0, 10) var extrapolation_cap_ticks: int = 1
## Prediction error (metres) above which the client resets and replays.
@export_range(0.0, 1.0, 0.001) var reconcile_epsilon_m: float = 0.02
## Max inputs replayed per reconciliation; beyond this the client snaps.
@export_range(1, 64) var max_replay_ticks: int = 16
## Client prediction history ring size (ticks).
@export_range(8, 256) var prediction_history_size: int = 64
## Seconds over which a visual correction offset decays to zero.
@export_range(0.0, 1.0, 0.01) var error_smoothing_s: float = 0.1
## InputCommands per InputBatch (redundancy against loss).
@export_range(1, 8) var input_redundancy: int = 3
## Anti speed-hack: max inputs the server consumes per client per tick.
@export_range(1, 16) var max_inputs_per_tick: int = 8
## Max inputs held per client awaiting processing; older ones are dropped.
@export_range(4, 256) var max_buffered_inputs: int = 32
## Packets larger than this are rejected as malformed.
@export_range(64, 65535) var max_packet_bytes: int = 1400
## Malformed packets tolerated before a peer is dropped.
@export_range(1, 1000) var max_violations: int = 50
## A released NetId is not reused for this long (architecture.md §5).
@export_range(0.0, 10.0, 0.1) var net_id_recycle_s: float = 2.0
## Lag-compensation rewind cap (used from E4).
@export_range(0, 1000) var max_rewind_ms: int = 200
## Per-client snapshot byte budget (enforced once delta compression lands).
@export_range(256, 65535) var snapshot_budget_bytes: int = 1100


## Seconds per tick.
func tick_dt() -> float:
	return 1.0 / tick_rate_hz
