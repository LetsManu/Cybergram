class_name StatBlock
extends RefCounted
## Dense stat values with modifiers (ADR-0004 §1, architecture.md §7.1).
## value = clamp(OVERRIDE ?? ((base + ΣADD) × (1 + ΣPCT) × ΠMUL), min, max);
## the latest OVERRIDE (highest handle) wins. Values are cached per stat and
## recomputed only when dirty. Timed modifiers expire in expire(tick).
##
## Example:
##   var b := StatBlock.new(PackedFloat32Array([6.0]))
##   b.add_modifier(Modifier.make(0, Modifier.Op.PCT, -0.25, src, tick + 90))
##   b.get_value(0)  # 4.5

signal stat_changed(stat_index: int)

var _base: PackedFloat32Array
var _min: PackedFloat32Array
var _max: PackedFloat32Array
var _cache: PackedFloat32Array
var _dirty: PackedByteArray
var _mods: Array[Modifier] = []
var _next_handle: int = 1
var _has_timed: bool = false


func _init(base: PackedFloat32Array) -> void:
	_base = base.duplicate()
	var n := _base.size()
	_cache = _base.duplicate()
	_dirty = PackedByteArray()
	_dirty.resize(n)
	_dirty.fill(0)
	_min = PackedFloat32Array()
	_min.resize(n)
	_min.fill(-INF)
	_max = PackedFloat32Array()
	_max.resize(n)
	_max.fill(INF)


func size() -> int:
	return _base.size()


func set_limits(stat: int, lo: float, hi: float) -> void:
	_min[stat] = lo
	_max[stat] = hi
	_mark(stat)


func get_base(stat: int) -> float:
	return _base[stat]


func set_base(stat: int, v: float) -> void:
	_base[stat] = v
	_mark(stat)


func get_value(stat: int) -> float:
	if _dirty[stat] != 0:
		_recompute(stat)
	return _cache[stat]


## Adds `mod`; returns its handle.
func add_modifier(mod: Modifier) -> int:
	mod.handle = _next_handle
	_next_handle += 1
	_mods.append(mod)
	if mod.expires_tick >= 0:
		_has_timed = true
	_mark(mod.stat)
	return mod.handle


func remove_modifier(handle: int) -> void:
	for i in range(_mods.size() - 1, -1, -1):
		if _mods[i].handle == handle:
			var s := _mods[i].stat
			_mods.remove_at(i)
			_mark(s)
			return


## Removes every modifier tagged `source_id` (one Crystal, one status...).
func remove_by_source(source_id: int) -> void:
	for i in range(_mods.size() - 1, -1, -1):
		if _mods[i].source_id == source_id:
			var s := _mods[i].stat
			_mods.remove_at(i)
			_mark(s)


func has_source(source_id: int) -> bool:
	for m in _mods:
		if m.source_id == source_id:
			return true
	return false


## Drops modifiers whose expires_tick <= tick.
func expire(tick: int) -> void:
	if not _has_timed:
		return
	var timed := false
	for i in range(_mods.size() - 1, -1, -1):
		var m := _mods[i]
		if m.expires_tick < 0:
			continue
		if tick >= m.expires_tick:
			_mods.remove_at(i)
			_mark(m.stat)
		else:
			timed = true
	_has_timed = timed


func modifier_count() -> int:
	return _mods.size()


func clear_modifiers() -> void:
	var stats := {}
	for m in _mods:
		stats[m.stat] = true
	_mods.clear()
	_has_timed = false
	for s in stats:
		_mark(s)


func _mark(stat: int) -> void:
	if _dirty[stat] == 0:
		_dirty[stat] = 1
		stat_changed.emit(stat)


func _recompute(stat: int) -> void:
	var add := 0.0
	var pct := 0.0
	var mul := 1.0
	var override_handle := -1
	var override_value := 0.0
	for m in _mods:
		if m.stat != stat:
			continue
		match m.op:
			Modifier.Op.ADD:
				add += m.value
			Modifier.Op.PCT:
				pct += m.value
			Modifier.Op.MUL:
				mul *= m.value
			Modifier.Op.OVERRIDE:
				if m.handle > override_handle:
					override_handle = m.handle
					override_value = m.value
	var v := override_value if override_handle >= 0 else (_base[stat] + add) * (1.0 + pct) * mul
	_cache[stat] = clampf(v, _min[stat], _max[stat])
	_dirty[stat] = 0
