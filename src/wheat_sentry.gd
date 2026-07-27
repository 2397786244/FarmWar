extends StaticBody3D
class_name WheatSentryTool

## 固定式自动炮台：
## - TurretYaw 仅绕本地 Y 轴旋转，炮口朝本地 +Z
## - Detect3D 保持为固定的 20m 球形警戒区；ShootingPoint 随 TurretYaw 转动
## - Hit3D 固定在根节点，不旋转
## - 当前锁定目标默认持续追踪，直到无效、死亡或被销毁

signal target_changed(target: Node3D)
signal reload_started()
signal reload_finished()
signal damaged(damage: float, effect: String, hp_left: float)
signal sentry_destroyed()
signal bullet_fired(target: Node3D)


@export_category("Team")

## 炮台所属队伍，例如 red / blue。
@export var tool_owner: String = ""


@export_category("Activation")

## 静态摆在地图中时保持 true，即进入场景后自动启用。
## 动态放置时建议关闭，或放置完成后明确调用 configure_and_activate(team)。
@export var auto_activate_on_ready: bool = false


@export_category("Weapon")

## 在 Inspector 中指定炮塔发射的子弹 PackedScene。
@export var bullet_scene: PackedScene

## 子弹飞行速度，单位 m/s。
@export var bullet_speed: float = 60.0
@export var target_range: float = 20.0
@export var projectile_damage: float = 25.0
## Impact radius applies after a nail hits: nearby enemies/tools can be affected.
@export var impact_radius: float = 1.0
## The direct-hit sweep matches the player capsule (about 0.5m) plus the nail.
@export var direct_hit_radius: float = 0.56

## 单次弹匣最多发射的子弹数量。子弹数量必须是整数。
@export_range(1, 500, 1) var bullet_amount: int = 50

## 两发子弹之间的时间间隔，0.1 = 每秒约 10 发。
@export_range(0.02, 2.0, 0.01) var fire_interval: float = 1.50

## 打完 bullet_amount 后的装填时间。
@export_range(0.0, 60.0, 0.1) var reload_time: float = 15.0

## 炮口与目标水平夹角在该范围内才允许开火。
@export_range(1.0, 45.0, 1.0, "degrees") var fire_angle_tolerance_degrees: float = 7.0

## 子弹相对 ShootingPoint 的局部射击方向。
## 你的 ShootingPoint 就在枪口，且炮口朝本地 +Z。
## 所以这里固定默认为 Vector3(0, 0, 1)。
@export var fire_axis_local: Vector3 = Vector3(0.0, 0.0, 1.0)


@export_category("Turret Rotation")

## 未发现目标时的搜索速度，单位为弧度/秒。
@export var rotation_speed: float = 1.4

## 锁定目标后的水平转向速度，单位为弧度/秒。
@export var tracking_rotation_speed: float = 5.0

@export var scan_clockwise: bool = true


@export_category("Targeting")

## 队伍判定规则固定为：
## - GamePlayer 只读取 team。
## - ShieldTool / AutoShooterTool / AntiAirTool / NormalDrone / WheatSentryTool
##   只读取 tool_owner。
## - 读不到或为空：绝不列入攻击目标。

## 默认 false：锁定目标离开 Detect3D 后仍会持续攻击，直至目标无效或死亡。
## 设为 true：目标离开 Detect3D 后立即丢失锁定。
@export var drop_target_when_left_detection: bool = false

## 在该周期内重新检查 Detect3D 的 overlap，
## 解决目标先进入区域、后才设置 tool_owner 时无法触发 body_entered 的情况。
@export_range(0.1, 3.0, 0.05) var target_refresh_interval: float = 0.35


@export_category("Health")

@export var current_hp: float = 500.0
@export var hp_debug_label: bool = true

@export_range(0.0, 1.0, 0.05) var freeze_rotation_multiplier: float = 0.35
@export var freeze_duration: float = 2.0
@export var flame_duration: float = 4.0
@export_range(0.0, 2.0, 0.05) var flame_damage_multiplier_per_second: float = 0.25

@export var destroyed_effect_scene: PackedScene


@export_category("Debug")

## 勾选后会向 Output 输出目标发现、锁定、丢失、射击、装填等信息。
@export var debug_enabled: bool = false

