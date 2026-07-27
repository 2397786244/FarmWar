extends CharacterBody3D
class_name SmallMouse

## ============================================================
## SmallMouse：地面遥控机械鼠
##
## 本脚本不会自动创建任何节点。
## 请在 SmallMouse.tscn 中手动创建并保持以下节点名：
##
## SmallMouse (CharacterBody3D，本脚本)
## ├── MouseVisual (Node3D，模型根节点；本脚本不直接控制它)
## ├── CollisionShape3D (CollisionShape3D，角色实体碰撞)
## ├── Hit3D (Area3D，子弹命中检测)
## │   └── CollisionShape3D (CollisionShape3D)
## ├── CameraPivot (Node3D，鼠标上下俯仰)
## │   └── Camera3D (Camera3D，遥控镜头)
## └── ActionMount (Marker3D，主动作/未来激光的发射起点)
##
## 推荐碰撞层：
## - SmallMouse 根 CharacterBody3D：Layer 128（Tool）
## - Hit3D Area3D：Layer 0，Mask 32（Bullet）
##
## 输入：
## - remote_left / remote_right / remote_forward / remote_backward：移动
## - remote_primary_action：唯一的主动作
## - remote_jump：跳跃（推荐新增）
##   若未定义 remote_jump，会自动回退使用 remote_ascend。
##
## 不使用：
## - remote_second_action
## - remote_interact
## - remote_descend
## - 任意轮子旋转或轮子驱动代码
##
## 坐标约定：
## - SmallMouse 模型前方为本地 +Z。
## - 鼠标左右：旋转 SmallMouse 根节点。
## - 鼠标上下：只旋转 CameraPivot 的 X 轴。
##
## 对外稳定 API：
## - activate_tool()
## - emit()
## - impact(effect, strength, attacker_team)
## ============================================================


signal remote_control_started
signal remote_control_stopped
signal remote_signal_lost
signal primary_action_requested

const NETWORK_SIMULATION_DELTA := 1.0 / 60.0
const SOFT_CORRECTION_DISTANCE := 0.04
const HARD_CORRECTION_DISTANCE := 1.5
const CORRECTION_BLEND := 0.25
const REMOTE_PRECISION_ACTION_MIN_EFFECTIVE_SIGNAL := 0.20


@export_group("Required Scene Nodes")
@export var require_mouse_visual: bool = false


@export_group("Basic")
@export var set_hp: float = 80.0
@export var use_distance: float = 80.0
@export var tool_owner: String = ""
@export var hp_debug_label: bool = true


@export_group("Ground Movement")
@export var move_speed: float = 7.0
@export var acceleration: float = 28.0
@export var braking_acceleration: float = 38.0

## 最大跳跃高度，代码按当前项目的重力换算为起跳速度。
@export_range(0.1, 5.0, 0.05) var max_jump_height: float = 1.15
@export_range(0.05, 5.0, 0.05) var jump_cooldown: float = 0.85


@export_group("Remote Camera")
@export var yaw_sensitivity: float = 0.0032
@export var enable_camera_pitch: bool = true
@export var camera_pitch_sensitivity: float = 0.0020

@export_range(5.0, 85.0, 1.0, "degrees")
var max_camera_pitch_degrees: float = 65.0


@export_group("Primary Action")
## 这里只负责主动作的输入、冷却和信号。
## 激光生成、射线命中、特效、伤害逻辑请在 _perform_primary_action() 内自行补充。
@export var primary_action_cooldown: float = 0.45
@export var primary_action_range: float = 60.0
@export var primary_action_damage: float = 5.0
@export var primary_action_visual_speed: float = 60.0


#@export_group("Damage")
#@export var rubber_bullet_damage: float = 10.0
#@export var nail_bullet_damage: float = 14.0
#@export var color_bullet_damage: float = 16.0


