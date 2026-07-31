@tool
class_name TerrainSurfaceBaker
extends Node3D

@export var palette: TerrainSurfacePalette
@export var target_mesh: NodePath
@export var area_root: NodePath
@export var terrain_center := Vector2.ZERO
@export var terrain_size := Vector2(512.0, 512.0)
@export_range(128, 4096, 128) var mask_resolution: int = 2048
@export_file("*.res") var mask_output_path := "res://worlds/creston_town/creston_town_surface_mask.res"
@export_file("*.res") var palette_output_path := "res://worlds/creston_town/creston_town_surface_palette_lookup.res"
@export_tool_button("Bake Terrain Mask") var bake_button: Callable = bake_surface_mask


func bake_surface_mask() -> void:
	if palette == null:
		push_error("TerrainSurfaceBaker: palette is not assigned.")
		return
	for validation_error in palette.validate():
		push_error("TerrainSurfaceBaker: %s" % validation_error)
		return
	if terrain_size.x <= 0.0 or terrain_size.y <= 0.0:
		push_error("TerrainSurfaceBaker: terrain_size must be positive.")
		return

	var default_encoded := float(palette.default_surface_id) / 255.0
	var mask_image := Image.create(mask_resolution, mask_resolution, false, Image.FORMAT_RGBA8)
	mask_image.fill(Color(default_encoded, default_encoded, 0.0, 0.0))

	var areas := _collect_surface_areas()
	areas.sort_custom(func(a: SurfaceArea3D, b: SurfaceArea3D) -> bool: return a.priority < b.priority)
	for area in areas:
		_paint_area(mask_image, area)

	var mask_texture := ImageTexture.create_from_image(mask_image)
	var mask_error := ResourceSaver.save(mask_texture, mask_output_path, ResourceSaver.FLAG_COMPRESS)
	if mask_error != OK:
		push_error("TerrainSurfaceBaker: could not save mask to %s (error %d)." % [mask_output_path, mask_error])
		return

	var palette_texture := palette.create_lookup_texture()
	var palette_error := ResourceSaver.save(palette_texture, palette_output_path, ResourceSaver.FLAG_COMPRESS)
	if palette_error != OK:
		push_error("TerrainSurfaceBaker: could not save palette lookup to %s (error %d)." % [palette_output_path, palette_error])
		return

	var saved_mask := ResourceLoader.load(
		mask_output_path,
		"",
		ResourceLoader.CACHE_MODE_REPLACE
	) as Texture2D
	var saved_palette := ResourceLoader.load(
		palette_output_path,
		"",
		ResourceLoader.CACHE_MODE_REPLACE
	) as Texture2D
	_apply_material_parameters(saved_mask, saved_palette)
	print("TerrainSurfaceBaker: baked %d surface areas to %s" % [areas.size(), mask_output_path])


func _collect_surface_areas() -> Array[SurfaceArea3D]:
	var result: Array[SurfaceArea3D] = []
	var root := get_node_or_null(area_root)
	if root == null:
		push_error("TerrainSurfaceBaker: area_root does not point to a node.")
		return result
	_collect_surface_areas_recursive(root, result)
	return result


func _collect_surface_areas_recursive(node: Node, result: Array[SurfaceArea3D]) -> void:
	if node is SurfaceArea3D and (node as SurfaceArea3D).area_enabled:
		result.append(node as SurfaceArea3D)
	for child in node.get_children():
		_collect_surface_areas_recursive(child, result)


