extends Node
class_name ClientServerRpcEndpoint

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


func submit_player_setup(setup_data: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		push_warning("Cannot submit player setup before connecting to a server.")
		return
	request_submit_player_setup.rpc_id(1, setup_data)


func submit_player_input(input_frame: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	request_player_input.rpc_id(1, input_frame)


func submit_player_jump(jump_request: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	request_player_jump.rpc_id(1, jump_request)


func submit_select_tool(tool_index: int, tool_id := "") -> void:
	if multiplayer.multiplayer_peer == null:
		return
	request_select_tool.rpc_id(1, tool_index, tool_id)


func submit_use_tool(tool_request: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	request_use_tool.rpc_id(1, tool_request)


func submit_reload_weapon(tool_id: String) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	request_reload_weapon.rpc_id(1, tool_id)


func submit_shop_transaction(transaction: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	request_shop_transaction.rpc_id(1, transaction)


func submit_farm_action(action: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	request_farm_action.rpc_id(1, action)


func submit_ingredient_pickup_action(action: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	request_ingredient_pickup_action.rpc_id(1, action)


func submit_remote_control_input(input_frame: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	request_remote_control_input.rpc_id(1, input_frame)


func submit_remote_control_session(device_id: String, connected: bool) -> void:
	if multiplayer.multiplayer_peer == null or device_id.is_empty():
		return
	request_remote_control_session.rpc_id(1, device_id, connected)


func submit_remote_action(action: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	request_remote_action.rpc_id(1, action)


func submit_vehicle_input(input_frame: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	request_vehicle_input.rpc_id(1, input_frame)


func submit_vehicle_session(vehicle_id: String, connected: bool, seat_index := -1) -> void:
	if multiplayer.multiplayer_peer == null or vehicle_id.is_empty():
		return
	request_vehicle_session.rpc_id(1, vehicle_id, connected, seat_index)


func submit_team_chat(message: String, scope: String) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	request_team_chat.rpc_id(1, message, scope)


@rpc("any_peer", "reliable")
func request_submit_player_setup(_setup_data: Dictionary) -> void:
	# 这个函数在客户端只作为 RPC 路径占位。
	# 真正执行的是服务端同 NodePath 上的 DedicatedServerManager.request_submit_player_setup。
	pass


@rpc("any_peer", "unreliable_ordered")
func request_player_input(_input_frame: Dictionary) -> void:
	pass


@rpc("any_peer", "reliable")
func request_player_jump(_jump_request: Dictionary) -> void:
	pass


@rpc("any_peer", "reliable")
func request_select_tool(_tool_index: int, _tool_id := "") -> void:
	pass


@rpc("any_peer", "reliable")
func request_use_tool(_tool_request: Dictionary) -> void:
	pass


@rpc("any_peer", "reliable")
func request_reload_weapon(_tool_id: String) -> void:
	pass


@rpc("any_peer", "reliable")
func request_shop_transaction(_transaction: Dictionary) -> void:
	pass


@rpc("any_peer", "call_remote", "reliable", 1)
func request_farm_action(_action: Dictionary) -> void:
	pass


@rpc("any_peer", "reliable")
func request_ingredient_pickup_action(_action: Dictionary) -> void:
	pass


@rpc("any_peer", "unreliable")
func request_remote_control_input(_input_frame: Dictionary) -> void:
	pass


@rpc("any_peer", "reliable")
func request_remote_control_session(_device_id: String, _connected: bool) -> void:
	pass


@rpc("any_peer", "reliable")
func request_remote_action(_action: Dictionary) -> void:
	pass


@rpc("any_peer", "unreliable")
func request_vehicle_input(_input_frame: Dictionary) -> void:
	pass


@rpc("any_peer", "reliable")
func request_vehicle_session(_vehicle_id: String, _connected: bool, _seat_index: int = -1) -> void:
	pass


@rpc("any_peer", "call_remote", "reliable", 4)
func request_team_chat(_message: String, _scope: String) -> void:
	pass


@rpc("authority", "reliable")
func receive_server_public_info(info: Dictionary) -> void:
	server_public_info_received.emit(info)


@rpc("authority", "reliable")
func receive_lobby_players_public_info(lobby_players: Array) -> void:
	lobby_players_public_info_received.emit(lobby_players)


@rpc("authority", "reliable")
func receive_match_started(info: Dictionary) -> void:
	match_started_received.emit(info)


@rpc("authority", "reliable")
func receive_player_setup_confirmed(selection: Dictionary) -> void:
	player_setup_confirmed.emit(selection)


@rpc("authority", "reliable")
func receive_player_setup_rejected(reason: String) -> void:
	player_setup_rejected.emit(reason)


@rpc("authority", "unreliable")
func receive_world_snapshot(snapshot: Dictionary) -> void:
	world_snapshot_received.emit(snapshot)


@rpc("authority", "call_remote", "reliable", 1)
func receive_reliable_world_event(event: Dictionary) -> void:
	reliable_world_event_received.emit(event)


@rpc("authority", "call_remote", "unreliable", 5)
func receive_visual_world_event(event: Dictionary) -> void:
	visual_world_event_received.emit(event)


@rpc("authority", "call_remote", "reliable", 2)
func receive_bulk_world_event(event: Dictionary) -> void:
	reliable_world_event_received.emit(event)


@rpc("authority", "call_remote", "reliable", 3)
func receive_hit_confirmation(event: Dictionary) -> void:
	reliable_world_event_received.emit(event)


@rpc("authority", "reliable")
func receive_inventory_state(state: Dictionary) -> void:
	inventory_state_received.emit(state)


@rpc("authority", "unreliable")
func receive_player_correction(correction: Dictionary) -> void:
	player_correction_received.emit(correction)


@rpc("authority", "call_remote", "reliable", 4)
func receive_team_chat_message(message: Dictionary) -> void:
	team_chat_message_received.emit(message)
