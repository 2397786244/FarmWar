extends CharacterBody3D
class_name NormalDrone

## 场景结构：
##
## NormalDrone (CharacterBody3D，本脚本)
## ├── DroneVisual
## ├── CollisionShape3D
## ├── Hit3D
## ├── CameraPivot
## │   └── Camera3D
## ├── BulletMountSlot
## └── CargoMountPos
##
## Input Map：
## remote_left
## remote_right
## remote_forward
## remote_backward
## remote_ascend
## remote_descend
## remote_primary_action
## remote_second_action
## remote_interact
##
## Esc 直接用 KEY_ESCAPE，不需要额外创建 Input Map。


signal remote_control_started
signal remote_control_stopped
signal interact_requested
signal remote_signal_lost   # 被炸毁、完全被干扰的时候发出

signal primary_action_requested
signal second_action_requested
signal bomb_dropped(bomb: Node3D)

const NETWORK_SIMULATION_DELTA := 1.0 / 60.0
const SOFT_CORRECTION_DISTANCE := 0.04
const HARD_CORRECTION_DISTANCE := 1.5
const CORRECTION_BLEND := 0.25

var forward_left: Node3D
var forward_right: Node3D
var backward_left: Node3D
var backward_right: Node3D

@export_group("Basic")
@export var SET_HP:float = 200
@export var use_distance:float = 100

@export_group("Debug")
@export var hp_debug_label: bool = true

@export_group("State")

## 无人机是否通电，控制旋翼转动。
@export var power_on: bool = false

@export var tool_owner: String = ""


@export_group("Rotor")

## 旋翼视觉转速，单位是弧度/秒。
@export var ROTATION_SPEED: float = 500.0


@export_group("Flight")

@export var move_speed: float = 8.0
@export var ascend_speed: float = 6.0

## 有输入时的速度响应。
@export var acceleration: float = 24.0

## 松开按键后的减速响应。
@export var braking_acceleration: float = 32.0

## 鼠标左右控制无人机偏航的灵敏度。
@export var yaw_sensitivity: float = 0.0032

## 鼠标上下只控制 CameraPivot，不控制无人机机体俯仰。
@export var enable_camera_pitch: bool = true
@export var camera_pitch_sensitivity: float = 0.0020

@export_range(5.0, 85.0, 1.0, "degrees")
var max_camera_pitch_degrees: float = 70.0


@export_group("Bomb")

## 指向以 RigidBody3D 为根节点的炸弹场景。
@export var bomb_scene: PackedScene

@export var bomb_cooldown: float = 2.0
@export var startup_bomb_lock: float = 3.0
@export var bomb_initial_down_speed: float = 10.0
@export var bomb_damage: float = 100.0
@export var bomb_explosion_radius: float = 4.0
@export var bomb_ignore_drone_time: float = 0.1
const REMOTE_PRECISION_ACTION_MIN_EFFECTIVE_SIGNAL := 0.20

@onready var drone_visual: Node3D = $DroneVisual
@onready var camera_pivot: Node3D = $CameraPivot
@onready var drone_camera: Camera3D = $CameraPivot/Camera3D

@onready var bullet_mount_slot: Node3D = get_node_or_null("BulletMountSlot") as Node3D
@onready var cargo_mount_pos: Node3D = get_node_or_null("CargoMountPos") as Node3D
@onready var hit_area: Area3D = $Hit3D
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D


var _camera_pitch: float = 0.0
var _bomb_cooldown_left: float = 0.0

## 无人机是否已经被放置到世界中。
var _placed: bool = false

## 注意：
## power_on 只表示无人机是否通电。
## _remote_control_active 才表示玩家是否正在实际控制它。
var _remote_control_active: bool = false

## 避免 place_ready_setting() 被重复初始化。
var _scene_configured: bool = false

