class_name HudRoot
extends CanvasLayer
## The single in-match HUD (E12, design/ux/hud.md §3). Replaces the per-epic
## overlays (CombatHud, MatchHud, ObjectiveStrip, SquadStrip, EconomyHud).
##
## Layout: one design canvas (HudLayout: 1920x1080 units at 1080p, scaled for
## any resolution, clamped to a 16:9 centre region on ultrawide) with a 3% safe
## margin and the hud.md §3.2 zones as anchored Controls:
##   top-centre    MatchHeader + FrontStrip      top-right   KillFeed
##   right-middle  ObjectiveTracker, ToastLane   centre      CenterFeedback
##   bottom-left   SquadStrip + VitalsPanel      bottom-ctr  SkillBar (+ Med-Pack)
##   bottom-right  WeaponPanel
## Overlays: ArmoryPanel (left 60%), DeathScreen, Scoreboard (hold Tab / View),
## EndBanner. World-anchored plates and damage numbers draw in an unscaled
## WorldOverlay underneath. Context rules (hud.md §14): Armory open hides
## skills, squad strip and kill feed; scoreboard hides the gameplay HUD except
## HP and crosshair; dead hides the gameplay HUD except the header and skills.
##
## v0.12 (design/ux/hud-v0.12.md): no boxes; HudScrims draws a soft ink band
## at the top and bottom of the screen, and this node runs the idle fade
## (HudSettings.idle_fade: Off / 4 s / 8 s after the last combat event; parts
## of each widget fade through ctx.idle_k over 300 ms, instantly back on
## damage, firing, a cast, a hit, a kill or an objective change; snaps with
## reduce motion) and tracks keyboard vs gamepad for the key chips.
##
## Settings keys (until a settings menu exists; saved to user://settings.cfg):
## F6 colour-blind preset, F7 / F8 UI scale -/+, F9 damage numbers.
## Reads ClientWorld (replicated state, signals); writes only UI requests
## through PlayerInputSource.

## Set by AppRoot (the GameSession node).
var session: Node
var ctx: HudContext

var _world: WorldOverlay
var _root: Control
var _safe: Control
var _header: MatchHeader
var _front: FrontStrip
## W14: lane minimap (all lanes' hardpoints and fronts).
var _minimap: LaneMinimap
var _kill_feed: KillFeed
var _tracker: ObjectiveTracker
var _toasts: ToastLane
var _center: CenterFeedback
var _squad: SquadStrip
var _vitals: VitalsPanel
var _skills: SkillBar
var _weapon: WeaponPanel
var _armory: ArmoryPanel
var _death: DeathScreen
var _scoreboard: Scoreboard
var _end: EndBanner
var _task_cue: HudWidget
var _probe_t: float = 0.0
var _fkeys: Dictionary = {}
var _shot_t: float = 0.0
var _scrims: HudScrims
## Idle fade: seconds since the last combat event and the signature of the
## watched state (HP, ammo, cooldowns, objective) at the previous frame.
var _idle_t: float = 0.0
var _idle_sig: int = -1
var _last_hp: int = -1
var _last_ammo: float = 0.0
var _last_cd: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _keys_t: float = 0.0


func _ready() -> void:
	layer = 5
	HudStrings.ensure_loaded()
	var tuning := load(HudTuningDef.DEFAULT_PATH) as HudTuningDef
	if tuning == null:
		tuning = HudTuningDef.new()
	ctx = HudContext.new(session, HudSettings.load_user(OS.get_cmdline_user_args()), tuning)
	ctx.roster.probe = OfflineRosterProbe.make(session)
	_world = WorldOverlay.new()
	_world.set_anchors_preset(Control.PRESET_FULL_RECT)
	_world.bind(ctx)
	add_child(_world)
	_root = Control.new()
	_root.name = "HudCanvas"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = ctx.theme
	add_child(_root)
	_safe = Control.new()
	_safe.name = "SafeArea"
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrims = HudScrims.new()
	_scrims.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrims.bind(ctx)
	_root.add_child(_scrims)
	_root.add_child(_safe)
	_build()
	var c := ctx.client
	if c != null:
		c.kill_received.connect(_on_kill)
		c.hit_confirmed.connect(_on_hit)
		c.session.snapshot_received.connect(_on_snapshot)
	get_viewport().size_changed.connect(_relayout)
	_relayout()


