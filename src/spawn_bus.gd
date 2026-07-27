@tool
extends StaticBody3D
class_name SpawnBus

@export_enum("red", "blue") var team := "blue"
@export_range(0.5, 5.0, 0.1) var player_height_offset := 1.0
@export_range(0.5, 5.0, 0.1) var minimum_spawn_spacing := 2.2

@onready var spawn_region: Area3D = get_node_or_null("SpawnRegion") as Area3D
@onready var spawn_region_shape: CollisionShape3D = get_node_or_null(
	"SpawnRegion/CollisionShape3D"
) as CollisionShape3D


func get_spawn_position(player_index := 0, random_seed := 0) -> Vector3:
	var local_bounds := _get_local_spawn_bounds()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s:%s" % [random_seed, team, str(global_position)])
	var accepted_points: Array[Vector3] = []
	var candidate := local_bounds.get_center()
	for _slot in range(player_index + 1):
		candidate = _sample_local_position(rng, local_bounds)
		for _attempt in range(48):
			if _is_separated(candidate, accepted_points):
				break
			candidate = _sample_local_position(rng, local_bounds)
		accepted_points.append(candidate)

	return to_global(candidate) + Vector3.UP * player_height_offset


func _is_separated(candidate: Vector3, accepted_points: Array[Vector3]) -> bool:
	var required_distance_squared := minimum_spawn_spacing * minimum_spawn_spacing
	for accepted in accepted_points:
		if candidate.distance_squared_to(accepted) < required_distance_squared:
			return false
	return true


func get_spawn_region_size() -> Vector2:
	var bounds := _get_local_spawn_bounds()
	return Vector2(bounds.size.x, bounds.size.z)


func _get_local_spawn_bounds() -> AABB:
	if spawn_region == null:
		spawn_region = get_node_or_null("SpawnRegion") as Area3D
	if spawn_region_shape == null:
		spawn_region_shape = get_node_or_null("SpawnRegion/CollisionShape3D") as CollisionShape3D
	var center := Vector3(6.0, 0.1, 0.0)
	var size := Vector3(6.0, 0.2, 10.0)
	if spawn_region != null:
		center = spawn_region.position
	if spawn_region_shape != null and spawn_region_shape.shape is BoxShape3D:
		size = (spawn_region_shape.shape as BoxShape3D).size
		center += spawn_region_shape.position
	return AABB(center - size * 0.5, size)


func _sample_local_position(rng: RandomNumberGenerator, bounds: AABB) -> Vector3:
	return Vector3(
		rng.randf_range(bounds.position.x, bounds.end.x),
		bounds.get_center().y,
		rng.randf_range(bounds.position.z, bounds.end.z)
	)
