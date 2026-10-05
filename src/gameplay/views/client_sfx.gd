class_name ClientSfx
extends Node
## Client-only combat sounds (presentation; no gameplay state). Placeholder
## audio synthesized in code at startup, so no audio files are needed until
## the audio director's real assets land:
##   own shot        -> 2D gunshot (louder)
##   other shots     -> 3D gunshot at the shooter (positional, quieter)
##   hit confirm     -> short tick (higher for headshots)
##   kill by you     -> two-note chime
## Driven by ClientWorld's shot_received / hit_confirmed / kill_received.

const RATE := 22050
const OWN_SHOT_DB := -6.0
const REMOTE_SHOT_DB := -2.0
const HIT_DB := -8.0
const KILL_DB := -6.0
const REMOTE_MAX_DISTANCE_M := 90.0
## Pool sizes live in SfxBankDef (pool_2d / pool_3d / pool_ui / pool_loops).
## Shotgun pellets arrive as several SHOT events in one tick: play one sound.
const SAME_SHOOTER_GAP_MS := 40

var client: Node
var gunshot: AudioStreamWAV
var hit_tick: AudioStreamWAV
var head_tick: AudioStreamWAV
var kill_chime: AudioStreamWAV

var bank: SfxBank
var presenter: AbilityPresenter  ## W10-W5: set by ClientWorld (optional)
var _pool_ui: Array[AudioStreamPlayer] = []
var _next_ui: int = 0
var _loops: Dictionary = {}  # fx id -> AudioStreamPlayer3D (heal-beam loops)
var _loop_free: Array[AudioStreamPlayer3D] = []
var _def_cache: Dictionary = {}  # hero id -> HeroDef
var _prev_cd: PackedInt32Array = PackedInt32Array()
var _prev_flags: PackedInt32Array = PackedInt32Array()
var _prev_level: int = -1
var _prev_mounts: PackedInt32Array = PackedInt32Array()
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _next_2d: int = 0
var _next_3d: int = 0
var _pool_feet: Array[AudioStreamPlayer] = []
var _next_feet: int = 0
var _steps := FootstepClock.new()
var _was_reloading: bool = false
var _ammo_at_reload: float = 0.0
var _prev_fire: bool = false
var _last_shot_ms: Dictionary = {}  # shooter net id -> msec


func _ready() -> void:
	GameSettings.shared().apply_audio()  # creates the Effects / UI buses
	gunshot = synth_gunshot()
	hit_tick = synth_tone(1700.0, 0.05)
	head_tick = synth_tone(2600.0, 0.06)
	kill_chime = synth_chime()
	bank = SfxBank.shared()
	for i in bank.def.pool_2d:
		var p := AudioStreamPlayer.new()
		p.bus = GameSettings.BUS_EFFECTS
		add_child(p)
		_pool_2d.append(p)
	for i in bank.def.pool_3d:
		var p := AudioStreamPlayer3D.new()
		p.bus = GameSettings.BUS_EFFECTS
		p.max_distance = REMOTE_MAX_DISTANCE_M
		p.unit_size = 8.0
		add_child(p)
		_pool_3d.append(p)
	for i in bank.def.pool_ui:
		var p := AudioStreamPlayer.new()
		p.bus = GameSettings.BUS_UI
		add_child(p)
		_pool_ui.append(p)
	for i in bank.def.pool_feet:
		var p := AudioStreamPlayer.new()
		p.bus = GameSettings.BUS_EFFECTS
		add_child(p)
		_pool_feet.append(p)
	_steps.stride_m = bank.def.footstep_stride_m
	_steps.min_speed = bank.def.footstep_min_speed
	for i in bank.def.pool_loops:
		var p := AudioStreamPlayer3D.new()
		p.bus = GameSettings.BUS_EFFECTS
		p.max_distance = REMOTE_MAX_DISTANCE_M
		p.unit_size = 6.0
		p.volume_db = bank.def.beam_db
		p.stream = bank.stream(&"beam_loop")
		add_child(p)
		_loop_free.append(p)
	if presenter != null:
		presenter.fx_started.connect(_on_fx_started)
		presenter.fx_moved.connect(_on_fx_moved)
		presenter.fx_ended.connect(_on_fx_ended)
	if client != null:
		client.session.snapshot_received.connect(_on_snapshot)
		client.shot_received.connect(_on_shot)
		client.skill_cast_received.connect(_on_remote_cast)
		client.hit_confirmed.connect(_on_hit)
		client.kill_received.connect(_on_kill)