func _build() -> void:
	# v0.12 top-centre unit (variant D): clock plate + framed Uplink bars, then
	# the single lane line under the plate.
	var z_top := _zone("TopCentre", 0.235, -0.03, 0.765, 0.17)
	_header = _add(MatchHeader.new(), z_top, Rect2(0, 0, 1, 0), Vector2(0, MatchHeader.H)) as MatchHeader
	_front = _add(FrontStrip.new(), z_top, Rect2(0, 0, 1, 0), Vector2(MatchHeader.H + 8.0, MatchHeader.H + 8.0 + FrontStrip.HEIGHT)) as FrontStrip
	_minimap = _fill(LaneMinimap.new(), _zone("TopLeft", -0.012, -0.012, 0.2, 0.25)) as LaneMinimap
	_kill_feed = _fill(KillFeed.new(), _zone("TopRight", 0.7, -0.005, 1.0, 0.22)) as KillFeed
	_tracker = _fill(ObjectiveTracker.new(), _zone("RightMiddle", 0.76, 0.26, 1.0, 0.40)) as ObjectiveTracker
	# E14: minimal Plant / Breach cue under the tracker (Cell carried, channel, Generator).
	_task_cue = _add(TaskCue.new(), _tracker.get_parent(), Rect2(0, 0, 1, 0), Vector2(ObjectiveTracker.H + 6.0, ObjectiveTracker.H + 6.0 + TaskCue.H))
	_toasts = _fill(ToastLane.new(), _zone("Toasts", 0.70, 0.48, 1.0, 0.64)) as ToastLane
	# W16-SDWATER: "OUTSIDE THE RING" (Sudden Death) under the front strip.
	_fill(RingWarning.new(), _zone("RingWarning", 0.30, 0.71, 0.70, 0.79))  # below the centre: clear of the 3-row front strip and the damage ring
	_center = _fill(CenterFeedback.new(), _zone("Centre", 0.30, 0.30, 0.70, 0.70)) as CenterFeedback
	var z_bl := _zone("BottomLeft", 0.0, 0.70, 0.34, 1.0)
	_vitals = _fill(VitalsPanel.new(), z_bl) as VitalsPanel
	_squad = _add(SquadStrip.new(), z_bl, Rect2(0, 1, 1, 1), Vector2(-(VitalsPanel.H + SquadStrip.H + 24.0), -(VitalsPanel.H + 24.0))) as SquadStrip
	_skills = _fill(SkillBar.new(), _zone("BottomCentre", 0.3, 0.72, 0.7, 1.0)) as SkillBar
	_weapon = _fill(WeaponPanel.new(), _zone("BottomRight", 0.70, 0.74, 1.0, 1.0)) as WeaponPanel
	_armory = _fill(ArmoryPanel.new(), _zone("Armory", 0.02, 0.04, 0.98, 0.96)) as ArmoryPanel
	_death = _fill(DeathScreen.new(), _zone("Death", 0.2, 0.50, 0.8, 0.84)) as DeathScreen
	_end = _fill(EndBanner.new(), _zone("End", 0.0, 0.20, 1.0, 0.36)) as EndBanner
	_scoreboard = _fill(Scoreboard.new(), _zone("Scoreboard", 0.0, 0.0, 1.0, 1.0)) as Scoreboard


## A zone Control anchored to fractions of the safe area.
func _zone(n: String, l: float, t: float, r: float, b: float) -> Control:
	var z := Control.new()
	z.name = n
	z.mouse_filter = Control.MOUSE_FILTER_IGNORE
	z.anchor_left = l
	z.anchor_top = t
	z.anchor_right = r
	z.anchor_bottom = b
	_safe.add_child(z)
	return z


func _fill(w: HudWidget, zone: Control) -> HudWidget:
	w.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.bind(ctx)
	zone.add_child(w)
	return w


