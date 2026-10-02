class_name InputCommand
extends RefCounted
## One tick of player intent (ADR-0002 Key Interfaces, architecture.md §8.2).
## Humans (PlayerInputSource), dummies (ScriptedInputSource) and later bots all
## emit this. The client quantizes BEFORE predicting so client and server feed
## HeroMotor bit-identical values.
##
## Wire layout (WIRE_SIZE = 26 bytes): seq u32, move i8 x2, yaw u16, pitch i16,
## buttons u16, view_tick u32, view_alpha u8, squad_cmd u8, squad_target u16,
## squad_point i16 x3 (1/8 m). Squad fields (E8, wardlings-and-economy.md §8)
## are an edge event: set on the one tick the order is given, else SQUAD_NONE.
##
## Example:
##   cmd.quantize(); var off := cmd.write_to(buf, 0)
##   var back := InputCommand.new(); InputCommand.read_from(buf, 0, back)

const WIRE_SIZE: int = 26

const BTN_JUMP: int = 1 << 0
const BTN_CROUCH: int = 1 << 1
const BTN_SPRINT: int = 1 << 2
const BTN_FIRE: int = 1 << 3
const BTN_ALT: int = 1 << 4
const BTN_RELOAD: int = 1 << 5
const BTN_SKILL1: int = 1 << 6
const BTN_SKILL2: int = 1 << 7
const BTN_SKILL3: int = 1 << 8
const BTN_SKILL4: int = 1 << 9
const BTN_INTERACT: int = 1 << 10
const BTN_SQUAD: int = 1 << 11
const BUTTON_MASK: int = (1 << 12) - 1

## Squad orders (C15: 4 commands). Values match Squad.CMD_*.
const SQUAD_NONE: int = 0
const SQUAD_FOLLOW: int = 1
const SQUAD_HOLD: int = 2
const SQUAD_ATTACK: int = 3
const SQUAD_CAPTURE: int = 4
## Client-local only (Smart Command, Z tap): ClientWorld resolves it from the
## crosshair into ATTACK / CAPTURE / HOLD before the command is sent.
const SQUAD_SMART: int = 7
const _SQUAD_MAX: int = SQUAD_CAPTURE
const _POINT_STEPS: float = 8.0

const _MOVE_STEPS: float = 127.0
const _YAW_STEPS: float = 65536.0
const _PITCH_STEPS: float = 32767.0
const _HALF_PI: float = PI / 2.0
const _ALPHA_STEPS: float = 255.0

## Client tick this command belongs to (monotonic).
var seq: int = 0
## x = strafe right, y = forward; length <= 1.
var move: Vector2 = Vector2.ZERO
## Radians, wrapped to [0, TAU). 0 faces -Z.
var yaw: float = 0.0
## Radians in [-PI/2, PI/2]; positive looks up.
var pitch: float = 0.0
var buttons: int = 0
## Server tick the client was viewing (lag compensation, E4).
var view_tick: int = 0
var view_alpha: float = 0.0
## SQUAD_* order issued this tick (0 = none).
var squad_cmd: int = SQUAD_NONE
## ATTACK: target net id. CAPTURE: hardpoint index in the lane.
var squad_target: int = 0
## HOLD: ground point (the server re-validates range and projects to the navmesh).
var squad_point: Vector3 = Vector3.ZERO


func has(button: int) -> bool:
	return (buttons & button) != 0


## Snaps every field to wire precision (idempotent).
func quantize() -> void:
	var buf := PackedByteArray()
	buf.resize(WIRE_SIZE)
	write_to(buf, 0)
	read_from(buf, 0, self)


func copy_from(other: InputCommand) -> void:
	seq = other.seq
	move = other.move
	yaw = other.yaw
	pitch = other.pitch
	buttons = other.buttons
	view_tick = other.view_tick
	view_alpha = other.view_alpha
	squad_cmd = other.squad_cmd
	squad_target = other.squad_target
	squad_point = other.squad_point


func duplicate_command() -> InputCommand:
	var c := InputCommand.new()
	c.copy_from(self)
	return c


func equals(other: InputCommand) -> bool:
	return seq == other.seq and move == other.move and yaw == other.yaw \
		and pitch == other.pitch and buttons == other.buttons \
		and view_tick == other.view_tick and view_alpha == other.view_alpha \
		and squad_cmd == other.squad_cmd and squad_target == other.squad_target and squad_point == other.squad_point


## Writes WIRE_SIZE bytes at `offset` (buffer must be large enough). Returns the end offset.
func write_to(buf: PackedByteArray, offset: int) -> int:
	var m := move.limit_length(1.0)
	buf.encode_u32(offset, seq & 0xFFFFFFFF)
	buf.encode_s8(offset + 4, clampi(roundi(m.x * _MOVE_STEPS), -127, 127))
	buf.encode_s8(offset + 5, clampi(roundi(m.y * _MOVE_STEPS), -127, 127))
	buf.encode_u16(offset + 6, roundi(fposmod(yaw, TAU) / TAU * _YAW_STEPS) & 0xFFFF)
	buf.encode_s16(offset + 8, clampi(roundi(pitch / _HALF_PI * _PITCH_STEPS), -32767, 32767))
	buf.encode_u16(offset + 10, buttons & BUTTON_MASK)
	buf.encode_u32(offset + 12, view_tick & 0xFFFFFFFF)
	buf.encode_u8(offset + 16, clampi(roundi(view_alpha * _ALPHA_STEPS), 0, 255))
	buf.encode_u8(offset + 17, squad_cmd if squad_cmd >= 0 and squad_cmd <= _SQUAD_MAX else SQUAD_NONE)
	buf.encode_u16(offset + 18, squad_target & 0xFFFF)
	buf.encode_s16(offset + 20, clampi(roundi(squad_point.x * _POINT_STEPS), -32767, 32767))
	buf.encode_s16(offset + 22, clampi(roundi(squad_point.y * _POINT_STEPS), -32767, 32767))
	buf.encode_s16(offset + 24, clampi(roundi(squad_point.z * _POINT_STEPS), -32767, 32767))
	return offset + WIRE_SIZE


## Reads and validates a command. Returns false if the buffer is too short.
## Ranges are clamped (move length <= 1, pitch within +-90 degrees): the server
## never trusts the client.
static func read_from(buf: PackedByteArray, offset: int, out: InputCommand) -> bool:
	if offset < 0 or offset + WIRE_SIZE > buf.size():
		return false
	out.seq = buf.decode_u32(offset)
	out.move = Vector2(buf.decode_s8(offset + 4) / _MOVE_STEPS, buf.decode_s8(offset + 5) / _MOVE_STEPS)
	if out.move.length_squared() > 1.0:
		out.move = out.move.normalized()
	out.yaw = buf.decode_u16(offset + 6) * TAU / _YAW_STEPS
	out.pitch = clampi(buf.decode_s16(offset + 8), -32767, 32767) * _HALF_PI / _PITCH_STEPS
	out.buttons = buf.decode_u16(offset + 10) & BUTTON_MASK
	out.view_tick = buf.decode_u32(offset + 12)
	out.view_alpha = buf.decode_u8(offset + 16) / _ALPHA_STEPS
	var sc := buf.decode_u8(offset + 17)
	out.squad_cmd = sc if sc <= _SQUAD_MAX else SQUAD_NONE
	out.squad_target = buf.decode_u16(offset + 18)
	out.squad_point = Vector3(buf.decode_s16(offset + 20), buf.decode_s16(offset + 22),
		buf.decode_s16(offset + 24)) / _POINT_STEPS
	return true
