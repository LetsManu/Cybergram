class_name BotClientSource
extends RefCounted
## DEBUG ONLY (--bots --bot-player): a BotBrain drives the local client's hero,
## so first-person evidence captures follow a bot through a match. Offline only:
## the brain reads the in-process server's state. Its commands then take the
## normal client path (prediction, send, server validation).

var brain: BotBrain
var server: ServerWorld


func _init(b: BotBrain, s: ServerWorld) -> void:
	brain = b
	server = s


func sample(seq: int, out: InputCommand) -> void:
	brain.produce(server.tick, out)
	out.seq = seq
