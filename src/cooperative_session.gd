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
const DROPPED_ITEM_RECONCILE_INTERVAL_SECONDS := 3.0
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
var dropped_item_reconcile_accumulator := 0.0
var world_loading := false
var authority_ready := false
var world_state_restored := false
var pending_join_requests: Dictionary = {}
var pending_dropped_item_spawns: Dictionary = {}
var pending_dropped_item_removals: Dictionary = {}
var dropped_item_batch_flush_scheduled := false
var world_bootstrap_generation := 0
var threaded_scene_path := ""


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
	if not is_host() or world_loading or not authority_ready:
		return
	world_save_accumulator += delta
	dropped_item_reconcile_accumulator += delta
	if dropped_item_reconcile_accumulator >= DROPPED_ITEM_RECONCILE_INTERVAL_SECONDS:
		dropped_item_reconcile_accumulator = 0.0
		_broadcast_dropped_item_snapshots()
	if world_save_accumulator >= WORLD_SAVE_INTERVAL_SECONDS:
		world_save_accumulator = 0.0
		_save_authoritative_world_state()


func save_game() -> bool:
	if not is_host() or active_world.is_empty():
		return false
	return _save_authoritative_world_state()


func start_host(world: Dictionary, selection: Dictionary) -> bool:
	if not SteamService.initialized or not SteamService.is_current_lobby_host():
		session_failed.emit("只有已建立 Steam Lobby 的房主可以启动合作世界。")
		return false
	if world.is_empty() or selection.is_empty():
		session_failed.emit("合作世界或房主角色档案无效。")
		return false
	var host_map_validation := GameMapRegistry.validate_world_map(world)
	if not bool(host_map_validation.get("valid", false)):
		session_failed.emit(str(host_map_validation.get("error", "房主选择的地图不可用。")))
		return false
	var host_map: Dictionary = host_map_validation.get("map", {}) as Dictionary
	if not host_map.is_empty():
		world["map_scene_path"] = str(host_map.get("scene_path", world.get("map_scene_path", "")))
		world["map_icon_path"] = str(host_map.get("icon_path", world.get("map_icon_path", "")))
		world["map_name"] = str(host_map.get("display_name", world.get("map_name", "")))
		world["map_version"] = str(host_map.get("map_version", world.get("map_version", "")))
		world["map_hash"] = str(host_map.get("map_hash", world.get("map_hash", "")))
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
	var saved_host_state := _find_saved_player_state(int(local_selection.get("steam_id", SteamService.steam_id)))
	if not saved_host_state.is_empty():
		local_selection = _normalize_selection(
			_merge_saved_player_state(local_selection, saved_host_state),
			multiplayer.get_unique_id()
		)
	joined_players.clear()
	peer_chunk_subscriptions.clear()
	world_save_accumulator = 0.0
	dropped_item_reconcile_accumulator = 0.0
	pending_dropped_item_spawns.clear()
	pending_dropped_item_removals.clear()
	dropped_item_batch_flush_scheduled = false
	world_state_restored = false
	authority_ready = false
	pending_join_requests.clear()
	joined_players[int(local_selection["peer_id"])] = local_selection.duplicate(true)
	GameAuthority.start_server_mode(self)
	GameAuthority.set_physics_process(false)
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
	var map_validation := GameMapRegistry.validate_world_map(world)
	if not bool(map_validation.get("valid", false)):
		session_failed.emit(str(map_validation.get("error", "本地没有房主选择的地图，无法加入合作世界。")))
		return false
	var local_map: Dictionary = map_validation.get("map", {}) as Dictionary
	if not local_map.is_empty():
		world["map_scene_path"] = str(local_map.get("scene_path", world.get("map_scene_path", "")))
		world["map_icon_path"] = str(local_map.get("icon_path", world.get("map_icon_path", "")))
		world["map_name"] = str(local_map.get("display_name", world.get("map_name", "")))
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
	authority_ready = false
	pending_join_requests.clear()
	local_selection = _normalize_selection(profile, 0)
	_connect_multiplayer_signals()
	GameAuthority.start_client_mode()
	GameAuthority.set_physics_process(false)
	session_started.emit(false)
	return true


