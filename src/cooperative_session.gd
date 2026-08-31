extends Node
class_name CooperativeSessionService

## Steam Lobby only discovers/invites players; SteamMultiplayerPeer owns P2P transport.
signal session_started(is_host: bool)
signal session_failed(message: String)
signal world_bootstrap_received(world: Dictionary, selection: Dictionary)
signal peer_joined(peer_id: int, selection: Dictionary)
signal peer_left(peer_id: int)
signal connection_latency_updated(peer_id: int, rtt_ms: float)

const MODE_NONE := "none"
const MODE_HOST := "host"
const MODE_CLIENT := "client"
const DEFAULT_SPAWN := Vector3(0.0, 1.6, 0.0)
const SPAWN_SOURCE_SAVED := "saved_position"
const SPAWN_SOURCE_TEAM := "team_spawn"
const CHUNK_SIZE_METERS := 256.0
const INTEREST_RADIUS_METERS := 1024.0
const WORLD_SAVE_INTERVAL_SECONDS := 10.0
const CARGO_CAR_DEBUG := preload("res://src/cargo_car_debug.gd")
const DROPPED_ITEM_RECONCILE_INTERVAL_SECONDS := 3.0
const CLIENT_CONNECTION_TIMEOUT_SECONDS := 30.0
const RTT_PROBE_INTERVAL_SECONDS := 2.0
const RTT_LOG_INTERVAL_SECONDS := 5.0
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
var pending_join_sessions: Dictionary = {}
var pending_dropped_item_spawns: Dictionary = {}
var pending_dropped_item_removals: Dictionary = {}
var dropped_item_batch_flush_scheduled := false
var world_bootstrap_generation := 0
var threaded_scene_path := ""
var pending_join_token := ""
var client_scene_ready_sent := false
var client_world_state_received := false
var client_spawn_position_received := false
var client_world_ready_sent := false
var client_bootstrap_completing := false
var client_connection_elapsed := 0.0
var client_transport_ready := false
var rtt_probe_accumulator := 0.0
var rtt_probe_sequence := 0
var rtt_probe_sent_msec: Dictionary = {}
var peer_rtt_ms: Dictionary = {}
var last_rtt_ms := 0.0
var rtt_last_log_msec := 0


func is_active() -> bool:
	return mode != MODE_NONE and multiplayer.multiplayer_peer != null


func is_host() -> bool:
	return mode == MODE_HOST


func is_client() -> bool:
	return mode == MODE_CLIENT


func is_transport_connected() -> bool:
	return _is_client_transport_connected() if is_client() else is_active()


func get_last_rtt_ms() -> float:
	return last_rtt_ms


func get_peer_rtt_ms(peer_id: int) -> float:
	return float(peer_rtt_ms.get(peer_id, 0.0))


func get_peer_rtt_snapshot() -> Dictionary:
	return peer_rtt_ms.duplicate(true)


func get_death_drop_mode() -> String:
	var configured := str(active_world.get("death_drop_mode", "save")).to_lower()
	return configured if configured in ["all", "random", "save"] else "save"


func _ready() -> void:
	get_tree().scene_changed.connect(_on_scene_changed)
	SteamService.cooperative_lobby_closed.connect(_on_cooperative_lobby_closed)


func _process(delta: float) -> void:
	_process_client_transport(delta)
	_process_rtt_probes(delta)
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


func request_immediate_save() -> void:
	if not is_host() or active_world.is_empty() or world_loading:
		return
	# Garage mutations happen on the authority tick. Defer the disk write until
	# the current signal chain has finished, while retaining the in-memory state
	# if the atomic write fails; the normal periodic save will retry it.
	call_deferred("_save_authoritative_world_state")


func start_host(world: Dictionary, selection: Dictionary) -> bool:
	if not SteamService.initialized or not SteamService.is_current_lobby_host():
		session_failed.emit("只有已建立 Steam Lobby 的房主可以启动合作世界。")
		return false
	if is_active() or peer != null:
		session_failed.emit("合作世界正在启动或已经运行，请勿重复启动。")
		return false
	if world.is_empty() or selection.is_empty():
		session_failed.emit("合作世界或房主角色档案无效。")
		return false
	# Steam Lobby 只承载地图和房间元数据。准备室从 Lobby 读取的 world
	# 不包含 world_state/team_storage；房主必须按 world_id 从本地存档重新
	# 读取完整权威世界，不能把 Lobby 元数据当成存档本体。
	var persisted_world := CooperativeWorldStorage.load_world(str(world.get("world_id", "")))
	if not persisted_world.is_empty():
		world = persisted_world
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
	# The lobby is only the discovery/invite layer. Using host_with_lobby()
	# makes the extension call add_peer() for every LobbyChatUpdate member,
	# including stale or already-closed Steam connections. A plain host accepts
	# incoming SteamNet connections without that race.
	var error := steam_peer.create_host(0)
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
		_discard_peer(steam_peer)
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
	# The host owns the first team-spawn slot. A saved position, when present,
	# still takes precedence over this slot during world bootstrap.
	_mark_selection_spawn_source(local_selection)
	local_selection["spawn_index"] = 0
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
	pending_join_sessions.clear()
	pending_join_token = ""
	client_scene_ready_sent = false
	client_world_state_received = false
	client_spawn_position_received = false
	client_world_ready_sent = false
	client_bootstrap_completing = false
	joined_players[int(local_selection["peer_id"])] = local_selection.duplicate(true)
	GameAuthority.start_server_mode(self)
	WorldPersistence.apply_world_clock_state(active_world)
	GameAuthority.set_physics_process(false)
	_connect_multiplayer_signals()
	_connect_authority_signals()
	# 不要在世界状态恢复前写回存档。start_server_mode() 会先把全局
	# 队伍库存重置为初始值；此时保存会把已有存档的资金/库存覆盖掉。
	# 成功恢复并完成权威端初始化后再进行首次保存。
	# Keep the lobby in a non-running state while the host prepares the map.
	# Clients must not create a SteamMultiplayerPeer until the host is ready.
	SteamService.set_cooperative_world_starting()
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
	if not SteamService.is_cooperative_world_running():
		session_failed.emit("房主还在准备合作世界，请稍候再加入。")
		return false
	if is_active() or peer != null:
		session_failed.emit("合作世界连接正在建立，请勿重复加入。")
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
	var host_steam_id := SteamService.cooperative_lobby_host_steam_id
	if host_steam_id <= 0:
		host_steam_id = Steam.getLobbyOwner(SteamService.cooperative_lobby_id)
	if host_steam_id <= 0:
		session_failed.emit("无法读取 Steam 合作房主身份。")
		return false
	var steam_peer := SteamMultiplayerPeer.new()
	# Connect directly to the Lobby owner. Lobby membership has already been
	# validated above; the transport itself should not auto-add Lobby members.
	var error := steam_peer.create_client(host_steam_id, 0)
	if error != OK:
		session_failed.emit("连接 Steam P2P 房主失败，错误码：%d。" % error)
		return false
	peer = steam_peer
	multiplayer.multiplayer_peer = peer
	mode = MODE_CLIENT
	_begin_client_connection_tracking()
	_set_pve_event_system_enabled(false)
	active_world = world.duplicate(true)
	world_state_restored = false
	authority_ready = false
	pending_join_requests.clear()
	pending_join_sessions.clear()
	pending_join_token = _make_join_token()
	client_scene_ready_sent = false
	client_world_state_received = false
	client_spawn_position_received = false
	client_world_ready_sent = false
	client_bootstrap_completing = false
	local_selection = _normalize_selection(profile, 0)
	_connect_multiplayer_signals()
	GameAuthority.start_client_mode()
	WorldPersistence.apply_world_clock_state(active_world)
	GameAuthority.set_physics_process(false)
	session_started.emit(false)
	return true


