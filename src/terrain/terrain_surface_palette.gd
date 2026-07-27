@tool
class_name TerrainSurfacePalette
extends Resource

@export_range(0, 255, 1) var default_surface_id: int = 0
@export var surfaces: Array[TerrainSurfaceDefinition] = []


func get_surface(surface_id: int) -> TerrainSurfaceDefinition:
	for surface in surfaces:
		if surface != null and surface.surface_id == surface_id:
			return surface
	return null


func get_default_surface() -> TerrainSurfaceDefinition:
	var surface := get_surface(default_surface_id)
	if surface != null:
		return surface
	for candidate in surfaces:
		if candidate != null:
			return candidate
	return null


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var used_ids: Dictionary = {}
	for surface in surfaces:
		if surface == null:
			errors.append("Surface palette contains an empty entry.")
			continue
		if used_ids.has(surface.surface_id):
			errors.append("Surface ID %d is used more than once." % surface.surface_id)
		used_ids[surface.surface_id] = true
	if not used_ids.has(default_surface_id):
		errors.append("Default surface ID %d is not defined." % default_surface_id)
	return errors


func create_lookup_texture() -> ImageTexture:
	var fallback := get_default_surface()
	var fallback_color := Color(0.35, 0.65, 0.3, 0.95)
	if fallback != null:
		fallback_color = Color(fallback.color.r, fallback.color.g, fallback.color.b, fallback.roughness)

	var image := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	image.fill(fallback_color)
	for surface in surfaces:
		if surface == null:
			continue
		image.set_pixel(
			surface.surface_id,
			0,
			Color(surface.color.r, surface.color.g, surface.color.b, surface.roughness)
		)
	return ImageTexture.create_from_image(image)
