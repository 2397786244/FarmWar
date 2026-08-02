class_name WaterBody3D
extends Node3D

## Runtime water surface used by generated maps.
##
## The node itself stays at world Y=0.  `polygon_points` contains the X/Z
## outline in world metres and `water_level` is the absolute surface height.
## The surface is visual-only; the Area3D volume uses the dedicated water
## collision layer so players and vehicles can enter it without being blocked.

const CALM_WATER_SHADER_PATH := "res://src/calm_water.gdshader"
const DEFAULT_WATER_COLLISION_LAYER := 65536
const DEFAULT_WATER_COLLISION_MASK := 8 | 8192
const DEFAULT_WATER_LEVEL := 0.5
const DEFAULT_WATER_DEPTH := 2.0

enum BodyType {
	LAKE,
	RIVER,
}

@export var body_type: BodyType = BodyType.LAKE
@export var polygon_points: PackedVector2Array = PackedVector2Array()
@export var centerline_points: PackedVector2Array = PackedVector2Array()
@export_range(0.5, 100.0, 0.1) var river_width: float = 6.0
@export var water_level: float = DEFAULT_WATER_LEVEL
@export_range(0.1, 100.0, 0.1) var water_depth: float = DEFAULT_WATER_DEPTH
@export_range(0.0, 3.0, 0.01) var surface_offset: float = 0.01
@export_range(0.0, 1.0, 0.01) var water_alpha: float = 0.82
@export var shallow_color: Color = Color(0.12, 0.62, 0.72, 1.0)
@export var deep_color: Color = Color(0.025, 0.22, 0.34, 1.0)
@export var water_collision_layer: int = DEFAULT_WATER_COLLISION_LAYER
@export var water_collision_mask: int = DEFAULT_WATER_COLLISION_MASK
@export var detection_height: float = 0.6

var _surface: MeshInstance3D
var _area: Area3D
var _volume_shape: CollisionShape3D
var _navigation_obstacle: NavigationObstacle3D

signal body_entered_water(body: Node3D)
signal body_exited_water(body: Node3D)


func _ready() -> void:
	add_to_group("water_bodies")
	_ensure_nodes()
	rebuild_water_body()


func rebuild_water_body() -> void:
	_ensure_nodes()
	_rebuild_surface_mesh()
	_rebuild_water_volume()


func set_polygon_points(points: PackedVector2Array) -> void:
	polygon_points = points
	if is_inside_tree():
		rebuild_water_body()


func get_polygon_points() -> PackedVector2Array:
	return _effective_polygon()


func contains_world_point(world_position: Vector3) -> bool:
	var effective_polygon := _effective_polygon()
	if effective_polygon.size() < 3:
		return false
	if world_position.y > water_level + detection_height:
		return false
	if world_position.y < water_level - water_depth:
		return false
	return Geometry2D.is_point_in_polygon(
		Vector2(world_position.x, world_position.z),
		effective_polygon
	)


## Surface/placement test. Unlike navigation, this deliberately does not stop
## at `water_depth`'s lower bound: a tree below the configured seabed is still
## underwater and must not be placed there.
func contains_surface_point(world_position: Vector3) -> bool:
	var effective_polygon := _effective_polygon()
	if effective_polygon.size() < 3:
		return false
	if world_position.y > water_level + detection_height:
		return false
	return Geometry2D.is_point_in_polygon(
		Vector2(world_position.x, world_position.z),
		effective_polygon
	)


func contains_horizontal_point(world_position: Vector3) -> bool:
	var effective_polygon := _effective_polygon()
	return effective_polygon.size() >= 3 and Geometry2D.is_point_in_polygon(
		Vector2(world_position.x, world_position.z),
		effective_polygon
	)


## Shared navigation guard for AI, wildlife and livestock. Players intentionally
## do not call this and can enter water for the future swimming system.
static func is_navigation_blocked(world_position: Vector3) -> bool:
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not main_loop is SceneTree:
		return false
	for value in (main_loop as SceneTree).get_nodes_in_group("water_bodies"):
		var water := value as WaterBody3D
		if water != null and water.contains_world_point(world_position):
			return true
	return false


static func is_surface_blocked(world_position: Vector3) -> bool:
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not main_loop is SceneTree:
		return false
	for value in (main_loop as SceneTree).get_nodes_in_group("water_bodies"):
		var water := value as WaterBody3D
		if water != null and water.contains_surface_point(world_position):
			return true
	return false


