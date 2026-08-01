@tool
class_name RoadPath3D
extends Path3D

## Continuous procedural road renderer for FarmWar (rebuild-loop fixed).
##
## Replace the project's existing res://src/terrain/road_path_3d.gd with this
## file. Existing RoadPath3D scenes remain compatible because the original
## road_type, piece_spacing, vertical_offset and surface properties are kept.
##
## Unlike the legacy implementation, this script does not place rigid 6 m GLB
## blocks along the curve. It samples Curve3D into one continuous three-vertex
## strip (left / crown / right), so bends do not create wedge-shaped gaps.
## When follow_terrain is enabled, every sampled cross-section is ray-projected
## onto the terrain, including both road edges. This lets a road climb from a
## hilltop to the foot of a slope and follow cross-slope changes more reliably.

enum RoadType {
	ASPHALT_NARROW,
	ASPHALT_WIDE,
	COUNTRY_GRAVEL_NARROW,
	COUNTRY_GRAVEL_WIDE,
}

const ROAD_SCENES = {
	RoadType.ASPHALT_NARROW: preload("res://assets/environment/FTF_Road_Asphalt_Straight_4x6m.glb"),
	RoadType.ASPHALT_WIDE: preload("res://assets/environment/FTF_Road_Asphalt_Straight_6x6m.glb"),
	RoadType.COUNTRY_GRAVEL_NARROW: preload("res://assets/environment/FTF_Road_CountryGravel_Straight_3x6m.glb"),
	RoadType.COUNTRY_GRAVEL_WIDE: preload("res://assets/environment/FTF_Road_CountryGravel_Straight_5x6m.glb"),
}

const ROAD_WIDTHS = {
	RoadType.ASPHALT_NARROW: 4.0,
	RoadType.ASPHALT_WIDE: 6.0,
	RoadType.COUNTRY_GRAVEL_NARROW: 3.0,
	RoadType.COUNTRY_GRAVEL_WIDE: 5.0,
}

@export var road_type: RoadType = RoadType.ASPHALT_WIDE:
	set(value):
		road_type = value
		_request_rebuild()

@export_group("Continuous Mesh")
@export_range(0.0, 20.0, 0.05) var width_override = 0.0:
	set(value):
		width_override = value
		_request_rebuild()

@export_range(0.25, 4.0, 0.05) var mesh_sample_spacing = 1.0:
	set(value):
		mesh_sample_spacing = value
		_request_rebuild()

## Prevent one very long road segment from issuing tens of thousands of
## terrain raycasts in a single frame. The actual spacing becomes adaptive
## when this limit is reached.
@export_range(64, 4096, 1) var max_mesh_samples = 768:
	set(value):
		max_mesh_samples = maxi(64, value)
		_request_rebuild()

@export_range(-0.2, 1.0, 0.01) var vertical_offset = 0.06:
	set(value):
		vertical_offset = value
		_request_rebuild()

@export_range(0.5, 24.0, 0.1) var texture_repeat_length = 6.0:
	set(value):
		texture_repeat_length = value
		_request_rebuild()

@export_range(0.0, 0.25, 0.005) var crown_height = 0.015:
	set(value):
		crown_height = value
		_request_rebuild()

@export_range(0.0, 0.25, 0.005) var edge_drop = 0.0:
	set(value):
		edge_drop = value
		_request_rebuild()

@export_group("Editor Preview")
@export var editor_preview_mode = false:
	set(value):
		editor_preview_mode = value
		_request_rebuild()

@export_range(16, 512, 1) var editor_preview_max_samples = 128:
	set(value):
		editor_preview_max_samples = maxi(16, value)
		_request_rebuild()

@export_group("Terrain Following")
@export var follow_terrain = true:
	set(value):
		follow_terrain = value
		_request_rebuild()

@export_flags_3d_physics var terrain_collision_mask = 1:
	set(value):
		terrain_collision_mask = value
		_request_rebuild()

@export_range(10.0, 4000.0, 10.0) var terrain_probe_up = 1000.0
@export_range(10.0, 4000.0, 10.0) var terrain_probe_down = 2000.0

@export_group("Collision")
@export var generate_road = true:
	set(value):
		generate_road = value
		_request_rebuild()