func stop_session(save_host := true) -> void:
	var was_host := is_host()
	if save_host and was_host and not active_world.is_empty():
		_save_authoritative_world_state()
	var old_peer := peer
	var old_multiplayer_peer := multiplayer.multiplayer_peer
	# Detach the peer and clear the mode before closing the native connection.
	# Steam may dispatch a connection callback during close(); it must not be
	# routed through the old session or race with a newly created peer.
	peer = null
	mode = MODE_NONE
	if old_multiplayer_peer == old_peer:
		multiplayer.multiplayer_peer = null
	if old_peer != null:
		_discard_peer(old_peer)
	joined_players.clear()
	active_world.clear()
	local_selection.clear()
	pending_join_requests.clear()
	pending_join_sessions.clear()
	pending_join_token = ""
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
	client_scene_ready_sent = false
	client_world_state_received = false
	client_spawn_position_received = false
	client_world_ready_sent = false
	client_bootstrap_completing = false
	_reset_client_connection_tracking()
	GlobalVar.pending_player_selection = {}
	if is_instance_valid(MapLoading) and MapLoading.has_method("cancel_loading"):
		MapLoading.cancel_loading()
	_set_pve_event_system_enabled(true)
	if GameAuthority.is_server_authority() or GameAuthority.is_client_proxy():
		GameAuthority.stop_authority()


func return_to_main_menu() -> bool:
	if not is_active():
		return false
	if is_host() and not active_world.is_empty() and not save_game():
		return false
	var was_lobby_host := SteamService.is_current_lobby_host()
	stop_session(false)
	# The session has already released its peer. Suppress the local Lobby-close
	# callback because this path owns the transition to the main menu; otherwise
	# the generic callback would reopen the cooperative-world selector.
	SteamService.leave_cooperative_lobby(was_lobby_host)
	return true


func _discard_peer(peer_to_close: MultiplayerPeer, suspend_steam_callbacks := true) -> void:
	if peer_to_close == null:
		return
	if suspend_steam_callbacks:
		SteamService.suspend_callbacks(2)
	if multiplayer.multiplayer_peer == peer_to_close:
		multiplayer.multiplayer_peer = null
	peer_to_close.close()


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


func _begin_client_connection_tracking() -> void:
	client_connection_elapsed = 0.0
	client_transport_ready = false
	rtt_probe_accumulator = 0.0
	rtt_probe_sequence = 0
	rtt_probe_sent_msec.clear()
	peer_rtt_ms.clear()
	last_rtt_ms = 0.0
	rtt_last_log_msec = 0


func _reset_client_connection_tracking() -> void:
	client_connection_elapsed = 0.0
	client_transport_ready = false
	rtt_probe_accumulator = 0.0
	rtt_probe_sent_msec.clear()
	peer_rtt_ms.clear()
	last_rtt_ms = 0.0
	rtt_last_log_msec = 0


func _process_client_transport(delta: float) -> void:
	if not is_client() or peer == null or client_transport_ready:
		return
	var connection_status := peer.get_connection_status()
	if connection_status == MultiplayerPeer.CONNECTION_CONNECTED:
		# The normal connected_to_server signal should call this path, but the
		# status check also covers Steam callbacks that arrive one frame later.
		_on_connected_to_host()
		return
	client_connection_elapsed += delta
	if client_connection_elapsed >= CLIENT_CONNECTION_TIMEOUT_SECONDS:
		_fail_client_connection(
			"Steam P2P 连接超时（30 秒），本次连接已释放；仍在当前 Lobby，可重新点击“进入合作世界”。"
		)


func _process_rtt_probes(delta: float) -> void:
	if not is_client() or not client_transport_ready or not _is_client_transport_connected():
		return
	rtt_probe_accumulator += delta
	if rtt_probe_accumulator < RTT_PROBE_INTERVAL_SECONDS:
		return
	rtt_probe_accumulator = 0.0
	_send_rtt_probe()


func _send_rtt_probe() -> void:
	if not _is_client_transport_connected():
		return
	rtt_probe_sequence += 1
	var probe_id := rtt_probe_sequence
	rtt_probe_sent_msec[probe_id] = Time.get_ticks_msec()
	if rtt_probe_sent_msec.size() > 16:
		rtt_probe_sent_msec.erase(rtt_probe_sequence - 16)
	request_rtt_probe.rpc_id(1, probe_id)


