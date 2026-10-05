class_name GameSettings
extends RefCounted
## Player options stored in user://settings.cfg (per machine, not game rules).
## Read once at boot; the menus edit them and call save() + apply_display().
## LookSettings values are copied onto the session's LookSettings by
## apply_look() so gameplay keeps reading its own resource. Key bindings live
## in `bindings` (InputBindings) and are applied to the InputMap at boot.
## HUD options (UI scale, colour-blind preset, damage numbers) stay in
## HudSettings' [hud] section of the same file; save() keeps foreign sections.

const PATH := "user://settings.cfg"
const SENS_MIN := 0.02
const SENS_MAX := 0.5
const FOV_MIN := 70.0
const FOV_MAX := 120.0
const PAD_SENS_MIN := 30.0
const PAD_SENS_MAX := 540.0
const PAD_DEADZONE_MIN := 0.0
const PAD_DEADZONE_MAX := 0.5
const PAD_CURVE_MIN := 1.0
const PAD_CURVE_MAX := 3.0
const RENDER_SCALE_MIN := 0.5
const RENDER_SCALE_MAX := 1.0
## Comfort options (W16-COMFORT): centre dot size range in screen pixels.
const DOT_SIZE_MIN := 2.0
const DOT_SIZE_MAX := 6.0
const DOT_OPACITY_MIN := 0.1

enum WindowMode { WINDOWED, FULLSCREEN, BORDERLESS }
## Graphics quality preset (read by the graphics code: chunk G1).
enum Quality { LOW, MEDIUM, HIGH, ULTRA }
## FPS cap choices; 0 = unlimited.
const FPS_CAPS: Array[int] = [30, 60, 120, 144, 240, 0]
## Crosshair looks and colours (CenterFeedback draws from these).
enum Crosshair { CROSS_DOT, CROSS, DOT, CIRCLE }
const CROSSHAIR_COLORS: Array[Color] = [Color.WHITE, Color("#4CE38A"), Color("#00E5FF"),
	Color("#FFD447"), Color("#FF4FD8"), Color("#FF4A3D")]
const BUS_EFFECTS := &"Effects"
const BUS_UI := &"UI"
## W21-A1 mix (design/audio/audio-events.md §Buses): Master > Music, Effects
## (> Weapons, Abilities, Footsteps, World), UI, Voice, Ambient.
const BUS_MUSIC := &"Music"
const BUS_VOICE := &"Voice"
const BUS_AMBIENT := &"Ambient"
const BUS_WEAPONS := &"Weapons"
const BUS_ABILITIES := &"Abilities"
const BUS_FOOTSTEPS := &"Footsteps"
const BUS_WORLD := &"World"
## [name, parent] in creation order (a parent exists before its children).
const BUS_LAYOUT: Array = [
	[&"Music", &"Master"], [&"Effects", &"Master"], [&"Weapons", &"Effects"],
	[&"Abilities", &"Effects"], [&"Footsteps", &"Effects"], [&"World", &"Effects"],
	[&"UI", &"Master"], [&"Voice", &"Master"], [&"Ambient", &"Master"]]
## Mix-engineering constants of the bus effects (not gameplay tuning): the
## master limiter ceiling, the night-mode master compressor and the Voice
## side-chain duck on Music (~6 dB, 150 ms release) and Ambient (~4 dB).
const LIMITER_CEILING_DB := -1.0
const NIGHT_THRESHOLD_DB := -20.0
const NIGHT_RATIO := 4.0
const DUCK_THRESHOLD_DB := -30.0
const DUCK_RATIO_MUSIC := 4.0
const DUCK_RATIO_AMBIENT := 2.2
const DUCK_ATTACK_US := 20000.0
const DUCK_RELEASE_MS := 150.0
## Effect slots: Music / Ambient carry [Amplify (code duck), Compressor
## (Voice side-chain)]; Master carries [Compressor (night), HardLimiter].
const FX_CODE_DUCK := 0
const FX_MASTER_NIGHT := 0

