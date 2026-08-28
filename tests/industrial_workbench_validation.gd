extends Node3D

const WORKBENCH_SCENES := {
	"industrial_furnace": "res://facilities/industrial/industrial_furnace.tscn",
	"wood_processing_table": "res://facilities/industrial/wood_processing_table.tscn",
	"comprehensive_material_processing_station": "res://facilities/industrial/comprehensive_material_processing_station.tscn",
	"electronic_assembly_station": "res://facilities/industrial/electronic_assembly_station.tscn",
}

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var validation := IndustrialRecipeCatalog.validate_catalog()
	_check(bool(validation.get("ok", false)), "industrial recipe catalog validates")
	_check(int(validation.get("recipe_count", 0)) == 45, "catalog contains 45 recipes")
	_check(IndustrialRecipeCatalog.get_recipes_for_workbench("industrial_furnace").size() == 5, "furnace contains 5 recipes")
	_check(IndustrialRecipeCatalog.get_recipes_for_workbench("wood_processing_table").size() == 3, "wood table contains 3 recipes")
	_check(IndustrialRecipeCatalog.get_recipes_for_workbench("comprehensive_material_processing_station").size() == 25, "material station contains 25 recipes")
	_check(IndustrialRecipeCatalog.get_recipes_for_workbench("electronic_assembly_station").size() == 12, "electronic station contains 12 recipes")
	_check(IndustrialRecipeCatalog.get_recipes_for_workbench("robot_assembly_pod").is_empty(), "robot assembly has no recipe")
	for recipe in IndustrialRecipeCatalog.get_recipes():
		_check(IndustrialRecipeCatalog.get_duration_seconds(str(recipe.get("recipe_id", ""))) >= 8.0, "recipe duration has minimum")
		_check(IndustrialRecipeCatalog.get_duration_seconds(str(recipe.get("recipe_id", ""))) <= 90.0, "recipe duration has maximum")
	for workbench_id: String in WORKBENCH_SCENES:
		var packed := load(WORKBENCH_SCENES[workbench_id]) as PackedScene
		_check(packed != null, "%s scene loads" % workbench_id)
		if packed == null:
			continue
		var workbench := packed.instantiate() as IndustrialWorkbench
		_check(workbench != null, "%s uses IndustrialWorkbench base" % workbench_id)
		if workbench == null:
			continue
		add_child(workbench)
		await get_tree().process_frame
		_check(workbench.get_workbench_id() == workbench_id, "%s metadata id is registered" % workbench_id)
		_check(not (workbench as Node) is KitchenAppliance, "%s is not a kitchen appliance" % workbench_id)
		workbench.queue_free()
	await get_tree().process_frame
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("[IndustrialWorkbenchValidation] PASS")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("[IndustrialWorkbenchValidation] " + failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