func _is_client_transport_connected() -> bool:
	return is_client() and peer != null \
			and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _fail_client_connection(message: String) -> void:
	if not is_client():
		return
	stop_session()
	session_failed.emit(message)


func _on_connected_to_host() -> void:
	if not is_client() or client_transport_ready or not _is_client_transport_connected():
		return
	client_transport_ready = true
	client_connection_elapsed = 0.0
	print("[CooperativeSession] Steam P2P connected to host")
	var local_peer_id := multiplayer.get_unique_id()
	if local_peer_id > 0:
		local_selection["peer_id"] = local_peer_id
	request_join_world.rpc_id(1, _make_join_request())


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
	pending_join_sessions.erase(peer_id)
	pending_join_requests.erase(peer_id)
	peer_chunk_subscriptions.erase(peer_id)
	GameAuthority.unregister_player(peer_id)
	peer_left.emit(peer_id)
	_save_authoritative_world_state()


func _on_connection_failed() -> void:
	if is_client():
		_fail_client_connection("无法连接 Steam 房主；本次连接已释放，仍在当前 Lobby，可重新尝试。")


func _on_server_disconnected() -> void:
	if is_client():
		_fail_client_connection("Steam 房主已离开合作世界；本次连接已释放。")


func _make_join_token() -> String:
	return "%d-%d-%d" % [Time.get_ticks_usec(), randi(), maxi(1, multiplayer.get_unique_id())]


func _make_join_request() -> Dictionary:
	return {
		"world_id": str(active_world.get("world_id", "")),
		"map_id": str(active_world.get("map_id", "")),
		"map_version": str(active_world.get("map_version", "")),
		"map_hash": str(active_world.get("map_hash", "")),
		"death_drop_mode": get_death_drop_mode(),
		"host_role_identity": active_world.get("host_role_identity", {}).duplicate(true) \
			if active_world.get("host_role_identity", {}) is Dictionary else {},
		"join_token": pending_join_token,
		"profile": local_selection.duplicate(true),
	}


func _make_host_role_identity() -> Dictionary:
	return {
		"steam_id": SteamService.steam_id,
		"display_name": str(local_selection.get("display_name", SteamService.persona_name)),
		"hero_id": str(local_selection.get("hero_id", "farmer")),
		"primary_weapon_ids": local_selection.get("primary_weapon_ids", []).duplicate() \
			if local_selection.get("primary_weapon_ids", []) is Array else [],
		"special_tool_ids": local_selection.get("special_tool_ids", []).duplicate() \
			if local_selection.get("special_tool_ids", []) is Array else [],
	}


func _make_world_manifest(join_token: String) -> Dictionary:
	return {
		"world_id": str(active_world.get("world_id", "")),
		"map_id": str(active_world.get("map_id", "")),
		"map_version": str(active_world.get("map_version", "")),
		"map_hash": str(active_world.get("map_hash", "")),
		"death_drop_mode": get_death_drop_mode(),
		"host_role_identity": _make_host_role_identity(),
		"join_token": join_token,
	}


func _validate_join_request_metadata(request: Dictionary) -> String:
	var expected_world_id := str(active_world.get("world_id", ""))
	if str(request.get("world_id", "")) != expected_world_id:
		return "合作世界存档不匹配，无法加入。"
	for key: String in ["map_id", "map_version", "map_hash"]:
		var expected := str(active_world.get(key, ""))
		var received := str(request.get(key, ""))
		if not expected.is_empty() and received != expected:
			return "加入请求的地图信息与房主不一致。"
	if str(request.get("death_drop_mode", "save")).to_lower() != get_death_drop_mode():
		return "加入请求的死亡掉落规则与房主不一致。"
	return ""


func _reject_join_request(peer_id: int, reason: String, join_token: String) -> void:
	if peer_id <= 0 or not _is_connected_remote_peer(peer_id):
		return
	receive_join_rejected.rpc_id(peer_id, reason, join_token)


func _on_cooperative_lobby_closed(reason: String) -> void:
	if is_host() and not active_world.is_empty():
		save_game()
	stop_session()
	GlobalVar.open_cooperative_worlds_on_main_menu = true
	GlobalVar.cooperative_return_notice = reason
	if get_tree().current_scene != null:
		get_tree().call_deferred("change_scene_to_file", "res://ui/MainMenuRoot.tscn")


@rpc("any_peer", "call_remote", "reliable", 1)
func request_join_world(request: Dictionary) -> void:
	if not is_host():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if world_loading or not authority_ready:
		pending_join_requests[sender_id] = request.duplicate(true)
		return
	_begin_join_request(sender_id, request)


func _begin_join_request(sender_id: int, request: Dictionary) -> void:
	if not is_host() or sender_id <= 0 or not authority_ready:
		return
	if not request is Dictionary:
		_reject_join_request(sender_id, "加入请求格式无效。", "")
		return
	var join_request := request.duplicate(true)
	var join_token := str(join_request.get("join_token", "")).strip_edges()
	if join_token.is_empty():
		_reject_join_request(sender_id, "加入请求缺少本次会话令牌。", "")
		return
	var metadata_error := _validate_join_request_metadata(join_request)
	if not metadata_error.is_empty():
		_reject_join_request(sender_id, metadata_error, join_token)
		return
	var previous_session: Variant = pending_join_sessions.get(sender_id, null)
	if previous_session is Dictionary and str((previous_session as Dictionary).get("join_token", "")) == join_token:
		var previous_manifest: Variant = (previous_session as Dictionary).get("manifest", {})
		var previous_selection: Variant = (previous_session as Dictionary).get("selection", {})
		if previous_manifest is Dictionary and previous_selection is Dictionary:
			receive_world_manifest.rpc_id(sender_id, previous_manifest as Dictionary, previous_selection as Dictionary)
		return
	var profile_value: Variant = join_request.get("profile", {})
	var profile := profile_value as Dictionary if profile_value is Dictionary else {}
	var steam_id := int(profile.get("steam_id", 0))
	if steam_id <= 0:
		_reject_join_request(sender_id, "无法确认加入玩家的 Steam 身份。", join_token)
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
	# Do not invent a position while the map is still loading. The host resolves
	# a team spawn after the map has initialized and sends that final position in
	# the authoritative world-state payload. A missing position therefore means
	# "use a team spawn", never "use a temporary map-origin position".
	_mark_selection_spawn_source(selection)
	selection["spawn_index"] = _allocate_join_spawn_index()
	var manifest := _make_world_manifest(join_token)
	pending_join_sessions[sender_id] = {
		"join_token": join_token,
		"profile": profile.duplicate(true),
		"selection": selection.duplicate(true),
		"manifest": manifest.duplicate(true),
		"scene_ready": false,
		"world_state_sent": false,
		"created_msec": Time.get_ticks_msec(),
	}
	# Only the metadata manifest is sent at this point. The authoritative player
	# registration is deferred until the client has restored the world and sends
	# world_ready.
	receive_world_manifest.rpc_id(sender_id, manifest, selection)


