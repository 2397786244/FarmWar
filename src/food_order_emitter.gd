extends Node
class_name FoodOrderEmitterService

signal delivery_destination_entered(event: Dictionary)

const COOKED_DISH_DELIVERY := "Cooked Dish Delivery"
const FARM_PRODUCE_DELIVERY := "Farm Produce Delivery"
const MATERIAL_COLLECTION := "Material Collection"
const BAR_PRODUCE_DELIVERY := "Bar Produce Delivery"
const DINER_DISH_DELIVERY := "Roadside Diner Cooked Dish Delivery"
const DINER_PRODUCE_DELIVERY := "Roadside Diner Farm Produce Delivery"
const BAR_PRODUCE_IDS := ["grape", "kiwi", "strawberry", "watermelon", "potato"]
const DELIVERY_TASK_TYPE := "delivery_order"
const DELIVERY_CHAIN_DURATION_SECONDS := 360.0
const DELIVERY_BASE_DURATION_SECONDS := 360.0
const DELIVERY_MAX_DURATION_SECONDS := 1200.0
const DELIVERY_MAX_WORKLOAD_TIME_FACTOR := 1.5
const DELIVERY_RESULT_DISPLAY_SECONDS := 30.0
const DELIVERY_NEXT_TASK_DELAY_SECONDS := 60.0
const INITIAL_RESOURCE_TASK_PHASE_SECONDS := 360.0
const DEFAULT_MATCH_DURATION_SECONDS := 48.0 * 60.0
const MID_GAME_PROGRESS := 0.3
const LATE_GAME_PROGRESS := 0.6
const DELIVERY_CHAIN_CATEGORIES := [
	COOKED_DISH_DELIVERY,
	FARM_PRODUCE_DELIVERY,
	MATERIAL_COLLECTION,
	BAR_PRODUCE_DELIVERY,
	DINER_DISH_DELIVERY,
	DINER_PRODUCE_DELIVERY,
]
const TIMED_TASK_CHANCE := 0.5
const TIMED_TASK_MIN_SECONDS := 180.0
const TIMED_TASK_MAX_SECONDS := 420.0
const FARM_BASE_PRODUCTS := {
	"oil": true,
	"sugar": true,
	"yeast": true,
	"wheat_flour": true,
	"yeast_dough": true,
	"puff_pastry_dough": true,
	"chicken": true,
	"pork": true,
	"beef": true,
}

var _cooked_dish_inventory: Array[Dictionary] = []
var _farm_produce_inventory: Array[Dictionary] = []
var _material_collection_inventory: Array[Dictionary] = []
var _inventory_ready := false
var _rng := RandomNumberGenerator.new()
var _chain_update_accumulator := 0.0
var _local_match_elapsed_seconds := 0.0
var _tracked_authority_mode := ""
var runtime_enabled := true


func set_runtime_enabled(enabled: bool) -> void:
	runtime_enabled = enabled
	_chain_update_accumulator = 0.0
	_local_match_elapsed_seconds = 0.0


func is_runtime_enabled() -> bool:
	return runtime_enabled


func _ready() -> void:
	_rng.randomize()
	_rebuild_delivery_inventory()
	if not MapBuildingRegistry.buildings_changed.is_connected(_on_buildings_changed):
		MapBuildingRegistry.buildings_changed.connect(_on_buildings_changed)
	call_deferred("ensure_delivery_task_chains")


func _process(delta: float) -> void:
	if not runtime_enabled or GameAuthority.is_client_proxy():
		return
	_track_local_match_elapsed(delta)
	_chain_update_accumulator += delta
	if _chain_update_accumulator < 0.5:
		return
	_chain_update_accumulator = 0.0
	ensure_delivery_task_chains()


func _on_buildings_changed(_buildings: Array[Dictionary]) -> void:
	if runtime_enabled and not GameAuthority.is_client_proxy():
		call_deferred("ensure_delivery_task_chains")


