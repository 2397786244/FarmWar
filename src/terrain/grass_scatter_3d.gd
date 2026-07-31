@tool
class_name GrassScatter3D
extends Node3D

const GrassScatterBakeDataScript = preload("res://src/terrain/grass_scatter_bake_data.gd")
const VALUES_PER_INSTANCE := 4
const SMALL_SPECIES_SALT := 1103515245
const TALL_SPECIES_SALT := 214013

@export_group("Source Models")
@export var small_grass_scene: PackedScene
@export var tall_grass_scene: PackedScene

@export_group("Terrain")
@export var surface_mask: Texture2D
@export var grass_surface_id := 0
@export var terrain_center := Vector2.ZERO
@export var terrain_size := Vector2(256.0, 256.0)
@export var ground_height := 0.51
@export_range(8.0, 64.0, 1.0) var chunk_size := 32.0
@export_range(0.0, 1.0, 0.01) var maximum_non_grass_blend := 0.02

@export_group("Distribution")
@export var random_seed := 72451
@export_range(0.0, 2.0, 0.01, "or_greater") var small_density := 0.35
@export_range(0.0, 1.0, 0.01, "or_greater") var tall_density := 0.05
@export var small_scale_range := Vector2(0.85, 1.15)
@export var tall_scale_range := Vector2(0.85, 1.20)

@export_group("Rendering")
@export_range(1.0, 500.0, 1.0) var small_visibility_distance := 60.0
@export_range(1.0, 500.0, 1.0) var tall_visibility_distance := 80.0
@export_file("*.res") var bake_output_path := "res://worlds/creston_town/creston_town_grass_scatter.res"
@export var bake_data: GrassScatterBakeData

@export_group("Editor Actions")
@export_tool_button("Bake Grass") var bake_button: Callable = bake_grass
@export_tool_button("Rebuild Preview") var rebuild_button: Callable = rebuild_preview
@export_tool_button("Clear Preview") var clear_button: Callable = clear_preview
@export_tool_button("Randomize Seed") var randomize_button: Callable = randomize_seed

var _generated_root: Node3D


func _ready() -> void:
	call_deferred("rebuild_preview")


