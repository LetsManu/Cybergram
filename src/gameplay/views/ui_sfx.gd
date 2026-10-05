class_name UiSfx
extends Node
## W10-W5 / W21-A1: UI sounds (UI bus) for screens outside a match. Usage:
##   UiSfx.attach(button)          # hover + click
##   UiSfx.play(&"confirm")        # any ui_* event by short name
##   UiSfx.bind_matchmaking(mm)    # ready check / match found / result stingers
## Sounds are AudioEventDefs (ui_<name>) played through a lazily created
## AudioEvents under the SceneTree root; legacy names map like ClientSfx.UI_EVENTS.

static var _inst: UiSfx
var events: AudioEvents


static func attach(b: BaseButton) -> void:
	b.mouse_entered.connect(play.bind(&"hover"))
	b.pressed.connect(play.bind(&"click"))


## Plays UI event `event` (short name: hover, click, back, confirm, error, lock,
## match_found, ready_check, victory, defeat, ...). Unknown names are silent.
static func play(event: StringName) -> void:
	var ev := _events()
	if ev == null:
		return
	var id: StringName = ClientSfx.UI_EVENTS.get(event, StringName("ui_%s" % event))
	if ev.bank.has(id):
		ev.play(id)


## Connects a MatchmakingClient (duck-typed signals ready_check, match_assigned,
## match_result) to the flow sounds. Safe to call more than once per client.
static func bind_matchmaking(mm: Object) -> void:
	if mm == null:
		return
	if mm.has_signal(&"ready_check") and not mm.is_connected(&"ready_check", _on_ready_check):
		mm.connect(&"ready_check", _on_ready_check)
	if mm.has_signal(&"match_assigned") and not mm.is_connected(&"match_assigned", _on_match_assigned):
		mm.connect(&"match_assigned", _on_match_assigned)
	if mm.has_signal(&"match_result") and not mm.is_connected(&"match_result", _on_result):
		mm.connect(&"match_result", _on_result)


static func _on_ready_check(_deadline: float) -> void:
	play(&"ready_check")


static func _on_match_assigned(_host: String, _port: int, _ticket: String) -> void:
	play(&"match_found")


static func _on_result(result: Dictionary) -> void:
	play(&"victory" if bool(result.get("won", false)) else &"defeat")


static func _events() -> AudioEvents:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	if _inst == null or not is_instance_valid(_inst):
		_inst = UiSfx.new()
		_inst.name = "UiSfx"
		_inst.events = AudioEvents.new()
		_inst.add_child(_inst.events)
		loop.root.add_child(_inst)
	return _inst.events
