class_name TutorialModel
extends RefCounted
## Step progression of the first-time tutorial (W10-W4). Pure logic: feed it
## the facts observed this frame ({step id: true}); the current step completes
## when its fact is seen. Skippable per step or entirely.

signal step_completed(index: int)
signal finished(skipped: bool)

var def: TutorialDef
var index: int = 0
var done: bool = false
var skipped: bool = false


func _init(def_: TutorialDef) -> void:
	def = def_
	done = def == null or def.steps.is_empty()


func current() -> TutorialStepDef:
	return null if done else def.steps[index]


func step_count() -> int:
	return def.steps.size() if def != null else 0


## Feeds the facts seen this frame; returns true when the step advanced.
func update(facts: Dictionary) -> bool:
	if done:
		return false
	if not bool(facts.get(current().id, false)):
		return false
	_advance(false)
	return true


## Skips the current step ("skip step").
func skip_step() -> void:
	if not done:
		_advance(true)


## Ends the tutorial ("skip tutorial").
func skip_all() -> void:
	if done:
		return
	done = true
	skipped = true
	finished.emit(true)


func restart() -> void:
	index = 0
	done = def == null or def.steps.is_empty()
	skipped = false


func _advance(was_skip: bool) -> void:
	var finished_index := index
	if not was_skip:
		step_completed.emit(finished_index)
	index += 1
	if index >= def.steps.size():
		done = true
		finished.emit(false)