## 输出更详细的候选目标和目标无效原因。
@export var debug_verbose: bool = false

@export_range(0.2, 5.0, 0.1) var debug_status_interval: float = 0.75


@export_category("Debug Runtime State - Do Not Edit")

## 以下字段会在运行时更新，方便从 Remote Inspector 查看。
@export var debug_state: String = "NOT_READY"
@export var debug_locked_target_name: String = "<none>"
@export var debug_locked_target_type: String = "<none>"
@export var debug_locked_target_path: String = "<none>"
@export var debug_locked_target_priority: int = -1
@export var debug_locked_target_team: String = "<none>"
@export var debug_locked_target_position: Vector3 = Vector3.ZERO
@export var debug_locked_target_distance: float = -1.0
@export var debug_aim_error_degrees: float = -1.0
@export var debug_fire_direction: Vector3 = Vector3.ZERO
@export var debug_detected_target_count: int = 0
@export var debug_bullets_left: int = 0
@export var debug_reload_left: float = 0.0


@onready var visual_model: Node3D = get_node_or_null("WheatSentry") as Node3D
@onready var hit_3d: Area3D = get_node_or_null("Hit3D") as Area3D
@onready var detect_3d: Area3D = get_node_or_null("Detect3D") as Area3D
@onready var shooting_point: Marker3D = get_node_or_null("ShootingPoint") as Marker3D
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D

## GLB 内部的可旋转炮台节点。
var turret_yaw: Node3D

## 记录 ShootingPoint 相对于 TurretYaw 的初始世界关系。
## Detect3D 不跟随炮塔旋转，确保警戒范围始终是固定球体。
var _shooting_transform_relative_to_yaw: Transform3D = Transform3D.IDENTITY

var _current_target: Node3D
var _detected_targets: Array[Node3D] = []

var _bullets_left: int = 0
var _shot_cooldown_left: float = 0.0
var _is_reloading: bool = false
var _reload_left: float = 0.0

var _freeze_left: float = 0.0
var _flame_left: float = 0.0
var _flame_damage_per_second: float = 0.0
var _electronics_disabled_remaining: float = 0.0

var _refresh_left: float = 0.0
var _debug_status_left: float = 0.0
var _is_active: bool = false
var _is_destroyed: bool = false
var _setup_finished: bool = false


func _ready() -> void:
	_bullets_left = bullet_amount
	current_hp = maxf(current_hp, 0.0)
	_update_health_label()
	_update_debug_runtime_state()

	_find_turret_yaw()
	_connect_detection_signals()
	_cache_rotating_node_relationships()

	# Deferred：允许动态放置逻辑在 add_child() 后、同一帧内完成 team/owner 设置。
	call_deferred("_finish_setup")


func _finish_setup() -> void:
	_setup_finished = true

	if turret_yaw == null:
		debug_state = "ERROR_NO_TURRET_YAW"
		_debug_log("初始化失败：没有找到 GLB 内的 TurretYaw。")
		return

	_sync_rotating_nodes_to_turret()
	_seed_detected_targets()

	if auto_activate_on_ready:
		_activate_tool()
	else:
		debug_state = "READY_INACTIVE"

	_update_debug_runtime_state()
	_debug_log("初始化完成。owner=%s, active=%s, bullets=%d" % [tool_owner, str(_is_active), _bullets_left])


## 启用炮台。
func _activate_tool() -> void:
	print("ACTIVE!")
	if _is_destroyed:
		return

	if not _setup_finished:
		call_deferred("activate_tool")
		return

	# 炮台必须先有明确阵营，避免刚放入场景时误伤任何目标。
	if tool_owner.strip_edges().is_empty():
		_is_active = false
		debug_state = "WAITING_FOR_TOOL_OWNER"
		_debug_log("未启用：tool_owner 为空。请先设置为 red 或 blue，再调用 activate_tool()。")
		return

	_is_active = true
	_update_health_label()
	collision_layer = 128 # set tool
	debug_state = "ACTIVE_SCANNING"
	_seed_detected_targets()
	_debug_log("炮台已启用。owner=%s, detected=%d" % [tool_owner, _detected_targets.size()])

## 外部调用API
func activate_tool():
	#print("CALL!")
	if tool_owner.is_empty():
		return
	_activate_tool()


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	_is_active = true
	_update_health_label()


