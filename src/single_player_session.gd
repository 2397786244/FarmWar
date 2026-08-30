extends Node
class_name SinglePlayerSessionService

signal session_started
signal session_failed(message: String)

const DEFAULT_SPAWN := Vector3(0.0, 1.6, 0.0)

var active_world: Dictionary = {}
var local_selection: Dictionary = {}
var world_loading := false
var authority_ready := false
var world_bootstrap_generation := 0
var threaded_scene_path := ""


func _ready() -> void:
	get_tree().scene_changed.connect(_on_scene_changed)


func is_active() -> bool:
	return not active_world.is_empty()


func get_death_drop_mode() -> String:
	return "save"


func start_world(world_id: String) -> bool:
	if is_active() or CooperativeSession.is_active():
		session_failed.emit("已有世界会话正在运行。")
		return false
	var world := SinglePlayerWorldStorage.load_world(world_id)
	if world.is_empty():
		session_failed.emit("单人存档不存在或已损坏。")
		return false
	var validation := GameMapRegistry.validate_world_map(world)
	if not bool(validation.get("valid", false)):
		session_failed.emit(str(validation.get("error", "存档地图不可用。")))
		return false
	var map_definition: Dictionary = validation.get("map", {}) as Dictionary
	if not map_definition.is_empty():
		world["map_scene_path"] = str(map_definition.get("scene_path", world.get("map_scene_path", "")))
		world["map_icon_path"] = str(map_definition.get("icon_path", world.get("map_icon_path", "")))
		world["map_name"] = str(map_definition.get("display_name", world.get("map_name", "")))
		world["map_version"] = str(map_definition.get("map_version", world.get("map_version", "")))
		world["map_hash"] = str(map_definition.get("map_hash", world.get("map_hash", "")))
	var loadout := SinglePlayerWorldStorage.get_loadout_lock(world)
	if loadout.is_empty():
		session_failed.emit("该存档没有有效的角色与初始道具锁定。")
		return false
	var saved_state_value: Variant = world.get("player_state", {})
	var saved_state: Dictionary = saved_state_value as Dictionary if saved_state_value is Dictionary else {}
	local_selection = WorldPersistence.merge_player_state(loadout, saved_state)
	local_selection.merge({
		"peer_id": GameAuthority.LOCAL_PLAYER_ID,
		"display_name": "LocalPlayer",
		"team": "red",
		"ready": true,
		"spawn_index": 0,
	}, true)
	active_world = world.duplicate(true)
	get_tree().set_auto_accept_quit(false)
	SinglePlayerWorldStorage.active_world = active_world.duplicate(true)
	world_bootstrap_generation += 1
	world_loading = true
	authority_ready = false
	GameAuthority.start_local_mode(local_selection)
	WorldPersistence.apply_world_clock_state(active_world)
	GameAuthority.set_physics_process(false)
	session_started.emit()
	return _load_active_world()


func save_game() -> bool:
	if not is_active() or world_loading or not authority_ready:
		return false
	var scene := get_tree().current_scene
	if not scene is Node3D:
		return false
	active_world["player_state"] = WorldPersistence.capture_player_state(
		GameAuthority.LOCAL_PLAYER_ID, local_selection
	)
	active_world["team_storage"] = GlobalVar.team_storage.duplicate(true)
	active_world["team_money"] = float(
		(GlobalVar.team_storage.get("red", {}) as Dictionary).get("money", 0.0)
	)
	var world_state := WorldPersistence.capture_world_state()
	active_world["world_state"] = world_state
	var clock_value: Variant = world_state.get("world_clock", {})
	var clock: Dictionary = clock_value as Dictionary if clock_value is Dictionary else {}
	active_world["world_clock"] = clock.duplicate(true)
	active_world["world_elapsed_seconds"] = float(clock.get(
		"elapsed_seconds", GameAuthority.get_world_elapsed_seconds()
	))
	active_world["game_day"] = int(clock.get(
		"game_day", active_world.get("game_day", 1)
	))
	if not SinglePlayerWorldStorage.save_world(active_world):
		return false
	active_world = SinglePlayerWorldStorage.active_world.duplicate(true)
	return true


func stop_session() -> void:
	active_world.clear()
	local_selection.clear()
	world_loading = false
	authority_ready = false
	world_bootstrap_generation += 1
	threaded_scene_path = ""
	GlobalVar.pending_player_selection = {}
	SinglePlayerWorldStorage.active_world.clear()
	get_tree().set_auto_accept_quit(true)
	if is_instance_valid(MapLoading) and MapLoading.has_method("cancel_loading"):
		MapLoading.cancel_loading()
	if GameAuthority.is_local_authority():
		GameAuthority.stop_authority()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST or not is_inside_tree() or not is_active():
		return
	if not save_game():
		session_failed.emit("单人世界保存失败，已取消关闭。")
		return
	stop_session()
	get_tree().quit()