@export var generate_collision = false:
	set(value):
		generate_collision = value
		_request_rebuild()

@export_flags_3d_physics var collision_layer = 1:
	set(value):
		collision_layer = value
		_request_rebuild()

@export_group("Legacy Compatibility")
## Retained so existing .tscn files continue to load. The continuous renderer
## uses mesh_sample_spacing rather than rigid-piece spacing.
@export_range(3.0, 6.0, 0.05) var piece_spacing = 5.8

@export_group("Surface Rendering")
@export_range(0.8, 1.0, 0.01) var asphalt_roughness = 0.96:
	set(value):
		asphalt_roughness = value
		_material_cache.clear()
		_request_rebuild()

@export_range(0.8, 1.0, 0.01) var gravel_roughness = 0.98:
	set(value):
		gravel_roughness = value
		_material_cache.clear()
		_request_rebuild()

@export_range(0.0, 0.5, 0.01) var surface_specular = 0.12:
	set(value):
		surface_specular = value
		_material_cache.clear()
		_request_rebuild()

@export_tool_button("Rebuild Road") var rebuild_button: Callable = rebuild_road

var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _collision_shape: CollisionShape3D
var _rebuild_queued = false
var _is_rebuilding = false
var _rebuild_suspended = false
var _connected_curve: Curve3D
var _material_cache: Dictionary = {}


func _ready() -> void:
	_ensure_nodes()
	_connect_curve()
	_request_rebuild()


func _exit_tree() -> void:
	if _connected_curve != null and _connected_curve.changed.is_connected(_on_curve_changed):
		_connected_curve.changed.disconnect(_on_curve_changed)
	_connected_curve = null


func get_road_width() -> float:
	if width_override > 0.01:
		return width_override
	return float(ROAD_WIDTHS.get(road_type, 6.0))


func rebuild_road() -> void:
	# Always consume the queued request first. If a deferred call arrives while
	# point dragging has rebuilds suspended, leaving this flag true would block
	# the one rebuild requested when dragging ends.
	_rebuild_queued = false
	# Guard against Curve3D.changed recursively scheduling rebuild_road().
	# The old implementation changed bake_interval inside rebuild_road(),
	# which emitted changed and created an endless deferred rebuild loop as
	# soon as the road had two points.
	if _is_rebuilding or _rebuild_suspended:
		return
	_is_rebuilding = true
	_rebuild_road_internal()
	_is_rebuilding = false


