extends CharacterBody3D
class_name AssistantAI

## 与 FutureWarrior / FutureEngineer 一致：动态导航区块更新和本地卡住重试
## 通过这个信号供测试场景的左侧导航日志显示区块与通信触发的路径刷新。
signal navigation_path_refreshed(chunk_ids: Array, was_stuck: bool)

## 蓝方辅助角色：优先部署投弹无人机；无人机失效期间才使用 Nailgun 自卫。
const SquadMessageTypes := preload("res://src/squad_message.gd")
const INVALID_POSITION := Vector3(INF, INF, INF)
const DEATH_CLEANUP_SECONDS := 10.0

enum OperationState {
	ADVANCE_TO_DEPLOYMENT,
	CONTROLLING_DRONE,
	DEFENSIVE_PATROL,
}

@export_enum("red", "blue") var team_id := "blue"
## Optional map-assigned spawn. Empty means a random spawn point in team_id.
@export var spawn_point_id := ""
## 可选战略目标。设置后优先推进至此；为空时使用敌方出生点。
@export var target: Node3D
@export var max_hp := 200.0
@export var respawn_seconds := 10.0
@export var drone_respawn_time := 45.0
@export_range(1.0, 120.0, 0.5) var vision_distance := 80.0
@export var nailgun_cooldown := 0.45
@export var defensive_patrol_radius := 6.0
@export var defensive_patrol_speed := 2.5
@export var advance_speed := 2.6
@export var deployment_advance_distance := 30.0
@export var own_farm_advance_radius := 45.0
@export var navigation_refresh_interval := 0.25
## 与 FutureWarrior/FutureEngineer 保持一致：联机时 AI 行为仅由服务器执行。
@export var server_authoritative := true
@export_range(0.05, 5.0, 0.05) var combat_target_refresh_interval := 0.20
@export_range(1.0, 30.0, 0.5) var squad_support_timeout := 10.0
@export_range(0.5, 10.0, 0.1) var squad_support_arrival_distance := 3.0
@export_range(1.0, 120.0, 1.0) var squad_support_max_response_distance := 50.0
@export_range(0.0, 180.0, 1.0) var squad_support_max_off_target_angle_degrees := 120.0
@export_range(1.0, 30.0, 0.5) var squad_support_request_cooldown := 10.0
@export_range(1.0, 30.0, 0.5) var squad_warning_retreat_distance := 10.0
@export_range(0.5, 15.0, 0.5) var squad_warning_lifetime := 8.0
@export_range(1.0, 120.0, 1.0) var squad_drone_support_bombard_seconds := 30.0
@export_range(1.0, 15.0, 0.5) var squad_drone_support_bombard_radius := 5.0
@export_range(0.25, 10.0, 0.05) var squad_stuck_detection_seconds := 2.0
@export_range(0.1, 5.0, 0.05) var squad_stuck_min_goal_progress := 0.75
@export_range(0.1, 5.0, 0.05) var squad_stuck_min_actual_motion := 0.65
@export_range(0.05, 5.0, 0.05) var squad_stuck_blocked_seconds := 0.45
@export_range(1.0, 30.0, 0.5) var squad_stuck_escape_after_seconds := 10.0
@export_range(1.0, 15.0, 0.5) var squad_escape_duration := 5.0
@export_range(0.5, 10.0, 0.1) var squad_escape_distance := 5.0
## 调试期间在权威端命令行输出 Assistant 与 AI 无人机状态。
@export var console_debug_enabled := true
@export_range(0.2, 10.0, 0.1) var console_debug_interval := 1.0
@export_range(0.0, 1.0, 0.01) var signal_advance_threshold := 0.20
@export_range(0.0, 1.0, 0.01) var signal_recover_threshold := 0.50
@export_file("*.tscn") var drone_scene_path := "res://character/AIDevices/AINormalDrone.tscn"
@export_file("*.tscn") var nailgun_scene_path := "res://character/weapons/Nailgun.tscn"

var current_hp := 0.0
var interest_sleeping := false
var drone: AINormalDrone
var nailgun: Node3D
var target_player: CharacterBody3D
var respawn_timer := 0.0
var fire_timer := 0.0
var is_dead := false
var head: Node3D
var right_hand_socket: BoneAttachment3D
var tool_pivot: Node3D
var aim_marker: Marker3D
var upper_body_look_target: Marker3D
var right_hand_ik_target: Marker3D
var right_elbow_pole: Marker3D
var appearance_player: AnimationPlayer
var skeleton: Skeleton3D
var right_arm_ik: TwoBoneIK3D
var upper_body_look_modifiers: Array[LookAtModifier3D] = []
var upper_body_look_weights: Array[float] = []
var action_animation_locked := false
var patrol_anchor := Vector3.INF
var patrol_destination := Vector3.INF
var patrol_refresh_timer := 0.0
var navigation_agent: NavigationAgent3D
var navigation_refresh_timer := 0.0
var operation_state := OperationState.ADVANCE_TO_DEPLOYMENT
var deployment_origin := Vector3.INF
var deployment_position := Vector3.INF
var knockback_velocity := Vector3.ZERO
var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var debug_label: Label3D
var advancing_for_signal_recovery := false
var enemy_spawn_target := Vector3.INF
var team_marker: MeshInstance3D
var console_debug_timer := 0.0
var combat_target_refresh_timer := 0.0
var squad: Node
## EnemySquadSpawner 注入后，角色死亡只上报整队批次淘汰；绝不执行
## Assistant 自身的 respawn_seconds 复活。
var external_respawn_controller: Node
var squad_member_id := ""
var squad_ai_type := "assistant"
var squad_communicator: Node
var last_squad_message_text := ""
var squad_support_position := INVALID_POSITION
var squad_support_arrived := false
var squad_support_hold_timer := 0.0
var squad_support_request_timer := 0.0
var squad_support_broadcast_active := false
var squad_warning_position := INVALID_POSITION
var squad_warning_radius := 0.0
var squad_warning_timer := 0.0
var _avoidance_safe_velocity := Vector3.ZERO
var _avoidance_safe_velocity_valid := false
var _navigation_using_direct_fallback := false
var _squad_stuck := false
var _squad_stuck_elapsed := 0.0
var _squad_navigation_retry_timer := 0.0
var _squad_progress_window_elapsed := 0.0
var _squad_progress_anchor := Vector3.INF
var _squad_tracking_goal := Vector3.INF
var _squad_window_travel_distance := 0.0
var _squad_blocked_elapsed := 0.0
var _squad_escape_direction := Vector3.ZERO
var _squad_escape_timer := 0.0
var _squad_escape_waypoint := INVALID_POSITION
var _squad_drone_held_for_body_override := false
const TEAM_MARKER_HEIGHT := 3.15

@onready var hit_3d := get_node_or_null("Hit3D") as Area3D
@onready var body_collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
@onready var hit_collision := get_node_or_null("Hit3D/CollisionShape3D") as CollisionShape3D
@onready var health_label := get_node_or_null("HealthLabel3D") as Label3D


func _ready() -> void:
	current_hp = max_hp
	collision_layer = 8
	# 519 + 工具层 128：已放置的 TallLogWall 等防御建筑必须阻挡 Assistant。
	collision_mask = 647
	add_to_group("assistant_ai")
	add_to_group("combat_characters")
	_create_hand_mount()
	_load_assistant_appearance()
	_ensure_team_marker_visual()
	_create_nailgun()
	_create_navigation_agent()
	_create_debug_label()
	_update_label()
	_update_debug_label()
	if hit_3d != null:
		if not hit_3d.body_entered.is_connected(_on_hit_3d_body_entered):
			hit_3d.body_entered.connect(_on_hit_3d_body_entered)
		if not hit_3d.area_entered.is_connected(_on_hit_3d_area_entered):
			hit_3d.area_entered.connect(_on_hit_3d_area_entered)
	## Assistant 开局立即放飞无人机；之后仅在信号低于阈值时才自身推进。
	call_deferred("_start_drone_operation")


func _process(delta: float) -> void:
	if interest_sleeping or is_dead:
		return
	_update_aim_reference()
	_update_upper_body_aim(delta)
	_update_weapon_alignment()