func _accept_join_request(sender_id: int, profile: Dictionary) -> void:
	# Compatibility wrapper for older callers; the new protocol always starts
	# with a metadata request and waits for scene_ready/world_ready.
	_begin_join_request(sender_id, {
		"world_id": active_world.get("world_id", ""),
		"map_id": active_world.get("map_id", ""),
		"map_version": active_world.get("map_version", ""),
		"map_hash": active_world.get("map_hash", ""),
		"death_drop_mode": active_world.get("death_drop_mode", "save"),
		"join_token": _make_join_token(),
		"profile": profile,
	})


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
			_begin_join_request(peer_id, profile as Dictionary)


@rpc("any_peer", "call_remote", "reliable", 1)
func scene_ready(join_token: String, world_id: String, map_id: String, map_version: String, map_hash: String) -> void:
	if not is_host():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var session_value: Variant = pending_join_sessions.get(sender_id, null)
	if not session_value is Dictionary:
		_reject_join_request(sender_id, "房主没有找到对应的加入会话。", join_token)
		return
	var session := session_value as Dictionary
	if str(session.get("join_token", "")) != join_token:
		_reject_join_request(sender_id, "加入会话令牌无效。", join_token)
		return
	if str(active_world.get("world_id", "")) != world_id \
			or str(active_world.get("map_id", "")) != map_id \
			or str(active_world.get("map_version", "")) != map_version \
			or str(active_world.get("map_hash", "")) != map_hash:
		_reject_join_request(sender_id, "客户端加载的地图版本与房主不一致。", join_token)
		return
	if bool(session.get("world_state_sent", false)):
		return
	session["scene_ready"] = true
	pending_join_sessions[sender_id] = session
	_send_world_state_to_peer(sender_id, join_token)


@rpc("any_peer", "call_remote", "reliable", 1)
func world_ready(join_token: String) -> void:
	if not is_host():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var session_value: Variant = pending_join_sessions.get(sender_id, null)
	if not session_value is Dictionary:
		return
	var session := session_value as Dictionary
	if str(session.get("join_token", "")) != join_token \
			or not bool(session.get("scene_ready", false)) \
			or not bool(session.get("world_state_sent", false)):
		return
	_finalize_join_request(sender_id, session)


func _send_world_state_to_peer(peer_id: int, join_token: String) -> void:
	if not is_host() or not _is_connected_remote_peer(peer_id):
		return
	var session_value: Variant = pending_join_sessions.get(peer_id, null)
	if not session_value is Dictionary:
		return
	var session := session_value as Dictionary
	var selection: Dictionary = {}
	var selection_value: Variant = session.get("selection", {})
	if selection_value is Dictionary:
		selection = (selection_value as Dictionary).duplicate(true)
	selection["peer_id"] = peer_id
	selection["team"] = "red"
	# A saved position is used only when the player is not currently respawning.
	# Otherwise, or when the save has no position, resolve the deterministic
	# team-spawn slot now that the host's map is fully initialized.
	if float(selection.get("respawn_left", 0.0)) > 0.0 or not selection.has("position"):
		selection["position"] = _map_spawn_position(
			int(selection.get("spawn_index", 0)), peer_id
		)
	_mark_selection_spawn_source(selection)
	session["selection"] = selection.duplicate(true)
	pending_join_sessions[peer_id] = session
	var current_clock := _capture_current_world_clock()
	var world_state: Dictionary = {}
	var stored_state: Variant = active_world.get("world_state", {})
	if stored_state is Dictionary:
		world_state = (stored_state as Dictionary).duplicate(true)
	# Capture a current authoritative state for a joining client. This keeps a
	# newly opened world correct even before the periodic save has run once.
	if world_state_restored and is_instance_valid(GlobalVar.gameworld):
		world_state = WorldPersistence.capture_world_state()
	# The joining peer must receive the same clock that was sampled for this
	# payload.  Do this even when the host has an older cached world_state: the
	# cached snapshot may predate the latest simulation tick or manual save.
	world_state["world_clock"] = current_clock.duplicate(true)
	active_world["world_state"] = world_state.duplicate(true)
	var current_team_money := float(GlobalVar.check_team_item_amount("red", "money"))
	active_world["team_money"] = current_team_money
	var payload := {
		"world_id": str(active_world.get("world_id", "")),
		"map_id": str(active_world.get("map_id", "")),
		"map_version": str(active_world.get("map_version", "")),
		"map_hash": str(active_world.get("map_hash", "")),
		"death_drop_mode": get_death_drop_mode(),
		"team_money": current_team_money,
		"game_day": int(current_clock.get("game_day", active_world.get("game_day", 1))),
		"world_elapsed_seconds": float(current_clock.get(
			"elapsed_seconds", active_world.get("world_elapsed_seconds", 0.0)
		)),
		"world_clock": current_clock,
		"world_state": world_state,
		"player_selection": selection,
		"state_revision": int(Time.get_ticks_msec()),
		"join_token": join_token,
	}
	receive_world_state.rpc_id(peer_id, payload)
	session["world_state_sent"] = true
	session["state_revision"] = int(payload["state_revision"])
	pending_join_sessions[peer_id] = session


