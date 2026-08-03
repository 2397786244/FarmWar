extends Node3D

@export_range(0.01, 0.25, 0.005) var wire_radius := 0.055
@export_range(0.0, 8.0, 0.05) var sag_amount := 1.15
@export_range(4, 32, 1) var visual_segments := 12
@export_range(0.01, 0.5, 0.01) var collision_radius := 0.10
@export var collision_layer := 4096
@export var collision_mask := 45739

var _mesh_instance: MeshInstance3D
var _collision_body: StaticBody3D


func rebuild_from_endpoints(start_point: Vector3, end_point: Vector3) -> void:
	_clear_generated_children()
	var distance := start_point.distance_to(end_point)
	if distance <= 0.05:
		return

	var points := _build_sagged_points(start_point, end_point, distance)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "WireMesh"
	_mesh_instance.mesh = _build_tube_mesh(points)
	_mesh_instance.material_override = _make_wire_material()
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh_instance)

	_collision_body = StaticBody3D.new()
	_collision_body.name = "WireCollision"
	_collision_body.collision_layer = collision_layer
	_collision_body.collision_mask = collision_mask
	add_child(_collision_body)
	_build_collision_shapes(points)


func _build_sagged_points(start_point: Vector3, end_point: Vector3, distance: float) -> PackedVector3Array:
	var count := maxi(4, visual_segments)
	var points := PackedVector3Array()
	for index in range(count + 1):
		var t := float(index) / float(count)
		var point := start_point.lerp(end_point, t)
		var span_sag := sag_amount * clampf(distance / 18.0, 0.45, 2.0)
		point.y -= sin(t * PI) * span_sag
		points.append(point)
	return points


func _build_tube_mesh(points: PackedVector3Array) -> ArrayMesh:
	var sides := 6
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for point_index in range(points.size()):
		var tangent := _point_tangent(points, point_index)
		var reference := Vector3.UP
		if absf(tangent.dot(reference)) > 0.92:
			reference = Vector3.RIGHT
		var side := tangent.cross(reference).normalized()
		var up := side.cross(tangent).normalized()
		for side_index in range(sides):
			var angle := TAU * float(side_index) / float(sides)
			var radial := side * cos(angle) + up * sin(angle)
			vertices.append(points[point_index] + radial * wire_radius)
			normals.append(radial.normalized())
			uvs.append(Vector2(float(side_index) / float(sides), float(point_index)))

	for point_index in range(points.size() - 1):
		for side_index in range(sides):
			var next_side := (side_index + 1) % sides
			var current := point_index * sides + side_index
			var current_next := point_index * sides + next_side
			var next := (point_index + 1) * sides + side_index
			var next_next := (point_index + 1) * sides + next_side
			indices.append(current)
			indices.append(next)
			indices.append(current_next)
			indices.append(current_next)
			indices.append(next)
			indices.append(next_next)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _point_tangent(points: PackedVector3Array, index: int) -> Vector3:
	var tangent := Vector3.FORWARD
	if index <= 0:
		tangent = points[1] - points[0]
	elif index >= points.size() - 1:
		tangent = points[points.size() - 1] - points[points.size() - 2]
	else:
		tangent = points[index + 1] - points[index - 1]
	if tangent.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return tangent.normalized()


func _make_wire_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.006, 0.006, 0.008, 1.0)
	material.metallic = 0.05
	material.roughness = 0.82
	return material


func _build_collision_shapes(points: PackedVector3Array) -> void:
	var collision_stride := maxi(1, int(ceil(float(points.size() - 1) / 6.0)))
	for start_index in range(0, points.size() - 1, collision_stride):
		var end_index := mini(start_index + collision_stride, points.size() - 1)
		var segment := points[end_index] - points[start_index]
		var length := segment.length()
		if length <= 0.01:
			continue
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(collision_radius * 2.0, collision_radius * 2.0, length + collision_radius)
		shape_node.shape = shape
		shape_node.position = points[start_index].lerp(points[end_index], 0.5)
		var direction := segment / length
		var reference := Vector3.UP
		if absf(direction.dot(reference)) > 0.92:
			reference = Vector3.RIGHT
		shape_node.basis = Basis.looking_at(direction, reference)
		_collision_body.add_child(shape_node)


func _clear_generated_children() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_mesh_instance = null
	_collision_body = null
