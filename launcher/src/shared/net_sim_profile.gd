class_name NetSimProfile
extends Resource
## Network condition simulation for the loopback transport (architecture.md §8.8,
## `--net-sim <name>` loads assets/data/net/net_sim_<name>.tres).

## One-way delay added to every packet, in milliseconds.
@export_range(0, 2000) var one_way_latency_ms: int = 0
## Uniform random extra delay in [0, jitter_ms] per packet.
@export_range(0, 1000) var jitter_ms: int = 0
## Probability [0..1] that an unreliable packet (channels 2 and 3) is dropped.
## Reliable channels are delayed but never dropped, mirroring ENet reliability.
@export_range(0.0, 1.0, 0.001) var loss: float = 0.0
## RNG seed so a simulated session is reproducible.
@export var seed: int = 1