@onready var mouse_visual: Node3D = get_node_or_null("MouseVisual") as Node3D
@onready var body_collision_shape: CollisionShape3D = (
	$CollisionShape3D as CollisionShape3D
)
@onready var hit_area: Area3D = $Hit3D as Area3D
@onready var hit_collision_shape: CollisionShape3D = (
	$Hit3D/CollisionShape3D as CollisionShape3D
)
@onready var camera_pivot: Node3D = $CameraPivot as Node3D
@onready var mouse_camera: Camera3D = $CameraPivot/Camera3D as Camera3D
@onready var action_mount: Marker3D = $ActionMount as Marker3D
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D


var current_hp: float = 0.0

## 已经被工具 emit 放置到游戏世界。
var _placed := false

## 正在被玩家远程操控。
var _remote_control_active := false

## 已被摧毁，避免重复触发 remote_signal_lost。
var _destroyed := false

## 1.0 表示无干扰；由本地权威或多人服务器同步更新。
var jam_ratio: float = 1.0
## 1.0 表示没有增强，最大 100.0。
var aug_ratio: float = 1.0
var _remote_receiver: Node3D

var _camera_pitch := 0.0
var _jump_cooldown_left := 0.0
var _primary_action_cooldown_left := 0.0
var _capture_retry_frames := 0
var _server_authority_simulation := false
var _last_server_input_seq := 0
var _last_authoritative_jump_seq := 0
var _pending_network_inputs: Array[Dictionary] = []
var _pending_authority_snapshot: Dictionary = {}
var _electronics_disabled_remaining := 0.0
var _flame_remaining := 0.0
var _flame_damage_per_second := 0.0


func _ready() -> void:
	_update_health_label()

func _validate_required_scene_nodes() -> void:
	var missing: Array[String] = []

	if require_mouse_visual and mouse_visual == null:
		missing.append("MouseVisual (Node3D)")

	if body_collision_shape == null:
		missing.append("CollisionShape3D (CollisionShape3D)")

	if hit_area == null:
		missing.append("Hit3D (Area3D)")

	if hit_collision_shape == null:
		missing.append("Hit3D/CollisionShape3D (CollisionShape3D)")

	if camera_pivot == null:
		missing.append("CameraPivot (Node3D)")

	if mouse_camera == null:
		missing.append("CameraPivot/Camera3D (Camera3D)")

	if action_mount == null:
		missing.append("ActionMount (Marker3D)")

	if not missing.is_empty():
		push_error(
			"SmallMouse: 缺少场景节点："
			+ ", ".join(missing)
			+ "。本脚本不会自动创建节点，请按文件头节点结构手动补齐。"
		)
		set_process(false)
		set_physics_process(false)


# ------------------------------------------------------------------
# Remote control lifecycle
# ------------------------------------------------------------------

## 与 BoomBuggy / NormalDrone 保持兼容的旧调用别名。
func run() -> void:
	begin_remote_control()


func begin_remote_control() -> void:
	if not _placed:
		push_warning("SmallMouse: 尚未放置，不能进入遥控模式。")
		return

	if _destroyed:
		push_warning("SmallMouse: 已经被摧毁，不能进入遥控模式。")
		return

	var was_remote_control_active := _remote_control_active
	_remote_control_active = true

	_start_control_mode()

	if not was_remote_control_active:
		remote_control_started.emit()
	
func end_remote_control() -> void:
	stop()

func is_remote_control_active() -> bool:
	return _remote_control_active


func set_remote_receiver(receiver: Node3D) -> void:
	_remote_receiver = receiver


## Shared SignalJam / SignalAugment adapter.
func set_jam_ratio(value: float) -> void:
	jam_ratio = clampf(value, 0.01, 1.0)


func set_aug_ratio(value: float) -> void:
	aug_ratio = clampf(value, 1.0, 100.0)


func get_distance_signal_strength(receiver: Node3D) -> float:
	if not is_instance_valid(receiver):
		return 0.0

	var distance := global_position.distance_to(receiver.global_position)

	return clampf(
		(-distance + use_distance) / maxf(use_distance, 0.01),
		0.1,
		1.0
	)


