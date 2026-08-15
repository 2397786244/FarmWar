extends CharacterBody3D
class_name ServerPlayerPhysicsBody

## Dedicated/listen server 上代表远程玩家的权威物理代理。
##
## 服务器不实例化远程玩家的完整 GamePlayer 外观，但 AI 的视线、队伍判断
## 和受击反击仍然需要一个可查询的 CharacterBody3D。代理的位置由
## GameAuthority._simulate_players() 驱动，队伍和存活状态始终从 player_states
## 读取，避免把一份可能过期的玩家状态复制到代理节点中。

var peer_id: int = 0
var authority_peer_id: int = 0


func _ready() -> void:
	# Keep the proxy discoverable by older AI implementations that still query
	# human_players directly. The dedicated server-specific group remains the
	# authoritative query path for FutureWarrior/FutureEngineer.
	add_to_group("human_players")
	add_to_group("server_human_players")
	set_meta("authoritative_human_player", true)


func configure_for_peer(value: int) -> void:
	peer_id = value
	authority_peer_id = value
	set_meta("server_peer_id", value)
	set_meta("authority_peer_id", value)


func get_combat_team() -> String:
	var state := _authority_state()
	return str(state.get("team", ""))


func get_network_state() -> Dictionary:
	var state := _authority_state()
	var respawn_left := float(state.get("respawn_left", 0.0))
	var hp := float(state.get("hp", 0.0))
	return {
		"peer_id": peer_id,
		"team": str(state.get("team", "")),
		"position": global_position,
		"velocity": velocity,
		"yaw": rotation.y,
		"hp": hp,
		"dead": respawn_left > 0.0 or hp <= 0.0,
		"respawn_left": respawn_left,
	}


func _authority_state() -> Dictionary:
	if peer_id <= 0 or not is_instance_valid(GameAuthority):
		return {}
	var states: Variant = GameAuthority.get("player_states")
	if not states is Dictionary:
		return {}
	var state: Variant = (states as Dictionary).get(peer_id, {})
	return state as Dictionary if state is Dictionary else {}