func _update_health_label() -> void:
	if not is_instance_valid(health_label):
		return
	health_label.visible = hp_debug_label and _is_active
	health_label.text = "%d" % int(ceil(current_hp))


func get_network_visual_state() -> Dictionary:
	if turret_yaw == null:
		return {}
	return {
		"base_yaw": rotation.y,
		"turret_yaw": turret_yaw.rotation.y,
	}


func apply_network_visual_state(state: Dictionary) -> void:
	if turret_yaw == null:
		_find_turret_yaw()
		_cache_rotating_node_relationships()
	if turret_yaw == null:
		return
	rotation.y = float(state.get("base_yaw", rotation.y))
	turret_yaw.rotation.y = float(state.get("turret_yaw", turret_yaw.rotation.y))
	_sync_rotating_nodes_to_turret()


func apply_authoritative_target_position(target_position: Vector3, delta: float) -> void:
	if _is_destroyed or is_electronics_disabled():
		return
	_is_active = true
	debug_state = "TRACKING"
	_rotate_turret_toward(target_position, delta)


func apply_authoritative_idle_rotation(delta: float) -> void:
	if _is_destroyed or is_electronics_disabled():
		return
	_is_active = true
	debug_state = "SCANNING"
	_rotate_turret_idle(delta)


func is_authoritative_fire_ready(target_position: Vector3) -> bool:
	if shooting_point == null or is_electronics_disabled():
		return false
	var fire_direction := _get_fire_direction()
	var to_target := target_position - shooting_point.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.00001:
		return true
	return fire_direction.dot(to_target.normalized()) >= cos(deg_to_rad(fire_angle_tolerance_degrees))


func get_authoritative_fire_origin() -> Vector3:
	return shooting_point.global_position if shooting_point != null else global_position + Vector3.UP * 1.2


func get_authoritative_fire_direction() -> Vector3:
	return _get_fire_direction()
	
## 可在 Tool 被收回、禁用或断电时调用。
func deactivate_tool() -> void:
	_is_active = false
	_set_current_target(null, "炮台被停用")
	debug_state = "INACTIVE"
	_debug_log("炮台已停用。")


func _physics_process(delta: float) -> void:
	if _is_destroyed:
		return

	_update_status_effects(delta)

	if _is_destroyed:
		return

	if not _is_active:
		_update_debug_runtime_state()
		return
	# GameAuthority is the only combat/rotation authority in local and networked
	# matches. Running this legacy local target loop as well would overwrite the
	# replicated turret direction and duplicate shots.
	if GameAuthority.is_local_authority() or GameAuthority.is_server_authority() or GameAuthority.is_client_proxy():
		_update_debug_runtime_state()
		return

	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = target_refresh_interval
		_seed_detected_targets()

	_cleanup_detected_targets()

	# 锁定目标若死亡、释放、变为友军，或配置要求离开侦测区则取消锁定。
	if _current_target != null:
		var invalid_reason := _get_target_invalid_reason(_current_target)

		if invalid_reason.is_empty() and drop_target_when_left_detection:
			if not _detected_targets.has(_current_target):
				invalid_reason = "目标离开 Detect3D"

		if not invalid_reason.is_empty():
			_set_current_target(null, invalid_reason)

	# 没有锁定目标时，按优先级获取新的目标。
	if _current_target == null:
		var best_target := _select_best_target()
		if best_target != null:
			_set_current_target(best_target, "按威胁优先级锁定")

	if _current_target != null:
		debug_state = "TRACKING"
		_rotate_turret_toward(_current_target.global_position, delta)
	else:
		debug_state = "SCANNING"
		_rotate_turret_idle(delta)

	_update_reload_and_fire_cooldown(delta)

	if _is_reloading:
		debug_state = "RELOADING" if _current_target == null else "RELOADING_TRACKING"
		_update_debug_runtime_state()
		_debug_tick(delta)
		return

	if _current_target != null:
		_try_fire_at_current_target()

	_update_debug_runtime_state()
	_debug_tick(delta)