func ensure_delivery_task_chains() -> void:
	if not runtime_enabled or GameAuthority.is_client_proxy():
		return
	var warehouses := {}
	var now_msec := _unix_msec()
	for team: String in EventBoard.VALID_TEAMS:
		var warehouse := _get_team_warehouse(team)
		if warehouse.is_empty():
			return
		warehouses[team] = warehouse
		var active_task := _get_active_delivery_task(team)
		if not active_task.is_empty() and _is_task_expired(active_task):
			_finalize_delivery_task(team, active_task, false, true)
	# Every team's previous task must finish its full 60-second result/wait
	# interval before the synchronized delivery chain advances.
	var ready_for_next_task := true
	for team: String in EventBoard.VALID_TEAMS:
		if not _get_active_delivery_task(team).is_empty():
			ready_for_next_task = false
			continue
		var previous_task := _get_latest_managed_delivery_task(team)
		if previous_task.is_empty():
			continue
		var ended_msec := int(previous_task.get("ended_unix_msec", 0))
		if ended_msec <= 0:
			# Backward compatibility for tasks ended before result intervals existed.
			continue
		var elapsed_seconds := maxf(0.0, float(now_msec - ended_msec) / 1000.0)
		if bool(previous_task.get("summary_visible", false)) \
				and elapsed_seconds >= DELIVERY_RESULT_DISPLAY_SECONDS:
			EventBoard.update_team_task(team, int(previous_task.get("task_id", 0)), {
				"summary_visible": false,
				"summary_cleared_unix_msec": now_msec,
			})
		if elapsed_seconds < DELIVERY_NEXT_TASK_DELAY_SECONDS:
			ready_for_next_task = false
	if not ready_for_next_task:
		return
	var route_pool: Array = DELIVERY_CHAIN_CATEGORIES
	if _get_match_elapsed_seconds() < INITIAL_RESOURCE_TASK_PHASE_SECONDS:
		route_pool = [FARM_PRODUCE_DELIVERY, MATERIAL_COLLECTION]
	var route: String = str(route_pool[_rng.randi_range(0, route_pool.size() - 1)])
	var category := route
	var competitive_location: Dictionary = {}
	var order_profile := ""
	match route:
		BAR_PRODUCE_DELIVERY:
			category = FARM_PRODUCE_DELIVERY
			competitive_location = _get_bar_delivery_location()
			order_profile = "bar_produce"
		DINER_DISH_DELIVERY:
			category = COOKED_DISH_DELIVERY
			competitive_location = _get_roadside_diner_delivery_location(category)
			order_profile = "roadside_diner_dish"
		DINER_PRODUCE_DELIVERY:
			category = FARM_PRODUCE_DELIVERY
			competitive_location = _get_roadside_diner_delivery_location(category)
			order_profile = "roadside_diner_produce"
	if not order_profile.is_empty() and not competitive_location.is_empty():
		var shared_id := "%s_%d" % [order_profile, _unix_msec()]
		var competitive_metadata := {
			"is_timed": true,
			"time_limit_seconds": DELIVERY_CHAIN_DURATION_SECONDS,
			"delivery_location": competitive_location,
			"managed_delivery_chain": true,
			"order_profile": order_profile,
			"shared_task_id": shared_id,
			"all_team_task": true,
			"first_completion_bonus_rate": 0.2,
		}
		if order_profile == "bar_produce":
			competitive_metadata["allowed_ingredient_ids"] = BAR_PRODUCE_IDS
		emit_random_delivery_task(
			EventBoard.TEAM_ALL,
			category,
			"hard" if category == COOKED_DISH_DELIVERY and _rng.randf() < 0.4 else "simple",
			competitive_metadata
		)
		return
	for team: String in EventBoard.VALID_TEAMS:
		var metadata := {
			"is_timed": true,
			"time_limit_seconds": DELIVERY_CHAIN_DURATION_SECONDS,
			"delivery_location": warehouses[team],
			"managed_delivery_chain": true,
		}
		if category == MATERIAL_COLLECTION:
			metadata["material_group"] = "ore" if _rng.randf() < 0.5 else "wood"
		emit_random_delivery_task(
			team, category,
			"hard" if category == COOKED_DISH_DELIVERY and _rng.randf() < 0.4 else "simple",
			metadata
		)


func _get_active_delivery_task(team: String) -> Dictionary:
	for task: Dictionary in EventBoard.get_team_tasks(team):
		if str(task.get("task_type", "")) == DELIVERY_TASK_TYPE \
				and bool(task.get("active", true)):
			return task
	return {}


func _get_latest_managed_delivery_task(team: String) -> Dictionary:
	for task: Dictionary in EventBoard.get_team_tasks(team):
		if str(task.get("task_type", "")) == DELIVERY_TASK_TYPE \
				and bool(task.get("managed_delivery_chain", false)):
			return task
	return {}


func _is_task_expired(task: Dictionary) -> bool:
	if not bool(task.get("is_timed", false)):
		return false
	return int(task.get("deadline_unix_msec", 0)) > 0 \
		and _unix_msec() >= int(task.get("deadline_unix_msec", 0))


func _get_team_warehouse(team: String) -> Dictionary:
	for location: Dictionary in MapBuildingRegistry.get_delivery_locations("warehouse"):
		if str(location.get("team", "")) == team:
			return location.duplicate(true)
	return {}


func _get_bar_delivery_location() -> Dictionary:
	for location: Dictionary in MapBuildingRegistry.get_delivery_locations("", FARM_PRODUCE_DELIVERY):
		if str(location.get("id", "")) == "creston_bar" \
				or str(location.get("building_type", "")) == "bar":
			return location.duplicate(true)
	return {}


func _get_roadside_diner_delivery_location(category: String) -> Dictionary:
	for location: Dictionary in MapBuildingRegistry.get_delivery_locations("", category):
		if str(location.get("id", "")) == "roadside_diner" \
				or str(location.get("building_type", "")) == "roadside_diner":
			return location.duplicate(true)
	return {}


func _track_local_match_elapsed(delta: float) -> void:
	var mode_name := str(GameAuthority.mode)
	if mode_name != _tracked_authority_mode:
		_tracked_authority_mode = mode_name
		_local_match_elapsed_seconds = 0.0
	if GameAuthority.is_local_authority():
		_local_match_elapsed_seconds += maxf(0.0, delta)


func _get_match_elapsed_seconds() -> float:
	var manager: Node = GameAuthority.server_manager
	if is_instance_valid(manager) and manager.has_method("get_match_elapsed_seconds"):
		return maxf(0.0, float(manager.call("get_match_elapsed_seconds")))
	return _local_match_elapsed_seconds


func _get_match_duration_seconds() -> float:
	var manager: Node = GameAuthority.server_manager
	if is_instance_valid(manager) and manager.has_method("get_match_duration_seconds"):
		return maxf(60.0, float(manager.call("get_match_duration_seconds")))
	return DEFAULT_MATCH_DURATION_SECONDS


func _get_current_requirement_multiplier() -> int:
	var duration := _get_match_duration_seconds()
	var progress := clampf(_get_match_elapsed_seconds() / maxf(1.0, duration), 0.0, 1.0)
	if progress >= LATE_GAME_PROGRESS:
		return 3
	if progress >= MID_GAME_PROGRESS:
		return 2
	return 1


func _unix_msec() -> int:
	return roundi(Time.get_unix_time_from_system() * 1000.0)


