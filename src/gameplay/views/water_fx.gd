class_name WaterFx
extends Node
## W16-SDWATER presentation for the dock water: a splash puff when the local hero
## enters a water zone and a soft wading step sound while moving through it.
## Both follow GameSettings.comfort_fx_intensity (0 = no puff, silent wading).
## W21-A1: the sounds are the water_splash_own / water_wade_own events.
## Reuses the existing ring flash (FxDirector.flash) and footstep stream; no new
## assets. Reads ClientWorld.body / map_def only.

const SPLASH_COLOR := Color(0.62, 0.5, 1.0)
const SPLASH_SIZE_M: float = 2.6
const SPLASH_LIFE_S: float = 0.35
## Wading step: quieter and lower than the dry footstep.
const WADE_DB: float = -5.0
const WADE_PITCH: float = 0.7

var client: Node
## Injectable for tests; null = process-wide settings.
var settings: GameSettings
var _in_water: bool = false
var _steps := FootstepClock.new()
var _player: AudioStreamPlayer


## True on the tick the position passes from dry to wet.
static func entered(was_in: bool, now_in: bool) -> bool:
	return now_in and not was_in


## Volume offset (dB) for the wading sound at effects intensity `fx` (<= 0 = silent).
static func wade_db(fx: float, base_db: float) -> float:
	return base_db + linear_to_db(clampf(fx, 0.0, 1.0)) if fx > 0.0 else -80.0


func _ready() -> void:
	if GfxQuality.is_headless():
		set_process(false)
		return
	_player = AudioStreamPlayer.new()
	_player.bus = GameSettings.BUS_FOOTSTEPS
	add_child(_player)


func _process(delta: float) -> void:
	if client == null or client.body == null or client.map_def == null:
		return
	var st: MotorState = client.body.state
	var now: bool = client.map_def.water_factor_at(st.position) < 1.0
	var gs := settings if settings != null else GameSettings.shared()
	var fx := gs.comfort_fx_intensity
	if WaterFx.entered(_in_water, now) and not client.is_dead():
		if client.tracers != null and client.tracers.fx != null:
			client.tracers.fx.flash(st.position + Vector3(0.0, 0.1, 0.0), SPLASH_COLOR, SPLASH_SIZE_M, SPLASH_LIFE_S, true, 1.3)
		var ev := _events()
		if ev != null and fx > 0.0:  # W21-A1 splash (Footsteps bus)
			ev.play(&"water_splash_own", AudioEventDef.OwnerFilter.OWN, null, WaterFx.wade_db(fx, 0.0))
	_in_water = now
	if not now or client.is_dead() or fx <= 0.0:
		return
	var speed := Vector2(st.velocity.x, st.velocity.z).length()
	if _steps.advance(speed, st.grounded, delta):
		var ev := _events()
		if ev != null and ev.bank.has(&"water_wade_own"):  # W21-A1 wading event
			ev.play(&"water_wade_own", AudioEventDef.OwnerFilter.OWN, null, WaterFx.wade_db(fx, 0.0))
			return
		var bank: SfxBank = client.sfx.bank if client.sfx != null else null
		var s := bank.feel_stream(&"footstep") if bank != null else null
		if s != null:
			_player.stream = s
			_player.volume_db = wade_db(fx, WADE_DB + bank.def.footstep_db)
			_player.pitch_scale = WADE_PITCH * randf_range(0.92, 1.08)
			_player.play()


## The match's event player (ClientSfx.events), or null.
func _events() -> AudioEvents:
	var sfx: Variant = client.get("sfx") if client != null else null
	return sfx.events if sfx != null and is_instance_valid(sfx) else null