func _find_turret_yaw() -> void:
	if visual_model == null:
		push_error("WheatSentryTool: 未找到根节点下的 GLB 节点 WheatSentry。")
		return

	turret_yaw = visual_model.find_child("TurretYaw", true, false) as Node3D

	if turret_yaw == null:
		push_error("WheatSentryTool: GLB 内未找到 TurretYaw 节点。")
		return

	_debug_log("找到 TurretYaw: %s" % turret_yaw.get_path())


func _connect_detection_signals() -> void:
	if hit_3d == null:
		push_error("WheatSentryTool: 未找到 Hit3D。")
	else:
		hit_3d.monitoring = true
		if not hit_3d.body_entered.is_connected(_on_hit_3d_body_entered):
			hit_3d.body_entered.connect(_on_hit_3d_body_entered)

	if detect_3d == null:
		push_error("WheatSentryTool: 未找到 Detect3D。")
	else:
		detect_3d.monitoring = true
		if not detect_3d.body_entered.is_connected(_on_detect_3d_body_entered):
			detect_3d.body_entered.connect(_on_detect_3d_body_entered)
		if not detect_3d.body_exited.is_connected(_on_detect_3d_body_exited):
			detect_3d.body_exited.connect(_on_detect_3d_body_exited)

	if shooting_point == null:
		push_error("WheatSentryTool: 未找到 ShootingPoint。")


func _cache_rotating_node_relationships() -> void:
	if turret_yaw == null:
		return

	if shooting_point != null:
		_shooting_transform_relative_to_yaw = (
			turret_yaw.global_transform.affine_inverse()
			* shooting_point.global_transform
		)


## 只同步炮口 Transform，不使用 reparent()。
## Detect3D 和 Hit3D 都固定在根节点下。
func _sync_rotating_nodes_to_turret() -> void:
	if turret_yaw == null:
		return

	if shooting_point != null:
		shooting_point.global_transform = (
			turret_yaw.global_transform
			* _shooting_transform_relative_to_yaw
		)
		shooting_point.force_update_transform()


func _seed_detected_targets() -> void:
	if detect_3d == null:
		return

	# Area3D 在转动后可能有延迟，本函数会周期性补扫，避免漏掉已经在区域内的对象。
	for body in detect_3d.get_overlapping_bodies():
		if body is Node3D:
			_register_detected_body(body as Node3D, "overlap refresh")


func _on_detect_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests():
		return
	_register_detected_body(body, "body_entered")


func _on_detect_3d_body_exited(body: Node3D) -> void:
	var target := _resolve_attack_target(body)
	if target == null:
		return

	_detected_targets.erase(target)
	_debug_log_verbose("候选目标离开 Detect3D: %s" % _describe_target(target))

	if drop_target_when_left_detection and target == _current_target:
		_set_current_target(null, "目标离开 Detect3D")


func _register_detected_body(body: Node3D, source: String) -> void:
	if body == null or body == self:
		return

	var target := _resolve_attack_target(body)
	if target == null:
		_debug_log_verbose("Detect3D 发现非攻击对象: %s" % body.get_path())
		return

	if not _is_attackable_target(target):
		return

	var target_team := _get_target_team(target)
	if target_team.is_empty():
		_debug_log_verbose("忽略目标：没有可用队伍信息。%s" % _describe_target(target))
		return

	if not _is_enemy_target(target):
		_debug_log_verbose("忽略同队目标: %s, team=%s" % [_describe_target(target), target_team])
		return

	if _detected_targets.has(target):
		return

	_detected_targets.append(target)
	_debug_log("发现可攻击目标 [%s]: %s, priority=%d" % [source, _describe_target(target), _get_target_priority(target)])


func _resolve_attack_target(body: Node3D) -> Node3D:
	var node: Node = body

	# Detect3D 可能碰到目标根节点，也可能碰到目标内部的碰撞体。
	# 向上找第一个可攻击的实体根节点。
	while node != null and node != self:
		if node is Node3D and _is_attackable_target(node):
			return node as Node3D
		node = node.get_parent()

	return null


func _cleanup_detected_targets() -> void:
	for index in range(_detected_targets.size() - 1, -1, -1):
		var target := _detected_targets[index]
		if not _get_target_invalid_reason(target).is_empty():
			_detected_targets.remove_at(index)