static func get_surface_level_at(world_position: Vector3) -> float:
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not main_loop is SceneTree:
		return INF
	var highest_surface := -INF
	for value in (main_loop as SceneTree).get_nodes_in_group("water_bodies"):
		var water := value as WaterBody3D
		if water != null and water.contains_horizontal_point(world_position):
			highest_surface = maxf(highest_surface, water.water_level)
	return highest_surface


func _effective_polygon() -> PackedVector2Array:
	if body_type != BodyType.RIVER or centerline_points.size() < 2:
		return polygon_points
	var half_width := maxf(0.25, river_width * 0.5)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for index in range(centerline_points.size()):
		var current := centerline_points[index]
		var previous := centerline_points[maxi(0, index - 1)]
		var next := centerline_points[mini(centerline_points.size() - 1, index + 1)]
		var tangent := (next - previous).normalized()
		if tangent.length_squared() <= 0.0001:
			tangent = Vector2.RIGHT
		var normal := Vector2(-tangent.y, tangent.x)
		left.append(current + normal * half_width)
		right.append(current - normal * half_width)
	var result := PackedVector2Array()
	for point in left:
		result.append(point)
	for index in range(right.size() - 1, -1, -1):
		result.append(right[index])
	return result


func _ensure_nodes() -> void:
	_surface = get_node_or_null("WaterSurface") as MeshInstance3D
	if _surface == null:
		_surface = MeshInstance3D.new()
		_surface.name = "WaterSurface"
		_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_surface.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(_surface)
	_set_property_if_present(_surface, "navigation_mode", 0)

	_area = get_node_or_null("WaterVolume") as Area3D
	if _area == null:
		_area = Area3D.new()
		_area.name = "WaterVolume"
		_area.monitoring = true
		_area.monitorable = true
		add_child(_area)
		_area.body_entered.connect(_on_body_entered)
		_area.body_exited.connect(_on_body_exited)
	else:
		if not _area.body_entered.is_connected(_on_body_entered):
			_area.body_entered.connect(_on_body_entered)
		if not _area.body_exited.is_connected(_on_body_exited):
			_area.body_exited.connect(_on_body_exited)

	_volume_shape = _area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _volume_shape == null:
		_volume_shape = CollisionShape3D.new()
		_volume_shape.name = "CollisionShape3D"
		_area.add_child(_volume_shape)

	_navigation_obstacle = get_node_or_null("WaterNavigationObstacle") as NavigationObstacle3D
	if _navigation_obstacle == null:
		_navigation_obstacle = NavigationObstacle3D.new()
		_navigation_obstacle.name = "WaterNavigationObstacle"
		_navigation_obstacle.avoidance_enabled = true
		_navigation_obstacle.affect_navigation_mesh = true
		_navigation_obstacle.carve_navigation_mesh = true
		add_child(_navigation_obstacle)


func _make_water_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := load(CALM_WATER_SHADER_PATH) as Shader
	if shader == null:
		return material
	material.shader = shader
	material.set_shader_parameter("shallow_color", shallow_color)
	material.set_shader_parameter("deep_color", deep_color)
	material.set_shader_parameter("wave_scale", 7.0 if body_type == BodyType.RIVER else 11.0)
	material.set_shader_parameter("secondary_wave_scale", 12.0 if body_type == BodyType.RIVER else 17.0)
	material.set_shader_parameter("ripple_scale", 5.0 if body_type == BodyType.RIVER else 9.0)
	material.set_shader_parameter("ripple_strength", 0.32 if body_type == BodyType.RIVER else 0.16)
	material.set_shader_parameter("normal_strength", 0.65 if body_type == BodyType.RIVER else 0.35)
	material.set_shader_parameter("crest_strength", 0.23 if body_type == BodyType.RIVER else 0.10)
	material.set_shader_parameter("water_alpha", water_alpha)
	material.set_shader_parameter("water_roughness", 0.16 if body_type == BodyType.RIVER else 0.22)
	material.set_shader_parameter("fresnel_strength", 0.7)
	material.set_shader_parameter("depth_factor", clampf(water_depth / 8.0, 0.0, 1.0))
	return material


