extends GdUnitTestSuite
## Connection diagnostics (owner plan 2026-10-06, docs/connecting.md):
## NetDiagnosis steps (pure + real handshakes against a local DTLS server),
## ConnectionRejects (engine-error classification, masking, rate-limited log,
## /metrics counter), the bare-IP timeout reason and AccountService rejections.

const PORT := 47791


func test_bare_ip_address_fails_with_a_fix_and_a_name_passes() -> void:
	var ip_step := NetDiagnosis.address_step("192.168.1.7")
	assert_int(ip_step.state).is_equal(NetDiagnosis.State.FAIL)
	assert_str(ip_step.fix).contains("hosts file")
	assert_int(NetDiagnosis.address_step("cyber.djboeck.at").state).is_equal(NetDiagnosis.State.OK)


func test_dns_step_names_private_addresses_and_missing_names() -> void:
	assert_str(NetDiagnosis.dns_step("cyber.djboeck.at", "192.168.1.7").detail).contains("local network")
	assert_int(NetDiagnosis.dns_step("cyber.djboeck.at", "").state).is_equal(NetDiagnosis.State.FAIL)
	assert_int(NetDiagnosis.dns_step("10.0.0.2", "10.0.0.2").state).is_equal(NetDiagnosis.State.SKIPPED)
	assert_bool(NetDiagnosis.is_private_ipv4("172.20.1.1")).is_true()
	assert_bool(NetDiagnosis.is_private_ipv4("8.8.8.8")).is_false()


func test_handshake_outcomes_map_to_udp_and_certificate_lines() -> void:
	var silent := NetDiagnosis.handshake_steps("h", 7777, NetDiagnosis.Handshake.SILENT, NetDiagnosis.Handshake.SILENT)
	assert_int(silent[0].state).is_equal(NetDiagnosis.State.FAIL)
	assert_str(silent[0].fix).contains("forwards UDP 7777")
	assert_int(silent[1].state).is_equal(NetDiagnosis.State.SKIPPED)
	var cert := NetDiagnosis.handshake_steps("h", 7777, NetDiagnosis.Handshake.REJECTED, NetDiagnosis.Handshake.CONNECTED)
	assert_int(cert[0].state).is_equal(NetDiagnosis.State.OK)
	assert_int(cert[1].state).is_equal(NetDiagnosis.State.FAIL)
	assert_str(cert[1].detail).contains("certificate is not valid for h")
	var closed := NetDiagnosis.handshake_steps("h", 7777, NetDiagnosis.Handshake.REFUSED, NetDiagnosis.Handshake.SILENT)
	assert_int(closed[0].state).is_equal(NetDiagnosis.State.FAIL)
	assert_str(closed[0].fix).contains("7777/udp")
	var ok := NetDiagnosis.handshake_steps("h", 7777, NetDiagnosis.Handshake.CONNECTED, NetDiagnosis.Handshake.SILENT)
	assert_int(ok[1].state).is_equal(NetDiagnosis.State.OK)


func test_split_target_defaults_the_port() -> void:
	assert_array(NetDiagnosis.split_target("cyber.djboeck.at")).is_equal(["cyber.djboeck.at", 7777])
	assert_array(NetDiagnosis.split_target(" 192.168.1.7:7800 ")).is_equal(["192.168.1.7", 7800])


## Real handshakes against a local DTLS server whose certificate is issued for
## "cyber.test": the right name passes, a wrong name is a certificate failure
## (UDP OK), a port nobody listens on is silent.
func test_live_handshakes_against_a_local_dtls_server() -> void:
	var c := Crypto.new()
	var key := c.generate_rsa(2048)
	var cert := c.generate_self_signed_certificate(key, "CN=cyber.test,O=t,C=AT")
	var srv := ENetConnection.new()
	assert_int(srv.create_host_bound("127.0.0.1", PORT, 4, 2)).is_equal(OK)
	assert_int(srv.dtls_server_setup(TLSOptions.server(key, cert))).is_equal(OK)
	var pump := func() -> void:
		var ev := srv.service(0)
		while ev[0] != ENetConnection.EVENT_NONE:
			ev = srv.service(0)
	get_tree().process_frame.connect(pump)
	var d := NetDiagnosis.new()
	d.ca = cert
	d.timeout_s = 3.0
	var good: int = await d._handshake(get_tree(), "cyber.test", "127.0.0.1", PORT, false)
	var wrong: int = await d._handshake(get_tree(), "wrong.test", "127.0.0.1", PORT, false)
	var wrong_unsafe: int = await d._handshake(get_tree(), "wrong.test", "127.0.0.1", PORT, true)
	d.timeout_s = 1.0
	var nobody: int = await d._handshake(get_tree(), "cyber.test", "127.0.0.1", PORT + 1, false)
	get_tree().process_frame.disconnect(pump)
	srv.destroy()
	assert_int(good).is_equal(NetDiagnosis.Handshake.CONNECTED)
	assert_int(wrong).is_equal(NetDiagnosis.Handshake.REJECTED)
	assert_int(wrong_unsafe).is_equal(NetDiagnosis.Handshake.CONNECTED)
	# loopback answers "port closed" (ICMP): refused, not silent
	assert_int(nobody).is_equal(NetDiagnosis.Handshake.REFUSED)
	var lines := NetDiagnosis.handshake_steps("wrong.test", PORT, wrong, wrong_unsafe)
	assert_str(lines[1].detail).contains("not valid for wrong.test")


