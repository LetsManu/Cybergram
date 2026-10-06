class_name ClientSfx
extends Node
## Client-only match sounds (presentation; no gameplay state). W21-A1: every
## sound is an AudioEventDef played through `events` (AudioEvents); the
## event table, buses and loudness are in design/audio/audio-events.md.
## Sources (no protocol change; everything is derived on the client):
##   ClientWorld.shot_received       shots (own 2D / enemy + ally 3D), tails,
##                                   Core mount layer, low-ammo tick, music heat,
##                                   ambient duck, damage direction
##   ClientWorld.skill_cast_received remote casts (enemy ults: big moment)
##   own cooldown restarts           own casts
##   ClientWorld.hit_confirmed / kill_received   hit, headshot, kill, assist, own death
##   AbilityPresenter.fx_*           skill impacts / loops / end explosions
##   snapshots                       reload phases, Burnout, damage taken + victim
##                                   impact, heartbeat, level up, Lumen, mounts,
##                                   fork, hardpoint contest / capture / lost,
##                                   Uplink alarm, countdown, Wardlings, enemy
##                                   footsteps and landings
##   own body                        footsteps by surface, jump, landings, dry fire
## It also starts the MusicDirector / VoiceDirector for the match (no-ops headless).

const RATE := 22050
const OWN_SHOT_DB := -6.0
const REMOTE_SHOT_DB := -2.0
const HIT_DB := -8.0
const KILL_DB := -6.0
const REMOTE_MAX_DISTANCE_M := 90.0
## Shotgun pellets arrive as several SHOT events in one tick: play one sound.
const SAME_SHOOTER_GAP_MS := 40
const MIX_PATH := "res://assets/data/audio/audio_mix.tres"
const OWN := AudioEventDef.OwnerFilter.OWN
const ENEMY := AudioEventDef.OwnerFilter.ENEMY
const ALLY := AudioEventDef.OwnerFilter.ALLY
## Legacy UI names (SfxBankDef.ui keys) -> event ids.
const UI_EVENTS := {&"buy": &"ui_buy", &"sell": &"ui_sell", &"level_up": &"ui_levelup", &"fork": &"ui_fork",
	&"hover": &"ui_hover", &"click": &"ui_click", &"lock": &"ui_lock", &"lumen": &"ui_lumen",
	&"denied": &"ui_denied", &"confirm": &"ui_confirm", &"back": &"ui_back", &"error": &"ui_error"}

var client: Node
## Legacy synthesized fallback streams (kept for the in-code fallback / tests).
var gunshot: AudioStreamWAV
var hit_tick: AudioStreamWAV
var head_tick: AudioStreamWAV
var kill_chime: AudioStreamWAV
var bank: SfxBank
var presenter: AbilityPresenter  ## W10-W5: set by ClientWorld (optional)
## W21-A1 event player, mix tuning and code ducks.
var events: AudioEvents
var mix: AudioMixDef
var ducker: MixDucker
var voice: VoiceDirector
var music: MusicDirector
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _next_2d: int = 0
var _next_3d: int = 0
var _def_cache: Dictionary = {}  # hero id -> HeroDef
var _prev_cd: PackedInt32Array = PackedInt32Array()
var _prev_flags: PackedInt32Array = PackedInt32Array()
var _prev_level: int = -1
var _prev_mounts: PackedInt32Array = PackedInt32Array()
var _prev_lumen: int = -1
var _prev_hp: int = -1
var _prev_dead: bool = false
var _prev_burnout: bool = false
var _prev_contested: Dictionary = {}  # hardpoint index -> bool
var _prev_gen_stage: Dictionary = {}  # hardpoint index -> WardGeneratorView.Stage
var _prev_beacon: Dictionary = {}  # hardpoint index -> ProgressionSystem.Beacon
var _prev_supply: Dictionary = {}  # SupplyCacheView -> [stage, serving_me]
var _prev_phase: int = -1
var _countdown_last: int = -1
var _wardlings: Dictionary = {}  # net id -> last position (alive last snapshot)
var _wardlings_primed: bool = false
var _fx_pos: Dictionary = {}  # fx id -> last position (end sounds)
var _remote: Dictionary = {}  # net id -> {clock, pos, grounded, vy}
var _steps := FootstepClock.new()
var _was_reloading: bool = false
var _mag_out_left: float = -1.0
var _ammo_at_reload: float = 0.0
var _prev_fire: bool = false
var _was_grounded: bool = true
var _prev_vy: float = 0.0
var _last_shot_ms: Dictionary = {}  # shooter net id -> msec
var _shots_at_me: Dictionary = {}  # shooter net id -> msec of a SHOT ending near the own hero
var _hit_victims: Dictionary = {}  # victim net id -> msec of the last own hit
var _heartbeat_left: float = 0.0