func _finalize_join_request(sender_id: int, session: Dictionary) -> void:
	if not is_host() or sender_id <= 0 or not _is_connected_remote_peer(sender_id):
		return
	var selection_value: Variant = session.get("selection", {})
	if not selection_value is Dictionary:
		return
	var selection := (selection_value as Dictionary).duplicate(true)
	selection["peer_id"] = sender_id
	selection["team"] = "red"
	if float(selection.get("respawn_left", 0.0)) > 0.0 or not selection.has("position"):
		selection["position"] = _map_spawn_position(
			int(selection.get("spawn_index", 0)), sender_id
		)
	_mark_selection_spawn_source(selection)
	joined_players[sender_id] = selection.duplicate(true)
	GameAuthority.register_or_update_player(sender_id, selection)
	_save_joined_player_profile(sender_id, selection)
	_send_dropped_item_snapshot(sender_id)
	pending_join_sessions.erase(sender_id)
	peer_joined.emit(sender_id, selection)
	_save_host_runtime_state()


func submit_action(action_type: String, payload: Dictionary = {}) -> bool:
	# create_client() returns before Steam P2P has reached CONNECTED. Input can
	# already be produced by the local player during that window, so never call
	# rpc_id() against a peer that is still connecting or has been released.
	if not _is_client_transport_connected():
		return false
	if action_type == "ingredient_action" and str(payload.get("station_kind", "")) == "cargo_car":
		CARGO_CAR_DEBUG.log(
			"co-op submit action=%s vehicle_id=%s local_peer=%d"
			% [str(payload.get("action", "")), str(payload.get("vehicle_id", "")), multiplayer.get_unique_id()]
		)
	if UNRELIABLE_ACTION_TYPES.has(action_type):
		request_unreliable_game_action.rpc_id(1, action_type, payload)
	else:
		request_reliable_game_action.rpc_id(1, action_type, payload)
	return true


@rpc("any_peer", "call_remote", "unreliable", 6)
func request_rtt_probe(probe_id: int) -> void:
	if not is_host():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _is_connected_remote_peer(sender_id):
		return
	receive_rtt_probe_response.rpc_id(sender_id, probe_id)


@rpc("authority", "call_remote", "unreliable", 6)
func receive_rtt_probe_response(probe_id: int) -> void:
	if not is_client():
		return
	var sent_value: Variant = rtt_probe_sent_msec.get(probe_id, null)
	if sent_value == null:
		return
	rtt_probe_sent_msec.erase(probe_id)
	last_rtt_ms = maxf(0.0, float(Time.get_ticks_msec() - int(sent_value)))
	peer_rtt_ms[1] = last_rtt_ms
	connection_latency_updated.emit(1, last_rtt_ms)
	if Time.get_ticks_msec() - rtt_last_log_msec >= int(RTT_LOG_INTERVAL_SECONDS * 1000.0):
		rtt_last_log_msec = Time.get_ticks_msec()
		print("[CooperativeRTT] client -> host Steam P2P RTT: %.1f ms" % last_rtt_ms)
	if _is_client_transport_connected():
		report_rtt_probe.rpc_id(1, probe_id, last_rtt_ms)


@rpc("any_peer", "call_remote", "unreliable", 6)
func report_rtt_probe(probe_id: int, rtt_ms: float) -> void:
	if not is_host():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _is_connected_remote_peer(sender_id):
		return
	var measured_rtt := clampf(rtt_ms, 0.0, 60000.0)
	peer_rtt_ms[sender_id] = measured_rtt
	connection_latency_updated.emit(sender_id, measured_rtt)
	if Time.get_ticks_msec() - rtt_last_log_msec >= int(RTT_LOG_INTERVAL_SECONDS * 1000.0):
		rtt_last_log_msec = Time.get_ticks_msec()
		print(
			"[CooperativeRTT] host <- peer=%d Steam P2P RTT reported by client: %.1f ms (probe=%d)"
			% [sender_id, measured_rtt, probe_id]
		)


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
	if action_type == "ingredient_action" and str(payload.get("station_kind", "")) == "cargo_car":
		CARGO_CAR_DEBUG.log(
			"co-op host received action=%s vehicle_id=%s sender=%d"
			% [str(payload.get("action", "")), str(payload.get("vehicle_id", "")), sender_id]
		)
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
		"vehicle_action":
			GameAuthority.server_vehicle_action(sender_id, payload)
		"tool_action":
			GameAuthority.server_tool_action(sender_id, payload)
		"team_chat":
			GameAuthority.server_team_chat(sender_id, str(payload.get("message", "")), str(payload.get("scope", "team")))
		"gate_action":
			GameAuthority.server_gate_action(sender_id, payload)
		"ladder_action":
			GameAuthority.server_ladder_action(sender_id, payload)


@rpc("authority", "call_remote", "reliable", 1)
func receive_world_manifest(manifest: Dictionary, selection: Dictionary) -> void:
	if not is_client():
		return
	var join_token := str(manifest.get("join_token", "")).strip_edges()
	if join_token.is_empty() or join_token != pending_join_token:
		return
	var map_validation := GameMapRegistry.validate_world_map(manifest)
	if not bool(map_validation.get("valid", false)):
		session_failed.emit(str(map_validation.get("error", "本地地图校验失败，无法加入合作世界。")))
		stop_session()
		return
	var local_map: Dictionary = map_validation.get("map", {}) as Dictionary
	var merged_world := active_world.duplicate(true)
	for key: String in ["world_id", "map_id", "map_version", "map_hash", "death_drop_mode"]:
		merged_world[key] = manifest.get(key, merged_world.get(key, ""))
	merged_world["host_role_identity"] = manifest.get("host_role_identity", {})
	if not local_map.is_empty():
		merged_world["map_scene_path"] = str(local_map.get("scene_path", ""))
		merged_world["map_icon_path"] = str(local_map.get("icon_path", ""))
		merged_world["map_name"] = str(local_map.get("display_name", merged_world.get("map_name", "")))
		merged_world["map_source"] = str(local_map.get("source", merged_world.get("map_source", "")))
	active_world = merged_world
	local_selection = _normalize_selection(selection, multiplayer.get_unique_id())
	world_bootstrap_received.emit(active_world, local_selection)
	_load_active_world(local_selection)


