extends SceneTree
## Headless report for the procedural models: builds every hero, weapon and
## Wardling tier and prints triangle / mesh-instance counts against the art
## bible budgets. Observations only (no verdict).
## Usage: godot --headless --path . -s res://tools/models/model_report.gd


func _initialize() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	print("hero          tris  meshes  markers")
	for k in ModelCatalog.HERO_KEYS:
		var m := HeroModelBuilder.build(k, ModelPalette.TEAM_CONCORD)
		root.add_child(m)
		print("%-12s %6d  %6d  %s" % [k, m.triangle_count(), m.mesh_instance_count(), m.marker_names()])
	print("weapon        tris  meshes  sockets")
	for k in ModelCatalog.WEAPON_KEYS:
		var w := WeaponModelBuilder.build(k, true, ModelPalette.TEAM_SYNDICATE)
		root.add_child(w)
		print("%-12s %6d  %6d  %s" % [k, w.triangle_count(), w.mesh_instance_count(), w.marker_names()])
	if ClassDB.class_exists("WardlingModel") or ResourceLoader.exists("res://src/gameplay/views/models/wardling_model.gd"):
		for t in [1, 2, 3]:
			var wm = load("res://src/gameplay/views/models/wardling_model_builder.gd").build(&"picket", t, 0)
			root.add_child(wm)
			print("picket t%d    %6d  %6d" % [t, wm.triangle_count(), wm.mesh_instance_count()])
	print("materials cached: %d" % ModelMaterials.cached_count())
	quit()