func _physics_process(delta: float) -> void:
	if interest_sleeping:
		return
	if is_dead:
		_simulate_corpse_gravity(delta)
		if not _has_simulation_authority():
			return
		if _uses_external_squad_respawn():
			_update_debug_label()
			return
		respawn_timer = maxf(0.0, respawn_timer - delta)
		if respawn_timer <= 0.0:
			_respawn()
		_update_debug_label()
		return
	if not _has_simulation_authority():
		return
	var previous_position := global_position
	_apply_gravity(delta)
	_squad_navigation_retry_timer = maxf(0.0, _squad_navigation_retry_timer - delta)
	var body_override_active := _update_squad_warning_retreat(delta)
	if not body_override_active:
		body_override_active = _update_squad_escape(delta)
	if not body_override_active:
		match operation_state:
			OperationState.ADVANCE_TO_DEPLOYMENT:
				_start_drone_operation()
			OperationState.CONTROLLING_DRONE:
				if not is_instance_valid(drone):
					_enter_defensive_mode()
				else:
					_update_signal_recovery_state()
					if advancing_for_signal_recovery:
						# 信号低于 20% 后持续推进，直到恢复到 50% 以上。
						_advance_toward_enemy_farm(delta)
					else:
						_hold_position(delta)
			OperationState.DEFENSIVE_PATROL:
				_defensive_patrol(delta)
	## 支援不再移动 Assistant 本体：成功认领后由 AINormalDrone 执行 30 秒
	## 支援点轰炸。本体继续自身的部署/遥控/防御状态。
	_update_squad_drone_support_tracking()
	if operation_state != OperationState.DEFENSIVE_PATROL:
		_update_active_personal_combat(delta)
	_update_squad_support_broadcast(delta)
	var actual_horizontal_velocity := (
		(global_position - previous_position) / maxf(delta, 0.0001)
	)
	actual_horizontal_velocity.y = 0.0
	_update_character_animation(actual_horizontal_velocity)
	_update_debug_label()
	_emit_console_debug(delta)


func can_enter_interest_sleep() -> bool:
	return not is_dead


func set_interest_sleeping(value: bool) -> void:
	if value:
		if is_dead:
			return
		interest_sleeping = true
		velocity = Vector3.ZERO
		knockback_velocity = Vector3.ZERO
		target_player = null
		advancing_for_signal_recovery = false
		operation_state = OperationState.DEFENSIVE_PATROL
		_update_label()
		return
	interest_sleeping = false
	if is_dead:
		return
	velocity = Vector3.ZERO
	operation_state = OperationState.DEFENSIVE_PATROL


func _spawn_drone() -> void:
	if is_instance_valid(drone):
		return
	if not is_instance_valid(GlobalVar.gameworld):
		return
	var scene := load(drone_scene_path) as PackedScene
	if scene == null:
		push_error("[AssistantAI] Cannot load AI drone: %s" % drone_scene_path)
		return
	var spawned := scene.instantiate() as AINormalDrone
	if spawned == null:
		push_error("[AssistantAI] AINormalDrone scene root is invalid.")
		return
	spawned.team_id = team_id
	spawned.tool_owner = team_id
	spawned.squad_support_bombard_seconds = squad_drone_support_bombard_seconds
	spawned.squad_support_bombard_radius = squad_drone_support_bombard_radius
	# 运行时无人机需要独立于 Assistant 本体进行多人同步。控制器的网络 ID
	# 在地图加载时稳定，因此可用于客户端重建同一架无人机的视觉代理。
	var controller_network_id := str(get_meta("network_ai_id", name))
	spawned.set_meta("network_ai_drone_id", "%s:drone" % controller_network_id)
	spawned.set_ai_controller(self)
	GlobalVar.gameworld.add_child(spawned)
	spawned.global_position = global_position + Vector3.UP * spawned.cruise_altitude
	spawned.destroyed.connect(_on_drone_destroyed)
	spawned.signal_link_lost.connect(_on_drone_signal_lost)
	drone = spawned


func _start_drone_operation() -> void:
	if is_dead or not _has_simulation_authority():
		return
	if not is_instance_valid(GlobalVar.gameworld):
		call_deferred("_start_drone_operation")
		return
	operation_state = OperationState.CONTROLLING_DRONE
	deployment_origin = Vector3.INF
	deployment_position = Vector3.INF
	if not is_instance_valid(drone):
		_spawn_drone()


func _on_drone_destroyed() -> void:
	if is_instance_valid(drone):
		drone.queue_free()
	drone = null
	respawn_timer = drone_respawn_time
	_enter_defensive_mode()


func _on_drone_signal_lost() -> void:
	if is_instance_valid(drone):
		drone.queue_free()
	drone = null
	respawn_timer = drone_respawn_time
	_enter_defensive_mode()


func _create_nailgun() -> void:
	var scene := load(nailgun_scene_path) as PackedScene
	if scene == null:
		return
	nailgun = scene.instantiate() as Node3D
	if nailgun == null:
		return
	tool_pivot.add_child(nailgun)
	nailgun.position = Vector3.ZERO
	# 与 tool_definitions.json 的 nail_gun 握持参数保持一致。
	nailgun.rotation_degrees = Vector3(0.0, 180.0, 180.0)
	nailgun.scale = Vector3(0.5, 0.5, 0.5)
	if _has_property(nailgun, "tool_owner"):
		nailgun.set("tool_owner", team_id)


func _has_simulation_authority() -> bool:
	if not server_authoritative:
		return true
	if GameAuthority.is_server_authority():
		return true
	if GameAuthority.is_client_proxy():
		return false
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


## 不改变无人机状态机：Assistant 在部署推进或操控无人机时，仅以 Nailgun
## 叠加自卫射击；无人机的搜索、投弹、信号恢复仍由 AINormalDrone 自己执行。
func _update_active_personal_combat(delta: float) -> void:
	combat_target_refresh_timer = maxf(0.0, combat_target_refresh_timer - delta)
	if not _is_active_hostile_candidate(target_player) or combat_target_refresh_timer <= 0.0:
		target_player = _find_visible_enemy_player()
		combat_target_refresh_timer = combat_target_refresh_interval
	if not is_instance_valid(target_player):
		return
	_fire_at_target(delta)


func _search_and_fire(delta: float) -> void:
	fire_timer = maxf(0.0, fire_timer - delta)
	target_player = _find_visible_enemy_player()
	if not is_instance_valid(target_player) or fire_timer > 0.0 or nailgun == null:
		return
	look_at(target_player.global_position, Vector3.UP)
	aim_marker.global_position = target_player.global_position + Vector3.UP
	_update_weapon_alignment()
	if _fire_nailgun_hitscan():
		if appearance_player != null and appearance_player.has_animation(&"ShootOneHand"):
			action_animation_locked = true
			appearance_player.play(&"ShootOneHand", 0.05)
		fire_timer = nailgun_cooldown


func _defensive_patrol(delta: float) -> void:
	patrol_refresh_timer = maxf(0.0, patrol_refresh_timer - delta)
	if patrol_refresh_timer <= 0.0:
		patrol_refresh_timer = 1.5
		target_player = _find_visible_defensive_threat()
	if is_instance_valid(target_player):
		_hold_position(delta)
		_fire_at_target(delta)
		return
	if is_instance_valid(drone):
		_set_drone_body_override_hold(false)
		operation_state = OperationState.CONTROLLING_DRONE
		return
	respawn_timer = maxf(0.0, respawn_timer - delta)
	if respawn_timer <= 0.0:
		operation_state = OperationState.CONTROLLING_DRONE
		_spawn_drone()
		return
	if patrol_anchor == Vector3.INF:
		_capture_patrol_anchor()
	if patrol_destination == Vector3.INF or global_position.distance_to(patrol_destination) < 0.8:
		var angle := randf_range(0.0, TAU)
		patrol_destination = patrol_anchor + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(1.5, defensive_patrol_radius)
	_move_toward_position(patrol_destination, defensive_patrol_speed, delta)


# ------------------------------------------------------------------
# Squad membership and communication
# ------------------------------------------------------------------

func configure_squad_membership(
	value_squad: Node,
	member_id: String,
	ai_type: String,
	communicator: Node
) -> void:
	squad = value_squad
	squad_member_id = member_id
	squad_ai_type = ai_type
	squad_communicator = communicator
	last_squad_message_text = ""


func set_squad(value: Node) -> void:
	squad = value


func set_external_respawn_controller(value: Node) -> void:
	external_respawn_controller = value


func _uses_external_squad_respawn() -> bool:
	return is_instance_valid(external_respawn_controller) \
		and external_respawn_controller.has_method("notify_squad_member_dead")


func is_eliminated_for_squad_batch() -> bool:
	return is_dead


func set_strategic_target(value: Node3D) -> void:
	if not is_instance_valid(value):
		return
	target = value
	enemy_spawn_target = INVALID_POSITION
	deployment_position = INVALID_POSITION
	navigation_refresh_timer = 0.0
	if operation_state == OperationState.ADVANCE_TO_DEPLOYMENT:
		call_deferred("_initialize_deployment_advance")


