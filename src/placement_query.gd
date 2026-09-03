extends RefCounted
class_name PlacementQuery

const VehicleSpawnCatalogScript = preload("res://src/vehicle_spawn_catalog.gd")

const DEFAULT_GROUND_MASK := 1
const DEFAULT_MAX_SLOPE_DEGREES := 5.0
const DEFAULT_CLEARANCE := 0.15
const PLACEMENT_FOOTPRINT_CLEARANCE := 0.02
const PLACEMENT_FOOTPRINT_NODE_NAME := "PlacementFootprint"
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

## Vehicle placement deliberately keeps the collision-layer values local to
## this low-level query helper.  This avoids a dependency cycle with
## GameAuthority while keeping the runtime and editor rules explicit.
const COLLISION_LAYER_GROUND := 1
const COLLISION_LAYER_WALL := 2
const COLLISION_LAYER_CHARACTER := 8
const COLLISION_LAYER_FARM_TILE := 64
const COLLISION_LAYER_TOOL := 128
const COLLISION_LAYER_BUILDING := 4096
const COLLISION_LAYER_VEHICLES := 8192
const COLLISION_LAYER_NATURE_RESOURCE := 16384
const COLLISION_LAYER_WILD_ANIMAL := 32768
const COLLISION_LAYER_WATER := 65536
const VEHICLE_DYNAMIC_BLOCKING_MASK := COLLISION_LAYER_CHARACTER | COLLISION_LAYER_WILD_ANIMAL
const VEHICLE_HARD_BLOCKING_MASK := (
	COLLISION_LAYER_WALL
	| COLLISION_LAYER_TOOL
	| COLLISION_LAYER_BUILDING
	| COLLISION_LAYER_VEHICLES
	| COLLISION_LAYER_NATURE_RESOURCE
)
const VEHICLE_BLOCKING_MASK := VEHICLE_HARD_BLOCKING_MASK | VEHICLE_DYNAMIC_BLOCKING_MASK
const DEFAULT_VEHICLE_SEARCH_RADIUS := 12.0
const DEFAULT_VEHICLE_SEARCH_STEP := 1.0
const DEFAULT_VEHICLE_MAX_CANDIDATES := 512
const DEFAULT_AIRDROP_MIN_HEIGHT := 3.0
const DEFAULT_AIRDROP_MAX_HEIGHT := 8.0
const DEFAULT_AIRDROP_EXTRA_HEIGHT := 1.0
const DEFAULT_AIRDROP_TIMEOUT := 3.0

static var _vehicle_profile_cache: Dictionary = {}