func _select_best_target() -> Node3D:
	var best_target: Node3D
	var best_priority := -999999
	var best_distance_squared := INF

	for target in _detected_targets:
		if not _get_target_invalid_reason(target).is_empty():
			continue

		var priority := _get_target_priority(target)
		if priority < 0:
			continue

		var distance_squared := global_position.distance_squared_to(target.global_position)

		# 优先级更高者优先；相同优先级时攻击距离更近者。
		if priority > best_priority or (priority == best_priority and distance_squared < best_distance_squared):
			best_target = target
			best_priority = priority
			best_distance_squared = distance_squared

	return best_target


func _set_current_target(target: Node3D, reason: String) -> void:
	if target == _current_target:
		return

	var previous_description := _describe_target(_current_target)
	_current_target = target
	_update_debug_runtime_state()

	if _current_target != null:
		_debug_log("锁定目标：%s | team=%s | reason=%s | priority=%d" % [_describe_target(_current_target), _get_target_team(_current_target), reason, _get_target_priority(_current_target)])
	else:
		_debug_log("丢失目标：%s | reason=%s" % [previous_description, reason])

	target_changed.emit(_current_target)


func _get_target_invalid_reason(target: Node3D) -> String:
	if target == null:
		return "target 为 null"

	if not is_instance_valid(target):
		return "target 已失效"

	if target.is_queued_for_deletion():
		return "target 已 queue_free"

	if not _is_attackable_target(target):
		return "target 类型不再可攻击"

	if not _is_target_alive(target):
		return "target 已死亡或 HP <= 0"

	if not _is_enemy_target(target):
		return "target 不是敌方"

	return ""


func _is_target_alive(target: Node) -> bool:
	# 兼容你的不同角色/Tool 血量实现。
	if target.has_method("is_alive"):
		return bool(target.call("is_alive"))

	if target.has_method("is_destroyed"):
		return not bool(target.call("is_destroyed"))

	for bool_property in ["is_dead", "dead", "is_destroyed"]:
		if _object_has_property(target, bool_property):
			if bool(target.get(bool_property)):
				return false

	for hp_property in ["current_hp", "hp", "health"]:
		if _object_has_property(target, hp_property):
			var hp_value = target.get(hp_property)
			if typeof(hp_value) == TYPE_INT or typeof(hp_value) == TYPE_FLOAT:
				if float(hp_value) <= 0.0:
					return false

	return true


func _is_attackable_target(target: Node) -> bool:
	return (
		target is GamePlayer
		or target is NormalDrone
		or target is AutoShooterTool
		or target is AntiAirTool
		or target is WheatSentryTool
		or target is ShieldTool
	)


func _get_target_priority(target: Node) -> int:
	if target is GamePlayer:
		return 100
	if target is NormalDrone:
		return 80
	if target is AutoShooterTool:
		return 80
	if target is AntiAirTool:
		return 60
	if target is WheatSentryTool:
		return 50
	if target is ShieldTool:
		return 40
	return -1


func _is_enemy_target(target: Node) -> bool:
	# 队伍未知的对象永远不攻击。
	var target_team := _get_target_team(target)

	if target_team.is_empty():
		return false

	# 当前炮台的队伍也必须明确；activate_tool() 同样会检查。
	if tool_owner.strip_edges().is_empty():
		return false

	return target_team.to_lower() != tool_owner.strip_edges().to_lower()


func _get_target_team(target: Node) -> String:
	if target == null:
		return ""

	# 玩家只使用 GamePlayer.team。
	if target is GamePlayer:
		if _object_has_property(target, "team"):
			return str(target.get("team")).strip_edges()
		return ""

	# 所有可放置 Tool / 无人机只使用 tool_owner。
	if (
		target is ShieldTool
		or target is AutoShooterTool
		or target is AntiAirTool
		or target is NormalDrone
		or target is WheatSentryTool
	):
		if _object_has_property(target, "tool_owner"):
			return str(target.get("tool_owner")).strip_edges()
		return ""

	return ""


func _rotate_turret_idle(delta: float) -> void:
	if turret_yaw == null:
		return

	var direction := 1.0 if scan_clockwise else -1.0
	turret_yaw.rotation.y += direction * _get_effective_rotation_speed(rotation_speed) * delta
	_sync_rotating_nodes_to_turret()


