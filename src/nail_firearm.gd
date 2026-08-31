extends Node3D
class_name NailFirearmTool

const BULLET_SCENE := preload("res://character/weapons/NailBullet.tscn")

@export var tool_owner := ""
@export var profile_id := ""

@onready var muzzle: Marker3D = $Muzzle
@onready var muzzle_flash: GPUParticles3D = $Muzzle/MuzzleFlash
@onready var muzzle_flash_visual: Node = get_node_or_null("Muzzle/MuzzleFlashVisual")
@onready var model: Node3D = $Mesh

var is_aiming := false
var model_rest_position := Vector3.ZERO


func _ready() -> void:
	model_rest_position = model.position


func emit() -> void:
	_emit_bullets(false)


func emit_visual_only() -> void:
	_emit_bullets(true)


## AI authority uses a server-side hitscan for gameplay, then calls this
## method to draw the same shot locally without creating a damage projectile.
## Keeping the direction/distance explicit prevents the visual tracer from
## diverging from the authoritative AI ray.
func emit_visual_only_tracer(
	direction: Vector3,
	travel_distance: float = -1.0
) -> void:
	_emit_bullets(true, direction, travel_distance)


func get_fire_origin() -> Vector3:
	return muzzle.global_position if is_instance_valid(muzzle) else global_position


func get_fire_direction() -> Vector3:
	if is_instance_valid(muzzle):
		return -muzzle.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()


func _emit_bullets(
	visual_only: bool,
	direction_override: Vector3 = Vector3.ZERO,
	travel_distance: float = -1.0
) -> void:
	# Muzzle flash and recoil are local presentation.  They must still happen
	# for first-person visual-only shots when gameplay state is not yet valid.
	play_muzzle_visual()
	if tool_owner.is_empty() or profile_id.is_empty() \
			or not is_instance_valid(GlobalVar.gameworld):
		return

	var shooter := _get_shooter()
	var center_direction := _get_center_screen_direction(shooter)
	if direction_override.length_squared() > 0.001:
		center_direction = direction_override.normalized()
	var bullet_count := maxi(1, CombatBalance.get_int(profile_id, "bullet_count", 1))
	var spread_degrees := CombatBalance.get_float(profile_id, "spread_degrees")
	var spread_axis := _get_spread_axis(shooter, center_direction)
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
			visual_only,
			shooter,
			travel_distance
		)


func set_aiming(value: bool) -> void:
	is_aiming = value


func play_muzzle_visual(firepower: float = -1.0) -> void:
	var effective_firepower := firepower
	if effective_firepower <= 0.0:
		effective_firepower = CombatBalance.get_float(profile_id, "damage", 30.0)
	if is_instance_valid(muzzle_flash_visual) and muzzle_flash_visual.has_method("play"):
		muzzle_flash_visual.call("play", effective_firepower)
	else:
		muzzle_flash.restart()
		muzzle_flash.emitting = true
	_play_recoil()


func _spawn_bullet(
	direction: Vector3,
	visual_only := false,
	shooter: CollisionObject3D = null,
	travel_distance: float = -1.0
) -> void:
	var bullet := BULLET_SCENE.instantiate() as NailBullet
	if bullet == null:
		return
	bullet.speed = CombatBalance.get_float(profile_id, "visual_speed")
	bullet.max_distance = CombatBalance.get_float(profile_id, "range")
	bullet.max_lifetime = CombatBalance.get_float(profile_id, "visual_lifetime", bullet.max_lifetime)
	if travel_distance >= 0.0:
		bullet.max_distance = minf(bullet.max_distance, maxf(0.01, travel_distance))
		if bullet.speed > 0.01:
			bullet.max_lifetime = minf(
				bullet.max_lifetime,
				maxf(0.01, travel_distance / bullet.speed)
			)
	bullet.bullet_strength = CombatBalance.get_float(profile_id, "damage")
	bullet.knockback_force = CombatBalance.get_float(profile_id, "knockback")
	if visual_only:
		bullet.make_visual_only()
	GlobalVar.gameworld.add_child(bullet)
	bullet.run(muzzle.global_position, direction.normalized(), tool_owner, shooter)


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
	var max_distance := CombatBalance.get_float(profile_id, "range")
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
	var query := PhysicsRayQueryParameters3D.create(ray_origin, aim_point, 139)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		aim_point = hit["position"]
	return (aim_point - muzzle.global_position).normalized()


func _get_spread_axis(shooter: CollisionObject3D, center_direction := Vector3.ZERO) -> Vector3:
	if center_direction.length_squared() > 0.001:
		var screen_right := center_direction.cross(Vector3.UP).normalized()
		var spread_axis := screen_right.cross(center_direction).normalized()
		if spread_axis.length_squared() > 0.001:
			return spread_axis
	if is_instance_valid(shooter):
		var camera := shooter.get_node_or_null("Head/Camera3D") as Camera3D
		if camera != null:
			return camera.global_transform.basis.y.normalized()
	return Vector3.UP


func _play_recoil() -> void:
	var tween := create_tween()
	var recoil_offset := CombatBalance.get_model_recoil_offset(profile_id)
	model.position = model_rest_position + recoil_offset
	tween.tween_property(
		model, "position", model_rest_position, CombatBalance.MODEL_RECOIL_DURATION
	) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
