extends Node3D
class_name EnemySquadSpawner

const SQUAD_SCENE := preload("res://character/EnemySquad.tscn")
const MemberConfigScript := preload("res://src/enemy_squad_member_config.gd")

@export var spawner_id := "squad_spawner"
@export var team_id := "red"
@export var member_roles := PackedStringArray(["future_warrior"])
@export_range(1.0, 600.0, 1.0) var respawn_seconds := 30.0
@export_range(1.0, 30.0, 0.5) var spawn_radius := 5.0
@export var target_marker_id := ""
## 地图编辑器保存的生成器由 FarmWorldInitializer 显式启用。
@export var spawn_on_ready := false
@export var console_debug_enabled := true

var active_squad: EnemySquad
## 测试场景或运行时调用可以直接注入一个 Node3D target；地图编辑器使用 target_marker_id。
var target_node: Node3D
var active_batch := 0
var respawn_remaining := -1.0
var _runtime_active := false
var _gameplay_enabled := false


func _ready() -> void:
	add_to_group("enemy_squad_spawners")
	if spawn_on_ready and _has_authority():
		activate_runtime_spawning()


func _process(delta: float) -> void:
	if not _runtime_active or not _has_authority():
		return
	if respawn_remaining >= 0.0:
		respawn_remaining = maxf(0.0, respawn_remaining - delta)
		if respawn_remaining <= 0.0:
			_replace_with_new_batch()
		return
	if is_instance_valid(active_squad) and _is_active_batch_eliminated():
		respawn_remaining = maxf(1.0, respawn_seconds)
		_debug("batch=%d eliminated; next batch in %.1fs" % [active_batch, respawn_remaining])


func activate_runtime_spawning() -> void:
	if not _has_authority():
		return
	_runtime_active = true
	if not is_instance_valid(active_squad):
		spawn_new_batch()


func spawn_new_batch() -> EnemySquad:
	if not _has_authority() or member_roles.is_empty():
		return null
	active_batch += 1
	var squad := SQUAD_SCENE.instantiate() as EnemySquad
	if squad == null:
		push_error("[EnemySquadSpawner] Cannot instantiate EnemySquad.")
		return null
	squad.name = "%s_Batch_%03d" % [spawner_id.validate_node_name(), active_batch]
	squad.squad_id = "%s_batch_%03d" % [spawner_id, active_batch]
	squad.team_id = team_id
	squad.target = _resolve_target_point()
	squad.spawn_area_radius = spawn_radius
	squad.external_respawn_controller = self
	squad.member_configs = _build_member_configs()
	squad.auto_spawn_members = true
	squad.process_mode = Node.PROCESS_MODE_INHERIT if _gameplay_enabled else Node.PROCESS_MODE_DISABLED
	add_child(squad)
	active_squad = squad
	respawn_remaining = -1.0
	_assign_network_member_ids()
	_debug("spawned batch=%d members=%d target=%s" % [
		active_batch,
		squad.get_member_nodes().size(),
		squad.target.name if is_instance_valid(squad.target) else "enemy_spawn_fallback",
	])
	return squad


func set_gameplay_enabled(value: bool) -> void:
	_gameplay_enabled = value
	if is_instance_valid(active_squad):
		active_squad.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED


func notify_squad_member_dead(_member: Node) -> void:
	## 状态在 AI._die() 中已先切换为 DEAD；延迟检查可覆盖同一帧多个成员死亡。
	call_deferred("_begin_respawn_if_batch_eliminated")


func _begin_respawn_if_batch_eliminated() -> void:
	if respawn_remaining < 0.0 and _is_active_batch_eliminated():
		respawn_remaining = maxf(1.0, respawn_seconds)
		_debug("batch=%d eliminated; next batch in %.1fs" % [active_batch, respawn_remaining])


func _replace_with_new_batch() -> void:
	if is_instance_valid(active_squad):
		active_squad.queue_free()
		active_squad = null
	spawn_new_batch()


func _is_active_batch_eliminated() -> bool:
	if not is_instance_valid(active_squad):
		return true
	var members := active_squad.get_member_nodes()
	if members.is_empty():
		return true
	for member in members:
		if not is_instance_valid(member):
			continue
		if member.has_method("is_eliminated_for_squad_batch"):
			if not bool(member.is_eliminated_for_squad_batch()):
				return false
			continue
		var state_value = member.get("state")
		if state_value == null or int(state_value) != FutureWarriorAI.AIState.DEAD:
			return false
	return true


func _build_member_configs() -> Array[EnemySquadMemberConfig]:
	var result: Array[EnemySquadMemberConfig] = []
	for role_value in member_roles:
		var role := _normalize_role(str(role_value))
		if role not in ["future_warrior", "future_engineer"]:
			continue
		var config := MemberConfigScript.new() as EnemySquadMemberConfig
		config.ai_type = role
		config.count = 1
		result.append(config)
	return result


func _resolve_target_point() -> Node3D:
	if is_instance_valid(target_node):
		return target_node
	if target_marker_id.is_empty():
		return null
	for node in get_tree().get_nodes_in_group("squad_target_points"):
		if node is Node3D and str(node.get("target_id")) == target_marker_id:
			return node as Node3D
	return null


func _assign_network_member_ids() -> void:
	if not is_instance_valid(active_squad):
		return
	var members := active_squad.get_member_nodes()
	for index in range(members.size()):
		var member := members[index]
		if not is_instance_valid(member):
			continue
		member.set_meta("network_ai_id", "%s:batch_%03d:member_%02d" % [spawner_id, active_batch, index + 1])
		member.set_meta("map_ai_type", _normalize_role(str(member_roles[index])) if index < member_roles.size() else "future_warrior")


func _normalize_role(value: String) -> String:
	var normalized := value.strip_edges().to_lower().replace(" ", "_")
	if normalized in ["futurewarrior", "future_warrior_ai"]:
		return "future_warrior"
	if normalized in ["futureengineer", "future_engineer_ai"]:
		return "future_engineer"
	return normalized


func _has_authority() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return multiplayer.is_server()


func _debug(message: String) -> void:
	if console_debug_enabled:
		print("[EnemySquadSpawner] id=%s %s" % [spawner_id, message])
