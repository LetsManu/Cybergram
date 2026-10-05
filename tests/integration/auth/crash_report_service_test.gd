extends GdUnitTestSuite
## W15 crash reports through AccountService.handle(): chunked upload over a
## secure service, refused without DTLS, rate limited, out-of-order refused.

const DIR := "user://test_crash_service"
const DT := 1.0 / 30.0


class FakeTransport:
	extends Transport
	var sent: Array = []

	func send(to_peer: int, _channel: int, data: PackedByteArray) -> void:
		sent.append([to_peer, AccountCodec.decode_result(data)])

	func peer_address(_peer: int) -> String:
		return "192.0.2.44"


func before_test() -> void:
	_wipe()


func after_test() -> void:
	_wipe()


func _wipe() -> void:
	var d := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)


func _service(secure: bool) -> AccountService:
	var s := AccountService.new(null, AuthRulesDef.new(), secure, PresenceRegistry.new())
	if secure:
		var r := OnlineRulesDef.new()
		r.crash_per_ip_per_hour = 1
		s.online = r
		s.crash_store = CrashReportStore.new(DIR, r)
	return s


func _upload(s: AccountService, t: FakeTransport, peer: int, payload: PackedByteArray, skip_seq: int = -1) -> Array:
	t.sent.clear()
	var n := ceili(float(payload.size()) / AccountCodec.CHUNK_MAX)
	for i in n:
		if i == skip_seq:
			continue
		var part := payload.slice(i * AccountCodec.CHUNK_MAX, (i + 1) * AccountCodec.CHUNK_MAX)
		s.handle(t, peer, AccountCodec.encode_request(AccountCodec.OP_CRASH_CHUNK, {"seq": i, "total": n, "data": part}))
	s.step(DT)
	return t.sent.map(func(e: Array) -> int: return int(e[1].code))


static func _report() -> PackedByteArray:
	var noise := ""
	for i in 400:
		noise += "line %d %s\n" % [i, str(i * 7919 % 1013)]
	return JSON.stringify({"kind": "crash", "exit_code": 11, "files": {"log": noise + Crypto.new().generate_random_bytes(3000).hex_encode()}}) \
		.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)


func test_chunked_upload_is_stored_once() -> void:
	var s := _service(true)
	var t := FakeTransport.new()
	var p := _report()
	assert_int(p.size()).is_greater(AccountCodec.CHUNK_MAX * 2)  # really chunked
	assert_array(_upload(s, t, 2, p)).is_equal([AccountCodec.OK])
	assert_int(s.crash_store.count()).is_equal(1)
	# Second report from the same address inside the hour: rate limited at chunk 0.
	assert_array(_upload(s, t, 3, p)).is_equal([AccountCodec.E_RATE])
	assert_int(s.crash_store.count()).is_equal(1)


func test_refused_without_dtls() -> void:
	var s := _service(false)
	var t := FakeTransport.new()
	assert_array(_upload(s, t, 2, _report())).is_equal([AccountCodec.E_NOT_SECURE])


func test_out_of_order_chunk_drops_the_upload() -> void:
	var s := _service(true)
	var t := FakeTransport.new()
	assert_array(_upload(s, t, 2, _report(), 1)).is_equal([AccountCodec.E_BAD_REQUEST])
	assert_int(s.crash_store.count()).is_equal(0)


func test_chunk_codec_roundtrip_and_cap() -> void:
	var data := PackedByteArray([1, 2, 3])
	var d := AccountCodec.decode_request(AccountCodec.encode_request(AccountCodec.OP_CRASH_CHUNK, {"seq": 4, "total": 9, "data": data}))
	assert_int(int(d.seq)).is_equal(4)
	assert_that(d.data).is_equal(data)
	var big := AccountCodec.encode_request(AccountCodec.OP_CRASH_CHUNK, {"seq": 0, "total": 1, "data": PackedByteArray()})
	assert_int(big.size()).is_less(LobbyCodec.MAX_C2S_BYTES)
