@tool
class_name SurfaceArea3D
extends Path3D

enum DrawMode {
	CLOSED_AREA,
	PATH_STROKE,
}

@export_range(0, 255, 1) var surface_id: int = 1
@export var draw_mode: DrawMode = DrawMode.CLOSED_AREA
@export_range(0.1, 100.0, 0.1, "or_greater") var width: float = 6.0
@export_range(0.0, 20.0, 0.1, "or_greater") var edge_softness: float = 1.0
@export var priority: int = 0
@export var area_enabled: bool = true


func get_world_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	if curve == null:
		return points
	var tessellated := curve.tessellate(5, 4.0)
	for point in tessellated:
		var world_point := to_global(point)
		points.append(Vector2(world_point.x, world_point.z))
	return points
