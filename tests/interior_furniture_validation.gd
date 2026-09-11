extends Node

const COFFEE_TABLE_SCENE := preload("res://facilities/interior/coffee_table.tscn")
const DINING_TABLE_SCENE := preload("res://facilities/interior/dining_table.tscn")
const WOODEN_CASHIER_COUNTER_SCENE := preload("res://facilities/interior/wooden_cashier_counter.tscn")
const WAREHOUSE_SHELF_SCENE := preload("res://facilities/interior/warehouse_shelf.tscn")
const SOFA_SCENE := preload("res://facilities/interior/sofa.tscn")
const CHAIR_SCENE := preload("res://facilities/interior/chair.tscn")
const FLOOR_LAMP_SCENE := preload("res://facilities/interior/floor_lamp.tscn")
const SUNSET_FLOOR_LAMP_SCENE := preload("res://facilities/interior/sunset_floor_lamp.tscn")
const TABLE_CANDLE_SCENE := preload("res://facilities/interior/table_candle.tscn")
const STANDING_TORCH_SCENE := preload("res://facilities/interior/standing_torch.tscn")
const BED_SCENE := preload("res://facilities/interior/Bed.tscn")
const DOUBLE_BED_SCENE := preload("res://facilities/interior/DoubleBed.tscn")
const LAPTOP_SCENE := preload("res://facilities/interior/laptop.tscn")
const DESKTOP_SCENE := preload("res://facilities/interior/desktop.tscn")
const PLACEMENT_QUERY := preload("res://src/placement_query.gd")
const MAP_FACILITY_CATALOG := preload("res://src/map_facility_catalog.gd")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var furniture := {
		"coffee_table": {"scene": COFFEE_TABLE_SCENE, "name": "咖啡桌", "weight": 10.0},
		"dining_table": {"scene": DINING_TABLE_SCENE, "name": "餐桌", "weight": 20.0},
		"sofa": {"scene": SOFA_SCENE, "name": "沙发", "weight": 24.0},
		"chair": {"scene": CHAIR_SCENE, "name": "椅子", "weight": 8.0},
		"floor_lamp": {"scene": FLOOR_LAMP_SCENE, "name": "落地灯", "weight": 12.0},
		"sunset_floor_lamp": {"scene": SUNSET_FLOOR_LAMP_SCENE, "name": "夕阳落地灯", "weight": 12.0},
		"table_candle": {"scene": TABLE_CANDLE_SCENE, "name": "桌面蜡烛", "weight": 0.5},
		"standing_torch": {"scene": STANDING_TORCH_SCENE, "name": "立式火炬", "weight": 10.0},
	}
	var catalog := {}
	for entry_value: Variant in MAP_FACILITY_CATALOG.get_assets("interior"):
		var entry := entry_value as Dictionary
		catalog[str(entry.get("id", ""))] = entry
	for item_id_value: Variant in furniture:
		var item_id := str(item_id_value)
		var expected := furniture[item_id] as Dictionary
		var definition: Dictionary = GameAuthority.authoritative_tool_definitions.get(item_id, {})
		_check(not definition.is_empty(), "%s has a backpack definition" % item_id)
		_check(bool(definition.get("free_placement", false)), "%s supports free placement" % item_id)
		_check(bool(definition.get("consumed_on_use", false)), "%s is consumed when placed" % item_id)
		_check(is_equal_approx(float(definition.get("weight_kg", 0.0)), float(expected.get("weight", 0.0))), "%s weight is configured" % item_id)
		_check(FileAccess.file_exists("res://assets/icons/items/tools/%s.png" % item_id), "%s item icon exists" % item_id)
		var peer_id := 9230 + furniture.keys().find(item_id)
		GameAuthority.register_or_update_player(peer_id, {"display_name": "FurnitureGet", "team": "red", "primary_weapon_ids": [], "special_tool_ids": []})
		var get_state: Dictionary = GameAuthority.player_states.get(peer_id, {})
		var get_result: Dictionary = GameAuthority.call("_server_debug_get_tool", peer_id, get_state, "[get] %s 1" % item_id)
		_check(bool(get_result.get("ok", false)), "[get] grants %s" % item_id)
		var packed := expected.get("scene") as PackedScene
		var node := packed.instantiate() as StaticBody3D if packed != null else null
		_check(node != null, "%s scene instantiates as StaticBody3D" % item_id)
		if node != null:
			_check(node.collision_layer == 128 and node.collision_mask == 0, "%s collision contract is correct" % item_id)
			_check(node.get_node_or_null("CollisionShape3D") is CollisionShape3D, "%s has a root collision shape" % item_id)
			node.free()
		var catalog_entry: Dictionary = catalog.get("interior_%s" % item_id, {})
		_check(str(catalog_entry.get("label", "")) == str(expected.get("name", "")), "%s is discoverable with its Chinese name" % item_id)

	_validate_non_craftable_bed(BED_SCENE, "bed", "单人床", Vector3(3.0, 1.3, 4.2))
	_validate_non_craftable_bed(DOUBLE_BED_SCENE, "double_bed", "双人床", Vector3(4.8, 1.3, 4.2))
	_validate_non_craftable_interior_facility(WOODEN_CASHIER_COUNTER_SCENE, "wooden_cashier_counter", "木质收银台", Vector3(2.35, 1.4250001, 1.1325))
	_validate_non_craftable_interior_facility(WAREHOUSE_SHELF_SCENE, "warehouse_shelf", "仓库货架", Vector3(3.8200002, 2.88, 0.88500005))

	var coffee := COFFEE_TABLE_SCENE.instantiate() as StaticBody3D
	var dining := DINING_TABLE_SCENE.instantiate() as StaticBody3D
	var cashier_counter := WOODEN_CASHIER_COUNTER_SCENE.instantiate() as StaticBody3D
	var warehouse_shelf := WAREHOUSE_SHELF_SCENE.instantiate() as StaticBody3D
	var sofa := SOFA_SCENE.instantiate() as StaticBody3D
	var chair := CHAIR_SCENE.instantiate() as StaticBody3D
	add_child(coffee)
	add_child(dining)
	add_child(cashier_counter)
	add_child(warehouse_shelf)
	add_child(sofa)
	add_child(chair)
	_check(coffee.is_in_group("tabletop_supports") and dining.is_in_group("tabletop_supports") and cashier_counter.is_in_group("tabletop_supports"), "tables and cashier counter expose tabletop supports")
	_check(not warehouse_shelf.is_in_group("tabletop_supports"), "warehouse shelf is not a tabletop support")
	_check(not sofa.is_in_group("tabletop_supports"), "sofa is not a tabletop support")
	_check(not chair.is_in_group("tabletop_supports"), "chair is not a tabletop support")
	_check(bool(GameAuthority.authoritative_tool_definitions.get("laptop", {}).get("tabletop_placeable", false)), "laptop opts into tabletop placement")
	_check(bool(GameAuthority.authoritative_tool_definitions.get("desktop", {}).get("tabletop_placeable", false)), "desktop opts into tabletop placement")
	_check(bool(GameAuthority.authoritative_tool_definitions.get("table_candle", {}).get("tabletop_placeable", false)), "table candle opts into tabletop placement")
	_check(bool(GameAuthority.authoritative_tool_definitions.get("table_candle", {}).get("allow_support_object_overlap", false)), "table candle allows tabletop support overlap")
	_check(not bool(GameAuthority.authoritative_tool_definitions.get("standing_torch", {}).get("tabletop_placeable", false)), "standing torch remains a ground placement item")
	_validate_night_lights()
	var table_candle := TABLE_CANDLE_SCENE.instantiate() as StaticBody3D
	var standing_torch := STANDING_TORCH_SCENE.instantiate() as StaticBody3D
	var candle_shape := table_candle.get_node_or_null("CollisionShape3D") as CollisionShape3D if table_candle != null else null
	_check(candle_shape != null and candle_shape.shape is BoxShape3D, "table candle uses a box footprint for tabletop validation")
	if candle_shape != null:
		var candle_result := PLACEMENT_QUERY.validate_tabletop_footprint(coffee, Vector3.ZERO, 0.0, candle_shape.shape, candle_shape.transform)
		_check(bool(candle_result.get("ok", false)), "table candle footprint fits the coffee table")
	if table_candle != null:
		table_candle.free()
	if standing_torch != null:
		standing_torch.free()
	var coffee_recipe := IndustrialRecipeCatalog.get_recipe("wood_coffee_table")
	var dining_recipe := IndustrialRecipeCatalog.get_recipe("wood_dining_table")
	var sofa_recipe := IndustrialRecipeCatalog.get_recipe("wood_sofa")
	var chair_recipe := IndustrialRecipeCatalog.get_recipe("wood_chair")
	_check(str(coffee_recipe.get("output", {}).get("id", "")) == "coffee_table", "coffee table recipe is registered")
	_check(str(dining_recipe.get("output", {}).get("id", "")) == "dining_table", "dining table recipe is registered")
	_check(IndustrialRecipeCatalog.get_inputs("wood_sofa").size() == 3 and str(sofa_recipe.get("output", {}).get("id", "")) == "sofa", "sofa recipe consumes all three materials")
	_check(str(chair_recipe.get("output", {}).get("id", "")) == "chair", "chair recipe is registered")
	var chair_inputs := IndustrialRecipeCatalog.get_inputs("wood_chair")
	_check(chair_inputs.size() == 1 and str(chair_inputs[0].get("id", "")) == "lumber" and is_equal_approx(float(chair_inputs[0].get("amount", 0.0)), 6.0) and str(chair_inputs[0].get("unit", "")) == "kg", "chair recipe consumes six kilograms of lumber")
	var laptop_shape := (LAPTOP_SCENE.instantiate() as Node3D).get_node_or_null("CollisionShape3D") as CollisionShape3D
	var desktop_shape := (DESKTOP_SCENE.instantiate() as Node3D).get_node_or_null("CollisionShape3D") as CollisionShape3D
	_check(laptop_shape != null and desktop_shape != null, "tabletop test facilities have collision shapes")
	if laptop_shape != null:
		var accepted := PLACEMENT_QUERY.validate_tabletop_footprint(coffee, Vector3.ZERO, 0.0, laptop_shape.shape, laptop_shape.transform)
		var overflow := PLACEMENT_QUERY.validate_tabletop_footprint(coffee, Vector3(0.4, 0.0, 0.0), 0.0, laptop_shape.shape, laptop_shape.transform)
		var rotated := PLACEMENT_QUERY.validate_tabletop_footprint(coffee, Vector3.ZERO, PI * 0.5, laptop_shape.shape, laptop_shape.transform)
		_check(bool(accepted.get("ok", false)), "laptop footprint fits the coffee table")
		_check(str(overflow.get("reason", "")) == "placement_exceeds_tabletop", "coffee table rejects overflow")
		_check(str(rotated.get("reason", "")) == "placement_exceeds_tabletop", "coffee table rejects rotated overflow")
	if desktop_shape != null:
		var desktop_result := PLACEMENT_QUERY.validate_tabletop_footprint(dining, Vector3.ZERO, 0.0, desktop_shape.shape, desktop_shape.transform)
		_check(str(desktop_result.get("reason", "")) == "placement_exceeds_tabletop", "dining table rejects an oversized desktop")
	if laptop_shape != null:
		var cashier_result := PLACEMENT_QUERY.validate_tabletop_footprint(cashier_counter, Vector3.ZERO, 0.0, laptop_shape.shape, laptop_shape.transform)
		_check(bool(cashier_result.get("ok", false)), "cashier counter accepts a laptop on its surface")
	coffee.free()
	dining.free()
	cashier_counter.free()
	warehouse_shelf.free()
	sofa.free()
	chair.free()
	_finish()


