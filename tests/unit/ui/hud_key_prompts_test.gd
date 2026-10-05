extends GdUnitTestSuite
## Polish sprint 2026-10-05: HUD key prompts follow the player's bindings.
## Repro: rebinding Interact to G and Reload to T still showed "[F] ARMORY" and
## "DRY - [R] RELOAD", because the key letters were baked into the strings.

const HudContextScript := preload("res://src/ui/hud/hud_context.gd")

const TRANSLATION := "res://assets/localization/hud.en.translation"

var _saved: Dictionary = {}
var _tr: Translation


func before() -> void:
	# The suite runs without AppRoot, so the HUD strings are registered here.
	_tr = load(TRANSLATION) as Translation
	TranslationServer.add_translation(_tr)
	TranslationServer.set_locale("en")


func after() -> void:
	TranslationServer.remove_translation(_tr)


func before_test() -> void:
	var b := GameSettings.shared().bindings
	for a: String in ["interact", "reload"]:
		_saved[a] = b.get_spec(a)


func after_test() -> void:
	var b := GameSettings.shared().bindings
	for a: String in _saved:
		b.assign(a, _saved[a])


func _ctx() -> HudContext:
	return HudContextScript.new(null, HudSettings.new(), HudTuningDef.new())


func test_armory_and_reload_prompts_follow_rebinding() -> void:
	var b := GameSettings.shared().bindings
	b.assign("interact", "k:%d" % KEY_G)
	b.assign("reload", "k:%d" % KEY_T)
	var ctx := _ctx()
	assert_str(ctx.prompt("HUD_ARMORY_PROMPT", &"interact", "F")).contains("[G]")
	assert_str(ctx.prompt("HUD_ARMORY_PROMPT", &"interact", "F")).not_contains("[F]")
	assert_str(ctx.prompt("HUD_DRY", &"reload", "R")).contains("[T]")
	assert_str(ctx.prompt("HUD_DRY", &"reload", "R")).not_contains("[R]")


func test_prompts_show_pad_glyph_while_a_pad_is_active() -> void:
	var ctx := _ctx()
	ctx.pad_active = true
	var pad := InputBindings.joy_spec_text(GameSettings.shared().bindings.get_pad_spec("interact"))
	assert_str(ctx.prompt("HUD_ARMORY_PROMPT", &"interact", "F")).contains("[%s]" % HudContext.short_pad(pad))


func test_prompt_strings_take_the_key_as_a_parameter() -> void:
	for k: String in ["HUD_ARMORY_PROMPT", "HUD_DRY"]:
		assert_str(tr(k)).contains("[%s]")


func test_armory_toggles_on_the_interact_action_not_a_fixed_f() -> void:
	# The prompt names Interact, so Interact (whatever it is bound to) must toggle.
	var panel: ArmoryPanel = auto_free(ArmoryPanel.new())
	Input.action_press(&"interact")
	var first := panel._toggle_edge()
	var held := panel._toggle_edge()
	Input.action_release(&"interact")
	var released := panel._toggle_edge()
	assert_bool(first).is_true()
	assert_bool(held).is_false()
	assert_bool(released).is_false()


func test_fork_keys_on_a_pad_name_the_buttons_that_pick_the_fork() -> void:
	# Repro: fork_a / fork_b have no pad binding, so key_label fell back to "1"/"2"
	# while the pad actually picks with the skill 1 / skill 2 buttons.
	var ctx := _ctx()
	ctx.pad_active = true
	var b := GameSettings.shared().bindings
	assert_str(ctx.key_label(&"fork_a", "1")).is_equal("1")  # the old label
	var s1 := HudContext.short_pad(InputBindings.joy_spec_text(b.get_pad_spec("skill_1")))
	var s2 := HudContext.short_pad(InputBindings.joy_spec_text(b.get_pad_spec("skill_2")))
	assert_str(ctx.fork_key(false)).is_equal(s1.substr(0, 5))
	assert_str(ctx.fork_key(true)).is_equal(s2.substr(0, 5))
	ctx.pad_active = false
	assert_str(ctx.fork_key(false)).is_equal(InputBindings.spec_text(b.get_spec("fork_a")))
