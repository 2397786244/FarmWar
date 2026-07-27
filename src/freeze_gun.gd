extends Node3D
class_name FreezeGunTool

@export var tool_owner := ""
@export var bullet_speed := 60.0

const BULLET_SCENE := preload("res://character/weapons/ColorBullet.tscn")

@onready var muzzle: Marker3D = $Muzzle
@onready var muzzle_flash: GPUParticles3D = $Muzzle/MuzzleFlash
@onready var model: Node3D = $FreezeGun

var is_aiming := false
var model_rest_position := Vector3.ZERO


func _ready() -> void:
	model_rest_position = model.position


func emit() -> void:
	_emit_bullet(false)


func emit_visual_only() -> void:
	_emit_bullet(true)


func _emit_bullet(visual_only: bool) -> void:
	if tool_owner.is_empty() or not is_instance_valid(GlobalVar.gameworld):
		return

	var bullet := BULLET_SCENE.instantiate() as ColorBullet
	bullet.color = Color.DODGER_BLUE
	bullet.bullet_effect = "Freeze"
	if visual_only:
		bullet.make_visual_only()
	GlobalVar.gameworld.add_child(bullet)
	var shooter := _get_shooter()
	var direction := _get_center_screen_direction(shooter)
	bullet.speed = bullet_speed
	bullet.run(muzzle.global_position, direction, tool_owner)

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

	var camera := shooter.get_node_or_null("Head/Camera3D") as Camera3D
	if camera == null:
		return -muzzle.global_transform.basis.z.normalized()

	var screen_center := camera.get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(screen_center)
	var ray_direction := camera.project_ray_normal(screen_center).normalized()
	var aim_point := ray_origin + ray_direction * 60.0

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
	model.position = model_rest_position + Vector3(0.0, 0.025, 0.07)
	tween.tween_property(model, "position", model_rest_position, 0.12)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
