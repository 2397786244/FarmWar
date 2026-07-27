extends RefCounted
class_name IngredientCatalog

const DEFINITIONS_PATH := "res://data/ingredient_definitions.json"

static var _ingredients: Dictionary = {}
static var _plantable_order: Array = []
static var _loaded := false


static func get_definition(ingredient_id: String) -> Dictionary:
	_ensure_loaded()
	var definition: Variant = _ingredients.get(ingredient_id, {})
	return (definition as Dictionary).duplicate(true) if definition is Dictionary else {}


static func get_pickup_unit_kg(ingredient_id: String) -> float:
	return maxf(0.01, float(get_definition(ingredient_id).get("pickup_unit_kg", 1.0)))


static func is_plantable(ingredient_id: String) -> bool:
	var source: Variant = get_definition(ingredient_id).get("source", {})
	return source is Dictionary and bool((source as Dictionary).get("plantable", false))


static func get_plantable_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for ingredient_id_value: Variant in _plantable_order:
		var ingredient_id := str(ingredient_id_value)
		if is_plantable(ingredient_id):
			ids.append(ingredient_id)
	return ids


static func is_team_storage_material(ingredient_id: String) -> bool:
	var definition := get_definition(ingredient_id)
	if definition.is_empty():
		return false
	return is_plantable(ingredient_id) or str(definition.get("category", "")) in ["wood", "ore"]


static func get_team_storage_material_ids() -> Array[String]:
	_ensure_loaded()
	var ids := get_plantable_ids()
	for ingredient_id_value: Variant in _ingredients.keys():
		var ingredient_id := str(ingredient_id_value)
		if is_team_storage_material(ingredient_id) and not ids.has(ingredient_id):
			ids.append(ingredient_id)
	return ids


static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for ingredient_id_value: Variant in _ingredients.keys():
		ids.append(str(ingredient_id_value))
	return ids


static func get_crop_layout(ingredient_id: String) -> Dictionary:
	var definition := get_definition(ingredient_id)
	var source: Variant = definition.get("source", {})
	if not source is Dictionary:
		return {}
	var source_data := source as Dictionary
	var scene_path := str(source_data.get("farm_scene", ""))
	if not bool(source_data.get("plantable", false)) or scene_path.is_empty():
		return {}
	return {
		"scene": scene_path,
		"count": maxi(1, int(source_data.get("farm_tile_count", 1))),
		"harvest_kg_per_instance": _get_harvest_weight_per_instance(ingredient_id, source_data),
	}


static func _get_harvest_weight_per_instance(ingredient_id: String, source_data: Dictionary) -> float:
	var pickup_unit := get_pickup_unit_kg(ingredient_id)
	var requested_weight := maxf(pickup_unit, float(source_data.get("harvest_kg_per_instance", 1.0)))
	var maximum_multiple := maxi(1, floori(1.0 / pickup_unit + 0.0001))
	var requested_multiple := maxi(1, floori(requested_weight / pickup_unit + 0.0001))
	return pickup_unit * float(mini(requested_multiple, maximum_multiple))


static func is_reharvestable(ingredient_id: String) -> bool:
	var source: Variant = get_definition(ingredient_id).get("source", {})
	return source is Dictionary and bool((source as Dictionary).get("reharvestable", false))


static func get_model_path(ingredient_id: String, model_state: String) -> String:
	var models: Variant = get_definition(ingredient_id).get("models", {})
	return str((models as Dictionary).get(model_state, "")) if models is Dictionary else ""


static func get_harvest_drop_scene_path(ingredient_id: String) -> String:
	return get_model_path(ingredient_id, "harvest_drop")


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(DEFINITIONS_PATH, FileAccess.READ)
	if file == null:
		push_error("Ingredient catalog is missing: %s" % DEFINITIONS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Ingredient catalog contains invalid JSON: %s" % DEFINITIONS_PATH)
		return
	var definitions: Variant = (parsed as Dictionary).get("ingredients", {})
	if definitions is Dictionary:
		_ingredients = definitions as Dictionary
	var planting_order: Variant = (parsed as Dictionary).get("plantable_order", [])
	if planting_order is Array:
		_plantable_order = planting_order as Array