## Adds `w` with anchors (x=left, y=top, w=right, h=bottom) and vertical offsets (top, bottom).
func _add(w: HudWidget, zone: Control, anchors: Rect2, v_offsets: Vector2) -> HudWidget:
	w.anchor_left = anchors.position.x
	w.anchor_top = anchors.position.y
	w.anchor_right = anchors.size.x
	w.anchor_bottom = anchors.size.y
	w.offset_top = v_offsets.x
	w.offset_bottom = v_offsets.y
	w.bind(ctx)
	zone.add_child(w)
	return w


func _relayout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var lay := HudLayout.compute(vp, ctx.settings.ui_scale, ctx.settings.clamp_16_9, ctx.tuning)
	ctx.scale = lay.scale
	_root.position = lay.region.position
	_root.scale = Vector2(lay.scale, lay.scale)
	_root.size = lay.canvas
	var m := ctx.tuning.safe_margin
	_safe.position = lay.canvas * m
	_safe.size = lay.canvas * (1.0 - 2.0 * m)


func _process(delta: float) -> void:
	var c := ctx.client
	_settings_keys()
	_debug_screenshot(delta)
	if c == null:
		return
	_probe_t -= delta
	if _probe_t <= 0.0:
		_probe_t = 0.5
		ctx.roster.refresh_probe()
	_armory.poll()
	_death.poll()
	_idle_fade(c, delta)
	_keys_t -= delta
	if _keys_t <= 0.0:
		_keys_t = 1.0
		ctx.key_labels.clear()  # rebinding in the pause menu shows on the next refresh
	ctx.armory_open = _armory.open
	var at := c.progress != null and (c.progress.flags & SnapshotData.ProgressState.FLAG_AT_ARMORY) != 0
	ctx.armory_prompt = at and not _armory.open and not c.is_dead()
	var held := InputBindings.is_down(&"scoreboard", KEY_TAB) or Input.is_joy_button_pressed(0, JOY_BUTTON_BACK)
	ctx.scoreboard_open = (held or ctx.settings.debug_scoreboard) and not _armory.open
	_apply_context(c)


## hud.md §14 HUD states by context.
func _apply_context(c: ClientWorld) -> void:
	var dead := c.is_dead()
	var board := ctx.scoreboard_open
	var shop := ctx.armory_open
	var gameplay := not board and not dead
	_scrims.set_flags(not board, gameplay and not shop and (c.match_state == null or c.match_state.phase != MatchRules.Phase.END))
	_header.visible = not board
	_front.visible = not board and not shop
	_minimap.visible = gameplay
	_kill_feed.visible = gameplay and not shop
	_tracker.visible = gameplay and not shop
	if _task_cue != null:
		_task_cue.visible = gameplay and not shop
	_toasts.visible = not board
	_center.visible = not dead
	_squad.visible = gameplay and not shop
	_vitals.visible = not dead
	_skills.visible = not board and not shop
	_weapon.visible = gameplay
	_armory.visible = shop or _armory.wants_draw()
	_death.visible = dead and not board
	_end.visible = not board
	_scoreboard.visible = board


var _hud_rev: int = GameSettings.hud_revision


func _settings_keys() -> void:
	var s := ctx.settings
	if _hud_rev != GameSettings.hud_revision:  # the settings menu rewrote [hud]
		_hud_rev = GameSettings.hud_revision
		var cfg := ConfigFile.new()
		if cfg.load(HudSettings.PATH) == OK:
			s.read_config(cfg)
			_relayout()
	if _fedge(KEY_F6):
		s.cycle_colorblind()
		_toasts.push(tr("HUD_TOAST_COLORBLIND") % tr(HudPalette.PRESET_KEYS[s.colorblind]))
		s.save_user()
	if _fedge(KEY_F7) or _fedge(KEY_F8):
		s.set_ui_scale(s.ui_scale + (HudSettings.SCALE_STEP if Input.is_physical_key_pressed(KEY_F8) else -HudSettings.SCALE_STEP))
		_relayout()
		_toasts.push(tr("HUD_TOAST_UI_SCALE") % roundi(s.ui_scale * 100.0))
		s.save_user()
	if _fedge(KEY_F9):
		s.cycle_damage_numbers()
		_toasts.push(tr("HUD_TOAST_DAMAGE_NUMBERS") % tr(["HUD_DMG_OFF", "HUD_DMG_COMPACT", "HUD_DMG_FULL"][s.damage_numbers]))
		s.save_user()


