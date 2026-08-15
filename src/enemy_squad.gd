extends Node3D
class_name EnemySquad

const ChannelScript := preload("res://src/squad_communication_channel.gd")
const CommunicatorScript := preload("res://src/squad_communicator.gd")

const DEFAULT_SCENES := {
	"future_warrior": "res://character/FutureWarriorAI.tscn",
	"future_engineer": "res://character/FutureEngineerAI.tscn",
	"assistant": "res://character/AssistantAI.tscn",
	"bandit": "res://character/BanditAI.tscn",
}

@export var squad_id := "squad"
@export var team_id := "enemy"
@export var target: Node3D
@export var member_configs: Array[EnemySquadMemberConfig] = []
@export var auto_spawn_members := true
@export var minimum_member_distance := 2.0
@export_range(0.0, 1.0, 0.05) var separation_weight := 0.35
@export var spawn_spacing := 2.5
@export var spawn_area_radius := 5.0
@export var console_debug_enabled := true

var external_respawn_controller: Node

var communication_channel: SquadCommunicationChannel
var _members: Dictionary = {}
var _member_serial := 0
var _fallback_target: Node3D


func _ready() -> void:
	communication_channel = ChannelScript.new()
	communication_channel.name = "SquadCommunicationChannel"
	communication_channel.configure(self)
	add_child(communication_channel)
	if not _has_authority():
		return
	_ensure_shared_target()
	_register_existing_members()
	if auto_spawn_members:
		_spawn_configured_members()
	if is_instance_valid(target):
		communication_channel.broadcast_target(target)


func _process(_delta: float) -> void:
	if not _has_authority() or is_instance_valid(target):
		return
	_ensure_shared_target()
	if is_instance_valid(target) and is_instance_valid(communication_channel):
		communication_channel.broadcast_target(target)


func _exit_tree() -> void:
	if is_instance_valid(_fallback_target):
		_fallback_target.queue_free()
	_fallback_target = null


func register_member(member: Node, ai_type := "future_warrior") -> String:
	if not is_instance_valid(member):
		return ""
	for existing_id in _members:
		if _members[existing_id] == member:
			return existing_id
	_member_serial += 1
	var member_id := "%s_%02d" % [ai_type, _member_serial]
	var communicator := CommunicatorScript.new()
	communicator.name = "SquadCommunicator"
	member.add_child(communicator)
	communicator.bind(member, communication_channel, member_id, ai_type)
	communication_channel.register_member(member_id, communicator)
	_members[member_id] = member
	if "team_id" in member:
		member.team_id = team_id
	if member.has_method("configure_squad_membership"):
		member.configure_squad_membership(self, member_id, ai_type, communicator)
	elif member.has_method("set_squad"):
		member.set_squad(self)
	if is_instance_valid(target) and member.has_method("set_strategic_target"):
		member.set_strategic_target(target)
	if is_instance_valid(external_respawn_controller) and member.has_method("set_external_respawn_controller"):
		member.set_external_respawn_controller(external_respawn_controller)
	return member_id


func unregister_member(member: Node) -> void:
	for member_id in _members.keys():
		if _members[member_id] == member:
			communication_channel.unregister_member(member_id)
			_members.erase(member_id)
			return


func set_squad_target(value: Node3D) -> bool:
	if not is_instance_valid(value):
		return false
	target = value
	return bool(communication_channel.broadcast_target(value).get("accepted", false))


func get_member_nodes() -> Array[Node]:
	var result: Array[Node] = []
	for member in _members.values():
		if is_instance_valid(member):
			result.append(member)
	return result


func get_member_navigation_goal(member_id: String, base_position: Vector3) -> Vector3:
	var index := maxi(0, _members.keys().find(member_id))
	if index == 0:
		return base_position
	var ring_index := index - 1
	var angle := float(ring_index) * 2.399963
	var radius := minf(minimum_member_distance * (1.0 + floorf(float(ring_index) / 6.0)), 5.0)
	var candidate := base_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
	var map_rid := get_world_3d().navigation_map
	if map_rid.is_valid() and NavigationServer3D.map_get_iteration_id(map_rid) > 0:
		return NavigationServer3D.map_get_closest_point(map_rid, candidate)
	return candidate


## FutureEngineer 的业务适配接口；Engineer 不直接操作频道任务表。
func report_demolition_warning(engineer: Node, explosive_position: Vector3, danger_radius: float) -> bool:
	var request_id := str(engineer.get("squad_demolition_request_id"))
	var member_id := str(engineer.get("squad_member_id"))
	return bool(communication_channel.mark_demolition_planted(request_id, member_id, explosive_position, danger_radius).get("accepted", false))


## 爆破完成后通过统一通信频道请求小队成员刷新自己的导航路径。
func report_navigation_refresh(engineer: Node, demolished_position: Vector3) -> bool:
	var request_id := str(engineer.get("squad_demolition_request_id"))
	var member_id := str(engineer.get("squad_member_id"))
	return communication_channel.complete_demolition(request_id, member_id, demolished_position)


func _register_existing_members() -> void:
	for child in get_children():
		if child == communication_channel:
			continue
		if child.has_method("get_combat_team") and child.has_method("set_strategic_target"):
			register_member(child, _infer_ai_type(child))


func _spawn_configured_members() -> void:
	var spawn_index := _members.size()
	for config in member_configs:
		if config == null:
			continue
		for _index in range(maxi(0, config.count)):
			var scene: PackedScene = config.scene_override
			if scene == null:
				var path := str(DEFAULT_SCENES.get(config.ai_type, ""))
				if not path.is_empty():
					scene = load(path) as PackedScene
			if scene == null:
				continue
			var member := scene.instantiate()
			if "team_id" in member:
				member.team_id = team_id
			if is_instance_valid(target) and "target" in member:
				member.target = target
			add_child(member)
			member.global_position = _spawn_position(spawn_index)
			spawn_index += 1
			register_member(member, config.ai_type)


func _spawn_position(index: int) -> Vector3:
	var batch_rotation := fmod(float(hash(squad_id)), 6283.0) / 1000.0
	var angle := batch_rotation + float(index) * 2.399963
	var radius := minf(spawn_spacing * sqrt(float(index + 1)), maxf(1.0, spawn_area_radius))
	var candidate := global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
	var map_rid := get_world_3d().navigation_map
	if map_rid.is_valid() and NavigationServer3D.map_get_iteration_id(map_rid) > 0:
		return NavigationServer3D.map_get_closest_point(map_rid, candidate)
	return candidate


func _ensure_shared_target() -> void:
	if is_instance_valid(target):
		return
	var world := GlobalVar.gameworld
	if not is_instance_valid(world) or not world.has_method("get_random_enemy_spawn_position"):
		return
	var random_seed := hash(squad_id) + get_instance_id() + int(Time.get_ticks_msec())
	var position: Vector3 = world.get_random_enemy_spawn_position(team_id, random_seed, 0)
	if not position.is_finite():
		return
	_fallback_target = Node3D.new()
	_fallback_target.name = "SquadStrategicTarget"
	world.add_child(_fallback_target)
	_fallback_target.global_position = position
	target = _fallback_target


func _infer_ai_type(member: Node) -> String:
	if member.get_script() != null and str(member.get_script().resource_path).contains("future_engineer"):
		return "future_engineer"
	if member.get_script() != null and str(member.get_script().resource_path).contains("bandit"):
		return "bandit"
	if member is AssistantAI:
		return "assistant"
	return "future_warrior"


func _has_authority() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return multiplayer.is_server()