func _rotate_turret_toward(target_position: Vector3, delta: float) -> void:
	if turret_yaw == null:
		return

	# 只使用 XZ 平面，永远不产生 Pitch / Roll。
	var flat_target_position := Vector3(target_position.x, turret_yaw.global_position.y, target_position.z)
	var world_direction := flat_target_position - turret_yaw.global_position

	if world_direction.length_squared() < 0.00001:
		return

	world_direction = world_direction.normalized()

	var yaw_parent := turret_yaw.get_parent() as Node3D
	if yaw_parent == null:
		return

	# 将世界方向转换到 TurretYaw 父节点的本地空间。
	var local_direction := yaw_parent.global_transform.basis.inverse() * world_direction

	# 当前炮台模型和 ShootingPoint 的枪口前方均为本地 +Z。
	# 因此局部 +Z 对准 local_direction 时：yaw = atan2(x, z)。
	var desired_local_yaw := atan2(local_direction.x, local_direction.z)

	turret_yaw.rotation.y = rotate_toward(
		turret_yaw.rotation.y,
		desired_local_yaw,
		_get_effective_rotation_speed(tracking_rotation_speed) * delta
	)

	_sync_rotating_nodes_to_turret()


func _get_effective_rotation_speed(base_speed: float) -> float:
	return base_speed * freeze_rotation_multiplier if _freeze_left > 0.0 else base_speed


func _update_reload_and_fire_cooldown(delta: float) -> void:
	_shot_cooldown_left = maxf(_shot_cooldown_left - delta, 0.0)

	if not _is_reloading:
		return

	_reload_left -= delta
	if _reload_left > 0.0:
		return

	_is_reloading = false
	_reload_left = 0.0
	_bullets_left = bullet_amount
	reload_finished.emit()
	_debug_log("装填完成，弹匣恢复为 %d 发。" % _bullets_left)


func _try_fire_at_current_target() -> void:
	if _shot_cooldown_left > 0.0 or _current_target == null:
		return

	if _bullets_left <= 0:
		_begin_reload()
		return

	if not _is_target_inside_fire_cone(_current_target):
		_debug_log_verbose("已锁定但尚未对准：%s" % _describe_target(_current_target))
		return

	if not _spawn_bullet():
		return

	_bullets_left -= 1
	_shot_cooldown_left = fire_interval
	bullet_fired.emit(_current_target)
	_debug_log_verbose("射击：target=%s, bullets_left=%d, fire_dir=%s" % [_describe_target(_current_target), _bullets_left, str(_get_fire_direction())])

	if _bullets_left <= 0:
		_begin_reload()


func _begin_reload() -> void:
	if _is_reloading:
		return

	_is_reloading = true
	_reload_left = reload_time
	reload_started.emit()
	_debug_log("弹匣耗尽，开始装填 %.2fs。" % reload_time)


func _is_target_inside_fire_cone(target: Node3D) -> bool:
	if shooting_point == null:
		return false

	var fire_direction := _get_fire_direction()
	var to_target := target.global_position - shooting_point.global_position
	to_target.y = 0.0

	if to_target.length_squared() < 0.00001:
		return true

	to_target = to_target.normalized()
	var allowed_dot := cos(deg_to_rad(fire_angle_tolerance_degrees))
	return fire_direction.dot(to_target) >= allowed_dot


func _get_fire_direction() -> Vector3:
	if shooting_point != null:
		var direction := shooting_point.global_transform.basis * fire_axis_local
		direction.y = 0.0
		if direction.length_squared() > 0.00001:
			return direction.normalized()

	if turret_yaw != null:
		# 炮台枪口前方为 TurretYaw 的本地 +Z。
		var fallback := turret_yaw.global_transform.basis.z
		fallback.y = 0.0
		if fallback.length_squared() > 0.00001:
			return fallback.normalized()

	return Vector3.FORWARD


func _spawn_bullet() -> bool:
	if GameAuthority.is_server_authority():
		return true
	if bullet_scene == null:
		_debug_log("无法射击：bullet_scene 未设置。")
		return false

	if shooting_point == null:
		_debug_log("无法射击：ShootingPoint 未找到。")
		return false

	var projectile = bullet_scene.instantiate()
	if not (projectile is Node3D):
		push_error("WheatSentryTool: bullet_scene 根节点必须是 Node3D。")
		projectile.queue_free()
		return false

	GlobalVar.gameworld.add_child(projectile)
	projectile.global_transform = shooting_point.global_transform
	if projectile is NailBullet:
		var nail := projectile as NailBullet
		nail.speed = bullet_speed
		nail.bullet_strength = projectile_damage
	
	var fire_direction = _get_fire_direction()
	projectile.run(shooting_point.global_position,fire_direction,tool_owner)
	#func run(
		#spawn_position: Vector3,
		#shoot_direction: Vector3,
		#shooter_team: String,
		#shooter_body: CollisionObject3D = null
	#) -> void:
	return true


