extends Node3D
class_name FarmWorldInitializer

signal map_initialization_progress(progress: float, status: String)
signal map_initialization_completed

@export var loading_map_name := "Creston Town"
@export_dir var loading_images_directory := "res://assets/loading/creston_town"
@export_file("*.json") var loading_tips_path := "res://data/loading_tips.json"

var is_map_initialized := false

const FUTURE_WARRIOR_AI_SCENE := preload("res://character/FutureWarriorAI.tscn")
const FARMER_AI_SCENE := preload("res://character/FarmerAI.tscn")


func _ready() -> void:
	GlobalVar.gameworld = self
	MapLoading.ensure_loading(loading_map_name, loading_images_directory, loading_tips_path)
	_set_loading_progress(0.25, "正在初始化地图系统")
	await get_tree().process_frame
	await _initialize_farm_fields()
	_set_loading_progress(0.96, "正在完成地图初始化")
	await get_tree().process_frame
	is_map_initialized = true
	map_initialization_completed.emit()

	var player := _create_pending_player()
	var farmer_ai: FarmerAI
	if player != null:
		_set_loading_progress(0.99, "正在生成玩家")
		await get_tree().process_frame
		_spawn_singleplayer_future_warrior()
		farmer_ai = _spawn_singleplayer_farmer_ai()
	await MapLoading.finish_loading()
	if is_instance_valid(player):
		player.process_mode = Node.PROCESS_MODE_INHERIT
	if is_instance_valid(farmer_ai):
		farmer_ai.process_mode = Node.PROCESS_MODE_INHERIT


func wait_until_initialized() -> void:
	if is_map_initialized:
		return
	await map_initialization_completed


func _initialize_farm_fields() -> void:
	var fields: Array[FarmFieldGenerator] = []
	_collect_farm_fields(self, fields)
	var total_tiles := 0
	for field in fields:
		total_tiles += field.length_tiles * field.width_tiles
	if total_tiles <= 0:
		_set_loading_progress(0.9, "地图系统已准备")
		return

	var completed_tiles := 0
	for field in fields:
		var completed_before_field := completed_tiles
		var progress_callback := func(_field_id: String, generated: int, _total: int) -> void:
			var overall := float(completed_before_field + generated) / float(total_tiles)
			var progress := lerpf(0.25, 0.92, overall)
			_set_loading_progress(progress, "正在生成%s农田" % _field_display_name(field))
		field.generation_progress.connect(progress_callback)
		await field.generate_field_async()
		if field.generation_progress.is_connected(progress_callback):
			field.generation_progress.disconnect(progress_callback)
		completed_tiles += field.length_tiles * field.width_tiles


func _collect_farm_fields(node: Node, result: Array[FarmFieldGenerator]) -> void:
	for child in node.get_children():
		if child is FarmFieldGenerator:
			result.append(child as FarmFieldGenerator)
		_collect_farm_fields(child, result)


func _field_display_name(field: FarmFieldGenerator) -> String:
	if field.field_label.begins_with("red"):
		return "红队"
	if field.field_label.begins_with("blue"):
		return "蓝队"
	return field.field_label


func _create_pending_player() -> GamePlayer:
	if GlobalVar.pending_player_selection.is_empty():
		return null
	var selection := GlobalVar.pending_player_selection.duplicate(true)
	var player := load("res://character/player.tscn").instantiate() as GamePlayer
	if player == null:
		push_error("地图初始化完成，但无法创建玩家场景。")
		return null
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.apply_loadout_selection(selection)
	if selection.has("position") and selection["position"] is Vector3:
		player.global_position = selection["position"]
	else:
		player.global_position = get_team_spawn_position(
			str(selection.get("team", "red")),
			0,
			int(selection.get("peer_id", GameAuthority.LOCAL_PLAYER_ID))
		)
	if not GameAuthority.is_client_proxy():
		selection["position"] = player.global_position
		GameAuthority.register_or_update_player(
			int(selection.get("peer_id", GameAuthority.LOCAL_PLAYER_ID)),
			selection
		)
	GlobalVar.pending_player_selection = {}
	return player


func _spawn_singleplayer_future_warrior() -> void:
	# 单人局由本地权威生成一名蓝方敌人。多人局只保留真实玩家，
	# 不在客户端或专用服务器地图中额外生成这名 AI。
	if not GameAuthority.is_local_authority():
		return
	if not get_tree().get_nodes_in_group("future_warrior_ai").is_empty():
		return
	var future_warrior := FUTURE_WARRIOR_AI_SCENE.instantiate() as FutureWarriorAI
	if future_warrior == null:
		push_error("无法实例化 FutureWarriorAI 场景。")
		return
	future_warrior.name = "FutureWarrior_Blue"
	future_warrior.team_id = "blue"
	add_child(future_warrior)
	future_warrior.global_position = get_team_spawn_position(
		"blue",
		1,
		GameAuthority.LOCAL_PLAYER_ID
	)


func _spawn_singleplayer_farmer_ai() -> FarmerAI:
	if not GameAuthority.is_local_authority():
		return null
	if not get_tree().get_nodes_in_group("farmer_ai").is_empty():
		return null
	var farmer := FARMER_AI_SCENE.instantiate() as FarmerAI
	if farmer == null:
		push_error("无法实例化 FarmerAI 场景。")
		return null
	farmer.name = "FarmerAI_Blue"
	farmer.team_id = "blue"
	farmer.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(farmer)
	farmer.global_position = get_team_spawn_position(
		"blue",
		2,
		GameAuthority.LOCAL_PLAYER_ID
	)
	return farmer


func get_team_spawn_position(team: String, player_index := 0, random_seed := 0) -> Vector3:
	var bus_name := "SpawnBlueBus" if team == "blue" else "SpawnRedBus"
	var bus := get_node_or_null(bus_name) as SpawnBus
	if bus == null:
		push_warning("地图缺少出生巴士 %s，使用地图中心作为后备出生点。" % bus_name)
		return Vector3(0.0, 1.5, 0.0)
	return bus.get_spawn_position(player_index, random_seed)


func _set_loading_progress(progress: float, status: String) -> void:
	map_initialization_progress.emit(progress, status)
	MapLoading.update_progress(progress, status)