## --hud-screenshot <s> <path> (repeatable): saves the rendered frame after
## `s` seconds; quits after the last one.
func _debug_screenshot(delta: float) -> void:
	var shots := ctx.settings.debug_screenshots
	if shots.is_empty():
		return
	_shot_t += delta
	if _shot_t < float(shots[0][0]):
		return
	var shot: Array = shots.pop_front()
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(str(shot[1]))
	print("[hud] screenshot %s (%dx%d) -> %s" % [shot[1], img.get_width(), img.get_height(), error_string(err)])
	if shots.is_empty():
		get_tree().quit()


## v0.12 idle fade (hud-v0.12.md §2, §4.3): any change in own HP, ammo,
## cooldowns or the objective state (or a hit / kill, see _on_hit / _on_kill)
## restores the HUD at once; after `idle_fade_seconds` without one, ctx.idle_k
## eases to 1 over 300 ms (instantly with reduce motion).
func _idle_fade(c: ClientWorld, delta: float) -> void:
	var woke := false
	if c.combat != null:
		var cb := c.combat
		woke = (_last_hp >= 0 and cb.hp < _last_hp) or cb.ammo < _last_ammo - 0.01
		_last_hp = cb.hp
		_last_ammo = cb.ammo
		for i in mini(cb.skill_cd_left.size(), _last_cd.size()):
			if cb.skill_cd_left[i] > _last_cd[i] or (cb.skill_flags[i] & AbilityRunner.FLAG_CASTING) != 0:
				woke = true
			_last_cd[i] = cb.skill_cd_left[i]
	var sig := -1
	var hpi := c.own_hardpoint_index()
	if hpi >= 0 and hpi < c.hardpoints.size():
		var st := c.hardpoints[hpi]
		sig = hpi * 1000 + (st.owner + 1) * 100 + int(st.contested) * 50 + roundi(st.progress * 20.0)
	if sig != _idle_sig:
		_idle_sig = sig
		woke = true
	if woke:
		wake()
	_idle_t += delta
	var secs := ctx.settings.idle_fade_seconds()
	var target := 1.0 if secs > 0.0 and _idle_t >= secs and not c.is_dead() else 0.0
	if target <= 0.0:
		ctx.idle_k = 0.0
	elif UiKit.reduce_motion():
		ctx.idle_k = target
	else:
		ctx.idle_k = move_toward(ctx.idle_k, target, delta / 0.3)


## Restores the full HUD (a combat event happened).
func wake() -> void:
	_idle_t = 0.0
	ctx.idle_k = 0.0


func _input(event: InputEvent) -> void:
	var pad := ctx.pad_active
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	if pad != ctx.pad_active:
		ctx.pad_active = pad
		ctx.key_labels.clear()


func _fedge(key: int) -> bool:
	var down := Input.is_physical_key_pressed(key)
	var was: bool = _fkeys.get(key, false)
	_fkeys[key] = down
	return down and not was


func _on_snapshot(s: SnapshotData) -> void:
	ctx.roster.apply_entities(s.entities, s.own_net_id, ctx.own_team())


func _on_hit(e: GameEvent) -> void:
	wake()
	var hero := ctx.roster.hero(e.target_net_id) != null
	_center.on_hit(e, hero)
	if hero:  # Wardling / structure numbers are off by default (hud.md §13.2)
		_world.on_hit(e)


func _on_kill(e: GameEvent) -> void:
	var victim := e.target_net_id
	var killer := e.source_net_id
	if not ctx.roster.on_kill(victim, killer):
		return  # not a hero (Wardling kills stay out of the feed, hud.md §4.10)
	wake()
	var own := ctx.own_id()
	_kill_feed.add(_name(killer), ctx.roster.team_of(killer), _name(victim), ctx.roster.team_of(victim),
		killer == own or victim == own)


func _name(id: int) -> String:
	if id == ctx.own_id():
		return tr("HUD_YOU")
	var n := ctx.roster.name_of(id)
	if n != "":
		return n
	if ctx.roster.hero(id) == null:
		return tr("HUD_KILLER_UNKNOWN")
	return tr("HUD_HERO_N") % id