func _rebuild_delivery_inventory() -> void:
	_cooked_dish_inventory.clear()
	_farm_produce_inventory.clear()
	_material_collection_inventory = [
		{"material_id": "iron", "display_name": "铁矿", "material_group": "ore", "unit": "count", "rarity": "uncommon", "reward_weight": 1.25, "min_quantity": 1, "max_quantity": 3},
		{"material_id": "copper", "display_name": "铜矿", "material_group": "ore", "unit": "count", "rarity": "rare", "reward_weight": 1.6, "min_quantity": 1, "max_quantity": 3},
		{"material_id": "coal", "display_name": "煤矿", "material_group": "ore", "unit": "count", "rarity": "common", "reward_weight": 1.0, "min_quantity": 1, "max_quantity": 3},
		{"material_id": "limestone", "display_name": "石灰石", "material_group": "ore", "unit": "count", "rarity": "common", "reward_weight": 1.0, "min_quantity": 1, "max_quantity": 3},
		{"material_id": "oak_log", "display_name": "橡木材", "material_group": "wood", "unit": "count"},
		{"material_id": "pine_log", "display_name": "松木材", "material_group": "wood", "unit": "count"},
		{"material_id": "birch_log", "display_name": "桦木材", "material_group": "wood", "unit": "count"},
		{"material_id": "hardwood", "display_name": "硬木材", "material_group": "wood", "unit": "count"},
	]
	for recipe_id: String in RecipeCatalog.get_recipe_ids():
		var recipe := RecipeCatalog.get_recipe(recipe_id)
		var result := RecipeCatalog.get_result(recipe_id)
		var base_quantity := int(result.get("quantity", 0))
		if recipe.is_empty() or base_quantity <= 0:
			continue
		var ingredient_count := _get_recipe_ingredient_type_count(recipe_id)
		_cooked_dish_inventory.append({
			"recipe_id": recipe_id,
			"dish_id": str(result.get("dish_id", "")),
			"display_name": str(result.get("display_name", recipe.get("display_name", recipe_id))),
			"base_quantity": base_quantity,
			"serving_weight_kg": float(result.get("serving_weight_kg", 0.0)),
			"ingredient_count": ingredient_count,
			"reward_weight": _get_dish_reward_weight(ingredient_count),
		})
	for ingredient_id: String in _all_farm_delivery_ids():
		var definition := IngredientCatalog.get_definition(ingredient_id)
		var unit := IngredientCatalog.get_pickup_unit_kg(ingredient_id)
		if definition.is_empty() or unit <= 0.0:
			continue
		_farm_produce_inventory.append({
			"ingredient_id": ingredient_id,
			"display_name": str(definition.get("display_name", ingredient_id)),
			"pickup_unit_kg": unit,
		})
	_inventory_ready = true


func get_delivery_task_inventory(category := "") -> Array[Dictionary]:
	if not _inventory_ready:
		_rebuild_delivery_inventory()
	if category == COOKED_DISH_DELIVERY:
		return _cooked_dish_inventory.duplicate(true)
	if category == FARM_PRODUCE_DELIVERY:
		return _farm_produce_inventory.duplicate(true)
	if category == MATERIAL_COLLECTION:
		return _material_collection_inventory.duplicate(true)
	var result: Array[Dictionary] = []
	result.append_array(_cooked_dish_inventory)
	result.append_array(_farm_produce_inventory)
	result.append_array(_material_collection_inventory)
	return result.duplicate(true)


func get_cooked_dish_delivery_inventory() -> Array[Dictionary]:
	return get_delivery_task_inventory(COOKED_DISH_DELIVERY)


func get_farm_produce_delivery_inventory() -> Array[Dictionary]:
	return get_delivery_task_inventory(FARM_PRODUCE_DELIVERY)


func get_material_collection_inventory() -> Array[Dictionary]:
	return get_delivery_task_inventory(MATERIAL_COLLECTION)


func emit_random_delivery_task(target_team: String, category: String, difficulty := "simple", metadata := {}) -> Array[Dictionary]:
	if not runtime_enabled or GameAuthority.is_client_proxy():
		return []
	if not _inventory_ready:
		_rebuild_delivery_inventory()
	if category == COOKED_DISH_DELIVERY:
		return _emit_random_dish_delivery(target_team, difficulty, metadata if metadata is Dictionary else {})
	if category == FARM_PRODUCE_DELIVERY:
		return _emit_random_farm_delivery(target_team, metadata if metadata is Dictionary else {})
	if category == MATERIAL_COLLECTION:
		return _emit_random_material_collection(target_team, metadata if metadata is Dictionary else {})
	return []


func emit_cooked_dish_delivery(target_team: String, difficulty := "simple", metadata := {}) -> Array[Dictionary]:
	return emit_random_delivery_task(target_team, COOKED_DISH_DELIVERY, difficulty, metadata)


func emit_farm_produce_delivery(target_team: String, metadata := {}) -> Array[Dictionary]:
	return emit_random_delivery_task(target_team, FARM_PRODUCE_DELIVERY, "simple", metadata)


func emit_material_collection(target_team: String, metadata := {}) -> Array[Dictionary]:
	return emit_random_delivery_task(target_team, MATERIAL_COLLECTION, "simple", metadata)


