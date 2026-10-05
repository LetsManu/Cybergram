extends SceneTree
## W16-NET snapshot benchmark (headless). Runs a bots-only match through the
## real ServerWorld tick and attaches one virtual client per bot hero (a
## ClientSession on a LoopbackLink with optional latency / loss): the server
## builds, encodes and sends that hero's snapshot exactly as for a player, and
## the client decodes it and acks it in an (empty) InputBatch. Writes a per-second
## CSV and a summary JSON into the output folder.
##
## Usage:
##   godot --headless --path . -s tools/net/bench_snapshots.gd -- --map front --minutes 5 \
##     --label before --out production/qa/evidence/w16-net [--latency-ms 40 --loss 0.02 --seed 3]
##   (--map slice plays the 3v3 slice)

var _map := "front"
var _minutes := 5.0
var _label := "run"
var _out := "production/qa/evidence/w16-net"
var _latency := 40
var _jitter := 10
var _loss := 0.02
var _seed := 3


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		var v := args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--map": _map = v
			"--minutes": _minutes = v.to_float()
			"--label": _label = v
			"--out": _out = v
			"--latency-ms": _latency = v.to_int()
			"--jitter-ms": _jitter = v.to_int()
			"--loss": _loss = v.to_float()
			"--seed": _seed = v.to_int()
			_:
				i -= 1
		i += 2
	_run.call_deferred()


