extends Node
class_name CooperativeSessionService

## Steam Lobby only discovers/invites players; SteamMultiplayerPeer owns P2P transport.
signal session_started(is_host: bool)
signal session_failed(message: String)
signal world_bootstrap_received(world: Dictionary, selection: Dictionary)
signal peer_joined(peer_id: int, selection: Dictionary)
signal peer_left(peer_id: int)

const MODE_NONE := "none"
const MODE_HOST := "host"
const MODE_CLIENT := "client"
const DEFAULT_SPAWN := Vector3(0.0, 1.6, 0.0)
const CHUNK_SIZE_METERS := 256.0
const INTEREST_RADIUS_METERS := 1024.0
const WORLD_SAVE_INTERVAL_SECONDS := 10.0
const FARM_RESTORE_WAIT_FRAMES := 120
const UNRELIABLE_ACTION_TYPES := {
	"player_input": true,
	"remote_input": true,
	"vehicle_input": true,
}

var mode := MODE_NONE
var peer: MultiplayerPeer
var active_world: Dictionary = {}
var local_selection: Dictionary = {}
var joined_players: Dictionary = {}
var peer_chunk_subscriptions: Dictionary = {}
var world_save_accumulator := 0.0
var world_loading := false
var world_state_restored := false


func is_active() -> bool:
	return mode != MODE_NONE and multiplayer.multiplayer_peer != null


func is_host() -> bool:
	return mode == MODE_HOST


func is_client() -> bool:
	return mode == MODE_CLIENT


func get_death_drop_mode() -> String:
	var configured := str(active_world.get("death_drop_mode", "save")).to_lower()
	return configured if configured in ["all", "random", "save"] else "save"


func _ready() -> void:
	get_tree().scene_changed.connect(_on_scene_changed)
	SteamService.cooperative_lobby_closed.connect(_on_cooperative_lobby_closed)


func _process(delta: float) -> void:
	if not is_host():
		return
	world_save_accumulator += delta
	if world_save_accumulator >= WORLD_SAVE_INTERVAL_SECONDS:
		world_save_accumulator = 0.0
		_save_authoritative_world_state()


func start_host(world: Dictionary, selection: Dictionary) -> bool:
	if not SteamService.initialized or not SteamService.is_current_lobby_host():
		session_failed.emit("只有已建立 Steam Lobby 的房主可以启动合作世界。")
		return false
	if world.is_empty() or selection.is_empty():
		session_failed.emit("合作世界或房主角色档案无效。")
		return false
	stop_session()
	var steam_peer := SteamMultiplayerPeer.new()
	var error := steam_peer.host_with_lobby(SteamService.cooperative_lobby_id)
	if error != OK:
		session_failed.emit("创建 Steam P2P 房主失败，错误码：%d。" % error)
		return false
	peer = steam_peer
	multiplayer.multiplayer_peer = peer
	mode = MODE_HOST
	_set_pve_event_system_enabled(false)
	active_world = world.duplicate(true)
	var host_lock := CooperativeWorldStorage.get_host_loadout_lock(
		str(active_world.get("world_id", "")), SteamService.steam_id
	)
	if host_lock.is_empty():
		host_lock = CooperativeWorldStorage.save_host_loadout_lock(
			str(active_world.get("world_id", "")), SteamService.steam_id, selection
		)
	if host_lock.is_empty():
		session_failed.emit("无法锁定房主的合作角色与初始道具。")
		steam_peer.close()
		multiplayer.multiplayer_peer = null
		peer = null
		mode = MODE_NONE
		return false
	var active_locks: Dictionary = active_world.get("loadout_locks", {})
	active_locks[str(SteamService.steam_id)] = host_lock.duplicate(true)
	active_world["loadout_locks"] = active_locks
	local_selection = _normalize_selection(host_lock, multiplayer.get_unique_id())
	joined_players.clear()
	peer_chunk_subscriptions.clear()
	world_save_accumulator = 0.0
	world_state_restored = false
	joined_players[int(local_selection["peer_id"])] = local_selection.duplicate(true)
	GameAuthority.start_server_mode(self)
	GameAuthority.set_physics_process(false)
	GameAuthority.register_or_update_player(int(local_selection["peer_id"]), local_selection)
	_connect_multiplayer_signals()
	_connect_authority_signals()
	_save_host_runtime_state()
	SteamService.set_cooperative_world_running()
	_load_active_world(local_selection)
	session_started.emit(true)
	return true


func join_hosted_world() -> bool:
	if not SteamService.initialized or SteamService.cooperative_lobby_id <= 0:
		session_failed.emit("请先加入一个 Steam 合作 Lobby。")
		return false
	if SteamService.is_current_lobby_host():
		session_failed.emit("房主应使用“启动世界”，而不是加入客户端会话。")
		return false
	var world := SteamService.get_current_lobby_data()
	var profile := CooperativeWorldStorage.get_local_profile(str(world.get("world_id", "")), SteamService.steam_id)
	if profile.is_empty():
		session_failed.emit("请先完成这个合作世界的首次角色选择。")
		return false
	stop_session()
	var steam_peer := SteamMultiplayerPeer.new()
	var error := steam_peer.connect_to_lobby(SteamService.cooperative_lobby_id)
	if error != OK:
		session_failed.emit("连接 Steam P2P 房主失败，错误码：%d。" % error)
		return false
	peer = steam_peer
	multiplayer.multiplayer_peer = peer
	mode = MODE_CLIENT
	_set_pve_event_system_enabled(false)
	active_world = world.duplicate(true)
	world_state_restored = false
	local_selection = _normalize_selection(profile, 0)
	_connect_multiplayer_signals()
	GameAuthority.start_client_mode()
	GameAuthority.set_physics_process(false)
	session_started.emit(false)
	return true