## 公开信号质量：距离信号乘以干扰和增强比率。
func get_signal_strength(receiver: Node3D) -> float:
	return get_distance_signal_strength(receiver) \
		* clampf(jam_ratio, 0.01, 1.0) \
		* clampf(aug_ratio, 1.0, 100.0)


func get_effective_signal_strength(receiver: Node3D) -> float:
	return get_signal_strength(receiver)


func stop() -> void:
	if not _remote_control_active:
		return

	_remote_control_active = false
	velocity = Vector3.ZERO
	_capture_retry_frames = 0

	mouse_camera.current = false
	remote_control_stopped.emit()

	# 与玩家正常状态保持一致：退出遥控后继续捕获鼠标。
	call_deferred("_restore_player_mouse_capture")


func _start_control_mode() -> void:
	mouse_camera.make_current()
	_capture_retry_frames = 3

	call_deferred("_ensure_remote_camera_and_mouse")


func _ensure_remote_camera_and_mouse() -> void:
	if not _remote_control_active or _destroyed:
		return

	mouse_camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _restore_player_mouse_capture() -> void:
	if _remote_control_active:
		return

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------
# Input and movement
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	_tick_electronic_status(delta)
	if _capture_retry_frames <= 0:
		return

	_capture_retry_frames -= 1
	_ensure_remote_camera_and_mouse()


func _input(event: InputEvent) -> void:
	if not _placed or not _remote_control_active or _destroyed:
		return

	if not event is InputEventMouseMotion:
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var mouse_event := event as InputEventMouseMotion
	var mouse_delta := mouse_event.screen_relative

	# 小车同款：鼠标左右驱动根节点偏航。
	rotate_y(-mouse_delta.x * yaw_sensitivity)

	# 小车同款：鼠标上下只改变 CameraPivot 的俯仰。
	if enable_camera_pitch:
		var max_pitch := deg_to_rad(max_camera_pitch_degrees)

		_camera_pitch = clampf(
			_camera_pitch - mouse_delta.y * camera_pitch_sensitivity,
			-max_pitch,
			max_pitch
		)

		camera_pivot.rotation.x = _camera_pitch

	get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _server_authority_simulation:
		return
	if not _placed or _destroyed:
		return
	if is_electronics_disabled():
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * delta)
		_apply_gravity(delta)
		move_and_slide()
		return

	_jump_cooldown_left = maxf(
		0.0,
		_jump_cooldown_left - delta
	)
	_primary_action_cooldown_left = maxf(
		0.0,
		_primary_action_cooldown_left - delta
	)
	if not _pending_authority_snapshot.is_empty():
		var authority_snapshot := _pending_authority_snapshot
		_pending_authority_snapshot = {}
		_apply_authoritative_snapshot(authority_snapshot)
		return

	if not _remote_control_active:
		_update_idle_motion(NETWORK_SIMULATION_DELTA)
		return

	_update_ground_motion(NETWORK_SIMULATION_DELTA)

	if _jump_pressed():
		_try_jump()

func _update_idle_motion(delta: float) -> void:
	velocity.x = move_toward(
		velocity.x,
		0.0,
		braking_acceleration * delta
	)
	velocity.z = move_toward(
		velocity.z,
		0.0,
		braking_acceleration * delta
	)

	_apply_gravity(delta)
	move_and_slide()


func _update_ground_motion(delta: float) -> void:
	var move_input := Input.get_vector(
		"remote_left",
		"remote_right",
		"remote_forward",
		"remote_backward"
	)
	_simulate_ground_motion(move_input, delta)


