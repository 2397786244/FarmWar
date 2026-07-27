extends SceneTree


func _init() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	var map_scene := load("res://worlds/creston_town.tscn") as PackedScene
	assert(map_scene != null)
	var map := map_scene.instantiate()
	root.add_child(map)
	current_scene = map
	for _frame in range(4):
		await process_frame
	var registry: Node = root.get_node("MapBuildingRegistry")
	registry.rescan_current_map()
	var cooked: Array = registry.get_delivery_locations("", "Cooked Dish Delivery")
	var farm: Array = registry.get_delivery_locations("", "Farm Produce Delivery")
	var materials: Array = registry.get_delivery_locations("", "Material Collection")
	assert(not _has_location(cooked, "creston_bar"))
	assert(_has_location(farm, "creston_bar"))
	assert(not _has_location(materials, "creston_bar"))
	assert(_has_location(cooked, "roadside_diner"))
	assert(_has_location(farm, "roadside_diner"))
	assert(not _has_location(materials, "roadside_diner"))
	for warehouse_id in ["red_warehouse", "blue_warehouse"]:
		assert(_has_location(cooked, warehouse_id))
		assert(_has_location(farm, warehouse_id))
		assert(_has_location(materials, warehouse_id))
	var areas := get_nodes_in_group("task_delivery_areas")
	assert(areas.size() == 4)
	for area_value: Variant in areas:
		var area := area_value as Area3D
		assert(area.collision_layer == 512)
		assert(area.collision_mask == 8200)
		assert(area.get_parent().find_child("CargoAreaOutline", true, false) != null)
	var authority: Node = root.get_node("GameAuthority")
	var player_states := authority.get("player_states") as Dictionary
	var physics_nodes := authority.get("player_physics_nodes") as Dictionary
	player_states[901] = {"team": "red"}
	var player_proxy := CharacterBody3D.new()
	map.add_child(player_proxy)
	physics_nodes[901] = player_proxy
	var red_car: Node = map.get_node("RedCargoCar")
	red_car.driver_peer_id = 901
	var bar: Node = map.get_node("Bar")
	var roadside_diner: Node = map.get_node("RoadsideDiner")
	var red_warehouse: Node = map.get_node("WarehouseRed")
	var blue_warehouse: Node = map.get_node("WarehouseBlue")
	assert(bar.is_valid_delivery_body(player_proxy))
	assert(bar.is_valid_delivery_body(red_car))
	assert(roadside_diner.is_valid_delivery_body(player_proxy))
	assert(roadside_diner.is_valid_delivery_body(red_car))
	assert(red_warehouse.is_valid_delivery_body(player_proxy))
	assert(red_warehouse.is_valid_delivery_body(red_car))
	assert(not blue_warehouse.is_valid_delivery_body(player_proxy))
	assert(not blue_warehouse.is_valid_delivery_body(red_car))
	var emitter: Node = root.get_node("FoodOrderEmitter")
	for _sample in range(100):
		var red_cooked: Dictionary = emitter._choose_delivery_location(
			"red", "Cooked Dish Delivery", false
		)
		assert(str(red_cooked.get("id", "")) != "creston_bar")
		assert(str(red_cooked.get("id", "")) != "blue_warehouse")
		var blue_farm: Dictionary = emitter._choose_delivery_location(
			"blue", "Farm Produce Delivery", false
		)
		assert(str(blue_farm.get("id", "")) != "red_warehouse")
	var invalid_bar_override: Dictionary = emitter._delivery_metadata(
		"Cooked Dish Delivery", "simple", {"delivery_location": "creston_bar"}, "red", false
	)
	assert(str(invalid_bar_override.get("delivery_location_id", "")) != "creston_bar")
	var valid_bar_override: Dictionary = emitter._delivery_metadata(
		"Farm Produce Delivery", "simple", {"delivery_location": "creston_bar"}, "red", false
	)
	assert(str(valid_bar_override.get("delivery_location_id", "")) == "creston_bar")
	var event_board: Node = root.get_node("EventBoard")
	event_board.reset()
	var shared_id := "bar_validation"
	var bar_location: Dictionary = emitter._get_bar_delivery_location()
	var created: Array = emitter.emit_random_delivery_task("all", "Farm Produce Delivery", "simple", {
		"is_timed": true,
		"time_limit_seconds": 360.0,
		"delivery_location": bar_location,
		"managed_delivery_chain": true,
		"allowed_ingredient_ids": ["grape", "kiwi", "strawberry", "watermelon", "potato"],
		"order_profile": "bar_produce",
		"shared_task_id": shared_id,
		"all_team_task": true,
		"first_completion_bonus_rate": 0.2,
	})
	assert(created.size() == 2)
	var red_task: Dictionary = event_board.get_team_tasks("red")[0]
	var blue_task: Dictionary = event_board.get_team_tasks("blue")[0]
	assert(str(red_task.get("shared_task_id", "")) == shared_id)
	assert(str(blue_task.get("shared_task_id", "")) == shared_id)
	assert(float(red_task.get("time_limit_seconds", 0.0)) == 360.0)
	assert(str(red_task.get("delivery_location_id", "")) == "creston_bar")
	var requirement: Dictionary = (red_task.get("delivery_items", []) as Array)[0]
	assert(["grape", "kiwi", "strawberry", "watermelon", "potato"].has(str(requirement.get("ingredient_id", ""))))
	var base_reward := int((red_task.get("rewards", {}) as Dictionary).get("money", 0))
	assert(base_reward >= 1000 and base_reward <= 6000)
	var delivered := {str(requirement.get("ingredient_id", "")): float(requirement.get("weight_kg", 0.0))}
	var red_result: Dictionary = emitter.apply_cargo_delivery_progress("red", int(red_task.get("task_id", 0)), delivered)
	assert(int(red_result.get("reward_money", 0)) == roundi(float(base_reward) * 1.2))
	blue_task = event_board.get_team_tasks("blue")[0]
	assert(bool(blue_task.get("active", false)))
	assert((blue_task.get("delivery_progress", {}) as Dictionary).is_empty())
	var blue_result: Dictionary = emitter.apply_cargo_delivery_progress("blue", int(blue_task.get("task_id", 0)), delivered)
	assert(int(blue_result.get("reward_money", 0)) == base_reward)
	print(
		"Cargo delivery validation: %d areas; destinations, CargoArea entrants, and shared Bar rewards valid."
		% areas.size()
	)
	quit()


func _has_location(locations: Array, location_id: String) -> bool:
	for value: Variant in locations:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == location_id:
			return true
	return false
