extends CharacterBody3D
class_name BoomBuggy

## Food-War：BoomBuggy 小型遥控自爆车（v2：自定义爆炸逻辑 + 纯水平控制）
##
## 场景结构（节点名称必须一致）：
##
## BoomBuggy (CharacterBody3D，本脚本)
## ├── Mesh (Node3D / GLB 根节点)
## │   ├── WheelFrontLeft
## │   ├── WheelFrontRight
## │   ├── WheelRearLeft
## │   └── WheelRearRight
## ├── CollisionShape3D                 # 建议保留：小车物理碰撞
## ├── Hit3D (Area3D)                   # 攻击命中检测
## │   └── CollisionShape3D
## ├── ExplosionParticles (GPUParticles3D)
## └── CameraPivot (Node3D)
##     └── Camera3D
##
## Input Map：
## remote_left
## remote_right
## remote_forward
## remote_backward
## remote_primary_action     # 远程引爆
## remote_second_action      # 预留
## remote_interact           # 预留
##
## 设计：
## - remote_forward / remote_backward / remote_left / remote_right：四方向水平移动。
## - 鼠标左右：水平转动小车与摄像头视角。
## - 不读取鼠标上下；不提供上升、下降、跳跃或任何垂直操控。
## - remote_primary_action：信号和 jam_ratio 达标时，引爆自身。
## - 小车被 Hit3D 识别为攻击命中后，也会引爆。
##
## 重要：
## - 没有 _ready()；没有 @onready。
## - activate_tool() 被调用后，才查找节点、连接 Hit3D、初始化粒子、允许工作。
## - ExplosionParticles 的材质和形状由 initialize_explosion_particles() 初始化。
## - ExplosionParticles 负责本车爆炸视觉特效；范围伤害与命中判断由
##   create_explosion_gameplay(reason) 空函数负责，留给项目逻辑自行实现。


signal remote_control_started
signal remote_control_stopped
signal remote_signal_lost

signal primary_action_requested
signal second_action_requested
signal interact_requested

const NETWORK_SIMULATION_DELTA := 1.0 / 60.0
const SOFT_CORRECTION_DISTANCE := 0.04
const HARD_CORRECTION_DISTANCE := 1.5
const CORRECTION_BLEND := 0.25

signal explosion_triggered(position: Vector3, owner_team: String, reason: String)
signal detonation_blocked_by_jam


@export_group("Basic")
@export var set_hp: float = 100.0
@export var use_distance: float = 100.0
@export var tool_owner: String = ""

## 小车进入远控后，距离信号 × jam_ratio 低于此值会强制断控。
@export_range(0.0, 1.0, 0.01) var minimum_control_signal: float = 0.20

## 1.0 = 完全未被干扰；0.01 = SignalJam 的最强干扰。
@export_range(0.01, 1.0, 0.01) var jam_ratio: float = 1.0

## 1.0 = 未增强；100.0 = SignalAugment 中心的最大增强。
@export_range(1.0, 100.0, 1.0) var aug_ratio: float = 1.0


@export_group("Driving")
## 四方向水平移动的最大速度。
@export var drive_speed: float = 7.0
@export var acceleration: float = 22.0
@export var braking_acceleration: float = 30.0

## 轮子视觉滚动参数。
@export_range(0.01, 1.0, 0.01) var wheel_radius: float = 0.14
@export var wheel_spin_multiplier: float = 1.0

## 用于地面吸附和下落。
@export var gravity: float = 20.0
@export var floor_snap_distance: float = 0.15


@export_group("Remote Camera")
## 仅用于鼠标水平旋转。小车不使用上下视角和任何飞行/跳跃控制。
@export var yaw_sensitivity: float = 0.0032


@export_group("Explosion Gameplay")
## Hit3D 的 body_entered 被触发时，传入 impact() 的伤害值。
## 默认远大于 set_hp，因此被攻击会立即引爆。
@export var hit_area_damage: float = 9999.0

## true：任何有效攻击伤害都会立即自爆。
## false：只有 current_hp <= 0 时才爆炸。
@export var explode_on_any_damage: bool = true

## 小车爆炸后，保留粒子一小段时间才 queue_free。
@export_range(0.1, 5.0, 0.05) var explosion_cleanup_delay: float = 1.10


@export_group("Explosion Particles")
@export_range(1, 512, 1) var explosion_particle_amount: int = 100
@export_range(0.1, 3.0, 0.05) var explosion_particle_lifetime: float = 0.78
@export_range(0.1, 5.0, 0.05) var explosion_particle_speed_min: float = 5
@export_range(0.1, 8.0, 0.05) var explosion_particle_speed_max: float = 10
@export_range(0.01, 2.0, 0.01) var explosion_particle_radius: float = 0.05
@export_range(0.01, 3.0, 0.01) var explosion_particle_spread_radius: float = 0.20
@export var explosion_particle_color: Color = Color(1.0, 0.953, 0.204, 1.0)


@export_group("Debug")
@export var print_debug: bool = false
@export var hp_debug_label: bool = true

