extends Node

const SurfaceBlend = preload("res://src/terrain/terrain_surface_blend.gd")
const MAP_EDITOR_SCRIPT = preload("res://src/farmwar_runtime_map_editor.gd")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var ids := SurfaceBlend.make_default_ids(0)
	var weights := SurfaceBlend.make_default_weights()
	for surface_id in [1, 2, 3]:
		var painted := SurfaceBlend.paint_encoded(ids, weights, surface_id, 0.25, 0)
		ids = painted["ids"] as Color
		weights = painted["weights"] as Color

	var decoded_ids := SurfaceBlend.decode_ids(ids)
	var decoded_weights := SurfaceBlend.decode_weights(weights)
	for expected_id in [0, 1, 2, 3]:
		_check(expected_id in decoded_ids, "four distinct surfaces remain addressable")
	_check(absf(_weight_sum(decoded_weights) - 1.0) <= 0.01, "four weights stay normalized")

	var fifth := SurfaceBlend.paint_encoded(ids, weights, 4, 0.2, 0)
	var fifth_ids := SurfaceBlend.decode_ids(fifth["ids"] as Color)
	var fifth_weights := SurfaceBlend.decode_weights(fifth["weights"] as Color)
	_check(4 in fifth_ids, "a fifth painted surface replaces one weakest slot")
	_check(_active_layer_count(fifth_weights) <= 4, "no pixel stores more than four active layers")
	_check(absf(_weight_sum(fifth_weights) - 1.0) <= 0.01, "fifth-surface replacement remains normalized")

	var remapped := SurfaceBlend.remap_encoded(
		fifth["ids"] as Color,
		fifth["weights"] as Color,
		4,
		0,
		0
	)
	_check(
		SurfaceBlend.get_surface_weight(
			remapped["ids"] as Color,
			remapped["weights"] as Color,
			4
		) <= 0.0001,
		"removing a palette entry eliminates its indexed contribution"
	)

	var palette := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	palette.fill(Color(0.1, 0.2, 0.3, 0.9))
	palette.set_pixel(0, 0, Color(1.0, 0.0, 0.0, 0.8))
	palette.set_pixel(1, 0, Color(0.0, 1.0, 0.0, 1.0))
	var mixed_ids := Color(0.0, 1.0 / 255.0, 0.0, 0.0)
	var mixed_weights := Color(0.25, 0.75, 0.0, 0.0)
	var resolved := SurfaceBlend.resolve_color(mixed_ids, mixed_weights, palette, 0)
	_check(
		Vector4(resolved.r, resolved.g, resolved.b, resolved.a).distance_to(
			Vector4(0.25, 0.75, 0.0, 0.95)
		) <= 0.01,
		"render color and roughness use all indexed weights"
	)

	var shader_source := FileAccess.get_file_as_string("res://src/terrain/terrain_surface.gdshader")
	_check("surface_render" in shader_source, "terrain shader reads the derived render map")
	_check(not "surface_mask" in shader_source, "terrain shader no longer decodes the legacy two-layer mask")
	_validate_grass_weight_lookup()
	_validate_editor_edge_noise()

	for folder in ["coop_test", "xuanchuan2", "xuanchuanmap"]:
		_validate_builtin_package(folder)
	for scene_path in [
		"res://worlds/coop_test/coop_test.tscn",
		"res://worlds/xuanchuan2/xuanchuan2.tscn",
		"res://worlds/xuanchuanmap/xuanchuanmap.tscn",
		"res://worlds/xuanchuanmap/newfarmmap.tscn",
	]:
		_check(load(scene_path) is PackedScene, "%s loads with four-layer terrain resources" % scene_path)

	if failures.is_empty():
		print("TerrainSurfaceBlendValidation: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TerrainSurfaceBlendValidation: %s" % failure)
		get_tree().quit(1)


func _validate_builtin_package(folder: String) -> void:
	var base := "res://worlds/%s" % folder
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("map.json")))
	_check(manifest is Dictionary, "%s manifest parses" % folder)
	if not manifest is Dictionary:
		return
	_check(int((manifest as Dictionary).get("format_version", 0)) == 6, "%s uses map format 6" % folder)
	for file_name in ["surface_ids.png", "surface_weights.png", "surface_render.png"]:
		var texture := load(base.path_join(file_name)) as Texture2D
		_check(
			texture != null and texture.get_width() > 0 and texture.get_height() > 0,
			"%s contains %s" % [folder, file_name]
		)


func _validate_grass_weight_lookup() -> void:
	var scatter := GrassScatter3D.new()
	scatter.terrain_size = Vector2(2.0, 2.0)
	scatter.terrain_center = Vector2.ZERO
	scatter.grass_surface_id = 0
	scatter.maximum_non_grass_blend = 0.02
	var id_image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var weight_image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	id_image.set_pixel(0, 0, Color(0.0, 1.0 / 255.0, 0.0, 0.0))
	weight_image.set_pixel(0, 0, Color(0.98, 0.02, 0.0, 0.0))
	_check(
		scatter._is_grass_surface(Vector2.ZERO, id_image, weight_image),
		"grass scatter accepts the sum of grass weights at its configured threshold"
	)
	weight_image.set_pixel(0, 0, Color(0.90, 0.10, 0.0, 0.0))
	_check(
		not scatter._is_grass_surface(Vector2.ZERO, id_image, weight_image),
		"grass scatter rejects pixels with too much non-grass weight"
	)
	scatter.free()


func _validate_editor_edge_noise() -> void:
	var editor := MAP_EDITOR_SCRIPT.new() as Node
	editor.call("_configure_surface_edge_noise")
	var first := float(editor.call("_surface_brush_falloff", Vector2(7.0, 1.0), Vector2.ZERO))
	var repeated := float(editor.call("_surface_brush_falloff", Vector2(7.0, 1.0), Vector2.ZERO))
	_check(is_equal_approx(first, repeated), "surface edge noise is deterministic for the same seed and world position")
	editor.set("_surface_edge_variation", 0.0)
	var clean := float(editor.call("_surface_brush_falloff", Vector2(4.0, 0.0), Vector2.ZERO))
	_check(is_equal_approx(clean, 0.5), "zero edge variation restores the smooth radial brush")
	var loaded := editor.call(
		"_load_png_image",
		"res://worlds/coop_test/surface_ids.png"
	) as Image
	_check(loaded != null and not loaded.is_empty(), "map editor reads format 6 PNG sidecars from packed bytes")
	editor.free()


func _weight_sum(weights: PackedFloat32Array) -> float:
	var result := 0.0
	for weight in weights:
		result += weight
	return result


func _active_layer_count(weights: PackedFloat32Array) -> int:
	var result := 0
	for weight in weights:
		if weight > 0.0001:
			result += 1
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