func send_squad_message(type: int, payload: Dictionary = {}, reply_to := "") -> Dictionary:
	if not is_instance_valid(squad_communicator):
		return {"accepted": false, "reason": "not_in_squad"}
	return squad_communicator.send_message(type, payload, reply_to)


func record_squad_message(message: Dictionary) -> void:
	if squad_member_id.is_empty() or str(message.get("sender_member_id", "")) != squad_member_id:
		return
	last_squad_message_text = SquadMessageTypes.type_name(int(message.get("type", -1)))


func receive_squad_message(message: Dictionary) -> void:
	if is_dead:
		return
	var message_type := int(message.get("type", -1))
	var payload: Dictionary = message.get("payload", {})
	var request_id := str(message.get("request_id", ""))
	match message_type:
		SquadMessageTypes.Type.SET_TARGET:
			var new_target := payload.get("target") as Node3D
			if is_instance_valid(new_target):
				set_strategic_target(new_target)
		SquadMessageTypes.Type.DEMOLITION_WARNING:
			if str(message.get("sender_member_id", "")) != squad_member_id:
				_receive_squad_demolition_warning(payload)
		SquadMessageTypes.Type.NAVIGATION_REFRESH:
			_receive_squad_navigation_refresh(request_id)
		SquadMessageTypes.Type.SUPPORT_REQUEST:
			_try_claim_squad_support(request_id, payload.get("position", INVALID_POSITION))


func _receive_squad_demolition_warning(payload: Dictionary) -> void:
	var position: Variant = payload.get("position", INVALID_POSITION)
	if not position is Vector3 or not (position as Vector3).is_finite():
		return
	squad_warning_position = position as Vector3
	squad_warning_radius = maxf(
		float(payload.get("radius", 0.0)),
		squad_warning_retreat_distance
	)
	squad_warning_timer = squad_warning_lifetime
	## 爆破撤退属于 Assistant 本体的高优先级覆盖层，先暂停无人机的
	## 搜索/投弹；安全后由原 operation state 恢复无人机任务。
	_set_drone_body_override_hold(true)


func _update_squad_warning_retreat(delta: float) -> bool:
	if not squad_warning_position.is_finite():
		return false
	squad_warning_timer = maxf(0.0, squad_warning_timer - delta)
	if squad_warning_timer <= 0.0:
		_clear_squad_warning()
		return false
	if _horizontal_distance_to(squad_warning_position) >= squad_warning_radius:
		_set_drone_body_override_hold(false)
		return false
	var away := global_position - squad_warning_position
	away.y = 0.0
	if away.length_squared() <= 0.001:
		away = Vector3.RIGHT.rotated(Vector3.UP, randf_range(-PI, PI))
	away = _find_open_movement_direction(away)
	_move_with_horizontal_velocity(away.normalized() * defensive_patrol_speed, delta, false)
	return true


func _can_accept_squad_support() -> bool:
	return (
		not is_dead
		and is_instance_valid(drone)
		and drone.has_method("is_available_for_squad_support")
		and bool(drone.call("is_available_for_squad_support"))
		and not squad_support_position.is_finite()
	)


func _try_claim_squad_support(request_id: String, support_position: Variant) -> void:
	if request_id.is_empty() or not support_position is Vector3 or not (support_position as Vector3).is_finite():
		return
	if not _can_accept_squad_support():
		return
	var position := support_position as Vector3
	var distance := _horizontal_distance_to(position)
	if distance > squad_support_max_response_distance and _support_position_is_behind_target(position):
		return
	var result := send_squad_message(
		SquadMessageTypes.Type.SUPPORT_ACK,
		{"member_id": squad_member_id},
		request_id
	)
	if not bool(result.get("accepted", false)):
		return
	var accepted_position: Variant = result.get("position", position)
	if not accepted_position is Vector3 or not (accepted_position as Vector3).is_finite():
		return
	## 频道已经原子地限制最多两个 SUPPORT_ACK。只在 ACK 成功后才开始
	## 无人机支援，避免失败应答者也飞去轰炸。
	if not is_instance_valid(drone) or not drone.has_method("begin_squad_support_bombardment"):
		return
	if not bool(drone.call("begin_squad_support_bombardment", accepted_position as Vector3, squad_drone_support_bombard_seconds)):
		return
	squad_support_position = accepted_position as Vector3
	squad_support_arrived = false
	squad_support_hold_timer = squad_drone_support_bombard_seconds


func _support_position_is_behind_target(position: Vector3) -> bool:
	var strategic := get_attack_target_position()
	if not strategic.is_finite():
		return false
	var target_direction := strategic - global_position
	var support_direction := position - global_position
	target_direction.y = 0.0
	support_direction.y = 0.0
	if target_direction.length_squared() <= 0.001 or support_direction.length_squared() <= 0.001:
		return false
	return rad_to_deg(target_direction.angle_to(support_direction)) > squad_support_max_off_target_angle_degrees


func _update_squad_drone_support_tracking() -> void:
	if not squad_support_position.is_finite():
		return
	if not is_instance_valid(drone) or not drone.has_method("has_active_squad_support") \
			or not bool(drone.call("has_active_squad_support")):
		_clear_squad_support()


func _clear_squad_support() -> void:
	squad_support_position = INVALID_POSITION
	squad_support_arrived = false
	squad_support_hold_timer = 0.0


func _clear_squad_warning() -> void:
	squad_warning_position = INVALID_POSITION
	squad_warning_radius = 0.0
	squad_warning_timer = 0.0
	_set_drone_body_override_hold(false)


func _set_drone_body_override_hold(value: bool) -> void:
	_squad_drone_held_for_body_override = value
	if not is_instance_valid(drone):
		return
	if value:
		drone.set_operator_defensive_hold(true)
	elif not advancing_for_signal_recovery:
		drone.set_operator_defensive_hold(false)


func _receive_squad_navigation_refresh(request_id: String) -> void:
	## 只重置身体的 NavigationAgent 路径；不暂停无人机，也不把 Assistant
	## 拉向爆破位置。卡住标记保留，后续仍按正常导航重试/脱困处理。
	if is_dead:
		return
	var was_stuck := _squad_stuck
	_reset_navigation_path()
	if _squad_stuck:
		_squad_stuck_elapsed = 0.0
		_reset_squad_progress_window(get_attack_target_position())
		_squad_navigation_retry_timer = maxf(0.75, navigation_refresh_interval * 3.0)
	navigation_path_refreshed.emit([], was_stuck)
	_debug("squad navigation refresh received request=%s stuck=%s" % [request_id, str(was_stuck)])


func _update_squad_support_broadcast(delta: float) -> void:
	if not is_instance_valid(squad_communicator):
		return
	squad_support_request_timer = maxf(0.0, squad_support_request_timer - delta)
	if not squad_support_broadcast_active or not _is_active_hostile_candidate(target_player) \
			or squad_support_request_timer > 0.0:
		return
	var result := send_squad_message(
		SquadMessageTypes.Type.SUPPORT_REQUEST,
		{"position": global_position}
	)
	if bool(result.get("accepted", false)):
		squad_support_request_timer = squad_support_request_cooldown


func _enter_defensive_mode() -> void:
	operation_state = OperationState.DEFENSIVE_PATROL
	patrol_anchor = global_position
	patrol_destination = Vector3.INF
	patrol_refresh_timer = 0.0
	if is_instance_valid(drone):
		drone.set_operator_defensive_hold(true)


func _initialize_deployment_advance() -> void:
	var attack_target := get_attack_target_position()
	if attack_target == Vector3.INF:
		return
	deployment_origin = global_position
	var direction := attack_target - deployment_origin
	direction.y = 0.0
	if direction.length_squared() <= 0.01:
		return
	deployment_position = deployment_origin + direction.normalized() * deployment_advance_distance
	patrol_anchor = deployment_origin
	patrol_destination = Vector3.INF


func _get_enemy_spawn_position() -> Vector3:
	if enemy_spawn_target != Vector3.INF:
		return enemy_spawn_target
	var game_world: Node = GlobalVar.gameworld
	if not is_instance_valid(game_world):
		return Vector3.INF
	if game_world.has_method("get_random_enemy_spawn_position"):
		var value: Variant = game_world.call(
			"get_random_enemy_spawn_position",
			team_id,
			get_instance_id() + int(Time.get_ticks_msec() / 1000.0),
			0
		)
		if value is Vector3 and value != Vector3.INF:
			enemy_spawn_target = value as Vector3
			return enemy_spawn_target
	return Vector3.INF


## 提供给 AINormalDrone 的共享战略目标：地图 target 优先；未配置时缓存当前随机敌方出生点。
func get_attack_target_position(force_refresh := false) -> Vector3:
	if is_instance_valid(target):
		return target.global_position
	if force_refresh:
		enemy_spawn_target = Vector3.INF
	return _get_enemy_spawn_position()


