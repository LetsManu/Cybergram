class_name EntityRegistry
extends RefCounted
## NetId <-> node map for networked entities (architecture.md §5). NetIds are
## uint16, start at 1 (0 = none), and are not reused until `recycle_ticks`
## after release, so late packets never address a new entity.

const KIND_HERO: int = 1
const KIND_WARDLING: int = 2
const MAX_NET_ID: int = 65535

var _nodes: Dictionary = {}   # net id -> Node
var _kinds: Dictionary = {}   # net id -> kind
var _next: int = 1
var _released: Array = []     # [net_id, release_tick], oldest first
var _recycle_ticks: int


func _init(recycle_ticks: int) -> void:
	_recycle_ticks = recycle_ticks


## Registers `node` and returns its new NetId (0 if exhausted).
func register(node: Node, kind: int, now_tick: int) -> int:
	var id := 0
	if not _released.is_empty() and now_tick - int(_released[0][1]) >= _recycle_ticks:
		id = _released.pop_front()[0]
	elif _next <= MAX_NET_ID:
		id = _next
		_next += 1
	if id != 0:
		_nodes[id] = node
		_kinds[id] = kind
	return id


func release(net_id: int, now_tick: int) -> void:
	if _nodes.erase(net_id):
		_kinds.erase(net_id)
		_released.append([net_id, now_tick])


func get_node_by_id(net_id: int) -> Node:
	return _nodes.get(net_id)


func kind_of(net_id: int) -> int:
	return _kinds.get(net_id, 0)


## Registered ids in ascending order (deterministic iteration).
func ids() -> Array:
	var k := _nodes.keys()
	k.sort()
	return k


func count() -> int:
	return _nodes.size()