## 进入遥控后的几帧内持续确认鼠标捕获。
## 防止玩家/UI 脚本在同一帧把鼠标改回 Visible。
var _capture_retry_frames: int = 0
var current_hp:float = SET_HP
## 1.0 表示无干扰；由本地权威或多人服务器同步更新。
var jam_ratio:float = 1.0
## 1.0 表示没有增强，最大 100.0。
var aug_ratio:float = 1.0
var _remote_receiver: Node3D
var _network_visual_mode := false
var _server_authority_simulation := false
var _last_server_input_seq := 0
var _pending_network_inputs: Array[Dictionary] = []
var _pending_authority_snapshot: Dictionary = {}
var _electronics_disabled_remaining := 0.0
var _flame_remaining := 0.0
var _flame_damage_per_second := 0.0

func _ready() -> void:
	current_hp = SET_HP
	_configure_health_label()
	# 场景中直接摆放的无人机，也可以工作。
	if _placed:
		place_ready_setting()


func place_ready_setting() -> void:
	# 无人机采用自由飞行模式。
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	floor_snap_length = 0.0

	if not _scene_configured:
		# false 表示允许搜索 GLB 导入场景内部的节点。
		forward_left = drone_visual.find_child(
			"FrontLeft_RotorPivot",
			true,
			false
		) as Node3D

		forward_right = drone_visual.find_child(
			"FrontRight_RotorPivot",
			true,
			false
		) as Node3D

		backward_left = drone_visual.find_child(
			"RearLeft_RotorPivot",
			true,
			false
		) as Node3D

		backward_right = drone_visual.find_child(
			"RearRight_RotorPivot",
			true,
			false
		) as Node3D

		if forward_left == null \
		or forward_right == null \
		or backward_left == null \
		or backward_right == null:
			push_warning(
				"NormalDrone: 未找到一个或多个 RotorPivot。"
				+ "请检查 DroneVisual 内部四个旋翼节点名称。"
			)

		_camera_pitch = camera_pivot.rotation.x
		_scene_configured = true

	# 刚放置时不应该抢占玩家相机。
	if not is_instance_valid(drone_camera):
		drone_camera = camera_pivot.get_node_or_null("Camera3D") as Camera3D
	if is_instance_valid(drone_camera):
		drone_camera.current = false


func _process(delta: float) -> void:
	_tick_electronic_status(delta)
	if _network_visual_mode and power_on:
		_update_rotors(delta)
	# 切换到无人机后的几帧持续确认：
	# 1. 无人机相机仍是当前相机
	# 2. 鼠标仍是 CAPTURED
	if _capture_retry_frames > 0:
		_capture_retry_frames -= 1
		_ensure_remote_camera_and_mouse()


func _input(event: InputEvent) -> void:
	# 必须用 _input，而不是 _unhandled_input。
	# 因为玩家相机或 UI 可能先处理鼠标事件，
	# 导致 _unhandled_input 根本收不到鼠标移动。
	if not _placed:
		return

	if not _remote_control_active:
		return

	# Esc：退出无人机遥控。
	#if event is InputEventKey:
		#if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			#stop()
			#get_viewport().set_input_as_handled()
			#return

	# 鼠标左右转无人机，鼠标上下转镜头。
	if event is InputEventMouseMotion:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return

		var mouse_delta = event.screen_relative

		# 左右鼠标：无人机机体偏航。
		rotate_y(-mouse_delta.x * yaw_sensitivity)

		# 上下鼠标：只旋转 CameraPivot。
		if enable_camera_pitch:
			var max_pitch := deg_to_rad(max_camera_pitch_degrees)

			_camera_pitch = clampf(
				_camera_pitch - mouse_delta.y * camera_pitch_sensitivity,
				-max_pitch,
				max_pitch
			)

			camera_pivot.rotation.x = _camera_pitch

		# 防止玩家的 _unhandled_input 再转自己的相机。
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _server_authority_simulation:
		return
	if not _placed:
		return
	# 启动投弹锁从放置时开始计时，电子禁用和是否进入遥控都不会暂停它。
	if _bomb_cooldown_left > 0.0:
		_bomb_cooldown_left = maxf(0.0, _bomb_cooldown_left - delta)
	if is_electronics_disabled():
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * delta)
		move_and_slide()
		return
	if not _pending_authority_snapshot.is_empty():
		var authority_snapshot := _pending_authority_snapshot
		_pending_authority_snapshot = {}
		_apply_authoritative_snapshot(authority_snapshot)
		return

	# 只要通电，旋翼就持续旋转。
	if power_on:
		_update_rotors(delta)

	# 没有被遥控时，无人机不读取 remote 输入。
	if not _remote_control_active:
		velocity = velocity.move_toward(
			Vector3.ZERO,
			braking_acceleration * delta
		)

		move_and_slide()
		return

	_update_flight(NETWORK_SIMULATION_DELTA)
	_submit_remote_authority_input()

	if _allows_secondary_remote_actions() and Input.is_action_just_pressed("remote_second_action"):
		_on_remote_second_action()

	if _allows_secondary_remote_actions() and Input.is_action_just_pressed("remote_interact"):
		_on_remote_interact()