func _on_shot(e: GameEvent) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_shot_ms.get(e.source_net_id, -1000)) < SAME_SHOOTER_GAP_MS:
		return
	_last_shot_ms[e.source_net_id] = now
	var own: bool = e.source_net_id == client.session.own_net_id
	var w: WeaponDef = client.hero_def.weapon if own else _remote_weapon(e.source_net_id)
	var voice := _voice_for(w)
	var stream: AudioStream = voice.get("stream", gunshot)
	var db_off: float = voice.get("db", 0.0)
	var pitch: float = voice.get("pitch", 1.0)
	if own:
		play_2d(stream, OWN_SHOT_DB + db_off, pitch * randf_range(0.95, 1.05))
		return
	var at: Variant = client.call("hero_view_position", e.source_net_id)
	if at != null:
		play_3d(stream, at, REMOTE_SHOT_DB + db_off, pitch * randf_range(0.9, 1.1))


func _remote_weapon(net_id: int) -> WeaponDef:
	var h := _remote_def(net_id)
	return h.weapon if h != null else null


## HeroDef of a remote hero (cached by hero id), or null.
func _remote_def(net_id: int) -> HeroDef:
	var id: StringName = client.hero_id_of(net_id)
	if id == &"":
		return null
	if not _def_cache.has(id):
		var path := "%s/%s.tres" % [ContentDB.SOURCES[ContentDB.HERO][0], id]
		_def_cache[id] = load(path) as HeroDef if ResourceLoader.exists(path) else null
	return _def_cache[id]


## W11-V1: another hero's skill cast (SKILL_CAST event), played 3D at the caster. Own
## casts are skipped here: they are already played from the own cooldowns (_on_own_cast).
func _on_remote_cast(e: GameEvent) -> void:
	if e.source_net_id == client.session.own_net_id:
		return
	var h := _remote_def(e.source_net_id)
	var slot := e.cast_slot()
	if h == null or slot >= h.skills.size() or h.skills[slot] == null:
		return
	var c := bank.skill_cast(h.skills[slot].id)
	if c.is_empty():
		return
	var at: Variant = client.call("hero_view_position", e.source_net_id)
	play_3d(c["stream"], at if at != null else e.position, bank.def.cast_db, c["pitch"])


## Bank voice for a weapon ({} = generic fallback shot).
func _voice_for(w: WeaponDef) -> Dictionary:
	return {} if w == null else bank.weapon_voice(w.sfx_voice)


## W10-W5: own-state sounds read from the snapshot (no protocol change): skill
## cast (cooldown restarted), fork pick (skill flags changed), level up, shop
## buy / sell (mount contents changed).
func _on_snapshot(s: SnapshotData) -> void:
	var c := s.own_combat
	if c != null:
		_reload_sounds(c)
		if _prev_cd.size() == c.skill_cd_left.size():
			for i in c.skill_cd_left.size():
				if c.skill_cd_left[i] > _prev_cd[i]:
					_on_own_cast(i)
				if c.skill_flags[i] != _prev_flags[i] and c.skill_flags[i] > _prev_flags[i]:
					play_ui(&"fork")
		_prev_cd = c.skill_cd_left.duplicate()
		_prev_flags = c.skill_flags.duplicate()
	var p := s.progress
	if p != null:
		if _prev_level >= 0 and p.level > _prev_level:
			play_ui(&"level_up")
		_prev_level = p.level
		if _prev_mounts.size() == p.mount_item.size():
			for i in p.mount_item.size():
				if p.mount_item[i] != _prev_mounts[i]:
					play_ui(&"buy" if p.mount_item[i] >= 0 else &"sell")
		_prev_mounts = p.mount_item.duplicate()


## W11-C1 feel sounds that follow the own body: footsteps (cadence from ground
## speed, silent airborne / dead) and the dry-fire click on an empty magazine.
func _process(delta: float) -> void:
	if client == null or client.body == null or bank == null:
		return
	var st: MotorState = client.body.state
	var dead: bool = client.is_dead()
	var buttons: int = client.last_buttons
	var crouch: bool = (buttons & InputCommand.BTN_CROUCH) != 0
	var speed: float = Vector2(st.velocity.x, st.velocity.z).length()
	if not dead and _steps.advance(speed, st.grounded, delta, bank.def.footstep_crouch_stride_mult if crouch else 1.0):
		_play_footstep(crouch)
	var c: SnapshotData.OwnCombat = client.combat
	var fire: bool = (buttons & InputCommand.BTN_FIRE) != 0
	if fire and not _prev_fire and c != null and not dead and c.ammo <= 0.0 \
			and (c.ammo_flags & AmmoFeed.FLAG_RELOADING) == 0:
		var d := bank.feel_stream(&"dry_fire")
		if d != null:
			play_2d(d, bank.def.feel_db, randf_range(0.95, 1.05))
	_prev_fire = fire


func _play_footstep(crouch: bool) -> void:
	var st := bank.feel_stream(&"footstep")
	if st == null or _pool_feet.is_empty():
		return
	var p := _pool_feet[_next_feet]
	_next_feet = (_next_feet + 1) % _pool_feet.size()
	p.stream = st
	p.volume_db = bank.def.footstep_db - (6.0 if crouch else 0.0)
	p.pitch_scale = randf_range(0.9, 1.1)
	p.play()


