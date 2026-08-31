extends Node3D
class_name NailGunTool

@export var tool_owner := ""
@export var bullet_speed := 120

const BULLET_SCENE := preload("res://character/weapons/NailBullet.tscn")

@onready var muzzle: Marker3D = $Muzzle
@onready var muzzle_flash: GPUParticles3D = $Muzzle/MuzzleFlash
@onready var muzzle_flash_visual: Node = $Muzzle/MuzzleFlashVisual
@onready var model: Node3D = $NailGun

var is_aiming := false
var model_rest_position := Vector3.ZERO

func _ready() -> void:
	model_rest_position = model.position


func emit() -> void:
	_emit_bullet(false)


func emit_visual_only() -> void:
	_emit_bullet(true)


## AI hitscan 在权威端完成伤害结算后使用，视觉弹道严格沿用同一条射线。
func emit_visual_only_tracer(direction: Vector3, travel_distance := -1.0) -> void:
	_emit_bullet(true, direction, travel_distance)


func get_fire_origin() -> Vector3:
	return muzzle.global_position if is_instance_valid(muzzle) else global_position


func get_fire_direction() -> Vector3:
	return -muzzle.global_transform.basis.z.normalized() if is_instance_valid(muzzle) else -global_transform.basis.z.normalized()


func _emit_bullet(
	visual_only: bool,
	direction_override := Vector3.ZERO,
	travel_distance := -1.0
) -> void:
	# Keep the local first-person muzzle presentation independent from the
	# gameplay projectile/world validation below.
	play_muzzle_visual()
	if tool_owner.is_empty() or not is_instance_valid(GlobalVar.gameworld):
		return

	var bullet := BULLET_SCENE.instantiate() as NailBullet
	if visual_only:
		bullet.make_visual_only()
	GlobalVar.gameworld.add_child(bullet)
	var shooter := _get_shooter()
	var direction := _get_center_screen_direction(shooter)
	if direction_override.length_squared() > 0.001:
		direction = direction_override.normalized()
	bullet.speed = CombatBalance.get_float("nail_gun", "visual_speed", bullet_speed)
	bullet.max_distance = CombatBalance.get_float("nail_gun", "range", bullet.max_distance)
	bullet.max_lifetime = CombatBalance.get_float("nail_gun", "visual_lifetime", bullet.max_lifetime)
	if travel_distance >= 0.0:
		bullet.max_distance = minf(bullet.max_distance, maxf(0.01, travel_distance))
		if bullet.speed > 0.01:
			bullet.max_lifetime = minf(bullet.max_lifetime, bullet.max_distance / bullet.speed)
	bullet.run(muzzle.global_position, direction, tool_owner)

func play_muzzle_visual(firepower: float = -1.0) -> void:
	var effective_firepower := firepower
	if effective_firepower <= 0.0:
		effective_firepower = CombatBalance.get_float("nail_gun", "damage", 20.0)
	if is_instance_valid(muzzle_flash_visual) and muzzle_flash_visual.has_method("play"):
		muzzle_flash_visual.call("play", effective_firepower)
	else:
		muzzle_flash.restart()
	_play_recoil()


func set_aiming(value: bool) -> void:
	is_aiming = value


func _get_shooter() -> CollisionObject3D:
	var node: Node = get_parent()
	while node != null:
		if node is CollisionObject3D:
			return node as CollisionObject3D
		node = node.get_parent()
	return null


func _get_center_screen_direction(shooter: CollisionObject3D) -> Vector3:
	if not is_instance_valid(shooter):
		return -muzzle.global_transform.basis.z.normalized()
	var max_distance := CombatBalance.get_float("nail_gun", "range", 80.0)
	if shooter.has_method("get_shooting_aim_direction"):
		var shared_direction: Variant = shooter.call(
			"get_shooting_aim_direction",
			muzzle.global_position,
			max_distance
		)
		if shared_direction is Vector3 and (shared_direction as Vector3).length_squared() > 0.001:
			return (shared_direction as Vector3).normalized()

	var camera := shooter.get_node_or_null("Head/Camera3D") as Camera3D
	if camera == null:
		return -muzzle.global_transform.basis.z.normalized()

	var screen_center := camera.get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(screen_center)
	var ray_direction := camera.project_ray_normal(screen_center).normalized()
	var aim_point := ray_origin + ray_direction * max_distance

	# 先从摄像机中心做射线检测，准心指到近处障碍物时也能准确命中。
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		aim_point,
		139
	)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		aim_point = hit["position"]

	return (aim_point - muzzle.global_position).normalized()


func _play_recoil() -> void:
	var tween := create_tween()
	var recoil_offset := CombatBalance.get_model_recoil_offset("nail_gun")
	model.position = model_rest_position + recoil_offset
	tween.tween_property(
		model, "position", model_rest_position, CombatBalance.MODEL_RECOIL_DURATION
	)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