var mouse_sensitivity_deg: float = 0.12
var invert_y: bool = false
var fov_deg: float = 90.0
## Gamepad look (W11-C1): right-stick rate at full tilt (deg/s), radial dead
## zone, response-curve exponent, invert Y, and the aim-assist toggle.
var pad_sensitivity_deg_s: float = 180.0
var pad_deadzone: float = 0.15
var pad_curve: float = 1.6
var pad_invert_y: bool = false
var aim_assist: bool = true
## Master volume, 0..1 (linear). Effects and UI buses sit below Master.
var master_volume: float = 0.8
var effects_volume: float = 1.0
var ui_volume: float = 1.0
## W21-A1 [audio] keys: Music, Voice (announcer) and Ambient bus volumes 0..1,
## night mode (master 4:1 compression from -20 dB, explosions / ults -4 dB) and
## reduced music (match music = stingers only at phase changes / final minutes).
var music_volume: float = 0.7
var voice_volume: float = 1.0
var ambient_volume: float = 0.8
var night_mode: bool = false
var reduce_music: bool = false
## WindowMode.
var window_mode: int = WindowMode.WINDOWED
## Window size in WINDOWED mode (0 = the engine default). Set by the launcher.
var window_w: int = 0
var window_h: int = 0
## 3D render resolution scale, 0.5..1.0.
var render_scale: float = 1.0
var vsync: bool = true
## Index into FPS_CAPS (default: unlimited, the last entry).
var fps_cap_index: int = 5
## Quality preset 0..3 (Quality), default High. Chunk G1 reads this field.
var graphics_quality: int = Quality.HIGH
## W18-LIFE World ambience (Video tab): background life level 0 Low, 1 Medium,
## 2 High. The graphics quality caps it (AmbientComfort.level()).
var ambient_level: int = 2
## W18-LIFE: allow rain in matches whose weather rolls rain (else fog).
var ambient_rain: bool = true
## Crosshair style (Crosshair) and colour index (CROSSHAIR_COLORS).
var crosshair_style: int = Crosshair.CROSS_DOT
var crosshair_color: int = 0
## Dynamic crosshair: the gap opens to the real spread cone (SpreadModel).
var crosshair_dynamic: bool = true
## Key bindings (applied to the InputMap by apply_bindings()).
var bindings: InputBindings = InputBindings.new()
## W10-W4: the first-time Practice Range tutorial was finished or skipped.
var tutorial_done: bool = false
## Accessibility: skip menu tweens, freeze the menu background and the hero
## turntable (design/ux/ui-kit.md §5). Video tab.
var reduce_motion: bool = false
## Comfort (W16-COMFORT, [comfort] section). Scales are 0..1 (UI shows percent).
## Camera recoil: share of the view punch the CAMERA shows. The aim sent to the
## server always includes the full kick (fair for everyone); the remainder moves
## the crosshair to where the shot lands. The server's spread is never scaled.
var comfort_camera_recoil: float = 1.0
## Weapon (viewmodel) walk bob.
var comfort_weapon_bob: bool = true
## Screen effects: flashes, hit flashes, glow bursts, vignettes and ink-edge pulses.
var comfort_fx_intensity: float = 1.0
## Fixed centre dot (always drawn at the exact screen centre, under the crosshair).
var comfort_center_dot: bool = false
var comfort_dot_size_px: float = 3.0
var comfort_dot_opacity: float = 1.0
## Blend small prediction corrections into the camera instead of snapping.
var comfort_smooth_corrections: bool = true
## Comfort vignette strength (0 = off); fades in only during fast / forced moves.
var comfort_vignette: float = 0.0
## The one-time "see Settings > Comfort" hint was shown (and dismissed).
var comfort_hint_seen: bool = false

static var _shared: GameSettings
## Bumped when the Gameplay tab rewrites the [hud] section, so a running HUD
## knows to re-read it.
static var hud_revision: int = 0


## The process-wide settings (loaded from disk on first use; the key bindings
## are applied to the InputMap right then, i.e. at boot).
static func shared() -> GameSettings:
	if _shared == null:
		_shared = GameSettings.new()
		_shared.load_from_disk()
		_shared.apply_bindings()
	return _shared


## True for fullscreen or borderless (legacy accessor).
var fullscreen: bool:
	get:
		return window_mode != WindowMode.WINDOWED
	set(v):
		window_mode = WindowMode.FULLSCREEN if v else WindowMode.WINDOWED


