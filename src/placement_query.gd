extends RefCounted
class_name PlacementQuery

const DEFAULT_GROUND_MASK := 1
const DEFAULT_MAX_SLOPE_DEGREES := 5.0
const DEFAULT_CLEARANCE := 0.15
const DEFAULT_GROUND_RAY_ABOVE := 20.0
const DEFAULT_GROUND_RAY_BELOW := 48.0


static func resolve_free_placement(
	world: World3D,
	requested_position: Vector3,
	player_position: Vector3,
	placement_yaw: float,
	collision_shape: Shape3D,
	collision_transform: Transform3D,
	blocking_mask: int,
	exceptions: Array = [],
	ground_mask: int = DEFAULT_GROUND_MASK,
	max_slope_degrees: float = DEFAULT_MAX_SLOPE_DEGREES,
	clearance: float = DEFAULT_CLEARANCE,
	ground_ray_above: float = DEFAULT_GROUND_RAY_ABOVE,
	ground_ray_below: float = DEFAULT_GROUND_RAY_BELOW
) -> Dictionary:
	if world == null or collision_shape == null:
		return {"ok": false, "reason": "placement_query_unavailable"}

	var direct_space_state := world.direct_space_state
	var ray_center_y := maxf(requested_position.y, player_position.y)
	var ray_start := Vector3(
		requested_position.x,
		ray_center_y + ground_ray_above,
		requested_position.z
	)
	var ray_end := Vector3(
		requested_position.x,
		ray_center_y - ground_ray_below,
		requested_position.z
	)
	var ground_query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	ground_query.collision_mask = ground_mask
	ground_query.collide_with_bodies = true
	ground_query.collide_with_areas = true
	ground_query.exclude = exceptions
	var ground_hit := direct_space_state.intersect_ray(ground_query)
	if ground_hit.is_empty() or not ground_hit.has("position"):
		return {
			"ok": false,
			"reason": "placement_no_ground",
			"requested_position": requested_position,
		}

	var ground_normal := Vector3.UP
	var normal_value: Variant = ground_hit.get("normal", Vector3.UP)
	if normal_value is Vector3:
		ground_normal = (normal_value as Vector3).normalized()
	var slope_degrees := rad_to_deg(acos(clampf(ground_normal.dot(Vector3.UP), -1.0, 1.0)))
	if slope_degrees > max_slope_degrees:
		return {
			"ok": false,
			"reason": "placement_too_steep",
			"ground_position": ground_hit.get("position", requested_position),
			"ground_normal": ground_normal,
			"slope_degrees": slope_degrees,
		}

	var ground_position := ground_hit.get("position", requested_position) as Vector3
	if WaterBody3D.is_surface_blocked(ground_position):
		return {
			"ok": false,
			"reason": "placement_in_water",
			"ground_position": ground_position,
			"ground_normal": ground_normal,
			"slope_degrees": slope_degrees,
		}

	var support_offset := support_offset_for_shape(collision_shape, collision_transform)
	var placement_position := ground_position + Vector3.UP * support_offset
	var clearance_shape := make_clearance_shape(collision_shape, clearance)
	if clearance_shape == null:
		return {
			"ok": false,
			"reason": "placement_unsupported_collision_shape",
			"ground_position": ground_position,
		}

	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = clearance_shape
	shape_query.transform = Transform3D(
		Basis(Vector3.UP, placement_yaw),
		placement_position
	) * collision_transform
	shape_query.collision_mask = blocking_mask
	shape_query.collide_with_bodies = true
	shape_query.collide_with_areas = false
	shape_query.exclude = exceptions
	var collisions := direct_space_state.intersect_shape(shape_query, 32)
	var result := {
		"ok": collisions.is_empty(),
		"reason": "" if collisions.is_empty() else "placement_blocked",
		"position": placement_position,
		"ground_position": ground_position,
		"ground_normal": ground_normal,
		"slope_degrees": slope_degrees,
		"support_offset": support_offset,
		"collisions": collisions,
	}
	return result


static func support_offset_for_shape(
	shape: Shape3D,
	shape_transform: Transform3D
) -> float:
	var transform := shape_transform
	var y_extent := 0.0
	if shape is BoxShape3D:
		var half_size := (shape as BoxShape3D).size * 0.5
		y_extent = (
			absf(transform.basis.x.y) * half_size.x
			+ absf(transform.basis.y.y) * half_size.y
			+ absf(transform.basis.z.y) * half_size.z
		)
	elif shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius
		y_extent = radius * Vector3(
			transform.basis.x.y,
			transform.basis.y.y,
			transform.basis.z.y
		).length()
	elif shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var radius := capsule.radius
		var segment_half_height := maxf(0.0, capsule.height * 0.5 - radius)
		var sphere_y_extent := radius * Vector3(
			transform.basis.x.y,
			transform.basis.y.y,
			transform.basis.z.y
		).length()
		y_extent = absf(transform.basis.y.y) * segment_half_height + sphere_y_extent
	elif shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		var radial_y_extent := cylinder.radius * sqrt(
			pow(transform.basis.x.y, 2.0) + pow(transform.basis.z.y, 2.0)
		)
		y_extent = absf(transform.basis.y.y) * cylinder.height * 0.5 + radial_y_extent
	else:
		return -transform.origin.y
	return -(transform.origin.y - y_extent)


static func make_clearance_shape(source_shape: Shape3D, clearance: float) -> Shape3D:
	var expanded := source_shape.duplicate(true) as Shape3D
	if expanded is BoxShape3D:
		(expanded as BoxShape3D).size += Vector3.ONE * clearance * 2.0
	elif expanded is SphereShape3D:
		(expanded as SphereShape3D).radius += clearance
	elif expanded is CapsuleShape3D:
		var capsule := expanded as CapsuleShape3D
		capsule.radius += clearance
		capsule.height += clearance * 2.0
	elif expanded is CylinderShape3D:
		var cylinder := expanded as CylinderShape3D
		cylinder.radius += clearance
		cylinder.height += clearance * 2.0
	else:
		return null
	return expanded
