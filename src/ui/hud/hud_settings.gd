class_name HudSettings
extends RefCounted
## Player HUD options (design/ux/hud.md §13.2, §16): UI scale, colour-blind
## preset, damage numbers, world-plate numbers, net graph, HUD aspect.
## Persisted in the [hud] section of user://settings.cfg (ConfigFile). Until the
## settings menu exists, the HUD binds F6 (colour-blind preset), F7 / F8 (UI
## scale -/+), F9 (damage numbers) and saves on change; launch args override
## the file for one run (see apply_args).

const PATH := "user://settings.cfg"
const SECTION := "hud"
const SCALE_MIN: float = 0.8
const SCALE_MAX: float = 1.2
const SCALE_STEP: float = 0.1
const DAMAGE_IDS: Array[String] = ["off", "compact", "full"]

## HUD scale 80-120% (hud.md §16).
var ui_scale: float = 1.0
## HudPalette.Preset.
var colorblind: int = HudPalette.Preset.DEFAULT
## DamageNumberModel.Mode (default Compact, hud.md §13.2 / U1).
var damage_numbers: int = DamageNumberModel.Mode.COMPACT
## Small HP number next to world health plates.
var plate_numbers: bool = false
## Debug net graph visible at start (F3 toggles).
var net_graph: bool = false
## Clamp the HUD to a 16:9 centre region on ultrawide (hud.md §3.2).
var clamp_16_9: bool = true
## Debug (evidence captures): keep the scoreboard open.
var debug_scoreboard: bool = false


func set_ui_scale(v: float) -> void:
	ui_scale = clampf(snappedf(v, 0.01), SCALE_MIN, SCALE_MAX)


func cycle_colorblind() -> void:
	colorblind = (colorblind + 1) % HudPalette.PRESET_IDS.size()


func cycle_damage_numbers() -> void:
	damage_numbers = (damage_numbers + 1) % DAMAGE_IDS.size()


## Reads the [hud] section; missing or invalid keys keep their defaults.
func read_config(cfg: ConfigFile) -> void:
	set_ui_scale(float(cfg.get_value(SECTION, "ui_scale", ui_scale)))
	colorblind = HudPalette.preset_from_id(str(cfg.get_value(SECTION, "colorblind", HudPalette.PRESET_IDS[colorblind])))
	var dn := DAMAGE_IDS.find(str(cfg.get_value(SECTION, "damage_numbers", DAMAGE_IDS[damage_numbers])))
	damage_numbers = dn if dn >= 0 else DamageNumberModel.Mode.COMPACT
	plate_numbers = bool(cfg.get_value(SECTION, "plate_numbers", plate_numbers))
	net_graph = bool(cfg.get_value(SECTION, "net_graph", net_graph))
	clamp_16_9 = str(cfg.get_value(SECTION, "hud_aspect", "16:9")) != "native"


func write_config(cfg: ConfigFile) -> void:
	cfg.set_value(SECTION, "ui_scale", ui_scale)
	cfg.set_value(SECTION, "colorblind", HudPalette.PRESET_IDS[colorblind])
	cfg.set_value(SECTION, "damage_numbers", DAMAGE_IDS[damage_numbers])
	cfg.set_value(SECTION, "plate_numbers", plate_numbers)
	cfg.set_value(SECTION, "net_graph", net_graph)
	cfg.set_value(SECTION, "hud_aspect", "16:9" if clamp_16_9 else "native")


## Launch-arg overrides (user args after "--"; unknown args are ignored):
##   --ui-scale 1.1   --colorblind deuteranopia|protanopia|tritanopia|default
##   --damage-numbers off|compact|full   --plate-numbers   --net-graph
##   --hud-aspect native|16:9   --hud-scoreboard (debug: scoreboard held open)
func apply_args(args: PackedStringArray) -> void:
	var i := 0
	while i < args.size():
		var a := args[i]
		var has_next := i + 1 < args.size()
		match a:
			"--ui-scale":
				if has_next:
					i += 1
					set_ui_scale(args[i].to_float())
			"--colorblind":
				if has_next:
					i += 1
					colorblind = HudPalette.preset_from_id(args[i])
			"--damage-numbers":
				if has_next:
					i += 1
					var dn := DAMAGE_IDS.find(args[i].to_lower())
					if dn >= 0:
						damage_numbers = dn
			"--plate-numbers":
				plate_numbers = true
			"--net-graph":
				net_graph = true
			"--hud-aspect":
				if has_next:
					i += 1
					clamp_16_9 = args[i] != "native"
			"--hud-scoreboard":
				debug_scoreboard = true
		i += 1


## Settings for this run: user://settings.cfg, then launch-arg overrides.
static func load_user(args: PackedStringArray = PackedStringArray()) -> HudSettings:
	var s := HudSettings.new()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		s.read_config(cfg)
	s.apply_args(args)
	return s


## Writes the [hud] section, keeping other sections of the file.
func save_user() -> Error:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # missing file is fine
	write_config(cfg)
	return cfg.save(PATH)