func load_from_disk(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	read_config(cfg)


## Writes the file; sections owned by others (e.g. [hud]) are kept.
func save(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file is fine
	write_config(cfg)
	cfg.save(path)


## Reads every section; missing or invalid values keep their defaults.
func read_config(cfg: ConfigFile) -> void:
	mouse_sensitivity_deg = clampf(cfg.get_value("look", "sensitivity_deg", mouse_sensitivity_deg), SENS_MIN, SENS_MAX)
	invert_y = cfg.get_value("look", "invert_y", invert_y)
	fov_deg = clampf(cfg.get_value("look", "fov_deg", fov_deg), FOV_MIN, FOV_MAX)
	pad_sensitivity_deg_s = clampf(cfg.get_value("gamepad", "sensitivity_deg_s", pad_sensitivity_deg_s), PAD_SENS_MIN, PAD_SENS_MAX)
	pad_deadzone = clampf(cfg.get_value("gamepad", "deadzone", pad_deadzone), PAD_DEADZONE_MIN, PAD_DEADZONE_MAX)
	pad_curve = clampf(cfg.get_value("gamepad", "curve", pad_curve), PAD_CURVE_MIN, PAD_CURVE_MAX)
	pad_invert_y = bool(cfg.get_value("gamepad", "invert_y", pad_invert_y))
	aim_assist = bool(cfg.get_value("gamepad", "aim_assist", aim_assist))
	master_volume = clampf(cfg.get_value("audio", "master", master_volume), 0.0, 1.0)
	effects_volume = clampf(cfg.get_value("audio", "effects", effects_volume), 0.0, 1.0)
	ui_volume = clampf(cfg.get_value("audio", "ui", ui_volume), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	voice_volume = clampf(float(cfg.get_value("audio", "voice", voice_volume)), 0.0, 1.0)
	ambient_volume = clampf(float(cfg.get_value("audio", "ambient", ambient_volume)), 0.0, 1.0)
	night_mode = bool(cfg.get_value("audio", "night_mode", night_mode))
	reduce_music = bool(cfg.get_value("audio", "reduce_music", reduce_music))
	var legacy_fs: bool = cfg.get_value("display", "fullscreen", false)
	window_mode = clampi(int(cfg.get_value("display", "window_mode",
		WindowMode.FULLSCREEN if legacy_fs else WindowMode.WINDOWED)), 0, WindowMode.BORDERLESS)
	window_w = maxi(0, int(cfg.get_value("display", "window_w", window_w)))
	window_h = maxi(0, int(cfg.get_value("display", "window_h", window_h)))
	render_scale = clampf(cfg.get_value("display", "render_scale", render_scale), RENDER_SCALE_MIN, RENDER_SCALE_MAX)
	vsync = cfg.get_value("display", "vsync", vsync)
	fps_cap_index = clampi(int(cfg.get_value("display", "fps_cap_index", fps_cap_index)), 0, FPS_CAPS.size() - 1)
	graphics_quality = clampi(int(cfg.get_value("display", "quality", graphics_quality)), Quality.LOW, Quality.ULTRA)
	ambient_level = clampi(int(cfg.get_value("display", "ambient_level", ambient_level)), 0, 2)
	ambient_rain = bool(cfg.get_value("display", "ambient_rain", ambient_rain))
	tutorial_done = bool(cfg.get_value("tutorial", "done", tutorial_done))
	reduce_motion = bool(cfg.get_value("accessibility", "reduce_motion", reduce_motion))
	crosshair_style = clampi(int(cfg.get_value("crosshair", "style", crosshair_style)), 0, Crosshair.CIRCLE)
	crosshair_color = clampi(int(cfg.get_value("crosshair", "color", crosshair_color)), 0, CROSSHAIR_COLORS.size() - 1)
	crosshair_dynamic = bool(cfg.get_value("crosshair", "dynamic", crosshair_dynamic))
	comfort_camera_recoil = clampf(float(cfg.get_value("comfort", "camera_recoil", comfort_camera_recoil)), 0.0, 1.0)
	comfort_weapon_bob = bool(cfg.get_value("comfort", "weapon_bob", comfort_weapon_bob))
	comfort_fx_intensity = clampf(float(cfg.get_value("comfort", "fx_intensity", comfort_fx_intensity)), 0.0, 1.0)
	comfort_center_dot = bool(cfg.get_value("comfort", "center_dot", comfort_center_dot))
	comfort_dot_size_px = clampf(float(cfg.get_value("comfort", "dot_size_px", comfort_dot_size_px)), DOT_SIZE_MIN, DOT_SIZE_MAX)
	comfort_dot_opacity = clampf(float(cfg.get_value("comfort", "dot_opacity", comfort_dot_opacity)), DOT_OPACITY_MIN, 1.0)
	comfort_smooth_corrections = bool(cfg.get_value("comfort", "smooth_corrections", comfort_smooth_corrections))
	comfort_vignette = clampf(float(cfg.get_value("comfort", "vignette", comfort_vignette)), 0.0, 1.0)
	comfort_hint_seen = bool(cfg.get_value("comfort", "hint_seen", comfort_hint_seen))
	bindings.read_config(cfg)


func write_config(cfg: ConfigFile) -> void:
	cfg.set_value("tutorial", "done", tutorial_done)
	cfg.set_value("accessibility", "reduce_motion", reduce_motion)
	cfg.set_value("look", "sensitivity_deg", mouse_sensitivity_deg)
	cfg.set_value("look", "invert_y", invert_y)
	cfg.set_value("look", "fov_deg", fov_deg)
	cfg.set_value("gamepad", "sensitivity_deg_s", pad_sensitivity_deg_s)
	cfg.set_value("gamepad", "deadzone", pad_deadzone)
	cfg.set_value("gamepad", "curve", pad_curve)
	cfg.set_value("gamepad", "invert_y", pad_invert_y)
	cfg.set_value("gamepad", "aim_assist", aim_assist)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "effects", effects_volume)
	cfg.set_value("audio", "ui", ui_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "voice", voice_volume)
	cfg.set_value("audio", "ambient", ambient_volume)
	cfg.set_value("audio", "night_mode", night_mode)
	cfg.set_value("audio", "reduce_music", reduce_music)
	cfg.set_value("display", "window_mode", window_mode)
	cfg.set_value("display", "window_w", window_w)
	cfg.set_value("display", "window_h", window_h)
	cfg.set_value("display", "render_scale", render_scale)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "fps_cap_index", fps_cap_index)
	cfg.set_value("display", "quality", graphics_quality)
	cfg.set_value("display", "ambient_level", ambient_level)
	cfg.set_value("display", "ambient_rain", ambient_rain)
	cfg.set_value("crosshair", "style", crosshair_style)
	cfg.set_value("crosshair", "color", crosshair_color)
	cfg.set_value("crosshair", "dynamic", crosshair_dynamic)
	cfg.set_value("comfort", "camera_recoil", comfort_camera_recoil)
	cfg.set_value("comfort", "weapon_bob", comfort_weapon_bob)
	cfg.set_value("comfort", "fx_intensity", comfort_fx_intensity)
	cfg.set_value("comfort", "center_dot", comfort_center_dot)
	cfg.set_value("comfort", "dot_size_px", comfort_dot_size_px)
	cfg.set_value("comfort", "dot_opacity", comfort_dot_opacity)
	cfg.set_value("comfort", "smooth_corrections", comfort_smooth_corrections)
	cfg.set_value("comfort", "vignette", comfort_vignette)
	cfg.set_value("comfort", "hint_seen", comfort_hint_seen)
	bindings.write_config(cfg)


## The "Motion comfort" preset (values from `rules`, ComfortRulesDef).
## Raises the FOV to the preset minimum but never lowers a higher one.
func apply_comfort_preset(rules: ComfortRulesDef = null) -> void:
	if rules == null:
		rules = ComfortRulesDef.load_default()
	comfort_camera_recoil = clampf(rules.preset_camera_recoil, 0.0, 1.0)
	comfort_weapon_bob = rules.preset_weapon_bob
	comfort_fx_intensity = clampf(rules.preset_fx_intensity, 0.0, 1.0)
	comfort_center_dot = rules.preset_center_dot
	comfort_smooth_corrections = rules.preset_smooth_corrections
	comfort_vignette = clampf(rules.preset_vignette, 0.0, 1.0)
	reduce_motion = rules.preset_reduce_motion
	fov_deg = clampf(maxf(fov_deg, rules.preset_fov_min_deg), FOV_MIN, FOV_MAX)


## Copies the look options onto `look` (a LookSettings, duck-typed: core
## does not name gameplay classes).
func apply_look(look: Resource) -> void:
	if look == null:
		return
	look.set("mouse_sensitivity_deg", mouse_sensitivity_deg)
	look.set("invert_y", invert_y)
	look.set("fov_deg", fov_deg)
	look.set("pad_sensitivity_deg_s", pad_sensitivity_deg_s)
	look.set("pad_deadzone", pad_deadzone)
	look.set("pad_curve", pad_curve)
	look.set("pad_invert_y", pad_invert_y)
	look.set("aim_assist", aim_assist)


## Pushes the key bindings into the InputMap.
func apply_bindings() -> void:
	bindings.apply_to_input_map()


## Creates the W21-A1 bus layout (BUS_LAYOUT) under Master when missing, with
## its effects: Master night compressor (off until night mode) + hard limiter;
## Music / Ambient code-duck Amplify + Voice side-chain compressor. Returns the
## number of buses created (0 when the layout already exists).
static func ensure_buses() -> int:
	var made := 0
	for entry in BUS_LAYOUT:
		var bus_name: StringName = entry[0]
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, entry[1])
		if bus_name == BUS_MUSIC or bus_name == BUS_AMBIENT:
			AudioServer.add_effect(idx, AudioEffectAmplify.new(), FX_CODE_DUCK)
			var duck := AudioEffectCompressor.new()
			duck.sidechain = BUS_VOICE
			duck.threshold = DUCK_THRESHOLD_DB
			duck.ratio = DUCK_RATIO_MUSIC if bus_name == BUS_MUSIC else DUCK_RATIO_AMBIENT
			duck.attack_us = DUCK_ATTACK_US
			duck.release_ms = DUCK_RELEASE_MS
			AudioServer.add_effect(idx, duck)
		made += 1
	var master := AudioServer.get_bus_index(&"Master")
	if master >= 0 and not _has_effect(master, "AudioEffectHardLimiter"):
		var night := AudioEffectCompressor.new()
		night.threshold = NIGHT_THRESHOLD_DB
		night.ratio = NIGHT_RATIO
		AudioServer.add_effect(master, night, FX_MASTER_NIGHT)
		AudioServer.set_bus_effect_enabled(master, FX_MASTER_NIGHT, false)
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = LIMITER_CEILING_DB
		AudioServer.add_effect(master, lim)
	return made