func _ready() -> void:
	GameSettings.shared().apply_audio()
	gunshot = synth_gunshot()
	hit_tick = synth_tone(1700.0, 0.05)
	head_tick = synth_tone(2600.0, 0.06)
	kill_chime = synth_chime()
	bank = SfxBank.shared()
	mix = load(MIX_PATH) as AudioMixDef
	ducker = MixDucker.new(mix)
	for i in bank.def.pool_2d:
		var p := AudioStreamPlayer.new()
		p.bus = GameSettings.BUS_WEAPONS
		add_child(p)
		_pool_2d.append(p)
	for i in bank.def.pool_3d:
		var p := AudioStreamPlayer3D.new()
		p.bus = GameSettings.BUS_WEAPONS
		p.max_distance = REMOTE_MAX_DISTANCE_M
		p.unit_size = 8.0
		add_child(p)
		_pool_3d.append(p)
	events = AudioEvents.new()
	events.name = "Events"
	events.listener_fn = listener_position
	add_child(events)
	_steps.stride_m = bank.def.footstep_stride_m
	_steps.min_speed = bank.def.footstep_min_speed
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
		client.match_phase_changed.connect(_on_phase)
		client.hardpoint_owner_changed.connect(on_hardpoint_owner_changed)
		_start_directors()


## W21-A1: announcer + music for this match; both no-op headless.
func _start_directors() -> void:
	voice = VoiceDirector.new()
	voice.name = "Voice"
	voice.events = events
	add_child(voice)
	voice.bind_client(client)
	voice.announced.connect(func(line: StringName, _k: String, pri: int) -> void:
		if line == &"uplink_under_attack":
			events.play(&"objective_uplink_alarm")
		if pri >= mix.big_moment_line_priority:
			ducker.note_big_moment())
	if DisplayServer.get_name() != "headless":
		music = MusicDirector.shared()
		music.bind_client(client)


func _exit_tree() -> void:
	GameSettings.set_bus_duck_db(GameSettings.BUS_MUSIC, 0.0)
	GameSettings.set_bus_duck_db(GameSettings.BUS_AMBIENT, 0.0)


## Listener world position (camera, else the own body), or null before spawn.
func listener_position() -> Variant:
	if client == null:
		return null
	if client.rig != null and client.rig.camera != null and client.rig.camera.is_inside_tree():
		return client.rig.camera.global_position
	if client.body != null:
		return client.body.state.position
	return null


## OwnerFilter of whoever `net_id` is relative to the local player.
func relation_of(net_id: int) -> int:
	if net_id == client.session.own_net_id:
		return OWN
	var v: HeroView = client.view(net_id)
	if v != null and v.team == client.own_team():
		return ALLY
	return ENEMY


func _dist(at: Variant) -> float:
	var lis: Variant = listener_position()
	if at is Vector3 and lis is Vector3:
		return (lis as Vector3).distance_to(at)
	return 0.0


