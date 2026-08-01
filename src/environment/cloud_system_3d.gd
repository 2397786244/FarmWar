@tool
class_name CloudSystem3D
extends Node3D

const DEFAULT_CLOUD_COLOR := Color(1.0, 1.0, 1.0, 0.68)
const DEFAULT_SHADOW_COLOR := Color(0.08, 0.12, 0.08, 0.105)

@export_group("Cloud Models")
@export var large_tower_scene: PackedScene
@export var long_wispy_scene: PackedScene
@export var medium_layered_scene: PackedScene
@export var small_puff_scene: PackedScene

@export_group("Distribution")
@export_range(0, 64, 1) var large_tower_count := 48
@export_range(0, 24, 1) var long_wispy_count := 4
@export_range(0, 48, 1) var medium_layered_count := 12
@export_range(0, 64, 1) var small_puff_count := 12
@export var random_seed := 86421
@export var coverage_center := Vector2.ZERO
@export var coverage_size := Vector2(768.0, 768.0)
@export var core_map_size := Vector2(256.0, 256.0)
@export_range(0.0, 1.0, 0.05) var core_cloud_ratio := 0.5
@export var cloud_height_range := Vector2(60.0, 100.0)

@export_group("Motion")
@export var wind_direction := Vector2(1.0, 0.24)
@export_range(0.0, 4.0, 0.05) var wind_speed := 0.55

@export_group("Cloud Shadows")
@export var shadows_enabled := true
@export var shadow_ground_height := 0.56
@export var shadow_color := Color(0.08, 0.12, 0.08, 0.105)
@export_range(20.0, 500.0, 1.0) var shadow_visibility_distance := 180.0

@export_group("Rendering")
@export var cloud_color := Color(1.0, 1.0, 1.0, 0.68)
@export_range(0.0, 1.0, 0.01) var minimum_cloud_opacity := 0.78
@export_range(50.0, 1500.0, 1.0) var cloud_visibility_distance := 900.0
@export_range(0.25, 4.0, 0.05) var cloud_scale_multiplier := 2.0

@export_group("Editor Actions")
@export_tool_button("Rebuild Clouds") var rebuild_button: Callable = rebuild

var _generated_root: Node3D
var _variant_states: Dictionary = {}
var _variant_renderers: Dictionary = {}
var _variant_shadow_lobes: Dictionary = {}
var _shadow_multimesh: MultiMesh
var _cloud_material: StandardMaterial3D
var _shadow_material: StandardMaterial3D
var _daylight_factor := 1.0
var _sun_direction := Vector3(0.0, 1.0, 0.0)
var _rain_strength := 0.0


func _ready() -> void:
	rebuild()
	set_process(not Engine.is_editor_hint())


func _process(delta: float) -> void:
	if wind_speed <= 0.0 or _variant_states.is_empty():
		return
	var direction := wind_direction.normalized()
	if direction.length_squared() <= 0.001:
		return
	for variant_value: Variant in _variant_states.keys():
		var variant_index := int(variant_value)
		var states := _variant_states[variant_index] as Array
		for index in range(states.size()):
			var state := states[index] as Dictionary
			var position := state.get("position", Vector3.ZERO) as Vector3
			position.x += direction.x * wind_speed * float(state.get("speed_scale", 1.0)) * delta
			position.z += direction.y * wind_speed * float(state.get("speed_scale", 1.0)) * delta
			position = _wrap_position(position)
			state["position"] = position
			states[index] = state
		_variant_states[variant_index] = states
	_update_multimeshes()


func rebuild() -> void:
	_ensure_generated_root()
	for child in _generated_root.get_children():
		child.free()
	_variant_states.clear()
	_variant_renderers.clear()
	_variant_shadow_lobes.clear()
	_shadow_multimesh = null
	_shadow_material = null
	_cloud_material = _create_cloud_material()
	if coverage_size.x <= 0.0 or coverage_size.y <= 0.0:
		push_warning("CloudSystem3D: coverage_size must be positive.")
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var configs := _get_variant_configs()
	for variant_index in range(configs.size()):
		var config := configs[variant_index] as Dictionary
		var count := int(config.get("count", 0))
		var scene := config.get("scene") as PackedScene
		_variant_shadow_lobes[variant_index] = config.get("shadow_lobes", [])
		_variant_states[variant_index] = _create_states(config, count, rng)
		_variant_renderers[variant_index] = _create_cloud_renderers(
			variant_index, scene, count
		)
	if shadows_enabled:
		_create_shadow_renderer(_get_total_shadow_count())
	_apply_daylight_materials()
	_update_multimeshes()