## 设置一个爆炸长按时间
var explosion_ensure_time:float = 3.0
var _current_ensure_time:float = 0
# 所有节点都在 activate_tool() 后才赋值。
var mesh_node: Node3D
var hit_area: Area3D
var main_collision_shape: CollisionShape3D
var explosion_particles: GPUParticles3D
var camera_pivot: Node3D
var buggy_camera: Camera3D

var wheel_front_left: Node3D
var wheel_front_right: Node3D
var wheel_rear_left: Node3D
var wheel_rear_right: Node3D

var current_hp: float = 0.0
var health_label: Label3D

var _activated: bool = false
var _scene_configured: bool = false
var _remote_control_active: bool = false
var _exploding: bool = false
var _capture_retry_frames: int = 0
var _server_authority_simulation := false
var _last_server_input_seq := 0
var _pending_network_inputs: Array[Dictionary] = []
var _pending_authority_snapshot: Dictionary = {}
var _electronics_disabled_remaining := 0.0
var _flame_remaining := 0.0
var _flame_damage_per_second := 0.0

## 遥控终端/玩家节点。可为空：为空时仅 jam_ratio 限制远控。
var _remote_receiver: Node3D

# ------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------

## 由 FarmTile.setting_tool()、部署脚本或外部生成逻辑调用。
## 调用后才真正开始查找场景节点、连接槽函数、初始化爆炸粒子。
func activate_tool() -> void:
	collision_layer = 128
	_activated = true

	if not is_node_ready():
		call_deferred("_activate_after_tree_ready")
		return

	_activate_after_tree_ready()


func _activate_after_tree_ready() -> void:
	if not _activated or _exploding:
		return

	_configure_scene_nodes()
	_connect_hit_area_signal()
	initialize_explosion_particles()

	# 地面车辆模式：没有 jump/ascend/descend 输入，只有重力与贴地。
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = floor_snap_distance

	current_hp = set_hp
	_update_health_label()
	velocity = Vector3.ZERO
	_remote_control_active = false
	_capture_retry_frames = 0

	if buggy_camera != null:
		buggy_camera.current = false

	_debug("Activated. Wheels found=%s." % _has_all_wheels())


func _configure_scene_nodes() -> void:
	if _scene_configured:
		return

	mesh_node = get_node_or_null("Mesh") as Node3D
	health_label = get_node_or_null("Label3D") as Label3D
	hit_area = get_node_or_null("Hit3D") as Area3D
	main_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	explosion_particles = get_node_or_null("ExplosionParticles") as GPUParticles3D
	camera_pivot = get_node_or_null("CameraPivot") as Node3D

	if camera_pivot != null:
		buggy_camera = camera_pivot.get_node_or_null("Camera3D") as Camera3D

	if mesh_node == null:
		push_warning(
			"BoomBuggy: 未找到 Mesh 节点。"
			+ "请确认 GLB 根节点或外层视觉节点名称为 Mesh。"
		)
	else:
		wheel_front_left = mesh_node.find_child(
			"WheelFrontLeft",
			true,
			false
		) as Node3D

		wheel_front_right = mesh_node.find_child(
			"WheelFrontRight",
			true,
			false
		) as Node3D

		wheel_rear_left = mesh_node.find_child(
			"WheelRearLeft",
			true,
			false
		) as Node3D

		wheel_rear_right = mesh_node.find_child(
			"WheelRearRight",
			true,
			false
		) as Node3D

		if not _has_all_wheels():
			push_warning(
				"BoomBuggy: 未找到一个或多个轮子节点。"
				+ "要求 Mesh 内有 WheelFrontLeft、WheelFrontRight、"
				+ "WheelRearLeft、WheelRearRight。"
			)

	if hit_area == null:
		push_warning(
			"BoomBuggy: 未找到 Hit3D (Area3D)。"
			+ "攻击命中无法触发自爆。"
		)

	if explosion_particles == null:
		push_warning(
			"BoomBuggy: 未找到 ExplosionParticles (GPUParticles3D)。"
			+ "爆炸时仍会执行 create_explosion_gameplay()，但不会有本车粒子视觉效果。"
		)

	if camera_pivot == null or buggy_camera == null:
		push_warning(
			"BoomBuggy: 未找到 CameraPivot/Camera3D。"
			+ "远程驾驶仍可执行，但无法切换到小车摄像头。"
		)

	_scene_configured = true


func _connect_hit_area_signal() -> void:
	if hit_area == null:
		return

	if not hit_area.body_entered.is_connected(_on_hit_3d_body_entered):
		hit_area.body_entered.connect(_on_hit_3d_body_entered)


# ------------------------------------------------------------------
# GPU explosion particle initialization
# ------------------------------------------------------------------