# ------------------------------------------------------------------ shots
func _on_shot(e: GameEvent) -> void:
	var now := Time.get_ticks_msec()
	if client.body != null and e.position.distance_to(client.body.state.position + Vector3(0, 1, 0)) <= mix.damage_shot_radius_m:
		_shots_at_me[e.source_net_id] = now
	if now - int(_last_shot_ms.get(e.source_net_id, -1000)) < SAME_SHOOTER_GAP_MS:
		return
	_last_shot_ms[e.source_net_id] = now
	var rel := relation_of(e.source_net_id)
	var w: WeaponDef = client.hero_def.weapon if rel == OWN else _remote_weapon(e.source_net_id)
	var v: StringName = w.sfx_voice if w != null else &""
	var at: Variant = null if rel == OWN else client.call("hero_view_position", e.source_net_id)
	var dist := 0.0 if rel == OWN else _dist(at)
	ducker.note_weapon(dist)
	var played: Node = null
	if v != &"" and events.bank.has(StringName("weapon_%s_shot_own" % v)):
		var suffix := "own" if rel == OWN else ("ally" if rel == ALLY else "enemy")
		played = events.play(StringName("weapon_%s_shot_%s" % [v, suffix]), rel, at)
		events.play(StringName("weapon_%s_tail_%s" % [v, "own" if rel == OWN else "remote"]), rel, at)
	elif rel == OWN:
		played = play_2d(gunshot, OWN_SHOT_DB, randf_range(0.95, 1.05))
	elif at != null:
		played = play_3d(gunshot, at, REMOTE_SHOT_DB, randf_range(0.9, 1.1))
	if rel == OWN and played != null:
		_own_shot_layers(w)


## Core mount tonal layer and the low-ammo tick (own shots only).
func _own_shot_layers(w: WeaponDef) -> void:
	var p = client.progress
	if p != null and p.mount_tier.size() > 0 and p.mount_item[0] >= 0 and p.mount_tier[0] > 0:
		events.play(StringName("weapon_core_layer_t%d" % clampi(p.mount_tier[0], 1, 3)), OWN)
	var c: SnapshotData.OwnCombat = client.combat
	if c != null and c.ammo_capacity > 0 and c.ammo / float(c.ammo_capacity) <= mix.low_ammo_frac:
		var mech := w != null and w.feed_kind == WeaponDef.FeedKind.MAGAZINE
		events.play(&"weapon_low_ammo_mech" if mech else &"weapon_low_ammo_mana", OWN)


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


# ------------------------------------------------------------------ casts
## W11-V1: another hero's skill cast, 3D at the caster. Own casts come from cooldowns.
func _on_remote_cast(e: GameEvent) -> void:
	if e.source_net_id == client.session.own_net_id:
		return
	var h := _remote_def(e.source_net_id)
	var slot := e.cast_slot()
	if h == null or slot >= h.skills.size() or h.skills[slot] == null:
		return
	var rel := relation_of(e.source_net_id)
	var at: Variant = client.call("hero_view_position", e.source_net_id)
	var id := StringName("%s_cast_%s" % [h.skills[slot].id, "ally" if rel == ALLY else "enemy"])
	if events.play(id, rel, at if at != null else e.position) != null and rel == ENEMY and h.skills[slot].ultimate:
		ducker.note_big_moment()


func _on_own_cast(slot: int) -> void:
	if slot >= client.hero_def.skills.size() or client.hero_def.skills[slot] == null:
		return
	events.play(StringName("%s_cast_own" % client.hero_def.skills[slot].id), OWN)


# ------------------------------------------------------------- hits / kills
func _on_hit(e: GameEvent) -> void:
	_hit_victims[e.target_net_id] = Time.get_ticks_msec()
	var head := (e.flags & GameEvent.FLAG_HEADSHOT) != 0
	if events.play(&"combat_headshot" if head else &"combat_hit", OWN) == null and not events.bank.has(&"combat_hit"):
		play_2d(head_tick if head else hit_tick, HIT_DB, 1.0)


