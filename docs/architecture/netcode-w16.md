# Netcode efficiency (W16-NET, protocol 16)

Implements the quantisation, delta and bandwidth plan of architecture.md §8.5.
It is server-authoritative and runs at 30 Hz, 5v5, over ENet UDP with DTLS.
Story: W16-NET.

## Before / after

Source: `tools/net/bench_snapshots.gd`. The benchmark runs a bots-only match through the real `ServerWorld` tick with one virtual client per bot. Each client decodes its snapshots and acks them on a loopback link set to 40 ms one way, +10 ms jitter and 2 % loss (seed 3). The raw output is in `production/qa/evidence/w16-net/bench_{before,after}_{front,slice}.{csv,json}`.

### Shardline Front, 5v5 (10 clients, 6 min of match)

| Metric | Before (v15) | After (v16) | Change |
|---|---|---|---|
| Snapshot avg | 1706 B | 352 B | -79 % |
| Snapshot p50 / p95 | 1748 / 1844 B | 360 / 494 B | -73 % (p95) |
| Snapshot max | 1906 B | 1031 B (first full snapshot) | inside the budget |
| Snapshot kB/s per client | 51.2 | 10.6 | -79 % |
| All channels kB/s per client | 51.4 | 10.7 | -79 % |
| Server upload, 10 players | 4.11 Mbit/s | 0.86 Mbit/s | -79 % |
| Fragmented snapshots (> 1364 B) | 99.7 % | 0 % | |
| Over the 1100 B budget | 99.9 % | 0 % | |
| Delta snapshots | 0 % | 99.95 % | |
| Wardling updates deferred | 0 | 12.5 per snapshot | priority working |
| Encode cost, all 10 clients | not measured | 5.4 ms per tick | |
| Server step p50 / p95 (bots + 10 encodes) | 14.9 / 24.9 ms | 15.5 / 26.2 ms | about flat |

### Slice, 3v3 (6 clients, 4 min)

| Metric | Before | After |
|---|---|---|
| Snapshot avg / p95 / max | 888 / 1077 / 1284 B | 260 / 417 / 636 B |
| kB/s per client (all channels) | 26.8 | 7.9 |
| Upload scaled to 10 players | 2.14 Mbit/s | 0.63 Mbit/s |
| Fragmented / over budget | 0 % / 3.4 % | 0 % / 0 % |

Upload is the payload only. UDP, IP, ENet and DTLS headers add about 70 B per packet. At 30 packets/s that is about 2 kB/s more per client, or about +0.17 Mbit/s for 10 players.

**Why fragmentation mattered.** A packet larger than 1364 B is split by ENet (MTU 1392). When a split packet is sent without `FLAG_UNRELIABLE_FRAGMENT`, ENet sends its fragments **reliably**. So in v15 almost every snapshot on the "unreliable" channel was retransmitted and blocked the next one behind it while lost fragments were resent. v16 keeps every snapshot inside one datagram, so this cannot happen.

## Protocol 16 (snapshot wire)

The full layout is in the header of `src/networking/protocol/codecs/snapshot_codec.gd`.

- **Header (16 B):** tick, base tick, last processed seq, own net id, flags (has own, delta).
- **Quantised records:**
  - Hero (28 B, was 46 B):
    - position i16 at 1/32 m (±1023 m; the Front map spans 160 × 415 m)
    - velocity i16 at 1/128 m/s
    - yaw u16, pitch i16
    - hp, status, identity
  - Wardling: 13 B. Skill FX: 18 B, with an absolute expiry tick. Hardpoint: 20 B.
  - The own motor state stays f32: the reconcile epsilon is 0.02 m, which is smaller than the 1/32 m step.
- **Keyed sections** (heroes, FX, hardpoints, Wardlings), each encoded against the client's acked baseline:
  - removals
  - updates as key + group change mask + changed groups (a new key must carry every group)
  - a stale bitmask for updates that were deferred
- **Blobs** (own combat, fronts, progress, match): each is absent, "same as baseline", or new bytes. The match clock is sent outside its blob, so a ticking clock does not resend the block.
- **Acks:** the client already acks its newest decoded tick in every InputBatch.
  - The server keeps 32 baselines per client.
  - An unknown or too-old ack (more than 32 ticks, about 1 s) gets a full snapshot.
  - The client keeps 64 baselines. A delta whose baseline it lacks counts as a baseline miss, not as malformed input. It is dropped, and the next ack resyncs.
- **Budget:** `snapshot_budget_bytes` (1100) is enforced.
  - Bolt tracers are trimmed first.
  - Wardling updates are then deferred by priority. A deferred Wardling keeps its baseline value on the client and is marked `stale`.
  - `WardlingPresenter` does not feed stale values to interpolation.
  - Heroes, hardpoints, objectives and FX are never deferred.

## Relevance and priority

Implemented in `WardlingPrioritiser`, one per client.

| Wardling | Rate |
|---|---|
| Own squad, within 40 m, or in the view cone (±55°, ≤ 90 m) | every tick (30 Hz) |
| Everything else (other lanes, behind) | every 3rd tick (10 Hz) |

- **Accumulator:** each tick, every Wardling's accumulator grows by 1 if it is relevant and by 1/3 if not. It becomes eligible at 1, and eligible updates go oldest first. The accumulator resets when the client's view of that Wardling is current.
- **No starvation:** an update that was not sent keeps growing until it outranks everything else (tested).
- **Fairness:** all 10 heroes go out every tick, so an enemy hero within weapon range is never delayed. Hardpoint and objective changes always ship in the tick they happen.

## Adaptive interpolation

Implemented in `InterpDelayController`. Arrival lateness is measured against `tick × 33.3 ms` over 3 s (`ClientNetStats`).

- **Formula:** `target = clamp(ceil(1.5 + p95_lateness / tick + [1 if loss >= 5 %]), 2, 5)` ticks, which is 66 to 166 ms.
- **Hysteresis:**
  - The target rises at once.
  - It falls one tick at a time, and only after the need has stayed more than 1.2 ticks lower for 2 s.
  - The applied delay slews at 2 ticks/s.
- `extrapolation_cap_ticks` is unchanged. Lag compensation still rewinds to the client's `view_tick`, and the 200 ms cap covers the 166 ms maximum.

## Measurement

- **Server:** with `[net]`, each client gets one line every 10 s, rate-limited to 12 lines plus a summary line. It shows:
  - snapshot avg / p95 / max
  - fragments and over-budget count
  - packets/s and kB/s per channel
  - ENet RTT, RTT variance and loss

  Lines carry peer ids only, no names.
- **Client:** the net graph (F3) shows:
  - ping, loss, jitter (mean and p95)
  - interpolation delay
  - snapshot kB/s in and input kB/s out
  - snapshot size, plus a size history against the budget

  Headless CLIENT runs print `[client-net]` lines.
- **Debug loss injector:** in debug builds, `--net-sim <profile>` on a `--connect` client conditions the packets it receives over real UDP.

## Risks and limits

- **Upgrade order:** protocol 16 is a breaking change, so the server and every client must update together. Old clients get `REJECT_PROTOCOL_MISMATCH`.
- **Server CPU:**
  - Encoding costs about 0.5 ms per client per tick in GDScript.
  - At 10 clients the step p95 is about 26 ms against a 33 ms budget, and bots dominate it.
  - If the owner's NAS is slower, the encoder is the first GDExtension candidate.
- **First snapshot:** a full snapshot, after a join or more than 1 s of loss, defers far Wardlings for a few ticks.
- **Jitter resolution:** jitter is measured at poll time. Sub-tick jitter (below about 33 ms) shows as about 0 on the loopback.