## 专门初始化 ExplosionParticles。
## 该函数可由外部在改参数后再次调用，以重新生成粒子配置。
func initialize_explosion_particles() -> void:
	if explosion_particles == null:
		return

	explosion_particles.one_shot = true
	explosion_particles.emitting = false
	explosion_particles.amount = explosion_particle_amount
	explosion_particles.lifetime = explosion_particle_lifetime
	explosion_particles.explosiveness = 1.0
	explosion_particles.randomness = 0.32
	explosion_particles.local_coords = false
	explosion_particles.visibility_aabb = AABB(
		Vector3(-2.6, -2.6, -2.6),
		Vector3(5.2, 5.2, 5.2)
	)

	var particle_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_material.emission_sphere_radius = explosion_particle_spread_radius
	particle_material.direction = Vector3.UP
	particle_material.spread = 180.0
	particle_material.gravity = Vector3(0.0, -10.0, 0.0)
	particle_material.initial_velocity_min = explosion_particle_speed_min
	particle_material.initial_velocity_max = explosion_particle_speed_max
	particle_material.damping_min = 1.2
	particle_material.damping_max = 2.4
	particle_material.scale_min = 0.65
	particle_material.scale_max = 1.35
	particle_material.color = explosion_particle_color

	var spark_mesh: SphereMesh = SphereMesh.new()
	spark_mesh.radius = explosion_particle_radius
	spark_mesh.height = explosion_particle_radius * 2.0
	spark_mesh.radial_segments = 8
	spark_mesh.rings = 4

	var spark_material: StandardMaterial3D = StandardMaterial3D.new()
	spark_material.albedo_color = explosion_particle_color
	spark_material.vertex_color_use_as_albedo = true
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mesh.material = spark_material

	explosion_particles.process_material = particle_material
	explosion_particles.draw_pass_1 = spark_mesh
	explosion_particles.draw_passes = 1


func _play_explosion_particles() -> void:
	if explosion_particles == null:
		return

	explosion_particles.global_position = global_position
	explosion_particles.restart()
	explosion_particles.emitting = true


# ------------------------------------------------------------------
# Remote control and signal
# ------------------------------------------------------------------

## 保持和 NormalDrone 类似的外部调用风格。
func run(receiver: Node3D = null) -> void:
	begin_remote_control(receiver)


## receiver 建议传入玩家或遥控终端 Node3D。
## 若 receiver 为空，则不检查距离，仅使用 jam_ratio 判断链路。
func begin_remote_control(receiver: Node3D = null) -> void:
	if not _activated:
		push_warning("BoomBuggy: 尚未 activate_tool()，不能进入遥控模式。")
		return

	if _exploding:
		return

	if receiver != null:
		_remote_receiver = receiver

	if not _has_remote_link():
		_debug("Remote control denied: insufficient signal.")
		remote_signal_lost.emit()
		return

	var was_remote_control_active: bool = _remote_control_active
	_remote_control_active = true

	_start_control_mode()

	if not was_remote_control_active:
		remote_control_started.emit()


func end_remote_control() -> void:
	stop()


func stop() -> void:
	if not _remote_control_active:
		return

	_remote_control_active = false
	velocity = Vector3.ZERO
	_capture_retry_frames = 0

	if buggy_camera != null:
		buggy_camera.current = false

	remote_control_stopped.emit()
	call_deferred("_restore_player_mouse_capture")


func is_remote_control_active() -> bool:
	return _remote_control_active


## 设置当前连接小车的遥控终端；用于距离信号强度和掉线判定。
func set_remote_receiver(receiver: Node3D) -> void:
	_remote_receiver = receiver


## 外部信号修正器可直接调用。1.0 表示无干扰。
func set_jam_ratio(value: float) -> void:
	jam_ratio = clampf(value, 0.01, 1.0)


func set_aug_ratio(value: float) -> void:
	aug_ratio = clampf(value, 1.0, 100.0)


func get_distance_signal_strength(receiver: Node3D) -> float:
	if receiver == null or not is_instance_valid(receiver):
		return 0.0

	if use_distance <= 0.001:
		return 1.0

	var distance_to_receiver: float = global_position.distance_to(
		receiver.global_position
	)

	return clampf(
		1.0 - distance_to_receiver / use_distance,
		0.0,
		1.0
	)


## 公开信号质量：距离信号乘以干扰和增强比率。
func get_signal_strength(receiver: Node3D) -> float:
	return get_distance_signal_strength(receiver) \
		* clampf(jam_ratio, 0.01, 1.0) \
		* clampf(aug_ratio, 1.0, 100.0)


func get_effective_signal_strength(receiver: Node3D) -> float:
	return get_signal_strength(receiver)


func get_current_effective_signal_strength() -> float:
	if _remote_receiver == null or not is_instance_valid(_remote_receiver):
		return clampf(jam_ratio, 0.01, 1.0) * clampf(aug_ratio, 1.0, 100.0)

	return get_signal_strength(_remote_receiver)


func _has_remote_link() -> bool:
	if _remote_receiver == null or not is_instance_valid(_remote_receiver):
		# 没指定终端时，仍使用两个修正量做基础链路判定。
		return get_current_effective_signal_strength() >= minimum_control_signal

	return get_signal_strength(_remote_receiver) >= minimum_control_signal


