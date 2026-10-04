class_name UiSfx
extends Node
## W10-W5: light UI sounds (UI bus) for screens outside a match. Usage:
##   UiSfx.attach(button)   # hover + click blips, bounded 3-voice pool
## The pool node lives under the SceneTree root, created lazily.

static var _inst: UiSfx
var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0


static func attach(b: BaseButton) -> void:
	b.mouse_entered.connect(play.bind(&"hover"))
	b.pressed.connect(play.bind(&"click"))


static func play(event: StringName) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	if _inst == null or not is_instance_valid(_inst):
		GameSettings.shared().apply_audio()
		_inst = UiSfx.new()
		_inst.name = "UiSfx"
		var bank := SfxBank.shared()
		for i in bank.def.pool_ui:
			var p := AudioStreamPlayer.new()
			p.bus = GameSettings.BUS_UI
			_inst.add_child(p)
			_inst._pool.append(p)
		loop.root.add_child(_inst)
	var st := SfxBank.shared().ui_stream(event)
	if st == null:
		return
	var p := _inst._pool[_inst._next]
	_inst._next = (_inst._next + 1) % _inst._pool.size()
	p.stream = st
	p.volume_db = SfxBank.shared().def.ui_db
	p.play()