func _validate_night_lights() -> void:
	var lights := [
		{"scene": FLOOR_LAMP_SCENE, "name": "floor lamp", "range": 5.5, "energy": 3.0},
		{"scene": SUNSET_FLOOR_LAMP_SCENE, "name": "sunset floor lamp", "range": 5.5, "energy": 3.5},
		{"scene": STANDING_TORCH_SCENE, "name": "standing torch", "range": 7.0, "energy": 3.0},
		{"scene": TABLE_CANDLE_SCENE, "name": "table candle", "range": 2.2, "energy": 1.2},
	]
	for entry_value: Variant in lights:
		var entry := entry_value as Dictionary
		var lamp := (entry.get("scene") as PackedScene).instantiate() as StaticBody3D
		_check(lamp != null, "%s scene instantiates for night lighting" % entry.get("name", "light"))
		if lamp == null:
			continue
		add_child(lamp)
		var light := lamp.find_child("NightLight", true, false) as OmniLight3D
		_check(light != null, "%s has a NightLight OmniLight3D" % entry.get("name", "light"))
		_check(lamp.is_in_group("day_night_lamps"), "%s joins the day/night lamp group" % entry.get("name", "light"))
		if light != null:
			_check(is_zero_approx(light.light_energy), "%s starts off before night" % entry.get("name", "light"))
			_check(is_equal_approx(light.omni_range, float(entry.get("range", 0.0))), "%s uses its configured light range" % entry.get("name", "light"))
			lamp.set_night_factor(1.0)
			_check(is_equal_approx(light.light_energy, float(entry.get("energy", 0.0))), "%s reaches its configured night intensity" % entry.get("name", "light"))
			lamp.set_night_factor(0.0)
			_check(is_zero_approx(light.light_energy), "%s switches off at daytime" % entry.get("name", "light"))
		lamp.free()