func _start_control_mode() -> void:
	if buggy_camera != null:
		buggy_camera.make_current()

	_capture_retry_frames = 3
	call_deferred("_ensure_remote_camera_and_mouse")


func _ensure_remote_camera_and_mouse() -> void:
	if not _remote_control_active or _exploding:
		return

	if buggy_camera != null:
		buggy_camera.make_current()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _restore_player_mouse_capture() -> void:
	if _remote_control_active:
		return

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _handle_remote_link_lost() -> void:
	if not _remote_control_active:
		return

	_remote_control_active = false
	velocity = Vector3.ZERO
	_capture_retry_frames = 0

	if buggy_camera != null:
		buggy_camera.current = false

	remote_control_stopped.emit()
	remote_signal_lost.emit()
	call_deferred("_restore_player_mouse_capture")


# ------------------------------------------------------------------
# Input / movement
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _activated:
		return
	_tick_electronic_status(delta)

	if _capture_retry_frames > 0:
		_capture_retry_frames -= 1
		_ensure_remote_camera_and_mouse()


func _input(event: InputEvent) -> void:
	if not _activated or _exploding:
		return
	if is_electronics_disabled():
		return

	if not _remote_control_active:
		return

	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			stop()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return

		var mouse_delta: Vector2 = event.screen_relative

		# 鼠标只控制水平朝向。CameraPivot 是小车的子节点，
		# 因此车体水平转动时，摄像头视角会同步水平旋转。
		# 不读取 mouse_delta.y：没有视角俯仰，也没有跳跃/垂直操控。
		rotate_y(-mouse_delta.x * yaw_sensitivity)

		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _server_authority_simulation:
		return
	if not _activated or _exploding:
		return
	if is_electronics_disabled():
		_apply_idle_physics(NETWORK_SIMULATION_DELTA)
		return
	if not _pending_authority_snapshot.is_empty():
		var authority_snapshot := _pending_authority_snapshot
		_pending_authority_snapshot = {}
		_apply_authoritative_snapshot(authority_snapshot)
		return

	if _remote_control_active and not _has_remote_link():
		_handle_remote_link_lost()
		return

	if not _remote_control_active:
		_apply_idle_physics(NETWORK_SIMULATION_DELTA)
		return

	_update_drive(NETWORK_SIMULATION_DELTA)
	_submit_remote_authority_input()
	_update_remote_actions(delta)


func _apply_idle_physics(delta: float) -> void:
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

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	move_and_slide()
	_update_wheels(delta)


func _update_drive(delta: float) -> void:
	# 与 NormalDrone 的水平移动一致：四个方向只形成水平平面向量。
	# 不存在 ascend / descend / jump，也不会主动给 velocity.y 正值。
	var move_input: Vector2 = Input.get_vector(
		"remote_left",
		"remote_right",
		"remote_forward",
		"remote_backward"
	)
	_simulate_drive(move_input, delta)


func _simulate_drive(move_input: Vector2, delta: float) -> void:

	var forward_direction: Vector3 = global_transform.basis.z
	var right_direction: Vector3 = -global_transform.basis.x

	forward_direction.y = 0.0
	right_direction.y = 0.0

	if forward_direction.length_squared() > 0.0001:
		forward_direction = forward_direction.normalized()
	else:
		forward_direction = Vector3.FORWARD

	if right_direction.length_squared() > 0.0001:
		right_direction = right_direction.normalized()
	else:
		right_direction = Vector3.RIGHT

	var horizontal_direction: Vector3 = (
		right_direction * move_input.x
		+ forward_direction * -move_input.y
	)

	if horizontal_direction.length_squared() > 1.0:
		horizontal_direction = horizontal_direction.normalized()

	var target_planar_velocity: Vector3 = horizontal_direction * drive_speed
	var current_planar_velocity: Vector3 = Vector3(
		velocity.x,
		0.0,
		velocity.z
	)

	var has_horizontal_input: bool = (
		horizontal_direction.length_squared() > 0.0001
	)
	var response_speed: float = (
		acceleration
		if has_horizontal_input
		else braking_acceleration
	)

	current_planar_velocity = current_planar_velocity.move_toward(
		target_planar_velocity,
		response_speed * delta
	)

	velocity.x = current_planar_velocity.x
	velocity.z = current_planar_velocity.z

	# 仅保持贴地/受重力，不提供任何可让小车离地的控制输入。
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	move_and_slide()
	_update_wheels(delta)


func simulate_authoritative_remote_input(input_frame: Dictionary, _delta: float) -> void:
	if not _activated or _exploding:
		return
	if is_electronics_disabled():
		_apply_idle_physics(NETWORK_SIMULATION_DELTA)
		return
	rotation.y = float(input_frame.get("yaw", rotation.y))
	var move_value: Variant = input_frame.get("move", Vector2.ZERO)
	var move := move_value as Vector2 if move_value is Vector2 else Vector2.ZERO
	_simulate_drive(move, NETWORK_SIMULATION_DELTA)


