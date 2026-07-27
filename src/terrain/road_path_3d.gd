@tool
class_name RoadPath3D
extends Path3D

enum RoadType {
	ASPHALT_NARROW,
	ASPHALT_WIDE,
	COUNTRY_GRAVEL_NARROW,
	COUNTRY_GRAVEL_WIDE,
}

const ROAD_SCENES := {
	RoadType.ASPHALT_NARROW: preload("res://assets/environment/FTF_Road_Asphalt_Straight_4x6m.glb"),
	RoadType.ASPHALT_WIDE: preload("res://assets/environment/FTF_Road_Asphalt_Straight_6x6m.glb"),
	RoadType.COUNTRY_GRAVEL_NARROW: preload("res://assets/environment/FTF_Road_CountryGravel_Straight_3x6m.glb"),
	RoadType.COUNTRY_GRAVEL_WIDE: preload("res://assets/environment/FTF_Road_CountryGravel_Straight_5x6m.glb"),
}

@export var road_type: RoadType = RoadType.ASPHALT_WIDE:
	set(value):
		road_type = value
		_request_rebuild()
@export_range(3.0, 6.0, 0.05) var piece_spacing: float = 5.8:
	set(value):
		piece_spacing = value
		_request_rebuild()
@export_range(-0.2, 1.0, 0.01) var vertical_offset: float = 0.5:
	set(value):
		vertical_offset = value
		_request_rebuild()
@export var generate_road: bool = true:
	set(value):
		generate_road = value
		_request_rebuild()
@export_group("Surface Rendering")
@export_range(0.8, 1.0, 0.01) var asphalt_roughness := 0.96
@export_range(0.8, 1.0, 0.01) var gravel_roughness := 0.98
@export_range(0.0, 0.5, 0.01) var surface_specular := 0.12
@export_tool_button("Rebuild Road") var rebuild_button: Callable = rebuild_road

var _pieces_root: Node3D
var _rebuild_queued := false
var _surface_material_cache: Dictionary = {}


func _ready() -> void:
	_ensure_pieces_root()
	_connect_curve()
	_request_rebuild()


func _exit_tree() -> void:
	if curve != null and curve.changed.is_connected(_on_curve_changed):
		curve.changed.disconnect(_on_curve_changed)


func rebuild_road() -> void:
	_rebuild_queued = false
	_ensure_pieces_root()
	_clear_pieces()
	if not generate_road or curve == null or curve.point_count < 2:
		return

	var road_scene := ROAD_SCENES.get(road_type) as PackedScene
	if road_scene == null:
		return
	var total_length := curve.get_baked_length()
	if total_length <= 0.01:
		return
	var piece_count := maxi(1, int(ceil(total_length / piece_spacing)))
	var actual_spacing := total_length / float(piece_count)
	for index in range(piece_count):
		var distance := minf((float(index) + 0.5) * actual_spacing, total_length)
		var sample_distance := minf(distance + 0.1, total_length)
		var position_on_curve := curve.sample_baked(distance, true)
		var ahead := curve.sample_baked(sample_distance, true)
		var direction := ahead - position_on_curve
		if direction.length_squared() <= 0.000001:
			var behind := curve.sample_baked(maxf(distance - 0.1, 0.0), true)
			direction = position_on_curve - behind
		direction.y = 0.0
		if direction.length_squared() <= 0.000001:
			continue

		var piece := road_scene.instantiate() as Node3D
		piece.name = "RoadPiece_%03d" % index
		_pieces_root.add_child(piece)
		_apply_rough_road_materials(piece)
		piece.position = position_on_curve + Vector3.UP * vertical_offset
		piece.basis = Basis.looking_at(direction.normalized(), Vector3.UP)


func _apply_rough_road_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				var source := mesh_instance.get_active_material(surface_index)
				var optimized := _get_rough_road_material(source)
				if optimized != null:
					mesh_instance.set_surface_override_material(surface_index, optimized)
	for child in node.get_children():
		_apply_rough_road_materials(child)


func _get_rough_road_material(source: Material) -> Material:
	if not source is BaseMaterial3D:
		return null
	var roughness := asphalt_roughness if road_type in [
		RoadType.ASPHALT_NARROW, RoadType.ASPHALT_WIDE
	] else gravel_roughness
	var cache_key := "%d:%.2f:%.2f" % [source.get_instance_id(), roughness, surface_specular]
	if _surface_material_cache.has(cache_key):
		return _surface_material_cache[cache_key] as Material
	var material := source.duplicate() as BaseMaterial3D
	material.metallic = 0.0
	material.metallic_specular = surface_specular
	material.roughness = roughness
	_surface_material_cache[cache_key] = material
	return material


func _ensure_pieces_root() -> void:
	_pieces_root = get_node_or_null("RoadPieces") as Node3D
	if _pieces_root == null:
		_pieces_root = Node3D.new()
		_pieces_root.name = "RoadPieces"
		add_child(_pieces_root, false, Node.INTERNAL_MODE_BACK)


func _clear_pieces() -> void:
	if _pieces_root == null:
		return
	for child in _pieces_root.get_children():
		child.free()


func _connect_curve() -> void:
	if curve != null and not curve.changed.is_connected(_on_curve_changed):
		curve.changed.connect(_on_curve_changed)


func _on_curve_changed() -> void:
	_request_rebuild()


func _request_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("rebuild_road")
