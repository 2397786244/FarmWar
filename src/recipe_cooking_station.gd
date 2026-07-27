extends KitchenAppliance
class_name RecipeCookingStation

const PROGRESS_SYNC_INTERVAL := 0.25
const SPOIL_DELAY_MULTIPLIER := 1.5

var recipe_id := ""
var task_id := -1
var staged_slots: Array[Dictionary] = []
var cooking := false
var complete := false
var cooking_started_msec := 0
var cooking_duration_seconds := 0.0
var completed_msec := 0
var spoiled := false
var _last_progress_sync_msec := 0

@onready var status_label: Label3D = $StatusLabel
@onready var progress_back: MeshInstance3D = $ProgressBack
@onready var progress_fill: MeshInstance3D = $ProgressFill


func _ready() -> void:
	add_to_group(get_station_group_name())
	_refresh_station_visual()


func _process(_delta: float) -> void:
	if GameAuthority.is_client_proxy():
		return
	var now_msec := Time.get_ticks_msec()
	if cooking:
		if get_progress(now_msec) >= 1.0:
			cooking = false
			complete = true
			completed_msec = now_msec
			if active_user_peer_id != 0:
				release_user(active_user_peer_id)
			_refresh_station_visual()
			_emit_authoritative_state()
			return
		if now_msec - _last_progress_sync_msec >= int(PROGRESS_SYNC_INTERVAL * 1000.0):
			_last_progress_sync_msec = now_msec
			_refresh_station_visual()
			_emit_authoritative_state()
		return
	if should_spoil_output() and complete and not spoiled and completed_msec > 0 and now_msec - completed_msec >= _get_spoil_delay_msec():
		spoiled = true
		_refresh_station_visual()
		_emit_authoritative_state()


func get_station_group_name() -> String:
	return ""


func get_state_event_type() -> String:
	return ""


func get_recipe_station_key() -> String:
	return ""


func get_station_display_name() -> String:
	return "厨具"


func get_cooking_verb() -> String:
	return "制作"


func get_spoiled_dish_id() -> String:
	return "burnt_plate"


func should_spoil_output() -> bool:
	return true


func get_interaction_hint(player: GamePlayer) -> String:
	if not can_player_interact(player):
		return "敌方厨房用具"
	if complete:
		return "[E] 拿取成品菜"
	if cooking:
		return "正在%s" % get_cooking_verb()
	if is_in_use_by_other(player.authority_peer_id):
		return "队友正在使用%s" % get_station_display_name()
	return "[E] 使用%s" % get_station_display_name()


func get_current_order(team: String) -> Dictionary:
	if not recipe_id.is_empty():
		return {"task_id": task_id, "recipe_id": recipe_id}
	var task := EventBoard.get_latest_recipe_order(team)
	if task.is_empty():
		return {}
	var candidate_recipe_id := str(task.get("recipe_id", ""))
	var step: Variant = RecipeCatalog.get_recipe(candidate_recipe_id).get("key_step", {})
	if not step is Dictionary or str((step as Dictionary).get("station", "")) != get_recipe_station_key():
		return {}
	return task


func get_display_slots(team: String) -> Array[Dictionary]:
	if not staged_slots.is_empty():
		return staged_slots.duplicate(true)
	var task := get_current_order(team)
	if task.is_empty():
		return []
	var result: Array[Dictionary] = []
	for ingredient: Dictionary in RecipeCatalog.get_ingredients_per_batch(str(task.get("recipe_id", ""))):
		var ingredient_id := str(ingredient.get("ingredient_id", ""))
		var definition := IngredientCatalog.get_definition(ingredient_id)
		var is_chopped := bool(ingredient.get("is_chopped", false))
		result.append({
			"ingredient_id": ingredient_id,
			"display_name": "切碎的" + str(definition.get("display_name", ingredient_id)) if is_chopped else str(definition.get("display_name", ingredient_id)),
			"required_weight_kg": float(ingredient.get("weight_kg", 0.0)),
			"is_chopped": is_chopped,
			"placed": false,
		})
	return result


func get_stage_requirement(team: String, ingredient_id: String, is_chopped: bool) -> Dictionary:
	if cooking or complete or ingredient_id.is_empty():
		return {}
	for slot: Dictionary in get_display_slots(team):
		if str(slot.get("ingredient_id", "")) == ingredient_id and bool(slot.get("is_chopped", false)) == is_chopped and not bool(slot.get("placed", false)):
			return slot.duplicate(true)
	return {}


func stage_ingredient(team: String, ingredient_id: String, is_chopped: bool) -> Dictionary:
	if get_stage_requirement(team, ingredient_id, is_chopped).is_empty():
		return {}
	if staged_slots.is_empty():
		var task := get_current_order(team)
		if task.is_empty():
			return {}
		recipe_id = str(task.get("recipe_id", ""))
		task_id = int(task.get("task_id", -1))
		staged_slots = get_display_slots(team)
	for index in range(staged_slots.size()):
		var slot := staged_slots[index]
		if str(slot.get("ingredient_id", "")) == ingredient_id and bool(slot.get("is_chopped", false)) == is_chopped and not bool(slot.get("placed", false)):
			slot["placed"] = true
			staged_slots[index] = slot
			_refresh_station_visual()
			return slot.duplicate(true)
	return {}


func can_start_cooking() -> bool:
	if recipe_id.is_empty() or staged_slots.is_empty() or cooking or complete:
		return false
	for slot: Dictionary in staged_slots:
		if not bool(slot.get("placed", false)):
			return false
	return true