func _is_in_own_farm_area() -> bool:
	var game_world: Node = GlobalVar.gameworld
	if not is_instance_valid(game_world):
		return false
	var own_farm_name := "BlueFarm" if team_id == "blue" else "RedFarm"
	var own_farm := game_world.get_node_or_null(own_farm_name) as Node3D
	return own_farm != null and _horizontal_distance_to(own_farm.global_position) <= own_farm_advance_radius


func _advance_toward_enemy_farm(delta: float) -> void:
	var attack_target := get_attack_target_position()
	if attack_target == Vector3.INF:
		return
	_move_toward_position(attack_target, advance_speed, delta)


func _update_signal_recovery_state() -> void:
	if not is_instance_valid(drone):
		advancing_for_signal_recovery = false
		return
	var signal_strength := drone.get_effective_signal_strength(self)
	if signal_strength < signal_advance_threshold:
		advancing_for_signal_recovery = true
	if advancing_for_signal_recovery:
		if signal_strength >= signal_recover_threshold:
			advancing_for_signal_recovery = false
			if not _squad_drone_held_for_body_override:
				drone.set_operator_defensive_hold(false)
		else:
				# 20%-50% is a recovery-only band: do not let the drone resume its
			# hunt/bombard loop until the Assistant has restored a strong link.
			drone.set_operator_defensive_hold(true)
	elif not _squad_drone_held_for_body_override:
		drone.set_operator_defensive_hold(false)


func _move_toward_position(
	goal: Vector3,
	speed: float,
	delta: float,
	track_stuck := true
) -> void:
	if not goal.is_finite():
		_hold_position(delta)
		return
	if _horizontal_distance_to(goal) <= 0.5:
		_hold_position(delta)
		if track_stuck:
			_reset_squad_stuck_tracking()
		return
	var previous_position := global_position
	var movement_direction := _navigation_direction_to_goal(goal, delta)
	_move_with_horizontal_velocity(movement_direction * speed, delta)
	if track_stuck:
		_update_squad_stuck_tracking(previous_position, movement_direction, speed, delta, goal)


func _hold_position(delta: float) -> void:
	_move_with_horizontal_velocity(Vector3.ZERO, delta, false)


func _move_with_horizontal_velocity(
	desired: Vector3,
	delta: float,
	use_navigation_avoidance := true
) -> void:
	desired *= GameAuthority.get_chain_link_fence_speed_multiplier(
		global_position,
		team_id,
		"ai"
	)
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, 18.0 * delta)
	var proposed := global_position + Vector3(
		desired.x + knockback_velocity.x,
		0.0,
		desired.z + knockback_velocity.z
	) * delta
	if WaterBody3D.is_navigation_blocked(proposed):
		# Water is traversable by players, but never by AI navigation actors.
		desired = Vector3.ZERO
		knockback_velocity.x = 0.0
		knockback_velocity.z = 0.0
	var desired_velocity := desired + knockback_velocity
	var movement_velocity := desired_velocity
	if use_navigation_avoidance and _navigation_avoidance_is_active():
		navigation_agent.set_velocity(Vector3(desired_velocity.x, 0.0, desired_velocity.z))
		if _avoidance_safe_velocity_valid:
			movement_velocity.x = _avoidance_safe_velocity.x
			movement_velocity.z = _avoidance_safe_velocity.z
		_avoidance_safe_velocity_valid = false
	else:
		_avoidance_safe_velocity_valid = false
	velocity.x = movement_velocity.x
	velocity.z = movement_velocity.z
	if desired.length_squared() > 0.01:
		var facing := Vector3(desired.x, 0.0, desired.z)
		look_at(global_position + facing, Vector3.UP)
	move_and_slide()


func _on_navigation_velocity_computed(safe_velocity: Vector3) -> void:
	_avoidance_safe_velocity = safe_velocity
	_avoidance_safe_velocity_valid = true


func _navigation_direction_to_goal(goal: Vector3, delta: float) -> Vector3:
	_navigation_using_direct_fallback = false
	var direct_direction := goal - global_position
	direct_direction.y = 0.0
	if direct_direction.length_squared() <= 0.001:
		return Vector3.ZERO
	direct_direction = direct_direction.normalized()
	if navigation_agent == null or not _navigation_map_is_ready():
		_navigation_using_direct_fallback = true
		return direct_direction
	navigation_refresh_timer = maxf(0.0, navigation_refresh_timer - delta)
	if navigation_refresh_timer <= 0.0:
		navigation_agent.target_position = goal
		navigation_refresh_timer = navigation_refresh_interval
	var next_position := navigation_agent.get_next_path_position()
	var routed_direction := next_position - global_position
	routed_direction.y = 0.0
	if routed_direction.length_squared() > 0.001:
		return routed_direction.normalized()
	## 导航可用但当前没有路径时先等待困住判定与路径刷新；只有已经
	## 困住且导航重试窗口结束后，才允许有限的直线保底脱离死锁。
	if _squad_stuck and _squad_navigation_retry_timer <= 0.0:
		_navigation_using_direct_fallback = true
		return direct_direction
	return Vector3.ZERO


func _reset_navigation_path() -> void:
	navigation_refresh_timer = 0.0
	_avoidance_safe_velocity = Vector3.ZERO
	_avoidance_safe_velocity_valid = false
	if navigation_agent != null:
		navigation_agent.target_position = global_position


func _navigation_avoidance_is_active() -> bool:
	return navigation_agent != null and navigation_agent.avoidance_enabled and _navigation_map_is_ready()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1


