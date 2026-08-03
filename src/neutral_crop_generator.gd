extends Area3D
class_name NeutralCropGenerator

const FARM_GROUND_COLLISION_LAYER := 64
const EDITOR_VISUAL_META := &"farmwar_editor_visual_only"
const PLAYER_PREVIEW_SCENE_SCRIPT := "res://src/farmwar_runtime_map_editor.gd"
const DEFAULT_AREA_HEIGHT := 4.0

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
	if _scan_requested:
		_scan_requested = false
		_scan_and_plant()
	_spawn_timer += delta
	var threshold := initial_spawn_delay if _initial_spawn_pending else respawn_interval_seconds
	if _spawn_timer < maxf(0.0, threshold):
		return
	_spawn_timer = 0.0
	_initial_spawn_pending = false
	_scan_and_plant()


func refresh_visuals() -> void:
	_configure_area()
	_refresh_boundary()


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
	if not _is_runtime_editor_preview() and initial_spawn_delay <= 0.0 \
		and (GameAuthority.is_server_authority() or GameAuthority.is_local_authority()):
		_initial_spawn_pending = false
		_scan_and_plant()


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
		_scan_requested = true


func _scan_and_plant() -> void:
	if crop_id.is_empty() or not IngredientCatalog.is_plantable(crop_id):
		return
	var tiles: Array = Farmlandmanager.get_all_plots()
	for tile_value: Variant in tiles:
		if not tile_value is FarmTile:
			continue
		var tile := tile_value as FarmTile
		if not is_instance_valid(tile) or not _contains_tile(tile):
			continue
		if not tile.land_owner.is_empty() or not tile.is_empty():
			continue
		tile.plant_neutral(crop_id)


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
