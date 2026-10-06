extends GdUnitTestSuite
## P1: the operations endpoint answers /health, /health/live, /metrics and
## guards /admin with the token (Bearer or Basic); everything else is 404 /
## 405. One test goes through a real localhost TCP socket and must finish
## within its own deadline. OpsMetrics renders valid Prometheus text.


func _server(token := "") -> OpsHttpServer:
	var s := OpsHttpServer.new()
	s.admin_token = token
	s.health = func() -> Dictionary: return {"ready": true, "version": "v-test"}
	s.metrics = func() -> String: return "x_total 1\n"
	s.admin = func() -> Dictionary: return {"queues": [{"queue": "normal_5v5", "players": 1}]}
	return s


func test_health_ready_and_degraded() -> void:
	var s := _server()
	var r := s.respond("GET", "/health", {})
	assert_int(int(r.status)).is_equal(200)
	assert_dict(JSON.parse_string(r.body)).is_equal({"status": "ok", "version": "v-test"})
	s.health = func() -> Dictionary: return {"ready": false}
	assert_int(int(s.respond("GET", "/health", {}).status)).is_equal(503)
	assert_int(int(s.respond("GET", "/health/live", {}).status)).is_equal(200)


func test_metrics_is_prometheus_text() -> void:
	var r := _server().respond("GET", "/metrics?x=1", {})
	assert_int(int(r.status)).is_equal(200)
	assert_str(r.type).starts_with("text/plain")
	assert_str(r.body).is_equal("x_total 1\n")


func test_admin_is_off_without_a_token() -> void:
	assert_int(int(_server().respond("GET", "/admin", {"authorization": "Bearer "}).status)).is_equal(404)


func test_admin_needs_the_token() -> void:
	var s := _server("s3cret")
	assert_int(int(s.respond("GET", "/admin.json", {}).status)).is_equal(401)
	assert_int(int(s.respond("GET", "/admin.json", {"authorization": "Bearer wrong"}).status)).is_equal(401)
	var ok := s.respond("GET", "/admin.json", {"authorization": "Bearer s3cret"})
	assert_int(int(ok.status)).is_equal(200)
	assert_str(ok.body).contains("normal_5v5")
	var basic := "Basic " + Marshalls.utf8_to_base64("ops:s3cret")
	var html := s.respond("GET", "/admin", {"authorization": basic})
	assert_int(int(html.status)).is_equal(200)
	assert_str(html.type).starts_with("text/html")


func test_other_paths_and_methods() -> void:
	var s := _server()
	assert_int(int(s.respond("GET", "/nope", {}).status)).is_equal(404)
	assert_int(int(s.respond("POST", "/health", {}).status)).is_equal(405)
	assert_str(s.respond("HEAD", "/health", {}).body).is_empty()
	assert_int(int(s.respond_raw("garbage").status)).is_equal(400)


func test_admin_page_escapes_values() -> void:
	var html := OpsAdminPage.html({"events": [{"msg": "<script>x</script>"}]})
	assert_str(html).not_contains("<script>x")
	assert_str(html).contains("&lt;script&gt;")


func test_real_socket_round_trip() -> void:
	var s := _server()
	assert_int(s.listen(0, "127.0.0.1")).is_equal(OK)
	var c := StreamPeerTCP.new()
	assert_int(c.connect_to_host("127.0.0.1", s.port())).is_equal(OK)
	var sent := false
	var got := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		s.poll()
		c.poll()
		if c.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				c.put_data("GET /health HTTP/1.0\r\nHost: x\r\n\r\n".to_utf8_buffer())
				sent = true
			var n := c.get_available_bytes()
			if n > 0:
				got += c.get_data(n)[1]
		elif sent and c.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			break
		OS.delay_msec(5)
	s.stop()
	var text := got.get_string_from_utf8()
	assert_str(text).starts_with("HTTP/1.0 200 OK")
	assert_str(text).contains("\"status\":\"ok\"")
	assert_int(s.served).is_equal(1)


func test_metrics_render_format() -> void:
	var m := OpsMetrics.new()
	m.describe("a_total", "counter", "A things.")
	m.inc("a_total", {"q": "x\"y"})
	m.inc("a_total", {"q": "x\"y"}, 2.0)
	m.set_gauge("b", 0.5)
	var text := m.render()
	assert_str(text).contains("# HELP a_total A things.\n# TYPE a_total counter\na_total{q=\"x\\\"y\"} 3\n")
	assert_str(text).contains("b 0.500000\n")


func test_log_tag_is_stable_and_hides_the_id() -> void:
	var t := OpsLog.tag("0123456789abcdef0123456789abcdef")
	assert_int(t.length()).is_equal(10)
	assert_str(t).is_equal(OpsLog.tag("0123456789abcdef0123456789abcdef"))
	assert_str(t).is_not_equal(OpsLog.tag("0123456789abcdef0123456789abcdee"))
	assert_str(OpsLog.tag("")).is_empty()
