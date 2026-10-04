class_name TutorialDef
extends Resource
## Ordered first-time tutorial steps (assets/data/match/tutorial_steps.tres).

@export var steps: Array[TutorialStepDef] = []
## Seconds the "step done" tick stays before the next instruction appears.
@export_range(0.0, 5.0, 0.1) var done_flash_s: float = 0.8
