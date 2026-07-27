extends CharacterBody3D
class_name DefendBullet

## 拦截弹逻辑：
##
## 目标有效：
## - 追踪目标
## - 靠近目标时引爆目标，并自身销毁
##
## 目标为空或失效：
## - 不自毁
## - 不再转向追踪
## - 保持当前速度方向直线飞行
##
## 无论是否有目标：
## - 撞到任意碰撞体时自身自毁
## - lifetime 结束时自身自毁


@export_category("Target")

## 要拦截的敌方炮弹。
@export var target_bullet: Node3D


@export_category("Movement")

## 追踪炮弹飞行速度，单位：米/秒。
@export var move_speed: float = 200.0

## 数值越大，转向越灵敏。
## 10 ~ 20：较自然
## 100：接近瞬间锁定
@export var turn_speed: float = 16.0


@export_category("Detonation")

## 拦截距离，单位：米。
##
## move_speed = 200 时，建议设为 2.5 ~ 4.0。
## 过小可能导致高速时两帧之间直接穿过去。
@export var detonation_distance: float = 4.0

## 最大存在时间。
@export var lifetime: float = 3.0


var _life_left: float = 0.0
var _has_detonated: bool = false
var bullet_owner := ""


func get_bullet_owner() -> String:
	return bullet_owner


func track(target: Node3D, speed: float) -> void:
	target_bullet = target
	move_speed = speed


func _ready() -> void:
	_life_left = lifetime

	# 空中飞行物不需要“地面模式”。
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING


func _physics_process(delta: float) -> void:
	if _has_detonated:
		return

	_life_left -= delta
	var projectile_delta := delta

	# 条件 1：寿命结束，自毁。
	if _life_left <= 0.0:
		_self_destruct()
		return

	# 目标是否仍然有效。
	var has_valid_target: bool = (
		target_bullet != null
		and is_instance_valid(target_bullet)
	)

	# 记录本帧开始时的位置，用于后续高速拦截检测。
	var interceptor_start_position: Vector3 = global_position
	var target_start_position: Vector3 = Vector3.ZERO

	if has_valid_target:
		target_start_position = target_bullet.global_position

		var to_target: Vector3 = (
			target_start_position
			- interceptor_start_position
		)

		var distance_to_target: float = to_target.length()

		# 本帧开始时已经非常接近目标，直接引爆。
		if distance_to_target <= detonation_distance:
			_detonate_target_bullet()
			return

		# 有效目标存在：正常追踪。
		_update_tracking_velocity(
			to_target,
			projectile_delta
		)

	else:
		# 目标为空或已经失效：
		# 不自毁，保持当前方向直飞。
		_keep_flying_straight()

	# 炮弹模型朝向飞行方向。
	_update_visual_forward()

	# 保留原来的碰撞逻辑：
	# 撞到目标则拦截；
	# 撞到墙、地面、建筑、其他碰撞体则自身自毁。
	var collision: KinematicCollision3D = move_and_collide(
		velocity * projectile_delta
	)

	if collision != null:
		var collider: Object = collision.get_collider()

		# 只有目标仍有效时，才判断碰撞物是否为目标。
		if (
			has_valid_target
			and target_bullet != null
			and is_instance_valid(target_bullet)
			and _is_target_or_target_child(collider)
		):
			_detonate_target_bullet()
			return

		# 撞到其他任意碰撞体：自身爆炸。
		_self_destruct()
		return

	# 目标无效时，不再做高速拦截检测。
	# 下一帧继续保持直线飞行即可。
	if not has_valid_target:
		return

	# 目标可能在这一帧被别的逻辑销毁。
	# 此时不自毁；下一帧自动进入直线飞行分支。
	if target_bullet == null or not is_instance_valid(target_bullet):
		return

	# 移动后再检测本帧内双方最近距离。
	# 防止高速情况下两枚炮弹一帧内“穿过彼此”却没触发拦截。
	var interceptor_end_position: Vector3 = global_position
	var target_end_position: Vector3 = target_bullet.global_position

	var relative_start: Vector3 = (
		target_start_position
		- interceptor_start_position
	)

	var relative_end: Vector3 = (
		target_end_position
		- interceptor_end_position
	)

	var closest_distance: float = _get_closest_distance_to_origin(
		relative_start,
		relative_end
	)

	if closest_distance <= detonation_distance:
		_detonate_target_bullet()