func _update_flight(delta: float) -> void:
	_simulate_flight(
		Input.get_vector(
		"remote_left",
		"remote_right",
		"remote_forward",
		"remote_backward"
		),
		Input.get_axis("remote_descend", "remote_ascend"),
		delta
	)


func simulate_authoritative_remote_input(input_frame: Dictionary, delta: float) -> void:
	if not _placed:
		return
	if is_electronics_disabled():
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * delta)
		move_and_slide()
		_update_health_label()
		return
	power_on = true
	rotation.y = float(input_frame.get("yaw", rotation.y))
	var move = input_frame.get("move", Vector2.ZERO)
	if not move is Vector2:
		move = Vector2.ZERO
	var vertical := clampf(float(input_frame.get("vertical", 0.0)), -1.0, 1.0)
	_simulate_flight(move as Vector2, vertical, NETWORK_SIMULATION_DELTA)
	_update_health_label()


func _simulate_flight(move_input: Vector2, vertical_input: float, delta: float) -> void:

	# Godot 本地 -Z 为前方。
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x

	# 保持 W/A/S/D 永远在水平面飞行，
	# 不受相机上下俯仰影响。
	forward.y = 0.0
	right.y = 0.0

	forward = forward.normalized()
	right = right.normalized()

	var horizontal_direction := (
		right * move_input.x
		+ forward * -move_input.y
	)

	if horizontal_direction.length_squared() > 1.0:
		horizontal_direction = horizontal_direction.normalized()

	var target_velocity := horizontal_direction * move_speed
	target_velocity.y = vertical_input * ascend_speed

	var has_input := (
		horizontal_direction.length_squared() > 0.0001
		or absf(vertical_input) > 0.0001
	)

	var response := (
		acceleration
		if has_input
		else braking_acceleration
	)

	velocity = velocity.move_toward(
		target_velocity,
		response * delta
	)

	move_and_slide()


func set_server_authority_simulation(enabled: bool) -> void:
	_server_authority_simulation = enabled
	if enabled:
		_placed = true
		power_on = true
		place_ready_setting()
	set_physics_process(not enabled)


