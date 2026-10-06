class_name ConnectionTestCard
extends VBoxContainer
## Settings > Connection test (owner plan 2026-10-06, docs/connecting.md):
## runs NetDiagnosis against the game server and lists each step (address,
## name lookup, UDP port, encryption + certificate) with a plain-words result
## and, when something fails, what to do. Sends only handshakes: no login, no
## account data.

## Callable -> String: the server to test ("host:port").
var server: Callable = Callable()
## Optional pinned certificate (self-hosted servers, captures); null = system CAs.
var ca: X509Certificate = null
var _card: UiCard
var _target: LineEdit
var _run: Button
var _lines: VBoxContainer
var _busy := false


func _ready() -> void:
	var t: UiKitTokens = UiKit.tokens()
	_card = UiKit.card("CONNECTION TEST", 16)
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_card)
	var info: Label = UiKit.label("Checks the server name, the UDP port and the encrypted handshake, and says what to fix when one fails. No login, no account data.", &"small", t.text_dim)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 300
	_card.body.add_child(info)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_card.body.add_child(row)
	_target = LineEdit.new()
	_target.text = String(server.call()) if server.is_valid() else ""
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target.custom_minimum_size.y = 38
	_target.text_submitted.connect(func(_s: String) -> void: run())
	row.add_child(_target)
	_run = UiKit.button("TEST CONNECTION", run, &"secondary", 38)
	row.add_child(_run)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 6)
	_card.body.add_child(_lines)


## Runs the test against the field's address; returns the steps.
func run() -> Array:
	if _busy:
		return []
	_busy = true
	_run.disabled = true
	for c in _lines.get_children():
		c.queue_free()
	var d := NetDiagnosis.new()
	d.ca = ca
	d.step_done.connect(_add_line)
	var steps: Array = await d.run(get_tree(), _target.text)
	_run.disabled = false
	_busy = false
	return steps


## Mark + colour for a step state (pure).
static func mark(state: int) -> Array:
	var t: UiKitTokens = UiKit.tokens()
	match state:
		NetDiagnosis.State.OK:
			return ["OK", t.ok]
		NetDiagnosis.State.WARN:
			return ["!", t.warn]
		NetDiagnosis.State.FAIL:
			return ["FAIL", t.danger]
	return ["-", t.text_off]


func _add_line(s: NetDiagnosis.Step) -> void:
	var t: UiKitTokens = UiKit.tokens()
	var m: Array = mark(s.state)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var head: Label = UiKit.label("%s  %s" % [m[0], s.title], &"small", m[1])
	box.add_child(head)
	var detail: Label = UiKit.label(s.detail, &"small", t.text_dim)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)
	if s.fix != "":
		var fix: Label = UiKit.label("Fix: " + s.fix, &"small", t.text)
		fix.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(fix)
	_lines.add_child(box)