@rpc("authority", "call_remote", "reliable", 1)
func receive_join_rejected(reason: String, join_token: String) -> void:
	if not is_client() or (not join_token.is_empty() and join_token != pending_join_token):
		return
	session_failed.emit(reason)
	stop_session()


@rpc("authority", "call_remote", "reliable", 3)
func receive_world_state(payload: Dictionary) -> void:
	if not is_client() or client_world_state_received:
		return
	var join_token := str(payload.get("join_token", "")).strip_edges()
	if join_token.is_empty() or join_token != pending_join_token or not client_scene_ready_sent:
		return
	if str(payload.get("world_id", "")) != str(active_world.get("world_id", "")):
		return
	var selection_value: Variant = payload.get("player_selection", {})
	if not selection_value is Dictionary:
		# Never release the loading screen on a world-state packet that does not
		# include the host's authoritative player selection and spawn position.
		return
	var authoritative_selection := _normalize_selection(
		selection_value as Dictionary,
		multiplayer.get_unique_id()
	)
	var authoritative_position: Variant = authoritative_selection.get("position", null)
	if not authoritative_position is Vector3 or not (authoritative_position as Vector3).is_finite():
		# The client must not fall back to its manifest-time/team-default position;
		# keep loading until the host sends a usable final position.
		return
	var spawn_source := str(authoritative_selection.get("spawn_source", ""))
	if spawn_source not in [SPAWN_SOURCE_SAVED, SPAWN_SOURCE_TEAM]:
		# A position without a source is not enough to decide whether this was the
		# saved location or the host's newly allocated team spawn.
		return
	# The host resolves a no-save joiner's team spawn only after its map is
	# initialized. Replace the manifest-time profile before creating the local
	# player so the first visible frame is already at the final position.
	local_selection = authoritative_selection
	client_spawn_position_received = true
	active_world["world_state"] = payload.get("world_state", {})
	active_world["team_money"] = float(payload.get("team_money", active_world.get("team_money", 0.0)))
	active_world["game_day"] = int(payload.get("game_day", active_world.get("game_day", 1)))
	active_world["world_elapsed_seconds"] = float(
		payload.get("world_elapsed_seconds", active_world.get("world_elapsed_seconds", 0.0))
	)
	var incoming_clock: Variant = payload.get("world_clock", {})
	if incoming_clock is Dictionary:
		active_world["world_clock"] = (incoming_clock as Dictionary).duplicate(true)
	active_world["state_revision"] = int(payload.get("state_revision", 0))
	WorldPersistence.apply_world_clock_state(active_world)
	client_world_state_received = true
	call_deferred("_complete_client_world_bootstrap", get_tree().current_scene, world_bootstrap_generation)


@rpc("authority", "call_remote", "reliable", 3)
func receive_hit_confirmation(event: Dictionary) -> void:
	if not is_client():
		return
	GameAuthority.apply_reliable_world_event(event)
	MultiplayerNetwork.reliable_world_event_received.emit(event)


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
		_send_hit_confirmation_to_peer(int(event.get("attacker_peer_id", 0)), event)
		return
	if event_type == "weapon_ammo_state" or event_type == "action_reward" \
			or event_type == "shield_state":
		_send_reliable_event_to_peer(int(event.get("peer_id", 0)), event)
		return
	if event_type in ["backpack_test_grant", "personal_inventory_grant"]:
		# These events mutate one player's private inventory. They must never be
		# broadcast as a shared world event; station/projectile visuals have their
		# own broadcast paths.
		_send_reliable_event_to_peer(int(event.get("peer_id", 0)), event)
		return
	if event_type == "team_garage_state":
		var garage_team := str(event.get("team", ""))
		for peer_id_value: Variant in joined_players.keys():
			var garage_peer_id := int(peer_id_value)
			if not _is_connected_remote_peer(garage_peer_id):
				continue
			if str((joined_players[garage_peer_id] as Dictionary).get("team", "")) == garage_team:
				_send_reliable_event_to_peer(garage_peer_id, event)
		return
	if event_type == "vehicle_service_state":
		# Terminal occupancy is shared with the players who could actually use the
		# terminal. An empty owner team is the clear/unlock transition (or a neutral
		# map vehicle), so deliver it to every connected client.
		var service_owner_team := str(event.get("owner_team", ""))
		for peer_id_value: Variant in joined_players.keys():
			var service_peer_id := int(peer_id_value)
			if not _is_connected_remote_peer(service_peer_id):
				continue
			var peer_team := str((joined_players[service_peer_id] as Dictionary).get("team", ""))
			if service_owner_team.is_empty() or peer_team == service_owner_team:
				_send_reliable_event_to_peer(service_peer_id, event)
		return
	if event_type == "shop_transaction":
		# Purchase results contain the requester id, transaction id and refund
		# details. They are private even though the purchased vehicle itself is a
		# shared world object.
		var shop_data: Variant = event.get("data", {})
		var shop_peer_id := int((shop_data as Dictionary).get("peer_id", 0)) \
			if shop_data is Dictionary else 0
		_send_reliable_event_to_peer(shop_peer_id, event)
		return
	if event_type == "computer_action_result":
		# Computer action results can contain complete per-app storage. Deliver the
		# result only to its requester; lock changes are broadcast separately as a
		# summary-only computer_state event.
		var computer_data: Variant = event.get("data", {})
		var computer_peer_id := int((computer_data as Dictionary).get("peer_id", 0)) \
			if computer_data is Dictionary else 0
		_send_reliable_event_to_peer(computer_peer_id, event)
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