func _on_kill(e: GameEvent) -> void:
	var own: int = client.session.own_net_id
	if e.source_net_id == own and e.target_net_id != own:
		events.play(&"combat_kill", OWN)
	elif e.target_net_id == own:
		events.play(&"combat_own_death", OWN)
	elif Time.get_ticks_msec() - int(_hit_victims.get(e.target_net_id, -100000)) <= int(mix.assist_window_s * 1000.0):
		events.play(&"combat_assist", OWN)
	_hit_victims.erase(e.target_net_id)


func _on_phase(phase: int) -> void:
	if phase == MatchRules.Phase.SUDDEN_DEATH and _prev_phase != phase:
		events.play(&"objective_sudden_death")
		ducker.note_big_moment()
	_prev_phase = phase


# --------------------------------------------------------------- snapshots
## Own-state and world sounds derived from the snapshot (no protocol change).
func _on_snapshot(s: SnapshotData) -> void:
	var c := s.own_combat
	if c != null:
		_reload_sounds(c)
		_burnout_sounds(c)
		_damage_sounds(c)
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
		if _prev_lumen >= 0 and p.lumen > _prev_lumen and not _mounts_changed(p):
			play_ui(&"lumen")
		_prev_lumen = p.lumen
		if _prev_mounts.size() == p.mount_item.size():
			for i in p.mount_item.size():
				if p.mount_item[i] != _prev_mounts[i]:
					play_ui(&"buy" if p.mount_item[i] >= 0 else &"sell")
		_prev_mounts = p.mount_item.duplicate()
	_objective_sounds(s)
	_wardling_sounds(s)
	_remote_states(s)
	for f in s.fx:  # end sounds (grenade / mine / charge) play where the FX was last seen
		_fx_pos[f.id] = f.position


func _mounts_changed(p: SnapshotData.ProgressState) -> bool:
	return _prev_mounts.size() == p.mount_item.size() and _prev_mounts != p.mount_item


## Reload start / magazine out (after mag_out_delay_s) / done (only when rounds were added).
func _reload_sounds(c: SnapshotData.OwnCombat) -> void:
	var reloading := (c.ammo_flags & AmmoFeed.FLAG_RELOADING) != 0
	var v: StringName = client.hero_def.weapon.sfx_voice if client.hero_def.weapon != null else &""
	if reloading and not _was_reloading:
		_ammo_at_reload = c.ammo
		_play_or_feel(StringName("weapon_%s_reload_start_own" % v), &"reload_start")
		_mag_out_left = mix.mag_out_delay_s
	elif _was_reloading and not reloading and c.ammo > _ammo_at_reload and not c.dead:
		_play_or_feel(StringName("weapon_%s_reload_done_own" % v), &"reload_done")
		_mag_out_left = -1.0
	_was_reloading = reloading


## Plays an event; when the id is unknown falls back to the legacy feel archetype.
func _play_or_feel(id: StringName, feel: StringName) -> bool:
	if events.bank.has(id):
		return events.play(id, OWN) != null
	var st := bank.feel_stream(feel)
	if st != null:
		play_2d(st, bank.def.feel_db, 1.0)
	return st != null


func _burnout_sounds(c: SnapshotData.OwnCombat) -> void:
	var burn := (c.ammo_flags & AmmoFeed.FLAG_BURNOUT) != 0
	if burn and not _prev_burnout:
		events.play(&"weapon_burnout_own", OWN)
	elif _prev_burnout and not burn and not c.dead:
		events.play(&"weapon_mana_regen_own", OWN)
	_prev_burnout = burn