## Reload start / finish from the replicated reload flag (finish only when rounds were added).
func _reload_sounds(c: SnapshotData.OwnCombat) -> void:
	var reloading := (c.ammo_flags & AmmoFeed.FLAG_RELOADING) != 0
	if reloading and not _was_reloading:
		_ammo_at_reload = c.ammo
		var s := bank.feel_stream(&"reload_start")
		if s != null:
			play_2d(s, bank.def.feel_db, 1.0)
	elif _was_reloading and not reloading and c.ammo > _ammo_at_reload and not c.dead:
		var s := bank.feel_stream(&"reload_done")
		if s != null:
			play_2d(s, bank.def.feel_db, 1.0)
	_was_reloading = reloading


func _on_own_cast(slot: int) -> void:
	if slot >= client.hero_def.skills.size() or client.hero_def.skills[slot] == null:
		return
	var c := bank.skill_cast(client.hero_def.skills[slot].id)
	if not c.is_empty():
		play_2d(c["stream"], bank.def.cast_db, c["pitch"])


func _on_fx_started(kind: int, at: Vector3, id: int) -> void:
	if kind == SkillEntities.FX_BEAM:
		if _loop_free.is_empty() or _loops.has(id):
			return
		var p: AudioStreamPlayer3D = _loop_free.pop_back()
		p.global_position = at
		p.play()
		_loops[id] = p
		return
	var st := bank.fx_impact(kind)
	if st != null:
		play_3d(st, at, bank.def.impact_db, randf_range(0.95, 1.05))


func _on_fx_moved(_kind: int, at: Vector3, id: int) -> void:
	if _loops.has(id):
		(_loops[id] as AudioStreamPlayer3D).global_position = at


func _on_fx_ended(kind: int, id: int) -> void:
	if kind == SkillEntities.FX_BEAM and _loops.has(id):
		var p: AudioStreamPlayer3D = _loops[id]
		p.stop()
		_loops.erase(id)
		_loop_free.append(p)


## Light UI sound (UI bus) by event name from SfxBankDef.ui.
func play_ui(event: StringName) -> void:
	var st := bank.ui_stream(event)
	if st == null or _pool_ui.is_empty():
		return
	var p := _pool_ui[_next_ui]
	_next_ui = (_next_ui + 1) % _pool_ui.size()
	p.stream = st
	p.volume_db = bank.def.ui_db
	p.play()


func _on_hit(e: GameEvent) -> void:
	var head := (e.flags & GameEvent.FLAG_HEADSHOT) != 0
	play_2d(head_tick if head else hit_tick, HIT_DB, 1.0)


func _on_kill(e: GameEvent) -> void:
	if e.source_net_id == client.session.own_net_id:
		play_2d(kill_chime, KILL_DB, 1.0)


func play_2d(stream: AudioStream, db: float, pitch: float) -> AudioStreamPlayer:
	var p := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % _pool_2d.size()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
	return p


func play_3d(stream: AudioStream, at: Vector3, db: float, pitch: float) -> AudioStreamPlayer3D:
	var p := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % _pool_3d.size()
	p.stream = stream
	p.global_position = at
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
	return p


## Noise crack with a fast decay over a low thump (0.22 s).
static func synth_gunshot() -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pcm := PackedFloat32Array()
	pcm.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.55)  # soften the hiss a little
		var crack := lp * exp(-t * 38.0)
		var thump := sin(TAU * (95.0 - 40.0 * t) * t) * exp(-t * 18.0)
		pcm[i] = clampf(crack * 0.75 + thump * 0.6, -1.0, 1.0)
	return _to_wav(pcm)


## Short sine blip with a click-free attack.
static func synth_tone(hz: float, length_s: float) -> AudioStreamWAV:
	var n := int(RATE * length_s)
	var pcm := PackedFloat32Array()
	pcm.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / 0.004, 1.0) * exp(-t * 60.0)
		pcm[i] = sin(TAU * hz * t) * env * 0.8
	return _to_wav(pcm)


## Two rising notes (kill confirm).
static func synth_chime() -> AudioStreamWAV:
	var n := int(RATE * 0.3)
	var pcm := PackedFloat32Array()
	pcm.resize(n)
	for i in n:
		var t := float(i) / RATE
		var hz := 660.0 if t < 0.11 else 990.0
		var tt := t if t < 0.11 else t - 0.11
		var env := minf(tt / 0.005, 1.0) * exp(-tt * 14.0)
		pcm[i] = (sin(TAU * hz * t) * 0.6 + sin(TAU * hz * 2.0 * t) * 0.15) * env
	return _to_wav(pcm)


static func _to_wav(pcm: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(pcm.size() * 2)
	for i in pcm.size():
		bytes.encode_s16(i * 2, int(clampf(pcm[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
