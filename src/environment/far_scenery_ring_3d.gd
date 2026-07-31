extends Node3D
class_name FarSceneryRing3D

const FAR_TREE_SCENE := preload("res://assets/environment/FarTreeCluster.glb")
const FAR_ROCK_SCENE := preload("res://assets/environment/FarRockMass.glb")
const FAR_FARM_PATCH_SCENE := preload("res://assets/environment/FarFarmPatch.glb")
const FAR_FARM_BUILDINGS_SCENE := preload("res://assets/environment/FarFarmBuildings.glb")
const SMALL_GRASS_SCENE := preload("res://assets/environment/Grass_small.glb")
const TALL_GRASS_SCENE := preload("res://assets/environment/Grass_tall.glb")
const FAR_GRASS_SHADER: Shader = preload("res://src/environment/far_grass_surface.gdshader")
const LOCAL_BOUNDARY_WARNING_SHADER: Shader = preload(
	"res://src/environment/local_boundary_warning.gdshader"
)
const CRESTON_TOWN_SURFACE_PALETTE_LOOKUP: Texture2D = preload(
	"res://worlds/creston_town/creston_town_surface_palette_lookup.res"
)
# CrestonTown's 1m-thick Grass BoxMesh is centered at y=0, so its visible
# surface is y=0.5. Keep the GLB base slabs slightly below that surface.
const FAR_TILE_SURFACE_Y := 0.48
const FAR_GRASS_SURFACE_Y := 0.51

@export var random_seed := 731902
@export var core_map_size := Vector2(256.0, 256.0)
@export var far_ground_size := Vector2(1536.0, 1536.0)
@export var inner_tree_half_extent := 170.0
@export var outer_tree_half_extent := 225.0
@export var inner_tree_spacing := 68.0
@export var outer_tree_spacing := 92.0
@export_range(0.0, 0.8, 0.01) var inner_tree_skip_chance := 0.05
@export_range(0.0, 0.8, 0.01) var outer_tree_skip_chance := 0.14
@export var tree_position_jitter := 3.0
@export var farm_patch_spacing := Vector2(82.0, 82.0)
@export var fourth_rock_half_extent := 520.0
@export var fifth_rock_half_extent := 650.0
@export var fourth_rock_count := 5
@export var fifth_rock_count := 3
@export var visibility_distance := 900.0
@export var surface_palette_lookup: Texture2D = CRESTON_TOWN_SURFACE_PALETTE_LOOKUP
@export_group("Sparse First-ring Grass")
@export var far_grass_inner_half_extent := 132.0
@export var far_grass_outer_half_extent := 250.0
@export var far_small_grass_count := 120
@export var far_tall_grass_count := 24
@export var far_grass_visibility_distance := 180.0
@export_group("Local Boundary Warning")
@export var boundary_warning_distance := 3.0
@export var boundary_warning_full_distance := 0.75
@export var boundary_visual_height := 50.0
@export var boundary_visual_thickness := 0.18

var _rng := RandomNumberGenerator.new()
var _grass_material: ShaderMaterial = null
var _boundary_warning_root: Node3D = null
var _boundary_warning_material: ShaderMaterial = null


func _ready() -> void:
	_rng.seed = random_seed
	_build_far_ground()
	_build_local_boundary_warning()
	var inner_trees := _make_square_ring(
		inner_tree_half_extent, inner_tree_spacing, inner_tree_skip_chance
	)
	var outer_trees := _make_square_ring(
		outer_tree_half_extent, outer_tree_spacing, outer_tree_skip_chance
	)
	_create_scene_multimeshes(FAR_TREE_SCENE, inner_trees, "InnerTreeRing")
	_create_scene_multimeshes(FAR_TREE_SCENE, outer_trees, "OuterTreeRing")
	var distant_rocks := _make_sparse_rock_ring(fourth_rock_half_extent, fourth_rock_count, 0.0)
	distant_rocks.append_array(_make_sparse_rock_ring(fifth_rock_half_extent, fifth_rock_count, 0.5))
	_create_scene_multimeshes(FAR_ROCK_SCENE, distant_rocks, "DistantRockRings")
	var farm_groups := _farm_group_layouts()
	_create_scene_multimeshes(FAR_FARM_PATCH_SCENE, _make_farm_patches(farm_groups), "FarFarmPatches")
	_create_scene_multimeshes(FAR_FARM_BUILDINGS_SCENE, _make_farm_buildings(farm_groups), "FarFarmBuildings")
	_create_scene_multimeshes(
		SMALL_GRASS_SCENE,
		_make_sparse_far_grass(far_small_grass_count, Vector2(0.8, 1.1)),
		"SparseFarSmallGrass",
		far_grass_visibility_distance
	)
	_create_scene_multimeshes(
		TALL_GRASS_SCENE,
		_make_sparse_far_grass(far_tall_grass_count, Vector2(0.75, 1.0)),
		"SparseFarTallGrass",
		far_grass_visibility_distance
	)


