extends RecipeCookingStation
class_name PlatingStation

@export var output_surface_position := Vector3(0.0, 1.02, 0.0)
@export var output_surface_scale := Vector3(0.55, 0.55, 0.55)

var displayed_output: Node3D


func get_station_group_name() -> String:
	return "plating_stations"


func get_state_event_type() -> String:
	return "plating_station_state"


func get_recipe_station_key() -> String:
	return "prep_counter"


func get_station_display_name() -> String:
	return "配餐台"


func should_spoil_output() -> bool:
	return false


func get_interaction_hint(player: GamePlayer) -> String:
	if not can_player_interact(player):
		return "敌方厨房用具"
	if complete:
		return "[E] 拿取成品菜"
	if cooking:
		return "正在制作"
	if is_in_use_by_other(player.authority_peer_id):
		return "队友正在使用配餐台"
	return "[E] 使用配餐台"


func _refresh_station_visual() -> void:
	super._refresh_station_visual()
	if is_instance_valid(displayed_output):
		displayed_output.queue_free()
		displayed_output = null
	if complete and _should_display_completed_output():
		var model_path := DishCatalog.get_model_path(str(RecipeCatalog.get_result(recipe_id).get("dish_id", "")))
		var packed_scene := load(model_path) as PackedScene
		if packed_scene != null:
			displayed_output = packed_scene.instantiate() as Node3D
			if displayed_output != null:
				add_child(displayed_output)
				displayed_output.position = output_surface_position
				displayed_output.scale = output_surface_scale
				_disable_visual_collision(displayed_output)
func _should_display_completed_output() -> bool:
	return true


func _disable_visual_collision(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	for child in node.get_children():
		_disable_visual_collision(child)