## Damage taken (panned toward the attacker), the victim impact, own death heartbeat state.
func _damage_sounds(c: SnapshotData.OwnCombat) -> void:
	if _prev_hp >= 0 and c.hp < _prev_hp and not c.dead and not _prev_dead:
		var src := _recent_attacker()
		var lis: Variant = listener_position()
		var at: Variant = lis
		if src >= 0 and lis is Vector3:
			var from: Variant = client.call("hero_view_position", src)
			if from is Vector3 and (from as Vector3).distance_to(lis) > 0.1:
				at = (lis as Vector3) + ((from as Vector3) - (lis as Vector3)).normalized() * 1.5
		events.play(&"combat_damage_taken", OWN, at)
		var w := _remote_weapon(src) if src >= 0 else null
		var mana := w != null and w.feed_kind == WeaponDef.FeedKind.MANA
		events.play(&"impact_mana_victim" if mana else &"impact_standard_victim", OWN)
	_prev_hp = c.hp
	_prev_dead = c.dead


func _recent_attacker() -> int:
	var now := Time.get_ticks_msec()
	var best := -1
	var best_t := -1
	for id in _shots_at_me:
		var t: int = _shots_at_me[id]
		if now - t <= mix.damage_shot_window_ms and t > best_t and id != client.session.own_net_id:
			best = id
			best_t = t
	return best


func _objective_sounds(s: SnapshotData) -> void:
	var team: int = client.own_team()
	_generator_sounds(s)
	_beacon_sounds(s)
	_supply_sounds()
	for i in s.hardpoints.size():
		var h := s.hardpoints[i]
		var mine := h.owner == team or h.capturing_team == team
		if h.contested and not bool(_prev_contested.get(i, false)) and mine:
			events.play(&"objective_contest")
		_prev_contested[i] = h.contested
	var ms := s.match_state
	if ms != null and ms.phase == MatchRules.Phase.DEPLOY and ms.next_phase_s >= 0.0:
		var left := int(ceilf(ms.next_phase_s - ms.time_s))
		if left != _countdown_last and left >= 1 and left <= mix.countdown_ticks_s:
			events.play(&"ui_countdown_tick")
		_countdown_last = left
	elif ms != null and ms.phase == MatchRules.Phase.SKIRMISH and _countdown_last >= 1 and _countdown_last <= mix.countdown_ticks_s:
		events.play(&"ui_countdown_go")
		_countdown_last = -1


## Ward Generator sounds (docs/assets/ward_generator.md), from the same stage
## function as its view: shield down, each crack stage, the breach.
func _generator_sounds(s: SnapshotData) -> void:
	var md: MapDef = client.map_def if client != null else null
	for i in s.hardpoints.size():
		var h := s.hardpoints[i]
		if h.task != HardpointDef.TaskKind.BREACH:
			continue
		var st := WardGeneratorView.stage_of(h.owner, h.shielded, h.gen_frac, h.breach_phase2)
		var prev: int = _prev_gen_stage.get(i, -1)
		_prev_gen_stage[i] = st
		var ev := generator_event(prev, st)
		if ev == &"":
			continue
		var at: Variant = null
		if md != null:
			var hd := md.hardpoint_global(i)
			if hd != null:
				at = hd.position + Vector3(0, 1.5, 0)
		events.play(ev, AudioEventDef.OwnerFilter.ANY, at)


## The generator sound for a stage change (pure; "" = none). The first sample
## (prev -1) only records the stage.
static func generator_event(prev: int, now: int) -> StringName:
	var S := WardGeneratorView.Stage
	if prev < 0 or prev == now:
		return &""
	if now == S.BREACHED:
		return &"generator_breach"
	if prev == S.SHIELDED and now != S.NEUTRAL:
		return &"generator_shield_down"
	if now >= S.CRACK_1 and now <= S.CRACK_3 and now > prev:
		return &"generator_crack"
	return &""


## Supply Cache sounds (docs/assets/supply_cache.md): online for the new owner,
## and the own hero starting to use it.
func _supply_sounds() -> void:
	if client == null or not client.has_method("supply_views"):
		return
	for sv: SupplyCacheView in client.supply_views():
		var prev: Array = _prev_supply.get(sv, [-1, false])
		var now := [sv.stage, sv.serving_me()]
		_prev_supply[sv] = now
		var ev := supply_event(int(prev[0]), int(now[0]), bool(prev[1]), bool(now[1]))
		if ev != &"":
			events.play(ev, AudioEventDef.OwnerFilter.ANY, sv.global_position + Vector3(0, 0.8, 0))