func can_start_selected_recipe(selected_recipe_id: String) -> bool:
	if selected_recipe_id.is_empty() or cooking or complete:
		return false
	var recipe := RecipeCatalog.get_recipe(selected_recipe_id)
	var step_value: Variant = recipe.get("key_step", {})
	return not recipe.is_empty() and step_value is Dictionary \
		and str((step_value as Dictionary).get("station", "")) == get_recipe_station_key()


func start_selected_recipe(selected_recipe_id: String) -> bool:
	if not can_start_selected_recipe(selected_recipe_id):
		return false
	recipe_id = selected_recipe_id
	task_id = -1
	staged_slots.clear()
	for ingredient: Dictionary in RecipeCatalog.get_ingredients_per_batch(recipe_id):
		var ingredient_id := str(ingredient.get("ingredient_id", ""))
		var definition := IngredientCatalog.get_definition(ingredient_id)
		var is_chopped := bool(ingredient.get("is_chopped", false))
		staged_slots.append({
			"ingredient_id": ingredient_id,
			"display_name": "切碎的" + str(definition.get("display_name", ingredient_id)) if is_chopped else str(definition.get("display_name", ingredient_id)),
			"required_weight_kg": float(ingredient.get("weight_kg", 0.0)),
			"is_chopped": is_chopped,
			"placed": true,
		})
	return start_cooking()


func start_cooking() -> bool:
	if not can_start_cooking():
		return false
	var step: Variant = RecipeCatalog.get_recipe(recipe_id).get("key_step", {})
	if not step is Dictionary:
		return false
	cooking_duration_seconds = maxf(0.1, float((step as Dictionary).get("duration_seconds", 0.0)))
	cooking_started_msec = Time.get_ticks_msec()
	cooking = true
	complete = false
	_last_progress_sync_msec = 0
	_refresh_station_visual()
	return true


func can_take_output() -> bool:
	return complete and not recipe_id.is_empty()


func take_output() -> Dictionary:
	if not can_take_output():
		return {}
	var result := get_output_result()
	clear_station()
	return result


func get_output_result() -> Dictionary:
	var result := RecipeCatalog.get_result(recipe_id)
	if spoiled and not result.is_empty():
		var failed_dish_id := get_spoiled_dish_id()
		result["dish_id"] = failed_dish_id
		result["display_name"] = str(DishCatalog.get_definition(failed_dish_id).get("display_name", "失败料理"))
		result["serving_weight_kg"] = float(result.get("total_weight_kg", 0.0)) / maxf(1.0, float(result.get("quantity", 0)))
	return result


func clear_station() -> void:
	recipe_id = ""
	task_id = -1
	staged_slots.clear()
	cooking = false
	complete = false
	cooking_started_msec = 0
	cooking_duration_seconds = 0.0
	completed_msec = 0
	spoiled = false
	_refresh_station_visual()


func get_station_state() -> Dictionary:
	var state := {
		"station_path": str(get_path()), "station_position": global_position,
		"recipe_id": recipe_id, "task_id": task_id, "staged_slots": staged_slots.duplicate(true),
		"cooking": cooking, "complete": complete, "progress": get_progress(),
		"cooking_duration_seconds": cooking_duration_seconds, "spoiled": spoiled,
	}
	state.merge(get_user_lock_state(), true)
	return state


func apply_authoritative_station_state(state: Dictionary) -> void:
	apply_user_lock_state(state)
	recipe_id = str(state.get("recipe_id", ""))
	task_id = int(state.get("task_id", -1))
	staged_slots.clear()
	var slots_value: Variant = state.get("staged_slots", [])
	if slots_value is Array:
		for value: Variant in slots_value:
			if value is Dictionary:
				staged_slots.append((value as Dictionary).duplicate(true))
	cooking = bool(state.get("cooking", false))
	complete = bool(state.get("complete", false))
	spoiled = bool(state.get("spoiled", false))
	cooking_duration_seconds = maxf(0.0, float(state.get("cooking_duration_seconds", 0.0)))
	if cooking and cooking_duration_seconds > 0.0:
		cooking_started_msec = Time.get_ticks_msec() - int(clampf(float(state.get("progress", 0.0)), 0.0, 1.0) * cooking_duration_seconds * 1000.0)
	_refresh_station_visual()


func get_progress(now_msec := Time.get_ticks_msec()) -> float:
	if complete:
		return 1.0
	if not cooking or cooking_duration_seconds <= 0.0:
		return 0.0
	return clampf(float(now_msec - cooking_started_msec) / (cooking_duration_seconds * 1000.0), 0.0, 1.0)


func _emit_authoritative_state() -> void:
	var event_type := get_state_event_type()
	if event_type.is_empty():
		return
	GameAuthority.reliable_world_event_ready.emit({"type": event_type, "station_state": get_station_state(), "tick": GameAuthority.server_tick})


func _refresh_station_visual() -> void:
	var progress := get_progress()
	if is_instance_valid(progress_back):
		progress_back.visible = cooking
	if is_instance_valid(progress_fill):
		progress_fill.visible = cooking
		progress_fill.scale.x = maxf(0.001, progress)
		progress_fill.position.x = -0.72 * (1.0 - progress)
	if is_instance_valid(status_label):
		if complete and spoiled:
			status_label.text = "已变质，按 [E] 取走失败料理"
		elif complete:
			status_label.text = "按 [E] 拿取成品菜"
		elif cooking:
			status_label.text = "%s中 %d%%" % [get_cooking_verb(), roundi(progress * 100.0)]
		elif recipe_id.is_empty():
			status_label.text = "按 [E] 使用%s" % get_station_display_name()
		else:
			status_label.text = "放入原料后开始%s" % get_cooking_verb()


func _should_keep_user_lock() -> bool:
	return cooking


func _get_spoil_delay_msec() -> int:
	return maxi(1, roundi(cooking_duration_seconds * SPOIL_DELAY_MULTIPLIER)) * 1000