## Returns the placement-only box authored on a map building/facility.  The
## transform is relative to the scene root and can be passed directly to the
## shared placement resolvers.  Legacy scenes intentionally return an empty
## result so they retain their existing collision-shape behavior.
static func placement_footprint_for_node(node: Node) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return {}
	var footprint_root := node.get_node_or_null(NodePath(PLACEMENT_FOOTPRINT_NODE_NAME)) as Node3D
	if footprint_root == null:
		return {}
	var collision_shape := footprint_root.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or not collision_shape.shape is BoxShape3D:
		return {}
	return {
		"shape": collision_shape.shape,
		"transform": footprint_root.transform * collision_shape.transform,
		"clearance": PLACEMENT_FOOTPRINT_CLEARANCE,
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


static func resolve_surface_placement(
	world: World3D,
	surface_position: Vector3,
	player_position: Vector3,
	placement_yaw: float,
	collision_shape: Shape3D,
	collision_transform: Transform3D,
	blocking_mask: int,
	exceptions: Array = [],
	surface_normal: Vector3 = Vector3.UP,
	max_slope_degrees: float = DEFAULT_MAX_SLOPE_DEGREES,
	clearance: float = DEFAULT_CLEARANCE
) -> Dictionary:
	## Place a small facility on the surface hit by the player's placement ray.
	## Unlike resolve_free_placement(), this intentionally does not recast down
	## to the terrain. It is used by tabletop facilities such as the laptop,
	## whose support surface can be several metres above the ground.
	if world == null or collision_shape == null:
		return {"ok": false, "reason": "placement_query_unavailable"}

	var normal := surface_normal.normalized()
	if normal.length_squared() <= 0.001:
		normal = Vector3.UP
	var slope_degrees := rad_to_deg(acos(clampf(normal.dot(Vector3.UP), -1.0, 1.0)))
	if slope_degrees > max_slope_degrees:
		return {
			"ok": false,
			"reason": "placement_too_steep",
			"surface_position": surface_position,
			"surface_normal": normal,
			"slope_degrees": slope_degrees,
		}

	var support_offset := support_offset_for_shape(collision_shape, collision_transform)
	var placement_position := surface_position + Vector3.UP * support_offset
	var clearance_shape := make_clearance_shape(collision_shape, clearance)
	if clearance_shape == null:
		return {
			"ok": false,
			"reason": "placement_unsupported_collision_shape",
			"surface_position": surface_position,
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
	var collisions := world.direct_space_state.intersect_shape(shape_query, 32)
	return {
		"ok": collisions.is_empty(),
		"reason": "" if collisions.is_empty() else "placement_blocked",
		"position": placement_position,
		"surface_position": surface_position,
		"surface_normal": normal,
		"slope_degrees": slope_degrees,
		"support_offset": support_offset,
		"collisions": collisions,
	}


## Returns the tabletop support owning a physics collider, if that collider is
## part of a furniture scene that explicitly exposes a tabletop surface.
static func tabletop_support_for_collider(collider: Variant) -> Node3D:
	var current: Node = collider as Node if collider is Node else null
	while current != null:
		if current is Node3D and current.is_in_group("tabletop_supports"):
			return current as Node3D
		current = current.get_parent()
	return null


static func tabletop_surface_position(support: Node3D, hit_position: Vector3) -> Vector3:
	if support == null or not is_instance_valid(support):
		return hit_position
	var local_center_value: Variant = support.get_meta("tabletop_support_local_center", Vector3.ZERO)
	var local_center := local_center_value as Vector3 if local_center_value is Vector3 else Vector3.ZERO
	var local_hit := support.to_local(hit_position)
	local_hit.y = local_center.y
	return support.to_global(local_hit)


## Ensures the full horizontal BoxShape3D footprint remains strictly inside the
## configured tabletop rectangle. The same check is used by preview and server.
static func validate_tabletop_footprint(
	support: Node3D,
	root_position: Vector3,
	placement_yaw: float,
	collision_shape: Shape3D,
	collision_transform: Transform3D
) -> Dictionary:
	if support == null or not is_instance_valid(support):
		return {"ok": true}
	if not collision_shape is BoxShape3D:
		return {"ok": false, "reason": "placement_unsupported_tabletop_shape"}
	var size_value: Variant = support.get_meta("tabletop_support_size", Vector2.ZERO)
	var support_size := size_value as Vector2 if size_value is Vector2 else Vector2.ZERO
	if support_size.x <= 0.0 or support_size.y <= 0.0:
		return {"ok": false, "reason": "placement_invalid_tabletop"}
	var center_value: Variant = support.get_meta("tabletop_support_local_center", Vector3.ZERO)
	var center := center_value as Vector3 if center_value is Vector3 else Vector3.ZERO
	var half := (collision_shape as BoxShape3D).size * 0.5
	var rotation := Basis(Vector3.UP, placement_yaw)
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			var corner := root_position + rotation * (
				collision_transform.origin + collision_transform.basis * Vector3(half.x * x_sign, 0.0, half.z * z_sign)
			)
			var local_corner := support.to_local(corner)
			if absf(local_corner.x - center.x) > support_size.x * 0.5 + 0.001 \
					or absf(local_corner.z - center.z) > support_size.y * 0.5 + 0.001:
				return {"ok": false, "reason": "placement_exceeds_tabletop"}
	return {"ok": true}


static func resolve_tabletop_surface_placement(
	world: World3D,
	support: Node3D,
	hit_position: Vector3,
	player_position: Vector3,
	placement_yaw: float,
	collision_shape: Shape3D,
	collision_transform: Transform3D,
	blocking_mask: int,
	exceptions: Array = [],
	surface_normal: Vector3 = Vector3.UP,
	max_slope_degrees: float = DEFAULT_MAX_SLOPE_DEGREES,
	clearance: float = DEFAULT_CLEARANCE
) -> Dictionary:
	var surface_position := tabletop_surface_position(support, hit_position)
	var result := resolve_surface_placement(
		world, surface_position, player_position, placement_yaw, collision_shape,
		collision_transform, blocking_mask, exceptions, surface_normal,
		max_slope_degrees, clearance
	)
	if not bool(result.get("ok", false)):
		return result
	var footprint := validate_tabletop_footprint(
		support,
		result.get("position", surface_position) as Vector3,
		placement_yaw,
		collision_shape,
		collision_transform
	)
	if not bool(footprint.get("ok", false)):
		result["ok"] = false
		result["reason"] = str(footprint.get("reason", "placement_exceeds_tabletop"))
	return result


## Resolve a safe spawn transform for any registered VehicleBase scene.  This
## function is intentionally side-effect free: it only reads the scene to
## build a cached collision profile and queries the supplied physics world.
## The authority remains responsible for instantiating the vehicle.
static func resolve_vehicle_spawn(
	world: World3D,
	target: Variant,
	vehicle_type: String,
	options: Dictionary = {}
) -> Dictionary:
	var failure := {
		"ok": false,
		"position": Vector3.ZERO,
		"yaw": 0.0,
		"spawn_mode": "",
		"drop_start_position": Vector3.ZERO,
		"vehicle_id": "",
		"scene_path": "",
		"used_dynamic_fallback": false,
		"dynamic_blockers": [],
		"hard_blockers": [],
		"candidate_count": 0,
		"reason": "",
	}
	if world == null:
		failure["reason"] = "placement_query_unavailable"
		return failure

	var target_result := _resolve_vehicle_target(target, options)
	if not bool(target_result.get("ok", false)):
		failure["reason"] = str(target_result.get("reason", "invalid_target"))
		return failure
	var requested_position: Vector3 = target_result["position"]
	var placement_yaw := float(target_result.get("yaw", 0.0))

	var team := str(options.get("team", ""))
	var vehicle_resolution := VehicleSpawnCatalogScript.resolve_scene_path(vehicle_type, team)
	if not bool(vehicle_resolution.get("ok", false)):
		failure["vehicle_id"] = str(vehicle_resolution.get("vehicle_id", vehicle_type))
		failure["reason"] = "invalid_vehicle_type"
		return failure
	var vehicle_id := str(vehicle_resolution.get("vehicle_id", vehicle_type))
	var scene_path := str(vehicle_resolution.get("scene_path", ""))
	failure["vehicle_id"] = vehicle_id
	failure["scene_path"] = scene_path

	var profile := _get_vehicle_profile(scene_path)
	if not bool(profile.get("ok", false)):
		failure["reason"] = str(profile.get("reason", "invalid_vehicle_profile"))
		return failure

	var max_search_radius := maxf(
		0.0,
		float(options.get("max_search_radius", options.get("search_radius", DEFAULT_VEHICLE_SEARCH_RADIUS)))
	)
	var search_step := maxf(
		0.1,
		float(options.get("search_step", options.get("step", DEFAULT_VEHICLE_SEARCH_STEP)))
	)
	var max_candidates := maxi(
		1,
		int(options.get("max_candidates", DEFAULT_VEHICLE_MAX_CANDIDATES))
	)
	var max_slope_degrees := maxf(
		0.0,
		float(options.get("max_slope_degrees", DEFAULT_MAX_SLOPE_DEGREES))
	)
	var clearance := maxf(
		0.0,
		float(options.get("clearance", options.get("safety_clearance", DEFAULT_CLEARANCE)))
	)
	var exception_value: Variant = options.get(
		"exclude_rids",
		options.get("exclude_rid", [])
	)
	var exceptions := _normalize_placement_exceptions(exception_value)
	var clearance_shape := BoxShape3D.new()
	clearance_shape.size = (profile["size"] as Vector3) + Vector3.ONE * clearance * 2.0

	# Preserve the requested point whenever the only thing occupying it is a
	# moving character or animal.  The earlier search-first implementation
	# usually found a nearby empty cell during its strict pass, so a player
	# aiming directly at an AI almost never observed the intended delivery
	# drop.  Evaluate the exact target before searching outward: hard geometry,
	# water and slopes still reject it, while a dynamic-only overlap becomes an
	# air-drop candidate with the same vertical hard-obstacle check.
	var exact_target_result := _evaluate_vehicle_candidate(
		world,
		requested_position,
		placement_yaw,
		profile,
		clearance_shape,
		exceptions,
		max_slope_degrees,
		clearance,
		false,
		false
	)
	if bool(exact_target_result.get("ok", false)):
		exact_target_result["candidate_count"] = 1
		return _vehicle_spawn_result(
			exact_target_result,
			requested_position,
			placement_yaw,
			vehicle_id,
			scene_path,
			"ground",
			false
		)
	var target_hard_blockers: Array = exact_target_result.get("hard_blockers", []) as Array
	var target_dynamic_blockers: Array = exact_target_result.get("dynamic_blockers", []) as Array
	if str(exact_target_result.get("reason", "")) == "placement_blocked" \
			and target_hard_blockers.is_empty() and not target_dynamic_blockers.is_empty():
		var target_airdrop_result := _evaluate_vehicle_candidate(
			world,
			requested_position,
			placement_yaw,
			profile,
			clearance_shape,
			exceptions,
			max_slope_degrees,
			clearance,
			true,
			true
		)
		if bool(target_airdrop_result.get("ok", false)):
			target_airdrop_result["candidate_count"] = 2
			return _vehicle_spawn_result(
				target_airdrop_result,
				requested_position,
				placement_yaw,
				vehicle_id,
				scene_path,
				"airdrop",
				true
			)

	var strict_result := _search_vehicle_candidates(
		world,
		requested_position,
		placement_yaw,
		profile,
		clearance_shape,
		exceptions,
		max_search_radius,
		search_step,
		max_candidates,
		max_slope_degrees,
		clearance,
		false,
		false
	)
	failure["candidate_count"] = int(strict_result.get("candidate_count", 0))
	if bool(strict_result.get("ok", false)):
		return _vehicle_spawn_result(
			strict_result,
			requested_position,
		placement_yaw,
		vehicle_id,
		scene_path,
		"ground",
		false
		)

	# Dynamic actors are the only blockers allowed by the requested fallback.
	# The fallback still checks the complete collision result and rejects any
	# hard blocker.  Its selected point is delivered as an air-drop so the
	# vehicle never starts inside a moving actor at ground level.
	var fallback_result := _search_vehicle_candidates(
		world,
		requested_position,
		placement_yaw,
		profile,
		clearance_shape,
		exceptions,
		max_search_radius,
		search_step,
		max_candidates,
		max_slope_degrees,
		clearance,
		true,
		true
	)
	failure["candidate_count"] = int(failure["candidate_count"]) \
		+ int(fallback_result.get("candidate_count", 0))
	if bool(fallback_result.get("ok", false)):
		return _vehicle_spawn_result(
			fallback_result,
			requested_position,
		placement_yaw,
		vehicle_id,
		scene_path,
		"airdrop",
		true
		)
	failure["dynamic_blockers"] = fallback_result.get("dynamic_blockers", [])
	failure["hard_blockers"] = fallback_result.get("hard_blockers", [])
	failure["reason"] = "no_vehicle_spawn_point"
	failure["last_reason"] = str(fallback_result.get("last_reason", ""))
	return failure


static func clear_vehicle_profile_cache() -> void:
	_vehicle_profile_cache.clear()


static func _resolve_vehicle_target(target: Variant, options: Dictionary) -> Dictionary:
	var position := Vector3.ZERO
	var yaw := 0.0
	if target is Vector3:
		position = target as Vector3
	elif target is Node3D:
		var target_node := target as Node3D
		if not is_instance_valid(target_node):
			return {"ok": false, "reason": "invalid_target"}
		position = target_node.global_position
		yaw = target_node.global_rotation.y
	else:
		return {"ok": false, "reason": "invalid_target"}
	var yaw_value: Variant = options.get("yaw", null)
	if typeof(yaw_value) == TYPE_FLOAT or typeof(yaw_value) == TYPE_INT:
		yaw = float(yaw_value)
	return {"ok": true, "position": position, "yaw": yaw}


static func _normalize_placement_exceptions(value: Variant) -> Array:
	var exceptions: Array = []
	if value is RID:
		if (value as RID).is_valid():
			exceptions.append(value as RID)
		return exceptions
	if not value is Array:
		return exceptions
	for exception_value: Variant in value as Array:
		if exception_value is RID and (exception_value as RID).is_valid():
			exceptions.append(exception_value as RID)
	return exceptions


static func _get_vehicle_profile(scene_path: String) -> Dictionary:
	if _vehicle_profile_cache.has(scene_path):
		return _vehicle_profile_cache[scene_path]
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return {"ok": false, "reason": "placement_missing_scene"}
	var source := packed.instantiate() as Node3D
	if source == null:
		return {"ok": false, "reason": "placement_bad_scene"}
	if not source is VehicleBase:
		source.free()
		return {"ok": false, "reason": "placement_not_vehicle"}

	var minimum := Vector3(1.0e20, 1.0e20, 1.0e20)
	var maximum := Vector3(-1.0e20, -1.0e20, -1.0e20)
	var has_bounds := false
	var config_value: Variant = source.get("vehicle_config")
	if config_value is Resource:
		var config := config_value as Resource
		var config_size := _resource_vector3_property(config, "collision_size", Vector3.ZERO)
		var config_offset := _resource_vector3_property(config, "collision_offset", Vector3.ZERO)
		if config_size.length_squared() > 0.001:
			minimum = minimum.min(config_offset - config_size * 0.5)
			maximum = maximum.max(config_offset + config_size * 0.5)
			has_bounds = true

	# Include all body collision shapes below the vehicle root, while skipping
	# damage Areas and nested CollisionObject3D accessories.  This keeps the
	# profile correct for vehicles with several body shapes (CombineCar and
	# FarmBaseVehicle) without letting a workbench, machine gun or Hit3D make
	# the delivery footprint larger than the vehicle itself.
	var body_bounds := _collect_vehicle_collision_bounds(source, Transform3D.IDENTITY, source)
	if bool(body_bounds.get("has_bounds", false)):
		minimum = minimum.min(body_bounds.get("min", minimum) as Vector3)
		maximum = maximum.max(body_bounds.get("max", maximum) as Vector3)
		has_bounds = true
	source.free()
	if not has_bounds or minimum.x >= maximum.x or minimum.y >= maximum.y \
			or minimum.z >= maximum.z:
		return {"ok": false, "reason": "placement_missing_vehicle_collision"}
	var profile := {
		"ok": true,
		"min": minimum,
		"max": maximum,
		"size": maximum - minimum,
		"center": (minimum + maximum) * 0.5,
		"height": maximum.y - minimum.y,
	}
	_vehicle_profile_cache[scene_path] = profile
	return profile


static func _collect_vehicle_collision_bounds(
	node: Node,
	parent_transform: Transform3D,
	vehicle_root: Node
) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return {"has_bounds": false}
	# Areas are used for damage, hit confirmation and interaction, not the
	# physical placement footprint.  A nested body is likewise an accessory
	# (for example KitchenCar's induction counter), not the vehicle chassis.
	if node != vehicle_root and (node is Area3D or node is CollisionObject3D):
		return {"has_bounds": false}
	var node_transform := parent_transform
	if node is Node3D and node != vehicle_root:
		node_transform = parent_transform * (node as Node3D).transform
	var minimum := Vector3(1.0e20, 1.0e20, 1.0e20)
	var maximum := Vector3(-1.0e20, -1.0e20, -1.0e20)
	var has_bounds := false
	if node is CollisionShape3D:
		var collision_shape := node as CollisionShape3D
		if not collision_shape.disabled and collision_shape.shape != null:
			for point: Vector3 in _shape_bounds_points(collision_shape.shape):
				var local_point := node_transform * point
				minimum = minimum.min(local_point)
				maximum = maximum.max(local_point)
				has_bounds = true
	elif node is CollisionPolygon3D:
		var collision_polygon := node as CollisionPolygon3D
		if not collision_polygon.disabled and not collision_polygon.polygon.is_empty() \
				and collision_polygon.depth > 0.0:
			var half_depth := collision_polygon.depth * 0.5
			for point_2d: Vector2 in collision_polygon.polygon:
				for local_z in [-half_depth, half_depth]:
					var local_point := node_transform * Vector3(
						point_2d.x,
						point_2d.y,
						local_z
					)
					minimum = minimum.min(local_point)
					maximum = maximum.max(local_point)
					has_bounds = true
	for child: Node in node.get_children():
		var child_bounds := _collect_vehicle_collision_bounds(child, node_transform, vehicle_root)
		if not bool(child_bounds.get("has_bounds", false)):
			continue
		minimum = minimum.min(child_bounds.get("min", minimum) as Vector3)
		maximum = maximum.max(child_bounds.get("max", maximum) as Vector3)
		has_bounds = true
	return {"has_bounds": has_bounds, "min": minimum, "max": maximum}


static func _resource_vector3_property(resource: Resource, property_name: String, fallback: Vector3) -> Vector3:
	if resource == null:
		return fallback
	for property_info: Dictionary in resource.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			var value: Variant = resource.get(property_name)
			return value as Vector3 if value is Vector3 else fallback
	return fallback


static func _shape_bounds_points(shape: Shape3D) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if shape is BoxShape3D:
		var half_size := (shape as BoxShape3D).size * 0.5
		for x in [-half_size.x, half_size.x]:
			for y in [-half_size.y, half_size.y]:
				for z in [-half_size.z, half_size.z]:
					points.append(Vector3(x, y, z))
	elif shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius
		for x in [-radius, radius]:
			for y in [-radius, radius]:
				for z in [-radius, radius]:
					points.append(Vector3(x, y, z))
	elif shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var radius := capsule.radius
		var half_height := capsule.height * 0.5
		for x in [-radius, radius]:
			for y in [-half_height, half_height]:
				for z in [-radius, radius]:
					points.append(Vector3(x, y, z))
	elif shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		var half_height := cylinder.height * 0.5
		for x in [-cylinder.radius, cylinder.radius]:
			for y in [-half_height, half_height]:
				for z in [-cylinder.radius, cylinder.radius]:
					points.append(Vector3(x, y, z))
	elif shape is ConvexPolygonShape3D:
		for point: Vector3 in (shape as ConvexPolygonShape3D).points:
			points.append(point)
	elif shape is ConcavePolygonShape3D:
		for point: Vector3 in (shape as ConcavePolygonShape3D).get_faces():
			points.append(point)
	return points


static func _search_vehicle_candidates(
	world: World3D,
	requested_position: Vector3,
	placement_yaw: float,
	profile: Dictionary,
	clearance_shape: BoxShape3D,
	exceptions: Array,
	max_search_radius: float,
	search_step: float,
	max_candidates: int,
	max_slope_degrees: float,
	clearance: float,
	ignore_dynamic: bool,
	require_airdrop_path: bool
) -> Dictionary:
	var offsets: Array[Dictionary] = []
	var ring_count := ceili(max_search_radius / search_step)
	for x in range(-ring_count, ring_count + 1):
		for z in range(-ring_count, ring_count + 1):
			var offset := Vector2(float(x) * search_step, float(z) * search_step)
			if offset.length() > max_search_radius + 0.001:
				continue
			offsets.append({
				"offset": offset,
				"distance": offset.length_squared(),
				"angle": atan2(offset.y, offset.x),
			})
	offsets.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_distance := float(first.get("distance", 0.0))
		var second_distance := float(second.get("distance", 0.0))
		if not is_equal_approx(first_distance, second_distance):
			return first_distance < second_distance
		var first_angle := float(first.get("angle", 0.0))
		var second_angle := float(second.get("angle", 0.0))
		if not is_equal_approx(first_angle, second_angle):
			return first_angle < second_angle
		var first_offset := first.get("offset", Vector2.ZERO) as Vector2
		var second_offset := second.get("offset", Vector2.ZERO) as Vector2
		return first_offset.x < second_offset.x if not is_equal_approx(first_offset.x, second_offset.x) else first_offset.y < second_offset.y
	)

	var candidate_count := 0
	var last_reason := "no_vehicle_spawn_point"
	var last_hard_blockers: Array = []
	var last_dynamic_blockers: Array = []
	for offset_value: Dictionary in offsets:
		if candidate_count >= max_candidates:
			break
		var offset := offset_value.get("offset", Vector2.ZERO) as Vector2
		var candidate_position := requested_position + Vector3(offset.x, 0.0, offset.y)
		candidate_count += 1
		var evaluated := _evaluate_vehicle_candidate(
			world,
			candidate_position,
			placement_yaw,
			profile,
			clearance_shape,
			exceptions,
			max_slope_degrees,
			clearance,
			ignore_dynamic,
			require_airdrop_path
		)
		last_reason = str(evaluated.get("reason", last_reason))
		var evaluated_hard_blockers: Variant = evaluated.get("hard_blockers", [])
		if evaluated_hard_blockers is Array and not (evaluated_hard_blockers as Array).is_empty():
			last_hard_blockers = (evaluated_hard_blockers as Array).duplicate()
		var evaluated_dynamic_blockers: Variant = evaluated.get("dynamic_blockers", [])
		if evaluated_dynamic_blockers is Array and not (evaluated_dynamic_blockers as Array).is_empty():
			last_dynamic_blockers = (evaluated_dynamic_blockers as Array).duplicate()
		if bool(evaluated.get("ok", false)):
			evaluated["candidate_count"] = candidate_count
			return evaluated
	return {
		"ok": false,
		"candidate_count": candidate_count,
		"last_reason": last_reason,
		"reason": last_reason,
		"hard_blockers": last_hard_blockers,
		"dynamic_blockers": last_dynamic_blockers,
	}


static func _evaluate_vehicle_candidate(
	world: World3D,
	requested_position: Vector3,
	placement_yaw: float,
	profile: Dictionary,
	clearance_shape: BoxShape3D,
	exceptions: Array,
	max_slope_degrees: float,
	clearance: float,
	ignore_dynamic: bool,
	require_airdrop_path: bool
) -> Dictionary:
	var basis := Basis(Vector3.UP, placement_yaw)
	var minimum: Vector3 = profile.get("min", Vector3.ZERO)
	var maximum: Vector3 = profile.get("max", Vector3.ZERO)
	var profile_center: Vector3 = profile.get("center", Vector3.ZERO)
	var profile_height := float(profile.get("height", 0.0))
	var sample_offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(minimum.x, minimum.z),
		Vector2(minimum.x, maximum.z),
		Vector2(maximum.x, minimum.z),
		Vector2(maximum.x, maximum.z),
		Vector2((minimum.x + maximum.x) * 0.5, minimum.z),
		Vector2((minimum.x + maximum.x) * 0.5, maximum.z),
		Vector2(minimum.x, (minimum.z + maximum.z) * 0.5),
		Vector2(maximum.x, (minimum.z + maximum.z) * 0.5),
	]
	var center_ground := Vector3.ZERO
	var center_found := false
	var representative_normal := Vector3.UP
	var highest_slope := 0.0
	var ground_y_reference := requested_position.y
	var direct_space_state := world.direct_space_state
	for local_offset: Vector2 in sample_offsets:
		var sample_xz := requested_position + basis * Vector3(local_offset.x, 0.0, local_offset.y)
		var ray_start := Vector3(sample_xz.x, ground_y_reference + DEFAULT_GROUND_RAY_ABOVE, sample_xz.z)
		var ray_end := Vector3(sample_xz.x, ground_y_reference - DEFAULT_GROUND_RAY_BELOW, sample_xz.z)
		var ground_query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		ground_query.collision_mask = COLLISION_LAYER_GROUND
		ground_query.collide_with_bodies = true
		ground_query.collide_with_areas = true
		ground_query.exclude = exceptions
		var ground_hit := direct_space_state.intersect_ray(ground_query)
		if ground_hit.is_empty() or not (ground_hit.get("position", null) is Vector3):
			return {"ok": false, "reason": "placement_no_ground"}
		var ground_position := ground_hit["position"] as Vector3
		if local_offset == Vector2.ZERO:
			center_ground = ground_position
			center_found = true
		var normal_value: Variant = ground_hit.get("normal", Vector3.UP)
		var normal := normal_value as Vector3 if normal_value is Vector3 else Vector3.UP
		normal = normal.normalized()
		var slope := rad_to_deg(acos(clampf(normal.dot(Vector3.UP), -1.0, 1.0)))
		highest_slope = maxf(highest_slope, slope)
		if local_offset == Vector2.ZERO:
			representative_normal = normal
		if WaterBody3D.is_surface_blocked(ground_position):
			return {"ok": false, "reason": "placement_in_water"}
	if not center_found:
		return {"ok": false, "reason": "placement_no_ground"}
	if highest_slope > max_slope_degrees:
		return {
			"ok": false,
			"reason": "placement_too_steep",
			"slope_degrees": highest_slope,
		}

	var placement_position := Vector3(
		requested_position.x,
		center_ground.y - minimum.y,
		requested_position.z
	)
	var shape_center := placement_position + basis * profile_center
	var shape_transform := Transform3D(basis, shape_center)
	var water_query := PhysicsShapeQueryParameters3D.new()
	water_query.shape = clearance_shape
	water_query.transform = shape_transform
	water_query.collision_mask = COLLISION_LAYER_WATER
	water_query.collide_with_bodies = true
	water_query.collide_with_areas = true
	water_query.exclude = exceptions
	var water_collisions := direct_space_state.intersect_shape(water_query, 8)
	if not water_collisions.is_empty():
		return {"ok": false, "reason": "placement_in_water"}

	var blockers := _vehicle_intersections(
		world,
		clearance_shape,
		shape_transform,
		exceptions
	)
	var hard_blockers: Array = blockers.get("hard", [])
	var dynamic_blockers: Array = blockers.get("dynamic", [])
	if not hard_blockers.is_empty() or (not ignore_dynamic and not dynamic_blockers.is_empty()):
		return {
			"ok": false,
			"reason": "placement_blocked",
			"hard_blockers": hard_blockers,
			"dynamic_blockers": dynamic_blockers,
		}
	if require_airdrop_path and not _vehicle_airdrop_path_is_clear(
		world,
		clearance_shape,
		placement_position,
		shape_center - placement_position,
		profile_height,
		basis,
		exceptions
	):
		return {"ok": false, "reason": "placement_airdrop_path_blocked"}
	return {
		"ok": true,
		"reason": "",
		"position": placement_position,
		"ground_position": center_ground,
		"ground_normal": representative_normal,
		"slope_degrees": highest_slope,
		"support_offset": -minimum.y,
		"hard_blockers": hard_blockers,
		"dynamic_blockers": dynamic_blockers,
		"drop_height": clampf(
			profile_height + DEFAULT_AIRDROP_EXTRA_HEIGHT,
			DEFAULT_AIRDROP_MIN_HEIGHT,
			DEFAULT_AIRDROP_MAX_HEIGHT
		),
	}