## The Supply Cache sound for a change (pure; "" = none; prev stage -1 = first sample).
static func supply_event(prev_stage: int, stage: int, was_mine: bool, mine: bool) -> StringName:
	if mine and not was_mine:
		return &"supply_use"
	if prev_stage >= 0 and stage == SupplyCacheView.Stage.SERVING and prev_stage == SupplyCacheView.Stage.SWITCHING:
		return &"supply_online"
	return &""


## Forward Beacon sounds (docs/assets/forward_beacon.md) at the owner's pad:
## attunement starts, the Beacon is ready, it comes under attack.
func _beacon_sounds(s: SnapshotData) -> void:
	var md: MapDef = client.map_def if client != null else null
	for i in s.hardpoints.size():
		var h := s.hardpoints[i]
		var prev: int = _prev_beacon.get(i, -1)
		_prev_beacon[i] = h.beacon
		var ev := beacon_event(prev, h.beacon)
		if ev == &"":
			continue
		var at: Variant = null
		if md != null:
			var hd := md.hardpoint_global(i)
			if hd != null:
				for sp: Array in ForwardBeaconView.spots(md, hd):
					if sp[0] == h.owner:
						at = (sp[1] as Vector3) + Vector3(0, 1.0, 0)
		events.play(ev, AudioEventDef.OwnerFilter.ANY, at)


## The Beacon sound for a state change (pure; "" = none). The first sample
## (prev -1) only records the state.
static func beacon_event(prev: int, now: int) -> StringName:
	var B := ProgressionSystem.Beacon
	if prev < 0 or prev == now:
		return &""
	match now:
		B.ATTUNING:
			return &"beacon_attune"
		B.READY:
			return &"beacon_ready"
		B.UNDER_ATTACK:
			return &"beacon_threat"
	return &""


## Hardpoint capture / loss jingles (ClientWorld.hardpoint_owner_changed is
## consumed by VoiceDirector for the lines; the world jingle plays here).
func on_hardpoint_owner_changed(_index: int, old_team: int, new_team: int) -> void:
	var team: int = client.own_team()
	if new_team == team:
		events.play(&"objective_capture")
	elif old_team == team:
		events.play(&"objective_lost")


func _wardling_sounds(s: SnapshotData) -> void:
	var seen := {}
	for w in s.wardlings:
		seen[w.net_id] = true
		if not _wardlings.has(w.net_id) and _wardlings_primed:
			events.play(&"wardling_spawn", AudioEventDef.OwnerFilter.ANY, w.position)
		_wardlings[w.net_id] = w.position
	for id in _wardlings.keys():
		if not seen.has(id):
			events.play(&"wardling_death", AudioEventDef.OwnerFilter.ANY, _wardlings[id])
			_wardlings.erase(id)
	_wardlings_primed = true  # the first snapshot's Wardlings are not "spawns"
	for b in s.bolts:
		events.play(&"wardling_attack", AudioEventDef.OwnerFilter.ANY, b[0])


## Remote grounded / vertical speed for enemy landings (footsteps follow the views in _process).
func _remote_states(s: SnapshotData) -> void:
	for e in s.entities:
		if e.net_id == s.own_net_id:
			continue
		var r: Dictionary = _remote.get(e.net_id, {})
		if r.is_empty():
			r = {"clock": FootstepClock.new(mix.remote_stride_m, mix.remote_min_speed), "pos": e.position,
				"grounded": e.grounded, "vy": 0.0}
			_remote[e.net_id] = r
		if e.grounded and not bool(r["grounded"]) and not e.dead and relation_of(e.net_id) == ENEMY:
			var vy: float = r["vy"]
			if vy <= -mix.land_heavy_mps:
				events.play(&"move_land_heavy_enemy", ENEMY, e.position)
			elif vy <= -mix.land_light_mps:
				events.play(&"move_land_light_enemy", ENEMY, e.position)
		elif not e.grounded and bool(r["grounded"]) and e.velocity.y > 1.0 and relation_of(e.net_id) == ENEMY:
			events.play(&"move_jump_enemy", ENEMY, e.position)
		r["grounded"] = e.grounded
		r["vy"] = e.velocity.y


# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	ducker.step(delta)
	GameSettings.set_bus_duck_db(GameSettings.BUS_MUSIC, ducker.music_db)
	GameSettings.set_bus_duck_db(GameSettings.BUS_AMBIENT, ducker.ambient_db)
	if client == null or client.body == null or bank == null:
		return
	if _mag_out_left > 0.0:
		_mag_out_left -= delta
		if _mag_out_left <= 0.0 and _was_reloading:
			var v: StringName = client.hero_def.weapon.sfx_voice if client.hero_def.weapon != null else &""
			events.play(StringName("weapon_%s_reload_mag_out_own" % v), OWN)
	var st: MotorState = client.body.state
	var dead: bool = client.is_dead()
	var buttons: int = client.last_buttons
	var crouch: bool = (buttons & InputCommand.BTN_CROUCH) != 0
	var speed: float = Vector2(st.velocity.x, st.velocity.z).length()
	var wet: bool = client.map_def != null and client.map_def.water_factor_at(st.position) < 1.0
	if not dead and _steps.advance(speed, st.grounded, delta, bank.def.footstep_crouch_stride_mult if crouch else 1.0) and not wet:
		_play_footstep(crouch, st.position)
	_own_air(st, dead)
	var c: SnapshotData.OwnCombat = client.combat
	var fire: bool = (buttons & InputCommand.BTN_FIRE) != 0
	if fire and not _prev_fire and c != null and not dead and c.ammo <= 0.0 \
			and (c.ammo_flags & AmmoFeed.FLAG_RELOADING) == 0:
		if events.play(&"weapon_dry_fire", OWN) == null and not events.bank.has(&"weapon_dry_fire"):
			var d := bank.feel_stream(&"dry_fire")
			if d != null:
				play_2d(d, bank.def.feel_db, randf_range(0.95, 1.05))
	_prev_fire = fire
	_heartbeat(c, delta)
	_remote_footsteps(delta)


func _own_air(st: MotorState, dead: bool) -> void:
	if not dead:
		if _was_grounded and not st.grounded and st.velocity.y > 1.0:
			events.play(&"move_jump_own", OWN)
		elif not _was_grounded and st.grounded:
			if _prev_vy <= -mix.land_heavy_mps:
				events.play(&"move_land_heavy_own", OWN)
			elif _prev_vy <= -mix.land_light_mps:
				events.play(&"move_land_light_own", OWN)
	_was_grounded = st.grounded
	_prev_vy = st.velocity.y


func _heartbeat(c: SnapshotData.OwnCombat, delta: float) -> void:
	if c == null or c.dead or c.max_hp <= 0:
		_heartbeat_left = 0.0
		return
	var frac := float(c.hp) / float(c.max_hp)
	if frac >= mix.heartbeat_hp_frac:
		_heartbeat_left = 0.0
		return
	_heartbeat_left -= delta
	if _heartbeat_left <= 0.0:
		events.play(&"combat_heartbeat", OWN)
		var k := clampf(frac / maxf(mix.heartbeat_hp_frac, 0.01), 0.0, 1.0)
		_heartbeat_left = 1.0 / lerpf(mix.heartbeat_rate_max_hz, mix.heartbeat_rate_min_hz, k)


