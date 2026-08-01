extends Node
class_name WorldNetworkSession

## 统一游戏世界网络接口。
## ENet 与 Steam P2P 只在本类的传输选择处不同；玩法、快照和视觉层只依赖本接口。

signal world_snapshot_received(snapshot: Dictionary)
signal reliable_world_event_received(event: Dictionary)
signal visual_world_event_received(event: Dictionary)
signal inventory_state_received(state: Dictionary)
signal player_correction_received(correction: Dictionary)
signal team_chat_message_received(message: Dictionary)
signal disconnected(reason: String)


func _ready() -> void:
	MultiplayerNetwork.world_snapshot_received.connect(
		func(snapshot: Dictionary) -> void: world_snapshot_received.emit(snapshot)
	)
	MultiplayerNetwork.reliable_world_event_received.connect(
		func(event: Dictionary) -> void: reliable_world_event_received.emit(event)
	)
	MultiplayerNetwork.visual_world_event_received.connect(
		func(event: Dictionary) -> void: visual_world_event_received.emit(event)
	)
	MultiplayerNetwork.inventory_state_received.connect(
		func(state: Dictionary) -> void: inventory_state_received.emit(state)
	)
	MultiplayerNetwork.player_correction_received.connect(
		func(correction: Dictionary) -> void: player_correction_received.emit(correction)
	)
	MultiplayerNetwork.team_chat_message_received.connect(
		func(message: Dictionary) -> void: team_chat_message_received.emit(message)
	)
	MultiplayerNetwork.disconnected.connect(
		func(reason: String) -> void: disconnected.emit(reason)
	)


func is_client() -> bool:
	return CooperativeSession.is_client() or MultiplayerNetwork.is_connected_to_game_server()


func is_listen_server() -> bool:
	return CooperativeSession.is_host()


func is_authority_visual_client() -> bool:
	return is_client() or is_listen_server()


func get_unique_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


func get_last_rtt_ms() -> float:
	return MultiplayerNetwork.get_last_rtt_ms()


func get_death_drop_mode() -> String:
	return CooperativeSession.get_death_drop_mode() if CooperativeSession.is_active() else ""


func submit_action(action_type: String, payload: Dictionary = {}) -> void:
	if CooperativeSession.is_client():
		CooperativeSession.submit_action(action_type, payload)
		return
	MultiplayerNetwork.submit_enet_action(action_type, payload)
