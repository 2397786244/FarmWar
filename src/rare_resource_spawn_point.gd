extends Marker3D
class_name RareResourceSpawnPoint

@export var spawn_point_id := ""
@export var allowed_resource_ids: Array[String] = []
var active_resource: Dictionary = {}

func _ready() -> void:
	if spawn_point_id.is_empty():
		spawn_point_id = str(get_path())
	add_to_group("rare_resource_spawn_points")


func assign_resource(resource: Dictionary) -> void:
	active_resource = resource.duplicate(true)


func clear_resource() -> void:
	active_resource.clear()


func has_active_resource() -> bool:
	return not active_resource.is_empty()


func allows_resource(resource_id: String) -> bool:
	return allowed_resource_ids.is_empty() or allowed_resource_ids.has(resource_id)