func _emit_random_dish_delivery(target_team: String, difficulty: String, metadata: Dictionary) -> Array[Dictionary]:
	if _cooked_dish_inventory.is_empty():
		return []
	var count := 1 if difficulty.to_lower() == "simple" else _rng.randi_range(2, mini(3, _cooked_dish_inventory.size()))
	var candidates := _cooked_dish_inventory.duplicate(true)
	candidates.shuffle()
	var items: Array[Dictionary] = []
	for index in range(count):
		var template: Dictionary = candidates[index]
		var multiplier := _get_current_requirement_multiplier()
		var quantity := multiplier * int(template.get("base_quantity", 1))
		items.append({
			"dish_id": str(template.get("dish_id", "")),
			"recipe_id": str(template.get("recipe_id", "")),
			"display_name": str(template.get("display_name", "")),
			"quantity": quantity,
			"base_quantity": int(template.get("base_quantity", 1)),
			"multiplier": multiplier,
			"weight_kg": float(template.get("serving_weight_kg", 0.0)) * float(quantity),
			"ingredient_count": int(template.get("ingredient_count", 0)),
			"reward_weight": float(template.get("reward_weight", 1.0)),
		})
	var task := _delivery_metadata(COOKED_DISH_DELIVERY, "simple" if count == 1 else "hard", metadata, target_team)
	var roadside_diner_order := str(metadata.get("order_profile", "")) == "roadside_diner_dish"
	task.merge({
		"task_type": DELIVERY_TASK_TYPE,
		"delivery_category": COOKED_DISH_DELIVERY,
		"difficulty": "simple" if count == 1 else "hard",
		"title": "公路餐厅成品菜需求" if roadside_diner_order else "成品菜配送订单",
		"description": "将指定成品菜送到公路餐厅。" if roadside_diner_order else "交付指定数量的成品菜。",
		"delivery_items": items,
		"active": true,
	}, true)
	_apply_scaled_delivery_duration(task, items, COOKED_DISH_DELIVERY)
	task["rewards"] = _build_delivery_rewards(items, COOKED_DISH_DELIVERY, task)
	return EventBoard.add_team_task(target_team, task)


func _emit_random_farm_delivery(target_team: String, metadata: Dictionary) -> Array[Dictionary]:
	if _farm_produce_inventory.is_empty():
		return []
	var candidates := _farm_produce_inventory.duplicate(true)
	var allowed_value: Variant = metadata.get("allowed_ingredient_ids", [])
	if allowed_value is Array and not (allowed_value as Array).is_empty():
		var allowed: Array = allowed_value as Array
		candidates = candidates.filter(func(entry: Dictionary) -> bool:
			return allowed.has(str(entry.get("ingredient_id", "")))
		)
	if candidates.is_empty():
		return []
	var template: Dictionary = candidates[_rng.randi_range(0, candidates.size() - 1)]
	var multiplier := _get_current_requirement_multiplier()
	var unit := float(template.get("pickup_unit_kg", 0.01))
	var required_weight := unit * float(multiplier)
	var task := _delivery_metadata(FARM_PRODUCE_DELIVERY, "simple", metadata, target_team)
	var order_profile := str(metadata.get("order_profile", ""))
	var task_title := "农产品原料配送订单"
	var task_description := "交付大量农产品或基础加工原料。"
	if order_profile == "bar_produce":
		task_title = "酒吧鲜食需求"
		task_description = "将酒吧需要的新鲜农产品送到 Bar。"
	elif order_profile == "roadside_diner_produce":
		task_title = "公路餐厅原料需求"
		task_description = "将指定农产品或基础加工原料送到公路餐厅。"
	task.merge({
		"task_type": DELIVERY_TASK_TYPE,
		"delivery_category": FARM_PRODUCE_DELIVERY,
		"difficulty": "simple",
		"title": task_title,
		"description": task_description,
		"delivery_items": [{
			"ingredient_id": str(template.get("ingredient_id", "")),
			"display_name": str(template.get("display_name", "")),
			"quantity": multiplier,
			"multiplier": multiplier,
			"unit_weight_kg": unit,
			"weight_kg": required_weight,
		}],
		"active": true,
	}, true)
	_apply_scaled_delivery_duration(task, task["delivery_items"] as Array, FARM_PRODUCE_DELIVERY)
	task["rewards"] = _build_delivery_rewards(task["delivery_items"], FARM_PRODUCE_DELIVERY, task)
	return EventBoard.add_team_task(target_team, task)


func _emit_random_material_collection(target_team: String, metadata: Dictionary) -> Array[Dictionary]:
	if _material_collection_inventory.is_empty():
		return []
	var candidates := _material_collection_inventory.duplicate(true)
	var required_group := str(metadata.get("material_group", ""))
	if not required_group.is_empty():
		candidates = candidates.filter(func(entry: Dictionary) -> bool:
			return str(entry.get("material_group", "")) == required_group
		)
	if candidates.is_empty():
		return []
	candidates.shuffle()
	var count := _rng.randi_range(2, mini(3, candidates.size()))
	var items: Array[Dictionary] = []
	for index in range(count):
		var template: Dictionary = candidates[index]
		var multiplier := _get_current_requirement_multiplier()
		var minimum := multiplier
		var maximum := multiplier
		var quantity := multiplier
		items.append({
			"material_id": template["material_id"],
			"display_name": template["display_name"],
			"material_group": template["material_group"],
			"rarity": str(template.get("rarity", "common")),
			"reward_weight": float(template.get("reward_weight", 1.0)),
			"quantity": quantity,
			"multiplier": quantity,
			"min_quantity": minimum,
			"max_quantity": maximum,
			"unit": "count",
		})
	var task := _delivery_metadata(MATERIAL_COLLECTION, "hard" if count > 1 else "simple", metadata, target_team)
	task.merge({
		"task_type": DELIVERY_TASK_TYPE,
		"delivery_category": MATERIAL_COLLECTION,
		"title": "矿石配送订单" if required_group == "ore" else "木材收集任务",
		"description": "收集指定数量的矿石并交付到本队仓库。" if required_group == "ore" else "收集指定数量的木材并交付到本队仓库。",
		"delivery_items": items,
		"active": true,
	}, true)
	_apply_scaled_delivery_duration(task, items, MATERIAL_COLLECTION)
	task["rewards"] = _build_delivery_rewards(items, MATERIAL_COLLECTION, task)
	return EventBoard.add_team_task(target_team, task)


