extends KitchenAppliance
class_name ChoppingStation

const REQUIRED_CHOPS := 3

@export var ingredient_surface_position := Vector3(0.0, 1.0, 0.0)
@export var ingredient_surface_scale := Vector3(0.5, 0.5, 0.5)

var ingredient_id := ""
var ingredient_weight_kg := 0.0
var chop_count := 0
var displayed_ingredient: Node3D

@onready var status_label: Label3D = $StatusLabel


func _ready() -> void:
	add_to_group("chopping_stations")
	_refresh_station_visual()


func get_interaction_hint(player: GamePlayer) -> String:
	if not can_player_interact(player):
		return "敌方厨房用具"
	# A completed ingredient is shared output, not owned by the player who cut it.
	if chop_count < REQUIRED_CHOPS and is_in_use_by_other(player.authority_peer_id):
		return "队友正在使用切菜台"
	if ingredient_id.is_empty():
		return "[E] 放置食材" if not player.get_selected_choppable_ingredient().is_empty() else "需要手持可切碎食材"
	if chop_count < REQUIRED_CHOPS:
		return "[E] 切菜 (%d/%d)" % [chop_count, REQUIRED_CHOPS]
	if not player.can_add_personal_ingredient(ingredient_id, ingredient_weight_kg, true):
		return "个人背包已满，无法拿取"
	return "[E] 拿取切碎食材"


func interact(player: GamePlayer) -> bool:
	if not can_player_interact(player):
		return false
	if GameAuthority.should_send_network_requests():
		return _request_network_action(player)
	return _request_local_authority_action(player)


func _request_local_authority_action(player: GamePlayer) -> bool:
	var action := _build_action(player)
	if action.is_empty():
		return false
	var result := GameAuthority.local_ingredient_pickup_action(player.authority_peer_id, action)
	if not bool(result.get("ok", false)):
		return false
	player.apply_authoritative_chopping_action_result(result)
	return true


func _request_network_action(player: GamePlayer) -> bool:
	var action := _build_action(player)
	if action.is_empty():
		return false
	MultiplayerNetwork.submit_ingredient_pickup_action(action)
	return true


func _build_action(player: GamePlayer) -> Dictionary:
	var action := {
		"station_kind": "chopping",
		"station_path": str(get_path()),
		"station_position": global_position,
	}
	if ingredient_id.is_empty():
		var held_ingredient := player.get_selected_choppable_ingredient()
		if held_ingredient.is_empty():
			return {}
		action["action"] = "place"
		action["slot_index"] = int(held_ingredient.get("slot_index", -1))
		var held_ingredient_id := str(held_ingredient.get("ingredient_id", ""))
		action["ingredient_id"] = held_ingredient_id
		action["weight_kg"] = IngredientCatalog.get_pickup_unit_kg(held_ingredient_id)
	elif chop_count < REQUIRED_CHOPS:
		action["action"] = "cut"
	else:
		if not player.can_add_personal_ingredient(ingredient_id, ingredient_weight_kg, true):
			return {}
		action["action"] = "take"
	return action


func place_ingredient(next_ingredient_id: String, weight_kg: float) -> bool:
	if not ingredient_id.is_empty() or next_ingredient_id.is_empty() or weight_kg <= 0.0:
		return false
	if IngredientCatalog.get_model_path(next_ingredient_id, "chopped_item").is_empty():
		return false
	ingredient_id = next_ingredient_id
	ingredient_weight_kg = weight_kg
	chop_count = 0
	_refresh_station_visual()
	return true


func cut_once() -> bool:
	if ingredient_id.is_empty() or chop_count >= REQUIRED_CHOPS:
		return false
	chop_count += 1
	_refresh_station_visual()
	return true


func _should_keep_user_lock() -> bool:
	return not ingredient_id.is_empty() and chop_count < REQUIRED_CHOPS


func clear_station() -> void:
	ingredient_id = ""
	ingredient_weight_kg = 0.0
	chop_count = 0
	_refresh_station_visual()


func get_station_state() -> Dictionary:
	var state := {
		"station_path": str(get_path()),
		"station_position": global_position,
		"ingredient_id": ingredient_id,
		"ingredient_weight_kg": ingredient_weight_kg,
		"chop_count": chop_count,
	}
	state.merge(get_user_lock_state(), true)
	return state


func apply_authoritative_station_state(state: Dictionary) -> void:
	apply_user_lock_state(state)
	ingredient_id = str(state.get("ingredient_id", ""))
	ingredient_weight_kg = maxf(0.0, float(state.get("ingredient_weight_kg", 0.0)))
	chop_count = clampi(int(state.get("chop_count", 0)), 0, REQUIRED_CHOPS)
	if ingredient_id.is_empty():
		ingredient_weight_kg = 0.0
		chop_count = 0
	_refresh_station_visual()


func _refresh_station_visual() -> void:
	if is_instance_valid(displayed_ingredient):
		displayed_ingredient.queue_free()
		displayed_ingredient = null
	if ingredient_id.is_empty():
		if is_instance_valid(status_label):
			status_label.text = "手持可切碎食材后按 [E] 放置"
		return
	var model_state := "chopped_item" if chop_count >= REQUIRED_CHOPS else "whole_item"
	var model_path := IngredientCatalog.get_model_path(ingredient_id, model_state)
	if model_path.is_empty() and model_state == "whole_item":
		model_path = IngredientCatalog.get_harvest_drop_scene_path(ingredient_id)
	var packed_scene := load(model_path) as PackedScene
	if packed_scene != null:
		displayed_ingredient = packed_scene.instantiate() as Node3D
		if displayed_ingredient != null:
			add_child(displayed_ingredient)
			displayed_ingredient.position = ingredient_surface_position
			displayed_ingredient.scale = ingredient_surface_scale
			_disable_visual_collision(displayed_ingredient)
	if is_instance_valid(status_label):
		status_label.text = "按 [E] 切菜 (%d/%d)" % [chop_count, REQUIRED_CHOPS] if chop_count < REQUIRED_CHOPS else "按 [E] 拿取切碎食材"


func _disable_visual_collision(node: Node) -> void:
	if node is CollisionObject3D:
		var collision_object := node as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	for child in node.get_children():
		_disable_visual_collision(child)
