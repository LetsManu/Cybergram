class_name PresenceDef
extends Resource
## Discord Rich Presence settings (data: assets/data/net/presence.tres).
## OWNER TO-DO: create a Discord application (https://discord.com/developers/
## applications) and put its Application ID in `discord_app_id`. Empty = the
## feature stays off even for players who opted in.

const PATH := "res://assets/data/net/presence.tres"

## The Discord Application ID (a public number, not a secret).
@export var discord_app_id: String = ""
## Art asset key uploaded to the Discord application ("" = no image).
@export var large_image: String = ""


static func load_default() -> PresenceDef:
	var r := load(PATH) as PresenceDef if ResourceLoader.exists(PATH) else null
	return r if r != null else PresenceDef.new()