func _rebuild_surface_mesh() -> void:
	if _surface == null:
		return
	_surface.material_override = _make_water_material()
	var effective_polygon := _effective_polygon()
	if effective_polygon.size() < 3:
		_surface.mesh = null
		return

	var triangulation := Geometry2D.triangulate_polygon(effective_polygon)
	if triangulation.is_empty():
		_surface.mesh = null
		return

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for point in effective_polygon:
		vertices.append(Vector3(point.x, water_level + surface_offset, point.y))
		normals.append(Vector3.UP)
		uvs.append(Vector2(point.x, point.y) * 0.05)

	for index in range(0, triangulation.size(), 3):
		if index + 2 >= triangulation.size():
			break
		var a := int(triangulation[index])
		var b := int(triangulation[index + 1])
		var c := int(triangulation[index + 2])
		# Keep all triangles upward-facing for normal lighting and shadows.
		var cross := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		if cross.y < 0.0:
			var swap := b
			b = c
			c = swap
		indices.append(a)
		indices.append(b)
		indices.append(c)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_surface.mesh = mesh


func _rebuild_water_volume() -> void:
	if _area == null or _volume_shape == null:
		return
	_area.collision_layer = water_collision_layer
	_area.collision_mask = water_collision_mask
	_area.monitoring = true
	var effective_polygon := _effective_polygon()
	if effective_polygon.size() < 3:
		_volume_shape.shape = null
		if _navigation_obstacle != null:
			_navigation_obstacle.vertices = PackedVector3Array()
		return

	var triangles := Geometry2D.triangulate_polygon(effective_polygon)
	if triangles.is_empty():
		_volume_shape.shape = null
		return
	var bottom_y := water_level - maxf(0.1, water_depth)
	var top_y := water_level + maxf(0.05, detection_height)
	var faces := PackedVector3Array()
	for index in range(0, triangles.size(), 3):
		if index + 2 >= triangles.size():
			break
		var a := effective_polygon[int(triangles[index])]
		var b := effective_polygon[int(triangles[index + 1])]
		var c := effective_polygon[int(triangles[index + 2])]
		var top_a := Vector3(a.x, top_y, a.y)
		var top_b := Vector3(b.x, top_y, b.y)
		var top_c := Vector3(c.x, top_y, c.y)
		var bottom_a := Vector3(a.x, bottom_y, a.y)
		var bottom_b := Vector3(b.x, bottom_y, b.y)
		var bottom_c := Vector3(c.x, bottom_y, c.y)
		faces.append(top_a)
		faces.append(top_b)
		faces.append(top_c)
		faces.append(bottom_c)
		faces.append(bottom_b)
		faces.append(bottom_a)
		_append_side_faces(faces, top_a, top_b, bottom_a, bottom_b)
		_append_side_faces(faces, top_b, top_c, bottom_b, bottom_c)
		_append_side_faces(faces, top_c, top_a, bottom_c, bottom_a)
	var shape := ConcavePolygonShape3D.new()
	shape.data = faces
	_volume_shape.shape = shape
	if _navigation_obstacle != null:
		var obstacle_vertices := PackedVector3Array()
		var obstacle_y := water_level - maxf(0.1, water_depth) * 0.5
		for point in effective_polygon:
			obstacle_vertices.append(Vector3(point.x, 0.0, point.y))
		_navigation_obstacle.vertices = obstacle_vertices
		_navigation_obstacle.height = maxf(0.1, water_depth)
		_navigation_obstacle.position = Vector3(0.0, obstacle_y, 0.0)


func _set_property_if_present(target: Object, property_name: String, value: Variant) -> void:
	if target == null:
		return
	for property_info in target.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			target.set(property_name, value)
			return


func _append_side_faces(
	faces: PackedVector3Array,
	top_a: Vector3,
	top_b: Vector3,
	bottom_a: Vector3,
	bottom_b: Vector3,
) -> void:
	faces.append(top_a)
	faces.append(bottom_a)
	faces.append(top_b)
	faces.append(top_b)
	faces.append(bottom_a)
	faces.append(bottom_b)


func _on_body_entered(body: Node3D) -> void:
	body_entered_water.emit(body)
	if body.has_method("set_meta"):
		body.set_meta("farmwar_in_water", true)


func _on_body_exited(body: Node3D) -> void:
	body_exited_water.emit(body)
	if body.has_method("set_meta"):
		body.set_meta("farmwar_in_water", false)
