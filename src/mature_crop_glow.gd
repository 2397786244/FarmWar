extends Node3D
class_name MatureCropGlow

const GLOW_SHADER := preload("res://src/mature_crop_glow.gdshader")
const OUTER_SIZE := Vector2(2.04, 2.04)
const GLOW_HEIGHT := 0.24
const EDGE_THICKNESS := 0.06
const BASE_HEIGHT := 0.08
const GLOW_COLOR := Color(1.0, 0.78, 0.16, 0.86)

static var _shared_mesh: ArrayMesh
static var _shared_material: ShaderMaterial

var _glow_mesh_instance: MeshInstance3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	_ensure_visual()


func set_active(active: bool) -> void:
	visible = active
	if active:
		_ensure_visual()


func is_active() -> bool:
	return visible


func get_glow_height() -> float:
	return GLOW_HEIGHT


func get_outer_size() -> Vector2:
	return OUTER_SIZE


func _ensure_visual() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if is_instance_valid(_glow_mesh_instance):
		return
	_glow_mesh_instance = MeshInstance3D.new()
	_glow_mesh_instance.name = "GlowMesh"
	_glow_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow_mesh_instance.mesh = _get_shared_mesh()
	add_child(_glow_mesh_instance)
	_glow_mesh_instance.position.y = BASE_HEIGHT


static func _get_shared_mesh() -> ArrayMesh:
	if is_instance_valid(_shared_mesh):
		return _shared_mesh
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_x := OUTER_SIZE.x * 0.5
	var half_z := OUTER_SIZE.y * 0.5
	var inner_length_x := maxf(0.01, OUTER_SIZE.x - EDGE_THICKNESS * 2.0)
	var inner_length_z := maxf(0.01, OUTER_SIZE.y - EDGE_THICKNESS * 2.0)
	_append_box(
		surface,
		Vector3(0.0, 0.0, -half_z),
		Vector3(OUTER_SIZE.x, GLOW_HEIGHT, EDGE_THICKNESS)
	)
	_append_box(
		surface,
		Vector3(0.0, 0.0, half_z),
		Vector3(OUTER_SIZE.x, GLOW_HEIGHT, EDGE_THICKNESS)
	)
	_append_box(
		surface,
		Vector3(-half_x, 0.0, 0.0),
		Vector3(EDGE_THICKNESS, GLOW_HEIGHT, inner_length_z)
	)
	_append_box(
		surface,
		Vector3(half_x, 0.0, 0.0),
		Vector3(EDGE_THICKNESS, GLOW_HEIGHT, inner_length_z)
	)
	_shared_mesh = surface.commit() as ArrayMesh
	if _shared_mesh == null:
		return null
	_shared_mesh.surface_set_material(0, _get_shared_material())
	return _shared_mesh


static func _get_shared_material() -> ShaderMaterial:
	if is_instance_valid(_shared_material):
		return _shared_material
	_shared_material = ShaderMaterial.new()
	_shared_material.shader = GLOW_SHADER
	_shared_material.set_shader_parameter("glow_color", GLOW_COLOR)
	_shared_material.set_shader_parameter("glow_height", GLOW_HEIGHT)
	_shared_material.set_shader_parameter("emission_strength", 3.2)
	_shared_material.set_shader_parameter("edge_softness", 0.12)
	return _shared_material


static func _append_box(surface: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var half := size * 0.5
	var x0 := center.x - half.x
	var x1 := center.x + half.x
	var y0 := center.y
	var y1 := center.y + size.y
	var z0 := center.z - half.z
	var z1 := center.z + half.z
	var faces := [
		{
			"normal": Vector3(0.0, 0.0, -1.0),
			"vertices": [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0)],
		},
		{
			"normal": Vector3(0.0, 0.0, 1.0),
			"vertices": [Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x1, y1, z1)],
		},
		{
			"normal": Vector3(-1.0, 0.0, 0.0),
			"vertices": [Vector3(x0, y0, z1), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1)],
		},
		{
			"normal": Vector3(1.0, 0.0, 0.0),
			"vertices": [Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0)],
		},
		{
			"normal": Vector3(0.0, -1.0, 0.0),
			"vertices": [Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0)],
		},
		{
			"normal": Vector3(0.0, 1.0, 0.0),
			"vertices": [Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1)],
		},
	]
	for face_value: Variant in faces:
		var face := face_value as Dictionary
		var normal := face["normal"] as Vector3
		var vertices := face["vertices"] as Array
		_append_triangle(surface, vertices[0] as Vector3, vertices[1] as Vector3, vertices[2] as Vector3, normal)
		_append_triangle(surface, vertices[0] as Vector3, vertices[2] as Vector3, vertices[3] as Vector3, normal)


static func _append_triangle(
		surface: SurfaceTool,
		first: Vector3,
		second: Vector3,
		third: Vector3,
		normal: Vector3
	) -> void:
	for vertex in [first, second, third]:
		surface.set_normal(normal)
		surface.add_vertex(vertex)