func bake_grass() -> void:
	var generated := _generate_bake_data()
	if generated == null:
		return
	bake_data = generated
	if not bake_output_path.is_empty():
		var error := ResourceSaver.save(generated, bake_output_path, ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			push_error("GrassScatter3D: could not save %s (error %d)." % [bake_output_path, error])
			return
		bake_data = ResourceLoader.load(
			bake_output_path,
			"",
			ResourceLoader.CACHE_MODE_REPLACE
		) as GrassScatterBakeData
	_build_multimeshes(bake_data)
	print("GrassScatter3D: baked %d small and %d tall grass instances." % [
		_count_instances(bake_data.small_chunks),
		_count_instances(bake_data.tall_chunks),
	])


func rebuild_preview() -> void:
	var data := bake_data
	if data == null and not bake_output_path.is_empty() and ResourceLoader.exists(bake_output_path):
		data = ResourceLoader.load(bake_output_path) as GrassScatterBakeData
	if data == null or not data.is_compatible(terrain_size, chunk_size, random_seed):
		data = _generate_bake_data()
	_build_multimeshes(data)


func clear_preview() -> void:
	_ensure_generated_root()
	for child in _generated_root.get_children():
		child.free()


func randomize_seed() -> void:
	random_seed = randi()
	bake_grass()


func _generate_bake_data() -> GrassScatterBakeData:
	if surface_mask == null:
		push_error("GrassScatter3D: surface_mask is not assigned.")
		return null
	if terrain_size.x <= 0.0 or terrain_size.y <= 0.0 or chunk_size <= 0.0:
		push_error("GrassScatter3D: terrain and chunk sizes must be positive.")
		return null
	var mask_image := surface_mask.get_image()
	if mask_image == null or mask_image.is_empty():
		push_error("GrassScatter3D: surface_mask has no readable image data.")
		return null

	var data := GrassScatterBakeDataScript.new() as GrassScatterBakeData
	data.terrain_size = terrain_size
	data.chunk_size = chunk_size
	data.random_seed = random_seed
	var chunk_counts := Vector2i(
		int(ceil(terrain_size.x / chunk_size)),
		int(ceil(terrain_size.y / chunk_size))
	)
	for chunk_z in range(chunk_counts.y):
		for chunk_x in range(chunk_counts.x):
			var coordinate := Vector2i(chunk_x, chunk_z)
			var small_values := _scatter_chunk(
				coordinate, chunk_counts, small_density, small_scale_range,
				SMALL_SPECIES_SALT, mask_image
			)
			var tall_values := _scatter_chunk(
				coordinate, chunk_counts, tall_density, tall_scale_range,
				TALL_SPECIES_SALT, mask_image
			)
			var key := _chunk_key(coordinate)
			if not small_values.is_empty():
				data.small_chunks[key] = small_values
			if not tall_values.is_empty():
				data.tall_chunks[key] = tall_values
	return data


func _scatter_chunk(
	coordinate: Vector2i,
	chunk_counts: Vector2i,
	density: float,
	scale_range: Vector2,
	species_salt: int,
	mask_image: Image
) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	if density <= 0.0:
		return values
	var terrain_origin := terrain_center - terrain_size * 0.5
	var chunk_min := terrain_origin + Vector2(coordinate) * chunk_size
	var chunk_max := Vector2(
		minf(chunk_min.x + chunk_size, terrain_origin.x + terrain_size.x),
		minf(chunk_min.y + chunk_size, terrain_origin.y + terrain_size.y)
	)
	var chunk_extent := chunk_max - chunk_min
	var candidate_count := int(round(chunk_extent.x * chunk_extent.y * density))
	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(coordinate, chunk_counts, species_salt)
	for _candidate in range(candidate_count):
		var world_xz := Vector2(
			rng.randf_range(chunk_min.x, chunk_max.x),
			rng.randf_range(chunk_min.y, chunk_max.y)
		)
		if not _is_grass_surface(world_xz, mask_image):
			continue
		var chunk_center := (chunk_min + chunk_max) * 0.5
		values.append(world_xz.x - chunk_center.x)
		values.append(world_xz.y - chunk_center.y)
		values.append(rng.randf_range(-PI, PI))
		values.append(rng.randf_range(minf(scale_range.x, scale_range.y), maxf(scale_range.x, scale_range.y)))
	return values


func _is_grass_surface(world_xz: Vector2, mask_image: Image) -> bool:
	var terrain_origin := terrain_center - terrain_size * 0.5
	var uv := (world_xz - terrain_origin) / terrain_size
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return false
	var pixel := Vector2i(
		clampi(int(floor(uv.x * float(mask_image.get_width()))), 0, mask_image.get_width() - 1),
		clampi(int(floor(uv.y * float(mask_image.get_height()))), 0, mask_image.get_height() - 1)
	)
	var mask_value := mask_image.get_pixelv(pixel)
	var base_id := int(round(mask_value.r * 255.0))
	var overlay_id := int(round(mask_value.g * 255.0))
	if base_id != grass_surface_id:
		return false
	return overlay_id == grass_surface_id or mask_value.b <= maximum_non_grass_blend


func _build_multimeshes(data: GrassScatterBakeData) -> void:
	clear_preview()
	if data == null:
		return
	_build_species("Small", small_grass_scene, data.small_chunks, small_visibility_distance)
	_build_species("Tall", tall_grass_scene, data.tall_chunks, tall_visibility_distance)


func _build_species(
	species_name: String,
	source_scene: PackedScene,
	chunks: Dictionary,
	visibility_distance: float
) -> void:
	if source_scene == null:
		push_warning("GrassScatter3D: %s grass scene is not assigned." % species_name)
		return
	var source_root := source_scene.instantiate() as Node3D
	if source_root == null:
		push_error("GrassScatter3D: %s grass scene must have a Node3D root." % species_name)
		return
	var mesh_sources: Array[MeshInstance3D] = []
	_collect_mesh_sources(source_root, mesh_sources)
	if mesh_sources.is_empty():
		push_error("GrassScatter3D: %s grass scene contains no MeshInstance3D." % species_name)
		source_root.free()
		return

	for key: String in chunks:
		var values := chunks[key] as PackedFloat32Array
		var instance_count := values.size() / VALUES_PER_INSTANCE
		if instance_count <= 0:
			continue
		var coordinate := _parse_chunk_key(key)
		var chunk_center := _chunk_center(coordinate)
		for mesh_index in range(mesh_sources.size()):
			var source := mesh_sources[mesh_index]
			if source.mesh == null:
				continue
			var source_transform := _relative_transform(source, source_root)
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = source.mesh
			multi.instance_count = instance_count
			for index in range(instance_count):
				var value_index := index * VALUES_PER_INSTANCE
				var scale_value := values[value_index + 3]
				var transform := Transform3D(
					Basis(Vector3.UP, values[value_index + 2]).scaled(Vector3.ONE * scale_value),
					Vector3(values[value_index], ground_height, values[value_index + 1])
				)
				multi.set_instance_transform(index, transform * source_transform)
			var instance := MultiMeshInstance3D.new()
			instance.name = "%s_%s_%d" % [species_name, key.replace(":", "_"), mesh_index]
			instance.position = Vector3(chunk_center.x, 0.0, chunk_center.y)
			instance.multimesh = multi
			instance.material_override = source.material_override
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_end = visibility_distance
			instance.extra_cull_margin = 2.0
			_generated_root.add_child(instance)
	source_root.free()


func _ensure_generated_root() -> void:
	_generated_root = get_node_or_null("GeneratedGrass") as Node3D
	if _generated_root == null:
		_generated_root = Node3D.new()
		_generated_root.name = "GeneratedGrass"
		add_child(_generated_root, false, Node.INTERNAL_MODE_BACK)


func _collect_mesh_sources(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_sources(child, result)


func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := node.transform
	var cursor := node.get_parent() as Node3D
	while cursor != null and cursor != root:
		result = cursor.transform * result
		cursor = cursor.get_parent() as Node3D
	return result


func _chunk_seed(coordinate: Vector2i, chunk_counts: Vector2i, species_salt: int) -> int:
	return abs(random_seed * 1664525 + species_salt + coordinate.x * 73856093 \
		+ coordinate.y * 19349663 + chunk_counts.x * 83492791)


func _chunk_key(coordinate: Vector2i) -> String:
	return "%d:%d" % [coordinate.x, coordinate.y]


func _parse_chunk_key(key: String) -> Vector2i:
	var parts := key.split(":")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i.ZERO


func _chunk_center(coordinate: Vector2i) -> Vector2:
	var terrain_origin := terrain_center - terrain_size * 0.5
	var chunk_min := terrain_origin + Vector2(coordinate) * chunk_size
	var chunk_max := Vector2(
		minf(chunk_min.x + chunk_size, terrain_origin.x + terrain_size.x),
		minf(chunk_min.y + chunk_size, terrain_origin.y + terrain_size.y)
	)
	return (chunk_min + chunk_max) * 0.5


func _count_instances(chunks: Dictionary) -> int:
	var count := 0
	for values: PackedFloat32Array in chunks.values():
		count += values.size() / VALUES_PER_INSTANCE
	return count