func _validate_non_craftable_bed(
	packed: PackedScene,
	asset_id: String,
	label: String,
	expected_collision_size: Vector3
) -> void:
	var definition: Dictionary = GameAuthority.authoritative_tool_definitions.get(asset_id, {})
	_check(definition.is_empty(), "%s is not a player tool definition" % asset_id)
	_check(IndustrialRecipeCatalog.get_recipe("wood_%s" % asset_id).is_empty(), "%s has no player recipe" % asset_id)
	var catalog_entry: Dictionary = {}
	for entry_value: Variant in MAP_FACILITY_CATALOG.get_assets("interior"):
		var entry := entry_value as Dictionary
		if str(entry.get("id", "")) == "interior_%s" % asset_id:
			catalog_entry = entry
			break
	_check(str(catalog_entry.get("label", "")) == label, "%s is registered as an interior facility" % asset_id)
	_check(str(catalog_entry.get("path", "")) == ("res://facilities/interior/%s.tscn" % ("Bed" if asset_id == "bed" else "DoubleBed")), "%s catalog path is correct" % asset_id)
	if packed == null:
		_check(false, "%s scene loads" % asset_id)
		return
	var bed := packed.instantiate() as StaticBody3D
	_check(bed != null, "%s scene instantiates as StaticBody3D" % asset_id)
	if bed == null:
		return
	_check(bed.collision_layer == 128 and bed.collision_mask == 0, "%s uses the interior facility collision contract" % asset_id)
	var main_shape := bed.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_check(main_shape != null and main_shape.shape is BoxShape3D, "%s has a box collision shape" % asset_id)
	if main_shape != null and main_shape.shape is BoxShape3D:
		_check((main_shape.shape as BoxShape3D).size.is_equal_approx(expected_collision_size), "%s collision dimensions match the bed footprint" % asset_id)
	var placement := bed.get_node_or_null("PlacementFootprint/CollisionShape3D") as CollisionShape3D
	_check(placement != null and placement.shape is BoxShape3D, "%s has a map-editor placement footprint" % asset_id)
	bed.free()


