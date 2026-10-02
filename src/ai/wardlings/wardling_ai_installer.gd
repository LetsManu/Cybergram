class_name WardlingAiInstaller
extends Node
## Wires the Wardling AI into a running session (AppConfig.sim_plugin_scenes).
## Lives in src/ai so ServerWorld / GameSession (gameplay) never name the AI:
## AppRoot instantiates this scene in every mode and sets `session`.

## Set by AppRoot (the GameSession node).
var session: Node
var director: WardlingDirector


func _ready() -> void:
	var server := session.get("server") as ServerWorld if session != null else null
	if server == null or server.wardlings == null:
		return
	director = WardlingDirector.new()
	director.attach(server)