func _apply_scaled_delivery_duration(task: Dictionary, items: Array, category: String) -> void:
	if not bool(task.get("is_timed", false)):
		return
	var item_count := clampi(items.size(), 1, 3)
	var item_count_factor := 1.0
	if item_count == 2:
		item_count_factor = 1.5
	elif item_count >= 3:
		item_count_factor = 2.0
	var workload_ratio := 0.0
	for item_value: Variant in items:
		if not item_value is Dictionary:
			continue
		var item := item_value as Dictionary
		var value := 0.0
		var minimum := 0.0
		var maximum := 1.0
		match category:
			COOKED_DISH_DELIVERY:
				value = float(item.get("multiplier", 1))
				minimum = 1.0
				maximum = 3.0
			FARM_PRODUCE_DELIVERY:
				value = float(item.get("multiplier", item.get("quantity", 1)))
				minimum = 1.0
				maximum = 3.0
			MATERIAL_COLLECTION:
				value = float(item.get("quantity", 1))
				minimum = float(item.get("min_quantity", 1))
				maximum = float(item.get("max_quantity", 3))
		workload_ratio = maxf(
			workload_ratio,
			clampf((value - minimum) / maxf(1.0, maximum - minimum), 0.0, 1.0)
		)
	var workload_factor := lerpf(1.0, DELIVERY_MAX_WORKLOAD_TIME_FACTOR, workload_ratio)
	var duration := minf(
		DELIVERY_MAX_DURATION_SECONDS,
		DELIVERY_BASE_DURATION_SECONDS * item_count_factor * workload_factor
	)
	task["time_limit_seconds"] = duration
	task["deadline_unix_msec"] = _unix_msec() + roundi(duration * 1000.0)


func _delivery_metadata(category: String, difficulty: String, overrides: Dictionary, target_team := "", force_own_base := false) -> Dictionary:
	var timed := bool(overrides.get("is_timed", _rng.randf() < TIMED_TASK_CHANCE))
	var duration := maxf(0.0, float(overrides.get(
		"time_limit_seconds",
		_rng.randf_range(TIMED_TASK_MIN_SECONDS, TIMED_TASK_MAX_SECONDS)
	))) if timed else 0.0
	var location := _choose_delivery_location(target_team, category, force_own_base)
	var location_value: Variant = overrides.get("delivery_location", {})
	var override_location: Dictionary = {}
	if location_value is Dictionary:
		override_location = (location_value as Dictionary).duplicate(true)
	elif location_value is String and not str(location_value).is_empty():
		override_location = {"id": str(location_value), "name": str(location_value)}
	var resolved_override := _resolve_delivery_location_override(
		override_location, category, target_team, force_own_base
	)
	if not resolved_override.is_empty():
		location = resolved_override
	var deadline := _unix_msec() + roundi(duration * 1000.0) if timed else 0
	return {
		"is_timed": timed,
		"time_limit_seconds": duration,
		"deadline_unix_msec": deadline,
		"managed_delivery_chain": bool(overrides.get("managed_delivery_chain", false)),
		"shared_task_id": str(overrides.get("shared_task_id", "")),
		"all_team_task": bool(overrides.get("all_team_task", false)),
		"first_completion_bonus_rate": clampf(float(overrides.get("first_completion_bonus_rate", 0.0)), 0.0, 1.0),
		"delivery_location": location,
		"delivery_location_id": str(location.get("id", "")),
		"delivery_location_name": str(location.get("name", "")),
		"reward_profile": str(overrides.get("reward_profile", category)),
		"difficulty": difficulty,
		"rewards": {"score": 0, "money": 0, "team_items": []},
	}


func _resolve_delivery_location_override(
	override_location: Dictionary,
	delivery_category: String,
	target_team: String,
	force_own_base: bool
) -> Dictionary:
	if override_location.is_empty():
		return {}
	var location_id := str(override_location.get("id", ""))
	if not location_id.is_empty() and is_instance_valid(MapBuildingRegistry):
		var all_locations: Array[Dictionary] = MapBuildingRegistry.get_delivery_locations()
		var category_locations: Array[Dictionary] = MapBuildingRegistry.get_delivery_locations(
			"", delivery_category
		)
		var registered := false
		for candidate: Dictionary in all_locations:
			if str(candidate.get("id", "")) == location_id:
				registered = true
				break
		if registered:
			for candidate: Dictionary in category_locations:
				if str(candidate.get("id", "")) != location_id:
					continue
				return candidate.duplicate(true) if _location_matches_team_rules(
					candidate, target_team, force_own_base
				) else {}
			return {}
	return override_location if _location_matches_team_rules(
		override_location, target_team, force_own_base
	) else {}


func _location_matches_team_rules(
	location: Dictionary, target_team: String, force_own_base: bool
) -> bool:
	var location_team := str(location.get("team", ""))
	if force_own_base:
		return location_team == target_team \
			and str(location.get("building_type", "")) == "garage"
	return location_team.is_empty() or location_team == target_team


func _choose_delivery_location(
	target_team := "", delivery_category := "", force_own_base := false
) -> Dictionary:
	var locations: Array[Dictionary] = []
	if is_instance_valid(MapBuildingRegistry):
		locations = MapBuildingRegistry.get_delivery_locations("", delivery_category)
	var eligible: Array[Dictionary] = []
	for location: Dictionary in locations:
		var location_team := str(location.get("team", ""))
		if force_own_base:
			if location_team == target_team and str(location.get("building_type", "")) == "garage":
				eligible.append(location)
		elif location_team.is_empty() or location_team == target_team:
			eligible.append(location)
	if not eligible.is_empty():
		locations = eligible
	if not locations.is_empty():
		return locations[_rng.randi_range(0, locations.size() - 1)].duplicate(true)
	return {
		"id": "map_spawn_delivery",
		"name": "当前地图交付点",
		"building_type": "delivery",
		"position": Vector3.ZERO,
		"team": "",
	}