func _write_property_if_exists(object: Object, property_name: String, value: Variant) -> void:
	if _object_has_property(object, property_name):
		object.set(property_name, value)


func _object_has_property(object: Object, property_name: String) -> bool:
	for property_info in object.get_property_list():
		if String(property_info.get("name", "")) == property_name:
			return true
	return false


## 受到攻击时调用。返回 true 说明本次伤害被接收。
func impact(effect: String, strength: float, shooter: String) -> bool:
	if _is_destroyed:
		return false

	if not shooter.strip_edges().is_empty() and shooter.to_lower() == tool_owner.to_lower():
		return false
	var normalized_effect := effect.to_lower()
	if normalized_effect == "repair_laser" or normalized_effect == "lightening" or normalized_effect == "lightning":
		var duration_effect := "repair_laser" if normalized_effect == "repair_laser" else "lightning"
		_electronics_disabled_remaining = maxf(_electronics_disabled_remaining, CombatBalance.get_electronic_disable_duration("wheat_sentry", duration_effect))
		_set_current_target(null, "电子设备停机")
		debug_state = "ELECTRONICS_DISABLED"
		return true

	var actual_damage := maxf(strength, 0.0)
	current_hp -= actual_damage
	_update_health_label()
	_apply_impact_effect(effect, actual_damage)
	damaged.emit(actual_damage, effect, maxf(current_hp, 0.0))
	_debug_log("受到攻击：effect=%s, damage=%.2f, hp=%.2f" % [effect, actual_damage, maxf(current_hp, 0.0)])

	if current_hp <= 0.0:
		_destroy_sentry()

	return true


func _apply_impact_effect(effect: String, strength: float) -> void:
	match effect.to_lower():
		"freeze", "frozen", "ice":
			_freeze_left = maxf(_freeze_left, freeze_duration)
		"flame", "fire", "burn", "burning":
			_flame_left = maxf(_flame_left, flame_duration)
			_flame_damage_per_second = maxf(_flame_damage_per_second, strength * flame_damage_multiplier_per_second)
		_:
			pass


func _update_status_effects(delta: float) -> void:
	_electronics_disabled_remaining = maxf(0.0, _electronics_disabled_remaining - delta)
	if _freeze_left > 0.0:
		_freeze_left = maxf(_freeze_left - delta, 0.0)

	if _flame_left > 0.0:
		_flame_left = maxf(_flame_left - delta, 0.0)
		var flame_damage := _flame_damage_per_second * delta
		if flame_damage > 0.0:
			current_hp -= flame_damage
			_update_health_label()
			damaged.emit(flame_damage, "Flame", maxf(current_hp, 0.0))
			if current_hp <= 0.0:
				_destroy_sentry()
				return

	if _flame_left <= 0.0:
		_flame_damage_per_second = 0.0


func is_electronics_disabled() -> bool:
	return _electronics_disabled_remaining > 0.0


func _on_hit_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests():
		return
	if not (body is BoomBullet or body is RubberBullet or body is ColorBullet or body is NailBullet):
		return

	var projectile_owner := ""
	if body.has_method("get_bullet_owner"):
		projectile_owner = str(body.call("get_bullet_owner"))
	elif _object_has_property(body, "bullet_owner"):
		projectile_owner = str(body.get("bullet_owner"))

	if projectile_owner.to_lower() == tool_owner.to_lower() and not projectile_owner.is_empty():
		return

	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet:
		effect = body.bullet_effect

	var strength: float = body.bullet_strength
	if impact(effect, strength, projectile_owner):
		body.queue_free()


