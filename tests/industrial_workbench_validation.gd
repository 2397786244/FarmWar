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
	_check(int(validation.get("recipe_count", 0)) == 59, "catalog contains 59 recipes")
	_check(IndustrialRecipeCatalog.get_recipes_for_workbench("industrial_furnace").size() == 5, "furnace contains 5 recipes")
	_check(IndustrialRecipeCatalog.get_recipes_for_workbench("wood_processing_table").size() == 9, "wood table contains 9 recipes")
	var rack_recipe := IndustrialRecipeCatalog.get_recipe("wood_weapons_display_rack")
	_check(str(rack_recipe.get("workbench_id", "")) == "wood_processing_table", "rack recipe is on the wood processing table")
	_check(str(rack_recipe.get("output", {}).get("id", "")) == "weapons_display_rack", "rack recipe outputs the backpack rack item")
	var rack_inputs := IndustrialRecipeCatalog.get_inputs("wood_weapons_display_rack")
	_check(float(rack_inputs[0].get("amount", 0.0)) == 4.0 and str(rack_inputs[0].get("id", "")) == "metal_defense_net", "rack recipe consumes four metal defense nets")
	_check(float(rack_inputs[1].get("amount", 0.0)) == 8.0 and str(rack_inputs[1].get("id", "")) == "lumber", "rack recipe consumes eight lumber")
	var tall_log_wall_recipe := IndustrialRecipeCatalog.get_recipe("wood_tall_log_wall")
	_check(str(tall_log_wall_recipe.get("workbench_id", "")) == "wood_processing_table", "tall log wall recipe is on the wood processing table")
	_check(str(tall_log_wall_recipe.get("output", {}).get("id", "")) == "tall_log_wall", "tall log wall recipe outputs the tall log wall")
	var tall_log_wall_inputs := IndustrialRecipeCatalog.get_inputs("wood_tall_log_wall")
	_check(tall_log_wall_inputs.size() == 2, "tall log wall recipe has lumber and connectors")
	_check(tall_log_wall_inputs.size() == 2 and str(tall_log_wall_inputs[0].get("id", "")) == "lumber" and is_equal_approx(float(tall_log_wall_inputs[0].get("amount", 0.0)), 24.0) and str(tall_log_wall_inputs[0].get("unit", "")) == "kg", "tall log wall consumes 24 kilograms of lumber")
	_check(tall_log_wall_inputs.size() == 2 and str(tall_log_wall_inputs[1].get("id", "")) == "metal_connector" and is_equal_approx(float(tall_log_wall_inputs[1].get("amount", 0.0)), 4.0) and str(tall_log_wall_inputs[1].get("unit", "")) == "item", "tall log wall consumes four metal connectors")
	_check(IndustrialRecipeCatalog.get_recipes_for_workbench("comprehensive_material_processing_station").size() == 31, "material station contains 31 recipes")
	var tall_brick_recipe := IndustrialRecipeCatalog.get_recipe("material_tall_brick_wall")
	var tall_mesh_recipe := IndustrialRecipeCatalog.get_recipe("material_tall_mesh_wall")
	var wire_mesh_gate_recipe := IndustrialRecipeCatalog.get_recipe("material_wire_mesh_gate")
	var chain_link_fence_recipe := IndustrialRecipeCatalog.get_recipe("material_chain_link_fence")
	_check(str(tall_brick_recipe.get("workbench_id", "")) == "comprehensive_material_processing_station", "tall brick wall recipe is on the material processing station")
	_check(str(tall_mesh_recipe.get("workbench_id", "")) == "comprehensive_material_processing_station", "tall mesh wall recipe is on the material processing station")
	_check(str(wire_mesh_gate_recipe.get("workbench_id", "")) == "comprehensive_material_processing_station", "wire mesh gate recipe is on the material processing station")
	_check(str(chain_link_fence_recipe.get("workbench_id", "")) == "comprehensive_material_processing_station", "chain link fence recipe is on the material processing station")
	_check(str(tall_brick_recipe.get("output", {}).get("id", "")) == "tall_brick", "tall brick wall recipe outputs the tall brick wall")
	_check(str(tall_mesh_recipe.get("output", {}).get("id", "")) == "tall_mesh_wall", "tall mesh wall recipe outputs the tall mesh wall")
	_check(str(wire_mesh_gate_recipe.get("output", {}).get("id", "")) == "wire_mesh_gate", "wire mesh gate recipe outputs the wire mesh gate")
	_check(str(chain_link_fence_recipe.get("output", {}).get("id", "")) == "chain_link_fence", "chain link fence recipe outputs the chain link fence")
	var tall_brick_inputs := IndustrialRecipeCatalog.get_inputs("material_tall_brick_wall")
	var tall_mesh_inputs := IndustrialRecipeCatalog.get_inputs("material_tall_mesh_wall")
	var wire_mesh_gate_inputs := IndustrialRecipeCatalog.get_inputs("material_wire_mesh_gate")
	var chain_link_fence_inputs := IndustrialRecipeCatalog.get_inputs("material_chain_link_fence")
	_check(tall_brick_inputs.size() == 3 and str(tall_brick_inputs[0].get("id", "")) == "stone" and is_equal_approx(float(tall_brick_inputs[0].get("amount", 0.0)), 32.0) and str(tall_brick_inputs[0].get("unit", "")) == "kg", "tall brick wall consumes 32 kilograms of stone")
	_check(tall_brick_inputs.size() == 3 and str(tall_brick_inputs[1].get("id", "")) == "steel_plate" and is_equal_approx(float(tall_brick_inputs[1].get("amount", 0.0)), 2.0) and str(tall_brick_inputs[1].get("unit", "")) == "kg", "tall brick wall consumes two kilograms of steel plate")
	_check(tall_brick_inputs.size() == 3 and str(tall_brick_inputs[2].get("id", "")) == "metal_connector" and is_equal_approx(float(tall_brick_inputs[2].get("amount", 0.0)), 4.0) and str(tall_brick_inputs[2].get("unit", "")) == "item", "tall brick wall consumes four metal connectors")
	_check(tall_mesh_inputs.size() == 3 and str(tall_mesh_inputs[0].get("id", "")) == "metal_defense_net" and is_equal_approx(float(tall_mesh_inputs[0].get("amount", 0.0)), 3.0) and str(tall_mesh_inputs[0].get("unit", "")) == "item", "tall mesh wall consumes three metal defense nets")
	_check(tall_mesh_inputs.size() == 3 and str(tall_mesh_inputs[1].get("id", "")) == "steel_plate" and is_equal_approx(float(tall_mesh_inputs[1].get("amount", 0.0)), 2.0) and str(tall_mesh_inputs[1].get("unit", "")) == "kg", "tall mesh wall consumes two kilograms of steel plate")
	_check(tall_mesh_inputs.size() == 3 and str(tall_mesh_inputs[2].get("id", "")) == "metal_connector" and is_equal_approx(float(tall_mesh_inputs[2].get("amount", 0.0)), 2.0) and str(tall_mesh_inputs[2].get("unit", "")) == "item", "tall mesh wall consumes two metal connectors")
	_check(wire_mesh_gate_inputs.size() == 4 and str(wire_mesh_gate_inputs[0].get("id", "")) == "metal_defense_net" and is_equal_approx(float(wire_mesh_gate_inputs[0].get("amount", 0.0)), 3.0) and str(wire_mesh_gate_inputs[0].get("unit", "")) == "item", "wire mesh gate consumes three metal defense nets")
	_check(wire_mesh_gate_inputs.size() == 4 and str(wire_mesh_gate_inputs[1].get("id", "")) == "steel_plate" and is_equal_approx(float(wire_mesh_gate_inputs[1].get("amount", 0.0)), 2.0) and str(wire_mesh_gate_inputs[1].get("unit", "")) == "kg", "wire mesh gate consumes two kilograms of steel plate")
	_check(wire_mesh_gate_inputs.size() == 4 and str(wire_mesh_gate_inputs[2].get("id", "")) == "metal_connector" and is_equal_approx(float(wire_mesh_gate_inputs[2].get("amount", 0.0)), 2.0) and str(wire_mesh_gate_inputs[2].get("unit", "")) == "item", "wire mesh gate consumes two metal connectors")
	_check(wire_mesh_gate_inputs.size() == 4 and str(wire_mesh_gate_inputs[3].get("id", "")) == "bearing" and is_equal_approx(float(wire_mesh_gate_inputs[3].get("amount", 0.0)), 2.0) and str(wire_mesh_gate_inputs[3].get("unit", "")) == "item", "wire mesh gate consumes two bearings")
	_check(chain_link_fence_inputs.size() == 2 and str(chain_link_fence_inputs[0].get("id", "")) == "metal_defense_net" and is_equal_approx(float(chain_link_fence_inputs[0].get("amount", 0.0)), 1.0) and str(chain_link_fence_inputs[0].get("unit", "")) == "item", "chain link fence consumes one metal defense net")
	_check(chain_link_fence_inputs.size() == 2 and str(chain_link_fence_inputs[1].get("id", "")) == "steel_plate" and is_equal_approx(float(chain_link_fence_inputs[1].get("amount", 0.0)), 1.0) and str(chain_link_fence_inputs[1].get("unit", "")) == "kg", "chain link fence consumes one kilogram of steel plate")
	_check(IndustrialRecipeCatalog.get_recipes_for_workbench("electronic_assembly_station").size() == 14, "electronic station contains 14 recipes")
	var floor_lamp_recipe := IndustrialRecipeCatalog.get_recipe("electronic_floor_lamp")
	var sunset_floor_lamp_recipe := IndustrialRecipeCatalog.get_recipe("electronic_sunset_floor_lamp")
	_check(str(floor_lamp_recipe.get("workbench_id", "")) == "electronic_assembly_station", "floor lamp recipe is on the electronic assembly station")
	_check(str(sunset_floor_lamp_recipe.get("workbench_id", "")) == "electronic_assembly_station", "sunset floor lamp recipe is on the electronic assembly station")
	_check(str(floor_lamp_recipe.get("output", {}).get("id", "")) == "floor_lamp", "floor lamp recipe outputs the floor lamp backpack item")
	_check(str(sunset_floor_lamp_recipe.get("output", {}).get("id", "")) == "sunset_floor_lamp", "sunset floor lamp recipe outputs the sunset floor lamp backpack item")
	var floor_lamp_inputs := IndustrialRecipeCatalog.get_inputs("electronic_floor_lamp")
	var sunset_floor_lamp_inputs := IndustrialRecipeCatalog.get_inputs("electronic_sunset_floor_lamp")
	_check(floor_lamp_inputs.size() == 4, "floor lamp recipe has four materials")
	_check(sunset_floor_lamp_inputs.size() == 4, "sunset floor lamp recipe has four materials")
	_check(float(floor_lamp_inputs[0].get("amount", 0.0)) == 2.0 and str(floor_lamp_inputs[0].get("id", "")) == "steel_plate" and str(floor_lamp_inputs[0].get("unit", "")) == "kg", "floor lamp recipe consumes two kilograms of steel plate")
	_check(float(floor_lamp_inputs[1].get("amount", 0.0)) == 1.0 and str(floor_lamp_inputs[1].get("id", "")) == "glass_panes" and str(floor_lamp_inputs[1].get("unit", "")) == "kg", "floor lamp recipe consumes one kilogram of glass")
	_check(float(floor_lamp_inputs[2].get("amount", 0.0)) == 1.0 and str(floor_lamp_inputs[2].get("id", "")) == "circuit_board" and str(floor_lamp_inputs[2].get("unit", "")) == "item", "floor lamp recipe consumes one circuit board")
	_check(float(floor_lamp_inputs[3].get("amount", 0.0)) == 1.0 and str(floor_lamp_inputs[3].get("id", "")) == "copper_wire" and str(floor_lamp_inputs[3].get("unit", "")) == "kg", "floor lamp recipe consumes one kilogram of copper wire")
	for index in range(mini(floor_lamp_inputs.size(), sunset_floor_lamp_inputs.size())):
		_check(sunset_floor_lamp_inputs[index] == floor_lamp_inputs[index], "sunset floor lamp uses the same material recipe")
	var candle_recipe := IndustrialRecipeCatalog.get_recipe("material_table_candle")
	var torch_recipe := IndustrialRecipeCatalog.get_recipe("material_standing_torch")
	_check(str(candle_recipe.get("workbench_id", "")) == "comprehensive_material_processing_station", "table candle recipe is on the material processing station")
	_check(str(torch_recipe.get("workbench_id", "")) == "comprehensive_material_processing_station", "standing torch recipe is on the material processing station")
	_check(str(candle_recipe.get("output", {}).get("id", "")) == "table_candle", "table candle recipe outputs the backpack candle item")
	_check(str(torch_recipe.get("output", {}).get("id", "")) == "standing_torch", "standing torch recipe outputs the backpack torch item")
	var candle_inputs := IndustrialRecipeCatalog.get_inputs("material_table_candle")
	var torch_inputs := IndustrialRecipeCatalog.get_inputs("material_standing_torch")
	_check(candle_inputs.size() == 2, "table candle recipe has oil and cotton")
	_check(candle_inputs.size() == 2 and str(candle_inputs[0].get("id", "")) == "oil" and is_equal_approx(float(candle_inputs[0].get("amount", 0.0)), 0.2) and str(candle_inputs[0].get("unit", "")) == "kg", "table candle consumes 0.2 kilograms of oil")
	_check(candle_inputs.size() == 2 and str(candle_inputs[1].get("id", "")) == "cotton" and is_equal_approx(float(candle_inputs[1].get("amount", 0.0)), 0.05) and str(candle_inputs[1].get("unit", "")) == "kg", "table candle consumes 0.05 kilograms of cotton")
	_check(torch_inputs.size() == 3, "standing torch recipe has oil, cotton and steel plate")
	_check(torch_inputs.size() == 3 and str(torch_inputs[0].get("id", "")) == "oil" and is_equal_approx(float(torch_inputs[0].get("amount", 0.0)), 0.8) and str(torch_inputs[0].get("unit", "")) == "kg", "standing torch consumes 0.8 kilograms of oil")
	_check(torch_inputs.size() == 3 and str(torch_inputs[1].get("id", "")) == "cotton" and is_equal_approx(float(torch_inputs[1].get("amount", 0.0)), 0.2) and str(torch_inputs[1].get("unit", "")) == "kg", "standing torch consumes 0.2 kilograms of cotton")
	_check(torch_inputs.size() == 3 and str(torch_inputs[2].get("id", "")) == "steel_plate" and is_equal_approx(float(torch_inputs[2].get("amount", 0.0)), 2.0) and str(torch_inputs[2].get("unit", "")) == "kg", "standing torch consumes two kilograms of steel plate")
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