func notify_delivery_destination_entered(
	building_id: String,
	team: String,
	entrant_kind: String,
	peer_id: int,
	vehicle_id := ""
) -> Dictionary:
	if GameAuthority.is_client_proxy() or building_id.is_empty() or team.is_empty():
		return {}
	var matched_task_ids: Array[int] = []
	for task: Dictionary in EventBoard.get_team_tasks(team):
		if bool(task.get("active", true)) \
				and str(task.get("delivery_location_id", "")) == building_id:
			matched_task_ids.append(int(task.get("task_id", 0)))
	var event := {
		"building_id": building_id,
		"team": team,
		"entrant_kind": entrant_kind,
		"peer_id": peer_id,
		"vehicle_id": vehicle_id,
		"matched_task_ids": matched_task_ids,
	}
	delivery_destination_entered.emit(event.duplicate(true))
	return event


func build_cargo_delivery_preview(
	building_id: String,
	building_name: String,
	team: String,
	entrant_kind: String,
	peer_id: int,
	vehicle_id: String,
	crates: Array[Dictionary],
	requested_task_id := 0
) -> Dictionary:
	if GameAuthority.is_client_proxy() or building_id.is_empty() or team.is_empty():
		return {}
	var tasks := EventBoard.get_team_tasks(team)
	tasks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("created_msec", 0)) < int(b.get("created_msec", 0))
	)
	for task: Dictionary in tasks:
		if not bool(task.get("active", true)) \
				or str(task.get("delivery_location_id", "")) != building_id \
				or (requested_task_id > 0 and int(task.get("task_id", 0)) != requested_task_id):
			continue
		var progress: Dictionary = (task.get("delivery_progress", {}) as Dictionary).duplicate(true)
		var consumption: Array[Dictionary] = []
		var delivered_now := {}
		var requirement_lines: Array[String] = []
		var progress_lines: Array[String] = []
		for item_value: Variant in task.get("delivery_items", []):
			if not item_value is Dictionary:
				continue
			var requirement := _cargo_requirement(item_value as Dictionary)
			var content_id := str(requirement.get("content_id", ""))
			var unit := str(requirement.get("unit", "count"))
			var required := float(requirement.get("quantity", 0.0))
			var previous := minf(required, float(progress.get(content_id, 0.0)))
			var remaining := maxf(0.0, required - previous)
			var added := 0.0
			for slot_index in range(crates.size()):
				if remaining <= 0.0001:
					break
				# Always derive delivery values from the crate's actual stored item.
				# Compatibility fields may be stale after a partial fill or transfer.
				var crate := CargoCrateData.normalize(crates[slot_index])
				if crate.is_empty() or str(crate.get("content_id", "")) != content_id \
						or str(crate.get("content_unit", "")) != unit:
					continue
				var already_reserved := 0.0
				for entry: Dictionary in consumption:
					if int(entry.get("slot_index", -1)) == slot_index:
						already_reserved += float(entry.get("quantity", 0.0))
				var available := maxf(0.0, float(crate.get("content_quantity", 0.0)) - already_reserved)
				var amount := minf(available, remaining)
				if amount <= 0.0001:
					continue
				consumption.append({"slot_index": slot_index, "content_id": content_id, "unit": unit, "quantity": amount})
				added += amount
				remaining -= amount
			if added > 0.0:
				delivered_now[content_id] = float(delivered_now.get(content_id, 0.0)) + added
			var display_name := str(requirement.get("display_name", content_id))
			requirement_lines.append("%s %s" % [display_name, _format_delivery_amount(required, unit)])
			progress_lines.append("%s %s / %s" % [
				display_name,
				_format_delivery_amount(previous + added, unit),
				_format_delivery_amount(required, unit),
			])
		if consumption.is_empty():
			continue
		var involved_slots := {}
		for entry: Dictionary in consumption:
			involved_slots[int(entry.get("slot_index", -1))] = true
		var delivered_lines: Array[String] = []
		for content_id_value: Variant in delivered_now.keys():
			var content_id := str(content_id_value)
			var matching := _find_task_requirement(task, content_id)
			delivered_lines.append("%s %s" % [
				str(matching.get("display_name", content_id)),
				_format_delivery_amount(float(delivered_now[content_id]), str(matching.get("unit", "count"))),
			])
		return {
			"building_id": building_id,
			"building_name": building_name,
			"team": team,
			"peer_id": peer_id,
			"entrant_kind": entrant_kind,
			"vehicle_id": vehicle_id,
			"task_id": int(task.get("task_id", 0)),
			"task_name": str(task.get("title", "货运任务")),
			"crate_count": involved_slots.size(),
			"consumption": consumption,
			"delivered_now": delivered_now,
			"delivery_summary": "，".join(delivered_lines),
			"requirement_summary": "，".join(requirement_lines),
			"progress_summary": "，".join(progress_lines),
		}
	return {}


func apply_cargo_delivery_progress(team: String, task_id: int, delivered_now: Dictionary) -> Dictionary:
	if GameAuthority.is_client_proxy() or delivered_now.is_empty():
		return {}
	for task: Dictionary in EventBoard.get_team_tasks(team):
		if int(task.get("task_id", 0)) != task_id or not bool(task.get("active", true)):
			continue
		var progress: Dictionary = (task.get("delivery_progress", {}) as Dictionary).duplicate(true)
		for content_id_value: Variant in delivered_now.keys():
			var content_id := str(content_id_value)
			progress[content_id] = float(progress.get(content_id, 0.0)) + float(delivered_now[content_id_value])
		var complete := true
		for item_value: Variant in task.get("delivery_items", []):
			if not item_value is Dictionary:
				continue
			var requirement := _cargo_requirement(item_value as Dictionary)
			var content_id := str(requirement.get("content_id", ""))
			var required := maxf(0.0, float(requirement.get("quantity", 0.0)))
			var delivered := minf(required, maxf(0.0, float(progress.get(content_id, 0.0))))
			if delivered + 0.0001 < required:
				complete = false
		task["delivery_progress"] = progress
		if complete:
			return _finalize_delivery_task(team, task, true, false)
		EventBoard.update_team_task(team, task_id, {"delivery_progress": progress})
		return {"completed": false, "reward_money": 0, "delivery_progress": progress}
	return {}