func _rebuild_road_internal() -> void:
	_ensure_nodes()
	_remove_legacy_piece_root()

	if not generate_road or curve == null or curve.point_count < 2:
		_mesh_instance.mesh = null
		_collision_shape.shape = null
		return

	var desired_bake_interval = maxf(0.1, mesh_sample_spacing * 0.5)
	if not is_equal_approx(curve.bake_interval, desired_bake_interval):
		curve.bake_interval = desired_bake_interval
	var total_length = curve.get_baked_length()
	if total_length <= 0.05:
		_mesh_instance.mesh = null
		_collision_shape.shape = null
		return

	var width = get_road_width()
	var half_width = width * 0.5
	var interval = maxf(0.1, mesh_sample_spacing)
	var requested_sample_count = maxi(
		2,
		int(ceil(total_length / interval)) + 1
	)
	var sample_limit = maxi(64, max_mesh_samples)
	if editor_preview_mode:
		sample_limit = maxi(16, editor_preview_max_samples)
	var sample_count = mini(
		requested_sample_count,
		sample_limit
	)

	# First project every center sample to terrain. Tangents are then derived
	# from these projected centers rather than from the unprojected curve.
	var center_world: Array[Vector3] = []
	var center_normals: Array[Vector3] = []
	var distances: Array[float] = []
	center_world.resize(sample_count)
	center_normals.resize(sample_count)
	distances.resize(sample_count)

	for sample_index in range(sample_count):
		var distance = minf(
			float(sample_index) * total_length / float(sample_count - 1),
			total_length
		)
		var local_curve_point = curve.sample_baked(distance, true)
		var world_curve_point = to_global(local_curve_point)
		var projection = _project_world_point_to_terrain(world_curve_point)
		center_world[sample_index] = projection.get("position", world_curve_point) as Vector3
		center_normals[sample_index] = (
			projection.get("normal", Vector3.UP) as Vector3
		).normalized()
		distances[sample_index] = distance

	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	var vertices_per_sample = 3
	vertices.resize(sample_count * vertices_per_sample)
	normals.resize(sample_count * vertices_per_sample)
	uvs.resize(sample_count * vertices_per_sample)
	indices.resize((sample_count - 1) * 12)

	for sample_index in range(sample_count):
		var previous_index = maxi(0, sample_index - 1)
		var next_index = mini(sample_count - 1, sample_index + 1)
		var tangent = center_world[next_index] - center_world[previous_index]
		if tangent.length_squared() <= 0.000001:
			tangent = global_transform.basis * Vector3.FORWARD
		tangent = tangent.normalized()

		var center_normal = center_normals[sample_index]
		var right = center_normal.cross(tangent)
		if right.length_squared() <= 0.000001:
			right = Vector3.UP.cross(tangent)
		if right.length_squared() <= 0.000001:
			right = Vector3.RIGHT
		right = right.normalized()

		var raw_center = center_world[sample_index]
		var left_guess = raw_center - right * half_width
		var right_guess = raw_center + right * half_width
		var left_normal = center_normal
		var right_normal = center_normal
		var left_world = left_guess
		var right_world = right_guess

		# While the user is still placing control points, use the center terrain
		# projection for the whole cross-section. The final road performs the
		# more expensive left/center/right projection after Finish Road.
		if not editor_preview_mode:
			var left_projection = _project_world_point_to_terrain(left_guess)
			var right_projection = _project_world_point_to_terrain(right_guess)
			left_normal = (
				left_projection.get("normal", center_normal) as Vector3
			).normalized()
			right_normal = (
				right_projection.get("normal", center_normal) as Vector3
			).normalized()
			left_world = left_projection.get("position", left_guess) as Vector3
			right_world = right_projection.get("position", right_guess) as Vector3

		left_world += left_normal * (vertical_offset - edge_drop)
		var crown_world = raw_center + center_normal * (vertical_offset + crown_height)
		right_world += right_normal * (vertical_offset - edge_drop)

		var vertex_index = sample_index * vertices_per_sample
		vertices[vertex_index] = to_local(left_world)
		vertices[vertex_index + 1] = to_local(crown_world)
		vertices[vertex_index + 2] = to_local(right_world)

		# Transform world-space normals into this Path3D's local basis.
		var inverse_basis = global_transform.basis.inverse()
		normals[vertex_index] = (inverse_basis * left_normal).normalized()
		normals[vertex_index + 1] = (inverse_basis * center_normal).normalized()
		normals[vertex_index + 2] = (inverse_basis * right_normal).normalized()

		var v = distances[sample_index] / maxf(0.1, texture_repeat_length)
		uvs[vertex_index] = Vector2(0.0, v)
		uvs[vertex_index + 1] = Vector2(0.5, v)
		uvs[vertex_index + 2] = Vector2(1.0, v)

	for segment_index in range(sample_count - 1):
		var left_current = segment_index * vertices_per_sample
		var center_current = left_current + 1
		var right_current = left_current + 2
		var left_next = left_current + vertices_per_sample
		var center_next = left_next + 1
		var right_next = left_next + 2
		var write_index = segment_index * 12

		# Left half of the road crown.
		indices[write_index] = left_current
		indices[write_index + 1] = left_next
		indices[write_index + 2] = center_current
		indices[write_index + 3] = center_current
		indices[write_index + 4] = left_next
		indices[write_index + 5] = center_next

		# Right half of the road crown.
		indices[write_index + 6] = center_current
		indices[write_index + 7] = center_next
		indices[write_index + 8] = right_current
		indices[write_index + 9] = right_current
		indices[write_index + 10] = center_next
		indices[write_index + 11] = right_next

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var generated_mesh = ArrayMesh.new()
	generated_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var road_material = _get_road_material()
	if road_material != null:
		generated_mesh.surface_set_material(0, road_material)
	_mesh_instance.mesh = generated_mesh

	if generate_collision:
		var faces = PackedVector3Array()
		faces.resize(indices.size())
		for index in range(indices.size()):
			faces[index] = vertices[indices[index]]
		var concave = ConcavePolygonShape3D.new()
		concave.set_faces(faces)
		_collision_shape.shape = concave
		_body.collision_layer = collision_layer
		_body.collision_mask = 0
	else:
		_collision_shape.shape = null