## 死亡后身体只与静态世界碰撞：从高空死亡会落地，但不会再阻挡角色或
## 被任何战斗检测命中。
func _simulate_corpse_gravity(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()


func _corpse_collision_mask() -> int:
	return (
		GameAuthority.COLLISION_LAYER_GROUND
		| GameAuthority.COLLISION_LAYER_WALL
		| GameAuthority.COLLISION_LAYER_FARM_TILE
		| GameAuthority.COLLISION_LAYER_TOOL
		| GameAuthority.COLLISION_LAYER_BUILDING
		| GameAuthority.COLLISION_LAYER_VEHICLES
		| GameAuthority.COLLISION_LAYER_NATURE_RESOURCE
	)


func _horizontal_distance_to(position: Vector3) -> float:
	var offset := position - global_position
	offset.y = 0.0
	return offset.length()


func _create_navigation_agent() -> void:
	navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if navigation_agent == null:
		navigation_agent = NavigationAgent3D.new()
		navigation_agent.name = "NavigationAgent3D"
		add_child(navigation_agent)
	navigation_agent.radius = 0.34
	navigation_agent.height = 1.7
	navigation_agent.path_desired_distance = 0.55
	navigation_agent.target_desired_distance = 1.0
	navigation_agent.avoidance_enabled = true
	navigation_agent.neighbor_distance = 7.0
	navigation_agent.max_neighbors = 12
	navigation_agent.time_horizon_agents = 1.2
	if not navigation_agent.velocity_computed.is_connected(_on_navigation_velocity_computed):
		navigation_agent.velocity_computed.connect(_on_navigation_velocity_computed)


func _navigation_map_is_ready() -> bool:
	if navigation_agent == null:
		return false
	var navigation_map := navigation_agent.get_navigation_map()
	return navigation_map.is_valid() and NavigationServer3D.map_get_iteration_id(navigation_map) > 0


func is_squad_navigation_stuck() -> bool:
	return _squad_stuck


func notify_navigation_chunks_rebuilt(chunk_ids: Array) -> void:
	if is_dead:
		return
	var was_stuck := _squad_stuck
	_reset_navigation_path()
	if _squad_stuck:
		_squad_stuck_elapsed = 0.0
		_reset_squad_progress_window()
		_squad_navigation_retry_timer = maxf(0.75, navigation_refresh_interval * 3.0)
	navigation_path_refreshed.emit(chunk_ids.duplicate(), was_stuck)


func _reset_squad_progress_window(goal := INVALID_POSITION) -> void:
	_squad_progress_window_elapsed = 0.0
	_squad_progress_anchor = global_position
	_squad_tracking_goal = goal
	_squad_window_travel_distance = 0.0
	_squad_blocked_elapsed = 0.0


func _reset_squad_stuck_tracking() -> void:
	_squad_stuck = false
	_squad_stuck_elapsed = 0.0
	_squad_navigation_retry_timer = 0.0
	_reset_squad_progress_window()


func _frame_has_blocking_collision(
	previous_position: Vector3,
	direction: Vector3,
	speed: float,
	delta: float
) -> bool:
	var actual_motion := global_position - previous_position
	actual_motion.y = 0.0
	var expected_distance := maxf(0.0, speed) * maxf(0.0, delta)
	if direction.length_squared() > 0.001 and expected_distance > 0.08 \
			and actual_motion.length() < maxf(0.02, expected_distance * 0.18):
		return true
	if direction.length_squared() <= 0.001:
		return false
	var intended := Vector3(direction.x, 0.0, direction.z).normalized()
	for collision_index in range(get_slide_collision_count()):
		var collision := get_slide_collision(collision_index)
		if collision == null:
			continue
		var normal := collision.get_normal()
		normal.y = 0.0
		if normal.length_squared() > 0.01 and intended.dot(normal.normalized()) < -0.25:
			return true
	return false


func _update_squad_stuck_tracking(
	previous_position: Vector3,
	direction: Vector3,
	speed: float,
	delta: float,
	goal: Vector3
) -> void:
	if _squad_escape_timer > 0.0 \
			or not goal.is_finite() or _horizontal_distance_to(goal) <= 1.2:
		_reset_squad_stuck_tracking()
		return
	if navigation_agent != null and not _navigation_map_is_ready():
		_reset_squad_stuck_tracking()
		return
	if not _squad_tracking_goal.is_finite() \
			or _squad_tracking_goal.distance_to(goal) > 1.25:
		_reset_squad_progress_window(goal)
	_squad_progress_window_elapsed += delta
	_squad_window_travel_distance += _horizontal_distance_between(previous_position, global_position)
	var start_distance := _horizontal_distance_between(_squad_progress_anchor, _squad_tracking_goal)
	var current_distance := _horizontal_distance_to(goal)
	var goal_progress := start_distance - current_distance
	if _frame_has_blocking_collision(previous_position, direction, speed, delta):
		_squad_blocked_elapsed += delta
	else:
		_squad_blocked_elapsed = maxf(0.0, _squad_blocked_elapsed - delta * 0.5)
	if goal_progress >= squad_stuck_min_goal_progress and not _navigation_using_direct_fallback:
		if _squad_stuck:
			_squad_stuck = false
			_squad_stuck_elapsed = 0.0
		_reset_squad_progress_window(goal)
		return
	var elapsed := _squad_progress_window_elapsed
	var expected_motion := maxf(0.0, speed) * elapsed
	var minimum_motion := maxf(squad_stuck_min_actual_motion, expected_motion * 0.2)
	var actual_displacement := _horizontal_distance_between(_squad_progress_anchor, global_position)
	var insufficient_motion := _squad_window_travel_distance < minimum_motion
	var oscillating := _squad_window_travel_distance >= maxf(1.0, minimum_motion * 2.0) \
		and actual_displacement <= maxf(0.8, _squad_window_travel_distance * 0.45) \
		and goal_progress < squad_stuck_min_goal_progress
	var collision_confirmed := _squad_blocked_elapsed >= squad_stuck_blocked_seconds
	var confirmation_window := minf(squad_stuck_detection_seconds, 0.75) if collision_confirmed else squad_stuck_detection_seconds
	if not _squad_stuck:
		if elapsed < confirmation_window:
			return
		if goal_progress >= squad_stuck_min_goal_progress \
			or not (collision_confirmed or insufficient_motion or oscillating):
			return
		_squad_stuck = true
		_squad_stuck_elapsed = 0.0
		_reset_squad_progress_window(goal)
		_reset_navigation_path()
		_squad_navigation_retry_timer = maxf(0.75, navigation_refresh_interval * 3.0)
		navigation_path_refreshed.emit([], true)
		return
	_squad_stuck_elapsed += delta
	if _squad_stuck_elapsed >= squad_stuck_escape_after_seconds:
		_start_squad_escape()


func _update_squad_escape(delta: float) -> bool:
	if _squad_escape_timer <= 0.0:
		return false
	_set_drone_body_override_hold(true)
	_squad_escape_timer = maxf(0.0, _squad_escape_timer - delta)
	if _squad_escape_timer <= 0.0:
		_squad_escape_direction = Vector3.ZERO
		_squad_escape_waypoint = INVALID_POSITION
		_reset_navigation_path()
		_set_drone_body_override_hold(false)
		return false
	_move_with_horizontal_velocity(_squad_escape_direction * maxf(advance_speed, defensive_patrol_speed), delta, false)
	return true


func _start_squad_escape() -> void:
	var direction := Vector3.ZERO
	for _attempt in range(8):
		var candidate := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		if candidate.length_squared() <= 0.01:
			continue
		candidate = candidate.normalized()
		if not _movement_direction_is_blocked(candidate, minf(1.5, squad_escape_distance)):
			direction = candidate
			break
	if direction.length_squared() <= 0.001:
		direction = -global_transform.basis.z
		direction.y = 0.0
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	_squad_escape_direction = direction.normalized()
	_squad_escape_waypoint = global_position + _squad_escape_direction * squad_escape_distance
	_squad_escape_timer = squad_escape_duration
	_squad_stuck = false
	_squad_stuck_elapsed = 0.0
	_reset_squad_progress_window()
	_reset_navigation_path()


func _movement_direction_is_blocked(direction: Vector3, distance := 1.25) -> bool:
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	return horizontal.length_squared() <= 0.001 \
		or test_move(global_transform, horizontal.normalized() * maxf(0.25, distance))


func _find_open_movement_direction(preferred: Vector3, distance := 1.25) -> Vector3:
	var base := Vector3(preferred.x, 0.0, preferred.z)
	if base.length_squared() <= 0.001:
		base = -global_transform.basis.z
	if base.length_squared() <= 0.001:
		base = Vector3.FORWARD
	base = base.normalized()
	for candidate in [base, base.rotated(Vector3.UP, PI * 0.5), base.rotated(Vector3.UP, -PI * 0.5), base.rotated(Vector3.UP, PI)]:
		if not _movement_direction_is_blocked(candidate, distance):
			return candidate.normalized()
	return base


func _horizontal_distance_between(first: Vector3, second: Vector3) -> float:
	var offset := second - first
	offset.y = 0.0
	return offset.length()


func _fire_at_target(delta: float) -> void:
	fire_timer = maxf(0.0, fire_timer - delta)
	if not is_instance_valid(target_player) or fire_timer > 0.0 or nailgun == null:
		return
	look_at(target_player.global_position, Vector3.UP)
	aim_marker.global_position = target_player.global_position + Vector3.UP
	_update_weapon_alignment()
	if _fire_nailgun_hitscan():
		if appearance_player != null and appearance_player.has_animation(&"ShootOneHand"):
			action_animation_locked = true
			appearance_player.play(&"ShootOneHand", 0.05)
		fire_timer = nailgun_cooldown


func _fire_nailgun_hitscan() -> bool:
	if not is_instance_valid(nailgun) \
			or not nailgun.has_method("get_fire_origin") \
			or not nailgun.has_method("get_fire_direction") \
			or not GameAuthority.has_method("server_ai_hitscan"):
		return false
	if not GameAuthority.is_server_authority() and not GameAuthority.is_local_authority():
		return false
	var origin_value: Variant = nailgun.call("get_fire_origin")
	var direction_value: Variant = nailgun.call("get_fire_direction")
	if not origin_value is Vector3 or not direction_value is Vector3:
		return false
	var direction := direction_value as Vector3
	if direction.length_squared() <= 0.001:
		return false
	var result: Dictionary = GameAuthority.server_ai_hitscan(
		self,
		team_id,
		"nail_gun",
		origin_value as Vector3,
		direction.normalized()
	)
	if not bool(result.get("ok", false)):
		return false
	## 单人没有服务器广播的视觉事件，直接创建无伤害弹道；多人由
	## GameAuthority 通过不可靠视觉通道同步同一条 hitscan 轨迹。
	if GameAuthority.is_local_authority() and nailgun.has_method("emit_visual_only_tracer"):
		nailgun.call(
			"emit_visual_only_tracer",
			direction.normalized(),
			float(result.get("visual_distance", CombatBalance.get_float("nail_gun", "range")))
		)
	return true


func _capture_patrol_anchor() -> void:
	patrol_anchor = global_position
	patrol_destination = Vector3.INF


func _find_visible_enemy_player() -> CharacterBody3D:
	return _find_best_visible_hostile(false)


func _find_visible_defensive_threat() -> CharacterBody3D:
	return _find_best_visible_hostile(true)


func _find_best_visible_hostile(include_wild_animals: bool) -> CharacterBody3D:
	var best: CharacterBody3D
	var best_distance := INF
	var seen: Dictionary = {}
	var group_names := _authoritative_human_player_groups()
	group_names.append_array([&"combat_characters", &"future_warrior_ai", &"assistant_ai", &"farmer_ai", &"ai_players"])
	if include_wild_animals:
		group_names.append(&"wild_animals")
	for group_name in group_names:
		for node in get_tree().get_nodes_in_group(group_name):
			if not node is CharacterBody3D:
				continue
			var candidate := node as CharacterBody3D
			var candidate_id := candidate.get_instance_id()
			if seen.has(candidate_id):
				continue
			seen[candidate_id] = true
			if not _is_active_hostile_candidate(candidate):
				continue
			var distance := global_position.distance_to(candidate.global_position)
			if distance > vision_distance or not _has_line_of_sight(candidate):
				continue
			if distance < best_distance:
				best = candidate
				best_distance = distance
	return best


func _is_active_hostile_candidate(candidate: CharacterBody3D) -> bool:
	if candidate == null or candidate == self:
		return false
	if candidate.is_in_group("human_players") or candidate.is_in_group("server_human_players"):
		var expected_group := "server_human_players" if _uses_server_player_proxies() else "human_players"
		if not candidate.is_in_group(expected_group):
			return false
	if candidate.has_method("get_network_state"):
		var network_state := candidate.call("get_network_state") as Dictionary
		if bool(network_state.get("dead", false)):
			return false
	elif _has_property(candidate, "is_dead") and bool(candidate.get("is_dead")):
		return false
	var other_team := _get_combat_team(candidate)
	if candidate.is_in_group("wild_animals"):
		return true
	return not other_team.is_empty() and other_team != team_id


func _has_line_of_sight(candidate: CharacterBody3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP,
		candidate.global_position + Vector3.UP,
		65535,
		[get_rid()] + _server_presentation_player_query_exclusions()
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var cursor := hit.get("collider", null) as Node
	while cursor != null:
		if cursor == candidate:
			return true
		cursor = cursor.get_parent()
	return false


func _uses_server_player_proxies() -> bool:
	return GameAuthority.is_server_authority()


func _authoritative_human_player_groups() -> Array[StringName]:
	var groups: Array[StringName] = []
	groups.append(&"server_human_players" if _uses_server_player_proxies() else &"human_players")
	return groups


func _server_presentation_player_query_exclusions() -> Array[RID]:
	var exclusions: Array[RID] = []
	if not _uses_server_player_proxies():
		return exclusions
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and node is CollisionObject3D:
			exclusions.append((node as CollisionObject3D).get_rid())
	return exclusions


func _on_hit_3d_body_entered(body: Node3D) -> void:
	_handle_hit3d_contact(body)


func _on_hit_3d_area_entered(area: Area3D) -> void:
	_handle_hit3d_contact(area)


func _handle_hit3d_contact(contact: Node) -> void:
	var projectile := _find_projectile_root(contact)
	if projectile == null:
		return
	var attacker_team := str(projectile.call("get_bullet_owner"))
	if attacker_team.is_empty() or attacker_team == team_id:
		return
	var damage := 20.0
	if _has_property(projectile, "bullet_strength"):
		damage = float(projectile.get("bullet_strength"))
	elif _has_property(projectile, "damage"):
		damage = float(projectile.get("damage"))
	elif _has_property(projectile, "bullet_damage"):
		damage = float(projectile.get("bullet_damage"))
	var effect := str(projectile.get("bullet_effect")) if _has_property(projectile, "bullet_effect") else "bullet"
	var hit_direction := projectile.global_position.direction_to(global_position)
	if _has_property(projectile, "direction") and projectile.get("direction") is Vector3:
		hit_direction = projectile.get("direction") as Vector3
	impact(
		effect,
		damage,
		attacker_team,
		hit_direction,
		_get_projectile_attacker(projectile)
	)
	if _has_property(projectile, "knockback_force"):
		receive_bullet_hit(hit_direction, float(projectile.get("knockback_force")), attacker_team)
	projectile.queue_free()


func _find_projectile_root(contact: Node) -> Node3D:
	var cursor: Node = contact
	var depth := 0
	while cursor != null and depth < 12:
		if cursor is Node3D and cursor.has_method("get_bullet_owner"):
			return cursor as Node3D
		cursor = cursor.get_parent()
		depth += 1
	return null


func _get_projectile_attacker(projectile: Node) -> CharacterBody3D:
	if projectile != null and projectile.has_method("get_bullet_shooter"):
		var attacker: Variant = projectile.call("get_bullet_shooter")
		if attacker is CharacterBody3D:
			return attacker as CharacterBody3D
	return null


func impact(
	_effect: String,
	strength: float,
	attacker_team: String = "",
	hit_direction := Vector3.ZERO,
	attacker_node: CharacterBody3D = null
) -> bool:
	if is_dead or strength <= 0.0 or attacker_team == team_id:
		return false
	var damage := strength
	if _effect.to_lower() == "bug_storm":
		damage = CombatBalance.get_bug_storm_impact_damage(strength)
	current_hp = maxf(0.0, current_hp - damage)
	_update_label()
	if current_hp > 0.0:
		if _remember_retaliation_target(attacker_team, hit_direction, attacker_node):
			squad_support_broadcast_active = true
			squad_support_request_timer = 0.0
	if current_hp > 0.0 and operation_state == OperationState.CONTROLLING_DRONE:
		_enter_defensive_mode()
	if current_hp <= 0.0:
		_die(attacker_team)
	return true


func _remember_retaliation_target(
	attacker_team: String,
	hit_direction: Vector3,
	attacker_node: CharacterBody3D = null
) -> bool:
	if _is_active_hostile_candidate(attacker_node):
		_activate_retaliation_target(attacker_node)
		return true
	var attack_direction := -hit_direction
	attack_direction.y = 0.0
	if attack_direction.length_squared() <= 0.001:
		return false
	attack_direction = attack_direction.normalized()
	var best: CharacterBody3D
	var best_score := INF
	var seen: Dictionary = {}
	var groups := _authoritative_human_player_groups()
	groups.append_array([&"combat_characters", &"future_warrior_ai", &"assistant_ai", &"farmer_ai", &"ai_players"])
	for group_name in groups:
		for node in get_tree().get_nodes_in_group(group_name):
			if not node is CharacterBody3D:
				continue
			var candidate := node as CharacterBody3D
			if seen.has(candidate.get_instance_id()):
				continue
			seen[candidate.get_instance_id()] = true
			if not _is_active_hostile_candidate(candidate):
				continue
			if not attacker_team.is_empty() and _get_combat_team(candidate) != attacker_team:
				continue
			var offset := candidate.global_position - global_position
			offset.y = 0.0
			if offset.length_squared() <= 0.001:
				continue
			var alignment := attack_direction.dot(offset.normalized())
			if alignment <= 0.05:
				continue
			var score := offset.length() * (1.2 - alignment)
			if score < best_score:
				best_score = score
				best = candidate
	if not is_instance_valid(best):
		return false
	_activate_retaliation_target(best)
	return true


func _activate_retaliation_target(attacker: CharacterBody3D) -> void:
	target_player = attacker
	combat_target_refresh_timer = combat_target_refresh_interval
	var direction := attacker.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.001:
		rotation.y = atan2(-direction.x, -direction.z)
	aim_marker.global_position = attacker.global_position + Vector3.UP
	_update_weapon_alignment()
	fire_timer = 0.0


func receive_bullet_hit(hit_direction: Vector3, force: float, attacker_team: String) -> void:
	if attacker_team == team_id or force <= 0.0:
		return
	var horizontal := Vector3(hit_direction.x, 0.0, hit_direction.z)
	if horizontal.length_squared() > 0.001:
		knockback_velocity += horizontal.normalized() * force


func _die(attacker_team: String) -> void:
	if is_dead:
		return
	is_dead = true
	action_animation_locked = true
	_play_death_animation()
	if not attacker_team.is_empty():
		GameAuthority.award_team_ai_defeat(attacker_team, team_id, "Assistant AI")
	collision_layer = 0
	collision_mask = _corpse_collision_mask()
	if body_collision != null:
		body_collision.set_deferred("disabled", false)
	if hit_collision != null:
		hit_collision.set_deferred("disabled", true)
	if health_label != null:
		health_label.visible = false
	if is_instance_valid(drone):
		drone.queue_free()
	drone = null
	if _uses_external_squad_respawn():
		respawn_timer = -1.0
		external_respawn_controller.notify_squad_member_dead(self)
		call_deferred("_finish_squad_member_death")
	else:
		respawn_timer = respawn_seconds


func _finish_squad_member_death() -> void:
	## 与 FutureWarrior/FutureEngineer 一样，保留死亡节点十秒供表现和
	## 网络同步，之后移除；下一批成员只由 EnemySquadSpawner 生成。
	await get_tree().create_timer(DEATH_CLEANUP_SECONDS).timeout
	if is_inside_tree() and is_dead and _uses_external_squad_respawn():
		queue_free()


func _respawn() -> void:
	var world: Node = GlobalVar.gameworld
	if is_instance_valid(world) and world.has_method("get_spawn_position_for_id"):
		var spawn_value: Variant = world.call(
			"get_spawn_position_for_id", spawn_point_id, team_id, 3, get_instance_id()
		)
		if spawn_value is Vector3 and spawn_value != Vector3.INF:
			global_position = spawn_value as Vector3
	current_hp = max_hp
	is_dead = false
	action_animation_locked = false
	collision_layer = 8
	collision_mask = 647
	if body_collision != null:
		body_collision.set_deferred("disabled", false)
	if hit_collision != null:
		hit_collision.set_deferred("disabled", false)
	_update_label()
	operation_state = OperationState.CONTROLLING_DRONE
	deployment_origin = Vector3.INF
	deployment_position = Vector3.INF
	enemy_spawn_target = Vector3.INF
	advancing_for_signal_recovery = false
	knockback_velocity = Vector3.ZERO
	target_player = null
	combat_target_refresh_timer = 0.0
	squad_support_broadcast_active = false
	squad_support_request_timer = 0.0
	_clear_squad_support()
	_clear_squad_warning()
	_squad_escape_direction = Vector3.ZERO
	_squad_escape_timer = 0.0
	_squad_escape_waypoint = INVALID_POSITION
	_reset_squad_stuck_tracking()
	_reset_navigation_path()
	call_deferred("_start_drone_operation")


func get_combat_team() -> String:
	return team_id


func get_network_state() -> Dictionary:
	return {
		"ai_id": str(get_meta("network_ai_id", name)),
		"ai_type": "assistant",
		"name": name,
		"team": team_id,
		"position": global_position,
		"yaw": rotation.y,
		"hp": current_hp,
		"max_hp": max_hp,
		"dead": is_dead,
		"respawn_left": respawn_timer if is_dead else 0.0,
		"operation_state": int(operation_state),
		"velocity": velocity,
		"grounded": is_on_floor(),
	}


func apply_network_state(data: Dictionary) -> void:
	var was_dead := is_dead
	global_position = data.get("position", global_position) as Vector3
	rotation.y = float(data.get("yaw", rotation.y))
	current_hp = float(data.get("hp", current_hp))
	is_dead = bool(data.get("dead", is_dead))
	if is_dead:
		collision_layer = 0
		collision_mask = _corpse_collision_mask()
		if body_collision != null:
			body_collision.set_deferred("disabled", false)
		if hit_collision != null:
			hit_collision.set_deferred("disabled", true)
		if not was_dead:
			action_animation_locked = true
			_play_death_animation()
	if not is_dead:
		var velocity_value: Variant = data.get("velocity", Vector3.ZERO)
		var network_velocity := (
			velocity_value as Vector3
			if velocity_value is Vector3
			else Vector3.ZERO
		)
		_update_character_animation(network_velocity)
	_update_team_marker_visibility()
	if health_label != null:
		health_label.text = "Assistant AI  %d / %d" % [roundi(current_hp), roundi(max_hp)]
		health_label.visible = not bool(data.get("dead", false))


func _ensure_team_marker_visual() -> void:
	if is_instance_valid(team_marker):
		_update_team_marker_visibility()
		return
	team_marker = MeshInstance3D.new()
	team_marker.name = "TeamMarker"
	team_marker.position = Vector3.UP * TEAM_MARKER_HEIGHT
	team_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	team_marker.ignore_occlusion_culling = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	sphere.radial_segments = 16
	sphere.rings = 8
	team_marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = _team_marker_color()
	material.emission_enabled = true
	material.emission = _team_marker_color()
	material.emission_energy_multiplier = 2.5
	material.render_priority = 120
	team_marker.material_override = material
	add_child(team_marker)
	_update_team_marker_visibility()


func _team_marker_color() -> Color:
	return Color("#F04455") if team_id == "red" else Color("#398CFF")


func _local_viewer_team() -> String:
	for node in get_tree().get_nodes_in_group("human_players"):
		if not node is Node:
			continue
		if _has_property(node, "is_remote_proxy") and bool(node.get("is_remote_proxy")):
			continue
		var value := _get_combat_team(node)
		if not value.is_empty():
			return value
	return ""


func _update_team_marker_visibility() -> void:
	if not is_instance_valid(team_marker):
		return
	var material := team_marker.material_override as StandardMaterial3D
	var marker_color := _team_marker_color()
	if material != null:
		material.albedo_color = marker_color
		material.emission = marker_color
	var viewer_team := _local_viewer_team()
	team_marker.visible = (viewer_team.is_empty() or viewer_team == team_id) and not is_dead


func _get_combat_team(node: Node) -> String:
	if node.has_method("get_combat_team"):
		return str(node.call("get_combat_team"))
	return str(node.get("team")) if _has_property(node, "team") else str(node.get("team_id")) if _has_property(node, "team_id") else ""


func _has_property(object: Object, property_name: String) -> bool:
	for property_info: Dictionary in object.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false


func _update_label() -> void:
	if health_label != null:
		health_label.visible = not is_dead
		health_label.text = "Assistant AI  %d / %d" % [roundi(current_hp), roundi(max_hp)]


func _create_debug_label() -> void:
	debug_label = get_node_or_null("DebugStatus3D") as Label3D
	if debug_label == null:
		debug_label = Label3D.new()
		debug_label.name = "DebugStatus3D"
		add_child(debug_label)
	debug_label.position = Vector3(0.0, 3.35, 0.0)
	debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_label.font_size = 34
	debug_label.outline_size = 7
	debug_label.modulate = Color("#FFD166")
	debug_label.outline_modulate = Color("#18120A")


func _update_debug_label() -> void:
	if debug_label == null:
		return
	if is_dead:
		debug_label.visible = true
		debug_label.text = "DEBUG: 死亡复活 %.1fs" % respawn_timer
		return
	var state_text := ""
	match operation_state:
		OperationState.ADVANCE_TO_DEPLOYMENT:
			var remaining := _horizontal_distance_to(deployment_position) if deployment_position != Vector3.INF else -1.0
			state_text = "部署推进  %.1fm" % remaining if remaining >= 0.0 else "部署推进: 等待农场目标"
		OperationState.CONTROLLING_DRONE:
			state_text = "信号恢复推进" if advancing_for_signal_recovery else "无人机操控"
		OperationState.DEFENSIVE_PATROL:
			state_text = "防御警戒"
	var navigation_text := "导航: 已连接 | 困住: %s" % ("是" if _squad_stuck else "否") if _navigation_map_is_ready() else "导航: 等待/直线回退"
	var target_position := get_attack_target_position()
	var target_source := "target: %s" % target.name if is_instance_valid(target) else "target: 敌方出生点"
	var target_text := "%s  (%s)" % [target_source, _format_debug_position(target_position)]
	var drone_text := "无人机: 未部署"
	if is_instance_valid(drone):
		drone_text = "无人机: " + drone.get_debug_status()
	elif operation_state == OperationState.DEFENSIVE_PATROL:
		drone_text = "无人机重建: %.1fs" % respawn_timer
	debug_label.visible = true
	var squad_text := "Squad: 无"
	if not squad_member_id.is_empty():
		squad_text = "Squad: %s | 最近消息: %s" % [
			squad_member_id,
			last_squad_message_text if not last_squad_message_text.is_empty() else "无",
		]
	if squad_support_position.is_finite():
		squad_text += " | 无人机支援:%s" % _format_debug_position(squad_support_position)
	debug_label.text = "DEBUG Assistant: %s\n%s\n%s\n%s\n%s" % [state_text, target_text, navigation_text, drone_text, squad_text]


func _format_debug_position(value: Vector3) -> String:
	if value == Vector3.INF:
		return "未解析"
	return "%.1f, %.1f, %.1f" % [value.x, value.y, value.z]


func _debug(message: String) -> void:
	if console_debug_enabled and not GameAuthority.is_client_proxy():
		print("[AIAssistant] ", message)


func _emit_console_debug(delta: float) -> void:
	if not console_debug_enabled or GameAuthority.is_client_proxy():
		return
	if not (GameAuthority.is_local_authority() or GameAuthority.is_server_authority()):
		return
	console_debug_timer = maxf(0.0, console_debug_timer - delta)
	if console_debug_timer > 0.0:
		return
	console_debug_timer = console_debug_interval
	var state_text := "部署推进"
	if operation_state == OperationState.CONTROLLING_DRONE:
		state_text = "无人机操控"
	elif operation_state == OperationState.DEFENSIVE_PATROL:
		state_text = "防御警戒"
	var target_position := get_attack_target_position()
	var target_source := str(target.name) if is_instance_valid(target) else "敌方出生点"
	var drone_status := "未部署"
	if is_instance_valid(drone):
		drone_status = drone.get_console_debug_status() if drone.has_method("get_console_debug_status") else drone.get_debug_status()
	print(
		"[AIAssistant] name=%s team=%s state=%s pos=(%s) target=%s(%s) combat=%s stuck=%s squad=%s last_message=%s drone=%s"
		% [name, team_id, state_text, _format_debug_position(global_position), target_source,
			_format_debug_position(target_position),
			target_player.name if is_instance_valid(target_player) else "无",
			"是" if _squad_stuck else "否",
			squad_member_id if not squad_member_id.is_empty() else "无",
			last_squad_message_text if not last_squad_message_text.is_empty() else "无",
			drone_status]
	)


func _create_hand_mount() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 1.7, 0.0)
	add_child(head)
	aim_marker = Marker3D.new()
	aim_marker.name = "AimMarker"
	head.add_child(aim_marker)
	upper_body_look_target = Marker3D.new()
	upper_body_look_target.name = "UpperBodyLookTarget"
	head.add_child(upper_body_look_target)
	right_hand_ik_target = Marker3D.new()
	right_hand_ik_target.name = "RightHandIKTarget"
	right_hand_ik_target.position = Vector3(0.28, -0.28, -0.42)
	head.add_child(right_hand_ik_target)
	right_elbow_pole = Marker3D.new()
	right_elbow_pole.name = "RightElbowPole"
	right_elbow_pole.position = Vector3(0.65, 1.2, -0.1)
	add_child(right_elbow_pole)
	right_hand_socket = BoneAttachment3D.new()
	right_hand_socket.name = "RightHandSocket"
	right_hand_socket.bone_name = "Hand.R"
	add_child(right_hand_socket)
	tool_pivot = Node3D.new()
	tool_pivot.name = "ToolPivot"
	right_hand_socket.add_child(tool_pivot)


func _load_assistant_appearance() -> void:
	var scene := load("res://character/hero_skeleton/assistant_%s.tscn" % team_id) as PackedScene
	if scene == null:
		return
	var appearance := scene.instantiate() as Node3D
	if appearance == null:
		return
	appearance.name = "AppearanceNode"
	appearance.rotation.y = deg_to_rad(180.0)
	add_child(appearance)
	appearance_player = appearance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = appearance.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	right_hand_socket.use_external_skeleton = true
	right_hand_socket.external_skeleton = right_hand_socket.get_path_to(skeleton)
	right_hand_socket.bone_name = "Hand.R"
	right_hand_socket.override_pose = false
	_setup_upper_body_aim()
	if appearance_player != null and not appearance_player.animation_finished.is_connected(_on_skeleton_animation_finished):
		appearance_player.animation_finished.connect(_on_skeleton_animation_finished)
	if appearance_player != null and appearance_player.has_animation(&"Idle"):
		appearance_player.play(&"Idle")


func _update_weapon_alignment() -> void:
	if nailgun == null or tool_pivot == null or aim_marker == null:
		return
	var muzzle := nailgun.get_node_or_null("Muzzle") as Node3D
	if muzzle == null:
		return
	var weapon_aim_basis := muzzle.global_transform.basis.orthonormalized()
	if weapon_aim_basis.determinant() == 0.0:
		return
	var pivot_basis := tool_pivot.global_transform.basis.orthonormalized()
	var aim_from_pivot := (pivot_basis.inverse() * weapon_aim_basis).orthonormalized()
	var desired_pivot_basis := (aim_marker.global_transform.basis.orthonormalized() * aim_from_pivot.inverse()).orthonormalized()
	tool_pivot.global_transform = Transform3D(desired_pivot_basis, tool_pivot.global_position)


func _setup_upper_body_aim() -> void:
	upper_body_look_modifiers.clear()
	upper_body_look_weights.clear()
	_add_upper_body_look("SpineLook", "Spine", 0.10, 20.0)
	_add_upper_body_look("ChestLook", "Chest", 0.22, 30.0)
	_add_upper_body_look("NeckLook", "Neck", 0.16, 35.0)
	_add_upper_body_look("HeadLook", "Head_2", 0.28, 50.0)
	right_arm_ik = skeleton.find_child("RightArmIK", false, false) as TwoBoneIK3D
	if right_arm_ik == null:
		right_arm_ik = TwoBoneIK3D.new()
		right_arm_ik.name = "RightArmIK"
		skeleton.add_child(right_arm_ik)
	right_arm_ik.setting_count = 1
	right_arm_ik.set_root_bone_name(0, "UpperArm.R")
	right_arm_ik.set_middle_bone_name(0, "Forearm.R")
	right_arm_ik.set_end_bone_name(0, "Hand.R")
	right_arm_ik.set_use_virtual_end(0, false)
	right_arm_ik.set_extend_end_bone(0, false)
	right_arm_ik.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_X)
	right_arm_ik.set_target_node(0, right_arm_ik.get_path_to(right_hand_ik_target))
	right_arm_ik.set_pole_node(0, right_arm_ik.get_path_to(right_elbow_pole))
	right_arm_ik.active = true
	right_arm_ik.influence = 0.0


