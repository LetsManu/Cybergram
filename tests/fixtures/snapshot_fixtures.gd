class_name SnapshotFixtures
extends RefCounted
## W16-NET: snapshot factories for codec / priority tests (no file I/O).


static func hero(id: int, pos: Vector3, team: int = 0) -> SnapshotData.EntityState:
	var e := SnapshotData.EntityState.new()
	e.net_id = id
	e.kind = 1
	e.position = pos
	e.velocity = Vector3(3.3, -0.5, 7.1)
	e.yaw = 2.1
	e.pitch = -0.4
	e.grounded = true
	e.team = team
	e.hp = 640
	e.max_hp = 800
	e.status = 0x0012
	e.hero_index = 4
	e.fork_bits = SnapshotData.EntityState.with_slot(0, 1, 2, true)
	return e


static func wardling(id: int, pos: Vector3, owner: int = 0) -> SnapshotData.WardlingState:
	var w := SnapshotData.WardlingState.new()
	w.net_id = id
	w.position = pos
	w.yaw = 0.7
	w.hp_frac = 0.8
	w.team = 1
	w.owner_net_id = owner
	w.state = 2
	w.tier = 2
	return w


## A full 5v5-like snapshot for `own_id` at `tick` with `n_wardlings` in a line.
static func rich(tick: int, own_id: int = 1, n_wardlings: int = 20) -> SnapshotData:
	var s := SnapshotData.new()
	s.tick = tick
	s.last_processed_seq = tick * 2
	s.own_net_id = own_id
	var m := MotorState.new()
	m.position = Vector3(1.234567, 0.5, -200.987654)
	m.velocity = Vector3(0.1, 0.0, -6.5)
	m.grounded = true
	m.speed_scale = 0.85
	m.dash_ticks = 3
	m.dash_velocity = Vector3(1, 2, 3)
	s.own_state = m
	var c := SnapshotData.OwnCombat.new()
	c.hp = 500
	c.max_hp = 800
	c.ammo = 12.5
	c.ammo_capacity = 30
	c.skill_cd_left = PackedInt32Array([0, 30, 0, 600])
	c.level = 7
	s.own_combat = c
	for i in 10:
		s.entities.append(hero(i + 1, Vector3(-60.0 + i * 13.37, 1.0 + i * 0.1, -20.0 - i * 39.1), i % 2))
	for i in n_wardlings:
		s.wardlings.append(wardling(100 + i, Vector3(i * 2.0, 0.0, -100.0 - i * 9.0), 1 + (i % 10)))
	var f := SnapshotData.FxState.new()
	f.id = 9
	f.kind = 3
	f.position = Vector3(5, 0, -50)
	f.position2 = Vector3(2, 3, 0.5)
	f.param = 0.5
	f.ticks_left = 90
	s.fx.append(f)
	for i in 15:
		var h := SnapshotData.HardpointState.new()
		h.owner = i % 3 - 1
		h.progress = i / 15.0
		h.task = i % 3
		h.cell_pos = Vector3(i, 0, -i * 20)
		s.hardpoints.append(h)
	s.fronts = PackedInt32Array([1, 2, 0, 4, -1, 3])
	var p := SnapshotData.ProgressState.new()
	p.level = 7
	p.lumen = 1234
	p.motes = PackedVector3Array([Vector3(1, 0, -5), Vector3(-3, 0, -80)])
	s.progress = p
	var ms := SnapshotData.MatchState.new()
	ms.phase = 2
	ms.time_s = tick / 30.0
	ms.next_phase_s = 600.0
	var u := SnapshotData.UplinkState.new()
	u.team = 1
	u.integrity = 900.0
	u.max_integrity = 1000.0
	ms.uplinks.append(u)
	s.match_state = ms
	s.bolts.append([Vector3(1, 1, -2), Vector3(4, 1.5, -20)])
	return s


## `s` advanced one tick: every hero and the first `moving` Wardlings move.
static func advance(s: SnapshotData, moving: int) -> SnapshotData:
	var n := rich(s.tick + 1, s.own_net_id, s.wardlings.size())
	for i in n.entities.size():
		n.entities[i].position = s.entities[i].position + Vector3(0.2, 0.0, -0.15)
	for i in n.wardlings.size():
		n.wardlings[i].position = s.wardlings[i].position + (Vector3(0.1, 0.0, -0.1) if i < moving else Vector3.ZERO)
	n.bolts.clear()
	return n