func stop_session() -> void:
	if is_host() and not active_world.is_empty():
		_save_authoritative_world_state()
	if multiplayer.multiplayer_peer == peer and peer != null:
		peer.close()
		multiplayer.multiplayer_peer = null
	peer = null
	joined_players.clear()
	active_world.clear()
	local_selection.clear()
	pending_join_requests.clear()
	mode = MODE_NONE
	world_loading = false
	dropped_item_reconcile_accumulator = 0.0
	pending_dropped_item_spawns.clear()
	pending_dropped_item_removals.clear()
	dropped_item_batch_flush_scheduled = false
	authority_ready = false
	world_bootstrap_generation += 1
	threaded_scene_path = ""
	world_state_restored = false
	if is_instance_valid(MapLoading) and MapLoading.has_method("cancel_loading"):
		MapLoading.cancel_loading()
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
		var local_peer_id := multiplayer.get_unique_id()
		if local_peer_id > 0:
			local_selection["peer_id"] = local_peer_id
		request_join_world.rpc_id(1, local_selection)


func _on_peer_connected(peer_id: int) -> void:
	if is_host():
		print("[CooperativeSession] Steam peer connected: %d" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host():
		return
	var leaving_selection: Dictionary = joined_players.get(peer_id, {})
	if not leaving_selection.is_empty():
		_store_player_runtime_state(peer_id, leaving_selection)
	joined_players.erase(peer_id)
	peer_chunk_subscriptions.erase(peer_id)
	GameAuthority.unregister_player(peer_id)
	peer_left.emit(peer_id)
	_save_authoritative_world_state()


func _on_connection_failed() -> void:
	if is_client():
		session_failed.emit("无法连接 Steam 房主。")
		stop_session()


func _on_server_disconnected() -> void:
	if is_client():
		session_failed.emit("Steam 房主已离开合作世界。")
		stop_session()


func _on_cooperative_lobby_closed(reason: String) -> void:
	if is_host() and not active_world.is_empty():
		save_game()
	stop_session()
	GlobalVar.open_cooperative_worlds_on_main_menu = true
	GlobalVar.cooperative_return_notice = reason
	if get_tree().current_scene != null:
		get_tree().call_deferred("change_scene_to_file", "res://ui/MainMenuRoot.tscn")


@rpc("any_peer", "call_remote", "reliable", 1)
func request_join_world(profile: Dictionary) -> void:
	if not is_host():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if world_loading or not authority_ready:
		pending_join_requests[sender_id] = profile.duplicate(true)
		return
	_accept_join_request(sender_id, profile)


func _accept_join_request(sender_id: int, profile: Dictionary) -> void:
	if not is_host() or sender_id <= 0 or not authority_ready:
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
	var saved_player_state := _find_saved_player_state(steam_id)
	if not saved_player_state.is_empty():
		locked_selection = _merge_saved_player_state(locked_selection, saved_player_state)
	locked_selection["display_name"] = str(profile.get("display_name", "Player_%d" % sender_id))
	var selection := _normalize_selection(locked_selection, sender_id)
	selection["team"] = "red"
	if not selection.has("position"):
		selection["position"] = _next_spawn_position(sender_id)
	joined_players[sender_id] = selection.duplicate(true)
	GameAuthority.register_or_update_player(sender_id, selection)
	_save_joined_player_profile(sender_id, selection)
	receive_world_bootstrap.rpc_id(sender_id, active_world, selection)
	_send_dropped_item_snapshot(sender_id)
	peer_joined.emit(sender_id, selection)
	_save_host_runtime_state()


func _process_pending_join_requests() -> void:
	if not is_host() or not authority_ready or world_loading:
		return
	var requests := pending_join_requests.duplicate(true)
	pending_join_requests.clear()
	for peer_id_value: Variant in requests.keys():
		var peer_id := int(peer_id_value)
		if not _is_connected_remote_peer(peer_id):
			continue
		var profile: Variant = requests[peer_id_value]
		if profile is Dictionary:
			_accept_join_request(peer_id, profile as Dictionary)


func submit_action(action_type: String, payload: Dictionary = {}) -> void:
	if not is_client():
		return
	if UNRELIABLE_ACTION_TYPES.has(action_type):
		request_unreliable_game_action.rpc_id(1, action_type, payload)
	else:
		request_reliable_game_action.rpc_id(1, action_type, payload)


@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func request_unreliable_game_action(action_type: String, payload: Dictionary) -> void:
	if not UNRELIABLE_ACTION_TYPES.has(action_type):
		return
	_handle_game_action(multiplayer.get_remote_sender_id(), action_type, payload)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_reliable_game_action(action_type: String, payload: Dictionary) -> void:
	if UNRELIABLE_ACTION_TYPES.has(action_type):
		return
	_handle_game_action(multiplayer.get_remote_sender_id(), action_type, payload)


func _handle_game_action(sender_id: int, action_type: String, payload: Dictionary) -> void:
	if not is_host():
		return
	# The transport sender is the only trusted player identity. Never fall back to
	# a client-provided peer_id: a stale local id (especially the host's id `1`)
	# could otherwise apply a co-op player's inventory or movement request to the
	# host's authoritative state.
	if sender_id <= 0 or not joined_players.has(sender_id):
		return
	match action_type:
		"player_input":
			GameAuthority.server_receive_player_input(sender_id, payload)
		"player_jump":
			GameAuthority.server_receive_player_jump(sender_id, payload)
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


@rpc("authority", "call_remote", "reliable", 0)
func receive_world_bootstrap(world: Dictionary, selection: Dictionary) -> void:
	if not is_client():
		return
	active_world = world.duplicate(true)
	local_selection = _normalize_selection(selection, multiplayer.get_unique_id())
	world_bootstrap_received.emit(active_world, local_selection)
	_load_active_world(local_selection)


@rpc("authority", "call_remote", "unreliable", 0)
func receive_world_snapshot(snapshot: Dictionary) -> void:
	if not is_client():
		return
	GameAuthority.apply_world_snapshot(snapshot)
	MultiplayerNetwork.world_snapshot_received.emit(snapshot)


@rpc("authority", "call_remote", "reliable", 1)
func receive_inventory_state(state: Dictionary) -> void:
	if not is_client():
		return
	GameAuthority.apply_inventory_state(state)
	MultiplayerNetwork.inventory_state_received.emit(state)


@rpc("authority", "call_remote", "reliable", 1)
func receive_reliable_event(event: Dictionary) -> void:
	if not is_client():
		return
	GameAuthority.apply_reliable_world_event(event)
	MultiplayerNetwork.reliable_world_event_received.emit(event)


@rpc("authority", "call_remote", "unreliable", 5)
func receive_visual_event(event: Dictionary) -> void:
	if is_client():
		MultiplayerNetwork.visual_world_event_received.emit(event)


@rpc("authority", "call_remote", "unreliable", 0)
func receive_player_correction(correction: Dictionary) -> void:
	if not is_client():
		return
	GameAuthority.apply_player_correction(correction)
	MultiplayerNetwork.player_correction_received.emit(correction)


@rpc("authority", "call_remote", "reliable", 4)
func receive_team_chat_message(message: Dictionary) -> void:
	if is_client():
		MultiplayerNetwork.team_chat_message_received.emit(message)


@rpc("authority", "call_remote", "reliable", 2)
func receive_bulk_world_event(event: Dictionary) -> void:
	if not is_client():
		return
	GameAuthority.apply_reliable_world_event(event)
	MultiplayerNetwork.reliable_world_event_received.emit(event)


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
	if event_type == "dropped_item_spawned":
		_queue_dropped_item_spawn(event)
		return
	if event_type == "dropped_item_removed":
		_queue_dropped_item_removal(event)
		return
	if event_type == "dropped_items_spawned" or event_type == "dropped_items_removed":
		_broadcast_dropped_item_batch(event)
		return
	if event_type == "hit_confirmed":
		_send_reliable_event_to_peer(int(event.get("attacker_peer_id", 0)), event)
		return
	if event_type == "weapon_ammo_state" or event_type == "action_reward":
		_send_reliable_event_to_peer(int(event.get("peer_id", 0)), event)
		return
	if event_type in ["backpack_test_grant", "personal_inventory_grant"]:
		# These events mutate one player's private inventory. They must never be
		# broadcast as a shared world event; station/projectile visuals have their
		# own broadcast paths.
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
				receive_bulk_world_event.rpc_id(peer_id, filtered_event)
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


func _queue_dropped_item_spawn(event: Dictionary) -> void:
	var state_value: Variant = event.get("item_state", {})
	if not state_value is Dictionary:
		return
	var state := state_value as Dictionary
	var item_id := str(state.get("item_id", ""))
	if item_id.is_empty():
		return
	pending_dropped_item_spawns[item_id] = state.duplicate(true)
	pending_dropped_item_removals.erase(item_id)
	_schedule_dropped_item_batch_flush()


func _queue_dropped_item_removal(event: Dictionary) -> void:
	var item_id := str(event.get("item_id", ""))
	if item_id.is_empty():
		return
	pending_dropped_item_spawns.erase(item_id)
	pending_dropped_item_removals[item_id] = true
	_schedule_dropped_item_batch_flush()


func _schedule_dropped_item_batch_flush() -> void:
	if dropped_item_batch_flush_scheduled:
		return
	dropped_item_batch_flush_scheduled = true
	call_deferred("_flush_dropped_item_batch")


func _flush_dropped_item_batch() -> void:
	dropped_item_batch_flush_scheduled = false
	if not is_host():
		pending_dropped_item_spawns.clear()
		pending_dropped_item_removals.clear()
		return
	var spawn_states: Array[Dictionary] = []
	for state_value: Variant in pending_dropped_item_spawns.values():
		if state_value is Dictionary:
			spawn_states.append((state_value as Dictionary).duplicate(true))
	var removed_ids: Array[String] = []
	for item_id_value: Variant in pending_dropped_item_removals.keys():
		removed_ids.append(str(item_id_value))
	pending_dropped_item_spawns.clear()
	pending_dropped_item_removals.clear()
	if spawn_states.is_empty() and removed_ids.is_empty():
		return
	for peer_id_value: Variant in joined_players.keys():
		var peer_id := int(peer_id_value)
		if not _is_connected_remote_peer(peer_id):
			continue
		var observer := _as_vector3((GameAuthority.player_states.get(peer_id, {}) as Dictionary).get("position", DEFAULT_SPAWN))
		var visible_spawns := _filter_interest_entries(spawn_states, observer)
		if not visible_spawns.is_empty():
			receive_reliable_event.rpc_id(peer_id, {
				"type": "dropped_items_spawned",
				"items": visible_spawns,
				"tick": GameAuthority.server_tick,
			})
		if not removed_ids.is_empty():
			receive_reliable_event.rpc_id(peer_id, {
				"type": "dropped_items_removed",
				"item_ids": removed_ids,
				"tick": GameAuthority.server_tick,
			})


func _broadcast_dropped_item_batch(event: Dictionary) -> void:
	if not is_host():
		return
	var event_type := str(event.get("type", ""))
	for peer_id_value: Variant in joined_players.keys():
		var peer_id := int(peer_id_value)
		if not _is_connected_remote_peer(peer_id):
			continue
		var outgoing := event.duplicate(true)
		if event_type == "dropped_items_spawned":
			var states_value: Variant = event.get("items", [])
			if states_value is Array:
				var observer := _as_vector3((GameAuthority.player_states.get(peer_id, {}) as Dictionary).get("position", DEFAULT_SPAWN))
				outgoing["items"] = _filter_interest_entries(states_value as Array, observer)
				if (outgoing["items"] as Array).is_empty():
					continue
		receive_reliable_event.rpc_id(peer_id, outgoing)


func _broadcast_dropped_item_snapshots() -> void:
	if not is_host():
		return
	for peer_id_value: Variant in joined_players.keys():
		var peer_id := int(peer_id_value)
		if not _is_connected_remote_peer(peer_id):
			continue
		var player_state: Dictionary = GameAuthority.player_states.get(peer_id, {})
		var observer := _as_vector3(player_state.get("position", DEFAULT_SPAWN))
		receive_bulk_world_event.rpc_id(peer_id, {
			"type": "dropped_items_snapshot",
			"items": _get_interest_dropped_items(observer),
			"tick": GameAuthority.server_tick,
		})


func _send_dropped_item_snapshot(peer_id: int) -> void:
	if not is_host() or not _is_connected_remote_peer(peer_id):
		return
	var player_state: Dictionary = GameAuthority.player_states.get(peer_id, {})
	var observer := _as_vector3(player_state.get("position", DEFAULT_SPAWN))
	receive_bulk_world_event.rpc_id(peer_id, {
		"type": "dropped_items_snapshot",
		"items": _get_interest_dropped_items(observer),
		"tick": GameAuthority.server_tick,
	})


func _is_connected_remote_peer(peer_id: int) -> bool:
	return peer_id > 0 \
		and peer_id != multiplayer.get_unique_id() \
		and multiplayer.get_peers().has(peer_id)


func _load_active_world(selection: Dictionary) -> void:
	var scene_path := str(active_world.get("map_scene_path", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		session_failed.emit("合作地图不存在：%s" % scene_path)
		return
	world_bootstrap_generation += 1
	authority_ready = false
	world_loading = true
	var map_name := str(active_world.get("map_name", "FarmWar Map"))
	var loading_images_directory := str(active_world.get("loading_images_directory", ""))
	if loading_images_directory.is_empty():
		var map_id := str(active_world.get("map_id", ""))
		var map_definition := GameMapRegistry.get_map_by_id(map_id)
		loading_images_directory = str(map_definition.get("loading_images_directory", ""))
	if is_instance_valid(MapLoading):
		MapLoading.begin_loading(map_name, loading_images_directory, "res://data/loading_tips.json")
		MapLoading.update_progress(0.02, "正在加载地图场景")
	GameAuthority.prepare_world_transition()
	GameAuthority.set_physics_process(false)
	GlobalVar.gameworld = null
	GlobalVar.pending_player_selection = selection.duplicate(true)
	var error := ResourceLoader.load_threaded_request(scene_path)
	if error != OK:
		world_loading = false
		if is_instance_valid(MapLoading) and MapLoading.has_method("cancel_loading"):
			MapLoading.cancel_loading()
		session_failed.emit("无法开始加载合作地图（错误码：%d）。" % error)
		return
	threaded_scene_path = scene_path
	call_deferred("_load_world_scene_threaded", scene_path, world_bootstrap_generation)


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
				world_loading = false
				if is_instance_valid(MapLoading) and MapLoading.has_method("cancel_loading"):
					MapLoading.cancel_loading()
				session_failed.emit("合作地图资源加载完成，但场景无效。")
				return
			var error := get_tree().change_scene_to_packed(packed)
			if error != OK:
				world_loading = false
				if is_instance_valid(MapLoading) and MapLoading.has_method("cancel_loading"):
					MapLoading.cancel_loading()
				session_failed.emit("无法进入合作地图（错误码：%d）。" % error)
			return
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			threaded_scene_path = ""
			world_loading = false
			if is_instance_valid(MapLoading) and MapLoading.has_method("cancel_loading"):
				MapLoading.cancel_loading()
			session_failed.emit("合作地图资源加载失败。")
			return
		await get_tree().process_frame


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if not is_active() or local_selection.is_empty() or not scene is Node3D:
		return
	GlobalVar.gameworld = scene as Node3D
	world_loading = true
	# Farm terrain and collision are generated asynchronously. Keep the authority
	# tick paused until the local player has been placed on a valid spawn point;
	# otherwise the player physics proxy can fall from the map origin and the
	# subsequent correction appears as a long pull toward the map edge.
	GameAuthority.set_physics_process(false)
	var generation := world_bootstrap_generation
	call_deferred("_bootstrap_loaded_world", scene, generation)


func _bootstrap_loaded_world(scene: Node3D, generation: int) -> void:
	if not is_active() or generation != world_bootstrap_generation \
			or not is_instance_valid(scene) or scene != get_tree().current_scene:
		return
	if is_instance_valid(MapLoading):
		MapLoading.update_progress(0.28, "地图场景已加载，正在初始化地形与碰撞")
	if scene is FarmWorldInitializer:
		await (scene as FarmWorldInitializer).wait_until_initialized()
	if not is_active() or generation != world_bootstrap_generation \
			or scene != get_tree().current_scene:
		return
	if is_instance_valid(MapLoading):
		MapLoading.update_progress(0.78, "正在恢复农田与世界状态")
	await _restore_persistent_world_state(scene)
	if not is_active() or generation != world_bootstrap_generation \
			or scene != get_tree().current_scene:
		return
	await get_tree().process_frame
	await get_tree().physics_frame
	var spawned := await _spawn_local_player(scene)
	if not spawned:
		world_loading = false
		if is_instance_valid(MapLoading) and MapLoading.has_method("cancel_loading"):
			MapLoading.cancel_loading()
		session_failed.emit("合作世界初始化失败：无法完成房主玩家出生定位。")
		return
	await get_tree().process_frame
	await get_tree().physics_frame
	if not _local_player_is_ready(scene):
		world_loading = false
		if is_instance_valid(MapLoading) and MapLoading.has_method("cancel_loading"):
			MapLoading.cancel_loading()
		session_failed.emit("合作世界初始化失败：玩家出生点或碰撞系统尚未准备完成。")
		return
	if is_instance_valid(MapLoading):
		MapLoading.update_progress(0.98, "玩家与权威代理已绑定")
		await MapLoading.finish_loading()
	if not is_active() or generation != world_bootstrap_generation \
			or scene != get_tree().current_scene:
		return
	if scene is FarmWorldInitializer and (scene as FarmWorldInitializer).has_method("activate_runtime_entities"):
		(scene as FarmWorldInitializer).activate_runtime_entities()
	_activate_local_player(scene)
	authority_ready = true
	world_loading = false
	GameAuthority.set_physics_process(true)
	_process_pending_join_requests()


func _local_player_is_ready(scene: Node3D) -> bool:
	for node in get_tree().get_nodes_in_group("human_players"):
		if not node is GamePlayer:
			continue
		var player := node as GamePlayer
		if player.is_remote_proxy or not scene.is_ancestor_of(player):
			continue
		if not player.global_position.is_finite():
			return false
		if is_host():
			var peer_id := int(local_selection.get("peer_id", 0))
			var proxy: Variant = GameAuthority.player_physics_nodes.get(peer_id, null)
			if not proxy is CharacterBody3D or not is_instance_valid(proxy) \
					or not (proxy as CharacterBody3D).is_inside_tree():
				return false
			if (proxy as CharacterBody3D).global_position.distance_to(player.global_position) > 0.05:
				return false
		return true
	return false


func _activate_local_player(scene: Node3D) -> void:
	for node in get_tree().get_nodes_in_group("human_players"):
		if not node is GamePlayer:
			continue
		var player := node as GamePlayer
		if player.is_remote_proxy or not scene.is_ancestor_of(player):
			continue
		player.process_mode = Node.PROCESS_MODE_INHERIT


func _spawn_local_player(scene: Node3D) -> bool:
	if not is_active() or not is_instance_valid(scene) or scene != get_tree().current_scene:
		return false
	var existing_local: GamePlayer = null
	for node in get_tree().get_nodes_in_group("human_players"):
		if not node is GamePlayer or (node as GamePlayer).is_remote_proxy:
			continue
		if not scene.is_ancestor_of(node):
			continue
		if existing_local == null:
			existing_local = node as GamePlayer
		else:
			(node as GamePlayer).queue_free()
	if existing_local != null:
		existing_local.process_mode = Node.PROCESS_MODE_DISABLED
		if scene is FarmWorldInitializer:
			await (scene as FarmWorldInitializer).wait_until_initialized()
		if not is_instance_valid(existing_local) or existing_local.get_parent() != scene:
			return false
		_apply_local_spawn_state(existing_local)
		return true
	var stale_cooperative_player := scene.get_node_or_null("CooperativeLocalPlayer")
	if stale_cooperative_player != null and not stale_cooperative_player is GamePlayer:
		stale_cooperative_player.queue_free()
	var packed := load("res://character/player.tscn") as PackedScene
	if packed == null:
		session_failed.emit("无法加载合作模式玩家场景。")
		return false
	var player := packed.instantiate() as GamePlayer
	if player == null:
		session_failed.emit("合作模式玩家场景无效。")
		return false
	player.name = "CooperativeLocalPlayer"
	player.process_mode = Node.PROCESS_MODE_DISABLED
	scene.add_child(player)
	if scene is FarmWorldInitializer:
		await (scene as FarmWorldInitializer).wait_until_initialized()
	if not is_active() or scene != get_tree().current_scene or not is_instance_valid(player):
		return false
	_apply_local_spawn_state(player)
	return true


func _apply_local_spawn_state(player: GamePlayer) -> void:
	if not is_instance_valid(player):
		return
	player.apply_loadout_selection(local_selection)
	var saved_equipment := {
		"backpack": {
			"equipment_id": str(local_selection.get("equipped_backpack_id", "")),
		},
		"chest_armor": {
			"equipment_id": str(local_selection.get("equipped_chest_armor_id", "")),
		},
		"legwear": {
			"equipment_id": str(local_selection.get("equipped_legwear_id", "")),
		},
	}
	if local_selection.has("equipment_hp") and local_selection.get("equipment_hp") is Dictionary:
		for equipment_type: String in saved_equipment.keys():
			var equipment_id := str((saved_equipment[equipment_type] as Dictionary).get("equipment_id", ""))
			if not equipment_id.is_empty():
				(saved_equipment[equipment_type] as Dictionary)["current_hp"] = float(
					(local_selection.get("equipment_hp") as Dictionary).get(equipment_id, 0.0)
				)
	var saved_backpack := saved_equipment["backpack"] as Dictionary
	var saved_chest_armor := saved_equipment["chest_armor"] as Dictionary
	var saved_legwear := saved_equipment["legwear"] as Dictionary
	if not str(saved_backpack.get("equipment_id", "")).is_empty() \
				or not str(saved_chest_armor.get("equipment_id", "")).is_empty() \
				or not str(saved_legwear.get("equipment_id", "")).is_empty():
		player.apply_equipped_items_snapshot(saved_equipment)
	var saved_slots: Variant = local_selection.get("backpack_slot_items", null)
	if saved_slots is Array and not (saved_slots as Array).is_empty():
		player.apply_cargo_backpack_slots(saved_slots as Array)
	if local_selection.has("current_hp"):
		player.server_hp = clampf(float(local_selection.get("current_hp", 200.0)), 0.0, 200.0)
		if player.has_method("_update_health_ui"):
			player.call("_update_health_ui")
	var spawn_position := _map_spawn_position(0, int(local_selection.get("peer_id", 0)))
	var saved_respawn_left := maxf(0.0, float(local_selection.get("respawn_left", 0.0)))
	var position_value: Variant = local_selection.get("position", null)
	var can_resume_position := saved_respawn_left <= 0.0 and position_value is Vector3
	player.global_position = position_value if can_resume_position else spawn_position
	if saved_respawn_left > 0.0 and player.has_method("apply_respawn_state"):
		player.call("apply_respawn_state", saved_respawn_left)
	local_selection["position"] = player.global_position
	GlobalVar.pending_player_selection = {}
	if is_host():
		GameAuthority.register_or_update_player(int(local_selection.get("peer_id", 0)), local_selection)
	player.process_mode = Node.PROCESS_MODE_DISABLED


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
		receive_bulk_world_event.rpc_id(peer_id, {
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
		data.erase("dropped_items")
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
	for key: String in [
		"backpack_slot_items", "owned_equipment_ids", "equipment_hp",
		"primary_weapon_ids", "special_tool_ids", "weapon_ammo_states",
		"personal_ingredients", "personal_dishes", "personal_dish_weights",
		"personal_cargo_crates",
		"equipped_backpack_id", "equipped_chest_armor_id", "equipped_legwear_id",
		"current_hp", "max_hp", "respawn_left", "current_tool_index", "current_tool_id",
	]:
		if source.has(key):
			var value: Variant = source.get(key)
			normalized[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	if saved_position is Vector3:
		normalized["position"] = _as_vector3(saved_position)
	elif saved_position is Array and (saved_position as Array).size() >= 3:
		normalized["position"] = _as_vector3(saved_position)
	return normalized


func _save_joined_player_profile(peer_id: int, selection: Dictionary) -> void:
	_store_player_runtime_state(peer_id, selection)
	if not active_world.is_empty():
		CooperativeWorldStorage.save_world(active_world)


func _find_saved_player_state(steam_id: int) -> Dictionary:
	if steam_id <= 0:
		return {}
	var players_value: Variant = active_world.get("players", {})
	if not players_value is Dictionary:
		return {}
	for state_value: Variant in (players_value as Dictionary).values():
		if state_value is Dictionary and int((state_value as Dictionary).get("steam_id", 0)) == steam_id:
			return (state_value as Dictionary).duplicate(true)
	return {}


func _merge_saved_player_state(selection: Dictionary, saved_state: Dictionary) -> Dictionary:
	var merged := selection.duplicate(true)
	for key: String in [
		"position", "last_position", "current_hp", "max_hp", "backpack_slot_items",
		"owned_equipment_ids", "equipment_hp", "primary_weapon_ids", "special_tool_ids",
		"weapon_ammo_states", "personal_ingredients", "personal_dishes", "personal_dish_weights",
		"personal_cargo_crates", "equipped_backpack_id", "equipped_chest_armor_id",
		"equipped_legwear_id", "respawn_left", "current_tool_index", "current_tool_id",
	]:
		if saved_state.has(key):
			var value: Variant = saved_state.get(key)
			merged[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return merged


func _store_player_runtime_state(peer_id: int, selection: Dictionary) -> void:
	if not is_host() or active_world.is_empty() or peer_id <= 0:
		return
	var state: Dictionary = GameAuthority.player_states.get(peer_id, {})
	var runtime := selection.duplicate(true)
	runtime["peer_id"] = peer_id
	var steam_id := int(runtime.get("steam_id", 0))
	if steam_id <= 0:
		steam_id = int(state.get("steam_id", 0))
	if steam_id > 0:
		runtime["steam_id"] = steam_id
	runtime["position"] = _vector_to_array(_as_vector3(state.get("position", selection.get("position", DEFAULT_SPAWN))))
	runtime["last_position"] = runtime["position"]
	runtime["current_hp"] = float(state.get("hp", selection.get("current_hp", 200.0)))
	runtime["max_hp"] = float(state.get("max_hp", selection.get("max_hp", 200.0)))
	var slots_value: Variant = state.get("backpack_slot_items", selection.get("backpack_slot_items", []))
	runtime["backpack_slot_items"] = (slots_value as Array).duplicate(true) if slots_value is Array else []
	var equipment_ids_value: Variant = state.get("owned_equipment_ids", selection.get("owned_equipment_ids", []))
	runtime["owned_equipment_ids"] = (equipment_ids_value as Array).duplicate(true) if equipment_ids_value is Array else []
	var equipment_hp_value: Variant = state.get("equipment_hp", selection.get("equipment_hp", {}))
	runtime["equipment_hp"] = (equipment_hp_value as Dictionary).duplicate(true) if equipment_hp_value is Dictionary else {}
	runtime["equipped_backpack_id"] = str(state.get("equipped_backpack_id", selection.get("equipped_backpack_id", "")))
	runtime["equipped_chest_armor_id"] = str(state.get("equipped_chest_armor_id", selection.get("equipped_chest_armor_id", "")))
	runtime["equipped_legwear_id"] = str(state.get("equipped_legwear_id", selection.get("equipped_legwear_id", "")))
	runtime["respawn_left"] = maxf(0.0, float(state.get("respawn_left", selection.get("respawn_left", 0.0))))
	runtime["current_tool_index"] = int(state.get("current_tool_index", selection.get("current_tool_index", 0)))
	runtime["current_tool_id"] = str(state.get("current_tool_id", selection.get("current_tool_id", "")))
	for field_name: String in [
		"primary_weapon_ids", "special_tool_ids", "weapon_ammo_states",
		"personal_ingredients", "personal_dishes", "personal_dish_weights",
		"personal_cargo_crates",
	]:
		var fallback_value: Variant = [] if field_name.ends_with("_ids") or field_name == "personal_cargo_crates" else {}
		var field_value: Variant = state.get(field_name, selection.get(field_name, fallback_value))
		runtime[field_name] = field_value.duplicate(true) if field_value is Array or field_value is Dictionary else field_value
	var players_value: Variant = active_world.get("players", {})
	var players: Dictionary = players_value as Dictionary if players_value is Dictionary else {}
	var storage_key := str(peer_id)
	if steam_id > 0:
		storage_key = str(steam_id)
		for key_value: Variant in players.keys():
			var key := str(key_value)
			if key == storage_key:
				continue
			var other_value: Variant = players[key_value]
			if other_value is Dictionary and int((other_value as Dictionary).get("steam_id", 0)) == steam_id:
				players.erase(key_value)
	players[storage_key] = runtime
	active_world["players"] = players
	if steam_id > 0 and steam_id == int(active_world.get("host_steam_id", 0)):
		var host_summary_value: Variant = active_world.get("host_summary", {})
		var host_summary: Dictionary = host_summary_value as Dictionary if host_summary_value is Dictionary else {}
		host_summary["current_hp"] = runtime["current_hp"]
		host_summary["max_hp"] = runtime["max_hp"]
		host_summary["last_position"] = runtime["last_position"]
		host_summary["location_label"] = "世界内"
		active_world["host_summary"] = host_summary


func _save_host_runtime_state() -> void:
	if not is_host() or active_world.is_empty():
		return
	if world_state_restored or not active_world.has("world_state"):
		active_world["team_money"] = GlobalVar.check_team_item_amount("red", "money")
	for peer_id_value: Variant in joined_players.keys():
		var peer_id := int(peer_id_value)
		_store_player_runtime_state(peer_id, joined_players[peer_id] as Dictionary)
	if world_state_restored and is_instance_valid(GlobalVar.gameworld):
		active_world["world_state"] = _capture_persistent_world_state()
	CooperativeWorldStorage.save_world(active_world)


func _save_authoritative_world_state(advance_elapsed := false) -> bool:
	if not is_host() or active_world.is_empty():
		return false
	for peer_id_value: Variant in joined_players.keys():
		var peer_id := int(peer_id_value)
		var selection: Dictionary = joined_players[peer_id]
		_store_player_runtime_state(peer_id, selection)
	active_world["team_money"] = GlobalVar.check_team_item_amount("red", "money")
	if advance_elapsed:
		active_world["world_elapsed_seconds"] = float(active_world.get("world_elapsed_seconds", 0.0)) + WORLD_SAVE_INTERVAL_SECONDS
	if world_state_restored and is_instance_valid(GlobalVar.gameworld):
		active_world["world_state"] = _capture_persistent_world_state()
	return CooperativeWorldStorage.save_world(active_world)


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
