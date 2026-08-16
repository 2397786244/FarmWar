extends Area3D
class_name NeutralCropGenerator

const FARM_GROUND_COLLISION_LAYER := 64
const EDITOR_VISUAL_META := &"farmwar_editor_visual_only"
const PLAYER_PREVIEW_SCENE_SCRIPT := "res://src/farmwar_runtime_map_editor.gd"
const DEFAULT_AREA_HEIGHT := 4.0
const GENERATION_CHUNK_SIZE := 16.0
const GENERATION_CHUNK_QUERY_RADIUS := 13.0
const MAX_PLANTS_PER_GENERATOR_PER_FRAME := 8
const MAX_CHUNKS_SCANNED_PER_FRAME := 4

@export var generator_id := ""
@export var crop_id := "wheat"
@export var area_size := Vector2(16.0, 16.0)
@export_range(1.0, 3600.0, 1.0) var respawn_interval_seconds := 120.0
@export_range(0.0, 3600.0, 1.0) var initial_spawn_delay := 0.0
@export var show_boundary := true
@export_color_no_alpha var boundary_color := Color(0.95, 0.85, 0.25, 1.0)

var _spawn_timer := 0.0
var _initial_spawn_pending := true
var _started := false
var _scan_requested := false
var _generation_active := false
var _generation_chunks: Array[Vector2i] = []
var _generation_chunk_index := 0
var _generation_chunk_tiles: Array = []
var _generation_tile_index := 0
var _generation_crop_id := ""
var _generation_rescan_requested := false
var _generation_planted_count := 0
var _generation_scanned_chunk_count := 0
var _initialization_source: Node
var _boundary_root: Node3D


func _ready() -> void:
	if generator_id.is_empty():
		generator_id = "neutral_crop_%d" % get_instance_id()
	add_to_group("neutral_crop_generators")
	_configure_area()
	_refresh_boundary()
	_initialization_source = _find_world_initializer()
	if _initialization_source != null:
		if bool(_initialization_source.get("is_map_initialized")):
			_start_after_map_initialization()
		elif not _initialization_source.is_connected("map_initialization_completed", _on_map_initialization_completed):
			_initialization_source.connect("map_initialization_completed", _on_map_initialization_completed)
	else:
		call_deferred("_start_after_map_initialization")


func _process(delta: float) -> void:
	if _is_runtime_editor_preview():
		return
	if not (GameAuthority.is_server_authority() or GameAuthority.is_local_authority()):
		return
	if not _started:
		return
	if _generation_active:
		_process_generation_job()
		return
	if _scan_requested:
		_scan_requested = false
		_start_generation_job()
		_process_generation_job()
		return
	if _initial_spawn_pending:
		_spawn_timer += delta
		if _spawn_timer < maxf(0.0, initial_spawn_delay) or not _farm_tiles_ready():
			return
		_spawn_timer = 0.0
		_initial_spawn_pending = false
		_start_generation_job()
		_process_generation_job()
		return
	_spawn_timer += delta
	if _spawn_timer < maxf(0.0, respawn_interval_seconds):
		return
	_spawn_timer = 0.0
	_start_generation_job()
	_process_generation_job()


func refresh_visuals() -> void:
	_configure_area()
	_refresh_boundary()


func refresh_after_world_restore() -> void:
	if _is_runtime_editor_preview() or not (GameAuthority.is_server_authority() or GameAuthority.is_local_authority()):
		return
	_started = true
	_initial_spawn_pending = false
	_spawn_timer = 0.0
	_request_scan()


func get_spawn_area_size() -> Vector2:
	return area_size


func _on_map_initialization_completed() -> void:
	_start_after_map_initialization()


func _start_after_map_initialization() -> void:
	if _started or not is_inside_tree():
		return
	_started = true
	_initial_spawn_pending = true
	_spawn_timer = 0.0
	_scan_requested = false


func _farm_tiles_ready() -> bool:
	var manager := get_node_or_null("/root/Farmlandmanager")
	if manager == null or not manager.has_method("get_all_plots"):
		return false
	var plots: Array = manager.call("get_all_plots")
	if plots.is_empty():
		return false
	if _initialization_source != null:
		for field_value in _initialization_source.find_children("*", "FarmFieldGenerator", true, false):
			if field_value is FarmFieldGenerator and (field_value as FarmFieldGenerator).is_generating:
				return false
	return true


func _find_world_initializer() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_signal("map_initialization_completed") and cursor.has_method("wait_until_initialized"):
			return cursor
		cursor = cursor.get_parent()
	return null


func _configure_area() -> void:
	collision_layer = 0
	collision_mask = FARM_GROUND_COLLISION_LAYER
	monitoring = true
	monitorable = false
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		add_child(collision_shape)
	var box := collision_shape.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		collision_shape.shape = box
	box.size = Vector3(maxf(0.1, area_size.x), DEFAULT_AREA_HEIGHT, maxf(0.1, area_size.y))
	if not body_shape_entered.is_connected(_on_body_shape_entered):
		body_shape_entered.connect(_on_body_shape_entered)