func stop_session() -> void:
	if multiplayer.multiplayer_peer == peer and peer != null:
		peer.close()
		multiplayer.multiplayer_peer = null
	peer = null
	joined_players.clear()
	active_world.clear()
	local_selection.clear()
	mode = MODE_NONE
	world_loading = false
	world_state_restored = false
	_set_pve_event_system_enabled(true)
	if GameAuthority.is_server_authority() or GameAuthority.is_client_proxy():
		GameAuthority.stop_authority()


func _set_pve_event_system_enabled(enabled: bool) -> void:
	if is_instance_valid(FoodOrderEmitter) and FoodOrderEmitter.has_method("set_runtime_enabled"):
		FoodOrderEmitter.set_runtime_enabled(enabled)
	if is_instance_valid(EventBoard) and EventBoard.has_method("set_emitters_enabled"):
		EventBoard.set_emitters_enabled(enabled)
	if is_instance_valid(RareResourceManager) and RareResourceManager.has_method("set_runtime_enabled"):
		RareResourceManager.set_runtime_enabled(enabled)


func _connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_host):
		multiplayer.connected_to_server.connect(_on_connected_to_host)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _connect_authority_signals() -> void:
	if not GameAuthority.world_snapshot_ready.is_connected(_broadcast_world_snapshot):
		GameAuthority.world_snapshot_ready.connect(_broadcast_world_snapshot)
	if not GameAuthority.inventory_state_ready.is_connected(_broadcast_inventory_state):
		GameAuthority.inventory_state_ready.connect(_broadcast_inventory_state)
	if not GameAuthority.reliable_world_event_ready.is_connected(_broadcast_reliable_event):
		GameAuthority.reliable_world_event_ready.connect(_broadcast_reliable_event)
	if not GameAuthority.visual_world_event_ready.is_connected(_broadcast_visual_event):
		GameAuthority.visual_world_event_ready.connect(_broadcast_visual_event)
	if not GameAuthority.player_correction_ready.is_connected(_broadcast_player_correction):
		GameAuthority.player_correction_ready.connect(_broadcast_player_correction)
	if not GameAuthority.team_chat_message_ready.is_connected(_broadcast_team_chat_message):
		GameAuthority.team_chat_message_ready.connect(_broadcast_team_chat_message)


func _on_connected_to_host() -> void:
	if is_client():
		request_join_world.rpc_id(1, local_selection)