func test_engine_handshake_errors_are_classified() -> void:
	assert_str(ConnectionRejects.reason_of_engine_error("_do_handshake", "TLS handshake error: -30464")).is_equal("plain_udp")
	assert_str(ConnectionRejects.reason_of_engine_error("_do_handshake", "TLS handshake error: -30592")).is_equal("bad_certificate")
	assert_str(ConnectionRejects.reason_of_engine_error("_do_handshake", "TLS handshake error: -9984")).is_equal("handshake_other")
	assert_str(ConnectionRejects.reason_of_engine_error("load", "TLS handshake error: -30464")).is_equal("")


func test_source_addresses_are_masked_unless_full_ip_is_on() -> void:
	assert_str(ConnectionRejects.mask_ip("203.0.113.77")).is_equal("203.0.113.0")
	assert_str(ConnectionRejects.mask_ip("2001:db8:1:2:3:4:5:6")).is_equal("2001:db8:1::")
	assert_str(ConnectionRejects.mask_ip("203.0.113.77", true)).is_equal("203.0.113.77")


func test_rejects_count_in_metrics_and_log_once_per_interval() -> void:
	var r := ConnectionRejects.new()
	var lines: Array = []
	r.log_sink = func(rec: Dictionary) -> void: lines.append(rec)
	var m := OpsMetrics.new()
	for i in 5:
		r._log_error("_do_handshake", "f", 1, "TLS handshake error: -30464", "", false, 0, [])
	r.note("auth", "203.0.113.77")
	r.flush(m, 100.0)
	assert_float(m.value(ConnectionRejects.METRIC, {"reason": "plain_udp"})).is_equal(5.0)
	assert_float(m.value(ConnectionRejects.METRIC, {"reason": "auth"})).is_equal(1.0)
	assert_int(lines.size()).is_equal(2)
	var auth: Dictionary = lines.filter(func(x: Dictionary) -> bool: return x.reason == "auth")[0]
	assert_str(str(auth.source)).is_equal("203.0.113.0")
	# more of the same within the interval: counted, not logged again
	r._log_error("_do_handshake", "f", 1, "TLS handshake error: -30464", "", false, 0, [])
	r.flush(m, 105.0)
	assert_float(m.value(ConnectionRejects.METRIC, {"reason": "plain_udp"})).is_equal(6.0)
	assert_int(lines.size()).is_equal(2)
	r.flush(m, 111.0)
	assert_int(lines.size()).is_equal(3)
	assert_int(int(lines[2].count)).is_equal(1)


func test_bare_ip_plain_timeout_gets_its_own_reason() -> void:
	assert_int(ConnectionWatch.timeout_reason("192.168.1.7:7777", false)).is_equal(ConnectionWatch.Reason.PLAIN_IP)
	assert_int(ConnectionWatch.timeout_reason("cyber.djboeck.at:7777", true)).is_equal(ConnectionWatch.Reason.TIMEOUT_CONNECT)
	assert_int(ConnectionWatch.timeout_reason("127.0.0.1:7777", false)).is_equal(ConnectionWatch.Reason.TIMEOUT_CONNECT)
	assert_str(ConnectionWatch.reason_key(ConnectionWatch.Reason.PLAIN_IP)).is_equal("HUD_NET_ERR_PLAIN_IP")


func test_account_rejections_are_named() -> void:
	assert_str(AccountService.reject_reason(AccountCodec.E_VERSION)).is_equal("version_mismatch")
	assert_str(AccountService.reject_reason(AccountCodec.E_CREDENTIALS)).is_equal("auth")
	assert_str(AccountService.reject_reason(AccountCodec.OK)).is_equal("")


## End to end through the engine: a plain (unencrypted) ENet connect to a DTLS
## server is counted as plain_udp by the Logger the front installs.
func test_plain_connect_to_a_dtls_server_counts_as_plain_udp() -> void:
	var c := Crypto.new()
	var key := c.generate_rsa(2048)
	var cert := c.generate_self_signed_certificate(key, "CN=cyber.test,O=t,C=AT")
	var srv := ENetConnection.new()
	assert_int(srv.create_host_bound("127.0.0.1", PORT + 3, 4, 2)).is_equal(OK)
	srv.dtls_server_setup(TLSOptions.server(key, cert))
	var rej := ConnectionRejects.new()
	rej.log_sink = func(_r: Dictionary) -> void: pass
	OS.add_logger(rej)
	var cli := ENetConnection.new()
	cli.create_host(1, 2)
	cli.connect_to_host("127.0.0.1", PORT + 3, 2)
	for i in 30:
		for conn in [srv, cli]:
			var ev: Array = conn.service(0)
			while ev[0] != ENetConnection.EVENT_NONE:
				ev = conn.service(0)
		await get_tree().process_frame
	OS.remove_logger(rej)
	cli.destroy()
	srv.destroy()
	var m := OpsMetrics.new()
	rej.flush(m, 0.0)
	assert_float(m.value(ConnectionRejects.METRIC, {"reason": "plain_udp"})).is_greater_equal(1.0)
