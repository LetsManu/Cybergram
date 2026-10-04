class_name Pbkdf2
extends RefCounted
## PBKDF2-HMAC-SHA256 (RFC 8018 §5.2) on Crypto.hmac_digest, plus a
## constant-time comparison. Pure and thread-safe (each call makes its own
## Crypto), so PasswordHasher runs it on the WorkerThreadPool, never on the
## 30 Hz sim thread.
##
## Example:
##   var dk := Pbkdf2.derive("password".to_utf8_buffer(), "salt".to_utf8_buffer(), 4096, 32)
##   Pbkdf2.constant_time_equals(dk, stored)

const HLEN: int = 32


## Derives `dk_len` bytes from `password` and `salt` with `iterations` rounds.
static func derive(password: PackedByteArray, salt: PackedByteArray, iterations: int, dk_len: int = HLEN) -> PackedByteArray:
	var crypto := Crypto.new()
	var out := PackedByteArray()
	var blocks := ceili(float(dk_len) / HLEN)
	for i in range(1, blocks + 1):
		var msg := salt.duplicate()
		msg.append_array(PackedByteArray([(i >> 24) & 0xFF, (i >> 16) & 0xFF, (i >> 8) & 0xFF, i & 0xFF]))
		var u := crypto.hmac_digest(HashingContext.HASH_SHA256, password, msg)
		# T = U1 ^ U2 ^ ... as four 64-bit lanes (fast XOR in GDScript).
		var t0 := u.decode_s64(0)
		var t1 := u.decode_s64(8)
		var t2 := u.decode_s64(16)
		var t3 := u.decode_s64(24)
		for c in range(1, maxi(iterations, 1)):
			u = crypto.hmac_digest(HashingContext.HASH_SHA256, password, u)
			t0 ^= u.decode_s64(0)
			t1 ^= u.decode_s64(8)
			t2 ^= u.decode_s64(16)
			t3 ^= u.decode_s64(24)
		var t := PackedByteArray()
		t.resize(HLEN)
		t.encode_s64(0, t0)
		t.encode_s64(8, t1)
		t.encode_s64(16, t2)
		t.encode_s64(24, t3)
		out.append_array(t)
	return out.slice(0, dk_len)


## Compares without an early exit (no timing leak of the matching prefix).
static func constant_time_equals(a: PackedByteArray, b: PackedByteArray) -> bool:
	var diff := a.size() ^ b.size()
	var n := mini(a.size(), b.size())
	for i in n:
		diff |= a[i] ^ b[i]
	return diff == 0