func _load_active_world() -> bool:
	var scene_path := str(active_world.get("map_scene_path", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		_fail_start("单人存档地图不存在：%s" % scene_path)
		return false
	var map_name := str(active_world.get("map_name", "单人世界"))
	var loading_images_directory := str(active_world.get("loading_images_directory", ""))
	if loading_images_directory.is_empty():
		var map_definition := GameMapRegistry.get_map_by_id(str(active_world.get("map_id", "")))
		loading_images_directory = str(map_definition.get("loading_images_directory", ""))
	if is_instance_valid(MapLoading):
		MapLoading.begin_loading(map_name, loading_images_directory, "res://data/loading_tips.json")
		MapLoading.update_progress(0.02, "正在加载单人世界")
	GameAuthority.prepare_world_transition()
	GlobalVar.gameworld = null
	GlobalVar.pending_player_selection = local_selection.duplicate(true)
	var error := ResourceLoader.load_threaded_request(scene_path)
	if error != OK:
		_fail_start("无法开始加载单人地图（错误码：%d）。" % error)
		return false
	threaded_scene_path = scene_path
	call_deferred("_load_world_scene_threaded", scene_path, world_bootstrap_generation)
	return true


func _load_world_scene_threaded(scene_path: String, generation: int) -> void:
	while is_active() and world_loading and generation == world_bootstrap_generation \
			and threaded_scene_path == scene_path:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
		var resource_progress := float(progress[0]) if not progress.is_empty() else 0.0
		if is_instance_valid(MapLoading):
			MapLoading.update_progress(0.02 + resource_progress * 0.23, "正在加载地图资源")
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(scene_path) as PackedScene
			threaded_scene_path = ""
			if packed == null:
				_fail_start("单人地图场景无效。")
				return
			var error := get_tree().change_scene_to_packed(packed)
			if error != OK:
				_fail_start("无法进入单人地图（错误码：%d）。" % error)
			return
		if status == ResourceLoader.THREAD_LOAD_FAILED \
				or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			threaded_scene_path = ""
			_fail_start("单人地图资源加载失败。")
			return
		await get_tree().process_frame


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if not is_active() or local_selection.is_empty() or not scene is Node3D:
		return
	GlobalVar.gameworld = scene as Node3D
	world_loading = true
	GameAuthority.set_physics_process(false)
	call_deferred("_bootstrap_loaded_world", scene, world_bootstrap_generation)


func _bootstrap_loaded_world(scene: Node3D, generation: int) -> void:
	if not _bootstrap_is_current(scene, generation):
		return
	if is_instance_valid(MapLoading):
		MapLoading.update_progress(0.28, "正在初始化地形与碰撞")
	if scene is FarmWorldInitializer:
		await (scene as FarmWorldInitializer).wait_until_initialized()
	if not _bootstrap_is_current(scene, generation):
		return
	if is_instance_valid(MapLoading):
		MapLoading.update_progress(0.78, "正在恢复世界状态")
	var restored := await WorldPersistence.restore_world_state(scene, active_world)
	if not restored or not _bootstrap_is_current(scene, generation):
		_fail_start("单人世界状态恢复失败。")
		return
	await get_tree().process_frame
	await get_tree().physics_frame
	var player := await _spawn_local_player(scene)
	if player == null or not _bootstrap_is_current(scene, generation):
		_fail_start("无法生成单人玩家。")
		return
	if is_instance_valid(MapLoading):
		MapLoading.update_progress(0.98, "正在进入单人世界")
		await MapLoading.finish_loading()
	if not _bootstrap_is_current(scene, generation):
		return
	WorldPersistence.apply_saved_weather_state(active_world)
	if scene is FarmWorldInitializer and scene.has_method("activate_runtime_entities"):
		scene.call("activate_runtime_entities")
	player.activate_local_runtime()
	authority_ready = true
	world_loading = false
	GameAuthority.set_physics_process(true)


func _spawn_local_player(scene: Node3D) -> GamePlayer:
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and scene.is_ancestor_of(node):
			(node as GamePlayer).queue_free()
	var packed := load("res://character/player.tscn") as PackedScene
	if packed == null:
		return null
	var player := packed.instantiate() as GamePlayer
	if player == null:
		return null
	player.name = "SinglePlayerLocalPlayer"
	player.process_mode = Node.PROCESS_MODE_DISABLED
	scene.add_child(player)
	if scene is FarmWorldInitializer:
		await (scene as FarmWorldInitializer).wait_until_initialized()
	if not is_instance_valid(player) or scene != get_tree().current_scene:
		return null
	var spawn_position := _map_spawn_position(scene)
	WorldPersistence.apply_player_runtime_state(player, local_selection, spawn_position)
	local_selection["position"] = player.global_position
	GlobalVar.pending_player_selection = {}
	GameAuthority.register_or_update_player(GameAuthority.LOCAL_PLAYER_ID, local_selection)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	return player


func _map_spawn_position(scene: Node3D) -> Vector3:
	if scene is FarmWorldInitializer:
		return (scene as FarmWorldInitializer).get_team_spawn_position(
			"red", 0, GameAuthority.LOCAL_PLAYER_ID
		)
	return DEFAULT_SPAWN


func _bootstrap_is_current(scene: Node3D, generation: int) -> bool:
	return is_active() and generation == world_bootstrap_generation \
		and is_instance_valid(scene) and scene == get_tree().current_scene


func _fail_start(message: String) -> void:
	if is_instance_valid(MapLoading) and MapLoading.has_method("cancel_loading"):
		MapLoading.cancel_loading()
	active_world.clear()
	local_selection.clear()
	world_loading = false
	authority_ready = false
	threaded_scene_path = ""
	GlobalVar.pending_player_selection = {}
	SinglePlayerWorldStorage.active_world.clear()
	get_tree().set_auto_accept_quit(true)
	if GameAuthority.is_local_authority():
		GameAuthority.stop_authority()
	session_failed.emit(message)
