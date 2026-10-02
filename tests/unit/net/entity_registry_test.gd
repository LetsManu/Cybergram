extends GdUnitTestSuite
## EntityRegistry NetId allocation and delayed recycling.


func test_ids_start_at_one_and_increase() -> void:
	var r := EntityRegistry.new(60)
	var a: Node = auto_free(Node.new())
	var b: Node = auto_free(Node.new())
	assert_int(r.register(a, EntityRegistry.KIND_HERO, 0)).is_equal(1)
	assert_int(r.register(b, EntityRegistry.KIND_HERO, 0)).is_equal(2)
	assert_object(r.get_node_by_id(2)).is_same(b)


func test_released_id_is_not_reused_before_recycle_delay() -> void:
	var r := EntityRegistry.new(60)
	r.register(auto_free(Node.new()), EntityRegistry.KIND_HERO, 0)
	r.release(1, 10)
	assert_int(r.register(auto_free(Node.new()), EntityRegistry.KIND_HERO, 69)).is_equal(2)
	assert_int(r.register(auto_free(Node.new()), EntityRegistry.KIND_HERO, 70)).is_equal(1)