func _simulate_ground_motion(move_input: Vector2, delta: float) -> void:

	# 模型朝 +Z。
	# 此处与修正后的 BoomBuggy 控制方式一致：
	# forward 按下后沿 basis.z 移动，而不是 Godot 常见的 -basis.z。
	var forward_direction := global_transform.basis.z
	var right_direction := -global_transform.basis.x

	forward_direction.y = 0.0
	right_direction.y = 0.0

	if forward_direction.length_squared() > 0.0001:
		forward_direction = forward_direction.normalized()

	if right_direction.length_squared() > 0.0001:
		right_direction = right_direction.normalized()

	var move_direction := (
		right_direction * move_input.x
		+ forward_direction * -move_input.y
	)

	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()

	var target_velocity := move_direction * move_speed
	var response := (
		acceleration
		if move_direction.length_squared() > 0.0001
		else braking_acceleration
	)

	velocity.x = move_toward(
		velocity.x,
		target_velocity.x,
		response * delta
	)
	velocity.z = move_toward(
		velocity.z,
		target_velocity.z,
		response * delta
	)

	_apply_gravity(delta)
	move_and_slide()


func simulate_authoritative_remote_input(input_frame: Dictionary, _delta: float) -> void:
	if not _placed or _destroyed:
		return
	if is_electronics_disabled():
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * NETWORK_SIMULATION_DELTA)
		_apply_gravity(NETWORK_SIMULATION_DELTA)
		move_and_slide()
		return
	_jump_cooldown_left = maxf(0.0, _jump_cooldown_left - NETWORK_SIMULATION_DELTA)
	rotation.y = float(input_frame.get("yaw", rotation.y))
	var move_value: Variant = input_frame.get("move", Vector2.ZERO)
	var move := move_value as Vector2 if move_value is Vector2 else Vector2.ZERO
	_simulate_ground_motion(move, NETWORK_SIMULATION_DELTA)
	var jump_seq := int(input_frame.get("jump_seq", 0))
	if jump_seq > _last_authoritative_jump_seq:
		_last_authoritative_jump_seq = jump_seq
		_try_jump()


func set_server_authority_simulation(enabled: bool) -> void:
	_server_authority_simulation = enabled
	if enabled:
		_placed = true
		place_ready_setting()
	set_physics_process(not enabled)


func record_network_prediction(input_frame: Dictionary) -> void:
	if not _remote_control_active:
		return
	_pending_network_inputs.append(input_frame.duplicate(true))
	if _pending_network_inputs.size() > 120:
		_pending_network_inputs.pop_front()


func apply_authoritative_snapshot(snapshot: Dictionary) -> void:
	_pending_authority_snapshot = snapshot.duplicate(true)


func _apply_authoritative_snapshot(snapshot: Dictionary) -> void:
	if not _remote_control_active:
		return
	_electronics_disabled_remaining = maxf(
		_electronics_disabled_remaining,
		float(snapshot.get("electronics_disabled_remaining", 0.0))
	)
	var authoritative_cooldown := float(snapshot.get("primary_action_cooldown", 0.0))
	if authoritative_cooldown > 0.0:
		primary_action_cooldown = authoritative_cooldown
	_primary_action_cooldown_left = maxf(
		_primary_action_cooldown_left,
		float(snapshot.get("primary_action_cooldown_left", 0.0))
	)
	var server_position: Variant = snapshot.get("position", global_position)
	var server_velocity: Variant = snapshot.get("velocity", velocity)
	if not server_position is Vector3 or not server_velocity is Vector3:
		return
	var acknowledged_seq := int(snapshot.get("last_input_seq", 0))
	if acknowledged_seq < _last_server_input_seq:
		return
	_last_server_input_seq = acknowledged_seq
	while not _pending_network_inputs.is_empty() and int(_pending_network_inputs.front().get("input_seq", 0)) <= acknowledged_seq:
		_pending_network_inputs.pop_front()
	var rendered_position := global_position
	var rendered_velocity := velocity
	var rendered_yaw := rotation.y
	global_position = server_position
	velocity = server_velocity
	rotation.y = float(snapshot.get("yaw", rotation.y))
	for frame in _pending_network_inputs:
		rotation.y = float(frame.get("yaw", rotation.y))
		var move_value: Variant = frame.get("move", Vector2.ZERO)
		var move := move_value as Vector2 if move_value is Vector2 else Vector2.ZERO
		_simulate_ground_motion(move, NETWORK_SIMULATION_DELTA)
	var reconciled_position := global_position
	var reconciled_velocity := velocity
	var reconciled_yaw := rotation.y
	var correction_distance := rendered_position.distance_to(reconciled_position)
	if correction_distance >= HARD_CORRECTION_DISTANCE:
		global_position = reconciled_position
		velocity = reconciled_velocity
		rotation.y = reconciled_yaw
	elif correction_distance >= SOFT_CORRECTION_DISTANCE:
		global_position = rendered_position.lerp(reconciled_position, CORRECTION_BLEND)
		velocity = rendered_velocity.lerp(reconciled_velocity, CORRECTION_BLEND)
		rotation.y = lerp_angle(rendered_yaw, reconciled_yaw, CORRECTION_BLEND)
	else:
		global_position = rendered_position
		velocity = rendered_velocity
		rotation.y = rendered_yaw


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0


