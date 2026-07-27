extends RefCounted
class_name AutoCookerRecipeCatalog

const DEFINITIONS_PATH := "res://data/auto_cooker_recipe_definitions.json"
static var _recipes: Dictionary = {}
static var _order: Array[String] = []
static var _loaded := false

static func get_recipe(recipe_id: String) -> Dictionary:
	_ensure_loaded()
	var recipe: Variant = _recipes.get(recipe_id, {})
	return (recipe as Dictionary).duplicate(true) if recipe is Dictionary else {}

static func get_recipes() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for recipe_id in _order:
		var recipe := get_recipe(recipe_id)
		if not recipe.is_empty(): result.append(recipe)
	return result

static func get_ingredients(recipe_id: String) -> Array[Dictionary]:
	var values: Variant = get_recipe(recipe_id).get("ingredients", [])
	var result: Array[Dictionary] = []
	if values is Array:
		for value in values:
			if value is Dictionary: result.append((value as Dictionary).duplicate(true))
	return result

static func _ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	var file := FileAccess.open(DEFINITIONS_PATH, FileAccess.READ)
	if file == null:
		push_error("Automatic cook recipes are missing: %s" % DEFINITIONS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary: return
	var source := parsed as Dictionary
	var recipes: Variant = source.get("recipes", {})
	if not recipes is Dictionary: return
	for id_value in source.get("recipe_order", []):
		var recipe_id := str(id_value)
		var recipe: Variant = (recipes as Dictionary).get(recipe_id, {})
		if recipe is Dictionary and _is_valid(recipe as Dictionary):
			var value := (recipe as Dictionary).duplicate(true)
			value["recipe_id"] = recipe_id
			_recipes[recipe_id] = value
			_order.append(recipe_id)

static func _is_valid(recipe: Dictionary) -> bool:
	var result: Variant = recipe.get("result", {})
	var ingredients: Variant = recipe.get("ingredients", [])
	return not str(recipe.get("display_name", "")).is_empty() and result is Dictionary and ingredients is Array \
		and not (ingredients as Array).is_empty() and float(recipe.get("duration_seconds", 0.0)) >= 10.0
