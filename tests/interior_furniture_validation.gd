extends Node

const COFFEE_TABLE_SCENE := preload("res://facilities/interior/coffee_table.tscn")
const DINING_TABLE_SCENE := preload("res://facilities/interior/dining_table.tscn")
const SOFA_SCENE := preload("res://facilities/interior/sofa.tscn")
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

	var coffee := COFFEE_TABLE_SCENE.instantiate() as StaticBody3D
	var dining := DINING_TABLE_SCENE.instantiate() as StaticBody3D
	var sofa := SOFA_SCENE.instantiate() as StaticBody3D
	add_child(coffee)
	add_child(dining)
	add_child(sofa)
	_check(coffee.is_in_group("tabletop_supports") and dining.is_in_group("tabletop_supports"), "tables expose tabletop supports")
	_check(not sofa.is_in_group("tabletop_supports"), "sofa is not a tabletop support")
	_check(bool(GameAuthority.authoritative_tool_definitions.get("laptop", {}).get("tabletop_placeable", false)), "laptop opts into tabletop placement")
	_check(bool(GameAuthority.authoritative_tool_definitions.get("desktop", {}).get("tabletop_placeable", false)), "desktop opts into tabletop placement")
	var coffee_recipe := IndustrialRecipeCatalog.get_recipe("wood_coffee_table")
	var dining_recipe := IndustrialRecipeCatalog.get_recipe("wood_dining_table")
	var sofa_recipe := IndustrialRecipeCatalog.get_recipe("wood_sofa")
	_check(str(coffee_recipe.get("output", {}).get("id", "")) == "coffee_table", "coffee table recipe is registered")
	_check(str(dining_recipe.get("output", {}).get("id", "")) == "dining_table", "dining table recipe is registered")
	_check(IndustrialRecipeCatalog.get_inputs("wood_sofa").size() == 3 and str(sofa_recipe.get("output", {}).get("id", "")) == "sofa", "sofa recipe consumes all three materials")
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
	coffee.free()
	dining.free()
	sofa.free()
	_finish()


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