func _run() -> void:
	var def := GameSession.load_map_def(_map)
	if def == null:
		push_error("bench: unknown map %s" % _map)
		quit(2)
		return
	var net := load("res://assets/data/net/net_config.tres") as NetConfig
	var p := NetSimProfile.new()
	p.one_way_latency_ms = _latency
	p.jitter_ms = _jitter
	p.loss = _loss
	p.seed = _seed
	var link := LoopbackLink.new(p)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)
	var server := ServerWorld.new()
	vp.add_child(server)
	var rules := def.match_rules if def.match_rules != null \
		else load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef
	server.setup(net, load("res://assets/data/movement/movement_default.tres") as MovementDef, def.scene,
		link.create_endpoint(1), null, rules)
	server.setup_objectives(def)
	server.setup_match(def, 1.0)
	server.enable_wardlings(def, load(GameSession.WARDLING_RULES) as WardlingRulesDef,
		load(GameSession.WARDLING_PICKET) as WardlingDef)
	server.enable_progression(load(GameSession.ECONOMY_RULES) as EconomyRulesDef,
		load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef, def)
	var wd := WardlingDirector.new()
	wd.attach(server)
	var roster := load(BotAiInstaller.ROSTER_PATH) as BotRosterDef
	var director := BotDirector.new()
	director.setup(server, roster, roster.profile("normal"), _seed)
	# Navmesh first (bots path on it).
	var a := def.hq(MapDef.TEAM_CONCORD).sanctum
	var b := def.hq(MapDef.TEAM_SYNDICATE).sanctum
	for k in 240:
		await physics_frame
		if NavigationServer3D.map_get_path(server.get_world_3d().navigation_map, a, b, true).size() > 1:
			break
	var n := director.fill(false)
	var clients: Array[ClientSession] = []
	var fake_now := [0]
	for k in n:
		var peer := 2 + k
		var cs := ClientSession.new(link.create_endpoint(peer), net)
		cs.clock_usec = func() -> int: return link.now_usec
		clients.append(cs)
		server.session.accept(peer, director.brains[k].hero_id, server.tick)
		server.session.clients[peer].stats.keep_history = true
	print("[bench] map %s, %d bots, %d virtual clients, %.1f min, link %d ms +%d jitter %.1f%% loss" % [
		_map, n, clients.size(), _minutes, _latency, _jitter, _loss * 100.0])
	var ticks := roundi(_minutes * 60.0 * net.tick_rate_hz)
	var csv := PackedStringArray(["t_s,snap_avg_B,snap_p95_B,snap_max_B,kBps_per_client,frag_snaps,over_budget,wardlings,decode_fail"])
	var sec_sizes := PackedInt32Array()
	var sec_frag := 0
	var sec_over := 0
	var t0 := Time.get_ticks_msec()
	var step_us := PackedInt32Array()
	var empty: Array[InputCommand] = []
	for t in ticks:
		link.advance(net.tick_dt())
		for cs in clients:
			cs.poll()
			var batch := InputBatchCodec.encode(cs.latest_snapshot_tick, empty)
			cs.transport.send(ClientSession.SERVER_PEER, Transport.CH_INPUT, batch)
		var s0 := Time.get_ticks_usec()
		server.step()
		step_us.append(Time.get_ticks_usec() - s0)
		for peer in server.session.clients:
			var st: SnapshotStats = server.session.clients[peer].stats
			var sz := st.history[st.history.size() - 1] if not st.history.is_empty() else 0
			sec_sizes.append(sz)
			if SnapshotStats.fragments_for(sz) > 1:
				sec_frag += 1
			if sz > net.snapshot_budget_bytes:
				sec_over += 1
		if (t + 1) % net.tick_rate_hz == 0:
			var fails := 0
			for cs in clients:
				fails += cs.malformed_packets + cs.stats.baseline_misses
			var avg := _avg(sec_sizes)
			csv.append("%d,%.1f,%d,%d,%.2f,%d,%d,%d,%d" % [(t + 1) / net.tick_rate_hz, avg,
				SnapshotStats.percentile(sec_sizes, 0.95), _max(sec_sizes), avg * net.tick_rate_hz / 1000.0,
				sec_frag, sec_over, server.wardlings.wardlings.size(), fails])
			sec_sizes.clear()
			sec_frag = 0
			sec_over = 0
	var all := PackedInt32Array()
	var frag := 0
	var over := 0
	var deltas := 0
	var deferred := 0
	var bytes_all := 0
	for peer in server.session.clients:
		var st: SnapshotStats = server.session.clients[peer].stats
		all.append_array(st.history)
		frag += st.fragmented_snapshots
		over += st.over_budget
		deltas += st.delta_snapshots
		deferred += st.deferred_updates
		for ch in 4:
			bytes_all += st.total_bytes[ch]
	var fails := 0
	var decoded := 0
	var misses := 0
	for cs in clients:
		fails += cs.malformed_packets
		decoded += cs.stats.snapshots
		misses += cs.stats.baseline_misses
	var secs := ticks / float(net.tick_rate_hz)
	var avg_all := _avg(all)
	var per_client_kbps := bytes_all / secs / 1000.0 / maxi(clients.size(), 1)
	step_us.sort()
	var summary := {
		"label": _label, "map": _map, "bots": n, "minutes": _minutes, "protocol": MsgType.PROTOCOL_VERSION,
		"link": {"one_way_ms": _latency, "jitter_ms": _jitter, "loss": _loss, "seed": _seed},
		"snapshots": all.size(), "snap_avg_B": snappedf(avg_all, 0.1),
		"snap_p50_B": SnapshotStats.percentile(all, 0.5), "snap_p95_B": SnapshotStats.percentile(all, 0.95),
		"snap_max_B": _max(all),
		"snap_kBps_per_client": snappedf(avg_all * net.tick_rate_hz / 1000.0, 0.01),
		"all_channels_kBps_per_client": snappedf(per_client_kbps, 0.01),
		"server_upload_10_players_Mbit": snappedf(per_client_kbps * 10.0 * 8.0 / 1000.0, 0.001),
		"fragmented_pct": snappedf(100.0 * frag / maxi(all.size(), 1), 0.01),
		"over_budget_pct": snappedf(100.0 * over / maxi(all.size(), 1), 0.01),
		"delta_pct": snappedf(100.0 * deltas / maxi(all.size(), 1), 0.01),
		"deferred_updates_per_snapshot": snappedf(float(deferred) / maxi(all.size(), 1), 0.01),
		"client_decoded": decoded, "client_decode_failures": fails, "client_baseline_misses": misses,
		"encode_ms_per_tick_all_clients": snappedf(server.session.encode_usec / 1000.0 / ticks, 0.001),
		"server_step_p50_ms": snappedf(step_us[step_us.size() / 2] / 1000.0, 0.001),
		"server_step_p95_ms": snappedf(step_us[int(step_us.size() * 0.95)] / 1000.0, 0.001),
		"wall_s": snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + _out))
	var stem := "res://%s/bench_%s_%s" % [_out, _label, _map]
	var f := FileAccess.open(stem + ".csv", FileAccess.WRITE)
	f.store_string("\n".join(csv) + "\n")
	f.close()
	f = FileAccess.open(stem + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(summary, "  ") + "\n")
	f.close()
	print("[bench] " + JSON.stringify(summary))
	vp.queue_free()
	quit(0)


static func _avg(v: PackedInt32Array) -> float:
	if v.is_empty():
		return 0.0
	var s := 0
	for x in v:
		s += x
	return float(s) / v.size()


static func _max(v: PackedInt32Array) -> int:
	var m := 0
	for x in v:
		m = maxi(m, x)
	return m