func _on_body_shape_entered(
	_body_rid: RID,
	body: Node3D,
	body_shape_index: int,
	_local_shape_index: int
) -> void:
	var tile := Farmlandmanager.resolve_farm_tile(body, body_shape_index)
	if tile != null:
		_request_scan()


func _scan_and_plant() -> void:
	if _generation_active:
		_generation_rescan_requested = true
		return
	_start_generation_job()


func is_generation_in_progress() -> bool:
	return _generation_active


func has_pending_generation_request() -> bool:
	return _scan_requested or _generation_rescan_requested


func get_generation_progress() -> Dictionary:
	return {
		"active": _generation_active,
		"pending_scan": has_pending_generation_request(),
		"chunk_count": _generation_chunks.size(),
		"scanned_chunk_count": _generation_scanned_chunk_count,
		"current_chunk_index": _generation_chunk_index,
		"current_chunk_tile_count": _generation_chunk_tiles.size(),
		"current_chunk_tile_index": _generation_tile_index,
		"planted_count": _generation_planted_count,
		"rescan_requested": _generation_rescan_requested,
	}


func _request_scan() -> void:
	if _generation_active:
		_generation_rescan_requested = true
	else:
		_scan_requested = true


func _start_generation_job() -> void:
	if _generation_active:
		_generation_rescan_requested = true
		return
	if crop_id.is_empty() or not IngredientCatalog.is_plantable(crop_id):
		return
	_generation_crop_id = crop_id
	_generation_chunks = _get_generation_chunks()
	_generation_chunk_index = 0
	_generation_chunk_tiles.clear()
	_generation_tile_index = 0
	_generation_planted_count = 0
	_generation_scanned_chunk_count = 0
	_generation_rescan_requested = false
	_generation_active = not _generation_chunks.is_empty()


func _process_generation_job() -> void:
	if not _generation_active:
		return
	var planted_this_frame := 0
	var chunks_scanned_this_frame := 0
	while _generation_active \
			and planted_this_frame < MAX_PLANTS_PER_GENERATOR_PER_FRAME \
			and chunks_scanned_this_frame < MAX_CHUNKS_SCANNED_PER_FRAME:
		if _generation_tile_index >= _generation_chunk_tiles.size():
			if _generation_chunk_index >= _generation_chunks.size():
				_finish_generation_job()
				return
			var chunk_coordinate := _generation_chunks[_generation_chunk_index]
			_generation_chunk_index += 1
			_generation_scanned_chunk_count += 1
			chunks_scanned_this_frame += 1
			_generation_chunk_tiles = _get_chunk_tiles(chunk_coordinate)
			_generation_tile_index = 0
			continue

		var tile_value: Variant = _generation_chunk_tiles[_generation_tile_index]
		if not tile_value is FarmTile:
			_generation_tile_index += 1
			continue
		var tile := tile_value as FarmTile
		if not is_instance_valid(tile):
			_generation_tile_index += 1
			continue
		# Keep the existing visibility recovery behavior for saved or otherwise
		# hidden crops encountered during a generator scan.
		tile.visible = true
		tile.ensure_crop_visuals_visible()
		if not tile.land_owner.is_empty() or not tile.is_empty():
			_generation_tile_index += 1
			continue
		# Leave the tile at the current index when the world budget is exhausted;
		# it will be retried on the next process frame.
		if not Farmlandmanager.try_consume_crop_generation_budget():
			return
		_generation_tile_index += 1
		if tile.plant_neutral(_generation_crop_id):
			planted_this_frame += 1
			_generation_planted_count += 1

	if _generation_chunk_index >= _generation_chunks.size() \
			and _generation_tile_index >= _generation_chunk_tiles.size():
		_finish_generation_job()


func _finish_generation_job() -> void:
	_generation_active = false
	_generation_chunks.clear()
	_generation_chunk_tiles.clear()
	_generation_chunk_index = 0
	_generation_tile_index = 0
	if _generation_rescan_requested:
		_generation_rescan_requested = false
		_scan_requested = true