func _validate_non_craftable_interior_facility(
	packed: PackedScene,
	asset_id: String,
	label: String,
	expected_collision_size: Vector3
) -> void:
	var definition: Dictionary = GameAuthority.authoritative_tool_definitions.get(asset_id, {})
	_check(definition.is_empty(), "%s is not a player tool definition" % asset_id)
	_check(IndustrialRecipeCatalog.get_recipe("wood_%s" % asset_id).is_empty(), "%s has no player recipe" % asset_id)
	var catalog_entry: Dictionary = MAP_FACILITY_CATALOG.get_asset_by_id("interior_%s" % asset_id)
	_check(str(catalog_entry.get("label", "")) == label, "%s is registered as an interior facility" % asset_id)
	_check(str(catalog_entry.get("path", "")) == packed.resource_path, "%s catalog path is correct" % asset_id)
	var facility := packed.instantiate() as StaticBody3D
	_check(facility != null, "%s scene instantiates as StaticBody3D" % asset_id)
	if facility == null:
		return
	_check(facility.collision_layer == 128 and facility.collision_mask == 0, "%s uses the interior facility collision contract" % asset_id)
	var main_shape := facility.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_check(main_shape != null and main_shape.shape is BoxShape3D, "%s has a box collision shape" % asset_id)
	if main_shape != null and main_shape.shape is BoxShape3D:
		_check((main_shape.shape as BoxShape3D).size.is_equal_approx(expected_collision_size), "%s collision dimensions match its footprint" % asset_id)
	var placement := facility.get_node_or_null("PlacementFootprint/CollisionShape3D") as CollisionShape3D
	_check(placement != null and placement.shape is BoxShape3D, "%s has a map-editor placement footprint" % asset_id)
	facility.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("[InteriorFurnitureValidation] PASS")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("[InteriorFurnitureValidation] %s" % failure)
	get_tree().quit(1)