## Enemy footsteps from the interpolated views (3D, within the event's 20 m).
func _remote_footsteps(delta: float) -> void:
	if delta <= 0.0:
		return
	var views: Dictionary = client.remote_views()
	for id in views:
		var r: Dictionary = _remote.get(id, {})
		if r.is_empty():
			continue
		var v: HeroView = views[id]
		var pos := v.global_position if v.is_inside_tree() else v.position
		var prev: Vector3 = r["pos"]
		r["pos"] = pos
		if relation_of(id) != ENEMY:
			continue
		var spd := Vector2(pos.x - prev.x, pos.z - prev.z).length() / delta
		var clock: FootstepClock = r["clock"]
		if clock.advance(spd, bool(r["grounded"]), delta):
			events.play(StringName("footstep_%s_enemy" % surface_at(pos)), ENEMY, pos)


func _play_footstep(crouch: bool, at: Vector3) -> void:
	var id := StringName("footstep_%s_own" % surface_at(at))
	if events.bank.has(id):
		events.play(id, OWN, null, -6.0 if crouch else 0.0)
		return
	var st := bank.feel_stream(&"footstep")
	if st != null:
		play_2d(st, bank.def.footstep_db - (6.0 if crouch else 0.0), randf_range(0.9, 1.1))


## Footstep surface at a world position: water, metal (hardpoint platforms),
## grate (raised catwalks), concrete.
func surface_at(pos: Vector3) -> String:
	if client.map_def != null and client.map_def.water_factor_at(pos) < 1.0:
		return "water"
	for d in client.hardpoint_defs():
		if Vector2(pos.x - d.position.x, pos.z - d.position.z).length() <= d.zone_radius \
				and pos.y >= d.position.y - 1.0 and pos.y <= d.position.y + d.zone_height:
			return "metal"
	return "grate" if pos.y >= mix.grate_min_y else "concrete"


# -------------------------------------------------------------- skill FX
func _on_fx_started(kind: int, at: Vector3, id: int) -> void:
	_fx_pos[id] = at
	var m: Dictionary = mix.fx_events.get(kind, {})
	if m.has("loop"):
		events.start_loop(m["loop"], id, at)
	if m.has("start"):
		events.play(m["start"], AudioEventDef.OwnerFilter.ANY, at)
	if not m.is_empty():
		return
	var st := bank.fx_impact(kind)  # legacy mapping for kinds without an event
	if st != null:
		play_3d(st, at, bank.def.impact_db, randf_range(0.95, 1.05))


func _on_fx_moved(_kind: int, at: Vector3, id: int) -> void:
	_fx_pos[id] = at
	events.move_loop(id, at)


func _on_fx_ended(kind: int, id: int) -> void:
	events.stop_loop(id)
	var m: Dictionary = mix.fx_events.get(kind, {})
	var at: Variant = _fx_pos.get(id)
	_fx_pos.erase(id)
	if m.has("end") and at is Vector3:
		events.play(m["end"], AudioEventDef.OwnerFilter.ANY, at)
		ducker.note_big_moment()


# --------------------------------------------------------------- helpers
## Light UI sound by legacy name (buy, sell, level_up, fork, hover, click, lock, lumen, ...).
func play_ui(event: StringName) -> void:
	var id: StringName = UI_EVENTS.get(event, StringName("ui_%s" % event))
	if events != null and events.bank.has(id):
		events.play(id)
		return
	var st := bank.ui_stream(event)
	if st != null:
		play_2d(st, bank.def.ui_db, 1.0)


## Legacy direct 2D play (fallback streams; bounded pool).
func play_2d(stream: AudioStream, db: float, pitch: float) -> AudioStreamPlayer:
	var p := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % _pool_2d.size()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
	return p


## Legacy direct 3D play (fallback streams; bounded pool).
func play_3d(stream: AudioStream, at: Vector3, db: float, pitch: float) -> AudioStreamPlayer3D:
	var p := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % _pool_3d.size()
	p.stream = stream
	if p.is_inside_tree():
		p.global_position = at
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
	return p


## Noise crack with a fast decay over a low thump (0.22 s). In-code fallback.
static func synth_gunshot() -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pcm := PackedFloat32Array()
	pcm.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.55)
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


## Two rising notes (kill confirm fallback).
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
