extends SceneTree

const ORE_SCENES := [
	"res://items/CoalOre.tscn",
	"res://items/IronOre.tscn",
	"res://items/CopperOre.tscn",
	"res://items/LimestoneOre.tscn",
	"res://items/MossRock.tscn",
	"res://items/GraniteRock.tscn",
]


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	var shop_catalog := (load("res://src/global_var.gd") as Script).new() as Node
	for scene_path: String in ORE_SCENES:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			_fail("cannot load %s" % scene_path)
			return
		var ore := packed.instantiate() as StaticBody3D
		if ore == null:
			_fail("root is not StaticBody3D: %s" % scene_path)
			return
		var manager := Node3D.new()
		manager.set_script(load("res://src/tree_forest_manager.gd"))
		root.add_child(manager)
		root.add_child(ore)
		await process_frame
		await process_frame
		var body_shape := ore.get_node_or_null("CollisionShape3D") as CollisionShape3D
		var hit_area := ore.get_node_or_null("Hit3D") as Area3D
		var hit_shape := ore.get_node_or_null("Hit3D/CollisionShape3D") as CollisionShape3D
		if body_shape == null or body_shape.shape == null:
			_fail("missing body collision shape: %s" % scene_path)
			return
		if hit_area == null or hit_shape == null or hit_shape.shape == null:
			_fail("missing Hit3D collision shape: %s" % scene_path)
			return
		if ore.collision_layer != 16384 or ore.collision_mask != 32:
			_fail("invalid body collision configuration: %s" % scene_path)
			return
		if hit_area.collision_layer != 16384 or hit_area.collision_mask != 32:
			_fail("invalid Hit3D collision configuration: %s" % scene_path)
			return
		var multimeshes := manager.get("multimeshes") as Dictionary
		if ore.get("forest_manager") != manager or multimeshes.is_empty():
			_fail("TreeForestManager did not create an ore MultiMesh: %s" % scene_path)
			return
		var drops: Variant = ore.get("drops")
		if not drops is Array or (drops as Array).is_empty():
			_fail("missing ore drops: %s" % scene_path)
			return
		var drop := (drops as Array)[0] as Dictionary
		var ingredient_id := str(drop.get("item_id", ""))
		if IngredientCatalog.get_definition(ingredient_id).is_empty():
			_fail("missing handheld definition for %s" % ingredient_id)
			return
		if shop_catalog.call("get_shop_product", ingredient_id).is_empty():
			_fail("missing price definition for %s" % ingredient_id)
			return
		for method_name: String in ["impact", "apply_network_destroyed", "apply_network_respawned", "respawn_from_forest"]:
			if not ore.has_method(method_name):
				_fail("missing %s on %s" % [method_name, scene_path])
				return
		var max_hp := float(ore.get("max_hp"))
		if not bool(ore.call("impact", "test", max_hp, "red")) or not bool(ore.get("destroyed")):
			_fail("authoritative destruction failed: %s" % scene_path)
			return
		var mesh := ore.get_node_or_null("Mesh") as Node3D
		if mesh == null or mesh.visible:
			_fail("independent Mesh did not disappear: %s" % scene_path)
			return
		var bindings := ore.get_meta("forest_multimesh_bindings", []) as Array
		var expected_mesh_count := mesh.find_children("*", "MeshInstance3D", true, false).size()
		if bindings.size() != expected_mesh_count:
			_fail("incomplete MultiMesh component bindings: %s (%d/%d)" % [
				scene_path, bindings.size(), expected_mesh_count,
			])
			return
		manager.call("on_resource_destroyed", ore)
		await process_frame
		for binding_value: Variant in bindings:
			var binding := binding_value as Dictionary
			var multi := multimeshes.get(str(binding.get("key", "")), null) as MultiMesh
			var multi_index := int(binding.get("index", -1))
			if multi == null or multi_index < 0 or multi_index >= multi.instance_count:
				_fail("invalid MultiMesh binding: %s" % scene_path)
				return
		ore.call("respawn_from_forest")
		if bool(ore.get("destroyed")) or mesh.visible:
			_fail("respawn visibility failed: %s" % scene_path)
			return
		ore.queue_free()
		manager.queue_free()
		await process_frame
	shop_catalog.free()
	print("HARVEST_ORE_VALIDATION_OK: %d scenes" % ORE_SCENES.size())
	quit(0)


func _fail(message: String) -> void:
	push_error("HARVEST_ORE_VALIDATION_FAILED: " + message)
	quit(1)
