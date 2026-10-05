class_name AmbientAudio
extends Node
## W18-LIFE / W21-A1: ambient beds (client presentation only). One looping
## stereo bed per zone (base, lane, jungle, water; AmbientBedsDef) on the
## Ambient bus, cross-faded by the camera position over crossfade_m at zone
## edges (AmbientZoneMixer). Zones come from the ClientWorld's MapDef when this
## node sits under one; otherwise (menu backdrops, demos) only the lane bed.
## The beds replace the W18 hum / wash that played on the Effects bus.

const DEF_PATH := "res://assets/data/audio/ambient_beds.tres"
const SILENT_DB := -80.0

var level: int = AmbientComfort.HIGH
var def: AmbientBedsDef
var mixer: AmbientZoneMixer
var _players: Dictionary = {}  # zone -> AudioStreamPlayer
var _gain: Dictionary = {}  # zone -> current linear gain
var _map_checked: bool = false
var _poll: float = 0.0


func _ready() -> void:
	GameSettings.shared().apply_audio()
	def = load(DEF_PATH) as AmbientBedsDef
	mixer = AmbientZoneMixer.from_map(null, def.base_radius_m, def.crossfade_m)
	var bank := AudioEventBank.shared()
	for zone in AmbientZoneMixer.ZONES:
		var streams := bank.streams_for(def.beds.get(zone, &""))
		if streams.is_empty():
			continue
		var p := AudioStreamPlayer.new()
		p.stream = streams[0]
		p.bus = GameSettings.BUS_AMBIENT
		p.volume_db = SILENT_DB
		add_child(p)
		p.play()
		_players[zone] = p
		_gain[zone] = 1.0 if zone == &"lane" else 0.0


## AmbientComfort level 0..2: bed gain from AmbientBedsDef.level_db.
func set_level(lvl: int) -> void:
	level = lvl


func _process(delta: float) -> void:
	_poll += delta
	if not _map_checked and _poll > 0.5:
		_poll = 0.0
		var md := _find_map_def()
		if md != null:
			mixer = AmbientZoneMixer.from_map(md, def.base_radius_m, def.crossfade_m)
			_map_checked = true
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var w: Dictionary = mixer.weights(cam.global_position if cam != null else Vector3.ZERO)
	var lvl_db: float = def.level_db[clampi(level, 0, def.level_db.size() - 1)] if def.level_db.size() > 0 else 0.0
	var k := delta / maxf(def.glide_s, 0.01)
	for zone in _players:
		_gain[zone] = move_toward(float(_gain[zone]), float(w.get(zone, 0.0)), k)
		var g: float = _gain[zone]
		(_players[zone] as AudioStreamPlayer).volume_db = linear_to_db(g) + lvl_db if g > 0.001 else SILENT_DB


## Zone weights at `pos` (tests / debug).
func weights_at(pos: Vector3) -> Dictionary:
	return mixer.weights(pos)


func _find_map_def() -> MapDef:
	var n := get_parent()
	while n != null:
		var md: Variant = n.get("map_def")
		if md is MapDef:
			return md
		n = n.get_parent()
	return null