func enable_network_visuals() -> void:
	_network_visual_mode = true
	_placed = true
	power_on = true
	place_ready_setting()
	set_process(true)
	set_physics_process(false)


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	_placed = true
	_update_health_label()


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
		bomb_cooldown = authoritative_cooldown
	_bomb_cooldown_left = maxf(
		_bomb_cooldown_left,
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
		_simulate_flight(move, clampf(float(frame.get("vertical", 0.0)), -1.0, 1.0), NETWORK_SIMULATION_DELTA)
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


func _configure_health_label() -> void:
	if health_label == null:
		return
	health_label.visible = hp_debug_label and _placed
	_update_health_label()


func _update_health_label() -> void:
	if is_instance_valid(health_label):
		health_label.visible = hp_debug_label and _placed
		health_label.text = "%d" % int(ceil(current_hp))


func _update_rotors(delta: float) -> void:
	var spin := ROTATION_SPEED * delta

	# 对角线旋翼反向旋转。
	if forward_left != null:
		forward_left.rotate_y(spin)

	if backward_right != null:
		backward_right.rotate_y(spin)

	if forward_right != null:
		forward_right.rotate_y(-spin)

	if backward_left != null:
		backward_left.rotate_y(-spin)


## 保持和你旧的外部调用兼容。
func run() -> void:
	begin_remote_control()


## 外部遥控台、玩家工具、机器鼠系统都可以使用这个接口。
func begin_remote_control() -> void:
	if not _placed:
		push_warning("NormalDrone: 无人机尚未放置，不能进入遥控模式。")
		return

	var was_remote_control_active := _remote_control_active

	power_on = true
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
	var dist = global_position.distance_to(receiver.global_position)
	return clampf((-dist + use_distance) / maxf(use_distance, 0.01), 0.1, 1.0)


## 公开信号质量：距离信号乘以干扰和增强比率。
func get_signal_strength(receiver: Node3D) -> float:
	return get_distance_signal_strength(receiver) \
		* clampf(jam_ratio, 0.01, 1.0) \
		* clampf(aug_ratio, 1.0, 100.0)


func get_effective_signal_strength(receiver: Node3D) -> float:
	return get_signal_strength(receiver)


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
		_apply_damage(_flame_damage_per_second * burn_tick)
	if _flame_remaining <= 0.0:
		_flame_damage_per_second = 0.0
	
func stop() -> void:
	if not _remote_control_active:
		return

	_remote_control_active = false
	power_on = true
	velocity = Vector3.ZERO

	_capture_retry_frames = 0

	# 无人机退出当前相机。
	drone_camera.current = false

	remote_control_stopped.emit()

	# 你的玩家脚本应监听 remote_control_stopped，
	# 然后把玩家相机设回 current。
	#
	# 这里继续捕获鼠标，因为正常玩家状态通常也使用 CAPTURED。
	call_deferred("_restore_player_mouse_capture")


func _start_control_mode() -> void:
	# 强制无人机相机成为当前相机。
	drone_camera.make_current()

	# 进入后的三帧持续确认相机与鼠标状态。
	_capture_retry_frames = 3

	call_deferred("_ensure_remote_camera_and_mouse")


func _ensure_remote_camera_and_mouse() -> void:
	if not _remote_control_active:
		return

	drone_camera.make_current()

	# 注意是单个等号 = 。
	# 不是 Input.mouse_mode == Input.MOUSE_MODE_CAPTURED。
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _restore_player_mouse_capture() -> void:
	if _remote_control_active:
		return

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_remote_primary_action() -> void:
	if is_electronics_disabled() or _bomb_cooldown_left > 0.0:
		return
	if get_signal_strength(_remote_receiver) < REMOTE_PRECISION_ACTION_MIN_EFFECTIVE_SIGNAL:
		return
	primary_action_requested.emit()
	if _submit_remote_authority_action("primary"):
		_bomb_cooldown_left = maxf(_bomb_cooldown_left, bomb_cooldown)
		return
	_drop_bomb()


func request_primary_action() -> void:
	if not _placed or not _remote_control_active:
		return
	_on_remote_primary_action()


func _allows_secondary_remote_actions() -> bool:
	return true


func get_primary_action_cooldown_remaining() -> float:
	return _bomb_cooldown_left


func get_primary_action_cooldown_duration() -> float:
	return bomb_cooldown


func _on_remote_second_action() -> void:
	second_action_requested.emit()
	if _submit_remote_authority_action("second"):
		return

	# 以后可放：
	# 扫描
	# 切换无人机摄像头
	# 目标锁定
	# 投放诱饵
	pass


func _on_remote_interact() -> void:
	interact_requested.emit()
	if _submit_remote_authority_action("interact"):
		return
	_pickup()


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
		"device_type": "normal_drone",
		"client_time_msec": Time.get_ticks_msec(),
		"move": Input.get_vector("remote_left", "remote_right", "remote_forward", "remote_backward"),
		"vertical": Input.get_axis("remote_descend", "remote_ascend"),
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
		"device_type": "normal_drone",
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


func _drop_bomb() -> void:
	if bomb_scene == null:
		push_warning("NormalDrone: bomb_scene 尚未在 Inspector 中指定。")
		return
	if not is_instance_valid(bullet_mount_slot):
		return

	if _bomb_cooldown_left > 0.0:
		return

	var bomb_instance := bomb_scene.instantiate()

	if not (bomb_instance is Node3D):
		push_error("NormalDrone: bomb_scene 的根节点必须继承 Node3D。")
		return

	GlobalVar.gameworld.add_child(bomb_instance)

	bomb_instance.global_transform = bullet_mount_slot.global_transform
		# 继承无人机当前速度，并获得初始向下速度。
	var bomb_initvelocity = velocity + Vector3.DOWN * bomb_initial_down_speed
	bomb_instance.run(bullet_mount_slot.global_position,bomb_initvelocity,tool_owner)
	_bomb_cooldown_left = bomb_cooldown
	bomb_dropped.emit(bomb_instance)


func _pickup() -> void:
	# CargoMountPos 已经保留。
	# 后续可从这里加入吊货、拾取、挂载货物逻辑。
	pass


func activate_tool() -> void:
	collision_layer = 128
	_placed = true
	startup_bomb_lock = maxf(
		0.0,
		CombatBalance.get_float("normal_drone", "startup_bomb_lock", startup_bomb_lock)
	)
	_bomb_cooldown_left = maxf(_bomb_cooldown_left, startup_bomb_lock)
	# 不要在这里设为 true。
	# 放置无人机不等于立刻进入遥控。
	power_on = false
	bomb_scene = load("res://character/weapons/boom.tscn")
	place_ready_setting()
	_update_health_label()

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

	var drone := load(
		"res://character/weapons/NormalDrone.tscn"
	).instantiate() as NormalDrone

	GlobalVar.gameworld.add_child(drone)

	drone.global_position = ground_position + Vector3(0.0, 0.3, 0.0)

	drone.tool_owner = tool_owner
	drone.activate_tool()
	return {
		"remote_node": drone
	}


func _apply_damage(strength:float):
	current_hp = maxf(0.0, current_hp - strength)
	_update_health_label()
	return	
	
func impact(
	effect: String,
	strength: float,
	attacker_team: String = ""
) -> bool:
	if not attacker_team.is_empty() and tool_owner == attacker_team:
		return false
	var last_effect = effect.to_lower()
	if last_effect == "repair_laser":
		_electronics_disabled_remaining = maxf(
			_electronics_disabled_remaining,
			CombatBalance.get_electronic_disable_duration(_electronics_balance_id(), "repair_laser")
		)
		velocity = Vector3.ZERO
		return true
	if strength <= 0.0:
		return false
	_apply_damage(strength)
	if current_hp <= 0.0:
		remote_signal_lost.emit()
		call_deferred("queue_free")
		return true
	match last_effect:
		"flame", "fire":
			_flame_remaining = maxf(_flame_remaining, CombatBalance.get_float("remote_electronics", "flame_duration"))
			_flame_damage_per_second = maxf(_flame_damage_per_second, strength * CombatBalance.get_float("remote_electronics", "flame_damage_multiplier"))
		"lightening", "lightning":
			_electronics_disabled_remaining = maxf(_electronics_disabled_remaining, CombatBalance.get_electronic_disable_duration(_electronics_balance_id(), "lightning"))
			velocity = Vector3.ZERO
		"labeled":
			pass
	return true


func _electronics_balance_id() -> String:
	return "normal_drone"
	
	
func _on_hit_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests():
		return
	if not (body is BoomBullet or body is RubberBullet or body is ColorBullet or body is NailBullet or \
	body is DetectLaserBullet):
		return
	var projectile_owner := str(body.get_bullet_owner())
	if projectile_owner == tool_owner:
		return

	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet or body is DetectLaserBullet:
		effect = body.bullet_effect
	var strength = body.bullet_strength
	if impact(effect, strength, projectile_owner):
		body.queue_free()
