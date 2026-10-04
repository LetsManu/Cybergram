class_name TutorialStepDef
extends Resource
## One first-time tutorial step (W10-W4). `id` doubles as the observed fact the
## step waits for (TutorialObserver / TutorialModel.update).

@export var id: StringName = &""
## hud.csv key of the instruction; "%s" is replaced by the player's keys.
@export var text_key: String = ""
## Rebindable action ids (InputBindings) whose current keys fill the text.
@export var actions: PackedStringArray = PackedStringArray()
## hud.csv key of the gamepad hint shown next to the keys ("" = none).
@export var pad_key: String = ""