func _get_generation_chunks() -> Array[Vector2i]:
	var half_width := maxf(0.05, area_size.x * 0.5)
	var half_depth := maxf(0.05, area_size.y * 0.5)
	var corners := [
		to_global(Vector3(-half_width, 0.0, -half_depth)),
		to_global(Vector3(half_width, 0.0, -half_depth)),
		to_global(Vector3(-half_width, 0.0, half_depth)),
		to_global(Vector3(half_width, 0.0, half_depth)),
	]
	var minimum_x := INF
	var maximum_x := -INF
	var minimum_z := INF
	var maximum_z := -INF
	for corner_value: Variant in corners:
		if not corner_value is Vector3:
			continue
		var corner := corner_value as Vector3
		minimum_x = minf(minimum_x, corner.x)
		maximum_x = maxf(maximum_x, corner.x)
		minimum_z = minf(minimum_z, corner.z)
		maximum_z = maxf(maximum_z, corner.z)
	var minimum_chunk := _world_chunk_for_position(Vector3(minimum_x, 0.0, minimum_z))
	var maximum_chunk := _world_chunk_for_position(Vector3(maximum_x, 0.0, maximum_z))
	var chunks: Array[Vector2i] = []
	for chunk_x in range(minimum_chunk.x, maximum_chunk.x + 1):
		for chunk_z in range(minimum_chunk.y, maximum_chunk.y + 1):
			chunks.append(Vector2i(chunk_x, chunk_z))
	return chunks


func _get_chunk_tiles(chunk_coordinate: Vector2i) -> Array:
	var chunk_center := Vector3(
		(float(chunk_coordinate.x) + 0.5) * GENERATION_CHUNK_SIZE,
		global_position.y,
		(float(chunk_coordinate.y) + 0.5) * GENERATION_CHUNK_SIZE
	)
	var candidates: Array = Farmlandmanager.get_plots_in_radius(
		chunk_center,
		GENERATION_CHUNK_QUERY_RADIUS
	)
	var result: Array = []
	for tile_value: Variant in candidates:
		if not tile_value is FarmTile:
			continue
		var tile := tile_value as FarmTile
		if not is_instance_valid(tile):
			continue
		if _world_chunk_for_position(tile.global_position) != chunk_coordinate:
			continue
		if not _contains_tile(tile):
			continue
		result.append(tile)
	return result


func _world_chunk_for_position(world_position: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_position.x / GENERATION_CHUNK_SIZE),
		floori(world_position.z / GENERATION_CHUNK_SIZE)
	)


func _exit_tree() -> void:
	_generation_active = false
	_scan_requested = false
	_generation_rescan_requested = false
	_generation_chunks.clear()
	_generation_chunk_tiles.clear()


func _contains_tile(tile: FarmTile) -> bool:
	var local_position := to_local(tile.global_position)
	return absf(local_position.x) <= maxf(0.05, area_size.x * 0.5) \
		and absf(local_position.z) <= maxf(0.05, area_size.y * 0.5) \
		and absf(local_position.y) <= DEFAULT_AREA_HEIGHT * 0.5 + 1.0


func _is_runtime_editor_preview() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var script := scene.get_script() as Script
	return script != null and script.resource_path == PLAYER_PREVIEW_SCENE_SCRIPT


func _refresh_boundary() -> void:
	if is_instance_valid(_boundary_root):
		_boundary_root.queue_free()
		_boundary_root = null
	if not show_boundary or not _is_runtime_editor_preview():
		return
	_boundary_root = Node3D.new()
	_boundary_root.name = "_EditorNeutralCropBoundary"
	_boundary_root.set_meta(EDITOR_VISUAL_META, true)
	add_child(_boundary_root)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color(boundary_color.r, boundary_color.g, boundary_color.b, 0.9)
	material.emission_enabled = true
	material.emission = boundary_color
	material.emission_energy_multiplier = 1.4
	var fill := MeshInstance3D.new()
	fill.name = "_EditorNeutralCropFill"
	fill.set_meta(EDITOR_VISUAL_META, true)
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(maxf(0.1, area_size.x), 0.02, maxf(0.1, area_size.y))
	var fill_material := StandardMaterial3D.new()
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_material.albedo_color = Color(boundary_color.r, boundary_color.g, boundary_color.b, 0.12)
	fill_material.no_depth_test = true
	fill_mesh.material = fill_material
	fill.mesh = fill_mesh
	fill.position.y = 0.01
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_boundary_root.add_child(fill)
	_add_boundary_line(Vector3(0.0, 0.03, -area_size.y * 0.5), Vector3(area_size.x, 0.035, 0.035), material)
	_add_boundary_line(Vector3(0.0, 0.03, area_size.y * 0.5), Vector3(area_size.x, 0.035, 0.035), material)
	_add_boundary_line(Vector3(-area_size.x * 0.5, 0.03, 0.0), Vector3(0.035, 0.035, area_size.y), material)
	_add_boundary_line(Vector3(area_size.x * 0.5, 0.03, 0.0), Vector3(0.035, 0.035, area_size.y), material)


func _add_boundary_line(line_position: Vector3, line_size: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.set_meta(EDITOR_VISUAL_META, true)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(maxf(0.035, line_size.x), maxf(0.035, line_size.y), maxf(0.035, line_size.z))
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = line_position
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_boundary_root.add_child(mesh_instance)