func _finalize_delivery_task(team: String, task: Dictionary, completed: bool, timed_out: bool) -> Dictionary:
	if task.is_empty() or bool(task.get("reward_paid", false)):
		return {}
	var progress: Dictionary = (task.get("delivery_progress", {}) as Dictionary).duplicate(true)
	var total_delivered := 0.0
	var weighted_progress := 0.0
	var total_reward_weight := 0.0
	var delivered_lines: Array[String] = []
	for item_value: Variant in task.get("delivery_items", []):
		if not item_value is Dictionary:
			continue
		var requirement := _cargo_requirement(item_value as Dictionary)
		var content_id := str(requirement.get("content_id", ""))
		var required := maxf(0.0, float(requirement.get("quantity", 0.0)))
		var delivered := minf(required, maxf(0.0, float(progress.get(content_id, 0.0))))
		total_delivered += delivered
		var reward_weight := maxf(0.01, float((item_value as Dictionary).get("reward_weight", 1.0)))
		total_reward_weight += reward_weight
		weighted_progress += reward_weight * clampf(
			delivered / required if required > 0.0001 else 0.0,
			0.0,
			1.0
		)
		if delivered > 0.0001:
			delivered_lines.append("%s %s / %s" % [
				str(requirement.get("display_name", content_id)),
				_format_delivery_amount(delivered, str(requirement.get("unit", "count"))),
				_format_delivery_amount(required, str(requirement.get("unit", "count"))),
			])
	var completion_ratio := clampf(
		weighted_progress / total_reward_weight if total_reward_weight > 0.0001 else 0.0,
		0.0,
		1.0
	)
	var base_reward := int((task.get("rewards", {}) as Dictionary).get("money", 0))
	var reward_money := base_reward if completed else floori(float(base_reward) * 0.5 * completion_ratio)
	var changes := {
		"active": false,
		"completed": completed,
		"timed_out": timed_out,
		"ended_unix_msec": _unix_msec(),
		"summary_visible": true,
		"delivery_completion_ratio": completion_ratio,
		"delivery_reward_paid": reward_money,
		"reward_paid": true,
	}
	if completed:
		changes["completed_msec"] = Time.get_ticks_msec()
		var shared_id := str(task.get("shared_task_id", ""))
		var first_completion := not shared_id.is_empty() \
			and _get_shared_task_winner(shared_id).is_empty()
		if first_completion:
			reward_money = roundi(float(base_reward) * (
				1.0 + float(task.get("first_completion_bonus_rate", 0.0))
			))
			changes["race_winner_team"] = team
			changes["delivery_reward_paid"] = reward_money
			_mark_shared_task_winner(shared_id, team, int(task.get("task_id", 0)))
	else:
		changes["timed_out_unix_msec"] = changes["ended_unix_msec"]
	var summary_lines: Array[String] = []
	if total_delivered <= 0.0001:
		summary_lines.append("任务结束：队伍未交付任何需求物。")
	elif completed:
		summary_lines.append("任务完成：已交付全部需求物。")
		summary_lines.append("实际交付：" + "、".join(delivered_lines))
	else:
		summary_lines.append("任务结束：完成度 %.1f%%。" % (completion_ratio * 100.0))
		summary_lines.append("实际交付：" + "、".join(delivered_lines))
	if reward_money > 0:
		summary_lines.append("结算奖励：%d 队伍金钱，同时增加同额队伍得分。" % reward_money)
	else:
		summary_lines.append("结算奖励：0 队伍金钱和队伍得分。")
	changes["result_summary"] = "\n".join(summary_lines)
	if reward_money > 0:
		GlobalVar.add_team_reward(team, reward_money)
		var delivery_category := str(task.get("delivery_category", ""))
		var stat_category := "mining"
		if delivery_category == "cooked_dish":
			stat_category = "cooking"
		elif delivery_category == "farm_produce":
			stat_category = "agriculture_livestock"
		GlobalVar.add_match_stat(team, stat_category, reward_money)
	if completed:
		GlobalVar.add_match_stat(team, "completed_orders", 1)
	elif total_delivered > 0.0001:
		GlobalVar.add_match_stat(team, "partial_orders", 1)
	EventBoard.update_team_task(team, int(task.get("task_id", 0)), changes)
	return {
		"completed": completed,
		"completion_ratio": completion_ratio,
		"reward_money": reward_money,
		"delivery_progress": progress,
		"result_summary": changes["result_summary"],
	}


func _get_shared_task_winner(shared_task_id: String) -> String:
	for team: String in EventBoard.VALID_TEAMS:
		for task: Dictionary in EventBoard.get_team_tasks(team):
			if str(task.get("shared_task_id", "")) == shared_task_id \
					and not str(task.get("race_winner_team", "")).is_empty():
				return str(task.get("race_winner_team", ""))
	return ""


func _mark_shared_task_winner(shared_task_id: String, winner_team: String, excluded_task_id: int) -> void:
	for team: String in EventBoard.VALID_TEAMS:
		for task: Dictionary in EventBoard.get_team_tasks(team):
			if int(task.get("task_id", 0)) == excluded_task_id \
					or str(task.get("shared_task_id", "")) != shared_task_id:
				continue
			EventBoard.update_team_task(team, int(task.get("task_id", 0)), {
				"race_winner_team": winner_team,
			})