func set_daylight_state(daylight: float, sun_direction: Vector3) -> void:
	_daylight_factor = clampf(daylight, 0.0, 1.0)
	if sun_direction.length_squared() > 0.001:
		_sun_direction = sun_direction.normalized()
	_apply_daylight_materials()


func set_weather_state(weather_type: String, intensity := 1.0) -> void:
	_rain_strength = clampf(intensity, 0.0, 1.0) if weather_type == "rain" else 0.0
	_apply_daylight_materials()


func _get_variant_configs() -> Array[Dictionary]:
	return [
		{
			"name": "LargeTower", "scene": large_tower_scene, "count": large_tower_count,
			"scale": Vector2(0.82, 1.12),
			"shadow_lobes": [
				{"offset": Vector2(-5.0, 0.0), "size": Vector2(16.0, 12.0)},
				{"offset": Vector2(1.0, 0.0), "size": Vector2(21.0, 15.0)},
				{"offset": Vector2(7.0, 1.0), "size": Vector2(14.0, 10.0)},
			],
		},
		{
			"name": "LongWispy", "scene": long_wispy_scene, "count": long_wispy_count,
			"scale": Vector2(0.88, 1.20),
			"shadow_lobes": [
				{"offset": Vector2(-8.0, 0.0), "size": Vector2(18.0, 7.0)},
				{"offset": Vector2(0.0, 0.0), "size": Vector2(23.0, 8.5)},
				{"offset": Vector2(9.0, 0.5), "size": Vector2(16.0, 6.5)},
			],
		},
		{
			"name": "MediumLayered", "scene": medium_layered_scene, "count": medium_layered_count,
			"scale": Vector2(0.85, 1.18),
			"shadow_lobes": [
				{"offset": Vector2(-3.0, 0.0), "size": Vector2(14.0, 10.0)},
				{"offset": Vector2(4.0, 1.0), "size": Vector2(12.0, 9.0)},
			],
		},
		{
			"name": "SmallPuff", "scene": small_puff_scene, "count": small_puff_count,
			"scale": Vector2(0.82, 1.25),
			"shadow_lobes": [
				{"offset": Vector2.ZERO, "size": Vector2(9.0, 7.0)},
			],
		},
	]


func _create_states(config: Dictionary, count: int, rng: RandomNumberGenerator) -> Array:
	var result: Array = []
	var opacity_value: Variant = minimum_cloud_opacity
	var resolved_minimum_opacity := clampf(
		float(opacity_value) if opacity_value != null else 0.78,
		0.0,
		1.0
	)
	var height_range := Vector2(
		minf(cloud_height_range.x, cloud_height_range.y),
		maxf(cloud_height_range.x, cloud_height_range.y)
	)
	var scale_range := config.get("scale", Vector2(0.9, 1.1)) as Vector2
	var core_count := clampi(roundi(float(count) * core_cloud_ratio), 0, count)
	for index in range(count):
		var cloud_xz := _random_cloud_xz(rng, index < core_count)
		result.append({
			"position": Vector3(
				cloud_xz.x,
				rng.randf_range(height_range.x, height_range.y),
				cloud_xz.y
			),
			"yaw": rng.randf_range(-PI, PI),
			"scale": rng.randf_range(scale_range.x, scale_range.y),
			"speed_scale": rng.randf_range(0.82, 1.18),
			"opacity": rng.randf_range(resolved_minimum_opacity, 1.0),
		})
	return result


func _random_cloud_xz(rng: RandomNumberGenerator, inside_core: bool) -> Vector2:
	var half_coverage := coverage_size * 0.5
	var core_size_value: Variant = core_map_size
	var resolved_core_size := core_size_value as Vector2 \
			if core_size_value is Vector2 else Vector2(256.0, 256.0)
	var half_core := Vector2(
		minf(resolved_core_size.x, coverage_size.x) * 0.5,
		minf(resolved_core_size.y, coverage_size.y) * 0.5
	)
	if inside_core:
		return Vector2(
			rng.randf_range(coverage_center.x - half_core.x, coverage_center.x + half_core.x),
			rng.randf_range(coverage_center.y - half_core.y, coverage_center.y + half_core.y)
		)
	for _attempt in range(24):
		var candidate := Vector2(
			rng.randf_range(coverage_center.x - half_coverage.x, coverage_center.x + half_coverage.x),
			rng.randf_range(coverage_center.y - half_coverage.y, coverage_center.y + half_coverage.y)
		)
		if absf(candidate.x - coverage_center.x) > half_core.x \
				or absf(candidate.y - coverage_center.y) > half_core.y:
			return candidate
	return coverage_center + Vector2(half_core.x + 1.0, half_core.y + 1.0)


