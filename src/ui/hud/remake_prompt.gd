class_name RemakePrompt
extends HudWidget
## W17B-UI: the in-match early remake vote (design "Fair play": a teammate
## never connected or left in the first ~3 min; every connected teammate
## must vote yes; a passed remake voids the match with no rating change).
## Self-contained: reads ClientSession.matchmaking.remake_prompt (protocol
## 17) through MmClientAdapter.remake_of(), draws a small card at the top
## centre only while a vote is possible, open, or just settled, and sends
## votes with F1 (yes) / F2 (no), or D-pad up / down on a pad.
## Display only: the match process decides eligibility and the outcome.

const W: float = 470.0
const H: float = 92.0
## Seconds the outcome stays on screen.
const OUTCOME_S: float = 4.0

## Normalised state (MmClientAdapter.remake_of / MatchmakingFakeClient).
var state: Dictionary = {}
var left_s: float = 0.0
## Sends a vote (default: the session's MatchmakingClient). Tests inject.
var voter: Callable = Callable()
## True when the last _draw put the card on screen (tests).
var drawn: bool = false
var _outcome_t: float = 0.0
var _voted: bool = false


func bind(c: HudContext) -> void:
	super.bind(c)
	var mm: MatchmakingClient = null
	if c != null and c.client != null and c.client.session != null:
		mm = c.client.session.matchmaking
	if mm != null:
		mm.remake_prompt.connect(func(d: Dictionary) -> void: apply(MmClientAdapter.remake_of(d, _voted)))
		if not voter.is_valid():
			voter = func(yes: bool) -> void: mm.remake_vote(yes)


## A new remake state.
func apply(d: Dictionary) -> void:
	state = d
	left_s = float(d.get("deadline_s", 0.0))
	if bool(d.get("voted", false)):
		_voted = true
	if StringName(d.get("outcome", &"")) != &"":
		_outcome_t = OUTCOME_S
		_voted = false


## True when the card shows (eligible and open, or an outcome on screen).
func shows() -> bool:
	if state.is_empty():
		return false
	if StringName(state.get("outcome", &"")) != &"":
		return _outcome_t > 0.0
	return bool(state.get("eligible", false)) or bool(state.get("open", false))


func vote(yes: bool) -> void:
	if not shows() or _voted or StringName(state.get("outcome", &"")) != &"":
		return
	_voted = true
	if voter.is_valid():
		voter.call(yes)


func _process(delta: float) -> void:
	left_s = maxf(0.0, left_s - delta)
	_outcome_t = maxf(0.0, _outcome_t - delta)
	super._process(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not shows() or _voted:
		return
	var yes := false
	var hit := false
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		if k.physical_keycode == KEY_F1:
			yes = true
			hit = true
		elif k.physical_keycode == KEY_F2:
			hit = true
	var j := event as InputEventJoypadButton
	if j != null and j.pressed and j.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]:
		yes = j.button_index == JOY_BUTTON_DPAD_UP
		hit = true
	if hit:
		get_viewport().set_input_as_handled()
		vote(yes)


func _draw() -> void:
	drawn = false
	if ctx == null or not shows():
		return
	drawn = true
	var t := UiKit.tokens()
	var r := Rect2((size.x - W) * 0.5, 0.0, W, H)
	panel(r)
	draw_rect(Rect2(r.position, Vector2(3.0, H)), t.warn)
	var outcome := StringName(state.get("outcome", &""))
	var x := r.position.x + 16.0
	if outcome != &"":
		var passed := outcome == &"passed"
		text(tr("HUD_MM_REMAKE_PASSED") if passed else tr("HUD_MM_REMAKE_FAILED"), Vector2(x, 34.0), 20,
			t.ok if passed else t.text_dim, ctx.font_display)
		if passed:
			text(tr("HUD_MM_REMAKE_NO_RATING"), Vector2(x, 60.0), 13, t.text_dim)
		return
	var open := bool(state.get("open", false))
	text(tr("HUD_MM_REMAKE_TITLE"), Vector2(x, 26.0), 18, t.warn, ctx.font_display)
	if open:
		text("%s  %d / %d" % [tr("HUD_MM_REMAKE_YES_COUNT"), int(state.get("yes", 0)), int(state.get("needed", 0))],
			Vector2(x, 50.0), 14, HudPalette.TEXT_DIM)
		text(MmView.clock(left_s), Vector2(r.end.x - 70.0, 26.0), 18, t.accent, ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, 54.0)
		bar(Rect2(r.position.x + 3.0, r.end.y - 3.0, (W - 3.0) * clampf(left_s / 30.0, 0.0, 1.0), 3.0), 1.0, t.warn)
	else:
		text(tr("HUD_MM_REMAKE_ELIGIBLE"), Vector2(x, 50.0), 14, HudPalette.TEXT_DIM)
	var hint := tr("HUD_MM_REMAKE_VOTED") if _voted else tr("HUD_MM_REMAKE_KEYS")
	text(hint, Vector2(x, 76.0), 13, t.accent_hi if not _voted else t.text_dim)
