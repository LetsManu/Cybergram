extends GdUnitTestSuite
## PBKDF2-HMAC-SHA256 against published vectors (the SHA-256 counterpart of
## RFC 6070, as listed in RFC 7914 §11 / widely published test vectors), the
## constant-time compare, the threaded hasher and the login rate limiter.

const P := "password"
const S := "salt"


func _hex(password: String, salt: String, c: int, dk: int) -> String:
	return Pbkdf2.derive(password.to_utf8_buffer(), salt.to_utf8_buffer(), c, dk).hex_encode()


func test_vector_c1() -> void:
	assert_str(_hex(P, S, 1, 32)).is_equal("120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")


func test_vector_c2() -> void:
	assert_str(_hex(P, S, 2, 32)).is_equal("ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")


func test_vector_c4096() -> void:
	assert_str(_hex(P, S, 4096, 32)).is_equal("c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")


func test_vector_rfc7914_two_blocks() -> void:
	# RFC 7914 §11: P="passwd", S="salt", c=1, dkLen=64.
	assert_str(_hex("passwd", "salt", 1, 64)).is_equal(
		"55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc"
		+ "49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783")


func test_constant_time_equals() -> void:
	var a := PackedByteArray([1, 2, 3])
	assert_bool(Pbkdf2.constant_time_equals(a, PackedByteArray([1, 2, 3]))).is_true()
	assert_bool(Pbkdf2.constant_time_equals(a, PackedByteArray([1, 2, 4]))).is_false()
	assert_bool(Pbkdf2.constant_time_equals(a, PackedByteArray([1, 2]))).is_false()


func test_threaded_hasher_matches_inline() -> void:
	var h := PasswordHasher.new()
	h.submit(P.to_utf8_buffer(), S.to_utf8_buffer(), 2, {"n": 7})
	var done: Array = []
	for i in 2000:
		done.append_array(h.poll())
		if not done.is_empty():
			break
		OS.delay_msec(1)
	assert_int(done.size()).is_equal(1)
	assert_str(done[0].hash.hex_encode()).is_equal("ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
	assert_int(done[0].context.n).is_equal(7)
	assert_int(done[0].password.size()).is_equal(0)  # not kept


func test_rate_limiter_locks_after_failures_and_unlocks() -> void:
	var rl := LoginRateLimiter.new(3, 60.0, 120.0)
	assert_bool(rl.fail("u:neo", 0.0)).is_false()
	assert_bool(rl.fail("u:neo", 1.0)).is_false()
	assert_bool(rl.fail("u:neo", 2.0)).is_true()
	assert_bool(rl.is_locked("u:neo", 50.0)).is_true()
	assert_bool(rl.is_locked("u:other", 50.0)).is_false()
	assert_bool(rl.is_locked("u:neo", 123.0)).is_false()


func test_rate_limiter_window_and_success_reset() -> void:
	var rl := LoginRateLimiter.new(3, 10.0, 60.0)
	rl.fail("p:2", 0.0)
	rl.fail("p:2", 1.0)
	assert_bool(rl.fail("p:2", 20.0)).is_false()  # the first two fell out of the window
	rl.succeed("p:2")
	assert_int(rl.size()).is_equal(0)
	rl.fail("p:3", 0.0)
	rl.purge(100.0)
	assert_int(rl.size()).is_equal(0)


func test_auth_config_args_env_and_guest_switch() -> void:
	var c := AuthConfig.parse(PackedStringArray(["--tls-cert", "/x/c.pem", "--data-dir", "/d"]),
		{"CYBERGRAM_TLS_KEY": "/x/k.pem", "CYBERGRAM_DATA_DIR": "/env", "CYBERGRAM_ALLOW_GUESTS": "true"})
	assert_str(c.cert_path).is_equal("/x/c.pem")
	assert_str(c.key_path).is_equal("/x/k.pem")
	assert_str(c.data_dir).is_equal("/d")
	assert_bool(c.allow_guests).is_true()
	assert_bool(AuthConfig.parse(PackedStringArray(), {}).allow_guests).is_false()
	# A missing certificate file means guest-only, never a crash.
	var m := AuthConfig.parse(PackedStringArray(), {"CYBERGRAM_TLS_CERT": "/nope/fullchain.pem",
		"CYBERGRAM_TLS_KEY": "/nope/privkey.pem"})
	assert_object(m.load_server_tls()).is_null()
	assert_str(m.tls_error).contains("no TLS certificate at /nope/fullchain.pem")


func test_client_tls_policy() -> void:
	var c := AuthConfig.parse(PackedStringArray(), {})
	assert_object(c.client_tls_for("127.0.0.1")).is_null()
	assert_object(c.client_tls_for("cyber.djboeck.at")).is_not_null()
	assert_bool(c.client_tls_for("cyber.djboeck.at").is_unsafe_client()).is_false()
	var n := AuthConfig.parse(PackedStringArray(["--no-dtls"]), {})
	assert_object(n.client_tls_for("cyber.djboeck.at")).is_null()