func set_server_authority_simulation(enabled: bool) -> void:
	_server_authority_simulation = enabled
	if enabled:
		_activated = true
		_configure_scene_nodes()
		motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
		floor_snap_length = floor_snap_distance
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
		_simulate_drive(move, NETWORK_SIMULATION_DELTA)
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


func _update_wheels(delta: float) -> void:
	if not _has_all_wheels():
		return

	var planar_velocity: Vector3 = Vector3(
		velocity.x,
		0.0,
		velocity.z
	)
	var planar_speed: float = planar_velocity.length()

	if planar_speed <= 0.001:
		return

	# 前后移动以真实前向速度决定正反转。
	# 纯左右平移时也让轮子滚动，避免“车在动而轮子静止”。
	var forward_direction: Vector3 = -global_transform.basis.z
	forward_direction.y = 0.0

	var spin_sign: float = 1.0
	if forward_direction.length_squared() > 0.0001:
		forward_direction = forward_direction.normalized()
		var signed_forward_speed: float = planar_velocity.dot(forward_direction)
		if absf(signed_forward_speed) > 0.05:
			spin_sign = signf(signed_forward_speed)

	var spin_delta: float = (
		planar_speed
		/ maxf(wheel_radius, 0.01)
		* spin_sign
		* wheel_spin_multiplier
		* delta
	)

	# GLB 轮子规范：轮轴沿局部 X，因此四个轮子均绕本地 X 轴旋转。
	wheel_front_left.rotate_x(-spin_delta)
	wheel_front_right.rotate_x(-spin_delta)
	wheel_rear_left.rotate_x(-spin_delta)
	wheel_rear_right.rotate_x(-spin_delta)


func _update_remote_actions(delta:float) -> void:
	if is_electronics_disabled():
		_current_ensure_time = 0.0
		return
	if Input.is_action_pressed("remote_primary_action"):
		_current_ensure_time += delta
		if _current_ensure_time >= explosion_ensure_time:
			_current_ensure_time = 0
			_on_remote_primary_action()
	else:
		# 没有按左键，那么停止爆炸确认时间的累计
		_current_ensure_time = 0


# ------------------------------------------------------------------
# Actions / explosion
# ------------------------------------------------------------------

func _on_remote_primary_action() -> void:
	primary_action_requested.emit()
	if _submit_remote_authority_action("primary"):
		return

	if get_signal_strength(_remote_receiver) < minimum_control_signal:
		detonation_blocked_by_jam.emit()
		_debug("Remote detonation blocked by effective signal.")
		return
	print("EXPLISION!!!")
	trigger_explosion("remote_primary_action")


func _on_remote_second_action() -> void:
	second_action_requested.emit()
	if _submit_remote_authority_action("second"):
		return
	# 预留：侦察扫描、闪光、标记目标等。
	pass


func _on_remote_interact() -> void:
	interact_requested.emit()
	if _submit_remote_authority_action("interact"):
		return
	# 预留：回收、修理、切换遥控终端等。
	pass