func _process(_delta: float) -> void:
	_update_local_boundary_warning()


func _build_far_ground() -> void:
	_grass_material = ShaderMaterial.new()
	_grass_material.shader = FAR_GRASS_SHADER
	_grass_material.set_shader_parameter(
		"surface_palette", surface_palette_lookup
	)
	var core_half := core_map_size * 0.5
	var far_half := far_ground_size * 0.5
	_add_ground_strip("FarGroundNorth", Vector3(0.0, 0.0, -0.5 * (core_half.y + far_half.y)), Vector2(far_ground_size.x, far_half.y - core_half.y), _grass_material)
	_add_ground_strip("FarGroundSouth", Vector3(0.0, 0.0, 0.5 * (core_half.y + far_half.y)), Vector2(far_ground_size.x, far_half.y - core_half.y), _grass_material)
	_add_ground_strip("FarGroundWest", Vector3(-0.5 * (core_half.x + far_half.x), 0.0, 0.0), Vector2(far_half.x - core_half.x, core_map_size.y), _grass_material)
	_add_ground_strip("FarGroundEast", Vector3(0.5 * (core_half.x + far_half.x), 0.0, 0.0), Vector2(far_half.x - core_half.x, core_map_size.y), _grass_material)


func _add_ground_strip(node_name: String, center: Vector3, size_xz: Vector2, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size_xz.x, 1.0, size_xz.y)
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = center
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = visibility_distance
	add_child(instance)


func _build_local_boundary_warning() -> void:
	# Dedicated authority never needs local-only warning geometry.
	if GameAuthority.is_server_authority():
		set_process(false)
		return
	_boundary_warning_root = Node3D.new()
	_boundary_warning_root.name = "LocalBoundaryWarning"
	add_child(_boundary_warning_root)
	_boundary_warning_material = ShaderMaterial.new()
	_boundary_warning_material.shader = LOCAL_BOUNDARY_WARNING_SHADER
	_boundary_warning_material.set_shader_parameter("visibility_alpha", 0.0)
	var half_extent := core_map_size * 0.5
	_add_boundary_band(
		"NorthBoundaryBand",
		Vector3(0.0, boundary_visual_height * 0.5, -half_extent.y),
		Vector3(core_map_size.x, boundary_visual_height, boundary_visual_thickness)
	)
	_add_boundary_band(
		"SouthBoundaryBand",
		Vector3(0.0, boundary_visual_height * 0.5, half_extent.y),
		Vector3(core_map_size.x, boundary_visual_height, boundary_visual_thickness)
	)
	_add_boundary_band(
		"WestBoundaryBand",
		Vector3(-half_extent.x, boundary_visual_height * 0.5, 0.0),
		Vector3(boundary_visual_thickness, boundary_visual_height, core_map_size.y)
	)
	_add_boundary_band(
		"EastBoundaryBand",
		Vector3(half_extent.x, boundary_visual_height * 0.5, 0.0),
		Vector3(boundary_visual_thickness, boundary_visual_height, core_map_size.y)
	)
	_boundary_warning_root.visible = false


