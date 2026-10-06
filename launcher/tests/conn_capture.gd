extends SceneTree
## Screenshot of Settings > Connection test in three real situations against a
## local DTLS server (cert for "localhost"): all OK, certificate name wrong
## (server cert for another name), bare IP. Usage (virtual display):
##   godot --path launcher -s tests/conn_capture.gd -- <out.png>

const PORT := 47795


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var c := Crypto.new()
	var key := c.generate_rsa(2048)
	var good := c.generate_self_signed_certificate(key, "CN=localhost,O=t,C=AT")
	var other := c.generate_self_signed_certificate(key, "CN=cyber.djboeck.at,O=t,C=AT")
	var srv := ENetConnection.new()
	srv.create_host_bound("127.0.0.1", PORT, 4, 2)
	srv.dtls_server_setup(TLSOptions.server(key, good))
	var srv2 := ENetConnection.new()
	srv2.create_host_bound("127.0.0.1", PORT + 1, 4, 2)
	srv2.dtls_server_setup(TLSOptions.server(key, other))
	process_frame.connect(func() -> void:
		for s in [srv, srv2]:
			var ev: Array = s.service(0)
			while ev[0] != ENetConnection.EVENT_NONE:
				ev = s.service(0))
	var bg := ColorRect.new()
	bg.color = UiKit.tokens().bg
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 24)
	root.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	m.add_child(row)
	var cards: Array = []
	for t in ["localhost:%d" % PORT, "localhost:%d" % (PORT + 1), "127.0.0.2:%d" % (PORT + 2)]:
		var card := ConnectionTestCard.new()
		card.ca = good
		card.server = func() -> String: return t
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		cards.append(card)
	await process_frame
	for card in cards:
		await card.run()
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("[conn_capture] ", out)
	quit()