func _update_tracking_velocity(
	to_target: Vector3,
	delta: float
) -> void:
	if to_target.length_squared() < 0.000001:
		return

	var desired_direction: Vector3 = to_target.normalized()
	var desired_velocity: Vector3 = desired_direction * move_speed

	# 第一次飞行时直接给予初速度。
	if velocity.length_squared() < 0.01:
		velocity = desired_velocity
		return

	# 平滑转向。
	var steering_weight: float = clampf(
		turn_speed * delta,
		0.0,
		1.0
	)

	velocity = velocity.lerp(
		desired_velocity,
		steering_weight
	)

	# lerp 后可能会损失一点速度长度，
	# 统一恢复到 move_speed。
	if velocity.length_squared() > 0.000001:
		velocity = velocity.normalized() * move_speed
	else:
		velocity = desired_velocity


func _keep_flying_straight() -> void:
	# 目标失效后，保持最后一次飞行方向。
	if velocity.length_squared() > 0.000001:
		velocity = velocity.normalized() * move_speed
		return

	# 极少数情况：
	# 拦截弹刚生成时目标就是 null，且还未获得任何速度。
	# 此时按照模型自身本地 -Z 前方直飞。
	var forward_direction: Vector3 = -global_transform.basis.z

	if forward_direction.length_squared() < 0.000001:
		forward_direction = Vector3.FORWARD

	velocity = forward_direction.normalized() * move_speed


func _update_visual_forward() -> void:
	if velocity.length_squared() < 0.000001:
		return

	var forward_direction: Vector3 = velocity.normalized()
	var up_direction: Vector3 = Vector3.UP

	# 飞行方向接近竖直时，避免 look_at 的 up 与 forward 平行。
	if absf(forward_direction.dot(up_direction)) > 0.99:
		up_direction = Vector3.FORWARD

	# Godot 默认模型本地 -Z 是前方。
	look_at(
		global_position + forward_direction,
		up_direction
	)


# 计算一条线段到原点的最近距离。
#
# relative_start：
# 当前帧开始时，目标相对拦截弹的位置。
#
# relative_end：
# 当前帧结束时，目标相对拦截弹的位置。
func _get_closest_distance_to_origin(
	relative_start: Vector3,
	relative_end: Vector3
) -> float:
	var relative_motion: Vector3 = (
		relative_end
		- relative_start
	)

	var motion_length_squared: float = (
		relative_motion.length_squared()
	)

	if motion_length_squared < 0.000001:
		return relative_start.length()

	var t: float = clampf(
		-relative_start.dot(relative_motion)
		/ motion_length_squared,
		0.0,
		1.0
	)

	var closest_relative_position: Vector3 = (
		relative_start
		+ relative_motion * t
	)

	return closest_relative_position.length()


# 判断碰撞对象是否为 target_bullet，
# 或者是否为 target_bullet 内部的子节点。
func _is_target_or_target_child(
	collider: Object
) -> bool:
	if target_bullet == null or not is_instance_valid(target_bullet):
		return false

	if collider == target_bullet:
		return true

	if collider is Node:
		var collider_node: Node = collider as Node

		# collider 是 target_bullet 的子节点。
		if target_bullet.is_ancestor_of(collider_node):
			return true

		# collider 是 target_bullet 的父节点。
		if collider_node.is_ancestor_of(target_bullet):
			return true

	return false


# 成功拦截敌方炮弹。
func _detonate_target_bullet() -> void:
	if _has_detonated:
		return

	_has_detonated = true

	if target_bullet != null and is_instance_valid(target_bullet):
		# 推荐敌方炮弹实现 explode()。
		if target_bullet.has_method("explode"):
			target_bullet.call("explode")

		# 兼容 detonate() 命名。
		elif target_bullet.has_method("detonate"):
			target_bullet.call("detonate")

		# 没有爆炸函数，至少销毁目标。
		else:
			target_bullet.queue_free()

	_play_intercept_effect()

	queue_free()


# lifetime 结束、或撞到普通碰撞体时调用。
func _self_destruct() -> void:
	if _has_detonated:
		return

	_has_detonated = true

	_play_intercept_effect()

	queue_free()


# 后续可以加入：
# - 爆炸粒子
# - 拦截闪光
# - 音效
# - 冲击波
func _play_intercept_effect() -> void:
	pass
