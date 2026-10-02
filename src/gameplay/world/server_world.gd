class_name ServerWorld
extends Node3D
## Authoritative simulation (ADR-0002, architecture.md §8.3). One step() = one
## tick in a fixed order: poll transport -> scripted inputs -> hero movement ->
## snapshots -> tick++. Lives in its own World3D (SubViewport.own_world_3d) when
## sharing a process with ClientWorld (verification-4.7.md item 2).
## E2/E3 scope: heroes and movement only.

const PLAYER_SPAWN := "PlayerSpawn"

var net: NetConfig
var movement: MovementDef
var session: ServerSession
var registry: EntityRegistry
var tick: int = 0
var dt: float

var _humans: Dictionary = {}  # peer id -> HeroBody
var _dummies: Array = []      # [HeroBody, ScriptedInputSource]
var _map: Node3D
var _cmd := InputCommand.new()


## Builds the map and session. Call after the node is in the tree.
func setup(net_config: NetConfig, movement_def: MovementDef, map_scene: PackedScene, transport: Transport) -> void:
	net = net_config
	movement = movement_def
	dt = net.tick_dt()
	registry = EntityRegistry.new(roundi(net.net_id_recycle_s * net.tick_rate_hz))
	session = ServerSession.new(transport, net)
	session.client_joined.connect(_on_client_joined)
	_map = map_scene.instantiate()
	add_child(_map)


## World-space position of a Marker3D in the map, or the origin.
func spawn_point(marker_name: String) -> Vector3:
	var m := _map.get_node_or_null(marker_name) as Node3D
	return m.global_position if m != null else Vector3.ZERO


## Adds a server-driven hero fed by a scripted input source. Returns its NetId.
func add_scripted_hero(source: ScriptedInputSource, spawn: Vector3) -> int:
	var hero := _spawn_hero(spawn)
	_dummies.append([hero, source])
	return hero.net_id


func hero(net_id: int) -> HeroBody:
	return registry.get_node_by_id(net_id) as HeroBody


## One server tick.
func step() -> void:
	session.poll()
	for peer in session.clients:
		var h: HeroBody = _humans.get(peer)
		var buf: InputBuffer = session.clients[peer].inputs
		var n := 0
		while n < net.max_inputs_per_tick and buf.pop_next(_cmd):
			h.step(_cmd, dt)
			n += 1
	for d in _dummies:
		d[1].sample(tick, _cmd)
		d[0].step(_cmd, dt)
	_send_snapshots()
	tick += 1


func _spawn_hero(spawn: Vector3) -> HeroBody:
	var h := HeroBody.new()
	h.setup(movement, spawn, true)
	add_child(h)
	h.place()
	h.net_id = registry.register(h, EntityRegistry.KIND_HERO, tick)
	return h


func _on_client_joined(peer_id: int) -> void:
	var h := _spawn_hero(spawn_point(PLAYER_SPAWN))
	_humans[peer_id] = h
	session.accept(peer_id, h.net_id, tick)


func _send_snapshots() -> void:
	if session.clients.is_empty():
		return
	var entities: Array[SnapshotData.EntityState] = []
	for id in registry.ids():
		var h := registry.get_node_by_id(id) as HeroBody
		var e := SnapshotData.EntityState.new()
		e.net_id = id
		e.kind = registry.kind_of(id)
		e.position = h.state.position
		e.velocity = h.state.velocity
		e.yaw = h.look_yaw
		e.pitch = h.look_pitch
		e.crouching = h.state.crouching
		e.grounded = h.state.grounded
		entities.append(e)
	for peer in session.clients:
		var c: ServerSession.ClientConnection = session.clients[peer]
		var s := SnapshotData.new()
		s.tick = tick
		s.last_processed_seq = c.inputs.last_processed_seq
		s.own_net_id = c.own_net_id
		var own := registry.get_node_by_id(c.own_net_id) as HeroBody
		s.own_state = own.state if own != null else null
		s.entities = entities
		session.send_snapshot(peer, s)
