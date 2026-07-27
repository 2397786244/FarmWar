extends RefCounted
class_name ExtractorRecipeCatalog

const DEFINITIONS_PATH := "res://data/extractor_recipe_definitions.json"

static var _recipes: Dictionary = {}
static var _recipe_order: Array[String] = []
static var _loaded := false


static func get_recipe(recipe_id: String) -> Dictionary:
	_ensure_loaded()
	var recipe: Variant = _recipes.get(recipe_id, {})
	return (recipe as Dictionary).duplicate(true) if recipe is Dictionary else {}


static func get_recipes() -> Array[Dictionary]:
	_ensure_loaded()
	var recipes: Array[Dictionary] = []
	for recipe_id: String in _recipe_order:
		var recipe := get_recipe(recipe_id)
		if not recipe.is_empty():
			recipes.append(recipe)
	return recipes


static func get_display_name(recipe_id: String) -> String:
	var recipe := get_recipe(recipe_id)
	if recipe.is_empty():
		return ""
	var input_names: Array[String] = []
	for input: Dictionary in get_inputs(recipe_id):
		input_names.append(str(IngredientCatalog.get_definition(str(input.get("ingredient_id", ""))).get("display_name", "")))
	var output_name := str(IngredientCatalog.get_definition(str(recipe.get("output_ingredient_id", ""))).get("display_name", ""))
	return " + ".join(input_names) + " -> " + output_name


static func get_inputs(recipe_id: String) -> Array[Dictionary]:
	var recipe := get_recipe(recipe_id)
	var inputs_value: Variant = recipe.get("inputs", [])
	var inputs: Array[Dictionary] = []
	if inputs_value is Array:
		for input_value: Variant in inputs_value:
			if input_value is Dictionary:
				inputs.append((input_value as Dictionary).duplicate(true))
	return inputs


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(DEFINITIONS_PATH, FileAccess.READ)
	if file == null:
		push_error("Ingredient extractor recipes are missing: %s" % DEFINITIONS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Ingredient extractor recipes contain invalid JSON: %s" % DEFINITIONS_PATH)
		return
	var recipes_value: Variant = (parsed as Dictionary).get("recipes", {})
	if not recipes_value is Dictionary:
		return
	var configured_order: Variant = (parsed as Dictionary).get("recipe_order", [])
	var recipe_ids: Array = configured_order if configured_order is Array else (recipes_value as Dictionary).keys()
	for recipe_id_value: Variant in recipe_ids:
		if not (recipes_value as Dictionary).has(recipe_id_value):
			continue
		var recipe_value: Variant = (recipes_value as Dictionary)[recipe_id_value]
		if not recipe_value is Dictionary:
			continue
		var recipe := (recipe_value as Dictionary).duplicate(true)
		var inputs_value: Variant = recipe.get("inputs", [])
		var output_id := str(recipe.get("output_ingredient_id", ""))
		var output_weight := float(recipe.get("output_weight_kg", 0.0))
		var duration := float(recipe.get("duration_seconds", 0.0))
		if not inputs_value is Array or (inputs_value as Array).is_empty() or (inputs_value as Array).size() > 3 \
				or output_id.is_empty() or output_weight <= 0.0 or duration <= 0.0 \
				or IngredientCatalog.get_definition(output_id).is_empty():
			push_warning("Skipped invalid ingredient extractor recipe: %s" % str(recipe_id_value))
			continue
		var valid_inputs := true
		for input_value: Variant in inputs_value:
			if not input_value is Dictionary:
				valid_inputs = false
				break
			var input := input_value as Dictionary
			var input_id := str(input.get("ingredient_id", ""))
			if input_id.is_empty() or float(input.get("weight_kg", 0.0)) <= 0.0 \
					or IngredientCatalog.get_definition(input_id).is_empty():
				valid_inputs = false
				break
		if not valid_inputs:
			push_warning("Skipped invalid ingredient extractor recipe inputs: %s" % str(recipe_id_value))
			continue
		var pickup_unit := IngredientCatalog.get_pickup_unit_kg(output_id)
		if absf(output_weight / pickup_unit - roundf(output_weight / pickup_unit)) > 0.0001:
			push_warning("Ingredient extractor output must be a pickup-unit multiple: %s" % str(recipe_id_value))
			continue
		recipe["recipe_id"] = str(recipe_id_value)
		_recipes[str(recipe_id_value)] = recipe
		if not _recipe_order.has(str(recipe_id_value)):
			_recipe_order.append(str(recipe_id_value))
