extends RefCounted
class_name DishCatalog

const DEFINITIONS_PATH := "res://data/dish_definitions.json"

static var _dishes: Dictionary = {}
static var _loaded := false


static func get_definition(dish_id: String) -> Dictionary:
	_ensure_loaded()
	var definition: Variant = _dishes.get(dish_id, {})
	return (definition as Dictionary).duplicate(true) if definition is Dictionary else {}


static func get_model_path(dish_id: String) -> String:
	return str(get_definition(dish_id).get("model_path", ""))


static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for dish_id_value: Variant in _dishes.keys():
		ids.append(str(dish_id_value))
	return ids


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(DEFINITIONS_PATH, FileAccess.READ)
	if file == null:
		push_error("Dish catalog is missing: %s" % DEFINITIONS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Dish catalog contains invalid JSON: %s" % DEFINITIONS_PATH)
		return
	var values: Variant = (parsed as Dictionary).get("dishes", {})
	if values is Dictionary:
		_dishes = values as Dictionary