func _destroy_sentry() -> void:
	if _is_destroyed:
		return

	_is_destroyed = true
	_is_active = false
	current_hp = 0.0
	_update_health_label()
	_set_current_target(null, "炮台被摧毁")

	if destroyed_effect_scene != null:
		var effect := destroyed_effect_scene.instantiate()
		if effect is Node3D:
			var effect_node := effect as Node3D
			var effect_parent: Node = get_tree().current_scene
			if effect_parent == null:
				effect_parent = get_parent()
			if effect_parent != null:
				effect_parent.add_child(effect_node)
				effect_node.global_position = global_position

	sentry_destroyed.emit()
	queue_free()


func get_locked_target() -> Node3D:
	if _current_target == null or not is_instance_valid(_current_target):
		return null
	return _current_target


func debug_reacquire_target() -> void:
	_set_current_target(null, "手动调试重新选目标")
	_seed_detected_targets()
	_set_current_target(_select_best_target(), "手动调试重新选目标")


func _update_debug_runtime_state() -> void:
	debug_detected_target_count = _detected_targets.size()
	debug_bullets_left = _bullets_left
	debug_reload_left = maxf(_reload_left, 0.0)
	debug_fire_direction = _get_fire_direction()

	if _current_target != null and is_instance_valid(_current_target):
		debug_locked_target_name = _current_target.name
		debug_locked_target_type = _current_target.get_class()
		debug_locked_target_path = str(_current_target.get_path())
		debug_locked_target_priority = _get_target_priority(_current_target)
		debug_locked_target_team = _get_target_team(_current_target)
		debug_locked_target_position = _current_target.global_position
		debug_locked_target_distance = global_position.distance_to(_current_target.global_position)
		debug_aim_error_degrees = _get_aim_error_degrees(_current_target)
	else:
		debug_locked_target_name = "<none>"
		debug_locked_target_type = "<none>"
		debug_locked_target_path = "<none>"
		debug_locked_target_priority = -1
		debug_locked_target_team = "<none>"
		debug_locked_target_position = Vector3.ZERO
		debug_locked_target_distance = -1.0
		debug_aim_error_degrees = -1.0


func _get_aim_error_degrees(target: Node3D) -> float:
	if target == null or shooting_point == null:
		return -1.0

	var to_target := target.global_position - shooting_point.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.00001:
		return 0.0

	var dot_value := clampf(_get_fire_direction().dot(to_target.normalized()), -1.0, 1.0)
	return rad_to_deg(acos(dot_value))


func _debug_tick(delta: float) -> void:
	if not debug_enabled:
		return

	_debug_status_left -= delta
	if _debug_status_left > 0.0:
		return

	_debug_status_left = debug_status_interval
	_debug_log("STATE=%s | target=%s | team=%s | candidates=%d | bullets=%d | reload=%.2f | aim_error=%.1f° | fire_dir=%s" % [debug_state, _describe_target(_current_target), debug_locked_target_team, _detected_targets.size(), _bullets_left, maxf(_reload_left, 0.0), debug_aim_error_degrees, str(debug_fire_direction)])


func _debug_log(message: String) -> void:
	if debug_enabled:
		print("[WheatSentry:%s] %s" % [name, message])


func _debug_log_verbose(message: String) -> void:
	if debug_enabled and debug_verbose:
		print("[WheatSentry:%s][VERBOSE] %s" % [name, message])


func _describe_target(target: Node3D) -> String:
	if target == null:
		return "<none>"
	if not is_instance_valid(target):
		return "<invalid>"
	return "%s (%s @ %s)" % [target.name, target.get_class(), target.get_path()]


func emit():
	var user_node = get_node_or_null("../../../")  # 这里是根据玩家来的，因为这个工具放到了ToolPivot下面，如果是AIPlayer，注意这里要修改类型
	if not user_node:
		return
	var raycast = user_node.find_child("LookAtTarget",true)  # 这是玩家注视的Raycast。将手持的可放置工具放置玩家正视的位置				
	if tool_owner.is_empty() or not raycast:
		return
	if not raycast.is_colliding():
		return
	var gvec3 = raycast.get_collision_point()
	var sentry = load("res://character/weapons/WheatSentry.tscn").instantiate()
	GlobalVar.gameworld.add_child(sentry)
	sentry.global_position = gvec3 + Vector3(0,0.1,0)
	sentry.tool_owner = self.tool_owner
	sentry.activate_tool()
	
	
