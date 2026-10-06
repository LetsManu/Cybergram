extends GdUnitTestSuite
## P1: the front's player / party / lobby state machines. Every legal
## transition of each table is accepted, every pair outside the table is
## rejected and reported, and the registry's sequence numbers only grow.

const P := PhaseMachine.Player
const T0 := 1000.0


func _all_pairs(kind: PhaseMachine.Kind, n: int) -> Array:
	var out: Array = []
	for a in n:
		for b in n:
			out.append([a, b, a == b or (PhaseMachine.table(kind).get(a, []) as Array).has(b)])
	return out


func test_every_pair_matches_the_table() -> void:
	for spec in [[PhaseMachine.Kind.PLAYER, P.size()], [PhaseMachine.Kind.PARTY, PhaseMachine.Party.size()],
			[PhaseMachine.Kind.LOBBY, PhaseMachine.Lobby.size()]]:
		var legal := 0
		var illegal := 0
		for pr in _all_pairs(spec[0], spec[1]):
			var reg := PhaseRegistry.new(spec[0])
			reg._entries["k"] = {"state": pr[0], "prev": pr[0], "seq": 1, "since": T0, "ctx": {}}
			var ok := reg.request("k", pr[1], T0 + 1)
			assert_bool(ok).override_failure_message("%s -> %s" % [
				PhaseMachine.name_of(spec[0], pr[0]), PhaseMachine.name_of(spec[0], pr[1])]).is_equal(pr[2])
			assert_int(reg.state_of("k")).is_equal(pr[1] if pr[2] else pr[0])
			if pr[0] != pr[1]:
				if pr[2]:
					legal += 1
				else:
					illegal += 1
		assert_int(legal).is_greater(0)
		assert_int(illegal).is_greater(0)


func test_full_matchmade_path_is_legal() -> void:
	var reg := PhaseRegistry.new(PhaseMachine.Kind.PLAYER)
	for s in [P.IDLE, P.IN_PARTY, P.QUEUED, P.READY_CHECK, P.CHAMP_SELECT, P.LOADING, P.IN_GAME, P.POST_GAME,
			P.IN_PARTY, P.OFFLINE]:
		assert_bool(reg.request("a", s, T0)).override_failure_message(PhaseMachine.name_of(PhaseMachine.Kind.PLAYER, s)).is_true()
	assert_int(int(reg.entry("a").seq)).is_equal(10)


func test_illegal_is_rejected_counted_and_reported() -> void:
	var reg := PhaseRegistry.new(PhaseMachine.Kind.PLAYER)
	var seen: Array = []
	reg.on_illegal = func(key: String, from: int, to: int, _ctx: Dictionary) -> void: seen.append([key, from, to])
	reg.request("a", P.IDLE, T0)
	assert_bool(reg.request("a", P.IN_GAME, T0 + 1)).is_false()  # idle cannot jump into a game
	assert_bool(reg.request("a", P.READY_CHECK, T0 + 1)).is_false()  # nor skip the queue
	assert_int(reg.state_of("a")).is_equal(P.IDLE)
	assert_int(reg.illegal_count).is_equal(2)
	assert_array(seen).is_equal([["a", P.IDLE, P.IN_GAME], ["a", P.IDLE, P.READY_CHECK]])
	assert_int(int(reg.entry("a").seq)).is_equal(1)


func test_same_state_is_a_no_op_and_keeps_the_sequence() -> void:
	var reg := PhaseRegistry.new(PhaseMachine.Kind.PLAYER)
	var changes := [0]
	reg.on_change = func(_k: String, _e: Dictionary) -> void: changes[0] += 1
	reg.request("a", P.IDLE, T0)
	reg.request("a", P.IDLE, T0 + 5, {"x": 1})
	assert_int(changes[0]).is_equal(1)
	assert_int(int(reg.entry("a").seq)).is_equal(1)
	assert_dict(reg.entry("a").ctx).is_equal({"x": 1})


func test_reconnecting_returns_to_the_left_state() -> void:
	var reg := PhaseRegistry.new(PhaseMachine.Kind.PLAYER)
	for s in [P.IDLE, P.QUEUED, P.READY_CHECK, P.CHAMP_SELECT, P.LOADING, P.IN_GAME, P.RECONNECTING, P.IN_GAME]:
		assert_bool(reg.request("a", s, T0)).is_true()
	assert_int(int(reg.entry("a").prev)).is_equal(P.RECONNECTING)


func test_lobby_end_states_are_final() -> void:
	for end in [PhaseMachine.Lobby.ENDED, PhaseMachine.Lobby.CANCELLED]:
		for to in PhaseMachine.Lobby.size():
			assert_bool(PhaseMachine.is_legal(PhaseMachine.Kind.LOBBY, end, to)).is_equal(to == end)


func test_forget_restarts_from_the_initial_state() -> void:
	var reg := PhaseRegistry.new(PhaseMachine.Kind.PARTY)
	reg.request("p", PhaseMachine.Party.IDLE, T0)
	reg.request("p", PhaseMachine.Party.QUEUED, T0)
	reg.forget("p")
	assert_int(reg.state_of("p")).is_equal(PhaseMachine.Party.NONE)
	assert_bool(reg.request("p", PhaseMachine.Party.QUEUED, T0)).is_false()


func test_counts_per_state() -> void:
	var reg := PhaseRegistry.new(PhaseMachine.Kind.PLAYER)
	reg.request("a", P.IDLE, T0)
	reg.request("b", P.IDLE, T0)
	reg.request("c", P.IDLE, T0)
	reg.request("c", P.QUEUED, T0)
	assert_dict(reg.counts()).is_equal({P.IDLE: 2, P.QUEUED: 1})