func _paint_area(image: Image, area: SurfaceArea3D) -> void:
	var points := area.get_world_points()
	var minimum_points := 3 if area.draw_mode == SurfaceArea3D.DrawMode.CLOSED_AREA else 2
	if points.size() < minimum_points:
		push_warning("TerrainSurfaceBaker: %s needs at least %d curve points." % [area.name, minimum_points])
		return

	var margin := area.edge_softness
	if area.draw_mode == SurfaceArea3D.DrawMode.PATH_STROKE:
		margin += area.width * 0.5
	var bounds := _calculate_bounds(points, margin)
	var minimum_pixel := _world_to_pixel(bounds.position)
	var maximum_pixel := _world_to_pixel(bounds.end)
	var min_x := clampi(int(floor(minimum_pixel.x)), 0, mask_resolution - 1)
	var min_y := clampi(int(floor(minimum_pixel.y)), 0, mask_resolution - 1)
	var max_x := clampi(int(ceil(maximum_pixel.x)), 0, mask_resolution - 1)
	var max_y := clampi(int(ceil(maximum_pixel.y)), 0, mask_resolution - 1)

	for pixel_y in range(min_y, max_y + 1):
		for pixel_x in range(min_x, max_x + 1):
			var world_point := _pixel_to_world(Vector2i(pixel_x, pixel_y))
			var coverage := _get_coverage(world_point, points, area)
			if coverage <= 0.0:
				continue
			_write_surface_pixel(image, pixel_x, pixel_y, area.surface_id, coverage)


func _get_coverage(point: Vector2, points: PackedVector2Array, area: SurfaceArea3D) -> float:
	var distance := _distance_to_polyline(point, points, area.draw_mode == SurfaceArea3D.DrawMode.CLOSED_AREA)
	if area.draw_mode == SurfaceArea3D.DrawMode.CLOSED_AREA:
		if Geometry2D.is_point_in_polygon(point, points):
			return 1.0
		return _soft_coverage(distance, 0.0, area.edge_softness)

	var half_width := area.width * 0.5
	if distance <= half_width:
		return 1.0
	return _soft_coverage(distance, half_width, area.edge_softness)


func _soft_coverage(distance: float, solid_distance: float, softness: float) -> float:
	if softness <= 0.0:
		return 0.0
	var amount := clampf((distance - solid_distance) / softness, 0.0, 1.0)
	amount = amount * amount * (3.0 - 2.0 * amount)
	return 1.0 - amount


func _distance_to_polyline(point: Vector2, points: PackedVector2Array, closed: bool) -> float:
	var closest := INF
	var segment_count := points.size() if closed else points.size() - 1
	for index in range(segment_count):
		var start := points[index]
		var finish := points[(index + 1) % points.size()]
		closest = minf(closest, _distance_to_segment(point, start, finish))
	return closest


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(start)
	var amount := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * amount)


func _write_surface_pixel(image: Image, x: int, y: int, surface_id: int, coverage: float) -> void:
	var current := image.get_pixel(x, y)
	var current_id := int(round(current.g * 255.0)) if current.b >= 0.5 else int(round(current.r * 255.0))
	var encoded_id := float(surface_id) / 255.0
	if coverage >= 0.999:
		image.set_pixel(x, y, Color(encoded_id, encoded_id, 0.0, current.a))
	else:
		image.set_pixel(x, y, Color(float(current_id) / 255.0, encoded_id, coverage, current.a))


func _calculate_bounds(points: PackedVector2Array, margin: float) -> Rect2:
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum - Vector2.ONE * margin, maximum - minimum + Vector2.ONE * margin * 2.0)


func _world_to_pixel(world_position: Vector2) -> Vector2:
	var origin := terrain_center - terrain_size * 0.5
	return (world_position - origin) / terrain_size * float(mask_resolution)


func _pixel_to_world(pixel: Vector2i) -> Vector2:
	var origin := terrain_center - terrain_size * 0.5
	var uv := (Vector2(pixel) + Vector2(0.5, 0.5)) / float(mask_resolution)
	return origin + uv * terrain_size


func _apply_material_parameters(mask_texture: Texture2D, palette_texture: Texture2D) -> void:
	var mesh_instance := get_node_or_null(target_mesh) as MeshInstance3D
	if mesh_instance == null:
		push_error("TerrainSurfaceBaker: target_mesh does not point to a MeshInstance3D.")
		return
	var material := mesh_instance.get_active_material(0) as ShaderMaterial
	if material == null:
		push_error("TerrainSurfaceBaker: target mesh does not use a ShaderMaterial.")
		return
	material.set_shader_parameter("surface_mask", mask_texture)
	material.set_shader_parameter("surface_palette", palette_texture)
	material.set_shader_parameter("terrain_origin", terrain_center - terrain_size * 0.5)
	material.set_shader_parameter("terrain_size", terrain_size)