static func _has_effect(bus: int, cls: String) -> bool:
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i).get_class() == cls:
			return true
	return false


## Code-driven duck (dB, <= 0) on a bus with a FX_CODE_DUCK Amplify (Music,
## Ambient): mixed on top of the player's volume setting, never replacing it.
static func set_bus_duck_db(bus_name: StringName, db: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0 or AudioServer.get_bus_effect_count(idx) <= FX_CODE_DUCK:
		return
	var amp := AudioServer.get_bus_effect(idx, FX_CODE_DUCK) as AudioEffectAmplify
	if amp != null:
		amp.volume_db = minf(db, 0.0)


## Sets the volume of bus `bus_name` from a linear 0..1 value.
static func set_bus_linear(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


## Every bus volume plus night mode (creates the buses when missing).
func apply_audio() -> void:
	ensure_buses()
	set_bus_linear(&"Master", master_volume)
	set_bus_linear(BUS_EFFECTS, effects_volume)
	set_bus_linear(BUS_UI, ui_volume)
	set_bus_linear(BUS_MUSIC, music_volume)
	set_bus_linear(BUS_VOICE, voice_volume)
	set_bus_linear(BUS_AMBIENT, ambient_volume)
	var master := AudioServer.get_bus_index(&"Master")
	if master >= 0 and AudioServer.get_bus_effect_count(master) > FX_MASTER_NIGHT \
			and AudioServer.get_bus_effect(master, FX_MASTER_NIGHT) is AudioEffectCompressor:
		AudioServer.set_bus_effect_enabled(master, FX_MASTER_NIGHT, night_mode)


## Volume, window mode, render scale, VSync and FPS cap (window parts are a
## no-op headless).
func apply_display() -> void:
	apply_audio()
	Engine.max_fps = FPS_CAPS[fps_cap_index]
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.scaling_3d_scale = render_scale
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var want := DisplayServer.WINDOW_MODE_WINDOWED
	var borderless := false
	match window_mode:
		WindowMode.FULLSCREEN:
			want = DisplayServer.WINDOW_MODE_FULLSCREEN
		WindowMode.BORDERLESS:
			want = DisplayServer.WINDOW_MODE_WINDOWED
			borderless = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, borderless)
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	if want == DisplayServer.WINDOW_MODE_WINDOWED and not borderless and window_w > 0 and window_h > 0:
		DisplayServer.window_set_size(Vector2i(window_w, window_h))
	if borderless:
		DisplayServer.window_set_size(DisplayServer.screen_get_size())
		DisplayServer.window_set_position(DisplayServer.screen_get_position())