func _create_cloud_renderers(variant_index: int, source_scene: PackedScene, count: int) -> Array:
	var result: Array = []
	if count <= 0:
		return result
	if source_scene == null:
		push_warning("CloudSystem3D: cloud scene %d is not assigned." % variant_index)
		return result
	var source_root := source_scene.instantiate() as Node3D
	if source_root == null:
		push_warning("CloudSystem3D: cloud scene %d must have a Node3D root." % variant_index)
		return result
	var mesh_sources: Array[MeshInstance3D] = []
	_collect_mesh_sources(source_root, mesh_sources)
	for mesh_index in range(mesh_sources.size()):
		var source := mesh_sources[mesh_index]
		if source.mesh == null:
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = source.mesh
		multi.instance_count = count
		var instance := MultiMeshInstance3D.new()
		instance.name = "Cloud_%d_%d" % [variant_index, mesh_index]
		instance.multimesh = multi
		instance.material_override = _cloud_material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		instance.visibility_range_end = cloud_visibility_distance
		instance.custom_aabb = _cloud_system_aabb()
		_generated_root.add_child(instance)
		result.append({
			"multi": multi,
			"source_transform": _relative_transform(source, source_root),
		})
	if mesh_sources.is_empty():
		push_warning("CloudSystem3D: cloud scene %d contains no MeshInstance3D." % variant_index)
	source_root.free()
	return result


func _create_cloud_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var color_value: Variant = cloud_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color_value as Color if color_value is Color else DEFAULT_CLOUD_COLOR
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = Color(1.0, 1.0, 1.0, 1.0)
	material.emission_energy_multiplier = 0.12
	material.roughness = 1.0
	return material


func _create_shadow_renderer(instance_count: int) -> void:
	if instance_count <= 0:
		return
	var material := StandardMaterial3D.new()
	var color_value: Variant = shadow_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color_value as Color if color_value is Color else DEFAULT_SHADOW_COLOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow_material = material
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.012
	mesh.radial_segments = 12
	mesh.rings = 1
	mesh.material = material
	_shadow_multimesh = MultiMesh.new()
	_shadow_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_shadow_multimesh.mesh = mesh
	_shadow_multimesh.instance_count = instance_count
	var instance := MultiMeshInstance3D.new()
	instance.name = "CloudShadows"
	instance.multimesh = _shadow_multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.visibility_range_end = shadow_visibility_distance
	instance.custom_aabb = AABB(
		Vector3(coverage_center.x - coverage_size.x * 0.5 - 24.0, shadow_ground_height - 0.1, coverage_center.y - coverage_size.y * 0.5 - 24.0),
		Vector3(coverage_size.x + 48.0, 0.2, coverage_size.y + 48.0)
	)
	_generated_root.add_child(instance)


func _update_multimeshes() -> void:
	var shadow_index := 0
	for variant_value: Variant in _variant_states.keys():
		var variant_index := int(variant_value)
		var states := _variant_states[variant_index] as Array
		var renderers := _variant_renderers.get(variant_index, []) as Array
		var lobes := _variant_shadow_lobes.get(variant_index, []) as Array
		for index in range(states.size()):
			var state := states[index] as Dictionary
			var cloud_transform := _cloud_transform(state)
			for renderer_value: Variant in renderers:
				var renderer := renderer_value as Dictionary
				var multi := renderer.get("multi") as MultiMesh
				if multi != null:
					multi.set_instance_transform(
						index,
						cloud_transform * (renderer.get("source_transform", Transform3D.IDENTITY) as Transform3D)
					)
					multi.set_instance_color(
						index,
						Color(1.0, 1.0, 1.0, float(state.get("opacity", 1.0)))
					)
			if _shadow_multimesh == null:
				continue
			for lobe_value: Variant in lobes:
				var lobe := lobe_value as Dictionary
				_shadow_multimesh.set_instance_transform(
					shadow_index,
					_shadow_transform(state, lobe)
				)
				shadow_index += 1