static func _vehicle_intersections(
	world: World3D,
	shape: Shape3D,
	shape_transform: Transform3D,
	exceptions: Array
) -> Dictionary:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = shape_transform
	query.collision_mask = VEHICLE_BLOCKING_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = exceptions
	var collisions := world.direct_space_state.intersect_shape(query, 64)
	var hard: Array[String] = []
	var dynamic: Array[String] = []
	for collision_value: Variant in collisions:
		if not collision_value is Dictionary:
			continue
		var collision := collision_value as Dictionary
		var collider: Variant = collision.get("collider", null)
		var layer := _collision_layer_for(collider)
		var has_dynamic := layer > 0 and (layer & VEHICLE_DYNAMIC_BLOCKING_MASK) != 0
		var has_hard := layer <= 0 or (layer & VEHICLE_HARD_BLOCKING_MASK) != 0
		var label := _vehicle_collider_label(collider, layer)
		if has_dynamic:
			dynamic.append(label)
		if has_hard:
			hard.append(label)
	return {"collisions": collisions, "hard": hard, "dynamic": dynamic}


static func _collision_layer_for(collider: Variant) -> int:
	if collider is CollisionObject3D:
		return int((collider as CollisionObject3D).collision_layer)
	return 0


static func _vehicle_collider_label(collider: Variant, layer: int) -> String:
	if collider is CollisionObject3D:
		var object := collider as CollisionObject3D
		return "%s<%s> layer=%d" % [object.get_path(), object.get_class(), layer]
	return str(collider)


