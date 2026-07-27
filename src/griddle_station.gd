extends RecipeCookingStation
class_name GriddleStation

@onready var meat_griddle_food: Node3D = find_child("MeatGriddleFood", true, false) as Node3D
@onready var vegetable_griddle_food: Node3D = find_child("VegetableGriddleFood", true, false) as Node3D
@onready var cooking_smoke: GPUParticles3D = find_child("CookingSmoke", true, false) as GPUParticles3D

func get_station_group_name() -> String:
	return "griddle_stations"

func get_state_event_type() -> String:
	return "griddle_station_state"

func get_recipe_station_key() -> String:
	return "griddle_station"

func get_station_display_name() -> String:
	return "煎台"

func get_cooking_verb() -> String:
	return "煎制"

func _refresh_station_visual() -> void:
	super._refresh_station_visual()
	# Keep the cooked food on the griddle until the output is collected.
	var has_food_on_griddle := cooking or complete
	var use_meat_visual := has_food_on_griddle and _recipe_has_meat(recipe_id)
	if is_instance_valid(meat_griddle_food):
		meat_griddle_food.visible = use_meat_visual
	if is_instance_valid(vegetable_griddle_food):
		vegetable_griddle_food.visible = has_food_on_griddle and not use_meat_visual
	if is_instance_valid(cooking_smoke):
		cooking_smoke.emitting = cooking

func _recipe_has_meat(next_recipe_id: String) -> bool:
	for ingredient: Dictionary in RecipeCatalog.get_ingredients_per_batch(next_recipe_id):
		if str(IngredientCatalog.get_definition(str(ingredient.get("ingredient_id", ""))).get("category", "")) == "meat":
			return true
	return false