func _add_boundary_band(node_name: String, center: Vector3, size: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _boundary_warning_material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = center
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = maxf(80.0, boundary_warning_distance * 3.0)
	_boundary_warning_root.add_child(instance)


func _update_local_boundary_warning() -> void:
	if _boundary_warning_root == null or _boundary_warning_material == null:
		return
	var active_camera := get_viewport().get_camera_3d()
	if not is_instance_valid(active_camera):
		_boundary_warning_root.visible = false
		return
	var camera_position := active_camera.global_position
	var half_extent := core_map_size * 0.5
	var distance_to_boundary := minf(
		absf(absf(camera_position.x) - half_extent.x),
		absf(absf(camera_position.z) - half_extent.y)
	)
	var start_distance := maxf(boundary_warning_distance, boundary_warning_full_distance + 0.01)
	if distance_to_boundary >= start_distance:
		_boundary_warning_root.visible = false
		_boundary_warning_material.set_shader_parameter("visibility_alpha", 0.0)
		return
	var alpha := 1.0 - clampf(
		(distance_to_boundary - boundary_warning_full_distance)
			/ (start_distance - boundary_warning_full_distance),
		0.0,
		1.0
	)
	_boundary_warning_root.visible = true
	_boundary_warning_material.set_shader_parameter("visibility_alpha", alpha)


func _make_square_ring(half_extent: float, spacing: float, skip_chance: float) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	var count_per_side := maxi(2, floori(half_extent * 2.0 / spacing))
	for side in range(4):
		for index in range(count_per_side):
			if _rng.randf() < skip_chance:
				continue
			var along := lerpf(-half_extent, half_extent, (float(index) + 0.5) / float(count_per_side))
			var radial_jitter := _rng.randf_range(-tree_position_jitter, tree_position_jitter)
			var tangent_jitter := _rng.randf_range(-tree_position_jitter, tree_position_jitter)
			var position := Vector3.ZERO
			match side:
				0: position = Vector3(along + tangent_jitter, 0.0, -half_extent + radial_jitter)
				1: position = Vector3(half_extent + radial_jitter, 0.0, along + tangent_jitter)
				2: position = Vector3(-along + tangent_jitter, 0.0, half_extent + radial_jitter)
				_: position = Vector3(-half_extent + radial_jitter, 0.0, -along + tangent_jitter)
			# FarTreeCluster is an 80x34m tree line. Keep its local X long axis
			# tangent to the map edge so it cannot extend inward like a radial slab.
			var tangent_yaw := 0.0 if side == 0 or side == 2 else PI * 0.5
			if _rng.randi_range(0, 1) == 1:
				tangent_yaw += PI
			tangent_yaw += _rng.randf_range(-0.035, 0.035)
			transforms.append(_placement_transform(
				position, _rng.randf_range(0.92, 1.08), tangent_yaw
			))
	return transforms


func _make_sparse_rock_ring(half_extent: float, count: int, phase: float) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	for index in range(maxi(0, count)):
		var perimeter_ratio := fposmod((float(index) + phase) / float(maxi(1, count)), 1.0)
		var side_value := perimeter_ratio * 4.0
		var side := floori(side_value)
		var along := lerpf(-half_extent, half_extent, side_value - float(side))
		var position := Vector3.ZERO
		match side:
			0: position = Vector3(along, 0.0, -half_extent)
			1: position = Vector3(half_extent, 0.0, along)
			2: position = Vector3(-along, 0.0, half_extent)
			_: position = Vector3(-half_extent, 0.0, -along)
		position.x += _rng.randf_range(-14.0, 14.0)
		position.z += _rng.randf_range(-14.0, 14.0)
		transforms.append(_placement_transform(position, _rng.randf_range(0.9, 1.12)))
	return transforms


func _make_sparse_far_grass(count: int, scale_range: Vector2) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	var inner_extent := maxf(core_map_size.x * 0.5, far_grass_inner_half_extent)
	var outer_extent := maxf(inner_extent, far_grass_outer_half_extent)
	var minimum_scale := minf(scale_range.x, scale_range.y)
	var maximum_scale := maxf(scale_range.x, scale_range.y)
	while transforms.size() < maxi(0, count):
		var position := Vector3(
			_rng.randf_range(-outer_extent, outer_extent),
			FAR_GRASS_SURFACE_Y,
			_rng.randf_range(-outer_extent, outer_extent)
		)
		if maxf(absf(position.x), absf(position.z)) < inner_extent:
			continue
		var scale_value := _rng.randf_range(minimum_scale, maximum_scale)
		transforms.append(Transform3D(
			Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(Vector3.ONE * scale_value),
			position
		))
	return transforms


func _farm_group_layouts() -> Array[Dictionary]:
	return [
		{"position": Vector3(-190, 0, -390), "size": Vector2i(2, 2), "yaw": 0.0, "buildings": 2},
		{"position": Vector3(115, 0, -455), "size": Vector2i(2, 3), "yaw": 0.0, "buildings": 3},
		{"position": Vector3(405, 0, -165), "size": Vector2i(2, 2), "yaw": PI * 0.5, "buildings": 2},
		{"position": Vector3(470, 0, 175), "size": Vector2i(3, 2), "yaw": PI * 0.5, "buildings": 3},
		{"position": Vector3(175, 0, 410), "size": Vector2i(2, 2), "yaw": PI, "buildings": 2},
		{"position": Vector3(-135, 0, 470), "size": Vector2i(3, 2), "yaw": PI, "buildings": 3},
		{"position": Vector3(-415, 0, 145), "size": Vector2i(2, 2), "yaw": -PI * 0.5, "buildings": 2},
		{"position": Vector3(-460, 0, -190), "size": Vector2i(2, 3), "yaw": -PI * 0.5, "buildings": 3},
	]


func _make_farm_patches(groups: Array[Dictionary]) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	for group: Dictionary in groups:
		var size: Vector2i = group.get("size", Vector2i(3, 4))
		var yaw := float(group.get("yaw", 0.0))
		var group_position: Vector3 = group.get("position", Vector3.ZERO)
		group_position.y = FAR_TILE_SURFACE_Y
		var group_transform := Transform3D(Basis(Vector3.UP, yaw), group_position)
		for row in range(size.y):
			for column in range(size.x):
				var local_position := Vector3(
					(float(column) - float(size.x - 1) * 0.5) * farm_patch_spacing.x,
					0.0,
					(float(row) - float(size.y - 1) * 0.5) * farm_patch_spacing.y
				)
				transforms.append(group_transform * Transform3D(Basis.IDENTITY, local_position))
	return transforms


func _make_farm_buildings(groups: Array[Dictionary]) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	for group: Dictionary in groups:
		var size: Vector2i = group.get("size", Vector2i(3, 4))
		var count := int(group.get("buildings", 3))
		var yaw := float(group.get("yaw", 0.0))
		var group_transform := Transform3D(Basis(Vector3.UP, yaw), group.get("position", Vector3.ZERO))
		var field_edge := float(size.y) * farm_patch_spacing.y * 0.5 + 48.0
		for index in range(count):
			var local_position := Vector3(
				(float(index) - float(count - 1) * 0.5) * 82.0 + _rng.randf_range(-4.0, 4.0),
				0.0,
				field_edge + _rng.randf_range(-5.0, 5.0)
			)
			var position := group_transform * local_position
			var quarter_turn := float(_rng.randi_range(0, 3)) * PI * 0.5
			transforms.append(_placement_transform(
				position,
				_rng.randf_range(0.9, 1.12),
				yaw + quarter_turn + _rng.randf_range(-0.08, 0.08)
			))
	return transforms


func _placement_transform(position: Vector3, scale_value: float, yaw := NAN) -> Transform3D:
	var resolved_yaw := _rng.randf_range(0.0, TAU) if is_nan(yaw) else yaw
	position.y = FAR_TILE_SURFACE_Y
	return Transform3D(Basis(Vector3.UP, resolved_yaw).scaled(Vector3.ONE * scale_value), position)


func _create_scene_multimeshes(
	scene: PackedScene,
	placements: Array[Transform3D],
	prefix: String,
	instance_visibility_distance := -1.0
) -> void:
	if scene == null or placements.is_empty():
		return
	var source := scene.instantiate()
	var components: Array[Dictionary] = []
	_collect_mesh_components(source, Transform3D.IDENTITY, components)
	source.free()
	for component_index in range(components.size()):
		var component := components[component_index]
		var mesh: Mesh = component.get("mesh", null)
		if mesh == null:
			continue
		mesh = _replace_distant_earth_material(mesh)
		var component_transform: Transform3D = component.get("transform", Transform3D.IDENTITY)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = placements.size()
		for index in range(placements.size()):
			multimesh.set_instance_transform(index, placements[index] * component_transform)
		var instance := MultiMeshInstance3D.new()
		instance.name = "%sMesh%d" % [prefix, component_index]
		instance.multimesh = multimesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = (
			visibility_distance
			if instance_visibility_distance <= 0.0
			else instance_visibility_distance
		)
		add_child(instance)


func _replace_distant_earth_material(source_mesh: Mesh) -> Mesh:
	if source_mesh == null or _grass_material == null:
		return source_mesh
	var result := source_mesh.duplicate() as Mesh
	if result == null:
		return source_mesh
	for surface_index in range(result.get_surface_count()):
		var surface_material := result.surface_get_material(surface_index)
		if surface_material == null:
			continue
		if surface_material.resource_name.to_lower().contains("distant_earth"):
			result.surface_set_material(surface_index, _grass_material)
	return result


func _collect_mesh_components(node: Node, parent_transform: Transform3D, components: Array[Dictionary]) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		components.append({"mesh": (node as MeshInstance3D).mesh, "transform": current_transform})
	for child: Node in node.get_children():
		_collect_mesh_components(child, current_transform, components)
