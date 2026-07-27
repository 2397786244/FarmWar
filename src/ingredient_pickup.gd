extends KitchenAppliance
class_name IngredientPickup

const MAX_SLOTS := RecipeCatalog.MAX_INGREDIENTS

var staged_order_id := -1
var staged_ingredients: Array[Dictionary] = []

@onready var pickup_ready_glow: Node3D = find_child("PickupReadyGlow", true, false) as Node3D

signal staged_changed


func _ready() -> void:
	add_to_group("ingredient_pickups")
	_update_pickup_ready_glow()


func get_latest_order_if_fundable(team: String) -> Dictionary:
	var task := EventBoard.get_latest_recipe_order(team)
	if task.is_empty():
		return {}
	var ingredients_value: Variant = task.get("required_ingredients", [])
	if not ingredients_value is Array or (ingredients_value as Array).size() > MAX_SLOTS:
		return {}
	for entry_value: Variant in ingredients_value:
		if not entry_value is Dictionary:
			return {}
		var entry := entry_value as Dictionary
		var ingredient_id := str(entry.get("ingredient_id", ""))
		var weight_kg := float(entry.get("weight_kg", 0.0))
		if ingredient_id.is_empty() or weight_kg <= 0.0 or GlobalVar.check_team_item_amount(team, ingredient_id) + 0.0001 < weight_kg:
			return {}
	return task


func reserve_latest_order_ingredients(team: String) -> bool:
	if GameAuthority.should_send_network_requests():
		return false
	if not staged_ingredients.is_empty():
		return false
	var task := get_latest_order_if_fundable(team)
	if task.is_empty():
		return false
	var ingredients: Array[Dictionary] = []
	for entry_value: Variant in task.get("required_ingredients", []):
		if entry_value is Dictionary:
			ingredients.append((entry_value as Dictionary).duplicate(true))
	for entry: Dictionary in ingredients:
		var ingredient_id := str(entry.get("ingredient_id", ""))
		var weight_kg := float(entry.get("weight_kg", 0.0))
		if not GlobalVar.remove_item(team, ingredient_id, weight_kg):
			for rollback: Dictionary in ingredients:
				if rollback == entry:
					break
				GlobalVar.add_item(team, str(rollback.get("ingredient_id", "")), float(rollback.get("weight_kg", 0.0)))
			return false
	staged_order_id = int(task.get("task_id", -1))
	staged_ingredients = ingredients.duplicate(true)
	staged_changed.emit()
	_update_pickup_ready_glow()
	return true


func get_staged_ingredients() -> Array[Dictionary]:
	return staged_ingredients.duplicate(true)


func take_ingredient_portion(slot_index: int) -> Dictionary:
	if GameAuthority.should_send_network_requests() or slot_index < 0 or slot_index >= staged_ingredients.size():
		return {}
	var entry := staged_ingredients[slot_index]
	var weight_kg := float(entry.get("weight_kg", 0.0))
	if weight_kg <= 0.0001:
		return {}
	var taken_weight := get_pickup_weight_kg(str(entry.get("ingredient_id", "")), weight_kg)
	if taken_weight <= 0.0001:
		return {}
	entry["weight_kg"] = maxf(0.0, weight_kg - taken_weight)
	staged_ingredients[slot_index] = entry
	staged_changed.emit()
	_update_pickup_ready_glow()
	var taken := entry.duplicate(true)
	taken["weight_kg"] = taken_weight
	return taken


func get_pickup_weight_kg(ingredient_id: String, remaining_weight_kg: float) -> float:
	if ingredient_id.is_empty() or remaining_weight_kg <= 0.0001:
		return 0.0
	return minf(IngredientCatalog.get_pickup_unit_kg(ingredient_id), remaining_weight_kg)


func get_staged_state() -> Dictionary:
	var state := {
		"station_path": str(get_path()),
		"station_position": global_position,
		"staged_order_id": staged_order_id,
		"staged_ingredients": get_staged_ingredients(),
	}
	state.merge(get_user_lock_state(), true)
	return state


func apply_authoritative_staged_state(state: Dictionary) -> void:
	apply_user_lock_state(state)
	staged_order_id = int(state.get("staged_order_id", -1))
	var values: Variant = state.get("staged_ingredients", [])
	staged_ingredients.clear()
	if values is Array:
		for value: Variant in values:
			if value is Dictionary:
				staged_ingredients.append((value as Dictionary).duplicate(true))
	staged_changed.emit()
	_update_pickup_ready_glow()


func _update_pickup_ready_glow() -> void:
	if not is_instance_valid(pickup_ready_glow):
		return
	pickup_ready_glow.visible = has_reserved_ingredients()


func has_reserved_ingredients() -> bool:
	for entry: Dictionary in staged_ingredients:
		if float(entry.get("weight_kg", 0.0)) > 0.0:
			return true
	return false