func request_rebuild() -> void:
	_request_rebuild()


func set_rebuild_suspended(value: bool) -> void:
	if _rebuild_suspended == value:
		return
	_rebuild_suspended = value
	if not _rebuild_suspended:
		_request_rebuild()


func _project_world_point_to_terrain(world_point: Vector3) -> Dictionary:
	if not follow_terrain or not is_inside_tree() or get_world_3d() == null:
		return {
			"position": world_point,
			"normal": Vector3.UP,
			"hit": false,
		}

	var ray_from = world_point + Vector3.UP * terrain_probe_up
	var ray_to = world_point - Vector3.UP * terrain_probe_down
	var query = PhysicsRayQueryParameters3D.create(
		ray_from,
		ray_to,
		terrain_collision_mask
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if is_instance_valid(_body):
		query.exclude = [_body.get_rid()]
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {
			"position": world_point,
			"normal": Vector3.UP,
			"hit": false,
		}
	return {
		"position": hit.get("position", world_point) as Vector3,
		"normal": hit.get("normal", Vector3.UP) as Vector3,
		"hit": true,
	}


func _ensure_nodes() -> void:
	_mesh_instance = get_node_or_null("RoadMesh") as MeshInstance3D
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "RoadMesh"
		_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(_mesh_instance, false, Node.INTERNAL_MODE_BACK)

	_body = get_node_or_null("RoadBody") as StaticBody3D
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = "RoadBody"
		add_child(_body, false, Node.INTERNAL_MODE_BACK)

	_collision_shape = _body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "CollisionShape3D"
		_body.add_child(_collision_shape, false, Node.INTERNAL_MODE_BACK)


func _remove_legacy_piece_root() -> void:
	var legacy = get_node_or_null("RoadPieces")
	if legacy != null:
		legacy.queue_free()


func _get_road_material() -> Material:
	var roughness = asphalt_roughness if _is_asphalt() else gravel_roughness
	var cache_key = "%d:%.2f:%.2f" % [road_type, roughness, surface_specular]
	if _material_cache.has(cache_key):
		return _material_cache[cache_key] as Material

	var source_scene = ROAD_SCENES.get(road_type) as PackedScene
	var source_material: Material = null
	if source_scene != null:
		var source_root = source_scene.instantiate()
		source_material = _find_first_material(source_root)
		source_root.free()

	var result: Material
	if source_material is BaseMaterial3D:
		var base = source_material.duplicate() as BaseMaterial3D
		base.metallic = 0.0
		base.metallic_specular = surface_specular
		base.roughness = roughness
		result = base
	elif source_material != null:
		result = source_material.duplicate()
	else:
		var fallback = StandardMaterial3D.new()
		fallback.albedo_color = Color("51545a") if _is_asphalt() else Color("8c8068")
		fallback.roughness = roughness
		fallback.metallic_specular = surface_specular
		result = fallback

	_material_cache[cache_key] = result
	return result


func _find_first_material(node: Node) -> Material:
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
			var material = mesh_instance.get_active_material(0)
			if material != null:
				return material
	for child in node.get_children():
		var found = _find_first_material(child)
		if found != null:
			return found
	return null


func _is_asphalt() -> bool:
	return road_type in [RoadType.ASPHALT_NARROW, RoadType.ASPHALT_WIDE]


func _connect_curve() -> void:
	if _connected_curve != null and _connected_curve != curve:
		if _connected_curve.changed.is_connected(_on_curve_changed):
			_connected_curve.changed.disconnect(_on_curve_changed)
		_connected_curve = null
	if curve != null:
		_connected_curve = curve
		if not _connected_curve.changed.is_connected(_on_curve_changed):
			_connected_curve.changed.connect(_on_curve_changed)


func refresh_curve_connection() -> void:
	_connect_curve()
	_request_rebuild()


func _on_curve_changed() -> void:
	if _is_rebuilding or _rebuild_suspended:
		return
	_request_rebuild()


func _request_rebuild() -> void:
	if _is_rebuilding or _rebuild_suspended or not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("rebuild_road")