static func _vehicle_airdrop_path_is_clear(
	world: World3D,
	clearance_shape: Shape3D,
	landing_position: Vector3,
	shape_center_offset: Vector3,
	vehicle_height: float,
	placement_basis: Basis,
	exceptions: Array
) -> bool:
	var drop_height := clampf(
		vehicle_height + DEFAULT_AIRDROP_EXTRA_HEIGHT,
		DEFAULT_AIRDROP_MIN_HEIGHT,
		DEFAULT_AIRDROP_MAX_HEIGHT
	)
	var step_count := maxi(2, ceili(drop_height / 0.75))
	for index in range(1, step_count + 1):
		var fraction := float(index) / float(step_count)
		var sample_root := landing_position + Vector3.UP * drop_height * fraction
		var sample_center := sample_root + placement_basis * shape_center_offset
		var blockers := _vehicle_intersections(
			world,
			clearance_shape,
			Transform3D(placement_basis, sample_center),
			exceptions
		)
		if not (blockers.get("hard", []) as Array).is_empty():
			return false
	return true


static func _vehicle_spawn_result(
	evaluated: Dictionary,
	requested_position: Vector3,
	placement_yaw: float,
	vehicle_id: String,
	scene_path: String,
	spawn_mode: String,
	used_dynamic_fallback: bool
) -> Dictionary:
	var position := evaluated.get("position", requested_position) as Vector3
	var drop_height := float(evaluated.get("drop_height", 0.0))
	var result := {
		"ok": true,
		"position": position,
		"drop_landing_position": position,
		"yaw": placement_yaw,
		"spawn_mode": spawn_mode,
		"drop_start_position": position + Vector3.UP * drop_height if spawn_mode == "airdrop" else position,
		"vehicle_id": vehicle_id,
		"scene_path": scene_path,
		"used_dynamic_fallback": used_dynamic_fallback,
		"dynamic_blockers": evaluated.get("dynamic_blockers", []),
		"hard_blockers": evaluated.get("hard_blockers", []),
		"candidate_count": int(evaluated.get("candidate_count", 0)),
		"ground_position": evaluated.get("ground_position", position),
		"ground_normal": evaluated.get("ground_normal", Vector3.UP),
		"slope_degrees": float(evaluated.get("slope_degrees", 0.0)),
		"drop_height": drop_height,
		"drop_timeout": DEFAULT_AIRDROP_TIMEOUT,
		"reason": "",
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
