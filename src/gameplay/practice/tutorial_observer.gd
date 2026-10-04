class_name TutorialObserver
extends RefCounted
## Turns what the local client sees into tutorial facts (W10-W4). Works for
## keyboard and gamepad alike because it reads replicated / predicted state,
## not keys: speed and airborne state of the predicted body, ammo / skill /
## progress snapshots, signals, and the shop capture flag.
## Fact ids = TutorialStepDef.id.

var client: ClientWorld
var movement: MovementDef
## Fraction of the sprint speed that counts as sprinting.
var sprint_frac: float = 0.9
var min_move_speed: float = 1.5

var _prev_ammo: float = -1.0
var _prev_level: int = 0
var _prev_skill_points: int = -1
var _fired: bool = false
var _leveled: bool = false
var _baseline_owned: int = -1
var _baseline_mounts: PackedInt32Array = PackedInt32Array()


func _init(client_: ClientWorld) -> void:
	client = client_
	movement = client_.movement
	client.shot_received.connect(func(e: GameEvent) -> void:
		if client.session != null and e.source_net_id == client.session.own_net_id:
			_fired = true)
	client.level_changed.connect(func(_l: int) -> void: _leveled = true)


## Facts seen since the last call (latched ones clear when read).
func poll() -> Dictionary:
	var facts := {}
	if client == null or client.body == null or client.combat == null or client.is_dead():
		return facts
	var v := client.body.state.velocity
	var speed := Vector2(v.x, v.z).length()
	facts["move"] = speed >= min_move_speed
	facts["jump"] = not client.body.state.grounded and v.y > 1.0
	var sprint_speed := movement.base_move_speed * movement.sprint_multiplier * sprint_frac if movement != null else 8.0
	facts["sprint"] = speed >= sprint_speed
	var c := client.combat
	facts["shoot"] = _fired or (_prev_ammo >= 0.0 and c.ammo < _prev_ammo - 0.01 and c.feed_kind == WeaponDef.FeedKind.MAGAZINE)
	_fired = false
	_prev_ammo = c.ammo
	facts["reload"] = (c.ammo_flags & AmmoFeed.FLAG_RELOADING) != 0
	facts["skill_1"] = c.skill_cd_left.size() > 0 and c.skill_cd_left[0] > 0
	var p := client.progress
	if p != null:
		if _prev_level == 0:
			_prev_level = p.level
		facts["level_up"] = _leveled or p.level > _prev_level
		_prev_level = p.level
		facts["fork"] = _prev_skill_points >= 0 and p.skill_points < _prev_skill_points
		_prev_skill_points = p.skill_points
		if _baseline_owned < 0:
			_baseline_owned = p.owned_bits
			_baseline_mounts = p.mount_item.duplicate()
		facts["buy"] = p.owned_bits != _baseline_owned or p.mount_item != _baseline_mounts
	_leveled = false
	facts["shop_open"] = client.player_input != null and client.player_input.ui_captured
	return facts