func _jump_pressed() -> bool:
	# 推荐你在 Input Map 新建 remote_jump。
	# 为兼容已有 NormalDrone 输入，也允许 remote_ascend 作为备用跳跃键。
	var action_name := (
		"remote_jump"
		if InputMap.has_action("remote_jump")
		else "remote_ascend"
	)

	return (
		InputMap.has_action(action_name)
		and Input.is_action_just_pressed(action_name)
	)


func _try_jump() -> void:
	if not is_on_floor():
		return

	if _jump_cooldown_left > 0.0:
		return

	var gravity_strength := absf(get_gravity().y)

	# v^2 = 2gh：由最大高度换算起跳速度。
	velocity.y = sqrt(maxf(
		0.0,
		2.0 * gravity_strength * max_jump_height
	))

	_jump_cooldown_left = jump_cooldown


# ------------------------------------------------------------------
# Primary action
# ------------------------------------------------------------------

func _try_primary_action() -> void:
	if is_electronics_disabled() or _primary_action_cooldown_left > 0.0:
		return

	_primary_action_cooldown_left = primary_action_cooldown
	primary_action_requested.emit()
	if _submit_remote_authority_action("primary"):
		# Local authority has no client replicator to receive the server's visual
		# event, so it renders one collision-free LaserBullet locally. Multiplayer
		# clients wait for the server-confirmed visual instead.
		if GameAuthority.is_local_authority():
			_perform_primary_action(true)
		return

	# A local authority can reject the action (for example, weak signal). Do not
	# fall back to the legacy damaging projectile in that case.
	if GameAuthority.is_local_authority():
		_primary_action_cooldown_left = 0.0
		return
	_perform_primary_action(false)


func request_primary_action() -> void:
	if not _placed or not _remote_control_active or _destroyed:
		return
	_try_primary_action()


func get_primary_action_cooldown_remaining() -> float:
	return _primary_action_cooldown_left


func get_primary_action_cooldown_duration() -> float:
	return primary_action_cooldown


func is_electronics_disabled() -> bool:
	return _electronics_disabled_remaining > 0.0


func get_electronics_disabled_remaining() -> float:
	return _electronics_disabled_remaining


func _tick_electronic_status(delta: float) -> void:
	_electronics_disabled_remaining = maxf(0.0, _electronics_disabled_remaining - delta)
	if _flame_remaining <= 0.0:
		return
	var burn_tick := minf(delta, _flame_remaining)
	_flame_remaining = maxf(0.0, _flame_remaining - delta)
	if not GameAuthority.is_client_proxy():
		current_hp = maxf(0.0, current_hp - _flame_damage_per_second * burn_tick)
		_update_health_label()
	if _flame_remaining <= 0.0:
		_flame_damage_per_second = 0.0