func _add_upper_body_look(node_name: String, bone_name: String, weight: float, limit_degrees: float) -> void:
	var modifier := skeleton.find_child(node_name, false, false) as LookAtModifier3D
	if modifier == null:
		modifier = LookAtModifier3D.new()
		modifier.name = node_name
		skeleton.add_child(modifier)
	modifier.bone_name = bone_name
	modifier.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	modifier.primary_rotation_axis = Vector3.AXIS_X
	modifier.use_secondary_rotation = false
	modifier.relative = true
	modifier.use_angle_limitation = true
	modifier.symmetry_limitation = true
	modifier.primary_limit_angle = deg_to_rad(limit_degrees)
	modifier.primary_damp_threshold = 1.0
	modifier.target_node = modifier.get_path_to(upper_body_look_target)
	modifier.active = true
	modifier.influence = 0.0
	upper_body_look_modifiers.append(modifier)
	upper_body_look_weights.append(weight)


func _update_aim_reference() -> void:
	if head == null or aim_marker == null or upper_body_look_target == null:
		return
	var target_position := head.global_position - global_transform.basis.z * 40.0
	if is_instance_valid(target_player):
		target_position = target_player.global_position + Vector3.UP
	upper_body_look_target.global_position = target_position
	aim_marker.global_position = head.global_position
	if target_position.distance_squared_to(aim_marker.global_position) > 0.001:
		aim_marker.look_at(target_position, Vector3.UP)


