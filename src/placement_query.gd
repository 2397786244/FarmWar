extends RefCounted
class_name PlacementQuery

const DEFAULT_GROUND_MASK := 1
const DEFAULT_MAX_SLOPE_DEGREES := 5.0
const DEFAULT_CLEARANCE := 0.15
const DEFAULT_GROUND_RAY_ABOVE := 20.0
const DEFAULT_GROUND_RAY_BELOW := 48.0
const WALL_SNAP_DISTANCE := 1.0
const WALL_MIN_JOINT_ANGLE_DEGREES := 30.0
const WALL_FAMILY_BY_TOOL_ID := {
	"tall_brick": "brick",
	"tall_log_wall": "log",
	"tall_mesh_wall": "mesh",
	"wire_mesh_gate": "mesh",
}


static func wall_family_for_tool(tool_id: String) -> String:
	var normalized_id := tool_id.to_lower().replace(" ", "_")
	if WALL_FAMILY_BY_TOOL_ID.has(normalized_id):
		return str(WALL_FAMILY_BY_TOOL_ID[normalized_id])
	match normalized_id:
		"tallbrick":
			return "brick"
		"talllogwall":
			return "log"
		"tallmeshwall", "wiremeshgate":
			return "mesh"
	return ""


static func wall_tool_id_for_scene(scene_path: String) -> String:
	var normalized_path := scene_path.to_lower()
	if normalized_path.ends_with("tallbrick.tscn"):
		return "tall_brick"
	if normalized_path.ends_with("talllogwall.tscn"):
		return "tall_log_wall"
	if normalized_path.ends_with("tallmeshwall.tscn"):
		return "tall_mesh_wall"
	if normalized_path.ends_with("wiremeshgate.tscn"):
		return "wire_mesh_gate"
	return ""


static func wall_half_length_for_shape(shape: Shape3D, shape_transform: Transform3D) -> float:
	if shape is BoxShape3D:
		var half_size := (shape as BoxShape3D).size * 0.5
		# Project the collision box onto the root's local X axis. This includes
		# the scene's local scale (the mesh walls use a 0.4 root-scale collider).
		return maxf(
			0.01,
			absf(shape_transform.basis.x.x) * half_size.x
			+ absf(shape_transform.basis.y.x) * half_size.y
			+ absf(shape_transform.basis.z.x) * half_size.z
		)
	return 0.0


static func wall_half_length_for_node(node: Node) -> float:
	if node == null or not is_instance_valid(node):
		return 0.0
	var collision_shape: CollisionShape3D = null
	var direct_shape := node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if direct_shape != null and direct_shape.shape != null:
		collision_shape = direct_shape
	else:
		for child in node.get_children():
			if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
				collision_shape = child as CollisionShape3D
				break
			if collision_shape == null:
				var nested_length := wall_half_length_for_node(child)
				if nested_length > 0.0:
					return nested_length
	if collision_shape == null:
		return 0.0
	return wall_half_length_for_shape(collision_shape.shape, collision_shape.transform)


static func wall_endpoint(center: Vector3, yaw: float, half_length: float, side: int) -> Vector3:
	var side_sign := -1.0 if side < 0 else 1.0
	return center + Basis(Vector3.UP, yaw) * Vector3(side_sign * half_length, 0.0, 0.0)


static func horizontal_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))


static func wall_joint_angle_degrees(
	first_center: Vector3,
	first_endpoint: Vector3,
	second_center: Vector3,
	second_endpoint: Vector3
) -> float:
	var first_direction := Vector2(
		first_center.x - first_endpoint.x,
		first_center.z - first_endpoint.z
	).normalized()
	var second_direction := Vector2(
		second_center.x - second_endpoint.x,
		second_center.z - second_endpoint.z
	).normalized()
	if first_direction.length_squared() <= 0.001 or second_direction.length_squared() <= 0.001:
		return 180.0
	return rad_to_deg(acos(clampf(first_direction.dot(second_direction), -1.0, 1.0)))


static func resolve_wall_endpoint_snap(
	requested_position: Vector3,
	placement_yaw: float,
	current_half_length: float,
	candidates: Array,
	max_distance := WALL_SNAP_DISTANCE
) -> Dictionary:
	if current_half_length <= 0.0 or candidates.is_empty():
		return {"active": false, "position": requested_position}
	var best_distance := max_distance
	var best_position := requested_position
	var best_source_id := ""
	var best_source_side := 0
	var best_preview_side := 0
	for preview_side in [-1, 1]:
		var preview_endpoint := wall_endpoint(
			requested_position,
			placement_yaw,
			current_half_length,
			preview_side
		)
		for candidate_value: Variant in candidates:
			if not candidate_value is Dictionary:
				continue
			var candidate := candidate_value as Dictionary
			var candidate_half_length := float(candidate.get("half_length", 0.0))
			if candidate_half_length <= 0.0:
				continue
			var candidate_position_value: Variant = candidate.get("position", Vector3.ZERO)
			if not candidate_position_value is Vector3:
				continue
			var candidate_position := candidate_position_value as Vector3
			var candidate_yaw := float(candidate.get("yaw", 0.0))
			for candidate_side in [-1, 1]:
				var candidate_endpoint := wall_endpoint(
					candidate_position,
					candidate_yaw,
					candidate_half_length,
					candidate_side
				)
				var joint_angle := wall_joint_angle_degrees(
					requested_position,
					preview_endpoint,
					candidate_position,
					candidate_endpoint
				)
				if joint_angle < WALL_MIN_JOINT_ANGLE_DEGREES:
					continue
				var distance := horizontal_distance(preview_endpoint, candidate_endpoint)
				if distance > best_distance:
					continue
				# Only translate in X/Z. The normal placement query will recast
				# the ground and choose the correct support height afterwards.
				var snapped_position := requested_position + Vector3(
					candidate_endpoint.x - preview_endpoint.x,
					0.0,
					candidate_endpoint.z - preview_endpoint.z
				)
				best_distance = distance
				best_position = snapped_position
				best_source_id = str(candidate.get("source_id", ""))
				best_source_side = candidate_side
				best_preview_side = preview_side
	return {
		"active": not best_source_id.is_empty(),
		"position": best_position,
		"distance": best_distance,
		"source_id": best_source_id,
		"source_side": best_source_side,
		"preview_side": best_preview_side,
	}


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
