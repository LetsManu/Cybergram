class_name AudioEventBankDef
extends Resource
## W21-A1: index of every AudioEventDef (assets/data/audio/audio_events.tres)
## plus the voice-pool sizes of the event player.

@export var events: Array[AudioEventDef] = []
## Voice pools: flat (2D) and positional (3D) players; loops have their own.
@export_range(1, 64) var pool_2d: int = 12
@export_range(1, 64) var pool_3d: int = 20
@export_range(1, 32) var pool_loops: int = 8
## Highest variant number probed by the convention loader (_01 .. _NN).
@export_range(1, 16) var max_variants: int = 8
