class_name InputCommand
extends RefCounted
## One tick of player intent (ADR-0002 Key Interfaces, architecture.md §8.2).
## Humans (PlayerInputSource), dummies (ScriptedInputSource) and later bots all
## emit this. The client quantizes BEFORE predicting so client and server feed
## HeroMotor bit-identical values.
##
## Wire layout (WIRE_SIZE = 17 bytes): seq u32, move i8 x2, yaw u16, pitch i16,
## buttons u16, view_tick u32, view_alpha u8.
##
## Example:
##   cmd.quantize(); var off := cmd.write_to(buf, 0)
##   var back := InputCommand.new(); InputCommand.read_from(buf, 0, back)

const WIRE_SIZE: int = 17

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


func duplicate_command() -> InputCommand:
	var c := InputCommand.new()
	c.copy_from(self)
	return c


func equals(other: InputCommand) -> bool:
	return seq == other.seq and move == other.move and yaw == other.yaw \
		and pitch == other.pitch and buttons == other.buttons \
		and view_tick == other.view_tick and view_alpha == other.view_alpha


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
	return true
