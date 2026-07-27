extends RefCounted
class_name RecipeCatalog

const DEFINITIONS_PATH := "res://data/recipe_definitions.json"
const MAX_INGREDIENTS := 5

static var _recipes: Dictionary = {}
static var _recipe_order: Array[String] = []
static var _loaded := false


static func get_recipe(recipe_id: String) -> Dictionary:
	_ensure_loaded()
	var recipe: Variant = _recipes.get(recipe_id, {})
	return (recipe as Dictionary).duplicate(true) if recipe is Dictionary else {}


static func get_recipe_ids() -> Array[String]:
	_ensure_loaded()
	return _recipe_order.duplicate()


static func get_recipes() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for recipe_id: String in _recipe_order:
		var recipe := get_recipe(recipe_id)
		if not recipe.is_empty():
			result.append(recipe)
	return result


static func get_recipes_for_station(station_key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if station_key.is_empty():
		return result
	for recipe: Dictionary in get_recipes():
		var step_value: Variant = recipe.get("key_step", {})
		if step_value is Dictionary and str((step_value as Dictionary).get("station", "")) == station_key:
			result.append(recipe)
	return result


static func get_ingredients_per_batch(recipe_id: String) -> Array[Dictionary]:
	var recipe := get_recipe(recipe_id)
	var ingredient_values: Variant = recipe.get("ingredients", [])
	if not ingredient_values is Array:
		return []
	var result: Array[Dictionary] = []
	for entry_value: Variant in ingredient_values:
		if entry_value is Dictionary:
			result.append((entry_value as Dictionary).duplicate(true))
	return result


static func get_result(recipe_id: String, batch_count: int = 1) -> Dictionary:
	var recipe := get_recipe(recipe_id)
	var result_value: Variant = recipe.get("result", {})
	if not result_value is Dictionary:
		return {}
	var result := (result_value as Dictionary).duplicate(true)
	var normalized_batch_count := maxi(1, batch_count)
	result["quantity"] = int(result.get("quantity", 0)) * normalized_batch_count
	result["total_weight_kg"] = float(result.get("total_weight_kg", 0.0)) * float(normalized_batch_count)
	result["serving_weight_kg"] = float(result.get("total_weight_kg", 0.0)) / maxf(1.0, float(result.get("quantity", 0)))
	return result


static func get_required_ingredients(recipe_id: String, batch_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var normalized_batch_count := maxi(1, batch_count)
	for entry: Dictionary in get_ingredients_per_batch(recipe_id):
		var ingredient_id := str(entry.get("ingredient_id", ""))
		var weight_kg := float(entry.get("weight_kg", 0.0)) * float(normalized_batch_count)
		if ingredient_id.is_empty() or weight_kg <= 0.0:
			continue
		var ingredient_definition := IngredientCatalog.get_definition(ingredient_id)
		result.append({
			"ingredient_id": ingredient_id,
			"display_name": str(ingredient_definition.get("display_name", ingredient_id)),
			"weight_kg": weight_kg,
			"requires_chopping": bool(entry.get("is_chopped", false)),
		})
	return result


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_recipes.clear()
	_recipe_order.clear()
	var file := FileAccess.open(DEFINITIONS_PATH, FileAccess.READ)
	if file == null:
		push_error("Recipe catalog is missing: %s" % DEFINITIONS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Recipe catalog contains invalid JSON: %s" % DEFINITIONS_PATH)
		return
	var source := parsed as Dictionary
	var recipes_value: Variant = source.get("recipes", {})
	if not recipes_value is Dictionary:
		push_error("Recipe catalog field 'recipes' must be an object.")
		return
	for recipe_id_value: Variant in (recipes_value as Dictionary):
		var recipe_id := str(recipe_id_value)
		var recipe_value: Variant = (recipes_value as Dictionary)[recipe_id_value]
		if not recipe_value is Dictionary:
			push_warning("Skipped invalid recipe: %s" % recipe_id)
			continue
		var recipe := (recipe_value as Dictionary).duplicate(true)
		if _is_valid_recipe(recipe_id, recipe):
			recipe["recipe_id"] = recipe_id
			_recipes[recipe_id] = recipe
	var configured_order: Variant = source.get("recipe_order", [])
	if configured_order is Array:
		for recipe_id_value: Variant in configured_order:
			var recipe_id := str(recipe_id_value)
			if _recipes.has(recipe_id) and not _recipe_order.has(recipe_id):
				_recipe_order.append(recipe_id)
	for recipe_id: String in _recipes:
		if not _recipe_order.has(recipe_id):
			_recipe_order.append(recipe_id)


static func _is_valid_recipe(recipe_id: String, recipe: Dictionary) -> bool:
	if recipe_id.is_empty() or str(recipe.get("display_name", "")).is_empty():
		push_warning("Recipe is missing an id or display name: %s" % recipe_id)
		return false
	var result_value: Variant = recipe.get("result", {})
	if not result_value is Dictionary:
		push_warning("Recipe result must be an object: %s" % recipe_id)
		return false
	var recipe_result := result_value as Dictionary
	if str(recipe_result.get("dish_id", "")).is_empty() or \
		str(recipe_result.get("display_name", "")).is_empty() or \
		int(recipe_result.get("quantity", 0)) <= 0 or \
		float(recipe_result.get("total_weight_kg", 0.0)) <= 0.0 or \
		str(recipe_result.get("unit", "")) != "serving":
		push_warning("Recipe '%s' has an invalid serving result." % recipe_id)
		return false
	var ingredients_value: Variant = recipe.get("ingredients", [])
	if not ingredients_value is Array:
		push_warning("Recipe ingredients must be an array: %s" % recipe_id)
		return false
	var ingredients := ingredients_value as Array
	if ingredients.is_empty() or ingredients.size() > MAX_INGREDIENTS:
		push_warning("Recipe '%s' must contain 1-%d ingredients." % [recipe_id, MAX_INGREDIENTS])
		return false
	var used_ingredient_ids: Dictionary = {}
	for entry_value: Variant in ingredients:
		if not entry_value is Dictionary:
			push_warning("Recipe '%s' contains an invalid ingredient entry." % recipe_id)
			return false
		var entry := entry_value as Dictionary
		var ingredient_id := str(entry.get("ingredient_id", ""))
		var weight_kg := float(entry.get("weight_kg", 0.0))
		if ingredient_id.is_empty() or weight_kg <= 0.0 or used_ingredient_ids.has(ingredient_id):
			push_warning("Recipe '%s' contains an invalid or duplicate ingredient." % recipe_id)
			return false
		if IngredientCatalog.get_definition(ingredient_id).is_empty():
			push_warning("Recipe '%s' references an unknown ingredient: %s" % [recipe_id, ingredient_id])
			return false
		var chopping_value: Variant = entry.get("is_chopped", false)
		if not chopping_value is bool:
			push_warning("Recipe '%s' has a non-boolean chopping requirement: %s" % [recipe_id, ingredient_id])
			return false
		if bool(chopping_value) and IngredientCatalog.get_model_path(ingredient_id, "chopped_item").is_empty():
			push_warning("Recipe '%s' requires a chopped ingredient without a chopped model: %s" % [recipe_id, ingredient_id])
			return false
		used_ingredient_ids[ingredient_id] = true
	return true
