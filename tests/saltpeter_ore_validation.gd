extends Node3D

const SALTPETER_SCENE := preload("res://items/SaltpeterOre.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(
		ResourceLoader.exists("res://assets/other_items/Material/FTF_Resource_SaltpeterOre_Node.glb"),
		"saltpeter node model exists in the material folder"
	)
	_check(
		ResourceLoader.exists("res://assets/nature/drop_items/drop_saltpeter_ore.glb"),
		"saltpeter drop model exists in the nature drop folder"
	)

	var ore := SALTPETER_SCENE.instantiate() as HarvestOre
	_check(ore != null, "saltpeter ore scene instantiates as HarvestOre")
	if ore == null:
		_finish()
		return
	add_child(ore)
	await get_tree().process_frame

	_check(ore.resource_type == "saltpeter", "saltpeter resource type is registered")
	_check(ore.display_name == "硝矿石", "saltpeter display name is registered")
	_check(is_equal_approx(ore.max_hp, 400.0), "saltpeter ore uses the medium ore HP default")
	_check(is_equal_approx(ore.respawn_seconds, 90.0), "saltpeter ore uses the medium ore respawn default")
	_check(ore.get_node_or_null("Mesh") is Node3D, "saltpeter node model is mounted below Mesh")
	_check(ore.get_node_or_null("Hit3D") is Area3D, "saltpeter ore has a hit area")
	_check(ore.get_node_or_null("Hit3D/CollisionShape3D") is CollisionShape3D, "saltpeter hit area has collision")
	var drops: Array = ore.drops
	_check(drops.size() == 1, "saltpeter ore has one drop definition")
	if not drops.is_empty():
		var drop := drops[0] as Dictionary
		_check(str(drop.get("item_id", "")) == "saltpeter", "saltpeter drop item id is registered")
		_check(
			str(drop.get("model_path", "")) == "res://assets/nature/drop_items/drop_saltpeter_ore.glb",
			"saltpeter drop uses the Drop model"
		)

	var ingredient := IngredientCatalog.get_definition("saltpeter")
	_check(not ingredient.is_empty(), "saltpeter is in the ingredient catalog")
	_check(str(ingredient.get("category", "")) == "ore", "saltpeter is classified as an ore")
	_check(
			IngredientCatalog.get_harvest_drop_scene_path("saltpeter")
				== "res://assets/nature/drop_items/drop_saltpeter_ore.glb",
			"saltpeter catalog points to the Drop model"
	)

	var has_editor_asset := false
	for asset_value: Variant in HarvestOperationRuntimeMapEditor.ORE_ASSETS:
		var asset := asset_value as Dictionary
		if str(asset.get("path", "")) == "res://items/SaltpeterOre.tscn":
			has_editor_asset = true
			break
	_check(has_editor_asset, "map editor ore catalog contains saltpeter")

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("[SaltpeterOreValidation] PASS")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("[SaltpeterOreValidation] " + failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