func _cloud_transform(state: Dictionary) -> Transform3D:
	var scale_value := float(state.get("scale", 1.0)) * cloud_scale_multiplier
	return Transform3D(
		Basis(Vector3.UP, float(state.get("yaw", 0.0))).scaled(Vector3.ONE * scale_value),
		state.get("position", Vector3.ZERO) as Vector3
	)


func _shadow_transform(state: Dictionary, lobe: Dictionary) -> Transform3D:
	var yaw := float(state.get("yaw", 0.0))
	var scale_value := float(state.get("scale", 1.0)) * cloud_scale_multiplier
	var cloud_position := state.get("position", Vector3.ZERO) as Vector3
	var offset := (lobe.get("offset", Vector2.ZERO) as Vector2).rotated(-yaw) * scale_value
	var size := (lobe.get("size", Vector2.ONE) as Vector2) * scale_value
	var sunlight_offset := _get_sunlight_shadow_offset(cloud_position.y)
	return Transform3D(
		Basis(Vector3.UP, yaw).scaled(Vector3(size.x * 0.5, 1.0, size.y * 0.5)),
		Vector3(
			cloud_position.x + offset.x + sunlight_offset.x,
			shadow_ground_height,
			cloud_position.z + offset.y + sunlight_offset.y
		)
	)


func _get_sunlight_shadow_offset(cloud_height: float) -> Vector2:
	if _sun_direction.y <= 0.08:
		return Vector2.ZERO
	var vertical_distance := maxf(0.0, cloud_height - shadow_ground_height)
	var offset := Vector2(-_sun_direction.x, -_sun_direction.z) \
			* vertical_distance / _sun_direction.y
	if offset.length() > 36.0:
		offset = offset.normalized() * 36.0
	return offset


func _apply_daylight_materials() -> void:
	if _cloud_material != null:
		var color_value: Variant = cloud_color
		var day_color := color_value as Color if color_value is Color else DEFAULT_CLOUD_COLOR
		var night_color := Color(0.30, 0.37, 0.48, day_color.a * 0.72)
		var weather_color := Color(0.075, 0.105, 0.17, 0.94)
		_cloud_material.albedo_color = night_color.lerp(day_color, _daylight_factor).lerp(
			weather_color, _rain_strength
		)
		_cloud_material.emission_energy_multiplier = lerpf(
			lerpf(0.025, 0.12, _daylight_factor), 0.008, _rain_strength
		)
	if _shadow_material != null:
		var shadow_value: Variant = shadow_color
		var next_shadow_color := shadow_value as Color \
				if shadow_value is Color else DEFAULT_SHADOW_COLOR
		next_shadow_color.a *= lerpf(
			smoothstep(0.12, 0.72, _daylight_factor), 1.0, _rain_strength
		)
		next_shadow_color = next_shadow_color.lerp(
			Color(0.025, 0.04, 0.075, 0.30), _rain_strength
		)
		_shadow_material.albedo_color = next_shadow_color


func _get_total_shadow_count() -> int:
	var total := 0
	for variant_value: Variant in _variant_states.keys():
		var variant_index := int(variant_value)
		total += (_variant_states[variant_index] as Array).size() \
				* (_variant_shadow_lobes.get(variant_index, []) as Array).size()
	return total


func _wrap_position(position: Vector3) -> Vector3:
	var half_size := coverage_size * 0.5
	var minimum := coverage_center - half_size
	var maximum := coverage_center + half_size
	if position.x > maximum.x:
		position.x -= coverage_size.x
	elif position.x < minimum.x:
		position.x += coverage_size.x
	if position.z > maximum.y:
		position.z -= coverage_size.y
	elif position.z < minimum.y:
		position.z += coverage_size.y
	return position


func _cloud_system_aabb() -> AABB:
	var minimum_height := minf(cloud_height_range.x, cloud_height_range.y) - 12.0
	var maximum_height := maxf(cloud_height_range.x, cloud_height_range.y) + 12.0
	return AABB(
		Vector3(coverage_center.x - coverage_size.x * 0.5 - 32.0, minimum_height, coverage_center.y - coverage_size.y * 0.5 - 32.0),
		Vector3(coverage_size.x + 64.0, maximum_height - minimum_height, coverage_size.y + 64.0)
	)


func _ensure_generated_root() -> void:
	_generated_root = get_node_or_null("GeneratedClouds") as Node3D
	if _generated_root == null:
		_generated_root = Node3D.new()
		_generated_root.name = "GeneratedClouds"
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
