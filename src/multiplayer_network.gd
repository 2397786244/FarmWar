extends Node
class_name MultiplayerNetworkManager

signal connection_started(address: String, port: int)
signal connection_succeeded(peer_id: int)
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal status_changed(status: String)
signal server_public_info_received(info: Dictionary)
signal lobby_players_public_info_received(players: Array)
signal match_started_received(info: Dictionary)
signal player_setup_confirmed(selection: Dictionary)
signal player_setup_rejected(reason: String)
signal world_snapshot_received(snapshot: Dictionary)
signal reliable_world_event_received(event: Dictionary)
signal visual_world_event_received(event: Dictionary)
signal inventory_state_received(state: Dictionary)
signal player_correction_received(correction: Dictionary)
signal team_chat_message_received(message: Dictionary)

const STATUS_DISCONNECTED := "disconnected"
const STATUS_CONNECTING := "connecting"
const STATUS_CONNECTED := "connected"

var status := STATUS_DISCONNECTED
var server_address := ""
var server_port := 0
var peer: ENetMultiplayerPeer
var rpc_endpoint: ClientServerRpcEndpoint
var last_rtt_ms := 0.0


func _ready() -> void:
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func connect_to_game_server(address: String, port: int) -> bool:
	address = address.strip_edges()
	if address.is_empty():
		connection_failed.emit("服务器地址不能为空。")
		return false
	if port <= 0 or port > 65535:
		connection_failed.emit("服务器端口必须在 1 到 65535 之间。")
		return false

	disconnect_from_game_server(false)

	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		peer = null
		multiplayer.multiplayer_peer = null
		status = STATUS_DISCONNECTED
		status_changed.emit(status)
		connection_failed.emit("创建 ENet 客户端失败，错误码：%d。" % err)
		return false

	server_address = address
	server_port = port
	status = STATUS_CONNECTING
	_ensure_rpc_endpoint()
	multiplayer.multiplayer_peer = peer
	status_changed.emit(status)
	connection_started.emit(address, port)
	return true


func disconnect_from_game_server(emit_signal := true) -> void:
	_destroy_rpc_endpoint()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peer = null
	server_address = ""
	server_port = 0
	var was_connected_or_connecting := status != STATUS_DISCONNECTED
	status = STATUS_DISCONNECTED
	if GameAuthority.is_client_proxy():
		GameAuthority.stop_authority()
	status_changed.emit(status)
	if emit_signal and was_connected_or_connecting:
		disconnected.emit("已断开服务器连接。")


func is_connected_to_game_server() -> bool:
	return status == STATUS_CONNECTED and multiplayer.multiplayer_peer != null


func is_connecting_to_game_server() -> bool:
	return status == STATUS_CONNECTING


func get_remote_server_text() -> String:
	if server_address.is_empty():
		return ""
	return "%s:%d" % [server_address, server_port]


func submit_player_setup(setup_data: Dictionary) -> void:
	if rpc_endpoint == null or not is_instance_valid(rpc_endpoint):
		push_warning("Cannot submit player setup: RPC endpoint is not ready.")
		return
	rpc_endpoint.submit_player_setup(setup_data)


func submit_player_input(input_frame: Dictionary) -> void:
	if rpc_endpoint == null or not is_instance_valid(rpc_endpoint):
		return
	rpc_endpoint.submit_player_input(input_frame)


func submit_select_tool(tool_index: int, tool_id := "") -> void:
	if rpc_endpoint == null or not is_instance_valid(rpc_endpoint):
		return
	rpc_endpoint.submit_select_tool(tool_index, tool_id)


func submit_use_tool(tool_request: Dictionary) -> void:
	if rpc_endpoint == null or not is_instance_valid(rpc_endpoint):
		return
	rpc_endpoint.submit_use_tool(tool_request)


func submit_reload_weapon(tool_id: String) -> void:
	if rpc_endpoint == null or not is_instance_valid(rpc_endpoint):
		return
	rpc_endpoint.submit_reload_weapon(tool_id)


func submit_shop_transaction(transaction: Dictionary) -> void:
	if rpc_endpoint == null or not is_instance_valid(rpc_endpoint):
		return
	rpc_endpoint.submit_shop_transaction(transaction)


func submit_farm_action(action: Dictionary) -> void:
	if rpc_endpoint == null or not is_instance_valid(rpc_endpoint):
		return
	rpc_endpoint.submit_farm_action(action)


func submit_ingredient_pickup_action(action: Dictionary) -> void:
	if rpc_endpoint == null or not is_instance_valid(rpc_endpoint):
		return
	rpc_endpoint.submit_ingredient_pickup_action(action)


