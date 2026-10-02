class_name BotInputSource
extends ScriptedInputSource
## Feeds a bot slot (architecture.md §9, ADR-0005 §1): ServerWorld samples it
## like any scripted source, and it answers with its BotBrain's InputCommand.
## Lives in src/ai; gameplay only sees a ScriptedInputSource.

var brain: BotBrain
## Shared per-tick cost meter (BotDirector), or null.
var meter: BotCostMeter
## Tests / tools: called with (hero net id, command) after every sample.
var observer: Callable


func _init(b: BotBrain, m: BotCostMeter = null) -> void:
	super(ScriptedInputDef.new())
	brain = b
	meter = m
	respawn_at_home = false


func sample(seq: int, out: InputCommand) -> void:
	var t0 := Time.get_ticks_usec()
	brain.produce(seq, out)
	if meter != null:
		meter.add(seq, Time.get_ticks_usec() - t0)
	if observer.is_valid():
		observer.call(brain.hero_id, out)
