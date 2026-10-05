extends GdUnitTestSuite
## W16-SDWATER regression: with a client standing outside the Sudden Death ring
## the "OUTSIDE THE RING" banner is actually drawn (and not drawn inside / dead).

const MAP_PATH := "res://assets/data/match/map_front.tres"


class _Session extends Node:
	var client: ClientWorld


func _widget(pos: Vector3, active: bool, dead: bool = false) -> RingWarning:
	var md := load(MAP_PATH) as MapDef
	var c := ClientWorld.new()
	auto_free(c)
	c.setup_objectives(md)  # builds the ring model from the map
	c.sudden_death.active = active
	c.sudden_death.elapsed_s = 0.0
	var hb := HeroBody.new()
	auto_free(hb)
	hb.state.position = pos
	c.body = hb
	if dead:
		c.combat = SnapshotData.OwnCombat.new()
		c.combat.dead = true
	var sess := _Session.new()
	sess.client = c
	auto_free(sess)
	add_child(sess)
	sess.add_child(c)
	var ctx := HudContext.new(sess, HudSettings.new(), HudTuningDef.new())
	var w := RingWarning.new()
	w.bind(ctx)
	w.size = Vector2(534.0, 60.0)
	auto_free(w)
	add_child(w)
	return w


func _drawn(w: RingWarning) -> bool:
	w.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	return w.drawn


func test_banner_drawn_when_outside_the_ring() -> void:
	var md := load(MAP_PATH) as MapDef
	var far := md.mid_plaza_center + Vector3(60.0, 0.0, 0.0)  # beyond the 45 m start radius
	assert_bool(await _drawn(_widget(far, true))).is_true()


func test_banner_hidden_inside_dead_or_ring_off() -> void:
	var md := load(MAP_PATH) as MapDef
	assert_bool(await _drawn(_widget(md.mid_plaza_center, true))).is_false()
	assert_bool(await _drawn(_widget(md.mid_plaza_center + Vector3(60, 0, 0), true, true))).is_false()
	assert_bool(await _drawn(_widget(md.mid_plaza_center + Vector3(60, 0, 0), false))).is_false()