func submit_remote_control_input(input_frame: Dictionary) -> void:
	if rpc_endpoint == null or not is_instance_valid(rpc_endpoint):
		return
	rpc_endpoint.submit_remote_control_input(input_frame)


func submit_remote_control_session(device_id: String, connected: bool) -> void:
	if rpc_endpoint == null or not is_instance_valid(rpc_endpoint):
		return
	rpc_endpoint.submit_remote_control_session(device_id, connected)


func submit_remote_action(action: Dictionary) -> void:
	if rpc_endpoint == null or not is_instance_valid(rpc_endpoint):
		return
	rpc_endpoint.submit_remote_action(action)


func submit_vehicle_input(input_frame: Dictionary) -> void:
	if rpc_endpoint == null or not is_instance_valid(rpc_endpoint):
		return
	rpc_endpoint.submit_vehicle_input(input_frame)


func submit_vehicle_session(vehicle_id: String, connected: bool, seat_index := -1) -> void:
	if rpc_endpoint == null or not is_instance_valid(rpc_endpoint):
		return
	rpc_endpoint.submit_vehicle_session(vehicle_id, connected, seat_index)


func submit_team_chat(message: String, scope := "team") -> void:
	if rpc_endpoint == null or not is_instance_valid(rpc_endpoint):
		return
	rpc_endpoint.submit_team_chat(message, scope)


func get_unique_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


func get_last_rtt_ms() -> float:
	return last_rtt_ms


func _on_connected_to_server() -> void:
	status = STATUS_CONNECTED
	_ensure_rpc_endpoint()
	GameAuthority.start_client_mode()
	status_changed.emit(status)
	connection_succeeded.emit(multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	var failed_address := get_remote_server_text()
	disconnect_from_game_server(false)
	connection_failed.emit("连接服务器失败：%s。" % failed_address)


func _on_server_disconnected() -> void:
	disconnect_from_game_server(false)
	disconnected.emit("服务器已断开连接。")
	call_deferred("_return_to_server_browser_after_disconnect")


func _return_to_server_browser_after_disconnect() -> void:
	if get_tree() == null:
		return
	GlobalVar.open_server_browser_on_main_menu = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://ui/MainMenuRoot.tscn")


func _ensure_rpc_endpoint() -> void:
	if rpc_endpoint != null and is_instance_valid(rpc_endpoint):
		return
	rpc_endpoint = ClientServerRpcEndpoint.new()
	rpc_endpoint.name = "ServerScene"
	rpc_endpoint.server_public_info_received.connect(
		func(info: Dictionary) -> void:
			server_public_info_received.emit(info)
	)
	rpc_endpoint.lobby_players_public_info_received.connect(
		func(players: Array) -> void:
			lobby_players_public_info_received.emit(players)
	)
	rpc_endpoint.match_started_received.connect(
		func(info: Dictionary) -> void:
			match_started_received.emit(info)
	)
	rpc_endpoint.player_setup_confirmed.connect(
		func(selection: Dictionary) -> void:
			player_setup_confirmed.emit(selection)
	)
	rpc_endpoint.player_setup_rejected.connect(
		func(reason: String) -> void:
			player_setup_rejected.emit(reason)
	)
	rpc_endpoint.world_snapshot_received.connect(
		func(snapshot: Dictionary) -> void:
			GameAuthority.apply_world_snapshot(snapshot)
			world_snapshot_received.emit(snapshot)
	)
	rpc_endpoint.reliable_world_event_received.connect(
		func(event: Dictionary) -> void:
			GameAuthority.apply_reliable_world_event(event)
			reliable_world_event_received.emit(event)
	)
	rpc_endpoint.visual_world_event_received.connect(
		func(event: Dictionary) -> void:
			visual_world_event_received.emit(event)
	)
	rpc_endpoint.inventory_state_received.connect(
		func(state: Dictionary) -> void:
			GameAuthority.apply_inventory_state(state)
			inventory_state_received.emit(state)
	)
	rpc_endpoint.player_correction_received.connect(
		func(correction: Dictionary) -> void:
			_update_rtt_from_correction(correction)
			GameAuthority.apply_player_correction(correction)
			player_correction_received.emit(correction)
	)
	rpc_endpoint.team_chat_message_received.connect(
		func(message: Dictionary) -> void:
			team_chat_message_received.emit(message)
	)
	get_tree().root.add_child(rpc_endpoint)


func _destroy_rpc_endpoint() -> void:
	if rpc_endpoint != null and is_instance_valid(rpc_endpoint):
		rpc_endpoint.queue_free()
	rpc_endpoint = null


func _update_rtt_from_correction(correction: Dictionary) -> void:
	var client_msec := int(correction.get("client_time_msec", 0))
	if client_msec <= 0:
		return
	last_rtt_ms = float(Time.get_ticks_msec() - client_msec)
