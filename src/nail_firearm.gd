extends Node3D
class_name NailFirearmTool

const BULLET_SCENE := preload("res://character/weapons/NailBullet.tscn")

@export var tool_owner := ""
@export var profile_id := ""

@onready var muzzle: Marker3D = $Muzzle
@onready var muzzle_flash: GPUParticles3D = $Muzzle/MuzzleFlash
@onready var model: Node3D = $Mesh

var is_aiming := false
var model_rest_position := Vector3.ZERO


func _ready() -> void:
	model_rest_position = model.position


func emit() -> void:
	_emit_bullets(false)


func emit_visual_only() -> void:
	_emit_bullets(true)


func _emit_bullets(visual_only: bool) -> void:
	if tool_owner.is_empty() or profile_id.is_empty() \
			or not is_instance_valid(GlobalVar.gameworld):
		return

	var shooter := _get_shooter()
	var center_direction := _get_center_screen_direction(shooter)
	var bullet_count := maxi(1, CombatBalance.get_int(profile_id, "bullet_count", 1))
	var spread_degrees := CombatBalance.get_float(profile_id, "spread_degrees")
	var spread_axis := _get_spread_axis(shooter)
	for index in range(bullet_count):
		var angle_degrees := 0.0
		if bullet_count > 1:
			angle_degrees = lerpf(
				-spread_degrees * 0.5,
				spread_degrees * 0.5,
				float(index) / float(bullet_count - 1)
			)
		_spawn_bullet(
			center_direction.rotated(spread_axis, deg_to_rad(angle_degrees)),
			visual_only
		)

	muzzle_flash.restart()
	_play_recoil()


func set_aiming(value: bool) -> void:
	is_aiming = value


func play_muzzle_visual() -> void:
	muzzle_flash.restart()
	_play_recoil()


func _spawn_bullet(direction: Vector3, visual_only := false) -> void:
	var bullet := BULLET_SCENE.instantiate() as NailBullet
	if bullet == null:
		return
	bullet.speed = CombatBalance.get_float(profile_id, "visual_speed")
	bullet.max_distance = CombatBalance.get_float(profile_id, "range")
	bullet.bullet_strength = CombatBalance.get_float(profile_id, "damage")
	bullet.knockback_force = CombatBalance.get_float(profile_id, "knockback")
	if visual_only:
		bullet.make_visual_only()
	GlobalVar.gameworld.add_child(bullet)
	bullet.run(muzzle.global_position, direction.normalized(), tool_owner)


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

	var camera := shooter.get_node_or_null("Head/Camera3D") as Camera3D
	if camera == null:
		return -muzzle.global_transform.basis.z.normalized()

	var max_distance := CombatBalance.get_float(profile_id, "range")
	var screen_center := camera.get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(screen_center)
	var ray_direction := camera.project_ray_normal(screen_center).normalized()
	var aim_point := ray_origin + ray_direction * max_distance
	var query := PhysicsRayQueryParameters3D.create(ray_origin, aim_point, 139)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		aim_point = hit["position"]
	return (aim_point - muzzle.global_position).normalized()


func _get_spread_axis(shooter: CollisionObject3D) -> Vector3:
	if is_instance_valid(shooter):
		var camera := shooter.get_node_or_null("Head/Camera3D") as Camera3D
		if camera != null:
			return camera.global_transform.basis.y.normalized()
	return Vector3.UP


func _play_recoil() -> void:
	var tween := create_tween()
	model.position = model_rest_position + Vector3(0.0, 0.025, 0.07)
	tween.tween_property(model, "position", model_rest_position, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