func _send_hit_confirmation_to_peer(peer_id: int, event: Dictionary) -> void:
	if not _is_connected_remote_peer(peer_id):
		return
	receive_hit_confirmation.rpc_id(peer_id, event)


func _broadcast_visual_event(event: Dictionary) -> void:
	if not is_host():
		return
	# call_remote does not execute on the listen-server host. Feed the same
	# event into the local visual path so the host sees tracers/effects too.
	MultiplayerNetwork.visual_world_event_received.emit(event)
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
	var map_name := str(active_world.get("map_name", "Harvest Operation Map"))
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
	if is_client():
		# The scene, terrain, collision and map initializer are ready, but the
		# client must not fabricate a world state. Tell the host that it is ready
		# to receive the authoritative state over channel 3.
		_send_scene_ready(scene)
		if not client_world_state_received or not client_spawn_position_received:
			if is_instance_valid(MapLoading):
				MapLoading.update_progress(0.82, "地图已加载，正在等待房主发送出生位置")
			return
		call_deferred("_complete_client_world_bootstrap", scene, generation)
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
	WorldPersistence.apply_saved_weather_state(active_world)
	if scene is FarmWorldInitializer and (scene as FarmWorldInitializer).has_method("activate_runtime_entities"):
		(scene as FarmWorldInitializer).activate_runtime_entities()
	_activate_local_player(scene)
	authority_ready = true
	world_loading = false
	GameAuthority.set_physics_process(true)
	if is_host():
		# 此时库存已经从存档恢复，写入当前格式的完整快照，同时迁移旧档。
		_save_authoritative_world_state()
		# Advertise a running world only after scene, terrain/collision, spawn and
		# authority initialization have all completed. This closes the startup
		# window in which a joining client could trigger add_peer() too early.
		SteamService.set_cooperative_world_running()
	_process_pending_join_requests()


func _send_scene_ready(scene: Node3D) -> void:
	if not is_client() or client_scene_ready_sent or pending_join_token.is_empty():
		return
	if not is_instance_valid(scene) or scene != get_tree().current_scene:
		return
	client_scene_ready_sent = true
	scene_ready.rpc_id(
		1,
		pending_join_token,
		str(active_world.get("world_id", "")),
		str(active_world.get("map_id", "")),
		str(active_world.get("map_version", "")),
		str(active_world.get("map_hash", "")),
	)


func _complete_client_world_bootstrap(scene_value: Variant, generation: int) -> void:
	if client_bootstrap_completing or not is_client() or not client_scene_ready_sent \
			or not client_world_state_received or not client_spawn_position_received \
			or not is_instance_valid(scene_value) \
			or not scene_value is Node3D:
		return
	var scene := scene_value as Node3D
	if not is_active() or generation != world_bootstrap_generation \
			or scene != get_tree().current_scene:
		return
	client_bootstrap_completing = true
	if is_instance_valid(MapLoading):
		MapLoading.update_progress(0.84, "正在恢复房主世界状态")
	await _restore_persistent_world_state(scene)
	if not is_active() or generation != world_bootstrap_generation \
			or scene != get_tree().current_scene:
		client_bootstrap_completing = false
		return
	await get_tree().process_frame
	await get_tree().physics_frame
	var spawned := await _spawn_local_player(scene)
	if not spawned:
		client_bootstrap_completing = false
		world_loading = false
		if is_instance_valid(MapLoading) and MapLoading.has_method("cancel_loading"):
			MapLoading.cancel_loading()
		session_failed.emit("合作世界初始化失败：无法完成合作玩家出生定位。")
		return
	await get_tree().process_frame
	await get_tree().physics_frame
	if not _local_player_is_ready(scene):
		client_bootstrap_completing = false
		world_loading = false
		if is_instance_valid(MapLoading) and MapLoading.has_method("cancel_loading"):
			MapLoading.cancel_loading()
		session_failed.emit("合作世界初始化失败：合作玩家出生点或碰撞系统尚未准备完成。")
		return
	if is_instance_valid(MapLoading):
		MapLoading.update_progress(0.98, "世界状态已恢复，正在进入合作世界")
		await MapLoading.finish_loading()
	if not is_active() or generation != world_bootstrap_generation \
			or scene != get_tree().current_scene:
		client_bootstrap_completing = false
		return
	WorldPersistence.apply_saved_weather_state(active_world)
	if scene is FarmWorldInitializer and (scene as FarmWorldInitializer).has_method("activate_runtime_entities"):
		(scene as FarmWorldInitializer).activate_runtime_entities()
	_activate_local_player(scene)
	authority_ready = true
	world_loading = false
	GameAuthority.set_physics_process(true)
	client_bootstrap_completing = false
	if not client_world_ready_sent:
		client_world_ready_sent = true
		world_ready.rpc_id(1, pending_join_token)


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
		if player.has_method("activate_local_runtime"):
			player.call("activate_local_runtime")
		else:
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
	var saved_ammo_states: Variant = local_selection.get("weapon_ammo_states", {})
	if saved_ammo_states is Dictionary and not (saved_ammo_states as Dictionary).is_empty():
		player.apply_weapon_ammo_states_snapshot(saved_ammo_states as Dictionary)
	if local_selection.has("current_hp"):
		player.server_hp = clampf(float(local_selection.get("current_hp", 200.0)), 0.0, 200.0)
		if player.has_method("_update_health_ui"):
			player.call("_update_health_ui")
	var spawn_position := _map_spawn_position(
		int(local_selection.get("spawn_index", 0)),
		int(local_selection.get("peer_id", 0))
	)
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
	return _map_spawn_position(_allocate_join_spawn_index(), peer_id)


