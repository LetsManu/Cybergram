class_name MatchQueueDef
extends Resource
## One matchmaking queue (design/gdd/matchmaking.md §3 "Queues"). Lives inside
## MatchmakingRulesDef.queues; data only, no logic.

## BLIND (P3): everyone picks at once, enemy picks hidden (Normal 5v5).
enum PickMode { DRAFT, ALL_RANDOM, HOST_CHOICE, BLIND }

## Stable queue id used on the wire and in rating tracks ("normal_5v5", ...).
@export var id: StringName = &""
## Display name key (localised by the client later).
@export var display_name: String = ""
## Map id the match process loads.
@export var map_id: StringName = &""
## Players per team. Safe range 1-5.
@export_range(1, 5) var team_size: int = 5
## How heroes are picked.
@export var pick_mode: PickMode = PickMode.DRAFT
## Rating track this queue reads and writes ("" = unrated, e.g. Custom).
@export var rating_track: StringName = &""
## True for the visible-rank queue: medals, party-gap limit, dodge penalty.
@export var ranked: bool = false
## True if empty slots may be filled with labelled bots after bot_fill_delay_s.
## Ranked must keep this false (MatchmakingRulesDef.validate() checks it).
@export var bots_allowed: bool = false
## False for Custom: hosts build the lobby, the matchmaker refuses the queue.
@export var matchmade: bool = true
## Starting lane slots, one per team member, in assignment order. Values:
## &"north", &"center", &"south", &"flex". Empty = no lane assignment (3v3).
@export var lane_slots: Array[StringName] = []
## P3: a pick turn that ends with nothing locked and nothing hovered cancels
## the lobby and counts as a dodge (Ranked). False = a random legal hero is
## locked instead (Normal, few players online: never throw a lobby away).
@export var pick_timeout_dodges: bool = false
