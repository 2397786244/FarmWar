@tool
class_name TerrainSurfaceBaker
extends Node3D

const SurfaceBlend = preload("res://src/terrain/terrain_surface_blend.gd")

@export var palette: TerrainSurfacePalette
@export var target_mesh: NodePath
@export var area_root: NodePath
@export var terrain_center := Vector2.ZERO
@export var terrain_size := Vector2(512.0, 512.0)
@export_range(128, 4096, 128) var mask_resolution: int = 2048
@export_file("*.res") var id_map_output_path := "res://worlds/creston_town/creston_town_surface_ids.res"
@export_file("*.res") var weight_map_output_path := "res://worlds/creston_town/creston_town_surface_weights.res"
@export_file("*.res") var render_output_path := "res://worlds/creston_town/creston_town_surface_render.res"
@export_file("*.res") var palette_output_path := "res://worlds/creston_town/creston_town_surface_palette_lookup.res"
@export var surface_blend_noise_seed := 72451
@export_range(0.01, 1.0, 0.01) var surface_blend_noise_frequency := 0.18
@export_tool_button("Bake Terrain Surfaces") var bake_button: Callable = bake_surface_mask

var _edge_noise: FastNoiseLite


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

	var id_image := Image.create(mask_resolution, mask_resolution, false, Image.FORMAT_RGBA8)
	var weight_image := Image.create(mask_resolution, mask_resolution, false, Image.FORMAT_RGBA8)
	id_image.fill(SurfaceBlend.make_default_ids(palette.default_surface_id))
	weight_image.fill(SurfaceBlend.make_default_weights())
	_edge_noise = FastNoiseLite.new()
	_edge_noise.seed = surface_blend_noise_seed
	_edge_noise.frequency = surface_blend_noise_frequency
	_edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	var areas := _collect_surface_areas()
	areas.sort_custom(func(a: SurfaceArea3D, b: SurfaceArea3D) -> bool: return a.priority < b.priority)
	for area in areas:
		_paint_area(id_image, weight_image, area)

	var palette_texture := palette.create_lookup_texture()
	var render_image := _build_render_image(id_image, weight_image, palette_texture.get_image())
	if not _save_image_texture(id_image, id_map_output_path, "surface ID map"):
		return
	if not _save_image_texture(weight_image, weight_map_output_path, "surface weight map"):
		return
	if not _save_image_texture(render_image, render_output_path, "surface render map"):
		return
	if not _save_texture(palette_texture, palette_output_path, "palette lookup"):
		return

	var saved_render := ResourceLoader.load(
		render_output_path,
		"",
		ResourceLoader.CACHE_MODE_REPLACE
	) as Texture2D
	_apply_material_parameters(saved_render)
	print("TerrainSurfaceBaker: baked %d surface areas to %s" % [areas.size(), render_output_path])


func _save_image_texture(image: Image, path: String, label: String) -> bool:
	return _save_texture(ImageTexture.create_from_image(image), path, label)


func _save_texture(texture: Texture2D, path: String, label: String) -> bool:
	var error := ResourceSaver.save(texture, path, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("TerrainSurfaceBaker: could not save %s to %s (error %d)." % [label, path, error])
		return false
	return true


func _build_render_image(id_image: Image, weight_image: Image, palette_image: Image) -> Image:
	var render_image := Image.create(
		id_image.get_width(), id_image.get_height(), false, Image.FORMAT_RGBA8
	)
	for y in range(id_image.get_height()):
		for x in range(id_image.get_width()):
			render_image.set_pixel(
				x,
				y,
				SurfaceBlend.resolve_color(
					id_image.get_pixel(x, y),
					weight_image.get_pixel(x, y),
					palette_image,
					palette.default_surface_id
				)
			)
	return render_image


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


func _paint_area(id_image: Image, weight_image: Image, area: SurfaceArea3D) -> void:
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
			if coverage > 0.0 and coverage < 1.0 and area.edge_variation > 0.0:
				coverage = clampf(
					coverage + _edge_noise.get_noise_2d(world_point.x, world_point.y) * area.edge_variation,
					0.0,
					1.0
				)
			if coverage <= 0.0:
				continue
			var painted := SurfaceBlend.paint_encoded(
				id_image.get_pixel(pixel_x, pixel_y),
				weight_image.get_pixel(pixel_x, pixel_y),
				area.surface_id,
				coverage,
				palette.default_surface_id
			)
			id_image.set_pixel(pixel_x, pixel_y, painted["ids"] as Color)
			weight_image.set_pixel(pixel_x, pixel_y, painted["weights"] as Color)


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


func _apply_material_parameters(render_texture: Texture2D) -> void:
	var mesh_instance := get_node_or_null(target_mesh) as MeshInstance3D
	if mesh_instance == null:
		push_error("TerrainSurfaceBaker: target_mesh does not point to a MeshInstance3D.")
		return
	var material := mesh_instance.get_active_material(0) as ShaderMaterial
	if material == null:
		push_error("TerrainSurfaceBaker: target mesh does not use a ShaderMaterial.")
		return
	material.set_shader_parameter("surface_render", render_texture)
	material.set_shader_parameter("terrain_origin", terrain_center - terrain_size * 0.5)
	material.set_shader_parameter("terrain_size", terrain_size)
