extends Marker3D
class_name TeamSpawnPoint

## A map-rule node, intentionally independent from any building such as a bus.
@export_enum("red", "blue") var team := "red"
@export var spawn_point_id := ""
@export_range(0.5, 8.0, 0.1) var spawn_radius := 3.0
@export_range(0.5, 5.0, 0.1) var player_height_offset := 1.0
@export_range(0.5, 5.0, 0.1) var minimum_spawn_spacing := 2.2


func _ready() -> void:
	add_to_group("team_spawn_points")
	if spawn_point_id.is_empty():
		spawn_point_id = "%s:%s" % [team, name]


func get_spawn_position(player_index := 0, random_seed := 0) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s:%s" % [random_seed, spawn_point_id, team])
	var accepted: Array[Vector3] = []
	var candidate := Vector3.ZERO
	for _slot in range(player_index + 1):
		candidate = _sample_local_position(rng)
		for _attempt in range(48):
			if _is_separated(candidate, accepted):
				break
			candidate = _sample_local_position(rng)
		accepted.append(candidate)
	return to_global(candidate) + Vector3.UP * player_height_offset


func _sample_local_position(rng: RandomNumberGenerator) -> Vector3:
	var angle := rng.randf_range(0.0, TAU)
	var distance := sqrt(rng.randf()) * spawn_radius
	return Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)


func _is_separated(candidate: Vector3, accepted: Array[Vector3]) -> bool:
	var required_distance_squared := minimum_spawn_spacing * minimum_spawn_spacing
	for point: Vector3 in accepted:
		if candidate.distance_squared_to(point) < required_distance_squared:
			return false
	return true