func _on_peer_connected(peer_id: int) -> void:
	if is_host():
		print("[CooperativeSession] Steam peer connected: %d" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host():
		return
	joined_players.erase(peer_id)
	peer_chunk_subscriptions.erase(peer_id)
	GameAuthority.unregister_player(peer_id)
	peer_left.emit(peer_id)
	_save_host_runtime_state()


func _on_connection_failed() -> void:
	if is_client():
		session_failed.emit("无法连接 Steam 房主。")
		stop_session()


func _on_server_disconnected() -> void:
	if is_client():
		session_failed.emit("Steam 房主已离开合作世界。")
		stop_session()


func _on_cooperative_lobby_closed(reason: String) -> void:
	stop_session()
	GlobalVar.open_cooperative_worlds_on_main_menu = true
	GlobalVar.cooperative_return_notice = reason
	if get_tree().current_scene != null:
		get_tree().call_deferred("change_scene_to_file", "res://ui/MainMenuRoot.tscn")


@rpc("any_peer", "reliable")
func request_join_world(profile: Dictionary) -> void:
	if not is_host():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	var steam_id := int(profile.get("steam_id", 0))
	if steam_id <= 0:
		return
	var lock := CooperativeWorldStorage.get_host_loadout_lock(
		str(active_world.get("world_id", "")), steam_id
	)
	if lock.is_empty():
		lock = CooperativeWorldStorage.save_host_loadout_lock(
			str(active_world.get("world_id", "")), steam_id, profile
		)
	if lock.is_empty():
		return
	var locked_selection := lock.duplicate(true)
	locked_selection["display_name"] = str(profile.get("display_name", "Player_%d" % sender_id))
	var selection := _normalize_selection(locked_selection, sender_id)
	selection["team"] = "red"
	selection["position"] = _next_spawn_position(sender_id)
	joined_players[sender_id] = selection.duplicate(true)
	GameAuthority.register_or_update_player(sender_id, selection)
	_save_joined_player_profile(sender_id, selection)
	receive_world_bootstrap.rpc_id(sender_id, active_world, selection)
	peer_joined.emit(sender_id, selection)
	_save_host_runtime_state()


func submit_action(action_type: String, payload: Dictionary = {}) -> void:
	if not is_client():
		return
	if UNRELIABLE_ACTION_TYPES.has(action_type):
		request_unreliable_game_action.rpc_id(1, action_type, payload)
	else:
		request_reliable_game_action.rpc_id(1, action_type, payload)


@rpc("any_peer", "unreliable")
func request_unreliable_game_action(action_type: String, payload: Dictionary) -> void:
	if not UNRELIABLE_ACTION_TYPES.has(action_type):
		return
	_handle_game_action(multiplayer.get_remote_sender_id(), action_type, payload)


@rpc("any_peer", "reliable")
func request_reliable_game_action(action_type: String, payload: Dictionary) -> void:
	if UNRELIABLE_ACTION_TYPES.has(action_type):
		return
	_handle_game_action(multiplayer.get_remote_sender_id(), action_type, payload)


func _handle_game_action(sender_id: int, action_type: String, payload: Dictionary) -> void:
	if not is_host():
		return
	if sender_id <= 0 or not joined_players.has(sender_id):
		return
	match action_type:
		"player_input":
			GameAuthority.server_receive_player_input(sender_id, payload)
		"select_tool":
			GameAuthority.server_select_tool(sender_id, int(payload.get("tool_index", 0)), str(payload.get("tool_id", "")))
		"use_tool":
			GameAuthority.server_try_use_tool(sender_id, payload)
		"reload_weapon":
			GameAuthority.server_reload_weapon(sender_id, str(payload.get("tool_id", "")))
		"shop_transaction":
			GameAuthority.server_shop_transaction(sender_id, payload)
		"farm_action":
			GameAuthority.server_farm_action(sender_id, payload)
		"ingredient_action":
			GameAuthority.server_ingredient_pickup_action(sender_id, payload)
		"remote_input":
			GameAuthority.server_remote_control_input(sender_id, payload)
		"remote_session":
			GameAuthority.server_remote_control_session(sender_id, str(payload.get("device_id", "")), bool(payload.get("connected", false)))
		"remote_action":
			GameAuthority.server_remote_action(sender_id, payload)
		"vehicle_input":
			GameAuthority.server_vehicle_input(sender_id, payload)
		"vehicle_session":
			GameAuthority.server_vehicle_session(sender_id, str(payload.get("vehicle_id", "")), bool(payload.get("connected", false)), int(payload.get("seat_index", -1)))
		"team_chat":
			GameAuthority.server_team_chat(sender_id, str(payload.get("message", "")), str(payload.get("scope", "team")))


@rpc("authority", "reliable")
func receive_world_bootstrap(world: Dictionary, selection: Dictionary) -> void:
	if not is_client():
		return
	active_world = world.duplicate(true)
	local_selection = _normalize_selection(selection, multiplayer.get_unique_id())
	world_bootstrap_received.emit(active_world, local_selection)
	_load_active_world(local_selection)


@rpc("authority", "unreliable")
func receive_world_snapshot(snapshot: Dictionary) -> void:
	if not is_client():
		return
	GameAuthority.apply_world_snapshot(snapshot)
	MultiplayerNetwork.world_snapshot_received.emit(snapshot)


@rpc("authority", "reliable")
func receive_inventory_state(state: Dictionary) -> void:
	if not is_client():
		return
	GameAuthority.apply_inventory_state(state)
	MultiplayerNetwork.inventory_state_received.emit(state)


@rpc("authority", "reliable")
func receive_reliable_event(event: Dictionary) -> void:
	if not is_client():
		return
	GameAuthority.apply_reliable_world_event(event)
	MultiplayerNetwork.reliable_world_event_received.emit(event)


@rpc("authority", "unreliable")
func receive_visual_event(event: Dictionary) -> void:
	if is_client():
		MultiplayerNetwork.visual_world_event_received.emit(event)


@rpc("authority", "unreliable")
func receive_player_correction(correction: Dictionary) -> void:
	if not is_client():
		return
	GameAuthority.apply_player_correction(correction)
	MultiplayerNetwork.player_correction_received.emit(correction)


@rpc("authority", "reliable")
func receive_team_chat_message(message: Dictionary) -> void:
	if is_client():
		MultiplayerNetwork.team_chat_message_received.emit(message)


func _broadcast_world_snapshot(snapshot: Dictionary) -> void:
	if not is_host():
		return
	MultiplayerNetwork.world_snapshot_received.emit(snapshot)
	for peer_id_value: Variant in joined_players.keys():
		var peer_id := int(peer_id_value)
		if _is_connected_remote_peer(peer_id):
			var interest_snapshot := _make_interest_snapshot(peer_id, snapshot)
			var entered_chunks: Variant = interest_snapshot.get("entered_chunks", [])
			if entered_chunks is Array and not (entered_chunks as Array).is_empty():
				_send_farm_chunk_snapshot(peer_id, entered_chunks as Array)
			receive_world_snapshot.rpc_id(peer_id, interest_snapshot)


func _broadcast_inventory_state(state: Dictionary) -> void:
	if is_host():
		receive_inventory_state.rpc(state)


func _broadcast_reliable_event(event: Dictionary) -> void:
	if not is_host():
		return
	MultiplayerNetwork.reliable_world_event_received.emit(event)
	var event_type := str(event.get("type", ""))
	if event_type == "hit_confirmed":
		_send_reliable_event_to_peer(int(event.get("attacker_peer_id", 0)), event)
		return
	if event_type == "weapon_ammo_state" or event_type == "action_reward":
		_send_reliable_event_to_peer(int(event.get("peer_id", 0)), event)
		return
	if event_type in ["cargo_car_action_result", "cargo_crate_action_result"]:
		var action_data: Variant = event.get("data", {})
		var action_peer_id := int((action_data as Dictionary).get("peer_id", 0)) \
			if action_data is Dictionary else int(event.get("peer_id", 0))
		_send_reliable_event_to_peer(action_peer_id, event)
		return
	if event_type in ["cargo_delivery_preview", "cargo_delivery_result"]:
		_send_reliable_event_to_peer(int(event.get("peer_id", 0)), event)
		return
	if event_type == "remote_device_damaged":
		_send_reliable_event_to_peer(int(event.get("controller_peer_id", 0)), event)
		return
	if event_type == "vehicle_damaged":
		var occupants: Variant = event.get("occupant_peer_ids", [])
		if occupants is Array:
			for peer_id_value: Variant in occupants:
				_send_reliable_event_to_peer(int(peer_id_value), event)
		return
	if event_type in ["farm_tile_delta", "farm_tile_deltas", "farm_reconcile_chunk", "low_frequency_snapshot"]:
		for peer_id_value: Variant in joined_players.keys():
			var peer_id := int(peer_id_value)
			if not _is_connected_remote_peer(peer_id):
				continue
			var filtered_event := _filter_interest_reliable_event(peer_id, event)
			if not filtered_event.is_empty():
				receive_reliable_event.rpc_id(peer_id, filtered_event)
		return
	receive_reliable_event.rpc(event)


func _send_reliable_event_to_peer(peer_id: int, event: Dictionary) -> void:
	if not _is_connected_remote_peer(peer_id):
		return
	receive_reliable_event.rpc_id(peer_id, event)


func _broadcast_visual_event(event: Dictionary) -> void:
	if is_host():
		receive_visual_event.rpc(event)


func _broadcast_player_correction(peer_id: int, correction: Dictionary) -> void:
	if not is_host() or not _is_connected_remote_peer(peer_id):
		return
	receive_player_correction.rpc_id(peer_id, correction)


func _broadcast_team_chat_message(message: Dictionary) -> void:
	if not is_host():
		return
	var recipient_peer_id := int(message.get("recipient_peer_id", 0))
	if _is_connected_remote_peer(recipient_peer_id):
		receive_team_chat_message.rpc_id(recipient_peer_id, message)
		return
	for peer_id_value: Variant in joined_players.keys():
		var peer_id := int(peer_id_value)
		if _is_connected_remote_peer(peer_id):
			receive_team_chat_message.rpc_id(peer_id, message)


func _is_connected_remote_peer(peer_id: int) -> bool:
	return peer_id > 0 \
		and peer_id != multiplayer.get_unique_id() \
		and multiplayer.get_peers().has(peer_id)


func _load_active_world(selection: Dictionary) -> void:
	var scene_path := str(active_world.get("map_scene_path", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		session_failed.emit("合作地图不存在：%s" % scene_path)
		return
	world_loading = true
	GameAuthority.prepare_world_transition()
	GlobalVar.gameworld = null
	GlobalVar.pending_player_selection = selection.duplicate(true)
	get_tree().change_scene_to_file(scene_path)


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if not is_active() or local_selection.is_empty() or not scene is Node3D:
		return
	GlobalVar.gameworld = scene as Node3D
	world_loading = false
	GameAuthority.set_physics_process(true)
	call_deferred("_restore_persistent_world_state", scene)
	call_deferred("_spawn_local_player", scene)


func _spawn_local_player(scene: Node3D) -> void:
	if not is_active() or not is_instance_valid(scene) or scene != get_tree().current_scene:
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy:
			return
	if scene.get_node_or_null("CooperativeLocalPlayer") != null:
		return
	var packed := load("res://character/player.tscn") as PackedScene
	if packed == null:
		session_failed.emit("无法加载合作模式玩家场景。")
		return
	var player := packed.instantiate() as GamePlayer
	if player == null:
		session_failed.emit("合作模式玩家场景无效。")
		return
	player.name = "CooperativeLocalPlayer"
	scene.add_child(player)
	player.apply_loadout_selection(local_selection)
	var position_value: Variant = local_selection.get("position", _map_spawn_position(0, int(local_selection.get("peer_id", 0))))
	player.global_position = position_value if position_value is Vector3 else _map_spawn_position(0, int(local_selection.get("peer_id", 0)))


func _next_spawn_position(peer_id: int) -> Vector3:
	return _map_spawn_position(joined_players.size() % 4, peer_id)


func _map_spawn_position(player_index := 0, peer_id := 0) -> Vector3:
	var world := GlobalVar.gameworld
	if world is FarmWorldInitializer:
		return (world as FarmWorldInitializer).get_team_spawn_position("red", player_index, peer_id)
	var scene := get_tree().current_scene
	if scene is FarmWorldInitializer:
		return (scene as FarmWorldInitializer).get_team_spawn_position("red", player_index, peer_id)
	return DEFAULT_SPAWN


func _make_interest_snapshot(peer_id: int, snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate()
	var player_state: Dictionary = GameAuthority.player_states.get(peer_id, {})
	var observer_position := _as_vector3(player_state.get("position", DEFAULT_SPAWN))
	var subscription := _update_chunk_subscription(peer_id, observer_position)
	result["interest_chunk"] = _world_to_chunk(observer_position)
	result["interest_radius_m"] = INTEREST_RADIUS_METERS
	result["subscribed_chunks"] = subscription["active"]
	result["entered_chunks"] = subscription["entered"]
	result["left_chunks"] = subscription["left"]
	for key in ["players", "ai_players", "vehicles", "projectiles", "remote_devices", "placed_tools", "wild_animals"]:
		var value: Variant = snapshot.get(key, [])
		if value is Array:
			result[key] = _filter_interest_entries(value as Array, observer_position)
	result["dropped_items"] = _get_interest_dropped_items(observer_position)
	return result


func _update_chunk_subscription(peer_id: int, observer_position: Vector3) -> Dictionary:
	var active: Array[Vector2i] = []
	var center := _world_to_chunk(observer_position)
	var chunk_radius := ceili(INTEREST_RADIUS_METERS / CHUNK_SIZE_METERS)
	for offset_x in range(-chunk_radius, chunk_radius + 1):
		for offset_z in range(-chunk_radius, chunk_radius + 1):
			var offset_meters := Vector2(float(offset_x) * CHUNK_SIZE_METERS, float(offset_z) * CHUNK_SIZE_METERS)
			if offset_meters.length() <= INTEREST_RADIUS_METERS + CHUNK_SIZE_METERS * 0.72:
				active.append(center + Vector2i(offset_x, offset_z))
	var previous: Array = peer_chunk_subscriptions.get(peer_id, [])
	var entered: Array[Vector2i] = []
	var left: Array[Vector2i] = []
	for chunk in active:
		if not previous.has(chunk):
			entered.append(chunk)
	for chunk_value in previous:
		if chunk_value is Vector2i and not active.has(chunk_value):
			left.append(chunk_value)
	peer_chunk_subscriptions[peer_id] = active.duplicate()
	return {"active": active, "entered": entered, "left": left}


func _send_farm_chunk_snapshot(peer_id: int, chunks: Array) -> void:
	var tiles: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("farm_tiles"):
		if not node is FarmTile:
			continue
		var tile := node as FarmTile
		if chunks.has(_world_to_chunk(tile.global_position)):
			tiles.append(tile.get_authoritative_state())
	if not tiles.is_empty():
		receive_reliable_event.rpc_id(peer_id, {
			"type": "farm_reconcile_chunk",
			"tiles": tiles,
			"tick": GameAuthority.server_tick,
		})


func _get_interest_dropped_items(observer_position: Vector3) -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for pickup_value in GameAuthority.dropped_item_nodes.values():
		if pickup_value is PickupItem and is_instance_valid(pickup_value):
			var state := (pickup_value as PickupItem).get_pickup_state()
			var position: Variant = state.get("position", Vector3.ZERO)
			if position is Vector3 and (position as Vector3).distance_to(observer_position) <= INTEREST_RADIUS_METERS:
				states.append(state)
	return states


func _filter_interest_reliable_event(peer_id: int, event: Dictionary) -> Dictionary:
	var event_type := str(event.get("type", ""))
	var subscription: Array = peer_chunk_subscriptions.get(peer_id, [])
	if event_type == "low_frequency_snapshot":
		var data_value: Variant = event.get("data", {})
		if not data_value is Dictionary:
			return event.duplicate(true)
		var data := (data_value as Dictionary).duplicate(true)
		var observer := _as_vector3((GameAuthority.player_states.get(peer_id, {}) as Dictionary).get("position", DEFAULT_SPAWN))
		var dropped_value: Variant = data.get("dropped_items", [])
		if dropped_value is Array:
			data["dropped_items"] = _filter_interest_entries(dropped_value as Array, observer)
		var filtered_low_frequency := event.duplicate(true)
		filtered_low_frequency["data"] = data
		return filtered_low_frequency
	var tiles_value: Variant = event.get("tiles", [])
	if event_type == "farm_tile_delta":
		tiles_value = [event.get("data", {})]
	if not tiles_value is Array:
		return event.duplicate(true)
	var visible_tiles: Array = []
	for tile_value in tiles_value:
		if not tile_value is Dictionary:
			continue
		var tile_data := tile_value as Dictionary
		var position := _as_vector3(tile_data.get("tile_position", Vector3.ZERO))
		if subscription.has(_world_to_chunk(position)):
			visible_tiles.append(tile_data)
	if visible_tiles.is_empty():
		return {}
	var filtered_event := event.duplicate(true)
	if event_type == "farm_tile_delta":
		filtered_event["data"] = visible_tiles[0]
	else:
		filtered_event["tiles"] = visible_tiles
	return filtered_event


func _filter_interest_entries(entries: Array, observer_position: Vector3) -> Array:
	var visible: Array = []
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var position := _as_vector3(entry.get("position", observer_position))
		if position.distance_to(observer_position) <= INTEREST_RADIUS_METERS:
			visible.append(entry)
	return visible


func _world_to_chunk(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / CHUNK_SIZE_METERS), floori(position.z / CHUNK_SIZE_METERS))


func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and (value as Array).size() >= 3:
		var components := value as Array
		return Vector3(float(components[0]), float(components[1]), float(components[2]))
	return DEFAULT_SPAWN


func _normalize_selection(source: Dictionary, peer_id: int) -> Dictionary:
	var saved_position: Variant = source.get("position", null)
	if saved_position == null:
		saved_position = source.get("last_position", null)
	var normalized := {
		"peer_id": peer_id,
		"steam_id": int(source.get("steam_id", 0)),
		"display_name": str(source.get("display_name", SteamService.persona_name)),
		"team": "red",
		"hero_id": str(source.get("hero_id", "farmer")),
		"primary_weapon_ids": source.get("primary_weapon_ids", []).duplicate(),
		"special_tool_ids": source.get("special_tool_ids", []).duplicate(),
		"ready": true,
	}
	if saved_position is Vector3 or saved_position is Array:
		normalized["position"] = _as_vector3(saved_position)
	return normalized


func _save_joined_player_profile(peer_id: int, selection: Dictionary) -> void:
	if not active_world.is_empty():
		CooperativeWorldStorage.save_host_player_state(str(active_world.get("world_id", "")), peer_id, selection)


func _save_host_runtime_state() -> void:
	if not is_host() or active_world.is_empty():
		return
	if world_state_restored or not active_world.has("world_state"):
		active_world["team_money"] = GlobalVar.check_team_item_amount("red", "money")
	active_world["players"] = joined_players.duplicate(true)
	if world_state_restored and is_instance_valid(GlobalVar.gameworld):
		active_world["world_state"] = _capture_persistent_world_state()
	CooperativeWorldStorage.save_world(active_world)


func _save_authoritative_world_state() -> void:
	if not is_host() or active_world.is_empty():
		return
	var persisted_players: Dictionary = {}
	for peer_id_value: Variant in joined_players.keys():
		var peer_id := int(peer_id_value)
		var selection: Dictionary = joined_players[peer_id]
		var state: Dictionary = GameAuthority.player_states.get(peer_id, {})
		var runtime := selection.duplicate(true)
		runtime["position"] = _vector_to_array(_as_vector3(selection.get("position", DEFAULT_SPAWN)))
		runtime["current_hp"] = float(state.get("hp", 200.0))
		runtime["max_hp"] = 200.0
		runtime["last_position"] = _vector_to_array(_as_vector3(state.get("position", DEFAULT_SPAWN)))
		runtime["backpack_slot_items"] = state.get("backpack_slot_items", [])
		runtime["owned_equipment_ids"] = state.get("owned_equipment_ids", [])
		runtime["equipped_backpack_id"] = str(state.get("equipped_backpack_id", ""))
		runtime["equipped_chest_armor_id"] = str(state.get("equipped_chest_armor_id", ""))
		runtime["equipped_legwear_id"] = str(state.get("equipped_legwear_id", ""))
		persisted_players[str(peer_id)] = runtime
	active_world["players"] = persisted_players
	active_world["team_money"] = GlobalVar.check_team_item_amount("red", "money")
	active_world["world_elapsed_seconds"] = float(active_world.get("world_elapsed_seconds", 0.0)) + WORLD_SAVE_INTERVAL_SECONDS
	active_world["world_state"] = _capture_persistent_world_state()
	CooperativeWorldStorage.save_world(active_world)


func _capture_persistent_world_state() -> Dictionary:
	var farm_tiles: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("farm_tiles"):
		if not node is FarmTile:
			continue
		var tile := node as FarmTile
		var state := tile.get_authoritative_state()
		if not str(state.get("land_owner", "")).is_empty() \
				or not str(state.get("seed_record", "")).is_empty() \
				or bool(state.get("has_tool", false)):
			farm_tiles.append(state)

	var vehicles: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("vehicle_bases"):
		if not node is VehicleBase:
			continue
		var vehicle := node as VehicleBase
		if not vehicle.vehicle_deployed or vehicle.is_queued_for_deletion():
			continue
		var vehicle_id := vehicle.get_vehicle_id()
		var state := vehicle.get_network_state()
		state["vehicle_id"] = vehicle_id
		state["scene_path"] = str(GameAuthority.vehicle_states.get(vehicle_id, {}).get(
			"scene_path", vehicle.scene_file_path
		))
		if str(state["scene_path"]).is_empty() and vehicle_id.contains("cargo_car"):
			state["scene_path"] = "res://vehicles/red_cargo_car.tscn"
		state["driver_peer_id"] = 0
		state["seat_occupants"] = []
		vehicles.append(state)

	var placed_tools: Array[Dictionary] = []
	for state_value: Variant in GameAuthority.placed_tool_states.values():
		if not state_value is Dictionary:
			continue
		var state := (state_value as Dictionary).duplicate(true)
		if bool(state.get("free_placement", false)) \
				or str(state.get("tool_name", "")) == "cargo_crate":
			placed_tools.append(state)
	for node in get_tree().get_nodes_in_group("cargo_crates"):
		if not node is CargoCrateGround:
			continue
		var crate := node as CargoCrateGround
		var crate_id := str(crate.get_meta("network_device_id", crate.get_path()))
		for index in range(placed_tools.size()):
			if str(placed_tools[index].get("tool_id", "")) == crate_id:
				placed_tools[index]["crate_data"] = crate.get_crate_data()
				placed_tools[index]["position"] = crate.global_position
				placed_tools[index]["yaw"] = crate.rotation.y
				break

	var livestock: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("farm_livestock"):
		if not node is FarmLivestock:
			continue
		var animal := node as FarmLivestock
		if not animal.naturally_spawned and not animal.housed_in_chop and not animal.destroyed:
			livestock.append(animal.get_persistent_state())

	return {
		"team_inventory": (GlobalVar.team_storage.get("red", {}) as Dictionary).duplicate(true),
		"farm_tiles": farm_tiles,
		"vehicles": vehicles,
		"placed_tools": placed_tools,
		"livestock": livestock,
		"stations": _capture_persistent_station_states(),
	}


func _capture_persistent_station_states() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var groups := [
		"chopping_stations", "ingredient_extractors", "auto_cookers", "stand_mixers",
		"oven_stations", "smoker_stations", "freezer_stations", "griddle_stations",
		"induction_counters", "plating_stations", "livestock_chops",
	]
	for group_name: String in groups:
		for node in get_tree().get_nodes_in_group(group_name):
			var state: Dictionary = {}
			if node.has_method("get_station_state"):
				state = node.call("get_station_state") as Dictionary
			elif node.has_method("get_extractor_state"):
				state = node.call("get_extractor_state") as Dictionary
			elif node.has_method("get_cook_state"):
				state = node.call("get_cook_state") as Dictionary
			elif node.has_method("get_mixer_state"):
				state = node.call("get_mixer_state") as Dictionary
			elif node.has_method("get_chop_state"):
				state = node.call("get_chop_state") as Dictionary
			if not state.is_empty():
				entries.append({"group": group_name, "state": state})
	return entries


func _restore_persistent_world_state(scene: Node3D) -> void:
	if world_state_restored or not is_instance_valid(scene) or scene != get_tree().current_scene:
		return
	var state_value: Variant = active_world.get("world_state", {})
	if not state_value is Dictionary:
		world_state_restored = true
		return
	var world_state := state_value as Dictionary
	if world_state.is_empty():
		world_state_restored = true
		return
	for _frame in range(FARM_RESTORE_WAIT_FRAMES):
		await get_tree().process_frame
		if _farm_generation_finished(scene):
			break
	if not is_active() or scene != get_tree().current_scene:
		return
	_restore_team_inventory(world_state.get("team_inventory", {}))
	_restore_farm_tiles(world_state.get("farm_tiles", []))
	if is_host():
		_restore_persistent_vehicles(world_state.get("vehicles", []))
		_restore_persistent_tools(world_state.get("placed_tools", []))
		_restore_persistent_livestock(world_state.get("livestock", []))
	_restore_persistent_stations(world_state.get("stations", []))
	world_state_restored = true


func _restore_team_inventory(value: Variant) -> void:
	if not value is Dictionary:
		return
	var saved := value as Dictionary
	var inventory: Dictionary = GlobalVar.team_storage.get("red", {})
	for item_id_value: Variant in saved.keys():
		var item_id := str(item_id_value)
		inventory[item_id] = float(saved[item_id_value])
		GlobalVar.storage_changed.emit("red", item_id, float(inventory[item_id]))
	GlobalVar.team_storage["red"] = inventory


func _farm_generation_finished(scene: Node3D) -> bool:
	var generators := scene.find_children("*", "FarmFieldGenerator", true, false)
	if generators.is_empty():
		return true
	for generator in generators:
		if generator is FarmFieldGenerator and (generator as FarmFieldGenerator).is_generating:
			return false
	return not get_tree().get_nodes_in_group("farm_tiles").is_empty()


func _restore_farm_tiles(value: Variant) -> void:
	if not value is Array:
		return
	for state_value: Variant in value:
		if not state_value is Dictionary:
			continue
		var state := _decode_state_vectors(state_value as Dictionary)
		var tile := _find_farm_tile_for_restore(state)
		if tile != null:
			tile.apply_authoritative_state(state)


func _restore_persistent_vehicles(value: Variant) -> void:
	if not value is Array:
		return
	for state_value: Variant in value:
		if not state_value is Dictionary:
			continue
		var state := _decode_state_vectors(state_value as Dictionary)
		var vehicle_id := str(state.get("vehicle_id", ""))
		var vehicle := _find_vehicle_for_restore(vehicle_id)
		if vehicle == null:
			var scene_path := str(state.get("scene_path", ""))
			var packed := load(scene_path) as PackedScene if not scene_path.is_empty() else null
			vehicle = packed.instantiate() as VehicleBase if packed != null else null
			if vehicle == null:
				continue
			vehicle.name = "Persistent_" + vehicle_id.replace(":", "_")
			vehicle.network_id = vehicle_id
			vehicle.owner_team = str(state.get("owner_team", "red"))
			GlobalVar.gameworld.add_child(vehicle)
			if vehicle.has_method("set_kitchen_team"):
				vehicle.call("set_kitchen_team", vehicle.owner_team)
		state["driver_peer_id"] = 0
		state["seat_occupants"] = []
		vehicle.apply_network_state(state)
		var manifest: Variant = state.get("cargo_manifest", [])
		if manifest is Array:
			vehicle.set_cargo_manifest(manifest as Array)
		GameAuthority.vehicle_states[vehicle_id] = state.duplicate(true)


func _restore_persistent_tools(value: Variant) -> void:
	if not value is Array:
		return
	for state_value: Variant in value:
		if not state_value is Dictionary:
			continue
		var state := _decode_state_vectors(state_value as Dictionary)
		var tool_id := str(state.get("tool_id", state.get("device_id", "")))
		if tool_id.is_empty() or _find_persistent_tool(tool_id) != null:
			continue
		var scene_path := str(state.get("scene_path", ""))
		if str(state.get("tool_name", "")) == "cargo_crate":
			var crate_value: Variant = state.get("crate_data", {})
			if crate_value is Dictionary:
				scene_path = str((crate_value as Dictionary).get("model_path", scene_path))
		var packed := load(scene_path) as PackedScene if not scene_path.is_empty() else null
		var node := packed.instantiate() as Node3D if packed != null else null
		if node == null:
			continue
		node.name = "Persistent_" + tool_id.get_file().replace(":", "_")
		GlobalVar.gameworld.add_child(node)
		node.global_position = _as_vector3(state.get("position", Vector3.ZERO))
		node.rotation.y = float(state.get("yaw", 0.0))
		node.set_meta("network_device_id", tool_id)
		if node is CargoCrateGround:
			var crate_data: Variant = state.get("crate_data", {})
			if crate_data is Dictionary:
				(node as CargoCrateGround).setup_crate(crate_data as Dictionary)
			GameAuthority.register_map_cargo_crate(node as CargoCrateGround)
		else:
			node.set("tool_owner", str(state.get("team", "red")))
			if node is KitchenAppliance:
				(node as KitchenAppliance).owner_team = str(state.get("team", "red"))
			if node.has_method("activate_tool"):
				node.call("activate_tool")
			GameAuthority.register_map_placed_tool(
				node, str(state.get("tool_name", "")), tool_id, str(state.get("team", "red"))
			)
		if node.has_method("apply_network_health"):
			node.call("apply_network_health", float(state.get("hp", 0.0)))
		state["path"] = str(node.get_path())
		GameAuthority.placed_tool_states[tool_id] = state


func _restore_persistent_livestock(value: Variant) -> void:
	if not value is Array:
		return
	for state_value: Variant in value:
		if not state_value is Dictionary:
			continue
		var state := _decode_state_vectors(state_value as Dictionary)
		var animal_id := str(state.get("animal_id", ""))
		if animal_id.is_empty() or _find_livestock_for_restore(animal_id) != null:
			continue
		var scene_path := str(state.get("scene_path", ""))
		var packed := load(scene_path) as PackedScene if not scene_path.is_empty() else null
		var animal := packed.instantiate() as FarmLivestock if packed != null else null
		if animal == null:
			continue
		animal.name = "Persistent_" + animal_id.replace(":", "_")
		animal.animal_id = animal_id
		animal.owner_team = str(state.get("owner_team", "red"))
		animal.initial_hp = float(state.get("current_hp", -1.0))
		animal.initial_growth_progress = float(state.get("growth_progress", 0.0))
		animal.naturally_spawned = false
		GlobalVar.gameworld.add_child(animal)
		animal.global_position = _as_vector3(state.get("position", Vector3.ZERO))
		animal.rotation.y = float(state.get("yaw", 0.0))
		animal.home_position = _as_vector3(state.get("home_position", animal.global_position))


func _restore_persistent_stations(value: Variant) -> void:
	if not value is Array:
		return
	for entry_value: Variant in value:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var state_value: Variant = entry.get("state", {})
		if not state_value is Dictionary:
			continue
		var state := _decode_state_vectors(state_value as Dictionary)
		state["active_user_peer_id"] = 0
		var station := _find_station_for_restore(str(entry.get("group", "")), state)
		if station == null:
			continue
		if station.has_method("apply_authoritative_station_state"):
			station.call("apply_authoritative_station_state", state)
		elif station.has_method("apply_authoritative_extractor_state"):
			station.call("apply_authoritative_extractor_state", state)
		elif station.has_method("apply_authoritative_cook_state"):
			station.call("apply_authoritative_cook_state", state)
		elif station.has_method("apply_authoritative_mixer_state"):
			station.call("apply_authoritative_mixer_state", state)
		elif station.has_method("apply_authoritative_chop_state"):
			station.call("apply_authoritative_chop_state", state)


func _find_farm_tile_for_restore(state: Dictionary) -> FarmTile:
	var path_text := str(state.get("tile_path", ""))
	var direct := get_node_or_null(NodePath(path_text))
	if direct is FarmTile:
		return direct as FarmTile
	var position := _as_vector3(state.get("tile_position", Vector3.ZERO))
	for node in get_tree().get_nodes_in_group("farm_tiles"):
		if node is FarmTile and (node as FarmTile).global_position.distance_to(position) < 0.05:
			return node as FarmTile
	return null


func _find_vehicle_for_restore(vehicle_id: String) -> VehicleBase:
	for node in get_tree().get_nodes_in_group("vehicle_bases"):
		if node is VehicleBase and (node as VehicleBase).get_vehicle_id() == vehicle_id:
			return node as VehicleBase
	return null


func _find_persistent_tool(tool_id: String) -> Node3D:
	for node in get_tree().get_nodes_in_group("network_map_devices"):
		if node is Node3D and str(node.get_meta("network_device_id", "")) == tool_id:
			return node as Node3D
	return null


func _find_livestock_for_restore(animal_id: String) -> FarmLivestock:
	for node in get_tree().get_nodes_in_group("farm_livestock"):
		if node is FarmLivestock and (node as FarmLivestock).animal_id == animal_id:
			return node as FarmLivestock
	return null


func _find_station_for_restore(group_name: String, state: Dictionary) -> Node:
	var path_text := str(state.get("station_path", ""))
	var direct := get_node_or_null(NodePath(path_text))
	if direct != null:
		return direct
	var position := _as_vector3(state.get("station_position", Vector3.ZERO))
	for node in get_tree().get_nodes_in_group(group_name):
		if node is Node3D and (node as Node3D).global_position.distance_to(position) < 0.5:
			return node
	return null


func _decode_state_vectors(source: Dictionary) -> Dictionary:
	var state := source.duplicate(true)
	for key in ["position", "tile_position", "station_position", "home_position"]:
		if state.has(key):
			state[key] = _as_vector3(state[key])
	var crop_positions: Variant = state.get("crop_positions", [])
	if crop_positions is Array:
		var restored_positions: Array = []
		for position_value in crop_positions:
			restored_positions.append(_as_vector3(position_value))
		state["crop_positions"] = restored_positions
	return state


func _vector_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