func _update_upper_body_aim(delta: float) -> void:
	for index in range(upper_body_look_modifiers.size()):
		var modifier := upper_body_look_modifiers[index]
		if is_instance_valid(modifier):
			var desired := upper_body_look_weights[index] * (0.7 if action_animation_locked else 1.0)
			modifier.influence = move_toward(modifier.influence, desired, delta * 3.5)
	if is_instance_valid(right_arm_ik):
		var desired_ik := 0.62 if action_animation_locked else 0.82
		right_arm_ik.influence = move_toward(right_arm_ik.influence, desired_ik, delta * 5.0)


func _on_skeleton_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"ShootOneHand" or animation_name == &"JumpLand":
		action_animation_locked = false


func _play_death_animation() -> void:
	action_animation_locked = true
	if appearance_player == null:
		return
	var animation_name: StringName = &"Death"
	if not appearance_player.has_animation(animation_name):
		# 旧 Assistant 外观资源使用这个兼容名称；新资源仍优先使用 Death。
		animation_name = &"DeathFallForward"
	if appearance_player.has_animation(animation_name):
		# 死亡节点可能已经被小队/多人视觉系统暂停；死亡动画本身必须继续更新。
		appearance_player.process_mode = Node.PROCESS_MODE_ALWAYS
		appearance_player.set_process(true)
		appearance_player.play(animation_name, 0.05)


func _update_character_animation(
	actual_horizontal_velocity: Vector3 = Vector3.ZERO
) -> void:
	if appearance_player == null or action_animation_locked:
		return
	var horizontal_velocity := actual_horizontal_velocity
	horizontal_velocity.y = 0.0
	var animation_name: StringName = &"Walk" if horizontal_velocity.length_squared() > 0.01 else &"IdleTool"
	if appearance_player.has_animation(animation_name) \
		and (appearance_player.current_animation != animation_name or not appearance_player.is_playing()):
		appearance_player.play(animation_name, 0.08)
