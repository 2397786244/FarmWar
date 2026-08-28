extends RefCounted
class_name IndustrialRecipeCatalog

const DEFINITIONS_PATH := "res://data/industrial_recipe_definitions.json"

static var _recipes: Dictionary = {}
static var _recipe_order: Array[String] = []
static var _loaded := false


static func get_recipe(recipe_id: String) -> Dictionary:
	_ensure_loaded()
	var value: Variant = _recipes.get(recipe_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func get_recipes() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for recipe_id in _recipe_order:
		var recipe := get_recipe(recipe_id)
		if not recipe.is_empty():
			result.append(recipe)
	return result


static func get_recipes_for_workbench(next_workbench_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe in get_recipes():
		if str(recipe.get("workbench_id", "")) == next_workbench_id:
			result.append(recipe)
	return result


static func get_inputs(recipe_id: String) -> Array[Dictionary]:
	var recipe := get_recipe(recipe_id)
	var value: Variant = recipe.get("inputs", [])
	var result: Array[Dictionary] = []
	if value is Array:
		for input_value in value:
			if input_value is Dictionary:
				result.append((input_value as Dictionary).duplicate(true))
	return result


static func get_output(recipe_id: String) -> Dictionary:
	var recipe := get_recipe(recipe_id)
	var value: Variant = recipe.get("output", {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func get_display_name(recipe_id: String) -> String:
	return str(get_recipe(recipe_id).get("display_name", recipe_id))


static func get_workbench_id(recipe_id: String) -> String:
	return str(get_recipe(recipe_id).get("workbench_id", ""))


static func get_tech_tier(recipe_id: String) -> int:
	return clampi(int(get_recipe(recipe_id).get("tech_tier", 1)), 1, 5)


static func get_complexity(recipe_id: String) -> int:
	var recipe := get_recipe(recipe_id)
	var explicit := int(recipe.get("complexity", 0))
	if explicit > 0:
		return clampi(explicit, 1, 5)
	var inputs: Array[Dictionary] = get_inputs(recipe_id)
	return clampi(inputs.size() + (1 if str(get_output(recipe_id).get("kind", "")) != "ingredient" else 0), 1, 5)


static func get_duration_seconds(recipe_id: String) -> float:
	var inputs := get_inputs(recipe_id)
	var duration := 8.0 \
		+ 8.0 * float(get_tech_tier(recipe_id) - 1) \
		+ 5.0 * float(get_complexity(recipe_id) - 1) \
		+ 2.0 * float(maxi(0, inputs.size() - 1))
	return clampf(duration, 8.0, 90.0)


static func get_authority_inputs(recipe_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for input in get_inputs(recipe_id):
		var ingredient_id := str(input.get("id", input.get("ingredient_id", "")))
		var amount := maxf(0.0, float(input.get("amount", input.get("weight_kg", 0.0))))
		var unit := str(input.get("unit", "kg"))
		var pickup_unit := IngredientCatalog.get_pickup_unit_kg(ingredient_id)
		var personal_weight := amount if unit == "kg" else amount * pickup_unit
		result.append({
			"ingredient_id": ingredient_id,
			"weight_kg": personal_weight,
			"personal_weight_kg": personal_weight,
			"team_amount": amount,
			"unit": unit,
			"is_chopped": false,
		})
	return result


static func make_output_result(recipe_id: String) -> Dictionary:
	var output := get_output(recipe_id)
	if output.is_empty():
		return {}
	var output_id := str(output.get("id", output.get("item_id", "")))
	var amount := maxf(0.0, float(output.get("amount", 0.0)))
	var unit := str(output.get("unit", "item"))
	var kind := str(output.get("kind", "ingredient"))
	var result := output.duplicate(true)
	result["id"] = output_id
	result["amount"] = amount
	result["unit"] = unit
	result["kind"] = kind
	result["recipe_id"] = recipe_id
	result["display_name"] = get_output_display_name(kind, output_id)
	result["duration_seconds"] = get_duration_seconds(recipe_id)
	result["weight_kg"] = amount if unit == "kg" else amount * IngredientCatalog.get_pickup_unit_kg(output_id)
	return result


static func get_output_display_name(kind: String, output_id: String) -> String:
	match kind:
		"equipment":
			return str(EquipmentCatalog.get_definition(output_id).get("name", output_id))
		"tool":
			var definition := _get_runtime_tool_definition(output_id)
			return str(definition.get("name", output_id))
		_:
			return str(IngredientCatalog.get_definition(output_id).get("display_name", output_id))


static func format_quantity(amount: float, unit: String) -> String:
	if unit == "kg":
		return "%.2f kg" % amount
	return "%d 个" % roundi(amount)


static func validate_catalog() -> Dictionary:
	var errors: Array[String] = []
	var recipes := get_recipes()
	if recipes.size() != 45:
		errors.append("expected 45 recipes, got %d" % recipes.size())
	for recipe in recipes:
		var recipe_id := str(recipe.get("recipe_id", ""))
		if recipe_id.is_empty():
			errors.append("recipe without id")
		if str(recipe.get("workbench_id", "")) == "robot_assembly_pod":
			errors.append("robot recipe is not allowed: %s" % recipe_id)
		for input in get_inputs(recipe_id):
			var ingredient_id := str(input.get("id", ""))
			if IngredientCatalog.get_definition(ingredient_id).is_empty():
				errors.append("unknown input %s in %s" % [ingredient_id, recipe_id])
		var output := get_output(recipe_id)
		var output_id := str(output.get("id", ""))
		match str(output.get("kind", "ingredient")):
			"ingredient":
				if IngredientCatalog.get_definition(output_id).is_empty():
					errors.append("unknown ingredient output %s in %s" % [output_id, recipe_id])
			"equipment":
				if EquipmentCatalog.get_definition(output_id).is_empty():
					errors.append("unknown equipment output %s in %s" % [output_id, recipe_id])
			"tool":
				if _get_runtime_tool_definition(output_id).is_empty():
					errors.append("unknown tool output %s in %s" % [output_id, recipe_id])
			_:
				errors.append("unsupported output kind in %s" % recipe_id)
		if get_duration_seconds(recipe_id) < 8.0 or get_duration_seconds(recipe_id) > 90.0:
			errors.append("duration outside range in %s" % recipe_id)
	return {"ok": errors.is_empty(), "errors": errors, "recipe_count": recipes.size()}


static func _get_runtime_tool_definition(tool_id: String) -> Dictionary:
	var file := FileAccess.open("res://data/tool_definitions.json", FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {}
	var tools: Variant = (parsed as Dictionary).get("tools", [])
	if not tools is Array:
		return {}
	for value in tools:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == tool_id:
			return (value as Dictionary).duplicate(true)
	return {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(DEFINITIONS_PATH, FileAccess.READ)
	if file == null:
		push_error("Industrial recipe catalog is missing: %s" % DEFINITIONS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Industrial recipe catalog contains invalid JSON: %s" % DEFINITIONS_PATH)
		return
	var root := parsed as Dictionary
	var order_value: Variant = root.get("recipe_order", [])
	if order_value is Array:
		for value in order_value:
			_recipe_order.append(str(value))
	var recipes_value: Variant = root.get("recipes", [])
	if recipes_value is Array:
		for value in recipes_value:
			if not value is Dictionary:
				continue
			var recipe := value as Dictionary
			var recipe_id := str(recipe.get("recipe_id", ""))
			if recipe_id.is_empty():
				continue
			_recipes[recipe_id] = recipe.duplicate(true)
			if not _recipe_order.has(recipe_id):
				_recipe_order.append(recipe_id)