func _allocate_join_spawn_index() -> int:
	var used_indices: Dictionary = {}
	for selection_value: Variant in joined_players.values():
		if selection_value is Dictionary and (selection_value as Dictionary).has("spawn_index"):
			used_indices[int((selection_value as Dictionary).get("spawn_index", 0))] = true
	for session_value: Variant in pending_join_sessions.values():
		if not session_value is Dictionary:
			continue
		var selection_value: Variant = (session_value as Dictionary).get("selection", {})
		if selection_value is Dictionary and (selection_value as Dictionary).has("spawn_index"):
			used_indices[int((selection_value as Dictionary).get("spawn_index", 0))] = true
	for index in range(4):
		if not used_indices.has(index):
			return index
	return used_indices.size()


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
	var observer_team := str(player_state.get("team", ""))
	var subscription := _update_chunk_subscription(peer_id, observer_position)
	result["interest_chunk"] = _world_to_chunk(observer_position)
	result["interest_radius_m"] = INTEREST_RADIUS_METERS
	result["subscribed_chunks"] = subscription["active"]
	result["entered_chunks"] = subscription["entered"]
	result["left_chunks"] = subscription["left"]
	# Garage records and terminal occupancy are team-scoped.  They are included in
	# the common world snapshot for low-latency recovery, so filter them here too;
	# filtering only the 1 Hz reliable snapshot would still leak the other team's
	# purchased vehicles during the regular world snapshot path.
	var team_garages_value: Variant = result.get("team_garages", null)
	if team_garages_value is Dictionary:
		var filtered_team_garages := (team_garages_value as Dictionary).duplicate(true)
		for garage_team in ["red", "blue"]:
			if garage_team != observer_team:
				filtered_team_garages.erase(garage_team)
		result["team_garages"] = filtered_team_garages
	var service_terminals_value: Variant = result.get("vehicle_service_terminals", null)
	if service_terminals_value is Array:
		var visible_service_terminals: Array = []
		for terminal_value: Variant in service_terminals_value as Array:
			if not terminal_value is Dictionary:
				continue
			var terminal_state := terminal_value as Dictionary
			var terminal_team := str(terminal_state.get("owner_team", ""))
			if terminal_team.is_empty() or terminal_team == observer_team:
				visible_service_terminals.append(terminal_state)
		result["vehicle_service_terminals"] = visible_service_terminals
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
		var observer_team := str((joined_players.get(peer_id, {}) as Dictionary).get("team", "")) \
			if joined_players.get(peer_id, {}) is Dictionary else ""
		# Team garages are private to teammates. Low-frequency snapshots are
		# tailored per peer, just like the reliable garage-state event, so a
		# snapshot cannot leak the other team's purchased vehicles.
		var team_garages_value: Variant = data.get("team_garages", null)
		if team_garages_value is Dictionary:
			var filtered_team_garages := (team_garages_value as Dictionary).duplicate(true)
			for garage_team in ["red", "blue"]:
				if garage_team != observer_team:
					filtered_team_garages.erase(garage_team)
			data["team_garages"] = filtered_team_garages
		var service_terminals_value: Variant = data.get("vehicle_service_terminals", null)
		if service_terminals_value is Array:
			var visible_service_terminals: Array = []
			for terminal_value: Variant in service_terminals_value as Array:
				if not terminal_value is Dictionary:
					continue
				var terminal_state := terminal_value as Dictionary
				var terminal_team := str(terminal_state.get("owner_team", ""))
				if terminal_team.is_empty() or terminal_team == observer_team:
					visible_service_terminals.append(terminal_state)
			data["vehicle_service_terminals"] = visible_service_terminals
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


func _mark_selection_spawn_source(selection: Dictionary) -> void:
	var position_value: Variant = selection.get("position", null)
	var respawn_left := maxf(0.0, float(selection.get("respawn_left", 0.0)))
	if respawn_left <= 0.0 and position_value is Vector3 \
			and (position_value as Vector3).is_finite():
		selection["spawn_source"] = SPAWN_SOURCE_SAVED
	else:
		selection["spawn_source"] = SPAWN_SOURCE_TEAM


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
		"spawn_index",
		"spawn_source",
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


func _capture_current_world_clock() -> Dictionary:
	var clock := WorldPersistence.capture_world_clock_state()
	active_world["world_clock"] = clock.duplicate(true)
	active_world["world_elapsed_seconds"] = float(
		clock.get("elapsed_seconds", GameAuthority.get_world_elapsed_seconds())
	)
	active_world["game_day"] = int(clock.get("game_day", active_world.get("game_day", 1)))
	return clock


func _save_host_runtime_state() -> void:
	if not is_host() or active_world.is_empty():
		return
	_capture_current_world_clock()
	if world_state_restored or not active_world.has("world_state"):
		active_world["team_money"] = GlobalVar.check_team_item_amount("red", "money")
	for peer_id_value: Variant in joined_players.keys():
		var peer_id := int(peer_id_value)
		_store_player_runtime_state(peer_id, joined_players[peer_id] as Dictionary)
	if world_state_restored and is_instance_valid(GlobalVar.gameworld):
		active_world["world_state"] = WorldPersistence.capture_world_state()
	CooperativeWorldStorage.save_world(active_world)


func _save_authoritative_world_state() -> bool:
	if not is_host() or active_world.is_empty():
		return false
	for peer_id_value: Variant in joined_players.keys():
		var peer_id := int(peer_id_value)
		var selection: Dictionary = joined_players[peer_id]
		_store_player_runtime_state(peer_id, selection)
	active_world["team_money"] = GlobalVar.check_team_item_amount("red", "money")
	_capture_current_world_clock()
	if world_state_restored and is_instance_valid(GlobalVar.gameworld):
		active_world["world_state"] = WorldPersistence.capture_world_state()
	return CooperativeWorldStorage.save_world(active_world)


func _capture_persistent_world_state() -> Dictionary:
	return WorldPersistence.capture_world_state()


func _capture_persistent_station_states() -> Array[Dictionary]:
	var value: Variant = WorldPersistence.call("_capture_station_states")
	return value as Array[Dictionary] if value is Array else []


func _restore_persistent_world_state(scene: Node3D) -> void:
	if world_state_restored or not is_instance_valid(scene) or scene != get_tree().current_scene:
		return
	world_state_restored = await WorldPersistence.restore_world_state(scene, active_world, is_host())


func _vector_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
