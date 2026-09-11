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
var spread_rng := RandomNumberGenerator.new()


func _ready() -> void:
	model_rest_position = model.position
	spread_rng.randomize()


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


## Draw an authoritative shotgun pattern without generating a second random
## local pattern. Used by local authority and AI pellet hitscan results.
func emit_visual_only_pellets(pellet_results: Array) -> void:
	play_muzzle_visual()
	if tool_owner.is_empty() or profile_id.is_empty() \
			or not is_instance_valid(GlobalVar.gameworld):
		return
	var shooter := _get_shooter()
	for pellet_value: Variant in pellet_results:
		if not pellet_value is Dictionary:
			continue
		var pellet := pellet_value as Dictionary
		var direction_value: Variant = pellet.get("direction", Vector3.ZERO)
		if not direction_value is Vector3 or (direction_value as Vector3).length_squared() <= 0.001:
			continue
		var travel_distance := float(pellet.get("visual_distance", -1.0))
		if travel_distance < 0.0 and str(pellet.get("hit_kind", "none")) != "none":
			var hit_position_value: Variant = pellet.get("hit_position", null)
			if hit_position_value is Vector3:
				travel_distance = muzzle.global_position.distance_to(hit_position_value as Vector3)
		_spawn_bullet(
			(direction_value as Vector3).normalized(),
			true,
			shooter,
			travel_distance
		)


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
	for pellet_direction in _sample_circular_spread(
		center_direction,
		bullet_count,
		spread_degrees
	):
		_spawn_bullet(
			pellet_direction,
			visual_only,
			shooter,
			travel_distance
		)


func _sample_circular_spread(
	center_direction: Vector3,
	bullet_count: int,
	full_spread_degrees: float
) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var direction := center_direction.normalized()
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	var reference_up := Vector3.UP if absf(direction.dot(Vector3.UP)) <= 0.98 else Vector3.RIGHT
	var spread_right := direction.cross(reference_up).normalized()
	var spread_up := spread_right.cross(direction).normalized()
	# Existing profile values are the full fan width, so the circular cone radius
	# remains spread/2: Shotgun 1 degree, Remington870 1.5 degrees.
	var max_radius := tan(deg_to_rad(maxf(0.0, full_spread_degrees) * 0.5))
	for _pellet_index in range(maxi(1, bullet_count)):
		var polar_angle := spread_rng.randf_range(0.0, TAU)
		var radial_offset := max_radius * sqrt(spread_rng.randf())
		result.append((
			direction
			+ (spread_right * cos(polar_angle) + spread_up * sin(polar_angle)) * radial_offset
		).normalized())
	return result


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


func _play_recoil() -> void:
	var tween := create_tween()
	var recoil_offset := CombatBalance.get_model_recoil_offset(profile_id)
	model.position = model_rest_position + recoil_offset
	tween.tween_property(
		model, "position", model_rest_position, CombatBalance.MODEL_RECOIL_DURATION
	) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