@export_group("Primary Action Aim")
## 与其他射击武器保持一致：准星检测使用的碰撞层。
@export_flags_3d_physics var aim_collision_mask: int = 139
## 摄像机中心没有碰到物体时，默认瞄准到多远。
@export var max_aim_distance: float = 50  # DetectLaserBullet设定是50

func _get_center_screen_direction() -> Vector3:
	# SmallMouse 当前节点：
	# CameraPivot/Camera3D
	# ActionMount
	if not is_instance_valid(mouse_camera):
		# SmallMouse 正前方是本地 +Z。
		return global_transform.basis.z.normalized()
	if not is_instance_valid(action_mount):
		return global_transform.basis.z.normalized()
	var viewport = mouse_camera.get_viewport()
	if viewport == null:
		return global_transform.basis.z.normalized()

	# 1. 获取遥控画面正中心，也就是准星所在的位置。
	var screen_center = viewport.get_visible_rect().size * 0.5
	# 2. 从 SmallMouse 的 Camera3D 画面中心向世界投射射线。
	var camera_ray_origin = mouse_camera.project_ray_origin(screen_center)
	var camera_ray_direction = mouse_camera.project_ray_normal(
		screen_center
	).normalized()

	# 3. 先假设准星看向 max_aim_distance 米之外。
	var aim_point = (
		camera_ray_origin
		+ camera_ray_direction * max_aim_distance
	)

	# 4. 摄像机中心射线先检测真正命中的墙、敌人、地面、工具等。
	var query := PhysicsRayQueryParameters3D.create(
		camera_ray_origin,
		aim_point,
		aim_collision_mask
	)

	query.collide_with_bodies = true
	query.collide_with_areas = true

	# 排除 SmallMouse 根节点，防止准星射线打到自身碰撞体。
	query.exclude = [get_rid()]

	# Hit3D 是单独的 Area3D RID，也一并排除更稳妥。
	if is_instance_valid(hit_area):
		query.exclude.append(hit_area.get_rid())

	var hit = get_world_3d().direct_space_state.intersect_ray(query)

	# 摄像机准星射线有实际命中时，
	# 让 ActionMount 朝那个真实碰撞点发射。
	if not hit.is_empty():
		aim_point = hit["position"] as Vector3

	# 5. 真正的激光方向：
	# 从 SmallMouse 的 ActionMount 出发，指向画面中心的目标点。
	var laser_direction = (
		aim_point - action_mount.global_position
	)

	if laser_direction.length_squared() <= 0.0001:
		return global_transform.basis.z.normalized()

	return laser_direction.normalized()


func _get_crosshair_ray_origin() -> Vector3:
	if not is_instance_valid(mouse_camera):
		return action_mount.global_position if is_instance_valid(action_mount) else global_position
	var viewport := mouse_camera.get_viewport()
	if viewport == null:
		return mouse_camera.global_position
	return mouse_camera.project_ray_origin(viewport.get_visible_rect().size * 0.5)


func _get_crosshair_ray_direction() -> Vector3:
	if not is_instance_valid(mouse_camera):
		return global_transform.basis.z.normalized()
	var viewport := mouse_camera.get_viewport()
	if viewport == null:
		return -mouse_camera.global_transform.basis.z.normalized()
	return mouse_camera.project_ray_normal(viewport.get_visible_rect().size * 0.5).normalized()
	
func _perform_primary_action(visual_only := false) -> void:
	var laser_bullet = load("res://character/weapons/DetectLaserBullet.tscn").instantiate()
	_get_gameworld().add_child(laser_bullet)
	laser_bullet.global_position = action_mount.global_position
	if visual_only:
		laser_bullet.set("visual_only", true)
		laser_bullet.collision_layer = 0
		laser_bullet.collision_mask = 0
	laser_bullet.run(action_mount.global_position,_get_center_screen_direction(),tool_owner)


