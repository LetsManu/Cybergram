class_name PrivacyCard
extends VBoxContainer
## Settings > Privacy (W15): crash reports (ask / always / never; nothing is
## sent automatically until the player picks "always") and Discord Rich
## Presence (off until switched on). Saved at once in OnlinePrefs.

const CRASH_LABELS: Array[String] = ["Ask after a crash (nothing is sent without your click)",
	"Send automatically", "Never send, never ask"]
const DISCORD_NOTE: String = "Shows \"In launcher\", \"In lobby\" or \"In match (mode)\" on your Discord profile while the game runs. Never your name, ids or the server address. Works only when the Discord app runs on this computer; the data goes to Discord, under Discord's privacy policy."

var prefs: OnlinePrefs
var _crash: OptionButton
var _discord: CheckButton


func _ready() -> void:
	var t: UiKitTokens = UiKit.tokens()
	var card: UiCard = UiKit.card("PRIVACY", 16)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(card)
	card.body.add_child(UiKit.label("Crash reports", &"small", t.text))
	_crash = OptionButton.new()
	for i in CRASH_LABELS.size():
		_crash.add_item(CRASH_LABELS[i], i)
	_crash.select(OnlinePrefs.CRASH_MODES.find(prefs.crash_mode))
	_crash.item_selected.connect(func(i: int) -> void:
		prefs.crash_mode = OnlinePrefs.CRASH_MODES[i]
		prefs.save_file())
	card.body.add_child(_crash)
	var cn: Label = UiKit.label(CrashReporter.PRIVACY_NOTE, &"small", t.text_off)
	cn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cn.custom_minimum_size.x = 280
	card.body.add_child(cn)
	_discord = CheckButton.new()
	_discord.text = "Discord Rich Presence"
	_discord.button_pressed = prefs.discord_presence
	_discord.toggled.connect(func(on: bool) -> void:
		prefs.discord_presence = on
		prefs.save_file())
	card.body.add_child(_discord)
	var dn: Label = UiKit.label(DISCORD_NOTE, &"small", t.text_off)
	dn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dn.custom_minimum_size.x = 280
	card.body.add_child(dn)