func _submit_remote_authority_input() -> void:
	# Multiplayer/local remote input is submitted once by GamePlayer._submit_remote_control_frame().
	# Keeping a second sender here makes the same device state arrive twice per physics tick.
	return
	var network_device_id := ""
	if has_meta("network_device_id"):
		network_device_id = str(get_meta("network_device_id"))
	elif is_inside_tree():
		network_device_id = str(get_path())
	if network_device_id.is_empty():
		return
	var frame := {
		"device_id": network_device_id,
		"device_path": network_device_id,
		"device_type": "boom_buggy",
		"client_time_msec": Time.get_ticks_msec(),
		"move": Input.get_vector("remote_left", "remote_right", "remote_forward", "remote_backward"),
		"vertical": 0.0,
		"primary": Input.is_action_pressed("remote_primary_action"),
		"second": Input.is_action_pressed("remote_second_action"),
		"interact": Input.is_action_pressed("remote_interact"),
		"position": global_position,
		"velocity": velocity,
		"yaw": rotation.y,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_remote_control_input(frame)
	elif GameAuthority.is_local_authority():
		GameAuthority.local_remote_control_input(GameAuthority.LOCAL_PLAYER_ID, frame)


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
		"device_type": "boom_buggy",
		"action": action_name,
		"position": global_position,
		"velocity": velocity,
		"yaw": rotation.y,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_remote_action(action)
		return true
	if GameAuthority.is_local_authority():
		GameAuthority.local_remote_action(GameAuthority.LOCAL_PLAYER_ID, action)
	return false


## 外部也可以直接调用：
## trigger_explosion("some_reason")
func trigger_explosion(reason: String = "manual") -> bool:
	if not _activated or _exploding:
		return false

	_exploding = true
	velocity = Vector3.ZERO

	var had_remote_control: bool = _remote_control_active
	_remote_control_active = false
	_capture_retry_frames = 0

	if buggy_camera != null:
		buggy_camera.current = false

	if had_remote_control:
		remote_control_stopped.emit()

	# 禁用物理碰撞和攻击检测，避免爆炸后多次重复触发。
	collision_layer = 0
	collision_mask = 0

	if main_collision_shape != null:
		main_collision_shape.set_deferred("disabled", true)

	if hit_area != null:
		hit_area.set_deferred("monitoring", false)
		hit_area.set_deferred("monitorable", false)

	# 只隐藏车体网格，ExplosionParticles 仍然保留并正常播放。
	if mesh_node != null:
		mesh_node.visible = false

	# 粒子视觉效果由本脚本负责并立即播放。
	_play_explosion_particles()

	# Local and multiplayer combat damage is owned by GameAuthority. Keep this
	# legacy path only when authority is not running, so the node can still play
	# its local particle and cleanup sequence without double-damaging targets.
	if not GameAuthority.is_local_authority() and not GameAuthority.is_server_authority():
		create_explosion_gameplay(reason)

	explosion_triggered.emit(global_position, tool_owner, reason)

	# 爆炸后遥控终端也必须退出摄像头状态。
	remote_signal_lost.emit()
	call_deferred("_cleanup_after_explosion")
	return true


## 爆炸游戏逻辑挂钩函数。
##
## 本函数刻意保持为空。请在这里实现你项目自己的：
## - 爆炸半径检测
## - 命中对象筛选
## - 队伍/友伤判断
## - 对 CharacterBody3D、Tool、建筑物的 impact() 调用
## - 击退、状态效果、音效或其它服务端逻辑
##
## 注意：ExplosionParticles 已在 trigger_explosion() 中自动播放；
## 这里不需要再处理本车 GPU 粒子。

func _cleanup_after_explosion() -> void:
	var tree_timer: SceneTreeTimer = get_tree().create_timer(
		explosion_cleanup_delay
	)
	await tree_timer.timeout

	if is_instance_valid(self):
		queue_free()

@export_group("Explosion Param")
@export var explosion_radius: float = 16
@export var explosion_strength:float = 100
func _damage_nearby_plots() -> void:
	var manager := get_node_or_null("/root/Farmlandmanager")
	if manager == null:
		return
	for plot in manager.get_plots_in_radius(self.global_position, explosion_radius):
		if is_instance_valid(plot):
			plot.impact("Explosion", explosion_strength, tool_owner)
	
			
# ============================================================
# BoomBuggy ShapeCast3D 爆炸伤害
#
# 场景节点要求：
# BoomBuggy (CharacterBody3D)
# ├── CollisionShape3D
# ├── Hit3D
# └── ExplosionShapeCast (ShapeCast3D)
#
# ExplosionShapeCast：
# - Shape 必须设置为 SphereShape3D
# - collision_mask 必须包含 Player、Tool、Building / Wall
# - collide_with_bodies = true
# - collide_with_areas = true
# - max_results 建议 >= 64
# ============================================================

@onready var explosion_shape_cast: ShapeCast3D = $ShapeCast3D

func create_explosion_gameplay(reason: String) -> void:
	if explosion_shape_cast == null:
		push_error("[BoomBuggy] Missing ExplosionShapeCast.")
		return

	var sphere: SphereShape3D = (
		explosion_shape_cast.shape as SphereShape3D
	)
	if sphere == null:
		push_error(
			"[BoomBuggy] ExplosionShapeCast must use SphereShape3D."
		)
		return
	## 先处理农作物爆炸
	_damage_nearby_plots()
	
	## 然后处理Tools、Player、AI爆炸	
	# 爆炸中心略微抬高，避免从地面内部开始射线检测。
	var explosion_origin: Vector3 = global_position + Vector3.UP * 0.45

	# 同步 Inspector 中可调的爆炸半径。
	sphere.radius = explosion_radius

	# target_position 为 ZERO 时，ShapeCast 相当于当前位置的球形范围检测。
	explosion_shape_cast.global_position = explosion_origin
	explosion_shape_cast.target_position = Vector3.ZERO
	explosion_shape_cast.enabled = true
	explosion_shape_cast.collide_with_bodies = true
	explosion_shape_cast.collide_with_areas = true

	# 排除 BoomBuggy 自己、自己的 Hit3D、以及自身所在 FarmTile。
	explosion_shape_cast.clear_exceptions()
	explosion_shape_cast.add_exception(self)

	var own_hit_3d: CollisionObject3D = (
		get_node_or_null("Hit3D") as CollisionObject3D
	)
	if own_hit_3d != null:
		explosion_shape_cast.add_exception(own_hit_3d)

	var parent_collision: CollisionObject3D = (
		get_parent() as CollisionObject3D
	)
	if parent_collision != null:
		explosion_shape_cast.add_exception(parent_collision)

	# 立即更新，不等待下一个物理帧。
	explosion_shape_cast.force_shapecast_update()

	# 防止同一个 Player / Tool 因多个碰撞体、Hit3D 被重复结算。
	var damaged_targets: Dictionary = {}
		
	for index in range(explosion_shape_cast.get_collision_count()):
		var collider: Object = explosion_shape_cast.get_collider(index)
	
		var target: Node3D = _resolve_explosion_target(collider)
		print(target)
		if target == null or target == self:
			continue

		var target_id: int = target.get_instance_id()

		if damaged_targets.has(target_id):
			continue

		damaged_targets[target_id] = true

		## 只伤害 Player 或 Tool。
		#if not _is_explosion_damage_target(target):
			#continue

		# 不伤害同队 Player / Tool。
		if _is_same_team_as_boom_buggy(target):
			continue

		var final_strength: float = explosion_strength
		
		# 只对 Player 单独发射射线检查遮挡。
		if _is_player_target(target):
			var player_multiplier: float = (
				_get_player_explosion_damage_multiplier(
					explosion_origin,
					target
				)
			)

			# Building / 墙 / 地形等完全遮挡。
			if player_multiplier <= 0.0:
				continue

			# Tool 遮挡时，伤害减半。
			final_strength *= player_multiplier

		if final_strength <= 0.0:
			continue

		# 由 Player / Tool 自己处理生命、耐久、摧毁、掉落等逻辑。
		target.call(
			"impact",
			"Explosion",
			final_strength,
			tool_owner
		)

		print(
			"[BoomBuggy] Explosion hit: %s | strength=%.1f | reason=%s"
			% [
				target.get_path(),
				final_strength,
				reason,
			]
		)
# ============================================================
# 目标识别
# ============================================================

func _resolve_explosion_target(collider: Object) -> Node3D:
	var node: Node = collider as Node
	var depth: int = 0

	# 碰撞体可能是：
	# Player 的 CollisionShape3D
	# Tool 的子节点
	# Hit3D Area3D
	# 需要向上找到真正拥有 team / tool_owner / impact 的根实体。
	while node != null and depth < 4:
		if node is Node3D:
			var candidate: Node3D = node as Node3D
			if (
				candidate.has_method("impact")
			):
				return candidate

		node = node.get_parent()
		depth += 1

	return null

func _is_player_target(target: Node3D) -> bool:
	# GamePlayer 使用 team。
	return (target is GamePlayer or target is AIPlayer)


func _is_tool_target(target: Node3D) -> bool:
	# Tool 使用 tool_owner。
	# Player 若同时存在 tool_owner，也仍然优先视作 Player。
	return (
		_has_property(target, "tool_owner")
		and not _is_player_target(target)
	)


func _is_same_team_as_boom_buggy(target: Node3D) -> bool:
	if tool_owner.is_empty():
		return false

	var target_team: String = _get_target_team_name(target)

	return (
		not target_team.is_empty()
		and target_team == tool_owner
	)


func _get_target_team_name(target: Node3D) -> String:
	if _is_player_target(target):
		return _get_string_property(target, "team")

	if _is_tool_target(target):
		return _get_string_property(target, "tool_owner")

	return ""


# ============================================================
# Player 遮挡射线
#
# 返回：
# 1.0 = 无遮挡，完整爆炸伤害
# 0.5 = Tool 挡住，伤害减半
# 0.0 = Building / 墙 / 地形 / 其他实体遮挡，不受伤
# ============================================================

func _get_player_explosion_damage_multiplier(
	explosion_origin: Vector3,
	player: Node3D
) -> float:
	var player_point: Vector3 = (
		player.global_position + Vector3.UP * 0.75
	)

	var exclude_rids: Array[RID] = [get_rid()]

	var own_hit_3d: CollisionObject3D = (
		get_node_or_null("Hit3D") as CollisionObject3D
	)
	if own_hit_3d != null:
		exclude_rids.append(own_hit_3d.get_rid())

	var parent_collision: CollisionObject3D = (
		get_parent() as CollisionObject3D
	)
	if parent_collision != null:
		exclude_rids.append(parent_collision.get_rid())

	var ray_query: PhysicsRayQueryParameters3D = (
		PhysicsRayQueryParameters3D.create(
			explosion_origin,
			player_point,
			explosion_shape_cast.collision_mask + 4096,   # 4096是Buildings
			exclude_rids
		)
	)

	ray_query.collide_with_bodies = true
	ray_query.collide_with_areas = true
	ray_query.hit_from_inside = true

	var space_state: PhysicsDirectSpaceState3D = (
		get_world_3d().direct_space_state
	)

	var hit: Dictionary = space_state.intersect_ray(ray_query)

	# 射线未命中任何东西，代表无遮挡。
	if hit.is_empty():
		return 1.0

	var first_collider: Object = hit.get("collider")

	var first_target: Node3D = _resolve_explosion_target(
		first_collider
	)

	# 第一命中就是目标 Player 自己：无遮挡。
	if first_target == player:
		return 1.0

	# 第一命中是 Tool：Tool 为 Player 提供半伤害掩护。
	if first_target != null and _is_tool_target(first_target):
		return 0.5

	# Building、墙、FarmTile、地形、其他 Player 或未知碰撞体：
	# 都视为完全遮挡。
	return 0.0


# ============================================================
# Property 工具
# ============================================================

func _has_property(object: Object, property_name: String) -> bool:
	for property_info: Dictionary in object.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true

	return false


func _get_string_property(
	object: Object,
	property_name: String
) -> String:
	if not _has_property(object, property_name):
		return ""

	var value: Variant = object.get(property_name)

	if value is String:
		return value as String

	return str(value)
	
		
# ------------------------------------------------------------------
# Damage / Hit3D
# ------------------------------------------------------------------

## 外部子弹、炮塔、爆炸物可直接调用此函数。
##
## effect：伤害类型的文字标识，例如 "bullet"、"fire"、"boom"。
## strength：伤害数值。
## attacker_team：攻击者队伍；与 tool_owner 相同则忽略友伤。
func impact(
	effect: String,
	strength: float,
	attacker_team: String = ""
) -> bool:
	if not _activated or _exploding:
		return false

	if not attacker_team.is_empty() and attacker_team == tool_owner:
		return false

	var normalized_effect := effect.to_lower()
	if normalized_effect == "repair_laser":
		_electronics_disabled_remaining = maxf(_electronics_disabled_remaining, CombatBalance.get_electronic_disable_duration("boom_buggy", "repair_laser"))
		velocity = Vector3.ZERO
		return true
	var actual_damage: float = maxf(0.0, strength)
	if actual_damage <= 0.0:
		return false

	current_hp = maxf(0.0, current_hp - actual_damage)
	_update_health_label()
	_debug(
		"Impact effect=%s damage=%.2f hp=%.2f."
		% [effect, actual_damage, current_hp]
	)

	if explode_on_any_damage or current_hp <= 0.0:
		trigger_explosion("impact_" + effect)
	elif normalized_effect == "flame" or normalized_effect == "fire":
		_flame_remaining = maxf(_flame_remaining, CombatBalance.get_float("remote_electronics", "flame_duration"))
		_flame_damage_per_second = maxf(_flame_damage_per_second, actual_damage * CombatBalance.get_float("remote_electronics", "flame_damage_multiplier"))
	elif normalized_effect == "lightening" or normalized_effect == "lightning":
		_electronics_disabled_remaining = maxf(_electronics_disabled_remaining, CombatBalance.get_electronic_disable_duration("boom_buggy", "lightning"))
		velocity = Vector3.ZERO

	return true


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
		if current_hp <= 0.0:
			trigger_explosion("flame")
	if _flame_remaining <= 0.0:
		_flame_damage_per_second = 0.0


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	_activated = true
	if health_label == null:
		health_label = get_node_or_null("Label3D") as Label3D
	_update_health_label()


func _update_health_label() -> void:
	if not is_instance_valid(health_label):
		return
	health_label.visible = hp_debug_label and _activated
	health_label.text = "%d" % int(ceil(current_hp))


## Hit3D.body_entered 的槽函数。
##
## 注意：请让 Hit3D 的 collision_mask 只监听“攻击体/子弹”层，
## 不要监听普通地面、墙、玩家本体，否则这些普通碰撞也会使小车爆炸。
func _on_hit_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests():
		return
	if not _activated or _exploding:
		return

	if body == self:
		return

	# 由 Hit3D 的掩码保证这里只有攻击体。
	# 若你的子弹系统有队伍信息，建议子弹在命中时直接调用：
	# impact("bullet", damage, attacker_team)
	if not (body is NailBullet or body is ColorBullet or body is BoomBullet or body is RubberBullet or body is DetectLaserBullet):
		return
	var projectile_owner = str(body.get_bullet_owner())
	if projectile_owner == tool_owner:
		return

	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet or body is DetectLaserBullet:
		effect = body.bullet_effect
	impact(effect, body.bullet_strength	, projectile_owner)


# ------------------------------------------------------------------
# Utilities
# ------------------------------------------------------------------

func _has_all_wheels() -> bool:
	return (
		wheel_front_left != null
		and wheel_front_right != null
		and wheel_rear_left != null
		and wheel_rear_right != null
	)


func _debug(message: String) -> void:
	if print_debug:
		print("[BoomBuggy] ", message)


## 这是你当前手持工具调用的放置函数。
func emit():
	var user_node = get_node_or_null("../../../")

	if not user_node:
		queue_free()
		return

	var raycast = user_node.find_child(
		"LookAtTarget",
		true
	)

	if tool_owner.is_empty():
		return

	if not raycast or not raycast.is_colliding():
		return

	var ground_position: Vector3 = raycast.get_collision_point()

	var buggy := load(
		"res://character/weapons/BoomBuggy.tscn"
	).instantiate() as BoomBuggy

	GlobalVar.gameworld.add_child(buggy)

	buggy.global_position = ground_position + Vector3(0.0, 0.3, 0.0)

	buggy.tool_owner = tool_owner
	buggy.activate_tool()
	return {
		"remote_node": buggy
	}