func _submit_remote_authority_action(action_name: String) -> bool:
	var network_device_id := ""
	if has_meta("network_device_id"):
		network_device_id = str(get_meta("network_device_id"))
	elif is_inside_tree():
		network_device_id = str(get_path())
	if network_device_id.is_empty():
		return false
	var action := {
		"device_id": network_device_id,
		"device_path": network_device_id,
		"device_type": "small_mouse",
		"action": action_name,
		"position": global_position,
		"velocity": velocity,
		"yaw": rotation.y,
		"direction": _get_center_screen_direction(),
		"aim_origin": _get_crosshair_ray_origin(),
		"aim_direction": _get_crosshair_ray_direction(),
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_remote_action(action)
		return true
	if GameAuthority.is_local_authority():
		var result: Dictionary = GameAuthority.local_remote_action(
			GameAuthority.LOCAL_PLAYER_ID,
			action
		)
		return bool(result.get("ok", false))
	return false


# ------------------------------------------------------------------
# External gameplay API
# ------------------------------------------------------------------

## 外部工具系统调用。
## 语义与 BoomBuggy 的 activate_tool() 保持一致：
## 放入游戏世界后激活碰撞层，标记为已部署，但不自动抢占玩家镜头。
func activate_tool() -> void:
	_camera_pitch = camera_pivot.rotation.x
	collision_layer = 128
	_placed = true
	_destroyed = false
	current_hp = set_hp
	place_ready_setting()
	_update_health_label()


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	_placed = true
	_update_health_label()


func place_ready_setting() -> void:
	# SmallMouse 是地面 CharacterBody3D。
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = 0.18
	floor_max_angle = deg_to_rad(48.0)
	# 由 activate_tool() 负责设为 Layer 128。
	# collision_mask 保留 tscn Inspector 中的配置。
	mouse_camera.current = false


## 外部手持工具调用。
## 语义与 BoomBuggy / NormalDrone 的 emit() 保持一致：
## 从使用者 LookAtTarget 的碰撞点生成一个新的 SmallMouse，
## 并返回 remote_node 给 GamePlayer 的 remote_device_start() 使用。
func emit() -> Dictionary:
	var user_node := get_node_or_null("../../../") as Node3D

	if user_node == null:
		push_warning("SmallMouse: 无法从 ../../../ 找到工具拥有者。")
		return {}

	if tool_owner.is_empty():
		push_warning("SmallMouse: tool_owner 为空，拒绝部署。")
		return {}

	var raycast := user_node.find_child(
		"LookAtTarget",
		true,
		false
	) as RayCast3D

	if raycast == null:
		push_warning("SmallMouse: 未找到 LookAtTarget RayCast3D。")
		return {}

	raycast.force_raycast_update()

	if not raycast.is_colliding():
		return {}

	var mouse_scene := load(
		"res://character/weapons/SmallMouse.tscn"
	) as PackedScene

	if mouse_scene == null:
		push_error("SmallMouse: 无法加载 res://character/weapons/SmallMouse.tscn。")
		return {}

	var mouse := mouse_scene.instantiate() as SmallMouse
	if mouse == null:
		push_error(
			"SmallMouse: SmallMouse.tscn 根节点必须继承 CharacterBody3D "
			+ "并挂载 small_mouse_remote_control.gd。"
		)
		return {}

	var world_root := _get_gameworld()
	world_root.add_child(mouse)

	mouse.global_position = raycast.get_collision_point() + Vector3.UP * 0.18
	mouse.global_rotation.y = user_node.global_rotation.y
	mouse.tool_owner = tool_owner
	mouse.activate_tool()
	return {
		"remote_node": mouse,
	}


## 外部伤害接口。
## 语义与 BoomBuggy 的 impact(effect, strength, attacker_team) 一致：
## - 忽略同队伤害
## - 根据 strength 扣血
## - HP 为零时断开遥控、发送 remote_signal_lost 并销毁
## - 不会产生 BoomBuggy 式爆炸
func impact(
	effect: String,
	strength: float,
	attacker_team: String = ""
) -> bool:
	if _destroyed:
		return false

	if not attacker_team.is_empty() and attacker_team == tool_owner:
		return false

	var normalized_effect := effect.to_lower()
	if normalized_effect == "repair_laser":
		_electronics_disabled_remaining = maxf(_electronics_disabled_remaining, CombatBalance.get_electronic_disable_duration("small_mouse", "repair_laser"))
		velocity = Vector3.ZERO
		return true
	var damage := maxf(strength, 0.0)
	if damage <= 0.0:
		return false

	current_hp = maxf(0.0, current_hp - damage)
	_update_health_label()

	if current_hp <= 0.0:
		_destroy_mouse(effect, attacker_team)
	elif normalized_effect == "flame" or normalized_effect == "fire":
		_flame_remaining = maxf(_flame_remaining, CombatBalance.get_float("remote_electronics", "flame_duration"))
		_flame_damage_per_second = maxf(_flame_damage_per_second, damage * CombatBalance.get_float("remote_electronics", "flame_damage_multiplier"))
	elif normalized_effect == "lightening" or normalized_effect == "lightning":
		_electronics_disabled_remaining = maxf(_electronics_disabled_remaining, CombatBalance.get_electronic_disable_duration("small_mouse", "lightning"))
		velocity = Vector3.ZERO

	return true


func _update_health_label() -> void:
	if not is_instance_valid(health_label):
		return
	health_label.visible = hp_debug_label and _placed
	health_label.text = "%d" % int(ceil(current_hp))


func _destroy_mouse(effect: String, attacker_team: String) -> void:
	if _destroyed:
		return

	_destroyed = true
	_remote_control_active = false
	velocity = Vector3.ZERO

	collision_layer = 0
	collision_mask = 0
	hit_area.monitoring = false
	mouse_camera.current = false

	remote_signal_lost.emit()

	print(
		"[SmallMouse] destroyed | effect=%s | attacker=%s"
		% [effect, attacker_team]
	)

	call_deferred("queue_free")


# ------------------------------------------------------------------
# Hit3D projectile receiving
# ------------------------------------------------------------------

func _on_hit_3d_body_entered(body: Node3D) -> void:
	# Authority combat already resolves hits before local visual bullets can enter
	# this Area. Keep this callback only for legacy scenes that run without it.
	if GameAuthority.is_local_authority() or GameAuthority.is_server_authority() \
			or GameAuthority.should_send_network_requests():
		return
	_handle_bullet_contact(body)

func _handle_bullet_contact(contact: Node3D) -> void:
	var bullet = _find_bullet_root(contact)
	if bullet == null:
		return

	if not bullet.has_method("get_bullet_owner"):
		return

	var attacker_team := str(bullet.call("get_bullet_owner"))
	if attacker_team == tool_owner:
		return

	var effect = "None"
	var damage = bullet.bullet_strength
	
	if bullet is BoomBullet:
		effect = "Explosion"
	if bullet is RubberBullet:
		effect = "None"
	elif bullet is NailBullet:
		effect = "None"
	elif bullet is ColorBullet:
		effect = str((bullet as ColorBullet).bullet_effect)
	else:
		return

	impact(effect, damage, attacker_team)

	if is_instance_valid(bullet):
		bullet.queue_free()


func _find_bullet_root(contact: Node) -> Node:
	var cursor: Node = contact
	var depth := 0

	while cursor != null and depth < 12:
		if (
			cursor is RubberBullet
			or cursor is NailBullet
			or cursor is ColorBullet
			or cursor is BoomBullet
		):
			return cursor

		cursor = cursor.get_parent()
		depth += 1

	return null


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

func _get_gameworld() -> Node:
	# 与 BoomBuggy / NormalDrone 相同：优先加入全局游戏世界。
	if GlobalVar.gameworld != null:
		return GlobalVar.gameworld

	if get_tree().current_scene != null:
		return get_tree().current_scene

	return get_tree().root