func _cargo_requirement(item: Dictionary) -> Dictionary:
	if item.has("dish_id"):
		return {"content_id": str(item.get("dish_id", "")), "display_name": str(item.get("display_name", "成品菜")), "quantity": float(item.get("quantity", 0.0)), "unit": "serving"}
	if item.has("ingredient_id"):
		return {"content_id": str(item.get("ingredient_id", "")), "display_name": str(item.get("display_name", "原材料")), "quantity": float(item.get("weight_kg", 0.0)), "unit": "kg"}
	return {"content_id": str(item.get("material_id", "")), "display_name": str(item.get("display_name", "材料")), "quantity": float(item.get("quantity", 0.0)), "unit": str(item.get("unit", "count"))}


func _find_task_requirement(task: Dictionary, content_id: String) -> Dictionary:
	for item_value: Variant in task.get("delivery_items", []):
		if item_value is Dictionary:
			var requirement := _cargo_requirement(item_value as Dictionary)
			if str(requirement.get("content_id", "")) == content_id:
				return requirement
	return {}


func _format_delivery_amount(quantity: float, unit: String) -> String:
	if unit == "kg":
		return "%.2f kg" % quantity
	return "%d%s" % [roundi(quantity), "份" if unit == "serving" else "个"]


func _build_delivery_rewards(items: Array, category: String, task: Dictionary) -> Dictionary:
	var total_weight := 0.0
	var total_quantity := 0.0
	for value: Variant in items:
		if value is Dictionary:
			total_weight += float((value as Dictionary).get("weight_kg", 0.0))
			total_quantity += float((value as Dictionary).get("quantity", 0.0))
	var money := 1000.0
	match category:
		COOKED_DISH_DELIVERY:
			money = 1400.0 + total_quantity * 4.0 + maxf(0.0, items.size() - 1) * 700.0
		FARM_PRODUCE_DELIVERY:
			money = 1000.0 + total_weight * 180.0
		MATERIAL_COLLECTION:
			money = 1600.0 + total_quantity * 8.0 + maxf(0.0, items.size() - 1) * 350.0
	if str(task.get("difficulty", "simple")) == "hard":
		money *= 1.15
	money = clampf(money, 1000.0, 6000.0)
	return {
		# 任务奖励同时写入队伍资金和独立的累计队伍得分。
		"score": roundi(money),
		"money": roundi(money),
		"team_items": [],
	}


func _all_farm_delivery_ids() -> Array[String]:
	var ids: Array[String] = []
	for ingredient_id: String in IngredientCatalog.get_plantable_ids():
		if not ids.has(ingredient_id):
			ids.append(ingredient_id)
	for ingredient_id: String in FARM_BASE_PRODUCTS.keys():
		if not ids.has(ingredient_id) and not IngredientCatalog.get_definition(ingredient_id).is_empty():
			ids.append(ingredient_id)
	return ids


func _get_recipe_ingredient_type_count(recipe_id: String) -> int:
	var ingredient_ids := {}
	for ingredient: Dictionary in RecipeCatalog.get_ingredients_per_batch(recipe_id):
		var ingredient_id := str(ingredient.get("ingredient_id", ""))
		if not ingredient_id.is_empty():
			ingredient_ids[ingredient_id] = true
	return ingredient_ids.size()


func _get_dish_reward_weight(ingredient_count: int) -> float:
	if ingredient_count <= 2:
		return 1.0
	return 1.0 + 0.2 * float(mini(ingredient_count, RecipeCatalog.MAX_INGREDIENTS) - 2)

func emit_recipe_order(target_team: String, recipe_id: String, required_servings: int) -> Array[Dictionary]:
	if GameAuthority.is_client_proxy() or required_servings <= 0:
		return []
	var recipe := RecipeCatalog.get_recipe(recipe_id)
	var result := RecipeCatalog.get_result(recipe_id)
	var servings_per_batch := int(result.get("quantity", 0))
	if recipe.is_empty() or servings_per_batch <= 0 or required_servings % servings_per_batch != 0:
		push_warning("Food order must request a positive multiple of the recipe output: %s" % recipe_id)
		return []
	var batch_count := required_servings / servings_per_batch
	var required_ingredients := RecipeCatalog.get_required_ingredients(recipe_id, batch_count)
	if required_ingredients.is_empty() or required_ingredients.size() > RecipeCatalog.MAX_INGREDIENTS:
		return []
	var dish_name := str(result.get("display_name", recipe.get("display_name", recipe_id)))
	var task := {
		"task_type": "recipe_order",
		"title": "制作订单：%s × %d 份" % [dish_name, required_servings],
		"description": "按菜谱完成 %d 份%s。" % [required_servings, dish_name],
		"recipe_id": recipe_id,
		"recipe_display_name": dish_name,
		"required_servings": required_servings,
		"batch_count": batch_count,
		"required_ingredients": required_ingredients,
		"active": true,
	}
	var metadata := _delivery_metadata("recipe_order", "simple", {
		"is_timed": false,
		"reward_profile": "recipe_order",
	})
	task.merge(metadata, true)
	var reward_money := maxi(1, required_servings * 2)
	task["rewards"] = {
		"score": reward_money,
		"money": reward_money,
		"team_items": [],
	}
	var created := EventBoard.add_team_task(target_team, task)
	if not created.is_empty():
		for created_task: Dictionary in created:
			GameAuthority.reserve_ingredient_pickups_for_team(str(created_task.get("team", "")))
		EventBoard.add_global_event("公共餐饮订单", "%s：%d 份" % [dish_name, required_servings], "order")
	return created
